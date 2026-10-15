/**
 * 한국형 레몬법(자동차관리법 제47조의2)·반복 결함 판정. 기준 수치는 Lemon_Law_Rule__mdt(KR_Default).
 * - 판정 기간·주행거리 안의 '하자 수리'를 계통별로 센다(리콜·무상수리 제외).
 * - 중대 계통 수리가 기준 횟수만큼 있은 뒤 같은 계통 재발(그 다음 수리) → 대상 가능.
 *   일반 계통도 같은 방식. 1회 이상 수리 + 누적 수리 일수 초과 → 대상 가능.
 * - 기준까지 한 번 남음 → 주의. 요구 기한이 지나면 해당 없음(근거에 표시).
 * - 반복 결함: 기간과 무관하게 같은 계통 하자 수리 2회 이상.
 * 중대/일반은 주요 부품의 하자 등급, 부품이 없으면 계통 기본값(배터리·구동·제동 = 중대).
 */
public with sharing class LemonLawEvaluator {
    public static final String STATUS_NONE = '해당 없음';
    public static final String STATUS_WATCH = '주의';
    public static final String STATUS_ELIGIBLE = '대상 가능';
    private static final Set<String> MAJOR_SYSTEMS = new Set<String>{ '배터리', '구동', '제동' };

    public static void evaluate(Set<Id> vehicleIds) {
        vehicleIds.remove(null);
        if (vehicleIds.isEmpty()) {
            return;
        }
        Lemon_Law_Rule__mdt rule = Lemon_Law_Rule__mdt.getInstance('KR_Default');
        List<Vehicle__c> updates = new List<Vehicle__c>();
        for (Vehicle__c v : [
            SELECT Id, Delivery_Date__c,
                (SELECT Check_In_Date__c, Repair_Days__c, Mileage__c, Defect_System__c, Main_Part__r.Defect_Grade__c
                 FROM Service_Visits__r
                 WHERE Visit_Type__c = '하자 수리' AND Defect_System__c != null
                 ORDER BY Check_In_Date__c)
            FROM Vehicle__c WHERE Id IN :vehicleIds
        ]) {
            updates.add(judge(v, v.Service_Visits__r, rule, Date.today()));
        }
        update updates;
    }

    public static Vehicle__c judge(Vehicle__c v, List<Service_Visit__c> visits, Lemon_Law_Rule__mdt rule, Date today) {
        Map<String, Integer> windowCount = new Map<String, Integer>();
        Map<String, Decimal> windowDays = new Map<String, Decimal>();
        Map<String, Integer> totalCount = new Map<String, Integer>();
        Map<String, Boolean> major = new Map<String, Boolean>();
        Date windowEnd = v.Delivery_Date__c == null ? null : v.Delivery_Date__c.addMonths(rule.Period_Months__c.intValue());

        for (Service_Visit__c s : visits) {
            String sys = s.Defect_System__c;
            totalCount.put(sys, (totalCount.containsKey(sys) ? totalCount.get(sys) : 0) + 1);
            Boolean isMajor = s.Main_Part__r != null && s.Main_Part__r.Defect_Grade__c != null
                ? s.Main_Part__r.Defect_Grade__c == '중대'
                : MAJOR_SYSTEMS.contains(sys);
            major.put(sys, (major.containsKey(sys) && major.get(sys)) || isMajor);
            Boolean inWindow = windowEnd != null && s.Check_In_Date__c != null
                && s.Check_In_Date__c <= windowEnd
                && (s.Mileage__c == null || s.Mileage__c <= rule.Mileage_Limit_Km__c);
            if (inWindow) {
                windowCount.put(sys, (windowCount.containsKey(sys) ? windowCount.get(sys) : 0) + 1);
                windowDays.put(sys, (windowDays.containsKey(sys) ? windowDays.get(sys) : 0) + (s.Repair_Days__c == null ? 0 : s.Repair_Days__c));
            }
        }

        String status = STATUS_NONE;
        List<String> basis = new List<String>();
        for (String sys : windowCount.keySet()) {
            Integer n = windowCount.get(sys);
            Integer threshold = (major.get(sys) ? rule.Major_Defect_Repairs__c : rule.Minor_Defect_Repairs__c).intValue();
            String grade = major.get(sys) ? '중대' : '일반';
            if (n >= threshold + 1) {
                status = STATUS_ELIGIBLE;
                basis.add(sys + ' 계통(' + grade + ') ' + threshold + '회 수리 후 재발(판정 기간 내 수리 ' + n + '회)');
            } else if (windowDays.get(sys) > rule.Cumulative_Repair_Days__c) {
                status = STATUS_ELIGIBLE;
                basis.add(sys + ' 계통 누적 수리 ' + windowDays.get(sys) + '일(기준 ' + rule.Cumulative_Repair_Days__c.intValue() + '일 초과)');
            } else if (n >= threshold - 1 && status != STATUS_ELIGIBLE) {
                status = STATUS_WATCH;
                basis.add(sys + ' 계통(' + grade + ') 판정 기간 내 수리 ' + n + '회 — 기준 ' + threshold + '회 후 재발 시 대상');
            }
        }
        if (status != STATUS_NONE && v.Delivery_Date__c != null
                && today > v.Delivery_Date__c.addMonths(rule.Claim_Window_Months__c.intValue())) {
            basis.add('단, 요구 기한(인도 후 ' + rule.Claim_Window_Months__c.intValue() + '개월) 경과');
            status = STATUS_NONE;
        }
        if (basis.isEmpty() && windowEnd != null && today > windowEnd) {
            basis.add('판정 기간(인도 후 ' + rule.Period_Months__c.intValue() + '개월) 내 반복 하자 수리 없음');
        }

        List<String> repeatSystems = new List<String>();
        for (String sys : totalCount.keySet()) {
            if (totalCount.get(sys) >= 2) {
                repeatSystems.add(sys);
            }
        }
        repeatSystems.sort();
        return new Vehicle__c(
            Id = v.Id,
            Lemon_Law_Status__c = status,
            Lemon_Law_Basis__c = String.join(basis, ' / ').left(255),
            Repeat_Defect__c = !repeatSystems.isEmpty(),
            Repeat_Defect_System__c = String.join(repeatSystems, ', ')
        );
    }
}
