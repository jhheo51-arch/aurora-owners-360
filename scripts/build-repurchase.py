"""v5 S-4 재구매 상담 (docs/design/v5-retention.md Q74·Q75).
표준 Opportunity 재사용: Aurora_Type__c='재구매 상담'으로 org의 다른 영업 기회와 구분한다.
org 공용 Opportunity 단계·레이아웃·Path는 바꾸지 않는다 — 오로라 앱 전용 레코드 페이지(Dynamic Forms)와 리스트 뷰만.
- Flow Aurora_Finance_Maturity_Repurchase: 금융 계약 만기일 90일 전 예약 경로 → RepurchaseService
- Flow Aurora_Warranty_Expiry_Repurchase: 매일 1회 전체 점검(차량 일반 보증 만료일이 수식이라 예약 경로 기준이 될 수 없음)
- 이미 90일 이내인 샘플은 예약 경로가 다시 돌지 않으므로 배포 후 RepurchaseService.scan() 1회 실행
실행: python -X utf8 scripts/build-repurchase.py
"""
import importlib.util
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent.parent
ROOT = BASE / "force-app" / "main" / "default"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
O = "Opportunity"
WINDOW_DAYS = 90
AURORA_TYPE = "재구매 상담"

spec = importlib.util.spec_from_file_location("bp", BASE / "scripts" / "build-pages.py")
bp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bp)


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc=""):
    d = f"    <description>{escape(desc)}</description>\n" if desc else ""
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n{d}    <label>{escape(label)}</label>\n"
            f"{body}</CustomField>\n")


def picklist(values):
    vals = "".join(f"            <value>\n                <fullName>{v}</fullName>\n                <default>false</default>\n"
                   f"                <label>{v}</label>\n            </value>\n" for v in values)
    return ("    <required>false</required>\n    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n"
            f"        <valueSetDefinition>\n            <sorted>false</sorted>\n{vals}        </valueSetDefinition>\n    </valueSet>\n")


def lookup(ref, rel, label):
    return (f"    <deleteConstraint>SetNull</deleteConstraint>\n    <referenceTo>{ref}</referenceTo>\n"
            f"    <relationshipLabel>{escape(label)}</relationshipLabel>\n    <relationshipName>{rel}</relationshipName>\n"
            "    <required>false</required>\n    <type>Lookup</type>\n")


# ===== Opportunity 필드 =====
write(f"objects/{O}/fields/Aurora_Type__c.field-meta.xml", field(
    "Aurora_Type__c", "오로라 상담 유형", picklist([AURORA_TYPE]),
    "오로라 앱이 만든 영업 기회 표시. 비어 있으면 org의 다른 영업 기회(오로라와 무관)"))
write(f"objects/{O}/fields/Trigger_Reason__c.field-meta.xml", field(
    "Trigger_Reason__c", "상담 계기", picklist(["금융 만기", "보증 만료", "고객 요청"])))
write(f"objects/{O}/fields/Customer_Contact__c.field-meta.xml", field(
    "Customer_Contact__c", "고객(차주)", lookup("Contact", "Aurora_Repurchase_Opportunities", "재구매 상담"),
    "차주 대부분은 Account가 없어 Contact로 직접 연결"))
write(f"objects/{O}/fields/Vehicle__c.field-meta.xml", field(
    "Vehicle__c", "차량", lookup("Vehicle__c", "Repurchase_Opportunities", "재구매 상담"), "차량당 열린 재구매 상담은 1건"))
write(f"objects/{O}/fields/Finance_Contract__c.field-meta.xml", field(
    "Finance_Contract__c", "금융·리스 계약", lookup("Finance_Contract__c", "Repurchase_Opportunities", "재구매 상담")))
write(f"objects/{O}/fields/Recommended_Model__c.field-meta.xml", field(
    "Recommended_Model__c", "추천 모델", lookup("Vehicle_Model__c", "Recommended_Opportunities", "추천 재구매 상담"),
    "자동 생성 시 현재 차종이 기본값. 상담원이 상담 후 변경"))

# ===== 리스트 뷰 =====
COLS = "".join(f"    <columns>{c}</columns>\n" for c in
               ["OPPORTUNITY.NAME", "Trigger_Reason__c", "Customer_Contact__c", "Vehicle__c",
                "OPPORTUNITY.STAGE_NAME", "OPPORTUNITY.CLOSE_DATE", "Recommended_Model__c", "CORE.USERS.ALIAS"])
write(f"objects/{O}/listViews/Aurora_Repurchase.listView-meta.xml", f"""<ListView {NS}>
    <fullName>Aurora_Repurchase</fullName>
{COLS}    <filterScope>Everything</filterScope>
    <filters>
        <field>Aurora_Type__c</field>
        <operation>equals</operation>
        <value>{AURORA_TYPE}</value>
    </filters>
    <label>오로라 재구매 상담</label>
</ListView>
""")

# ===== Flow =====
ACTION = """    <actionCalls>
        <name>Create_Repurchase</name>
        <label>재구매 상담 생성</label>
        <locationX>{x}</locationX>
        <locationY>276</locationY>
        <actionName>RepurchaseService</actionName>
        <actionType>apex</actionType>
        <flowTransactionModel>CurrentTransaction</flowTransactionModel>
{inputs}        <nameSegment>RepurchaseService</nameSegment>
    </actionCalls>
"""
META = """    <processMetadataValues>
        <name>BuilderType</name>
        <value>
            <stringValue>LightningFlowBuilder</stringValue>
        </value>
    </processMetadataValues>
    <processMetadataValues>
        <name>CanvasMode</name>
        <value>
            <stringValue>AUTO_LAYOUT_CANVAS</stringValue>
        </value>
    </processMetadataValues>
    <processType>AutoLaunchedFlow</processType>
"""
RECORD_INPUT = """        <inputParameters>
            <name>recordId</name>
            <value>
                <elementReference>$Record.Id</elementReference>
            </value>
        </inputParameters>
"""
write("flows/Aurora_Finance_Maturity_Repurchase.flow-meta.xml", f"""<Flow {NS}>
{ACTION.format(x=314, inputs=RECORD_INPUT)}    <apiVersion>67.0</apiVersion>
    <description>v5 S-4: 진행 중인 금융·리스 계약의 만기일 {WINDOW_DAYS}일 전에 재구매 상담(Opportunity)을 만든다. 남은 기간·중복(차량당 열린 상담 1건)은 Apex가 다시 확인.</description>
    <environments>Default</environments>
    <interviewLabel>오로라 금융 만기 재구매 상담 {{!$Flow.CurrentDateTime}}</interviewLabel>
    <label>오로라 금융 만기 재구매 상담</label>
{META}    <start>
        <locationX>50</locationX>
        <locationY>0</locationY>
        <doesRequireRecordChangedToMeetCriteria>true</doesRequireRecordChangedToMeetCriteria>
        <filterLogic>and</filterLogic>
        <filters>
            <field>Status__c</field>
            <operator>EqualTo</operator>
            <value>
                <stringValue>진행</stringValue>
            </value>
        </filters>
        <filters>
            <field>End_Date__c</field>
            <operator>IsNull</operator>
            <value>
                <booleanValue>false</booleanValue>
            </value>
        </filters>
        <object>Finance_Contract__c</object>
        <recordTriggerType>CreateAndUpdate</recordTriggerType>
        <scheduledPaths>
            <name>Before_Maturity</name>
            <connector>
                <targetReference>Create_Repurchase</targetReference>
            </connector>
            <label>만기 {WINDOW_DAYS}일 전</label>
            <offsetNumber>-{WINDOW_DAYS}</offsetNumber>
            <offsetUnit>Days</offsetUnit>
            <recordField>End_Date__c</recordField>
            <timeSource>RecordField</timeSource>
        </scheduledPaths>
        <triggerType>RecordAfterSave</triggerType>
    </start>
    <status>Active</status>
</Flow>
""")
write("flows/Aurora_Warranty_Expiry_Repurchase.flow-meta.xml", f"""<Flow {NS}>
{ACTION.format(x=176, inputs="")}    <apiVersion>67.0</apiVersion>
    <description>v5 S-4: 매일 1회 금융 만기·일반 보증 만료 {WINDOW_DAYS}일 이내 차량을 점검해 재구매 상담을 만든다. 차량 일반 보증 만료일은 수식 필드라 기록 트리거 예약 경로의 기준이 될 수 없어 예약 Flow로 구현. 중복 없음.</description>
    <environments>Default</environments>
    <interviewLabel>오로라 보증 만료 재구매 상담 점검 {{!$Flow.CurrentDateTime}}</interviewLabel>
    <label>오로라 보증 만료 재구매 상담 점검</label>
{META}    <start>
        <locationX>50</locationX>
        <locationY>0</locationY>
        <connector>
            <targetReference>Create_Repurchase</targetReference>
        </connector>
        <schedule>
            <frequency>Daily</frequency>
            <startDate>2026-10-17</startDate>
            <startTime>07:00:00.000Z</startTime>
        </schedule>
        <triggerType>Scheduled</triggerType>
    </start>
    <status>Active</status>
</Flow>
""")

# ===== 오로라 앱 전용 재구매 상담 레코드 페이지 =====
regions = []
sections = [
    ("재구매 상담", [("Name", False), ("StageName", False), ("CloseDate", False), ("OwnerId", False)],
     [("Aurora_Type__c", True), ("Trigger_Reason__c", False), ("Amount", False), ("NextStep", False)], None),
    ("고객·차량", [("Customer_Contact__c", False), ("Vehicle__c", False)],
     [("Finance_Contract__c", False), ("Recommended_Model__c", False)], None),
    ("상담 메모", [("Description", False)], None, None),
]
main = bp.field_sections("repurchase", sections, regions)
xml = bp.page("오로라 재구매 상담 레코드 페이지", O, [bp.highlights()], main, [bp.related_container()], regions)
(bp.OUT / "Aurora_Repurchase_Record_Page.flexipage-meta.xml").write_text(xml, encoding="utf-8", newline="\n")
print("wrote flexipages/Aurora_Repurchase_Record_Page.flexipage-meta.xml")

# ===== 오로라 앱: 탭 + Opportunity 페이지 할당 =====
p = ROOT / "applications" / "Aurora_Owners_360.app-meta.xml"
t = p.read_text(encoding="utf-8")
if "Aurora_Repurchase_Record_Page" not in t:
    override = """    <actionOverrides>
        <actionName>View</actionName>
        <comment>오로라 앱에서만 재구매 상담 레코드 페이지 사용(org 공용 Opportunity 페이지는 그대로)</comment>
        <content>Aurora_Repurchase_Record_Page</content>
        <formFactor>Large</formFactor>
        <skipRecordTypeSelect>false</skipRecordTypeSelect>
        <type>Flexipage</type>
        <pageOrSobjectType>Opportunity</pageOrSobjectType>
    </actionOverrides>
"""
    anchor = "    <brand>\n"
    assert anchor in t
    t = t.replace(anchor, override + anchor, 1)
if "<tabs>standard-Opportunity</tabs>" not in t:
    anchor = "    <tabs>Finance_Contract__c</tabs>\n"
    assert anchor in t
    t = t.replace(anchor, anchor + "    <tabs>standard-Opportunity</tabs>\n", 1)
p.write_text(t, encoding="utf-8", newline="\n")
print("app Aurora_Owners_360: 영업 기회 탭 + 재구매 상담 페이지")

# ===== 차량·금융 계약 레이아웃에 재구매 상담 관련 목록 =====
RELATED = """    <relatedLists>
        <fields>OPPORTUNITY.NAME</fields>
        <fields>Trigger_Reason__c</fields>
        <fields>OPPORTUNITY.STAGE_NAME</fields>
        <fields>OPPORTUNITY.CLOSE_DATE</fields>
        <relatedList>Opportunity.{field}</relatedList>
    </relatedLists>
"""
for name, fld in [("Vehicle__c-고객 차량 레이아웃", "Vehicle__c"), ("Finance_Contract__c-금융·리스 계약 레이아웃", "Finance_Contract__c")]:
    p = ROOT / "layouts" / f"{name}.layout-meta.xml"
    t = p.read_text(encoding="utf-8")
    if f"<relatedList>Opportunity.{fld}</relatedList>" in t:
        continue
    anchor = "    <showEmailCheckbox>"
    assert anchor in t, name
    t = t.replace(anchor, RELATED.format(field=fld) + anchor, 1)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("layout", name, "+ 재구매 상담")
