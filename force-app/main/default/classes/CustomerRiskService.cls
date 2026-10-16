/**
 * 고객 위험 점수 0~100 (PRD Q42): 최근 90일 VOC 1건당 15 + 이관 이력 15 + 보상 반려 10 + 기한 위반 10
 * + 플래티넘 10 + 레몬법(주의·대상 가능)·반복 결함 차량 보유 25. VOC·정비 저장 시 다시 계산한다.
 */
public with sharing class CustomerRiskService {
    public static void recalculateForCases(List<Case> cases) {
        Set<Id> contactIds = new Set<Id>();
        for (Case c : cases) {
            if (c.ContactId != null && c.Advisor__c != null) {
                contactIds.add(c.ContactId);
            }
        }
        recalculate(contactIds);
    }

    public static void recalculateForVehicles(Set<Id> vehicleIds) {
        Set<Id> contactIds = new Set<Id>();
        for (Vehicle__c v : [SELECT Owner_Contact__c FROM Vehicle__c WHERE Id IN :vehicleIds AND Owner_Contact__c != null]) {
            contactIds.add(v.Owner_Contact__c);
        }
        recalculate(contactIds);
    }

    public static void recalculate(Set<Id> contactIds) {
        contactIds.remove(null);
        if (contactIds.isEmpty()) {
            return;
        }
        Datetime since = Datetime.now().addDays(-90);
        Map<Id, Integer> recent = new Map<Id, Integer>();
        Set<Id> escalated = new Set<Id>();
        Set<Id> overdue = new Set<Id>();
        for (Case c : [SELECT ContactId, CreatedDate, Escalation_Status__c, Response_Due_At__c, First_Response_At__c
                       FROM Case WHERE ContactId IN :contactIds AND Advisor__c != null
                       AND AI_Outcome__c != :AicxInfoService.AI_INFO]) {   // v4.3 D3: AI 정보 안내는 위험 점수에서 제외
            if (c.CreatedDate >= since) {
                recent.put(c.ContactId, (recent.containsKey(c.ContactId) ? recent.get(c.ContactId) : 0) + 1);
            }
            if (c.Escalation_Status__c == '요청' || c.Escalation_Status__c == '처리완료') {
                escalated.add(c.ContactId);
            }
            Boolean late = c.Response_Due_At__c != null && (c.First_Response_At__c == null
                ? c.Response_Due_At__c < Datetime.now() : c.First_Response_At__c > c.Response_Due_At__c);
            if (late) {
                overdue.add(c.ContactId);
            }
        }
        Set<Id> rejected = new Set<Id>();
        for (Compensation__c m : [SELECT Case__r.ContactId FROM Compensation__c WHERE Case__r.ContactId IN :contactIds AND Approval_Status__c = '반려']) {
            rejected.add(m.Case__r.ContactId);
        }
        Set<Id> riskyVehicle = new Set<Id>();
        for (Vehicle__c v : [SELECT Owner_Contact__c FROM Vehicle__c WHERE Owner_Contact__c IN :contactIds
                             AND (Repeat_Defect__c = true OR Lemon_Law_Status__c IN ('주의', '대상 가능'))]) {
            riskyVehicle.add(v.Owner_Contact__c);
        }

        List<Contact> updates = new List<Contact>();
        for (Contact c : [SELECT Id, Customer_Grade__c FROM Contact WHERE Id IN :contactIds]) {
            Integer count = recent.containsKey(c.Id) ? recent.get(c.Id) : 0;
            Integer score = count * 15
                + (escalated.contains(c.Id) ? 15 : 0)
                + (rejected.contains(c.Id) ? 10 : 0)
                + (overdue.contains(c.Id) ? 10 : 0)
                + (c.Customer_Grade__c == '플래티넘' ? 10 : 0)
                + (riskyVehicle.contains(c.Id) ? 25 : 0);
            updates.add(new Contact(Id = c.Id, VOC_Count_90d__c = count, Risk_Score__c = Math.min(score, 100)));
        }
        // v5: 같은 저장에서 고객 건강 점수도 채운다(위험 점수를 입력으로 씀)
        CustomerHealthService.apply(updates);
        update updates;
    }
}
