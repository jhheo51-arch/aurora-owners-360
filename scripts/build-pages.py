"""오로라 앱 전용 Lightning 레코드 페이지(Case VOC, Contact 차주)를 생성한다."""
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).resolve().parent.parent / "force-app" / "main" / "default" / "flexipages"

# 섹션: (라벨, 왼쪽 열, 오른쪽 열, 표시 조건). 필드는 (API, readonly 여부). 오른쪽 열이 None이면 1열 섹션.
# 표시 조건: None 또는 (booleanFilter, [(필드, 연산자, 값), ...]) — 오로라 페이지 안에서만 쓰는 조건부 표시(v3.5 S4)
ESCALATED = ("1 OR 2", [("Needs_Manager__c", "EQUAL", "true"), ("Escalation_Status__c", "EQUAL", "요청")])
HAS_COMPENSATION = ("1 OR 2", [("Total_Compensation__c", "GT", "0"), ("Pending_Approval_Count__c", "GT", "0")])
SAFETY = (None, [("VOC_Category__c", "EQUAL", "안전 결함")])

# VOC 탭: (id, 제목, 섹션). 같은 필드는 페이지에 한 번만(함정 4). [3D] 탭은 S7에서 추가.
CASE_TABS = [
    ("process", "처리", [
        ("① 접수",
         [("Subject", False), ("ContactId", False), ("Vehicle__c", False)],
         [("VOC_Category__c", False), ("Priority", False), ("Origin", False)], None),
        ("② 확인·처리",
         [("Advisor__c", False), ("Current_Handler__c", True), ("Needs_Manager__c", False)],
         [("VOC_Status__c", False), ("First_Response_At__c", False)], None),
        ("↑ 팀장 이관 (이관 요청일 때만 표시)",
         [("Manager_Employee__c", False), ("Assistance_Reason__c", False)],
         [("Escalation_Status__c", False), ("Escalation_Reason__c", False), ("Escalated_At__c", False)], ESCALATED),
        ("③ 해결 정보 (고장 위키)",
         [("Failure_Mode__c", False), ("Proposed_Failure_Mode__c", False), ("Root_Cause__c", False)],
         [("Resolution_Method__c", False), ("Self_Solvable__c", False), ("Resolution__c", False)], None),
        ("④ 종결 만족도 (선택 — 종결 통화에서 받은 1~5점, 고객 건강 점수에 반영)",
         [("CSAT__c", False)], None, None),
        ("🔒 자동 계산 (Flow·Apex — 직접 고치지 않음)",
         [("Response_Due_At__c", True), ("SLA_Met__c", True)],
         [("VOC_Status_Display__c", True)], None),
    ]),
    ("vehicle", "차량·보증", [
        ("보증 판정",
         [("Warranty_Scope__c", False), ("Warranty_Coverage__c", True)],
         [("Applied_Warranty__c", True)], None),
    ]),
    ("comp", "보상", [
        ("보상 요약 (보상이 있을 때만 표시)",
         [("Total_Compensation__c", True)],
         [("Pending_Approval_Count__c", True)], HAS_COMPENSATION),
    ]),
    ("history", "이력", []),
    ("threed", "3D", []),
    ("detail", "상세", [
        ("상세 내용", [("Description", False)], None, None),
        ("시스템 정보",
         [("CaseNumber", True), ("Status", True), ("VOC_Key__c", False), ("CreatedDate", True)],
         [("OwnerId", False), ("CreatedById", True), ("LastModifiedById", True)], None),
    ]),
]

SAFETY_GUIDE = (
    '<p><b style="color:#B3261E">⚠ 안전 결함 대응</b> (안전 결함 VOC에만 표시)</p>'
    "<ol><li>저장 즉시 상담팀장 이관 — 자동(Flow)</li>"
    "<li>품질·안전 대응 담당에게 공유</li>"
    "<li>차주에게 운행 자제 안내, 필요하면 견인 입고</li>"
    "<li>대차 지원 등 보상은 [보상] 탭에서 등록</li></ol>"
)

VEHICLE_SIGNAL_SECTIONS = [
    ("품질 신호 (Apex 자동 판정)",
     [("Vehicle_Status_Display__c", True), ("Repeat_Defect__c", True), ("Repeat_Defect_System__c", True)],
     [("Lemon_Law_Status__c", True), ("Lemon_Law_Basis__c", True)], None),
]
VEHICLE_DETAIL_SECTIONS = [
    ("차량",
     [("Name", True), ("Display_Name__c", False), ("Vehicle_Model__c", False), ("Model__c", False), ("Model_Year__c", False)],
     [("Owner_Contact__c", False), ("Plate_Number__c", False), ("VIN__c", False), ("Powertrain__c", False)], None),
    ("운행·보증",
     [("Mileage__c", False), ("Delivery_Date__c", False), ("Preferred_Center__c", False)],
     [("Warranty_End_Date__c", False), ("Battery_Warranty_End_Date__c", False), ("Selling_Dealer__c", False)], None),
    ("시스템 정보", [("OwnerId", False), ("CreatedById", True)], [("LastModifiedById", True)], None),
]


def prop(name, value):
    return (
        "                <componentInstanceProperties>\n"
        f"                    <name>{name}</name>\n"
        f"                    <value>{escape(str(value))}</value>\n"
        "                </componentInstanceProperties>\n"
    )


def visibility(rule):
    if not rule:
        return ""
    bool_filter, criteria = rule
    out = "                <visibilityRule>\n"
    if bool_filter:
        out += f"                    <booleanFilter>{bool_filter}</booleanFilter>\n"
    for fld, op, val in criteria:
        out += (
            "                    <criteria>\n"
            f"                        <leftValue>{{!Record.{fld}}}</leftValue>\n"
            f"                        <operator>{op}</operator>\n"
            f"                        <rightValue>{escape(val)}</rightValue>\n"
            "                    </criteria>\n"
        )
    return out + "                </visibilityRule>\n"


def component(name, ident, props, rule=None):
    return (
        "        <itemInstances>\n"
        "            <componentInstance>\n"
        + "".join(prop(k, v) for k, v in props)
        + f"                <componentName>{name}</componentName>\n"
        f"                <identifier>{ident}</identifier>\n"
        + visibility(rule)
        + "            </componentInstance>\n"
        "        </itemInstances>\n"
    )


def field(api, readonly):
    behavior = "readonly" if readonly else "none"
    return (
        "        <itemInstances>\n"
        "            <fieldInstance>\n"
        "                <fieldInstanceProperties>\n"
        "                    <name>uiBehavior</name>\n"
        f"                    <value>{behavior}</value>\n"
        "                </fieldInstanceProperties>\n"
        f"                <fieldItem>Record.{api}</fieldItem>\n"
        f"                <identifier>Record{api.replace('__', '_')}Field</identifier>\n"
        "            </fieldInstance>\n"
        "        </itemInstances>\n"
    )


def region(name, items, rtype="Facet", mode=None):
    # 상위 FlexiPage를 상속하지 않는 독립 페이지라 <mode>는 쓰지 않는다.
    return (
        "    <flexiPageRegions>\n"
        + "".join(items)
        + f"        <name>{name}</name>\n"
        f"        <type>{rtype}</type>\n"
        "    </flexiPageRegions>\n"
    )


def related_list(ident, parent, rel_api):
    # 주의: 이 표준 컴포넌트는 페이지 레이아웃에 있는 관련 목록만 렌더링한다
    return component("force:relatedListSingleContainer", ident, [
        ("parentFieldApiName", parent),
        ("relatedListApiName", rel_api),
        ("relatedListComponentOverride", "NONE"),
        ("rowsToDisplay", "10"),
        ("showActionBar", "true"),
    ])


def aurora_related_list(ident, title, icon, rel_api, child, parent_field, fields, empty):
    """auroraRelatedList LWC. Case 레이아웃(org 공용)에 없는 관련 목록용 —
    표준 단일·동적 관련 목록은 런타임에 레이아웃에 없는 Case 관련 목록을 그리지 않았다(v3.5 S4 확인)."""
    return component("auroraRelatedList", ident, [
        ("childObject", child),
        ("emptyMessage", empty),
        ("fields", ",".join(fields)),
        ("iconName", icon),
        ("parentField", parent_field),
        ("relatedListId", rel_api),
        ("title", title),
    ])


def highlights():
    return component("force:highlightsPanel", "force_highlightsPanel", [
        ("collapsed", "false"),
        ("enableActionsConfiguration", "false"),
        ("enableActionsInNative", "false"),
        ("hideChatterActions", "false"),
        ("numVisibleActions", "3"),
    ])


def tabset(tabs):
    """tabs: [(id, 제목, items)]. 첫 탭이 기본 선택."""
    regions, tab_items = [], []
    for i, (tid, title, items) in enumerate(tabs):
        body = f"{tid}TabContent"
        regions.append(region(body, items))
        tab_props = ([("active", "true")] if i == 0 else []) + [("body", body), ("title", title)]
        tab_items.append(component("flexipage:tab", f"{tid}Tab", tab_props))
    regions.append(region("maintabs", tab_items))
    return regions, component("flexipage:tabset", "flexipage_tabset", [("label", "Tabs"), ("tabs", "maintabs")])


def field_sections(prefix, sections, regions):
    """Dynamic Forms 필드 섹션 컴포넌트 목록을 만들고, 필요한 Facet 영역을 regions에 추가."""
    comps = []
    for i, (label, left, right, rule) in enumerate(sections, start=1):
        cols = []
        for j, col in enumerate([left] + ([right] if right else []), start=1):
            facet = f"Facet-{prefix}-s{i}-c{j}"
            regions.append(region(facet, [field(a, ro) for a, ro in col]))
            cols.append(component("flexipage:column", f"flexipage_column_{prefix}_s{i}_c{j}", [("body", facet)]))
        cols_facet = f"Facet-{prefix}-s{i}-cols"
        regions.append(region(cols_facet, cols))
        comps.append(component("flexipage:fieldSection", f"flexipage_fieldSection_{prefix}_{i}", [
            ("columns", cols_facet), ("horizontalAlignment", "false"), ("label", label)], rule))
    return comps


def related_container():
    return component("force:relatedListContainer", "force_relatedListContainer", [
        ("relatedListComponentOverride", "NONE"), ("rowsToDisplay", "10"), ("showActionBar", "true")])


def page(label, sobject, header, main, sidebar, extra_regions):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        + region("header", header, rtype="Region", mode="Replace")
        + "".join(extra_regions)
        + region("main", main, rtype="Region", mode="Replace")
        + region("sidebar", sidebar, rtype="Region", mode="Replace")
        + f"    <masterLabel>{label}</masterLabel>\n"
        f"    <sobjectType>{sobject}</sobjectType>\n"
        "    <template>\n"
        "        <name>flexipage:recordHomeTemplateDesktop</name>\n"
        "    </template>\n"
        "    <type>RecordPage</type>\n"
        "</FlexiPage>\n"
    )


def case_page():
    regions, tabs = [], []
    for tid, title, sections in CASE_TABS:
        items = field_sections(f"case_{tid}", sections, regions)
        if tid == "process":
            items.insert(0, component("flexipage:richText", "safety_guide", [
                ("decorate", "true"), ("richTextValue", SAFETY_GUIDE)], SAFETY))
        elif tid == "vehicle":
            items += [
                aurora_related_list("case_parts_related", "VOC 부품", "standard:product", "Case_Parts__r",
                                    "Case_Part__c", "Case__c", ["Name", "Part__r.Name", "Role__c"],
                                    "연결된 부품이 없습니다."),
                aurora_related_list("service_visits_related", "정비 이력", "standard:maintenance_plan",
                                    "Service_Visits__r", "Service_Visit__c", "Case__c",
                                    ["Name", "Check_In_Date__c", "Visit_Type__c", "Defect_System__c", "Main_Part__r.Name"],
                                    "이 VOC로 입고한 정비가 없습니다."),
            ]
        elif tid == "comp":
            items.append(aurora_related_list(
                "compensations_related", "보상·조치", "standard:currency", "Compensations__r", "Compensation__c",
                "Case__c", ["Name", "Compensation_Type__c", "Amount__c", "Approval_Status__c", "Approver__r.Name"],
                "보상·조치가 없습니다. [새로 만들기]로 등록하세요."))
        elif tid == "threed":
            items.append(component("aurora3dVehicle", "c_aurora3dVehicle", []))
        elif tid == "history":
            items += [component("runtime_sales_activities:activityPanel", "activityPanel", []), related_container()]
        tabs.append((tid, title, items))
    tab_regions, tabset_comp = tabset(tabs)
    path = component("runtime_sales_pathassistant:pathAssistant", "runtime_sales_pathassistant_pathAssistant", [
        ("hideUpdateButton", "false"), ("variant", "linear")])
    # v4: 코파일럿 이관 액션을 확인 화면 Flow로도 제공(Agent 라우터가 '이관' 요청을 막는 문제의 대안). 미이관·진행 중 VOC만
    escalate = component("flowruntime:interview", "aurora_copilot_escalation", [
        ("flowArguments", '[{"label":"recordId","dataType":"String","supportsRecordId":true,"value":"{!Record.Id}"}]'),
        ("flowLayout", "oneColumn"),
        ("flowName", "Aurora_Copilot_Escalation"),
    ], ("1 AND 2", [("Escalation_Status__c", "NE", "요청"), ("VOC_Status__c", "NE", "종결")]))
    sidebar = [component("auroraSimilarCases", "c_auroraSimilarCases", []), escalate]
    situation = component("auroraVocSituation", "c_auroraVocSituation", [])
    return page("오로라 VOC 레코드 페이지", "Case", [highlights(), situation], [path, tabset_comp], sidebar, regions + tab_regions)


def contact_page():
    # Contact 레이아웃도 org 공용이라 auroraRelatedList 사용
    overview = [
        aurora_related_list("owned_vehicles_related", "보유 차량", "custom:custom31", "Owned_Vehicles__r",
                            "Vehicle__c", "Owner_Contact__c",
                            ["Name", "Vehicle_Status_Display__c", "Vehicle_Model__r.Name", "Plate_Number__c", "Mileage__c"],
                            "보유 차량이 없습니다."),
        aurora_related_list("cases_related", "VOC 이력", "standard:case", "Cases", "Case", "ContactId",
                            ["CaseNumber", "VOC_Status_Display__c", "Subject", "VOC_Category__c", "VOC_Status__c",
                             "Current_Handler__r.Name"],
                            "VOC가 없습니다."),
    ]
    tab_regions, tabs = tabset([
        ("overview", "개요", overview),
        ("detail", "상세", [component("force:detailPanel", "force_detailPanel", [])]),
        ("related", "관련", [related_container()]),
    ])
    sidebar = [component("auroraTimeline", "c_auroraTimeline", [])]
    owner360 = component("auroraOwner360", "c_auroraOwner360", [])
    return page("오로라 차주 레코드 페이지", "Contact", [highlights(), owner360], [tabs], sidebar, tab_regions)


def vehicle_page():
    regions = []
    overview = field_sections("veh_sig", VEHICLE_SIGNAL_SECTIONS, regions) + [
        component("auroraWarrantyGauge", "c_auroraWarrantyGauge", []),
        component("aurora3dVehicle", "c_aurora3dVehicle", []),
        related_list("warranties_related", "Vehicle__c.Id", "Warranties__r"),
        related_list("service_visits_related", "Vehicle__c.Id", "Service_Visits__r"),
        related_list("voc_cases_related", "Vehicle__c.Id", "VOC_Cases__r"),
    ]
    detail = field_sections("veh_detail", VEHICLE_DETAIL_SECTIONS, regions)
    tab_regions, tabs = tabset([
        ("overview", "개요", overview),
        ("detail", "상세", detail),
        ("related", "관련", [related_container()]),
    ])
    # v5: 서비스센터 혼잡도(담당 센터 먼저) → 통합 타임라인
    sidebar = [component("auroraCenterLoad", "c_auroraCenterLoad", []), component("auroraTimeline", "c_auroraTimeline", [])]
    badges = component("auroraStatusBadges", "c_auroraStatusBadges", [])
    return page("오로라 차량 레코드 페이지", "Vehicle__c", [highlights(), badges], [tabs], sidebar, regions + tab_regions)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, text in [("Aurora_VOC_Record_Page", case_page()), ("Aurora_Owner_Record_Page", contact_page()),
                       ("Aurora_Vehicle_Record_Page", vehicle_page())]:
        p = OUT / f"{name}.flexipage-meta.xml"
        p.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {p.name}")
