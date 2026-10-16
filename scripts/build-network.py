"""v5 S-1 서비스 네트워크 (docs/design/v5-retention.md Q66~Q69).
Account 고객 구분(오로라)에 '서비스센터'·'딜러' 값, 지역·하루 입고 용량 필드,
차량 `Preferred_Center__c`(담당 서비스센터)·`Selling_Dealer__c`(판매 딜러), 정비 이력 `Service_Center_Account__c`.
기존 선택 목록 `Service_Center__c`(차량·정비)는 남기고 값을 Lookup으로 옮긴다(Q68).
서비스센터 4·딜러 3은 가상. 실습 Account는 바꾸지 않는다(레코드 유형 안 씀, 함정 21).
실행: python -X utf8 scripts/build-network.py  (메타데이터·레이아웃 + data/v5/*.csv 생성)
"""
import ast
import csv
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent.parent
ROOT = BASE / "force-app" / "main" / "default"
DATA = BASE / "data" / "v5"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

# (키, 이름, 구분, 지역 = 기존 선택 목록 값, 하루 입고 용량, 전화)
NETWORK = [
    ("SC-GN", "오로라 강남 서비스센터", "서비스센터", "서울 강남", 6, "02-0000-2101"),
    ("SC-SS", "오로라 성수 서비스센터", "서비스센터", "서울 성수", 5, "02-0000-2102"),
    ("SC-PG", "오로라 판교 서비스센터", "서비스센터", "경기 판교", 4, "031-000-2103"),
    ("SC-HU", "오로라 해운대 서비스센터", "서비스센터", "부산 해운대", 3, "051-000-2104"),
    ("DL-GN", "오로라 강남 전시장", "딜러", "서울 강남", None, "02-0000-3101"),
    ("DL-PG", "오로라 판교 전시장", "딜러", "경기 판교", None, "031-000-3102"),
    ("DL-HU", "오로라 해운대 전시장", "딜러", "부산 해운대", None, "051-000-3103"),
]
CENTER_BY_REGION = {r: k for k, _, seg, r, _, _ in NETWORK if seg == "서비스센터"}
# 판매 딜러: 성수 지역 차주는 강남 전시장에서 구매한 것으로 둔다
DEALER_BY_REGION = {"서울 강남": "DL-GN", "서울 성수": "DL-GN", "경기 판교": "DL-PG", "부산 해운대": "DL-HU"}


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc):
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n    <description>{escape(desc)}</description>\n"
            f"    <label>{escape(label)}</label>\n{body}</CustomField>\n")


def account_lookup(name, label, segment, rel_label, rel_name, desc):
    return field(name, label,
                 "    <deleteConstraint>SetNull</deleteConstraint>\n"
                 f"    <lookupFilter>\n        <active>true</active>\n        <errorMessage>고객 구분(오로라)이 '{segment}'인 거래처만 고를 수 있습니다.</errorMessage>\n"
                 "        <filterItems>\n            <field>Account.Customer_Segment__c</field>\n            <operation>equals</operation>\n"
                 f"            <value>{segment}</value>\n        </filterItems>\n        <isOptional>false</isOptional>\n    </lookupFilter>\n"
                 f"    <referenceTo>Account</referenceTo>\n    <relationshipLabel>{rel_label}</relationshipLabel>\n"
                 f"    <relationshipName>{rel_name}</relationshipName>\n    <required>false</required>\n    <type>Lookup</type>\n",
                 desc)


# ===== Account =====
seg = ROOT / "objects/Account/fields/Customer_Segment__c.field-meta.xml"
xml = seg.read_text(encoding="utf-8")
for v in ["서비스센터", "딜러"]:
    if f"<fullName>{v}</fullName>" not in xml:
        xml = xml.replace("        </valueSetDefinition>",
                          f"            <value>\n                <fullName>{v}</fullName>\n                <default>false</default>\n"
                          f"                <label>{v}</label>\n            </value>\n        </valueSetDefinition>", 1)
        print("Customer_Segment__c +" + v)
seg.write_text(xml, encoding="utf-8", newline="\n")
write("objects/Account/fields/Region__c.field-meta.xml", field(
    "Region__c", "지역(오로라)",
    "    <length>40</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n",
    "서비스센터·딜러 지역(예: 서울 강남). 기존 서비스센터 선택 목록 값과 같다"))
write("objects/Account/fields/Daily_Capacity__c.field-meta.xml", field(
    "Daily_Capacity__c", "하루 입고 용량(대)",
    "    <precision>4</precision>\n    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n",
    "서비스센터가 동시에 정비할 수 있는 차량 수. 진행 중 정비 수와 비교해 혼잡도를 계산한다(v5 Q69)"))

# ===== Vehicle__c · Service_Visit__c =====
write("objects/Vehicle__c/fields/Preferred_Center__c.field-meta.xml", account_lookup(
    "Preferred_Center__c", "담당 서비스센터", "서비스센터", "담당 차량", "Preferred_Vehicles",
    "차량을 관리하는 서비스센터(Account). 기존 선택 목록 '서비스센터'를 대체(v5 Q68)"))
write("objects/Vehicle__c/fields/Selling_Dealer__c.field-meta.xml", account_lookup(
    "Selling_Dealer__c", "판매 딜러", "딜러", "판매 차량", "Sold_Vehicles",
    "차량을 판매한 딜러(Account). 재구매 상담 배정 기준"))
write("objects/Service_Visit__c/fields/Service_Center_Account__c.field-meta.xml", account_lookup(
    "Service_Center_Account__c", "서비스센터(거래처)", "서비스센터", "정비 이력", "Center_Visits",
    "정비를 받은 서비스센터(Account). 기존 선택 목록 '서비스센터'를 대체(v5 Q68)"))


# ===== 레이아웃: 선택 목록 바로 뒤에 Lookup =====
def add_after(layout_name, anchor_field, new_fields):
    p = ROOT / "layouts" / layout_name
    t = p.read_text(encoding="utf-8")
    anchor = f"                <field>{anchor_field}</field>\n            </layoutItems>\n"
    assert anchor in t, layout_name
    for f in reversed(new_fields):
        if f"<field>{f}</field>" in t:
            continue
        t = t.replace(anchor, anchor + "            <layoutItems>\n                <behavior>Edit</behavior>\n"
                      f"                <field>{f}</field>\n            </layoutItems>\n", 1)
        print("layout", layout_name, "+", f)
    p.write_text(t, encoding="utf-8", newline="\n")


add_after("Vehicle__c-고객 차량 레이아웃.layout-meta.xml", "Service_Center__c", ["Preferred_Center__c", "Selling_Dealer__c"])
add_after("Service_Visit__c-정비 이력 레이아웃.layout-meta.xml", "Service_Center__c", ["Service_Center_Account__c"])

# ===== 데이터 CSV =====
DATA.mkdir(parents=True, exist_ok=True)


def write_csv(name, header, rows):
    with open(DATA / name, "w", encoding="utf-8", newline="\n") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print("wrote data/v5/" + name, len(rows), "rows")


write_csv("network.csv", ["Aurora_Key__c", "Name", "Customer_Segment__c", "Region__c", "Daily_Capacity__c", "Phone", "Description"],
          [(k, n, s, r, "" if c is None else c, ph, f"오로라모터스 {r} {s}(가상)") for k, n, s, r, c, ph in NETWORK])

# 차량 원본(build-data.py VEHICLES)의 서비스센터 선택 목록 값 → Lookup
src = (BASE / "scripts" / "build-data.py").read_text(encoding="utf-8")
tree = ast.parse(src)
VEHICLES = next(ast.literal_eval(n.value) for n in tree.body
                if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", None) == "VEHICLES")
write_csv("vehicles-network.csv", ["VIN__c", "Preferred_Center__r.Aurora_Key__c", "Selling_Dealer__r.Aurora_Key__c"],
          [(vin, CENTER_BY_REGION[sc], DEALER_BY_REGION[sc]) for _, vin, _, _, _, _, _, _, _, sc in VEHICLES])
with open(BASE / "data" / "v3" / "service-visits.csv", encoding="utf-8") as f:
    visits = [(r["Visit_Key__c"], CENTER_BY_REGION[r["Service_Center__c"]]) for r in csv.DictReader(f)]
write_csv("visits-network.csv", ["Visit_Key__c", "Service_Center_Account__r.Aurora_Key__c"], visits)
