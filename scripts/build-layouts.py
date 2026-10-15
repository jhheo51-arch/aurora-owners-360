"""v3 오브젝트 레이아웃·검색 열·목록 뷰 보완 (2026-10-15).
메타데이터로 만든 오브젝트는 레이아웃 필드가 자동 배치되지 않아(CLAUDE.md 함정 2) 이름·조회 필드만 보이던 문제를 고친다.
- 레이아웃 6개: 정비 이력·차량 보증·부품·고장 위키·VOC 부품·차량-사람 관계
- 검색 레이아웃 열(탭의 '최근 조회 항목' 목록에 쓰임): 8개 오브젝트
- 목록 뷰: 정비 이력 '하자 수리'
- 고장 위키에는 '이 고장으로 접수된 VOC와 조치' 관련 목록(해결 방식·원인·해결 방법)
주의: build-recall.py를 다시 돌리면 Recall_Alert__c 검색 열이 비워지므로 그 뒤에 이 스크립트를 다시 실행한다.
실행: python -X utf8 scripts/build-layouts.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "force-app" / "main" / "default"
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

# 섹션: (라벨, 왼쪽 열, 오른쪽 열). 오른쪽이 None이면 1열 섹션
LAYOUTS = {
    "Service_Visit__c": ("정비 이력 레이아웃", [
        ("기본 정보", ["Name", "Vehicle__c", "Case__c", "Visit_Type__c"], ["Service_Center__c", "Check_In_Date__c", "Completed_Date__c", "Repair_Days__c"]),
        ("하자·부품", ["Defect_System__c", "Main_Part__c", "Mileage__c"], ["Warranty_Applied__c", "Cost__c", "Battery_SOH__c"]),
        ("증상", ["Symptom__c"], None),
        ("시스템 정보", ["Visit_Key__c", "CreatedById"], ["LastModifiedById"]),
    ], []),
    "Vehicle_Warranty__c": ("차량 보증 레이아웃", [
        ("보증 정보", ["Name", "Vehicle__c", "Warranty_Type__c", "Status__c"], ["Start_Date__c", "End_Date__c", "Mileage_Limit_Km__c"]),
        ("시스템 정보", ["CreatedById"], ["LastModifiedById"]),
    ], [
        ("Case.Applied_Warranty__c", ["CASES.CASE_NUMBER", "CASES.SUBJECT", "VOC_Category__c", "VOC_Status__c", "Warranty_Scope__c"], None),
    ]),
    "Part__c": ("부품 레이아웃", [
        ("부품 정보", ["Name", "Part_Number__c", "System__c", "Location__c"], ["Defect_Grade__c", "Warranty_Type__c", "Applicable_Models__c", "Mesh_Id__c"]),
        ("공급사 (v4.4)", ["Supplier__c", "Supplier_Part_No__c"], ["Supplier_Contact__c"]),
        ("시스템 정보", ["CreatedById"], ["LastModifiedById"]),
    ], [
        ("Case_Part__c.Part__c", ["NAME", "Case__c", "Role__c"], None),
        ("Service_Visit__c.Main_Part__c", ["NAME", "Vehicle__c", "Check_In_Date__c", "Visit_Type__c", "Defect_System__c"], ("Check_In_Date__c", "Desc")),
        ("Failure_Mode__c.Primary_Part__c", ["NAME", "System__c", "Severity__c", "Status__c"], None),
    ]),
    "Failure_Mode__c": ("고장 위키 레이아웃", [
        ("위키 정보", ["Name", "Status__c", "System__c", "Severity__c"], ["Primary_Part__c", "Applicable_Models__c", "Self_Solvable__c", "Version__c"]),
        ("증상", ["Symptom__c"], None),
        ("원인", ["Cause__c"], None),
        ("진단 절차", ["Diagnosis__c"], None),
        ("해결 단계", ["Resolution_Steps__c"], None),
        ("조치 결과 집계", ["Success_Count__c"], ["Failure_Count__c"]),
        ("시스템 정보", ["Wiki_Key__c", "CreatedById"], ["LastModifiedById"]),
    ], [
        # 이 고장 유형이 연결된 VOC = 실제로 이루어진 조치 내역
        ("Case.Failure_Mode__c", ["CASES.CASE_NUMBER", "CASES.SUBJECT", "Vehicle__c", "VOC_Status__c",
                                  "Resolution_Method__c", "Root_Cause__c", "Resolution__c"], ("CASES.CASE_NUMBER", "Desc")),
    ]),
    "Case_Part__c": ("VOC 부품 레이아웃", [
        ("VOC 부품", ["Name", "Case__c"], ["Part__c", "Role__c"]),
        ("공급사 (v4.4)", ["Supplier_Name__c"], ["Supplier_Contact_Name__c"]),
        ("시스템 정보", ["CreatedById"], ["LastModifiedById"]),
    ], []),
    "Vehicle_Party__c": ("차량-사람 관계 레이아웃", [
        ("관계 정보", ["Name", "Vehicle__c", "Contact__c", "Account__c"], ["Role__c", "Start_Date__c", "End_Date__c", "Is_Current__c"]),
        ("시스템 정보", ["CreatedById"], ["LastModifiedById"]),
    ], []),
}

# 검색 레이아웃 열(이름 다음에 붙는 열)
SEARCH = {
    "Service_Visit__c": ["Vehicle__c", "Check_In_Date__c", "Visit_Type__c", "Defect_System__c", "Main_Part__c"],
    "Vehicle_Warranty__c": ["Vehicle__c", "Warranty_Type__c", "Status__c", "End_Date__c"],
    "Part__c": ["Part_Number__c", "System__c", "Defect_Grade__c", "Location__c", "Supplier__c", "Supplier_Contact__c"],
    "Failure_Mode__c": ["System__c", "Status__c", "Severity__c", "Primary_Part__c", "Success_Count__c"],
    "Case_Part__c": ["Case__c", "Part__c", "Role__c", "Supplier_Name__c"],
    "Vehicle_Party__c": ["Vehicle__c", "Contact__c", "Role__c", "Is_Current__c"],
    "Vehicle_Model__c": ["Model_Line__c", "Powertrain__c", "Trim__c", "Base_Price__c"],
    "Recall_Alert__c": ["Status__c", "Model_Line__c", "System__c", "VOC_Count__c", "Assigned_Staff__c"],
}

SYSTEM_FIELDS = {"CreatedById", "LastModifiedById"}


def field_info(obj, api):
    """(behavior) — 이름이 자동 번호면 읽기 전용, 수식·롤업은 읽기 전용, Master-Detail·필수 필드는 Required."""
    if api in SYSTEM_FIELDS:
        return "Readonly"
    if api == "Name":
        meta = (ROOT / "objects" / obj / f"{obj}.object-meta.xml").read_text(encoding="utf-8")
        name_type = re.search(r"<nameField>.*?<type>([^<]+)</type>", meta, re.S).group(1)
        return "Readonly" if name_type == "AutoNumber" else "Required"
    xml = (ROOT / "objects" / obj / "fields" / f"{api}.field-meta.xml").read_text(encoding="utf-8")
    if "<formula>" in xml or "<type>Summary</type>" in xml:
        return "Readonly"
    if "<type>MasterDetail</type>" in xml or "<required>true</required>" in xml:
        return "Required"
    return "Edit"


def column(obj, fields):
    items = "".join(
        f"            <layoutItems>\n                <behavior>{field_info(obj, f)}</behavior>\n"
        f"                <field>{f}</field>\n            </layoutItems>\n" for f in fields)
    return f"        <layoutColumns>\n{items}        </layoutColumns>\n"


def layout_xml(obj, sections, related):
    out = [f'<?xml version="1.0" encoding="UTF-8"?>\n<Layout {NS}>\n']
    for label, left, right in sections:
        style = "TwoColumnsTopToBottom" if right is not None else "OneColumn"
        out.append("    <layoutSections>\n        <customLabel>true</customLabel>\n"
                   "        <detailHeading>true</detailHeading>\n        <editHeading>true</editHeading>\n"
                   f"        <label>{label}</label>\n" + column(obj, left)
                   + (column(obj, right) if right is not None else "")
                   + f"        <style>{style}</style>\n    </layoutSections>\n")
    for rel, cols, sort in related:
        out.append("    <relatedLists>\n" + "".join(f"        <fields>{c}</fields>\n" for c in cols)
                   + f"        <relatedList>{rel}</relatedList>\n"
                   + (f"        <sortField>{sort[0]}</sortField>\n        <sortOrder>{sort[1]}</sortOrder>\n" if sort else "")
                   + "    </relatedLists>\n")
    out.append("    <showEmailCheckbox>false</showEmailCheckbox>\n    <showHighlightsPanel>false</showHighlightsPanel>\n"
               "    <showInteractionLogPanel>false</showInteractionLogPanel>\n"
               "    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>\n"
               "    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>\n</Layout>\n")
    return "".join(out)


for obj, (name, sections, related) in LAYOUTS.items():
    p = ROOT / "layouts" / f"{obj}-{name}.layout-meta.xml"
    p.write_text(layout_xml(obj, sections, related), encoding="utf-8", newline="\n")
    print("layout", p.name)

for obj, cols in SEARCH.items():
    p = ROOT / "objects" / obj / f"{obj}.object-meta.xml"
    t = p.read_text(encoding="utf-8")
    block = "    <searchLayouts>\n" + "".join(
        f"        <searchResultsAdditionalFields>{c}</searchResultsAdditionalFields>\n" for c in cols) + "    </searchLayouts>\n"
    t = re.sub(r"    <searchLayouts/>\n|    <searchLayouts>.*?</searchLayouts>\n", block, t, count=1, flags=re.S)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("search", obj, len(cols))

lv = ROOT / "objects" / "Service_Visit__c" / "listViews" / "Defect_Repairs.listView-meta.xml"
lv.write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<ListView {NS}>
    <fullName>Defect_Repairs</fullName>
    <columns>NAME</columns>
    <columns>Vehicle__c</columns>
    <columns>Check_In_Date__c</columns>
    <columns>Defect_System__c</columns>
    <columns>Main_Part__c</columns>
    <columns>Repair_Days__c</columns>
    <columns>Mileage__c</columns>
    <columns>Warranty_Applied__c</columns>
    <filterScope>Everything</filterScope>
    <filters>
        <field>Visit_Type__c</field>
        <operation>equals</operation>
        <value>하자 수리</value>
    </filters>
    <label>하자 수리</label>
</ListView>
""", encoding="utf-8", newline="\n")
print("listview", lv.name)
