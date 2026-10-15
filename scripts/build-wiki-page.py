"""고장 위키 전용 레코드 페이지 Aurora_Wiki_Record_Page (2026-10-15).
위키 상세 위에 '이 고장의 VOC와 조치 내역'(해결 방식·원인·해결 방법) 표를 둔다.
Failure_Mode__c는 오로라 전용 오브젝트라 오브젝트 기본 View 페이지로 지정한다(Failure_Mode__c.object-meta.xml actionOverrides).
build-pages.py의 공용 함수를 재사용한다.
실행: python -X utf8 scripts/build-wiki-page.py
"""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("build_pages", HERE / "build-pages.py")
bp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bp)

actions = bp.aurora_related_list(
    "wiki_actions", "이 고장의 VOC와 조치 내역", "standard:case", "Cases__r", "Case", "Failure_Mode__c",
    ["CaseNumber", "VOC_Status_Display__c", "Subject", "Vehicle__r.Name", "Resolution_Method__c", "Root_Cause__c", "Resolution__c"],
    "이 고장 유형으로 접수된 VOC가 아직 없습니다.")
main = [actions, bp.component("force:detailPanel", "force_detailPanel", [])]
sidebar = [bp.related_container()]
xml = bp.page("오로라 고장 위키 레코드 페이지", "Failure_Mode__c", [bp.highlights()], main, sidebar, [])
out = bp.OUT / "Aurora_Wiki_Record_Page.flexipage-meta.xml"
out.write_text(xml, encoding="utf-8", newline="\n")
print("wrote", out.name)

obj = HERE.parent / "force-app" / "main" / "default" / "objects" / "Failure_Mode__c" / "Failure_Mode__c.object-meta.xml"
t = obj.read_text(encoding="utf-8")
override = """    <actionOverrides>
        <actionName>View</actionName>
        <comment>오로라 고장 위키 레코드 페이지(조치 내역 표)</comment>
        <content>Aurora_Wiki_Record_Page</content>
        <formFactor>Large</formFactor>
        <skipRecordTypeSelect>false</skipRecordTypeSelect>
        <type>Flexipage</type>
    </actionOverrides>
"""
if "Aurora_Wiki_Record_Page" not in t:
    t = t.replace('<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n',
                  '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n' + override, 1)
    obj.write_text(t, encoding="utf-8", newline="\n")
    print("override added")
