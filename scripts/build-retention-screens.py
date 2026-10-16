"""v5 S-6 화면 연결: 연락처 리스트 뷰 '오로라 건강 주의 차주' + 오로라 홈 가운데 열 카드 2개(재구매 상담·건강 주의 차주).
Aurora_Home은 생성기 없이 관리하는 파일이라 카드만 끼워 넣는다(이미 있으면 건너뜀).
실행: python -X utf8 scripts/build-retention-screens.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "force-app" / "main" / "default"
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

cols = "".join(f"    <columns>{c}</columns>\n" for c in
               ["FULL_NAME", "Health_Score__c", "Health_Grade__c", "Health_Basis__c", "Risk_Score__c", "CONTACT.PHONE1"])
p = ROOT / "objects" / "Contact" / "listViews" / "Aurora_Health_Watch.listView-meta.xml"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(HEAD + f"""<ListView {NS}>
    <fullName>Aurora_Health_Watch</fullName>
{cols}    <filterScope>Everything</filterScope>
    <filters>
        <field>Health_Grade__c</field>
        <operation>equals</operation>
        <value>주의</value>
    </filters>
    <label>오로라 건강 주의 차주</label>
</ListView>
""", encoding="utf-8", newline="\n")
print("wrote", p.name)


def card(ident, entity, list_view):
    return f"""        <itemInstances>
            <componentInstance>
                <componentInstanceProperties>
                    <name>entityName</name>
                    <value>{entity}</value>
                </componentInstanceProperties>
                <componentInstanceProperties>
                    <name>filterName</name>
                    <value>{list_view}</value>
                </componentInstanceProperties>
                <componentInstanceProperties>
                    <name>hideActionBar</name>
                    <value>true</value>
                </componentInstanceProperties>
                <componentInstanceProperties>
                    <name>hideSearchBar</name>
                    <value>true</value>
                </componentInstanceProperties>
                <componentInstanceProperties>
                    <name>pageSize</name>
                    <value>5</value>
                </componentInstanceProperties>
                <componentName>flexipage:filterListCard</componentName>
                <identifier>{ident}</identifier>
            </componentInstance>
        </itemInstances>
"""


p = ROOT / "flexipages" / "Aurora_Home.flexipage-meta.xml"
t = p.read_text(encoding="utf-8")
if "card_repurchase" not in t:
    anchor = "        <name>middle</name>\n"
    assert t.count(anchor) == 1
    t = t.replace(anchor, card("card_repurchase", "Opportunity", "Aurora_Repurchase")
                  + card("card_health_watch", "Contact", "Aurora_Health_Watch") + anchor, 1)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("home + 재구매 상담·건강 주의 차주 카드")
