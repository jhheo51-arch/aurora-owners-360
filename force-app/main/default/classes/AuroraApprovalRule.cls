/**
 * v4.5 보상·조치 승인 단계 공용 규칙(PRD Q27·Q29). Apex에서 승인 단계가 필요하면 여기만 쓴다.
 * 수식 필드 Compensation__c.Approval_Level__c(화면·리포트·Flow용)와 같은 기준이며, 둘이 어긋나지 않는지
 * AuroraApprovalRuleTest가 실제 수식 값과 비교한다. before 트리거에서는 수식 값이 아직 계산되지 않아 이 메서드가 필요하다.
 */
public with sharing class AuroraApprovalRule {
    public static final Decimal TEAM_LEAD_FROM = 300000;    // 30만 원 이상: 상담팀장 승인
    public static final Decimal UPPER_FROM = 1000000;       // 100만 원 이상(또는 보증 연장): 상위 승인
    public static final String NONE = '승인 불필요';
    public static final String TEAM_LEAD = '팀장 승인';
    public static final String UPPER = '상위 승인';

    public static String level(Decimal amount, String compensationType) {
        if ((amount != null && amount >= UPPER_FROM) || compensationType == '보증 연장') {
            return UPPER;
        }
        return amount != null && amount >= TEAM_LEAD_FROM ? TEAM_LEAD : NONE;
    }

    public static String level(Compensation__c m) {
        return level(m.Amount__c, m.Compensation_Type__c);
    }
}
