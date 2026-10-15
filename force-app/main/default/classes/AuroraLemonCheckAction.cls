/**
 * VOC Care Assistant 액션: 레몬법·반복 결함 확인 (v4, PRD Q63). 읽기 전용.
 * 저장된 판정과, 지금 기준(Lemon_Law_Rule__mdt)으로 다시 계산한 결과·근거를 함께 돌려준다. 기록은 바꾸지 않는다.
 */
public with sharing class AuroraLemonCheckAction {
    public class Request {
        @InvocableVariable(label='레코드 ID' description='현재 열린 오로라 VOC(Case) 또는 고객 차량(Vehicle__c) ID' required=true)
        public String recordId;
    }

    public class Result {
        @InvocableVariable(label='레몬법 확인 결과' description='저장 판정·재계산 판정·근거·반복 결함·기준')
        public String message;
    }

    @InvocableMethod(label='오로라 레몬법·반복 결함 확인' description='차량의 레몬법(자동차관리법 제47조의2) 판정과 반복 결함 계통을 근거와 함께 반환합니다. 기록을 바꾸지 않습니다.')
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            res.message = describe(r.recordId);
            out.add(res);
        }
        return out;
    }

    static String describe(String recordId) {
        Id vehicleId = AuroraAgentSupport.vehicleIdOf(recordId);
        if (vehicleId == null) {
            return AuroraAgentSupport.NOT_VEHICLE + ' (VOC에 고객 차량이 없으면 판정할 수 없습니다.)';
        }
        Vehicle__c v = [SELECT Id, Name, Delivery_Date__c, Mileage__c, Vehicle_Model__r.Name, Owner_Contact__r.Name,
                               Lemon_Law_Status__c, Lemon_Law_Basis__c, Repeat_Defect__c, Repeat_Defect_System__c,
                               (SELECT Check_In_Date__c, Repair_Days__c, Mileage__c, Defect_System__c, Main_Part__r.Defect_Grade__c
                                FROM Service_Visits__r
                                WHERE Visit_Type__c = '하자 수리' AND Defect_System__c != null
                                ORDER BY Check_In_Date__c)
                        FROM Vehicle__c WHERE Id = :vehicleId];
        Lemon_Law_Rule__mdt rule = Lemon_Law_Rule__mdt.getInstance('KR_Default');
        Vehicle__c now = LemonLawEvaluator.judge(v, v.Service_Visits__r, rule, Date.today());

        Map<String, Integer> bySystem = new Map<String, Integer>();
        for (Service_Visit__c s : v.Service_Visits__r) {
            bySystem.put(s.Defect_System__c, (bySystem.containsKey(s.Defect_System__c) ? bySystem.get(s.Defect_System__c) : 0) + 1);
        }
        List<String> counts = new List<String>();
        for (String sys : bySystem.keySet()) {
            counts.add(sys + ' ' + bySystem.get(sys) + '회');
        }

        List<String> lines = new List<String>();
        lines.add(v.Name + (v.Vehicle_Model__r == null ? '' : ' · ' + v.Vehicle_Model__r.Name)
            + (v.Owner_Contact__r == null ? '' : ' · 차주 ' + v.Owner_Contact__r.Name)
            + ' · 인도 ' + (v.Delivery_Date__c == null ? '미확인' : String.valueOf(v.Delivery_Date__c))
            + ' · 주행 ' + (v.Mileage__c == null ? '미확인' : v.Mileage__c.format() + 'km'));
        lines.add('저장된 판정: ' + v.Lemon_Law_Status__c + (String.isBlank(v.Lemon_Law_Basis__c) ? '' : ' — ' + v.Lemon_Law_Basis__c));
        lines.add('지금 기준 재계산: ' + now.Lemon_Law_Status__c + (String.isBlank(now.Lemon_Law_Basis__c) ? '' : ' — ' + now.Lemon_Law_Basis__c)
            + (now.Lemon_Law_Status__c == v.Lemon_Law_Status__c ? ' (저장값과 같음)' : ' (저장값과 다름 — 정비 이력 저장 시 자동 갱신됨)'));
        lines.add('반복 결함: ' + (now.Repeat_Defect__c ? now.Repeat_Defect_System__c + ' 계통' : '없음')
            + (counts.isEmpty() ? '' : ' · 하자 수리 ' + String.join(counts, ', ')));
        if (rule != null) {
            lines.add('기준: 인도 후 ' + rule.Period_Months__c.intValue() + '개월·' + rule.Mileage_Limit_Km__c.intValue()
                + 'km 이내, 중대 결함 ' + rule.Major_Defect_Repairs__c.intValue() + '회·일반 결함 ' + rule.Minor_Defect_Repairs__c.intValue()
                + '회 수리 후 재발 또는 누적 수리 ' + rule.Cumulative_Repair_Days__c.intValue() + '일 초과, 요구 기한 인도 후 '
                + rule.Claim_Window_Months__c.intValue() + '개월');
        }
        lines.add('※ 상담 참고용 판정이며 법적 판단이 아닙니다. 교환·환불 여부는 자동차안전·하자심의위원회 중재로 결정됩니다.');
        return String.join(lines, '\n');
    }
}