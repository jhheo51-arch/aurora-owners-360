"""오로라 샘플 데이터(차주·차량·VOC·보상)를 t0(실행 시각) 기준으로 만들어 sf data import tree 플랜을 생성한다.

사용법: python -X utf8 scripts/build-data.py [--target-org sesac]
  1) 상담 직원 ID 조회  2) 중복 확인(VIN·VOC 키가 이미 있으면 중단)  3) data/out/*.json + aurora-plan.json 생성
"""
import json
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ORG = sys.argv[sys.argv.index("--target-org") + 1] if "--target-org" in sys.argv else "sesac"
OUT = Path(__file__).resolve().parent.parent / "data" / "out"
KST = timezone(timedelta(hours=9))
T0 = datetime.now(KST).replace(second=0, microsecond=0)


def soql(q):
    res = subprocess.run(f'sf data query -q "{q}" --target-org {ORG} --json',
                         shell=True, capture_output=True, text=True, encoding="utf-8")
    return json.loads(res.stdout)["result"]["records"]


def at(hours):
    return (T0 + timedelta(hours=hours)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


staff = {r["Staff_Number__c"]: r["Id"] for r in soql("SELECT Id, Staff_Number__c FROM Care_Staff__c")}
MANAGER = staff["AUR-CS-101"]
ADV = {"미나미": staff["AUR-CS-102"], "진경은": staff["AUR-CS-103"],
       "김가영": staff["AUR-CS-104"], "이예빈": staff["AUR-CS-105"]}
COMP_REVIEWER = staff["AUR-CS-202"]
# 차량 모델은 data/vehicle-models.csv를 먼저 upsert해 둔다(차종·동력은 Vehicle_Before_Save Flow가 모델에서 맞춤)
models = {r["Model_Code__c"]: r["Id"] for r in soql("SELECT Id, Model_Code__c FROM Vehicle_Model__c")}
MODEL_CODE = {"오로라 E5": "AUR-E5-LR", "노스라이트": "AUR-NL-AWD", "시티로": "AUR-CT-STD", "오로라 GT": "AUR-GT-HEV"}

if soql("SELECT Id FROM Vehicle__c WHERE VIN__c LIKE 'KAUR%' LIMIT 1") or \
   soql("SELECT Id FROM Case WHERE VOC_Key__c LIKE 'VOC-%' LIMIT 1"):
    sys.exit("이미 적재된 샘플이 있습니다(VIN 또는 VOC 키). 중복을 막기 위해 중단합니다.")

CONTACTS = [  # 키, 이름, 등급, 이메일 아이디
    ("C1", "정하늘", "일반", "haneul"), ("C2", "윤하겸", "프리미엄", "hagyeom"),
    ("C3", "한서아", "플래티넘", "seoa"), ("C4", "오지민", "일반", "jimin"),
    ("C5", "강민준", "프리미엄", "minjun"), ("C6", "남궁린", "일반", "rin"),
    ("C7", "차도경", "프리미엄", "dokyung"), ("C8", "하윤재", "플래티넘", "yunjae"),
]
VEHICLES = [  # 키, VIN, 차주, 차종, 동력, 연식, 번호판, 출고일, 주행거리, 센터
    ("V1", "KAURE5EV0RA000101", "C1", "오로라 E5", "전기", "2024", "123가 4567", "2024-03-15", 18400, "서울 강남"),
    ("V2", "KAURNLSV0RA000202", "C2", "노스라이트", "전기", "2025", "45나 7788", "2025-06-02", 6200, "서울 성수"),
    ("V3", "KAURNLSV0PA000303", "C3", "노스라이트", "전기", "2023", "67다 1020", "2023-01-20", 41000, "경기 판교"),
    ("V4", "KAURCTEV0RA000404", "C4", "시티로", "전기", "2024", "89라 4512", "2024-11-08", 9800, "부산 해운대"),
    ("V5", "KAURGTHB0LA000505", "C5", "오로라 GT", "하이브리드", "2020", "12마 3333", "2020-05-10", 96500, "서울 강남"),
    ("V6", "KAURE5EV0SA000606", "C1", "오로라 E5", "전기", "2026", None, None, 0, "서울 강남"),
    ("V7", "KAURCTEV0SA000707", "C6", "시티로", "전기", "2025", "34바 5678", "2025-09-01", 3200, "경기 판교"),
    ("V8", "KAURGTHB0PA000808", "C7", "오로라 GT", "하이브리드", "2023", "56사 9012", "2023-04-10", 52000, "서울 성수"),
    ("V9", "KAURNLSV0PA000909", "C8", "노스라이트", "전기", "2023", "78아 3456", "2023-11-20", 38000, "부산 해운대"),
]
# 키, 차주, 차량, 유형, Priority, VOC 상태, 상담원, 기한(h), 첫 응답(h), 보증 구분, 도움 요청 사유, 접수경로, 제목, 내용
# 기한 None = Flow 자동 계산. CreatedDate는 API로 지정할 수 없어 기한을 "접수 시각 + SLA"로 직접 넣어 상황을 재현한다.
CASES = [
    ("VOC-A", "C1", "V1", "품질 결함", "Medium", "조치 검토", "미나미", 21, -2, None, None, "Phone",
     "고속 주행 시 실내 풍절음", "100km/h 이상에서 운전석 A필러 쪽 풍절음. 접수 t0-3h."),
    ("VOC-B", "C2", "V2", "커넥티드카 앱", "High", "접수", "미나미", -1, None, None, None, "Web",
     "원격 공조 실행 실패", "앱에서 원격 공조 실행 시 '차량 응답 없음'. 첫 응답 전 기한 경과."),
    ("VOC-C", "C3", "V3", "안전 결함", "High", "확인 중", "미나미", 1, -0.5, None, None, "Phone",
     "주행 중 브레이크 경고등 점등", "일반 보증 만료 차량. 안전 결함으로 품질·안전 대응(연태오) 공유 필요."),
    ("VOC-D", "C4", "V4", "정비 서비스", "Medium", "확인 중", "진경은", 22, -1, None,
     "서비스센터 예약 3주 대기 — 서비스센터 협력(국하율) 통한 긴급 예약 조율 필요", "Phone",
     "서비스센터 예약 3주 대기", "부산 해운대 센터 예약 불가. 상담원이 팀장 도움 요청."),
    ("VOC-E", "C1", "V6", "출고·인도", "Low", "종결", "김가영", 8, -38, None, None, "Web",
     "출고 일정 지연 문의", "계약 차량 출고 2주 지연. 포인트 보상 후 종결."),
    ("VOC-F", "C5", "V5", "품질 결함", "Low", "접수", "이예빈", None, None, None, None, "Phone",
     "에어컨 냄새", "보증 만료 차량. 응답 기한은 Flow 자동 계산(+48h)."),
    ("VOC-G", None, None, "커넥티드카 앱", "Medium", "접수", "미나미", None, None, None, None, "Phone",
     "차주 미확인 전화 접수", "발신자가 차량 정보를 말하지 않고 끊음. 차주·차량 보완 필요."),
    ("VOC-I", "C3", "V3", "충전·배터리", "Medium", "확인 중", "진경은", 20, -3, "고전압 배터리", None, "Web",
     "급속 충전 속도 저하", "급속 충전이 50kW 이하로 제한됨. 일반 보증은 만료, 배터리 보증 내."),
    ("VOC-J", "C6", "V7", "충전·배터리", "High", "확인 중", "김가영", 2, -1.5, "고전압 배터리", None, "Web",
     "완속 충전 불가", "가정용 완속 충전기 연결 시 충전 시작 안 됨. EV 기술 상담(도하람) 원격 진단 요청."),
    ("VOC-K", "C7", "V8", "품질 결함", "Medium", "조치 검토", "이예빈", -2, -25, None, None, "Phone",
     "하이브리드 시스템 경고 반복", "일반 보증 만료 6개월 후 동일 경고 3회. 보상 심사(봉유진) 보증 연장 승인."),
]
COMPS = [  # 키, VOC, 유형, 금액, 승인 상태, 승인자, 사유
    ("CMP-K1", "VOC-A", "무상수리", 120000, "승인", MANAGER, "도어 웨더스트립 교체(보증 내)"),
    ("CMP-K2", "VOC-C", "대차 지원", 450000, "요청", None, "안전 점검 기간 대차. 30만 원 이상 → 팀장 승인 필요"),
    ("CMP-K3", "VOC-E", "포인트 지급", 50000, "승인", MANAGER, "출고 지연 보상 포인트"),
    ("CMP-K4", "VOC-F", "무상수리", 80000, "반려", MANAGER, "보증 만료 차량 — 유상 수리 안내"),
    ("CMP-K5", "VOC-I", "충전 크레딧", 30000, "승인", MANAGER, "배터리 보증 내 충전 불편 보상"),
    ("CMP-K6", "VOC-K", "보증 연장", 600000, "승인", COMP_REVIEWER, "하이브리드 시스템 보증 1년 연장(환산 금액)"),
]

DECISION_NOTES = {
    "CMP-K1": "보증 내 부품 결함 확인, 무상수리 승인",
    "CMP-K3": "출고 지연 2주, 기준표에 따른 포인트 지급",
    "CMP-K4": "일반 보증 만료(2023-05) 차량으로 무상수리 대상 아님. 유상 수리 견적 안내",
    "CMP-K5": "배터리 보증 내 충전 성능 저하, 진단 기간 충전 크레딧 지급",
    "CMP-K6": "동일 경고 3회 반복, 품질 이력 고려해 하이브리드 시스템 보증 1년 연장",
}

contacts = [{"attributes": {"type": "Contact", "referenceId": f"Contact{k}"},
             "LastName": n, "Customer_Grade__c": g, "Email": f"{e}@aurora.example.com",
             "Phone": f"010-0000-{i:04d}", "Description": f"오로라 차주 MOB-{k}", "Contact_Role__c": "차주"}
            for i, (k, n, g, e) in enumerate(CONTACTS, start=1)]
vehicles = []
for k, vin, owner, model, pt, yr, plate, dd, km, sc in VEHICLES:
    v = {"attributes": {"type": "Vehicle__c", "referenceId": f"Vehicle{k}"}, "VIN__c": vin,
         "Owner_Contact__c": f"@Contact{owner}", "Model__c": model, "Powertrain__c": pt,
         "Model_Year__c": yr, "Mileage__c": km, "Service_Center__c": sc,
         "Vehicle_Model__c": models[MODEL_CODE[model]]}
    if plate:
        v["Plate_Number__c"] = plate
    if dd:
        v["Delivery_Date__c"] = dd
    vehicles.append(v)
cases = []
for key, c, v, cat, pri, st, adv, due, first, scope, reason, origin, subj, desc in CASES:
    r = {"attributes": {"type": "Case", "referenceId": key.replace("-", "")}, "VOC_Key__c": key,
         "Subject": subj, "Description": desc, "Origin": origin, "Priority": pri,
         "VOC_Category__c": cat, "VOC_Status__c": st, "Advisor__c": ADV[adv], "Manager_Employee__c": MANAGER,
         "Warranty_Scope__c": scope or "일반 부품"}
    if c:
        r["ContactId"] = f"@Contact{c}"
    if v:
        r["Vehicle__c"] = f"@Vehicle{v}"
    if due is not None:
        r["Response_Due_At__c"] = at(due)
    if first is not None:
        r["First_Response_At__c"] = at(first)
    if reason:
        r["Needs_Manager__c"] = True
        r["Assistance_Reason__c"] = reason
    cases.append(r)
comps = []
for key, voc, typ, amt, appr, approver, reason in COMPS:
    r = {"attributes": {"type": "Compensation__c", "referenceId": key.replace("-", "")},
         "Compensation_Key__c": key, "Case__c": f"@{voc.replace('-', '')}", "Compensation_Type__c": typ,
         "Amount__c": amt, "Approval_Status__c": appr, "Reason__c": reason}
    if approver:
        r["Approver__c"] = approver
    if appr in ("승인", "반려"):
        r["Approved_At__c"] = at(-1)
        r["Decision_Note__c"] = DECISION_NOTES[key]
    comps.append(r)

OUT.mkdir(parents=True, exist_ok=True)
plan = []
for name, sobj, recs, save, resolve in [
    ("contacts", "Contact", contacts, True, False), ("vehicles", "Vehicle__c", vehicles, True, True),
    ("cases", "Case", cases, True, True), ("compensations", "Compensation__c", comps, False, True)]:
    (OUT / f"{name}.json").write_text(json.dumps({"records": recs}, ensure_ascii=False, indent=2), encoding="utf-8")
    plan.append({"sobject": sobj, "saveRefs": save, "resolveRefs": resolve, "files": [f"{name}.json"]})
(OUT / "aurora-plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"t0 = {T0.isoformat()} / 차주 {len(contacts)} · 차량 {len(vehicles)} · VOC {len(cases)} · 보상 {len(comps)}")
