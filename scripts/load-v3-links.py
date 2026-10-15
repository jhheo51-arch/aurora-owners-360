"""v3 연결 데이터 적재: 소유 관계 9건, 가구·법인 계정 2건, 기존 VOC 고장 유형·부품 연결.
선행: build-data.py 샘플 + data/v3/*.csv(부품·위키·정비) 적재. 사용: python -X utf8 scripts/load-v3-links.py [--target-org sesac]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ORG = sys.argv[sys.argv.index("--target-org") + 1] if "--target-org" in sys.argv else "sesac"


def sf(cmd):
    r = subprocess.run(f"sf {cmd} --target-org {ORG} --json", shell=True, capture_output=True, text=True, encoding="utf-8")
    if not r.stdout.strip():
        raise SystemExit(f"sf 실패: {cmd}\n{r.stderr}")
    return json.loads(r.stdout)


def soql(q):
    return sf(f'data query -q "{q}"')["result"]["records"]


def bulk(op, sobject, header, rows, ext=None):
    tmp = Path(tempfile.mkdtemp()) / f"{sobject}.csv"
    tmp.write_text("\n".join([header] + rows), encoding="utf-8", newline="\n")
    extra = f"-i {ext}" if ext else ""
    command = "import" if op == "insert" else op
    r = sf(f'data {command} bulk -s {sobject} -f "{tmp}" {extra} --line-ending LF --wait 10')
    print(f"{op} {sobject}: status {r['status']} {r.get('message', '')}")


# 1) 가구·법인 계정 (Q36 B안: 레코드 유형 대신 고객 구분 필드)
if not soql("SELECT Id FROM Account WHERE Customer_Segment__c != null LIMIT 1"):
    sf('data create record -s Account -v "Name=\'정하늘 가구\' Customer_Segment__c=\'가구\'"')
    sf('data create record -s Account -v "Name=\'그린모빌리티\' Customer_Segment__c=\'법인 Fleet\'"')
acct = {a["Name"]: a["Id"] for a in soql("SELECT Id, Name FROM Account WHERE Customer_Segment__c != null")}
contacts = {c["LastName"]: c["Id"] for c in soql("SELECT Id, LastName FROM Contact WHERE Email LIKE '%aurora.example.com'")}
bulk("update", "Contact", "Id,AccountId", [f"{contacts['정하늘']},{acct['정하늘 가구']}", f"{contacts['차도경']},{acct['그린모빌리티']}"])

# 2) 현재 소유자 관계 (없을 때만) — 차주 Lookup은 트리거가 맞춘다
if not soql("SELECT Id FROM Vehicle_Party__c LIMIT 1"):
    rows = []
    for v in soql("SELECT Id, Owner_Contact__c, Owner_Contact__r.LastName, Delivery_Date__c, CreatedDate FROM Vehicle__c WHERE Owner_Contact__c != null"):
        start = v["Delivery_Date__c"] or v["CreatedDate"][:10]
        account = acct["그린모빌리티"] if v["Owner_Contact__r"]["LastName"] == "차도경" else ""
        rows.append(f"{v['Id']},{v['Owner_Contact__c']},{account},소유자,{start}")
    bulk("insert", "Vehicle_Party__c", "Vehicle__c,Contact__c,Account__c,Role__c,Start_Date__c", rows)

# 3) 기존 VOC 고장 유형·해결 정보 (종결 건은 Q40 규칙 대비)
wiki = {w["Wiki_Key__c"]: w["Id"] for w in soql("SELECT Id, Wiki_Key__c FROM Failure_Mode__c")}
case = {c["VOC_Key__c"]: c["Id"] for c in soql("SELECT Id, VOC_Key__c FROM Case WHERE VOC_Key__c != null")}
updates = [
    (case["VOC-A"], wiki["FM-005"], "", "도어 웨더스트립 들뜸", "웨더스트립 교체(보증 내 무상)", "부품 교체"),
    (case["VOC-B"], wiki["FM-001"], "", "", "", ""),
    (case["VOC-C"], wiki["FM-004"], "", "", "", ""),
    (case["VOC-D"], "", "서비스센터 예약 지연", "부산 해운대 센터 예약 포화", "서비스센터 협력으로 긴급 예약 + 대차", "보상 처리"),
    (case["VOC-E"], "", "출고 일정 지연", "생산 일정 변경", "출고 일정 안내 + 포인트 보상", "보상 처리"),
    (case["VOC-F"], wiki["FM-006"], "", "", "", ""),
    (case["VOC-I"], wiki["FM-002"], "", "", "", ""),
    (case["VOC-J"], wiki["FM-003"], "", "", "", ""),
    (case["VOC-K"], wiki["FM-007"], "", "", "", ""),
]
bulk("update", "Case", "Id,Failure_Mode__c,Proposed_Failure_Mode__c,Root_Cause__c,Resolution__c,Resolution_Method__c",
     [",".join(u) for u in updates])

# 4) VOC-부품 연결 (없을 때만)
if not soql("SELECT Id FROM Case_Part__c LIMIT 1"):
    part = {p["Part_Number__c"]: p["Id"] for p in soql("SELECT Id, Part_Number__c FROM Part__c")}
    bulk("insert", "Case_Part__c", "Case__c,Part__c,Role__c", [
        f"{case['VOC-A']},{part['P-BDY-001']},교체",
        f"{case['VOC-C']},{part['P-BRK-002']},의심",
        f"{case['VOC-I']},{part['P-BAT-003']},점검",
        f"{case['VOC-J']},{part['P-BAT-002']},의심",
        f"{case['VOC-B']},{part['P-ELC-001']},점검",
    ])
