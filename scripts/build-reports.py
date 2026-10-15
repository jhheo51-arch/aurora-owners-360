"""홈 차트용 '오로라 VOC' 리포트 폴더와 리포트 3개를 생성한다. 오로라 VOC = 담당 상담원이 있는 Case."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "force-app" / "main" / "default" / "reports"
FOLDER = "Aurora_VOC"

AURORA_FILTER = ("Case.Advisor__c", "notEqual", "")
REPORTS = [
    {
        "name": "Aurora_VOC_By_Category", "label": "VOC 유형별 건수",
        "description": "오로라 VOC 전체를 유형별로 센다",
        "group": "Case.VOC_Category__c", "chart": "HorizontalBar",
        "filters": [AURORA_FILTER],
    },
    {
        "name": "Aurora_Open_VOC_By_Advisor", "label": "담당 상담원별 진행 중",
        "description": "종결되지 않은 오로라 VOC를 담당 상담원별로 센다(업무량)",
        "group": "Case.Advisor__c", "chart": "HorizontalBar",
        "filters": [AURORA_FILTER, ("Case.VOC_Status__c", "notEqual", "종결")],
    },
    {
        "name": "Aurora_SLA_Status", "label": "기한 준수 현황",
        "description": "첫 응답이 있는 오로라 VOC의 응답 기한 준수 여부",
        "group": "Case.SLA_Met__c", "chart": "Donut",
        "filters": [AURORA_FILTER, ("Case.First_Response_At__c", "notEqual", "")],
    },
]
COLUMNS = ["CASE_NUMBER", "SUBJECT", "Case.VOC_Category__c", "Case.VOC_Status__c", "Case.Advisor__c",
           "Case.Response_Due_At__c", "Case.SLA_Met__c"]


def report_xml(r):
    donut = r["chart"] == "Donut"
    cols = "".join(f"    <columns>\n        <field>{c}</field>\n    </columns>\n" for c in COLUMNS if c != r["group"])
    filters = "".join(
        "        <criteriaItems>\n"
        f"            <column>{c}</column>\n"
        "            <columnToColumn>false</columnToColumn>\n"
        "            <isUnlocked>true</isUnlocked>\n"
        f"            <operator>{op}</operator>\n"
        f"            <value>{v}</value>\n"
        "        </criteriaItems>\n"
        for c, op, v in r["filters"])
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <chart>
        <backgroundColor1>#FFFFFF</backgroundColor1>
        <backgroundColor2>#FFFFFF</backgroundColor2>
        <backgroundFadeDir>Diagonal</backgroundFadeDir>
        <chartSummaries>
            <axisBinding>y</axisBinding>
            <column>RowCount</column>
        </chartSummaries>
        <chartType>{r["chart"]}</chartType>
        <enableHoverLabels>true</enableHoverLabels>
        <expandOthers>true</expandOthers>
        <groupingColumn>{r["group"]}</groupingColumn>
{"        <legendPosition>Right</legendPosition>" + chr(10) if donut else ""}        <location>CHART_BOTTOM</location>
        <showAxisLabels>{str(not donut).lower()}</showAxisLabels>
        <showPercentage>{str(donut).lower()}</showPercentage>
        <showTotal>{str(donut).lower()}</showTotal>
        <showValues>true</showValues>
        <size>Medium</size>
        <summaryAxisRange>Auto</summaryAxisRange>
        <textColor>#000000</textColor>
        <textSize>12</textSize>
        <titleColor>#000000</titleColor>
        <titleSize>18</titleSize>
    </chart>
{cols}    <description>{r["description"]}</description>
    <filter>
{filters}    </filter>
    <format>Summary</format>
    <groupingsDown>
        <dateGranularity>Day</dateGranularity>
        <field>{r["group"]}</field>
        <sortOrder>Asc</sortOrder>
    </groupingsDown>
    <name>{r["label"]}</name>
    <params>
        <name>units</name>
        <value>h</value>
    </params>
    <reportType>CaseList</reportType>
    <scope>organization</scope>
    <showDetails>true</showDetails>
    <showGrandTotal>true</showGrandTotal>
    <showSubTotals>true</showSubTotals>
    <timeFrameFilter>
        <dateColumn>CREATED_DATEONLY</dateColumn>
        <interval>INTERVAL_CUSTOM</interval>
    </timeFrameFilter>
</Report>
"""


if __name__ == "__main__":
    (OUT / FOLDER).mkdir(parents=True, exist_ok=True)
    (OUT / f"{FOLDER}.reportFolder-meta.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<ReportFolder xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        "    <accessType>Public</accessType>\n"
        "    <name>오로라 VOC</name>\n"
        "    <publicFolderAccess>ReadWrite</publicFolderAccess>\n"
        "</ReportFolder>\n", encoding="utf-8", newline="\n")
    for r in REPORTS:
        (OUT / FOLDER / f"{r['name']}.report-meta.xml").write_text(report_xml(r), encoding="utf-8", newline="\n")
        print(f"wrote {FOLDER}/{r['name']}")
