"""v5 S-3 금융·리스 계약 (docs/design/v5-retention.md Q73).
Finance_Contract__c(FC-): 차량·고객·유형(할부/리스/장기렌트)·금융사·시작일·만기일·월 납입금·잔존가치·상태,
만기까지 일수·만기 단계(수식). 만기 90일 전 재구매 상담 자동 생성은 S-4(RepurchaseService)에서.
샘플 6건(만기 90일 이내 2건, 이미 만기 1건). 금융사·금액은 가상.
실행: python -X utf8 scripts/build-finance.py  (메타데이터 + data/v5/finance-contracts.csv 생성)
"""
import csv
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parent.parent
ROOT = BASE / "force-app" / "main" / "default"
DATA = BASE / "data" / "v5"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
O = "Finance_Contract__c"
MATURITY_DAYS = 90

# (키, VIN, 차주 이메일 아이디(참고, 고객은 차량 차주로 자동 채움), 유형, 시작일, 만기일, 월 납입금, 잔존가치, 상태)
CONTRACTS = [
    ("FC-K1", "KAURNLSV0PA000303", "seoa", "리스", "2023-01-20", "2026-12-31", 890000, 21000000, "진행"),
    ("FC-K2", "KAURGTHB0PA000808", "dokyung", "장기렌트", "2023-04-10", "2027-01-09", 1150000, 18500000, "진행"),
    ("FC-K3", "KAURE5EV0RA000101", "haneul", "할부", "2024-03-15", "2029-03-15", 760000, None, "진행"),
    ("FC-K4", "KAURCTEV0RA000404", "jimin", "리스", "2024-11-08", "2027-11-08", 540000, 12800000, "진행"),
    ("FC-K5", "KAURCTEV0SA000707", "rin", "할부", "2025-09-01", "2028-09-01", 620000, None, "진행"),
    ("FC-K6", "KAURGTHB0LA000505", "minjun", "할부", "2020-05-10", "2025-05-10", 830000, None, "만기"),
]


def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(HEAD + text, encoding="utf-8", newline="\n")
    print("wrote", rel)


def field(name, label, body, desc=""):
    d = f"    <description>{escape(desc)}</description>\n" if desc else ""
    return (f"<CustomField {NS}>\n    <fullName>{name}</fullName>\n{d}    <label>{escape(label)}</label>\n"
            f"{body}</CustomField>\n")


def picklist(values, default_first=False):
    vals = "".join(f"            <value>\n                <fullName>{v}</fullName>\n"
                   f"                <default>{'true' if default_first and i == 0 else 'false'}</default>\n"
                   f"                <label>{v}</label>\n            </value>\n" for i, v in enumerate(values))
    return ("    <required>false</required>\n    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n"
            f"        <valueSetDefinition>\n            <sorted>false</sorted>\n{vals}        </valueSetDefinition>\n    </valueSet>\n")


def number(precision=12):
    return f"    <precision>{precision}</precision>\n    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n"


def lookup(ref, rel, label):
    return (f"    <deleteConstraint>SetNull</deleteConstraint>\n    <referenceTo>{ref}</referenceTo>\n"
            f"    <relationshipLabel>{escape(label)}</relationshipLabel>\n    <relationshipName>{rel}</relationshipName>\n"
            "    <required>false</required>\n    <type>Lookup</type>\n")


DATE = "    <required>false</required>\n    <type>Date</type>\n"

write(f"objects/{O}/{O}.object-meta.xml", f"""<CustomObject {NS}>
    <allowInChatterGroups>false</allowInChatterGroups>
    <compactLayoutAssignment>SYSTEM</compactLayoutAssignment>
    <deploymentStatus>Deployed</deploymentStatus>
    <description>차량 금융·리스 계약(v5). 만기 {MATURITY_DAYS}일 전이면 재구매 상담(Opportunity)을 자동으로 만든다(S-4).</description>
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
    <label>금융·리스 계약</label>
    <nameField>
        <displayFormat>FC-{{0000}}</displayFormat>
        <label>계약 번호</label>
        <trackHistory>false</trackHistory>
        <type>AutoNumber</type>
        <startingNumber>1</startingNumber>
    </nameField>
    <pluralLabel>금융·리스 계약</pluralLabel>
    <searchLayouts/>
    <sharingModel>ReadWrite</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
""")
write(f"objects/{O}/fields/Contract_Key__c.field-meta.xml", field(
    "Contract_Key__c", "계약 키",
    "    <caseSensitive>false</caseSensitive>\n    <externalId>true</externalId>\n    <length>40</length>\n"
    "    <required>false</required>\n    <type>Text</type>\n    <unique>true</unique>\n", "샘플 적재용 외부 ID(예: FC-K1)"))
write(f"objects/{O}/fields/Vehicle__c.field-meta.xml", field("Vehicle__c", "차량", lookup("Vehicle__c", "Finance_Contracts", "금융·리스 계약")))
write(f"objects/{O}/fields/Customer__c.field-meta.xml", field("Customer__c", "고객", lookup("Contact", "Finance_Contracts", "금융·리스 계약")))
write(f"objects/{O}/fields/Contract_Type__c.field-meta.xml", field("Contract_Type__c", "계약 유형", picklist(["할부", "리스", "장기렌트"])))
write(f"objects/{O}/fields/Finance_Company__c.field-meta.xml", field(
    "Finance_Company__c", "금융사", "    <length>80</length>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n", "가상"))
write(f"objects/{O}/fields/Start_Date__c.field-meta.xml", field("Start_Date__c", "시작일", DATE))
write(f"objects/{O}/fields/End_Date__c.field-meta.xml", field("End_Date__c", "만기일", DATE))
write(f"objects/{O}/fields/Monthly_Payment__c.field-meta.xml", field("Monthly_Payment__c", "월 납입금(원)", number()))
write(f"objects/{O}/fields/Residual_Value__c.field-meta.xml", field("Residual_Value__c", "잔존가치(원)", number(), "리스·장기렌트 만기 시 인수 금액"))
write(f"objects/{O}/fields/Status__c.field-meta.xml", field("Status__c", "계약 상태", picklist(["진행", "만기", "중도 해지"], True)))
write(f"objects/{O}/fields/Days_To_Maturity__c.field-meta.xml", field(
    "Days_To_Maturity__c", "만기까지(일)",
    "    <formula>IF(ISBLANK(End_Date__c), null, End_Date__c - TODAY())</formula>\n    <formulaTreatBlanksAs>BlankAsBlank</formulaTreatBlanksAs>\n"
    "    <precision>18</precision>\n    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n",
    "음수면 만기 지남"))
write(f"objects/{O}/fields/Maturity_Stage__c.field-meta.xml", field(
    "Maturity_Stage__c", "만기 단계",
    "    <formula>IF(TEXT(Status__c) &lt;&gt; '진행', '⏹ ' &amp; TEXT(Status__c),\n"
    "IF(ISBLANK(End_Date__c), '–',\n"
    "IF(End_Date__c &lt; TODAY(), '⏱ 만기 지남',\n"
    f"IF(End_Date__c - TODAY() &lt;= {MATURITY_DAYS}, '⏳ 만기 {MATURITY_DAYS}일 이내', '✓ 진행'))))</formula>\n"
    "    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>\n    <required>false</required>\n    <type>Text</type>\n    <unique>false</unique>\n",
    f"재구매 상담 대상 표시(만기 {MATURITY_DAYS}일 이내)"))

COLS = "".join(f"    <columns>{c}</columns>\n" for c in
               ["NAME", "Maturity_Stage__c", "Customer__c", "Vehicle__c", "Contract_Type__c", "End_Date__c", "Days_To_Maturity__c", "Monthly_Payment__c"])
write(f"objects/{O}/listViews/All.listView-meta.xml", f"""<ListView {NS}>
    <fullName>All</fullName>
{COLS}    <filterScope>Everything</filterScope>
    <label>전체</label>
</ListView>
""")
write(f"objects/{O}/listViews/Maturing.listView-meta.xml", f"""<ListView {NS}>
    <fullName>Maturing</fullName>
{COLS}    <filterScope>Everything</filterScope>
    <filters>
        <field>Status__c</field>
        <operation>equals</operation>
        <value>진행</value>
    </filters>
    <filters>
        <field>Days_To_Maturity__c</field>
        <operation>lessOrEqual</operation>
        <value>{MATURITY_DAYS}</value>
    </filters>
    <label>만기 {MATURITY_DAYS}일 이내</label>
</ListView>
""")


def items(fs):
    return "".join(f"            <layoutItems>\n                <behavior>{b}</behavior>\n                <field>{f}</field>\n"
                   "            </layoutItems>\n" for f, b in fs)


write(f"layouts/{O}-금융·리스 계약 레이아웃.layout-meta.xml", f"""<Layout {NS}>
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>계약</label>
        <layoutColumns>
{items([("Name", "Readonly"), ("Customer__c", "Edit"), ("Vehicle__c", "Edit"), ("Contract_Type__c", "Edit"), ("Finance_Company__c", "Edit"), ("Status__c", "Edit")])}        </layoutColumns>
        <layoutColumns>
{items([("Maturity_Stage__c", "Readonly"), ("Start_Date__c", "Edit"), ("End_Date__c", "Edit"), ("Days_To_Maturity__c", "Readonly"), ("Monthly_Payment__c", "Edit"), ("Residual_Value__c", "Edit")])}        </layoutColumns>
        <style>TwoColumnsTopToBottom</style>
    </layoutSections>
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>시스템</label>
        <layoutColumns>
{items([("Contract_Key__c", "Edit")])}        </layoutColumns>
        <style>OneColumn</style>
    </layoutSections>
    <showEmailCheckbox>false</showEmailCheckbox>
    <showHighlightsPanel>false</showHighlightsPanel>
    <showInteractionLogPanel>false</showInteractionLogPanel>
    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>
    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>
</Layout>
""")
write(f"tabs/{O}.tab-meta.xml", f"""<CustomTab {NS}>
    <customObject>true</customObject>
    <motif>Custom41: Bank</motif>
</CustomTab>
""")

DATA.mkdir(parents=True, exist_ok=True)
with open(DATA / "finance-contracts.csv", "w", encoding="utf-8", newline="\n") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["Contract_Key__c", "Vehicle__r.VIN__c", "Contract_Type__c", "Finance_Company__c",
                "Start_Date__c", "End_Date__c", "Monthly_Payment__c", "Residual_Value__c", "Status__c"])
    for k, vin, mail, typ, s, e, pay, res, st in CONTRACTS:
        w.writerow([k, vin, typ, "오로라파이낸셜(가상)", s, e, pay, "" if res is None else res, st])
print("wrote data/v5/finance-contracts.csv", len(CONTRACTS), "rows")
