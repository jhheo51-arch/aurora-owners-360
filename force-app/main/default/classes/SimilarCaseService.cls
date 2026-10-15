/**
 * VOC 유사 사례 상위 3건(PRD Q39). 점수: 같은 차량 이전 VOC 100 / 같은 차종 + 같은 계통(부품·고장 유형) 60 /
 * 같은 VOC 유형 + 제목 키워드 30 / 연결된 게시 위키 성공 횟수 가산(최대 20). 근거 문구를 함께 돌려준다.
 */
public with sharing class SimilarCaseService {
    public class Suggestion {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Integer score;
        @AuraEnabled public String reason;
        @AuraEnabled public String wikiTitle;
        @AuraEnabled public String resolution;
    }

    @AuraEnabled(cacheable=true)
    public static List<Suggestion> getSimilar(Id caseId) {
        Case base = [SELECT Id, Subject, VOC_Category__c, Vehicle__c, Vehicle__r.Model__c, Failure_Mode__r.System__c,
                     (SELECT Part__r.System__c FROM Case_Parts__r)
                     FROM Case WHERE Id = :caseId];
        Set<String> systems = new Set<String>();
        if (base.Failure_Mode__r != null && base.Failure_Mode__r.System__c != null) {
            systems.add(base.Failure_Mode__r.System__c);
        }
        for (Case_Part__c cp : base.Case_Parts__r) {
            systems.add(cp.Part__r.System__c);
        }
        Set<String> keywords = keywordsOf(base.Subject);

        List<Suggestion> result = new List<Suggestion>();
        for (Case c : [SELECT Id, CaseNumber, Subject, VOC_Category__c, VOC_Status__c, Vehicle__c, Vehicle__r.Model__c, Resolution__c,
                       Failure_Mode__r.Name, Failure_Mode__r.System__c, Failure_Mode__r.Status__c, Failure_Mode__r.Success_Count__c,
                       (SELECT Part__r.System__c FROM Case_Parts__r)
                       FROM Case WHERE Id != :caseId AND Advisor__c != null ORDER BY CreatedDate DESC LIMIT 200]) {
            Integer score = 0;
            List<String> reasons = new List<String>();
            if (base.Vehicle__c != null && c.Vehicle__c == base.Vehicle__c) {
                score += 100;
                reasons.add('같은 차량');
            }
            Set<String> otherSystems = new Set<String>();
            if (c.Failure_Mode__r != null && c.Failure_Mode__r.System__c != null) {
                otherSystems.add(c.Failure_Mode__r.System__c);
            }
            for (Case_Part__c cp : c.Case_Parts__r) {
                otherSystems.add(cp.Part__r.System__c);
            }
            otherSystems.retainAll(systems);
            Boolean sameModel = base.Vehicle__r != null && base.Vehicle__r.Model__c != null
                && c.Vehicle__r != null && c.Vehicle__r.Model__c == base.Vehicle__r.Model__c;
            if (!otherSystems.isEmpty() && sameModel) {
                score += 60;
                reasons.add('같은 차종·' + String.join(new List<String>(otherSystems), '·') + ' 계통');
            } else if (!otherSystems.isEmpty()) {
                score += 40;
                reasons.add(String.join(new List<String>(otherSystems), '·') + ' 계통');
            }
            if (c.VOC_Category__c == base.VOC_Category__c) {
                Set<String> shared = keywordsOf(c.Subject);
                shared.retainAll(keywords);
                score += shared.isEmpty() ? 15 : 30;
                reasons.add('같은 VOC 유형' + (shared.isEmpty() ? '' : '·키워드 ' + String.join(new List<String>(shared), ',')));
            }
            if (c.Failure_Mode__r != null && c.Failure_Mode__r.Status__c == '게시' && score > 0) {
                Decimal success = c.Failure_Mode__r.Success_Count__c == null ? 0 : c.Failure_Mode__r.Success_Count__c;
                score += Math.min(success.intValue() * 5, 20);
                reasons.add('게시 위키 성공 ' + success.intValue() + '회');
            }
            if (score == 0) {
                continue;
            }
            Suggestion s = new Suggestion();
            s.caseId = c.Id;
            s.caseNumber = c.CaseNumber;
            s.subject = c.Subject;
            s.status = c.VOC_Status__c;
            s.score = score;
            s.reason = String.join(reasons, ' · ');
            s.wikiTitle = c.Failure_Mode__r == null ? null : c.Failure_Mode__r.Name;
            s.resolution = c.Resolution__c;
            result.add(s);
        }
        sortByScore(result);
        while (result.size() > 3) {
            result.remove(result.size() - 1);
        }
        return result;
    }

    private static Set<String> keywordsOf(String text) {
        Set<String> words = new Set<String>();
        if (text == null) {
            return words;
        }
        for (String w : text.split('[\\s·,()]+')) {
            if (w.length() >= 2) {
                words.add(w);
            }
        }
        return words;
    }

    private static void sortByScore(List<Suggestion> items) {
        for (Integer i = 1; i < items.size(); i++) {
            Suggestion key = items[i];
            Integer j = i - 1;
            while (j >= 0 && items[j].score < key.score) {
                items[j + 1] = items[j];
                j--;
            }
            items[j + 1] = key;
        }
    }
}
