/**
 * v5 S-2 리콜 캠페인(docs/design/v5-retention.md Q70~Q72).
 *  - preview/generateTargets: 모델 계열 + 출고일 범위에 맞는 차량으로 Recall_Vehicle__c 생성(키 = 캠페인 키|VIN, 중복 없음)
 *  - stampDates: 상태가 통지·입고 예약·조치 완료로 바뀌면 비어 있는 날짜를 오늘로
 *  - onVisits: 리콜 조치 정비가 완료되면 대상 차량을 '조치 완료'로
 */
public with sharing class RecallCampaignService {
    public static final String NOTIFIED = '통지';
    public static final String RESERVED = '입고 예약';
    public static final String DONE = '조치 완료';
    public static final String EXCLUDED = '제외';

    public class Result {
        @AuraEnabled public Integer matched = 0;    // 조건에 맞는 차량
        @AuraEnabled public Integer existing = 0;   // 이미 대상인 차량
        @AuraEnabled public Integer created = 0;    // 이번에 만든 대상
        @AuraEnabled public String condition;       // 사람이 읽는 조건
        @AuraEnabled public String message;
        @AuraEnabled public Boolean ok = true;
    }

    @AuraEnabled
    public static Result preview(Id campaignId) {
        return run(campaignId, false);
    }

    @AuraEnabled
    public static Result generateTargets(Id campaignId) {
        return run(campaignId, true);
    }

    static Result run(Id campaignId, Boolean commitRows) {
        Result r = new Result();
        Recall_Campaign__c c = [SELECT Id, Name, Campaign_Key__c, Model_Line__c, Delivery_From__c, Delivery_To__c, Status__c
                                FROM Recall_Campaign__c WHERE Id = :campaignId];
        if (String.isBlank(c.Model_Line__c)) {
            r.ok = false;
            r.message = '대상 모델 계열을 먼저 입력해 주세요.';
            return r;
        }
        r.condition = c.Model_Line__c + ' · 출고 ' + (c.Delivery_From__c == null ? '처음' : String.valueOf(c.Delivery_From__c))
            + ' ~ ' + (c.Delivery_To__c == null ? '현재' : String.valueOf(c.Delivery_To__c));
        String prefix = String.isBlank(c.Campaign_Key__c) ? c.Name : c.Campaign_Key__c;
        Set<String> keys = new Set<String>();
        for (Recall_Vehicle__c rv : [SELECT Target_Key__c FROM Recall_Vehicle__c WHERE Campaign__c = :campaignId]) {
            keys.add(rv.Target_Key__c);
        }
        List<Recall_Vehicle__c> rows = new List<Recall_Vehicle__c>();
        for (Vehicle__c v : matchingVehicles(c)) {
            r.matched++;
            String key = prefix + '|' + v.VIN__c;
            if (keys.contains(key)) {
                r.existing++;
                continue;
            }
            rows.add(new Recall_Vehicle__c(Campaign__c = c.Id, Vehicle__c = v.Id, Target_Key__c = key,
                                           Status__c = '미통지', Service_Center__c = v.Preferred_Center__c));
        }
        if (commitRows && !rows.isEmpty()) {
            insert rows;
            r.created = rows.size();
        }
        r.message = commitRows
            ? '대상 차량 ' + r.created + '대를 만들었습니다' + (r.existing > 0 ? '(이미 등록된 ' + r.existing + '대는 그대로).' : '.')
            : '조건에 맞는 차량 ' + r.matched + '대 중 새로 만들 대상은 ' + rows.size() + '대입니다.';
        return r;
    }

    /** 출고 전 차량(출고일 없음)은 출고일 범위가 있으면 제외 — 출고 전 조치는 생산 쪽 업무 */
    static List<Vehicle__c> matchingVehicles(Recall_Campaign__c c) {
        String line = c.Model_Line__c;
        Date dFrom = c.Delivery_From__c;
        Date dTo = c.Delivery_To__c;
        String soql = 'SELECT Id, Name, VIN__c, Preferred_Center__c FROM Vehicle__c WHERE Vehicle_Model__r.Model_Line__c = :line';
        if (dFrom != null) {
            soql += ' AND Delivery_Date__c >= :dFrom';
        }
        if (dTo != null) {
            soql += ' AND Delivery_Date__c <= :dTo';
        }
        return Database.query(soql + ' ORDER BY Name');
    }

    public static void stampDates(List<Recall_Vehicle__c> rows, Map<Id, Recall_Vehicle__c> oldMap) {
        for (Recall_Vehicle__c rv : rows) {
            Recall_Vehicle__c old = oldMap == null ? null : oldMap.get(rv.Id);
            if (old != null && old.Status__c == rv.Status__c) {
                continue;
            }
            if ((rv.Status__c == NOTIFIED || rv.Status__c == RESERVED || rv.Status__c == DONE) && rv.Notified_Date__c == null) {
                rv.Notified_Date__c = Date.today();
            }
            if (rv.Status__c == RESERVED && rv.Reserved_Date__c == null) {
                rv.Reserved_Date__c = Date.today();
            }
            if (rv.Status__c == DONE && rv.Completed_Date__c == null) {
                rv.Completed_Date__c = Date.today();
            }
        }
    }

    public static void onVisits(List<Service_Visit__c> visits) {
        Map<Id, Service_Visit__c> byTarget = new Map<Id, Service_Visit__c>();
        for (Service_Visit__c s : visits) {
            if (s.Recall_Vehicle__c != null && s.Completed_Date__c != null) {
                byTarget.put(s.Recall_Vehicle__c, s);
            }
        }
        if (byTarget.isEmpty()) {
            return;
        }
        List<Recall_Vehicle__c> updates = new List<Recall_Vehicle__c>();
        for (Recall_Vehicle__c rv : [SELECT Id, Status__c FROM Recall_Vehicle__c WHERE Id IN :byTarget.keySet() AND Status__c != :DONE]) {
            Service_Visit__c s = byTarget.get(rv.Id);
            updates.add(new Recall_Vehicle__c(Id = rv.Id, Status__c = DONE, Completed_Date__c = s.Completed_Date__c,
                                              Service_Center__c = s.Service_Center_Account__c));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }
}
