/** v4.5: Apex 승인 단계와 수식 필드 Approval_Level__c가 같은 기준인지, 계통 키워드 공용 목록이 기존 동작과 같은지 확인 */
@IsTest
private class AuroraApprovalRuleTest {
    @IsTest
    static void apexRuleMatchesFormulaField() {
        Care_Staff__c lead = new Care_Staff__c(Name = '테스트팀장', Role__c = '상담팀장', Staff_Number__c = 'T-AR-L', Active__c = true);
        insert lead;
        Care_Staff__c adv = new Care_Staff__c(Name = '테스트상담원', Role__c = '상담원', Staff_Number__c = 'T-AR-1', Active__c = true, Manager__c = lead.Id);
        insert adv;
        Case c = new Case(Subject = '승인 기준 테스트', Advisor__c = adv.Id, Manager_Employee__c = lead.Id, VOC_Category__c = '기타', VOC_Status__c = '접수');
        insert c;
        List<Compensation__c> rows = new List<Compensation__c>{
            new Compensation__c(Case__c = c.Id, Compensation_Type__c = '포인트 지급', Amount__c = 0, Approval_Status__c = '요청'),
            new Compensation__c(Case__c = c.Id, Compensation_Type__c = '포인트 지급', Amount__c = 299999, Approval_Status__c = '요청'),
            new Compensation__c(Case__c = c.Id, Compensation_Type__c = '대차 지원', Amount__c = 300000, Approval_Status__c = '요청'),
            new Compensation__c(Case__c = c.Id, Compensation_Type__c = '무상수리', Amount__c = 999999, Approval_Status__c = '요청'),
            new Compensation__c(Case__c = c.Id, Compensation_Type__c = '무상수리', Amount__c = 1000000, Approval_Status__c = '요청'),
            new Compensation__c(Case__c = c.Id, Compensation_Type__c = '보증 연장', Amount__c = 1000, Approval_Status__c = '요청')
        };
        insert rows;
        for (Compensation__c m : [SELECT Amount__c, Compensation_Type__c, Approval_Level__c FROM Compensation__c WHERE Case__c = :c.Id]) {
            System.assertEquals(m.Approval_Level__c, AuroraApprovalRule.level(m), '수식과 Apex 기준이 같아야 함: ' + m.Amount__c + ' ' + m.Compensation_Type__c);
        }
    }

    @IsTest
    static void systemKeywordsKeepPreviousBehavior() {
        // 리콜 경보(정확한 말): 기존 RecallAlertService 키워드와 같은 결과
        System.assertEquals('제동', AuroraSystemKeywords.firstSystem('주행 중 브레이크 경고등 점등'));
        System.assertEquals('배터리', AuroraSystemKeywords.firstSystem('급속 충전 속도 저하'));
        System.assertEquals('제동', AuroraSystemKeywords.firstSystem('브레이크 경고등과 충전 문제'), '앞 계통 우선');
        System.assertEquals(null, AuroraSystemKeywords.firstSystem('앱 로그인이 안 돼요'), '앱은 정확한 말이 아님');
        // RAG(넓게): 기존 AuroraRagService 키워드와 같은 결과
        System.assertEquals(new Set<String>{ '공조', '전장' }, AuroraSystemKeywords.systemsOf('앱에서 원격 공조가 안 돼요', true));
        System.assert(AuroraSystemKeywords.systemsOf('에어컨 냄새', true).contains('공조'));
        System.assert(AuroraSystemKeywords.systemsOf('OBC 이상', true).contains('배터리'));
        System.assert(!AuroraSystemKeywords.systemsOf('OBC 이상', false).contains('배터리'), '정확한 말만 쓸 때는 OBC 제외');
        System.assert(AuroraSystemKeywords.systemsOf('', true).isEmpty());
    }
}
