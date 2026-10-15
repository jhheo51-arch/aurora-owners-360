"""v4 리콜 조기 경보 메타데이터 생성: Recall_Alert__c(+필드·리스트 뷰·레이아웃·탭), Case.Recall_Alert__c,
기준 커스텀 메타데이터 Recall_Rule__mdt(KR_Default: 90일·2건), 벨 알림 유형 Aurora_Recall_Alert.
실행: python -X utf8 scripts/build-recall.py
"""
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent / "force-app" / "main" / "default"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc=""):
    d = f"    <description>{escape(desc)}</description>\n" if desc else ""
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n{d}    <label>{escape(label)}</label>\n"
            f"{body}</CustomField>\n")


OBJ = "Recall_Alert__c"
STATUSES = ["신규", "검토 중", "리콜 권고", "종결"]

write(f"objects/{OBJ}/{OBJ}.object-meta.xml", f"""<CustomObject {NS}>
    <allowInChatterGroups>false</allowInChatterGroups>
    <compactLayoutAssignment>SYSTEM</compactLayoutAssignment>
    <deploymentStatus>Deployed</deploymentStatus>
    <description>리콜 조기 경보(v4). 같은 모델 계열·같은 계통 안전 결함 VOC가 기준(Recall_Rule__mdt) 이상이면 Apex가 만들고 갱신한다. 검토는 품질·안전 대응 담당.</description>
    <enableActivities>false</enableActivities>
    <enableBulkApi>true</enableBulkApi>
    <enableFeeds>false</enableFeeds>
    <enableHistory>false</enableHistory>
    <enableLicensing>false</enableLicensing>
    <enableReports>true</enableReports>
    <enableSearch>true</enableSearch>
    <enableSharing>true</enableSharing>
    <enableStreamingApi>true</enableStreamingApi>
    <externalSharingModel>ReadWrite</externalSharingModel>
    <label>리콜 경보</label>
    <nameField>
        <displayFormat>RA-{{0000}}</displayFormat>
        <label>경보 번호</label>
        <trackHistory>false</trackHistory>
        <type>AutoNumber</type>
        <startingNumber>1</startingNumber>
    </nameField>
    <pluralLabel>리콜 경보</pluralLabel>
    <searchLayouts/>
    <sharingModel>ReadWrite</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
""")

text = lambda n: f"    <length>{n}</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n"
write(f"objects/{OBJ}/fields/Model_Line__c.field-meta.xml", field("Model_Line__c", "모델 계열", text(40), "예: 노스라이트"))
write(f"objects/{OBJ}/fields/System__c.field-meta.xml", field("System__c", "계통", text(20), "배터리·구동·제동·공조·전장·차체"))
write(f"objects/{OBJ}/fields/VOC_Count__c.field-meta.xml", field(
    "VOC_Count__c", "안전 결함 VOC 건수",
    "    <precision>4</precision>\n    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n",
    "기준 기간 안 같은 모델 계열·계통 안전 결함 VOC 수(종결 포함)"))
values = "".join(
    f"            <value>\n                <fullName>{s}</fullName>\n                <default>{'true' if i == 0 else 'false'}</default>\n"
    f"                <label>{s}</label>\n            </value>\n" for i, s in enumerate(STATUSES))
write(f"objects/{OBJ}/fields/Status__c.field-meta.xml", field(
    "Status__c", "검토 상태",
    "    <required>false</required>\n    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n"
    f"        <valueSetDefinition>\n            <sorted>false</sorted>\n{values}        </valueSetDefinition>\n    </valueSet>\n"))
lookup = lambda ref, rel, label: (f"    <deleteConstraint>SetNull</deleteConstraint>\n    <referenceTo>{ref}</referenceTo>\n"
                                  f"    <relationshipLabel>{escape(label)}</relationshipLabel>\n    <relationshipName>{rel}</relationshipName>\n"
                                  "    <required>false</required>\n    <type>Lookup</type>\n")
write(f"objects/{OBJ}/fields/Assigned_Staff__c.field-meta.xml", field(
    "Assigned_Staff__c", "담당(품질·안전)", lookup("Care_Staff__c", "Recall_Alerts", "리콜 경보")))
write(f"objects/{OBJ}/fields/Latest_Case__c.field-meta.xml", field(
    "Latest_Case__c", "최근 VOC", lookup("Case", "Latest_Recall_Alerts", "리콜 경보(최근 VOC)")))
dt = "    <required>false</required>\n    <type>DateTime</type>\n"
write(f"objects/{OBJ}/fields/First_Detected_At__c.field-meta.xml", field("First_Detected_At__c", "최초 감지", dt))
write(f"objects/{OBJ}/fields/Last_Detected_At__c.field-meta.xml", field("Last_Detected_At__c", "최근 감지", dt))
write(f"objects/{OBJ}/fields/Summary__c.field-meta.xml", field(
    "Summary__c", "경보 요약",
    "    <length>2000</length>\n    <type>LongTextArea</type>\n    <visibleLines>4</visibleLines>\n"))
write("objects/Case/fields/Recall_Alert__c.field-meta.xml", field(
    "Recall_Alert__c", "리콜 경보", lookup(OBJ, "Cases", "관련 VOC"), "리콜 조기 경보에 묶인 안전 결함 VOC (v4, Apex 설정)"))

write(f"objects/{OBJ}/listViews/All.listView-meta.xml", f"""<ListView {NS}>
    <fullName>All</fullName>
    <columns>NAME</columns>
    <columns>Status__c</columns>
    <columns>Model_Line__c</columns>
    <columns>System__c</columns>
    <columns>VOC_Count__c</columns>
    <columns>Last_Detected_At__c</columns>
    <columns>Assigned_Staff__c</columns>
    <filterScope>Everything</filterScope>
    <label>전체</label>
</ListView>
""")
write(f"objects/{OBJ}/listViews/Open_Alerts.listView-meta.xml", f"""<ListView {NS}>
    <fullName>Open_Alerts</fullName>
    <columns>NAME</columns>
    <columns>Status__c</columns>
    <columns>Model_Line__c</columns>
    <columns>System__c</columns>
    <columns>VOC_Count__c</columns>
    <columns>Last_Detected_At__c</columns>
    <columns>Assigned_Staff__c</columns>
    <filterScope>Everything</filterScope>
    <filters>
        <field>Status__c</field>
        <operation>notEqual</operation>
        <value>종결</value>
    </filters>
    <label>진행 중 경보</label>
</ListView>
""")

items = lambda fs: "".join(
    f"            <layoutItems>\n                <behavior>{b}</behavior>\n                <field>{f}</field>\n            </layoutItems>\n"
    for f, b in fs)
write(f"layouts/{OBJ}-리콜 경보 레이아웃.layout-meta.xml", f"""<Layout {NS}>
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>경보 정보</label>
        <layoutColumns>
{items([("Name", "Readonly"), ("Model_Line__c", "Readonly"), ("System__c", "Readonly"), ("VOC_Count__c", "Readonly")])}        </layoutColumns>
        <layoutColumns>
{items([("Status__c", "Edit"), ("Assigned_Staff__c", "Edit"), ("First_Detected_At__c", "Readonly"), ("Last_Detected_At__c", "Readonly"), ("Latest_Case__c", "Readonly")])}        </layoutColumns>
        <style>TwoColumnsTopToBottom</style>
    </layoutSections>
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>요약</label>
        <layoutColumns>
{items([("Summary__c", "Readonly")])}        </layoutColumns>
        <style>OneColumn</style>
    </layoutSections>
    <relatedLists>
        <fields>CASES.CASE_NUMBER</fields>
        <fields>CASES.SUBJECT</fields>
        <fields>Vehicle__c</fields>
        <fields>VOC_Status__c</fields>
        <fields>CASES.CREATED_DATE</fields>
        <relatedList>Case.Recall_Alert__c</relatedList>
    </relatedLists>
    <showEmailCheckbox>false</showEmailCheckbox>
    <showHighlightsPanel>false</showHighlightsPanel>
    <showInteractionLogPanel>false</showInteractionLogPanel>
    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>
    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>
</Layout>
""")
write(f"tabs/{OBJ}.tab-meta.xml", f"""<CustomTab {NS}>
    <customObject>true</customObject>
    <motif>Custom53: Bell</motif>
</CustomTab>
""")

write("objects/Recall_Rule__mdt/Recall_Rule__mdt.object-meta.xml", f"""<CustomObject {NS}>
    <description>리콜 조기 경보 기준(v4). 같은 모델 계열·계통 안전 결함 VOC를 이 기간·건수로 센다.</description>
    <label>리콜 경보 기준</label>
    <pluralLabel>리콜 경보 기준</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
""")
num = lambda: ("    <fieldManageability>DeveloperControlled</fieldManageability>\n    <precision>6</precision>\n"
               "    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n")
write("objects/Recall_Rule__mdt/fields/Window_Days__c.field-meta.xml", field("Window_Days__c", "기간(일)", num()))
write("objects/Recall_Rule__mdt/fields/Threshold__c.field-meta.xml", field("Threshold__c", "경보 건수", num()))
write("customMetadata/Recall_Rule.KR_Default.md-meta.xml", f"""<CustomMetadata {NS} xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>기본 (최근 90일 2건)</label>
    <protected>false</protected>
    <values>
        <field>Threshold__c</field>
        <value xsi:type="xsd:double">2</value>
    </values>
    <values>
        <field>Window_Days__c</field>
        <value xsi:type="xsd:double">90</value>
    </values>
</CustomMetadata>
""")
write("notificationtypes/Aurora_Recall_Alert.notiftype-meta.xml", f"""<CustomNotificationType {NS}>
    <customNotifTypeName>오로라 리콜 조기 경보</customNotifTypeName>
    <description>같은 모델 계열·계통 안전 결함 VOC가 기준 이상일 때 (v4)</description>
    <desktop>true</desktop>
    <masterLabel>오로라 리콜 조기 경보</masterLabel>
    <mobile>true</mobile>
    <slack>false</slack>
</CustomNotificationType>
""")
