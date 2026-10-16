/**
 * v5 S-1 서비스센터 혼잡도(docs/design/v5-retention.md Q69).
 * 혼잡도 = 진행 중 정비(입고했고 완료일 없음) 수 / 하루 입고 용량. 저장하지 않고 화면을 열 때 계산한다.
 * 차량 화면에서 담당 서비스센터를 맨 위에, 나머지 센터는 여유 있는 순으로 보여 준다.
 */
public with sharing class AuroraNetworkController {
    public static final String SERVICE_CENTER = '서비스센터';
    static final Decimal BUSY_FROM = 80;
    static final Decimal NORMAL_FROM = 50;

    public class CenterLoad {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String region;
        @AuraEnabled public Integer capacity;
        @AuraEnabled public Integer openVisits;
        @AuraEnabled public Integer percent;
        @AuraEnabled public String level;       // FREE / NORMAL / BUSY / UNKNOWN
        @AuraEnabled public String levelLabel;  // 여유 / 보통 / 혼잡 / 용량 미등록
        @AuraEnabled public Boolean preferred;
    }

    @AuraEnabled(cacheable=true)
    public static List<CenterLoad> centerLoads(Id vehicleId) {
        Id preferredId = null;
        if (vehicleId != null) {
            for (Vehicle__c v : [SELECT Preferred_Center__c FROM Vehicle__c WHERE Id = :vehicleId]) {
                preferredId = v.Preferred_Center__c;
            }
        }
        Map<Id, Integer> open = new Map<Id, Integer>();
        for (AggregateResult ar : [SELECT Service_Center_Account__c c, COUNT(Id) n FROM Service_Visit__c
                                   WHERE Service_Center_Account__c != null AND Check_In_Date__c != null AND Completed_Date__c = null
                                   GROUP BY Service_Center_Account__c]) {
            open.put((Id) ar.get('c'), (Integer) ar.get('n'));
        }
        List<CenterLoad> out = new List<CenterLoad>();
        for (Account a : [SELECT Id, Name, Region__c, Daily_Capacity__c FROM Account
                          WHERE Customer_Segment__c = :SERVICE_CENTER ORDER BY Name]) {
            out.add(load(a, open.containsKey(a.Id) ? open.get(a.Id) : 0, a.Id == preferredId));
        }
        sortRows(out);
        return out;
    }

    @TestVisible
    static CenterLoad load(Account a, Integer openVisits, Boolean preferred) {
        CenterLoad c = new CenterLoad();
        c.id = a.Id;
        c.name = a.Name;
        c.region = a.Region__c;
        c.openVisits = openVisits;
        c.preferred = preferred;
        if (a.Daily_Capacity__c == null || a.Daily_Capacity__c <= 0) {
            c.level = 'UNKNOWN';
            c.levelLabel = '용량 미등록';
            return c;
        }
        c.capacity = a.Daily_Capacity__c.intValue();
        c.percent = (Integer) Math.round(100.0 * openVisits / c.capacity);
        c.level = c.percent >= BUSY_FROM ? 'BUSY' : (c.percent >= NORMAL_FROM ? 'NORMAL' : 'FREE');
        c.levelLabel = c.level == 'BUSY' ? '혼잡' : (c.level == 'NORMAL' ? '보통' : '여유');
        return c;
    }

    /** 담당 센터 먼저, 나머지는 혼잡도 낮은 순(용량 미등록은 맨 뒤) */
    static void sortRows(List<CenterLoad> rows) {
        List<CenterLoad> sorted = new List<CenterLoad>();
        for (CenterLoad c : rows) {
            if (c.preferred) {
                sorted.add(c);
            }
        }
        List<CenterLoad> rest = new List<CenterLoad>();
        for (CenterLoad c : rows) {
            if (!c.preferred) {
                Integer i = 0;
                while (i < rest.size() && rank(rest[i]) <= rank(c)) {
                    i++;
                }
                if (i == rest.size()) {
                    rest.add(c);
                } else {
                    rest.add(i, c);
                }
            }
        }
        sorted.addAll(rest);
        rows.clear();
        rows.addAll(sorted);
    }

    static Integer rank(CenterLoad c) {
        return c.percent == null ? 100000 : c.percent;
    }
}
