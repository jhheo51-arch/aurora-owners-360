"""v5 S-2 리콜 캠페인 (docs/design/v5-retention.md Q70~Q72).
Recall_Campaign__c(RC-) + Recall_Vehicle__c(RV-, 캠페인 Master-Detail), 정비 이력 Recall_Vehicle__c(리콜 조치 기록),
[대상 차량 생성] 빠른 작업(LWC auroraRecallTargets → Apex RecallCampaignService), 리콜 경보 화면에 '리콜 캠페인' 관련 목록.
대상 조건 = 모델 계열 + 출고일 범위. 대상 차량 키(Target_Key__c) = 캠페인 키 + '|' + VIN → 다시 만들어도 중복 없음.
실행: python -X utf8 scripts/build-recall-campaign.py  (메타데이터 + data/v5/recall-*.csv 생성)
"""
import csv
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent.parent
ROOT = BASE / "force-app" / "main" / "default"
DATA = BASE / "data" / "v5"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

MODEL_LINES = ["오로라 E5", "노스라이트", "시티로", "오로라 GT"]
SYSTEMS = ["배터리", "구동", "제동", "공조", "전장", "차체"]
CAMPAIGN_STATUS = ["계획", "진행", "완료"]
TARGET_STATUS = ["미통지", "통지", "입고 예약", "조치 완료", "제외"]


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc=""):
    d = f"    <description>{escape(desc)}</description>\n" if desc else ""
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n{d}    <label>{escape(label)}</label>\n"
            f"{body}</CustomField>\n")


def text(n):
    return f"    <length>{n}</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n"


DATE = "    <required>false</required>\n    <type>Date</type>\n"
EXT_KEY = ("    <caseSensitive>false</caseSensitive>\n    <externalId>true</externalId>\n    <length>80</length>\n"
           "    <required>false</required>\n    <type>Text</type>\n    <unique>true</unique>\n")


def picklist(values, default_first=False):
    vals = "".join(f"            <value>\n                <fullName>{v}</fullName>\n"
                   f"                <default>{'true' if default_first and i == 0 else 'false'}</default>\n"
                   f"                <label>{v}</label>\n            </value>\n" for i, v in enumerate(values))
    return ("    <required>false</required>\n    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n"
            f"        <valueSetDefinition>\n            <sorted>false</sorted>\n{vals}        </valueSetDefinition>\n    </valueSet>\n")


def lookup(ref, rel, label, extra=""):
    return (f"    <deleteConstraint>SetNull</deleteConstraint>\n{extra}    <referenceTo>{ref}</referenceTo>\n"
            f"    <relationshipLabel>{escape(label)}</relationshipLabel>\n    <relationshipName>{rel}</relationshipName>\n"
            "    <required>false</required>\n    <type>Lookup</type>\n")


def obj(api, label, fmt, desc):
    return f"""<CustomObject {NS}>
    <allowInChatterGroups>false</allowInChatterGroups>
    <compactLayoutAssignment>SYSTEM</compactLayoutAssignment>
    <deploymentStatus>Deployed</deploymentStatus>
    <description>{escape(desc)}</description>
    <enableActivities>false</enableActivities>
    <enableBulkApi>true</enableBulkApi>
    <enableFeeds>false</enableFeeds>
    <enableHistory>false</enableHistory>
    <enableLicensing>false</enableLicensing>
    <enableReports>true</enableReports>
    <enableSearch>true</enableSearch>
    <enableSharing>true</enableSharing>
    <enableStreamingApi>true</enableStreamingApi>
    <externalSharingModel>{'ControlledByParent' if api == 'Recall_Vehicle__c' else 'ReadWrite'}</externalSharingModel>
    <label>{label}</label>
    <nameField>
        <displayFormat>{fmt}</displayFormat>
        <label>번호</label>
        <trackHistory>false</trackHistory>
        <type>AutoNumber</type>
        <startingNumber>1</startingNumber>
    </nameField>
    <pluralLabel>{label}</pluralLabel>
    <searchLayouts/>
    <sharingModel>{'ControlledByParent' if api == 'Recall_Vehicle__c' else 'ReadWrite'}</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
"""


def items(fs):
    return "".join(f"            <layoutItems>\n                <behavior>{b}</behavior>\n                <field>{f}</field>\n"
                   "            </layoutItems>\n" for f, b in fs)


def section(label, left, right=None):
    cols = f"        <layoutColumns>\n{items(left)}        </layoutColumns>\n"
    if right is not None:
        cols += f"        <layoutColumns>\n{items(right)}        </layoutColumns>\n"
    style = "TwoColumnsTopToBottom" if right is not None else "OneColumn"
    return ("    <layoutSections>\n        <customLabel>true</customLabel>\n        <detailHeading>true</detailHeading>\n"
            f"        <editHeading>true</editHeading>\n        <label>{label}</label>\n{cols}        <style>{style}</style>\n"
            "    </layoutSections>\n")


LAYOUT_TAIL = ("    <showEmailCheckbox>false</showEmailCheckbox>\n    <showHighlightsPanel>false</showHighlightsPanel>\n"
               "    <showInteractionLogPanel>false</showInteractionLogPanel>\n    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>\n"
               "    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>\n</Layout>\n")

# ===== Recall_Campaign__c =====
C = "Recall_Campaign__c"
write(f"objects/{C}/{C}.object-meta.xml", obj(C, "리콜 캠페인", "RC-{0000}",
      "차량 단위 리콜·무상수리 캠페인(v5). 대상 조건 = 모델 계열 + 출고일 범위, [대상 차량 생성]으로 Recall_Vehicle__c를 만든다."))
write(f"objects/{C}/fields/Campaign_Key__c.field-meta.xml", field("Campaign_Key__c", "캠페인 키", EXT_KEY, "샘플 적재용 외부 ID(예: RC-K1). 대상 차량 키의 앞부분"))
write(f"objects/{C}/fields/Title__c.field-meta.xml", field("Title__c", "캠페인명", text(120)))
write(f"objects/{C}/fields/Model_Line__c.field-meta.xml", field("Model_Line__c", "대상 모델 계열", picklist(MODEL_LINES)))
write(f"objects/{C}/fields/System__c.field-meta.xml", field("System__c", "계통", picklist(SYSTEMS)))
write(f"objects/{C}/fields/Delivery_From__c.field-meta.xml", field("Delivery_From__c", "대상 출고일(시작)", DATE, "비우면 시작 제한 없음"))
write(f"objects/{C}/fields/Delivery_To__c.field-meta.xml", field("Delivery_To__c", "대상 출고일(끝)", DATE, "비우면 끝 제한 없음"))
write(f"objects/{C}/fields/Start_Date__c.field-meta.xml", field("Start_Date__c", "시행일", DATE))
write(f"objects/{C}/fields/Status__c.field-meta.xml", field("Status__c", "캠페인 상태", picklist(CAMPAIGN_STATUS, True)))
write(f"objects/{C}/fields/Remedy__c.field-meta.xml", field(
    "Remedy__c", "조치 내용", "    <length>2000</length>\n    <type>LongTextArea</type>\n    <visibleLines>3</visibleLines>\n"))
write(f"objects/{C}/fields/Source_Alert__c.field-meta.xml", field(
    "Source_Alert__c", "출발 리콜 경보", lookup("Recall_Alert__c", "Campaigns", "리콜 캠페인"), "이 캠페인의 계기가 된 리콜 조기 경보(v4)"))


def rollup(name, label, op_value=None, desc=""):
    flt = ""
    if op_value:
        op, value = op_value
        flt = (f"    <summaryFilterItems>\n        <field>Recall_Vehicle__c.Status__c</field>\n        <operation>{op}</operation>\n"
               f"        <value>{value}</value>\n    </summaryFilterItems>\n")
    write(f"objects/{C}/fields/{name}.field-meta.xml", field(
        name, label, f"    <summaryForeignKey>Recall_Vehicle__c.Campaign__c</summaryForeignKey>\n{flt}"
        "    <summaryOperation>count</summaryOperation>\n    <type>Summary</type>\n", desc))


rollup("Target_Count__c", "대상 차량", ("notEqual", "제외"), "제외를 뺀 대상 차량 수")
rollup("Notified_Count__c", "통지 완료", ("equals", "통지, 입고 예약, 조치 완료"), "통지 이후 단계의 차량 수")
rollup("Completed_Count__c", "조치 완료", ("equals", "조치 완료"))
write(f"objects/{C}/fields/Completion_Rate__c.field-meta.xml", field(
    "Completion_Rate__c", "이행률",
    "    <formula>IF(Target_Count__c &gt; 0, Completed_Count__c / Target_Count__c, 0)</formula>\n"
    "    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>\n    <precision>18</precision>\n    <required>false</required>\n"
    "    <scale>0</scale>\n    <type>Percent</type>\n", "조치 완료 ÷ 대상 차량"))

write(f"objects/{C}/listViews/All.listView-meta.xml", f"""<ListView {NS}>
    <fullName>All</fullName>
    <columns>NAME</columns>
    <columns>Title__c</columns>
    <columns>Status__c</columns>
    <columns>Model_Line__c</columns>
    <columns>System__c</columns>
    <columns>Target_Count__c</columns>
    <columns>Completed_Count__c</columns>
    <columns>Completion_Rate__c</columns>
    <filterScope>Everything</filterScope>
    <label>전체</label>
</ListView>
""")
write(f"layouts/{C}-리콜 캠페인 레이아웃.layout-meta.xml", f"""<Layout {NS}>
{section("캠페인", [("Name", "Readonly"), ("Title__c", "Required"), ("Status__c", "Edit"), ("Start_Date__c", "Edit"), ("Source_Alert__c", "Edit")],
         [("Model_Line__c", "Required"), ("System__c", "Edit"), ("Delivery_From__c", "Edit"), ("Delivery_To__c", "Edit"), ("Campaign_Key__c", "Edit")])}{section("이행 현황", [("Target_Count__c", "Readonly"), ("Notified_Count__c", "Readonly")],
         [("Completed_Count__c", "Readonly"), ("Completion_Rate__c", "Readonly")])}{section("조치 내용", [("Remedy__c", "Edit")])}    <platformActionList>
        <actionListContext>Record</actionListContext>
        <platformActionListItems>
            <actionName>{C}.Generate_Targets</actionName>
            <actionType>QuickAction</actionType>
            <sortOrder>0</sortOrder>
        </platformActionListItems>
        <platformActionListItems>
            <actionName>Edit</actionName>
            <actionType>StandardButton</actionType>
            <sortOrder>1</sortOrder>
        </platformActionListItems>
    </platformActionList>
    <relatedLists>
        <fields>NAME</fields>
        <fields>Vehicle__c</fields>
        <fields>Owner_Name__c</fields>
        <fields>Status__c</fields>
        <fields>Service_Center__c</fields>
        <fields>Notified_Date__c</fields>
        <fields>Completed_Date__c</fields>
        <relatedList>Recall_Vehicle__c.Campaign__c</relatedList>
    </relatedLists>
{LAYOUT_TAIL}""")
write(f"tabs/{C}.tab-meta.xml", f"""<CustomTab {NS}>
    <customObject>true</customObject>
    <motif>Custom68: Shield</motif>
</CustomTab>
""")
write(f"quickActions/{C}.Generate_Targets.quickAction-meta.xml", f"""<QuickAction {NS}>
    <actionSubtype>ScreenAction</actionSubtype>
    <description>모델 계열·출고일 조건에 맞는 차량으로 대상 차량을 만든다(v5)</description>
    <label>대상 차량 생성</label>
    <lightningWebComponent>auroraRecallTargets</lightningWebComponent>
    <optionsCreateFeedItem>false</optionsCreateFeedItem>
    <type>LightningWebComponent</type>
</QuickAction>
""")

# ===== Recall_Vehicle__c =====
V = "Recall_Vehicle__c"
write(f"objects/{V}/{V}.object-meta.xml", obj(V, "리콜 대상 차량", "RV-{0000}",
      "리콜 캠페인의 차량별 이행 상태(v5): 미통지 → 통지 → 입고 예약 → 조치 완료 (+ 제외). 정비 이력 완료 시 조치 완료로 바뀐다."))
write(f"objects/{V}/fields/Campaign__c.field-meta.xml", field(
    "Campaign__c", "리콜 캠페인",
    f"    <referenceTo>{C}</referenceTo>\n    <relationshipLabel>대상 차량</relationshipLabel>\n    <relationshipName>Targets</relationshipName>\n"
    "    <relationshipOrder>0</relationshipOrder>\n    <reparentableMasterDetail>false</reparentableMasterDetail>\n"
    "    <type>MasterDetail</type>\n    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n"))
write(f"objects/{V}/fields/Vehicle__c.field-meta.xml", field("Vehicle__c", "차량", lookup("Vehicle__c", "Recall_Targets", "리콜 대상")))
write(f"objects/{V}/fields/Status__c.field-meta.xml", field("Status__c", "이행 상태", picklist(TARGET_STATUS, True)))
write(f"objects/{V}/fields/Notified_Date__c.field-meta.xml", field("Notified_Date__c", "통지일", DATE, "상태를 '통지'로 바꾸면 비어 있을 때 오늘로 채움"))
write(f"objects/{V}/fields/Reserved_Date__c.field-meta.xml", field("Reserved_Date__c", "입고 예약일", DATE))
write(f"objects/{V}/fields/Completed_Date__c.field-meta.xml", field("Completed_Date__c", "조치일", DATE))
write(f"objects/{V}/fields/Service_Center__c.field-meta.xml", field(
    "Service_Center__c", "조치 서비스센터",
    lookup("Account", "Recall_Center_Targets", "리콜 조치 차량",
           "    <lookupFilter>\n        <active>true</active>\n        <errorMessage>고객 구분(오로라)이 '서비스센터'인 거래처만 고를 수 있습니다.</errorMessage>\n"
           "        <filterItems>\n            <field>Account.Customer_Segment__c</field>\n            <operation>equals</operation>\n"
           "            <value>서비스센터</value>\n        </filterItems>\n        <isOptional>false</isOptional>\n    </lookupFilter>\n"),
    "기본값은 차량의 담당 서비스센터"))
write(f"objects/{V}/fields/Exclusion_Reason__c.field-meta.xml", field("Exclusion_Reason__c", "제외 사유", text(255), "폐차·수출·이미 조치 등"))
write(f"objects/{V}/fields/Target_Key__c.field-meta.xml", field("Target_Key__c", "대상 키", EXT_KEY, "캠페인 키 + '|' + VIN (중복 방지, Apex가 채움)"))
for api, label, formula in [("Owner_Name__c", "차주", "Vehicle__r.Owner_Contact__r.LastName"),
                            ("Plate_Number__c", "번호판", "Vehicle__r.Plate_Number__c")]:
    write(f"objects/{V}/fields/{api}.field-meta.xml", field(
        api, label, f"    <formula>{formula}</formula>\n    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>\n"
        "    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n", "표시용 수식"))
LV_COLS = "".join(f"    <columns>{c}</columns>\n" for c in ["NAME", "Campaign__c", "Vehicle__c", "Owner_Name__c", "Plate_Number__c", "Status__c", "Service_Center__c", "Reserved_Date__c"])
write(f"objects/{V}/listViews/All.listView-meta.xml", f"""<ListView {NS}>
    <fullName>All</fullName>
{LV_COLS}    <filterScope>Everything</filterScope>
    <label>전체</label>
</ListView>
""")
write(f"objects/{V}/listViews/Open_Targets.listView-meta.xml", f"""<ListView {NS}>
    <fullName>Open_Targets</fullName>
{LV_COLS}    <filterScope>Everything</filterScope>
    <filters>
        <field>Status__c</field>
        <operation>notEqual</operation>
        <value>조치 완료,제외</value>
    </filters>
    <label>미조치 차량</label>
</ListView>
""")
write(f"layouts/{V}-리콜 대상 차량 레이아웃.layout-meta.xml", f"""<Layout {NS}>
{section("대상 차량", [("Name", "Readonly"), ("Campaign__c", "Required"), ("Vehicle__c", "Edit"), ("Owner_Name__c", "Readonly"), ("Plate_Number__c", "Readonly")],
         [("Status__c", "Edit"), ("Service_Center__c", "Edit"), ("Notified_Date__c", "Edit"), ("Reserved_Date__c", "Edit"), ("Completed_Date__c", "Edit")])}{section("기타", [("Exclusion_Reason__c", "Edit")], [("Target_Key__c", "Readonly")])}    <relatedLists>
        <fields>NAME</fields>
        <fields>Visit_Type__c</fields>
        <fields>Check_In_Date__c</fields>
        <fields>Completed_Date__c</fields>
        <fields>Service_Center_Account__c</fields>
        <relatedList>Service_Visit__c.Recall_Vehicle__c</relatedList>
    </relatedLists>
{LAYOUT_TAIL}""")

# ===== Service_Visit__c: 리콜 조치 기록 =====
write("objects/Service_Visit__c/fields/Recall_Vehicle__c.field-meta.xml", field(
    "Recall_Vehicle__c", "리콜 대상 차량", lookup(V, "Visits", "리콜 조치 정비"),
    "리콜 조치로 입고한 정비. 완료일이 들어가면 대상 차량이 '조치 완료'가 된다(v5)"))
p = ROOT / "layouts" / "Service_Visit__c-정비 이력 레이아웃.layout-meta.xml"
t = p.read_text(encoding="utf-8")
anchor = "                <field>Service_Center_Account__c</field>\n            </layoutItems>\n"
if "<field>Recall_Vehicle__c</field>" not in t:
    assert anchor in t
    t = t.replace(anchor, anchor + "            <layoutItems>\n                <behavior>Edit</behavior>\n"
                  "                <field>Recall_Vehicle__c</field>\n            </layoutItems>\n", 1)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("layout Service_Visit__c + Recall_Vehicle__c")

# ===== 샘플 데이터 =====
DATA.mkdir(parents=True, exist_ok=True)


def write_csv(name, header, rows):
    with open(DATA / name, "w", encoding="utf-8", newline="\n") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print("wrote data/v5/" + name, len(rows), "rows")


write_csv("recall-campaigns.csv",
          ["Campaign_Key__c", "Title__c", "Model_Line__c", "System__c", "Delivery_From__c", "Delivery_To__c", "Start_Date__c", "Status__c", "Remedy__c"],
          [("RC-K1", "노스라이트 전자식 브레이크 부스터 점검·교체", "노스라이트", "제동", "2023-01-01", "2023-12-31", "2026-10-15", "진행",
            "2023년 출고 노스라이트의 전자식 브레이크 부스터 제어 소프트웨어 업데이트 및 부스터 점검. 이상 시 무상 교체(약 2시간). 대상 차주에게 통지 후 담당 서비스센터 입고 예약.")])
# [대상 차량 생성] 뒤 상태 반영용(키가 같아 중복 없음). 버튼 없이 적재해도 같은 결과
write_csv("recall-vehicles.csv",
          ["Target_Key__c", "Campaign__r.Campaign_Key__c", "Vehicle__r.VIN__c", "Status__c", "Notified_Date__c", "Reserved_Date__c", "Service_Center__r.Aurora_Key__c"],
          [("RC-K1|KAURNLSV0PA000303", "RC-K1", "KAURNLSV0PA000303", "입고 예약", "2026-10-15", "2026-10-20", "SC-PG"),
           ("RC-K1|KAURNLSV0PA000909", "RC-K1", "KAURNLSV0PA000909", "미통지", "", "", "SC-HU")])
