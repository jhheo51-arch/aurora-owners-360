"""정비 이력·차량 보증 전용 레코드 페이지 (2026-10-15).
왼쪽: 레코드 상세(레이아웃) / 오른쪽: 같은 차량의 형제 레코드 목록 LWC
- Aurora_Service_Visit_Record_Page: auroraVisitHistory(같은 차량 정비 이력, 입고일 최신순)
- Aurora_Warranty_Record_Page: auroraWarrantySiblings(같은 차량 보증, 만료일 순)
두 오브젝트 모두 오로라 전용이라 오브젝트 기본 View 페이지로 지정한다.
실행: python -X utf8 scripts/build-visit-page.py
"""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("build_pages", HERE / "build-pages.py")
bp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bp)

PAGES = [
    ("Service_Visit__c", "Aurora_Service_Visit_Record_Page", "오로라 정비 이력 레코드 페이지", "auroraVisitHistory",
     "오로라 정비 이력 레코드 페이지(같은 차량 정비 이력)"),
    ("Vehicle_Warranty__c", "Aurora_Warranty_Record_Page", "오로라 차량 보증 레코드 페이지", "auroraWarrantySiblings",
     "오로라 차량 보증 레코드 페이지(같은 차량 보증)"),
]

for obj, page_name, label, lwc, comment in PAGES:
    main = [bp.component("force:detailPanel", "force_detailPanel", []), bp.related_container()]
    sidebar = [bp.component(lwc, f"c_{lwc}", [])]
    out = bp.OUT / f"{page_name}.flexipage-meta.xml"
    out.write_text(bp.page(label, obj, [bp.highlights()], main, sidebar, []), encoding="utf-8", newline="\n")
    print("wrote", out.name)

    meta = HERE.parent / "force-app" / "main" / "default" / "objects" / obj / f"{obj}.object-meta.xml"
    t = meta.read_text(encoding="utf-8")
    if page_name not in t:
        override = (
            "    <actionOverrides>\n        <actionName>View</actionName>\n"
            f"        <comment>{comment}</comment>\n        <content>{page_name}</content>\n"
            "        <formFactor>Large</formFactor>\n        <skipRecordTypeSelect>false</skipRecordTypeSelect>\n"
            "        <type>Flexipage</type>\n    </actionOverrides>\n")
        t = t.replace('<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n',
                      '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n' + override, 1)
        meta.write_text(t, encoding="utf-8", newline="\n")
        print("override added", obj)
