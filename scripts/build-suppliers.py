"""v4.4 P-1 부품 공급사·담당자 (docs/design/v4.4-feedback.md F3).
Account·Contact를 재사용한다: Account 고객 구분(오로라)에 '공급사' 값, Contact '연락처 구분'(차주/공급사 담당자).
부품(Part__c)에 공급사·담당자·공급사 품번, VOC 부품(Case_Part__c)에 공급사·담당자 표시용 수식.
공급사 6곳·담당자 6명은 가상(사용자 확정 2026-10-15), 담당자 이메일은 @supplier.example.com
→ '오로라 차주' 리스트 뷰(@aurora.example.com)에 섞이지 않는다. 실습 Account·연락처는 바꾸지 않는다.
실행: python -X utf8 scripts/build-suppliers.py  (메타데이터 + data/v4.4/*.csv 생성)
"""
import csv
import re
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent.parent
ROOT = BASE / "force-app" / "main" / "default"
DATA = BASE / "data" / "v4.4"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

# (키, 공급사, 계통, 담당자, 직함, 이메일 아이디, 전화)
SUPPLIERS = [
    ("SUP-BAT", "오로라배터리솔루션", "배터리", "박진우", "품질 담당 책임", "jinwoo.park", "02-0000-1101"),
    ("SUP-DRV", "다온드라이브", "구동", "이도윤", "품질 담당 선임", "doyun.lee", "02-0000-1102"),
    ("SUP-BRK", "한빛브레이크시스템", "제동", "최수아", "품질 담당 책임", "sua.choi", "02-0000-1103"),
    ("SUP-HVAC", "세온공조", "공조", "문하린", "기술 영업 매니저", "harin.moon", "02-0000-1104"),
    ("SUP-ELC", "누리전장", "전장", "정태민", "품질 담당 선임", "taemin.jung", "02-0000-1105"),
    ("SUP-BDY", "가람차체", "차체", "한지호", "품질 담당 매니저", "jiho.han", "02-0000-1106"),
]


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc):
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n    <description>{escape(desc)}</description>\n"
            f"    <label>{escape(label)}</label>\n{body}</CustomField>\n")


def picklist(values):
    vals = "".join(f"            <value>\n                <fullName>{v}</fullName>\n                <default>false</default>\n"
                   f"                <label>{v}</label>\n            </value>\n" for v in values)
    return ("    <required>false</required>\n    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n"
            f"        <valueSetDefinition>\n            <sorted>false</sorted>\n{vals}        </valueSetDefinition>\n    </valueSet>\n")


EXT_KEY = ("    <caseSensitive>false</caseSensitive>\n    <externalId>true</externalId>\n    <length>40</length>\n"
           "    <required>false</required>\n    <type>Text</type>\n    <unique>true</unique>\n")

# ===== Account =====
seg = ROOT / "objects/Account/fields/Customer_Segment__c.field-meta.xml"
xml = seg.read_text(encoding="utf-8")
if "<fullName>공급사</fullName>" not in xml:
    xml = xml.replace("        </valueSetDefinition>",
                      "            <value>\n                <fullName>공급사</fullName>\n                <default>false</default>\n"
                      "                <label>공급사</label>\n            </value>\n        </valueSetDefinition>", 1)
    seg.write_text(xml, encoding="utf-8", newline="\n")
    print("updated objects/Account/fields/Customer_Segment__c.field-meta.xml (+공급사)")
write("objects/Account/fields/Aurora_Key__c.field-meta.xml", field(
    "Aurora_Key__c", "오로라 식별키", EXT_KEY, "오로라 샘플 데이터 적재용 외부 ID(예: SUP-BAT). 실습 Account는 비어 있음"))

# ===== Contact =====
write("objects/Contact/fields/Contact_Role__c.field-meta.xml", field(
    "Contact_Role__c", "연락처 구분(오로라)", picklist(["차주", "공급사 담당자"]),
    "오로라 연락처 구분. 공급사 담당자는 공급사 Account 소속, 이메일 @supplier.example.com (v4.4 F3)"))
write("objects/Contact/fields/Aurora_Key__c.field-meta.xml", field(
    "Aurora_Key__c", "오로라 식별키", EXT_KEY, "오로라 샘플 데이터 적재용 외부 ID(예: SUP-BAT-C1)"))

# ===== Part__c =====
write("objects/Part__c/fields/Supplier__c.field-meta.xml", field(
    "Supplier__c", "공급사",
    "    <deleteConstraint>SetNull</deleteConstraint>\n"
    "    <lookupFilter>\n        <active>true</active>\n        <errorMessage>고객 구분(오로라)이 '공급사'인 거래처만 고를 수 있습니다.</errorMessage>\n"
    "        <filterItems>\n            <field>Account.Customer_Segment__c</field>\n            <operation>equals</operation>\n"
    "            <value>공급사</value>\n        </filterItems>\n        <isOptional>false</isOptional>\n    </lookupFilter>\n"
    "    <referenceTo>Account</referenceTo>\n    <relationshipLabel>공급 부품</relationshipLabel>\n"
    "    <relationshipName>Supplied_Parts</relationshipName>\n    <required>false</required>\n    <type>Lookup</type>\n",
    "이 부품을 공급하는 회사(Account, 고객 구분 = 공급사)"))
write("objects/Part__c/fields/Supplier_Contact__c.field-meta.xml", field(
    "Supplier_Contact__c", "공급사 담당자",
    "    <deleteConstraint>SetNull</deleteConstraint>\n"
    "    <lookupFilter>\n        <active>true</active>\n        <errorMessage>선택한 공급사 소속 담당자만 고를 수 있습니다.</errorMessage>\n"
    "        <filterItems>\n            <field>Contact.AccountId</field>\n            <operation>equals</operation>\n"
    "            <valueField>$Source.Supplier__c</valueField>\n        </filterItems>\n        <isOptional>false</isOptional>\n    </lookupFilter>\n"
    "    <referenceTo>Contact</referenceTo>\n    <relationshipLabel>담당 부품</relationshipLabel>\n"
    "    <relationshipName>Managed_Parts</relationshipName>\n    <required>false</required>\n    <type>Lookup</type>\n",
    "공급사 품질 담당자(Contact, 그 공급사 소속)"))
write("objects/Part__c/fields/Supplier_Part_No__c.field-meta.xml", field(
    "Supplier_Part_No__c", "공급사 품번",
    "    <length>40</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n",
    "공급사가 쓰는 품번(가상)"))

# ===== Case_Part__c: VOC 부품 화면에 공급사·담당자 =====
for api, label, formula in [("Supplier_Name__c", "공급사", "Part__r.Supplier__r.Name"),
                            ("Supplier_Contact_Name__c", "공급사 담당자", "Part__r.Supplier_Contact__r.LastName")]:
    write(f"objects/Case_Part__c/fields/{api}.field-meta.xml", field(
        api, label,
        f"    <formula>{formula}</formula>\n    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>\n"
        "    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n",
        "부품의 공급사·담당자(표시용 수식)"))

# ===== 데이터 CSV =====
DATA.mkdir(parents=True, exist_ok=True)


def write_csv(name, header, rows):
    with open(DATA / name, "w", encoding="utf-8", newline="\n") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print("wrote data/v4.4/" + name, len(rows), "rows")


write_csv("suppliers.csv", ["Aurora_Key__c", "Name", "Customer_Segment__c", "Phone", "Description"],
          [(k, n, "공급사", ph, f"오로라모터스 {sysname} 계통 부품 공급사(가상)") for k, n, sysname, _, _, _, ph in SUPPLIERS])
write_csv("supplier-contacts.csv", ["Aurora_Key__c", "LastName", "Account.Aurora_Key__c", "Contact_Role__c", "Title", "Email", "Phone"],
          [(k + "-C1", person, k, "공급사 담당자", title, f"{mail}@supplier.example.com", ph)
           for k, _, _, person, title, mail, ph in SUPPLIERS])

by_system = {s[2]: s for s in SUPPLIERS}
rows = []
with open(BASE / "data" / "v3" / "parts.csv", encoding="utf-8") as f:
    for p in csv.DictReader(f):
        s = by_system[p["System__c"]]
        rows.append((p["Part_Number__c"], s[0], s[0] + "-C1", s[0].replace("SUP-", "") + "-" + re.sub(r"^P-[A-Z]+-", "", p["Part_Number__c"]) + "K"))
write_csv("parts-suppliers.csv", ["Part_Number__c", "Supplier__r.Aurora_Key__c", "Supplier_Contact__r.Aurora_Key__c", "Supplier_Part_No__c"], rows)
