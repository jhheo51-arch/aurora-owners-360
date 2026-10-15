/** VOC Care Assistant 액션 공통: 대상 레코드 확인. 오로라 VOC = VOC 상태가 있는 Case. */
public with sharing class AuroraAgentSupport {
    public static final String NOT_VOC = '오로라 VOC 화면이 아닙니다. 확인할 VOC를 연 뒤 새 대화를 시작해 주세요.';
    public static final String NOT_VEHICLE = '오로라 VOC 또는 고객 차량 화면이 아닙니다. 확인할 레코드를 연 뒤 새 대화를 시작해 주세요.';

    public static Case vocOrNull(String recordId) {
        Id id = toId(recordId);
        if (id == null || id.getSobjectType() != Case.SObjectType) {
            return null;
        }
        List<Case> rows = [SELECT Id, CaseNumber, Subject, VOC_Status__c, VOC_Category__c, Vehicle__c, Escalation_Status__c,
                                  Needs_Manager__c, Manager_Employee__c, Advisor__r.Manager__c
                           FROM Case WHERE Id = :id AND VOC_Status__c != null];
        return rows.isEmpty() ? null : rows[0];
    }

    public static Id vehicleIdOf(String recordId) {
        Id id = toId(recordId);
        if (id == null) {
            return null;
        }
        if (id.getSobjectType() == Vehicle__c.SObjectType) {
            return id;
        }
        Case c = vocOrNull(recordId);
        return c == null ? null : c.Vehicle__c;
    }

    static Id toId(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }
}
