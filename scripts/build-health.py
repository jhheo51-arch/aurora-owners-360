"""v5 S-5 고객 건강 점수·CSAT (docs/design/v5-retention.md Q76).
Contact Health_Score__c·Health_Grade__c·Health_Basis__c는 CustomerHealthService가 채운다(위험 점수와 같은 저장).
기준값 Health_Rule__mdt(KR_Default), CSAT 1~5 유효성 규칙, VOC 화면 '④ 종결 만족도', Path 종결 안내 한 줄.
샘플: 종결 VOC 3건 CSAT(data/v5/case-csat.csv) — 정하늘 5·4, 오지민 2.
실행: python -X utf8 scripts/build-health.py  → 이어서 build-pages.py·build-permissions.py
"""
import csv
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent.parent
ROOT = BASE / "force-app" / "main" / "default"
DATA = BASE / "data" / "v5"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

# (API 이름, 라벨, 값, 정밀도, 소수 자릿수)
RULE = [
    ("Risk_Weight__c", "위험 점수 가중치", 0.4, 3, 2),
    ("Low_CSAT_Max__c", "낮은 CSAT 기준(이하)", 2, 1, 0),
    ("Low_CSAT_Penalty__c", "낮은 CSAT 감점", 15, 3, 0),
    ("Recall_Penalty__c", "리콜 미조치 감점", 10, 3, 0),
    ("Lemon_Penalty__c", "레몬법 주의 이상 감점", 10, 3, 0),
    ("Open_VOC_Penalty__c", "진행 중 VOC 1건당 감점", 5, 3, 0),
    ("Good_Min__c", "'좋음' 최소 점수", 80, 3, 0),
    ("Fair_Min__c", "'보통' 최소 점수(미만은 주의)", 60, 3, 0),
]
# 종결 VOC의 CSAT 샘플(VOC_Key__c 기준)
CSAT = [("VOC-A", 5), ("VOC-E", 4), ("VOC-D", 2)]


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc=""):
    d = f"    <description>{escape(desc)}</description>\n" if desc else ""
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n{d}    <label>{escape(label)}</label>\n"
            f"{body}</CustomField>\n")


# ===== Contact 필드 =====
write("objects/Contact/fields/Health_Score__c.field-meta.xml", field(
    "Health_Score__c", "고객 건강 점수",
    "    <precision>3</precision>\n    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n",
    "0~100, 높을수록 남을 가능성 큼(v5 Q76). 100에서 위험 점수·낮은 CSAT·리콜 미조치·레몬법·진행 중 VOC 감점. 위험 점수와 함께 재계산"))
grades = "".join(f"            <value>\n                <fullName>{g}</fullName>\n                <default>false</default>\n"
                 f"                <label>{g}</label>\n            </value>\n" for g in ["좋음", "보통", "주의"])
write("objects/Contact/fields/Health_Grade__c.field-meta.xml", field(
    "Health_Grade__c", "고객 건강 등급",
    "    <required>false</required>\n    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n"
    f"        <valueSetDefinition>\n            <sorted>false</sorted>\n{grades}        </valueSetDefinition>\n    </valueSet>\n",
    "Health_Rule__mdt 기준: 80 이상 좋음, 60~79 보통, 60 미만 주의"))
write("objects/Contact/fields/Health_Basis__c.field-meta.xml", field(
    "Health_Basis__c", "건강 점수 근거",
    "    <length>255</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n",
    "감점 항목 문장(예: 위험 80 → −32 · 리콜 미조치 −10)"))

# ===== 기준 커스텀 메타데이터 =====
write("objects/Health_Rule__mdt/Health_Rule__mdt.object-meta.xml", f"""<CustomObject {NS}>
    <description>고객 건강 점수 감점·등급 기준(v5 S-5). CustomerHealthService가 KR_Default를 읽는다.</description>
    <label>고객 건강 점수 기준</label>
    <pluralLabel>고객 건강 점수 기준</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
""")
for api, label, _, precision, scale in RULE:
    write(f"objects/Health_Rule__mdt/fields/{api}.field-meta.xml", f"""<CustomField {NS}>
    <fullName>{api}</fullName>
    <label>{escape(label)}</label>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <precision>{precision}</precision>
    <required>false</required>
    <scale>{scale}</scale>
    <type>Number</type>
    <unique>false</unique>
</CustomField>
""")
values = "".join(f"""    <values>
        <field>{api}</field>
        <value xsi:type="xsd:double">{value}</value>
    </values>
""" for api, _, value, _, _ in RULE)
write("customMetadata/Health_Rule.KR_Default.md-meta.xml",
      '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n'
      "    <label>기본 (위험×0.4, 80/60)</label>\n    <protected>false</protected>\n" + values + "</CustomMetadata>\n")

# ===== CSAT 1~5 =====
write("objects/Case/validationRules/Aurora_CSAT_Range.validationRule-meta.xml", f"""<ValidationRule {NS}>
    <fullName>Aurora_CSAT_Range</fullName>
    <active>true</active>
    <description>v5 S-5: 만족도(CSAT)는 비우거나 1~5. 고객 건강 점수에 반영된다.</description>
    <errorConditionFormula>AND(NOT(ISBLANK(CSAT__c)), OR(CSAT__c &lt; 1, CSAT__c &gt; 5))</errorConditionFormula>
    <errorDisplayField>CSAT__c</errorDisplayField>
    <errorMessage>만족도(CSAT)는 1~5점으로 입력하세요(모르면 비워 두세요).</errorMessage>
</ValidationRule>
""")
p = ROOT / "objects" / "Case" / "fields" / "CSAT__c.field-meta.xml"
t = p.read_text(encoding="utf-8")
t = t.replace("<description>AI 자가 해결 후 차주가 준 별점 1~5</description>",
              "<description>차주 만족도 1~5: AI 자가 해결 후 차주가 준 별점, 또는 VOC 종결 시 상담원이 통화로 받은 점수(v5). 고객 건강 점수에 반영</description>")
p.write_text(t, encoding="utf-8", newline="\n")

# ===== Path 종결 안내 =====
p = ROOT / "pathAssistants" / "Aurora_VOC_Status.pathAssistant-meta.xml"
t = p.read_text(encoding="utf-8")
line = "&lt;p&gt;(선택) 종결 통화에서 받은 만족도 1~5점을 처리 탭 &apos;④ 종결 만족도&apos;에 입력하면 고객 건강 점수에 반영됩니다.&lt;/p&gt;"
if "종결 만족도" not in t:
    start = t.index("<picklistValueName>종결</picklistValueName>")
    info_end = t.rindex("</info>", 0, start)
    t = t[:info_end] + line + t[info_end:]
    p.write_text(t, encoding="utf-8", newline="\n")
    print("path 종결 안내 + CSAT")

# ===== 샘플 CSAT =====
DATA.mkdir(parents=True, exist_ok=True)
with open(DATA / "case-csat.csv", "w", encoding="utf-8", newline="\n") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["VOC_Key__c", "CSAT__c"])
    w.writerows(CSAT)
print("wrote data/v5/case-csat.csv", len(CSAT), "rows")
