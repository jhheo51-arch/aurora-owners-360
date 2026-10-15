"""권한 세트 Aurora_Owners_360_User와 Admin 프로필 부분 파일을 같은 필드 목록으로 생성한다."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "force-app" / "main" / "default"

# (오브젝트, 필드, 편집 가능). Master-Detail(Compensation__c.Case__c)은 FLS 대상이 아니라 제외.
FIELDS = [
    ("Vehicle__c", "VIN__c", True),
    ("Vehicle__c", "Owner_Contact__c", True),
    ("Vehicle__c", "Model__c", True),
    ("Vehicle__c", "Powertrain__c", True),
    ("Vehicle__c", "Model_Year__c", True),
    ("Vehicle__c", "Plate_Number__c", True),
    ("Vehicle__c", "Delivery_Date__c", True),
    ("Vehicle__c", "Mileage__c", True),
    ("Vehicle__c", "Service_Center__c", True),
    ("Vehicle__c", "Warranty_End_Date__c", False),
    ("Vehicle__c", "Battery_Warranty_End_Date__c", False),
    ("Vehicle__c", "Display_Name__c", False),
    ("Vehicle__c", "Vehicle_Model__c", True),
    ("Vehicle__c", "Lemon_Law_Status__c", False),
    ("Vehicle__c", "Lemon_Law_Basis__c", False),
    ("Vehicle__c", "Repeat_Defect__c", False),
    ("Vehicle__c", "Repeat_Defect_System__c", False),
    ("Vehicle_Model__c", "Model_Code__c", True),
    ("Vehicle_Model__c", "Model_Line__c", True),
    ("Vehicle_Model__c", "Powertrain__c", True),
    ("Vehicle_Model__c", "Trim__c", True),
    ("Vehicle_Model__c", "Battery_Capacity_kWh__c", True),
    ("Vehicle_Model__c", "Base_Price__c", True),
    ("Vehicle_Model__c", "General_Warranty_Months__c", True),
    ("Vehicle_Model__c", "General_Warranty_Km__c", True),
    ("Vehicle_Model__c", "Powertrain_Warranty_Months__c", True),
    ("Vehicle_Model__c", "Powertrain_Warranty_Km__c", True),
    ("Vehicle_Model__c", "Battery_Warranty_Months__c", True),
    ("Vehicle_Model__c", "Battery_Warranty_Km__c", True),
    ("Vehicle_Model__c", "Maintenance_Interval_Months__c", True),
    ("Vehicle_Model__c", "Maintenance_Interval_Km__c", True),
    ("Case", "VOC_Status__c", True),
    ("Case", "VOC_Category__c", True),
    ("Case", "Warranty_Scope__c", True),
    ("Case", "Vehicle__c", True),
    ("Case", "Advisor__c", True),
    ("Case", "Manager_Employee__c", True),
    ("Case", "Current_Handler__c", True),
    ("Case", "Needs_Manager__c", True),
    ("Case", "Assistance_Reason__c", True),
    ("Case", "Response_Due_At__c", True),
    ("Case", "First_Response_At__c", True),
    ("Case", "Escalation_Status__c", True),
    ("Case", "Escalation_Reason__c", True),
    ("Case", "Escalated_At__c", True),
    ("Case", "VOC_Key__c", True),
    ("Case", "SLA_Met__c", False),
    ("Case", "Under_Warranty__c", False),
    ("Case", "Total_Compensation__c", False),
    ("Case", "Pending_High_Value_Count__c", False),
    ("Case", "Pending_Extension_Count__c", False),
    ("Case", "Pending_Approval_Count__c", False),
    ("Case", "VOC_Status_Display__c", False),
    ("Case", "Response_Due_KST__c", False),
    ("Case", "First_Response_KST__c", False),
    ("Case", "Escalated_KST__c", False),
    ("Case", "AI_Outcome__c", True),
    ("Case", "Handoff_Reason__c", True),
    ("Case", "CSAT__c", True),
    ("Case", "AI_Wiki__c", True),
    ("Vehicle__c", "Vehicle_Status_Display__c", False),
    ("Compensation__c", "Compensation_Type__c", True),
    ("Compensation__c", "Amount__c", True),
    ("Compensation__c", "Reason__c", True),
    ("Compensation__c", "Approval_Status__c", True),
    ("Compensation__c", "Approver__c", True),
    ("Compensation__c", "Compensation_Key__c", True),
    ("Compensation__c", "Needs_Approval__c", False),
    ("Compensation__c", "Approved_At__c", True),
    ("Compensation__c", "Decision_Note__c", True),
    ("Compensation__c", "Approval_Level__c", False),
    ("Care_Staff__c", "Staff_Number__c", True),
    ("Care_Staff__c", "Role__c", True),
    ("Care_Staff__c", "Manager__c", True),
    ("Care_Staff__c", "Work_Email__c", True),
    ("Care_Staff__c", "Active__c", True),
]

# v3부터는 오브젝트 폴더의 필드를 자동으로 읽는다: 수식·롤업은 읽기 전용, Master-Detail은 FLS 대상 아님
AUTO_OBJECTS = ["Vehicle_Warranty__c", "Vehicle_Party__c", "Part__c", "Failure_Mode__c", "Case_Part__c", "Service_Visit__c", "Recall_Alert__c"]
EXTRA_FIELDS = [("Case", f) for f in ["Failure_Mode__c", "Proposed_Failure_Mode__c", "Root_Cause__c",
                                      "Resolution__c", "Resolution_Method__c", "Self_Solvable__c", "Recall_Alert__c"]] + \
               [("Account", "Customer_Segment__c"), ("Account", "Aurora_Key__c"),
                ("Contact", "Contact_Role__c"), ("Contact", "Aurora_Key__c")]


APEX_CLASSES = ["CustomerTimelineController", "SimilarCaseService", "Aurora3dController", "AuroraCardController",
                "AuroraSimilarCasesAction", "AuroraLemonCheckAction", "AuroraEscalationAction", "AuroraAgentSupport",
                "AicxController", "AicxRoutingService", "AicxSelfHelpService", "AuroraOwnerBoardController", "AuroraRagService", "AuroraRagAnswerAction", "AuroraRecordFinder", "AuroraWorkQueryAction"]
READONLY_EXTRA = [("Case", "Alert_Codes_Sent__c"), ("Compensation__c", "Alert_Codes_Sent__c"), ("Case", "Warranty_Coverage__c"), ("Case", "Applied_Warranty__c"), ("Contact", "VOC_Count_90d__c"), ("Contact", "Risk_Score__c"), ("Contact", "Risk_Level__c")]


def class_access():
    return "".join(
        "    <classAccesses>\n"
        f"        <apexClass>{c}</apexClass>\n"
        "        <enabled>true</enabled>\n"
        "    </classAccesses>\n" for c in APEX_CLASSES)


def scan_fields():
    found = [(o, f, False) for o, f in READONLY_EXTRA]
    for obj, field in EXTRA_FIELDS:
        found.append((obj, field, True))
    for obj in AUTO_OBJECTS:
        for f in sorted((ROOT / "objects" / obj / "fields").glob("*.field-meta.xml")):
            xml = f.read_text(encoding="utf-8")
            if "<type>MasterDetail</type>" in xml:
                continue
            found.append((obj, f.name.split(".")[0], "<formula>" not in xml and "<type>Summary</type>" not in xml))
    return found


FIELDS = FIELDS + scan_fields()

NEW_TABS = ["Vehicle__c", "Compensation__c", "Care_Staff__c", "Vehicle_Model__c",
            "Vehicle_Party__c", "Part__c", "Failure_Mode__c", "Case_Part__c", "Service_Visit__c", "Vehicle_Warranty__c", "Recall_Alert__c", "Aurora_AI_Care_Demo", "Aurora_Owners_Vehicles"]
APP = "Aurora_Owners_360"
AGENT = "Aurora_Care_Copilot"


def field_perms():
    out = []
    for obj, field, editable in sorted(FIELDS):
        out.append(
            "    <fieldPermissions>\n"
            f"        <editable>{str(editable).lower()}</editable>\n"
            f"        <field>{obj}.{field}</field>\n"
            "        <readable>true</readable>\n"
            "    </fieldPermissions>"
        )
    return "\n".join(out)


def object_perm(obj, read, create, edit, delete, view_all, modify_all):
    b = lambda v: str(v).lower()
    return (
        "    <objectPermissions>\n"
        f"        <allowCreate>{b(create)}</allowCreate>\n"
        f"        <allowDelete>{b(delete)}</allowDelete>\n"
        f"        <allowEdit>{b(edit)}</allowEdit>\n"
        f"        <allowRead>{b(read)}</allowRead>\n"
        f"        <modifyAllRecords>{b(modify_all)}</modifyAllRecords>\n"
        f"        <object>{obj}</object>\n"
        f"        <viewAllRecords>{b(view_all)}</viewAllRecords>\n"
        "    </objectPermissions>"
    )


def permission_set():
    objs = [
        object_perm("Care_Staff__c", True, False, False, False, False, False),
        object_perm("Case", True, True, True, False, False, False),
        object_perm("Compensation__c", True, True, True, True, False, False),
        object_perm("Contact", True, False, False, False, False, False),
        object_perm("Vehicle__c", True, True, True, True, False, False),
        object_perm("Vehicle_Model__c", True, False, False, False, False, False),
    ] + [object_perm(o, True, True, True, True, False, False) for o in AUTO_OBJECTS]
    tabs = "\n".join(
        "    <tabSettings>\n"
        f"        <tab>{t}</tab>\n"
        "        <visibility>Visible</visibility>\n"
        "    </tabSettings>"
        for t in sorted(NEW_TABS)
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        # v4 직원용 Agent 접근(실습 Agent는 건드리지 않음)
        "    <agentAccesses>\n"
        f"        <agentName>{AGENT}</agentName>\n"
        "        <enabled>true</enabled>\n"
        "    </agentAccesses>\n"
        "    <applicationVisibilities>\n"
        f"        <application>{APP}</application>\n"
        "        <visible>true</visible>\n"
        "    </applicationVisibilities>\n"
        + class_access() +
        "    <description>오로라 오너스 360 상담원·팀장용: 고객 차량·보상·조치 전체, VOC(Case) 생성·편집, 연락처·상담 직원 읽기</description>\n"
        f"{field_perms()}\n"
        "    <hasActivationRequired>false</hasActivationRequired>\n"
        "    <label>오로라 오너스 360 사용자</label>\n"
        + "\n".join(objs) + "\n"
        f"{tabs}\n"
        "</PermissionSet>\n"
    )


def admin_profile():
    objs = [
        object_perm("Care_Staff__c", True, True, True, True, True, True),
        object_perm("Compensation__c", True, True, True, True, True, True),
        object_perm("Vehicle__c", True, True, True, True, True, True),
        object_perm("Vehicle_Model__c", True, True, True, True, True, True),
    ] + [object_perm(o, True, True, True, True, True, True) for o in AUTO_OBJECTS]
    tabs = "\n".join(
        "    <tabVisibilities>\n"
        f"        <tab>{t}</tab>\n"
        "        <visibility>DefaultOn</visibility>\n"
        "    </tabVisibilities>"
        for t in sorted(NEW_TABS)
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Profile xmlns="http://soap.sforce.com/2006/04/metadata">\n'
        "    <applicationVisibilities>\n"
        f"        <application>{APP}</application>\n"
        "        <default>false</default>\n"
        "        <visible>true</visible>\n"
        "    </applicationVisibilities>\n"
        + class_access() +
        "    <custom>false</custom>\n"
        f"{field_perms()}\n"
        + "\n".join(objs) + "\n"
        f"{tabs}\n"
        "</Profile>\n"
    )


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {path.relative_to(ROOT.parent.parent.parent)}")


if __name__ == "__main__":
    write(ROOT / "permissionsets" / "Aurora_Owners_360_User.permissionset-meta.xml", permission_set())
    write(ROOT / "profiles" / "Admin.profile-meta.xml", admin_profile())
    print(f"field permissions: {len(FIELDS)}")
