/**
 * v5 S-5 고객 건강 점수 0~100(docs/design/v5-retention.md Q76): "이 고객이 남을까"를 한 숫자로.
 * 100에서 감점: 위험 점수 × 가중치, 최근 CSAT 낮음, 리콜 미조치, 레몬법 '주의' 이상 차량, 진행 중 VOC 건수.
 * 기준값은 Health_Rule__mdt(KR_Default) — 배포 없이 조정. CustomerRiskService가 위험 점수를 계산한 같은 Contact 목록에 채운다(DML 1회).
 */
public with sharing class CustomerHealthService {
    public static final String GRADE_GOOD = '좋음';
    public static final String GRADE_FAIR = '보통';
    public static final String GRADE_WATCH = '주의';

    /** rows: Id·Risk_Score__c가 채워진 Contact. Health_* 필드를 채운다(저장은 호출한 쪽). */
    public static void apply(List<Contact> rows) {
        Set<Id> ids = new Set<Id>();
        for (Contact c : rows) {
            ids.add(c.Id);
        }
        ids.remove(null);
        if (ids.isEmpty()) {
            return;
        }
        Health_Rule__mdt rule = Health_Rule__mdt.getInstance('KR_Default');

        // 쿼리 2개만 쓴다: VOC·정비 저장마다 위험 점수와 함께 돌기 때문(트리거 연쇄에서 SOQL 한도 보호)
        Map<Id, Integer> openVoc = new Map<Id, Integer>();
        Map<Id, Decimal> lastCsat = new Map<Id, Decimal>();   // 가장 최근에 종결된 VOC 중 CSAT가 있는 건
        for (Case c : [SELECT ContactId, VOC_Status__c, CSAT__c, AI_Outcome__c FROM Case
                       WHERE ContactId IN :ids AND VOC_Status__c != null
                       AND (VOC_Status__c != '종결' OR CSAT__c != null)
                       ORDER BY ClosedDate DESC NULLS LAST, LastModifiedDate DESC]) {
            if (c.VOC_Status__c != '종결') {
                if (c.AI_Outcome__c != AicxInfoService.AI_INFO) {
                    openVoc.put(c.ContactId, (openVoc.containsKey(c.ContactId) ? openVoc.get(c.ContactId) : 0) + 1);
                }
            } else if (!lastCsat.containsKey(c.ContactId)) {
                lastCsat.put(c.ContactId, c.CSAT__c);
            }
        }
        Set<Id> openRecall = new Set<Id>();
        Set<Id> lemon = new Set<Id>();
        for (Vehicle__c v : [SELECT Owner_Contact__c, Lemon_Law_Status__c,
                                    (SELECT Id FROM Recall_Targets__r WHERE Status__c NOT IN ('조치 완료', '제외') LIMIT 1)
                             FROM Vehicle__c WHERE Owner_Contact__c IN :ids]) {
            if (v.Lemon_Law_Status__c == '주의' || v.Lemon_Law_Status__c == '대상 가능') {
                lemon.add(v.Owner_Contact__c);
            }
            if (!v.Recall_Targets__r.isEmpty()) {
                openRecall.add(v.Owner_Contact__c);
            }
        }

        for (Contact c : rows) {
            Integer risk = c.Risk_Score__c == null ? 0 : c.Risk_Score__c.intValue();
            Integer riskCut = (risk * rule.Risk_Weight__c).round(System.RoundingMode.HALF_UP).intValue();
            Integer score = 100 - riskCut;
            List<String> basis = new List<String>{ '위험 ' + risk + ' → −' + riskCut };
            Decimal csat = lastCsat.get(c.Id);
            if (csat != null && csat <= rule.Low_CSAT_Max__c) {
                score -= rule.Low_CSAT_Penalty__c.intValue();
                basis.add('최근 CSAT ' + csat.intValue() + '점 −' + rule.Low_CSAT_Penalty__c.intValue());
            }
            if (openRecall.contains(c.Id)) {
                score -= rule.Recall_Penalty__c.intValue();
                basis.add('리콜 미조치 −' + rule.Recall_Penalty__c.intValue());
            }
            if (lemon.contains(c.Id)) {
                score -= rule.Lemon_Penalty__c.intValue();
                basis.add('레몬법 주의 이상 −' + rule.Lemon_Penalty__c.intValue());
            }
            Integer open = openVoc.containsKey(c.Id) ? openVoc.get(c.Id) : 0;
            if (open > 0) {
                Integer cut = open * rule.Open_VOC_Penalty__c.intValue();
                score -= cut;
                basis.add('진행 중 VOC ' + open + '건 −' + cut);
            }
            score = Math.max(0, Math.min(100, score));
            c.Health_Score__c = score;
            c.Health_Grade__c = score >= rule.Good_Min__c ? GRADE_GOOD : (score >= rule.Fair_Min__c ? GRADE_FAIR : GRADE_WATCH);
            c.Health_Basis__c = String.join(basis, ' · ').left(255);
        }
    }
}
