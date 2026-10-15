/**
 * 오로라 AI 상담(AICX) 위키 매칭·자동 안내 허용·피드백 (PRD §20-5).
 * 점수 = 메시지와 위키 제목·증상의 키워드 일치 수 + 계통 동의어 일치 시 +1.
 * 자동 안내 허용 = 자가 해결 가능 AND 심각도≠높음 AND 계통≠제동 AND 실패율 < 0.5.
 */
public with sharing class AicxSelfHelpService {
    static final Map<String, List<String>> SYNONYMS = new Map<String, List<String>>{
        '공조' => new List<String>{ '에어컨', '히터', '냄새', '원격 공조' },
        '전장' => new List<String>{ '앱', '로그인', '원격', '카메라' },
        '배터리' => new List<String>{ '충전', '충전기', '급속', '완속' }
    };

    public class Match {
        @AuraEnabled public Id wikiId;
        @AuraEnabled public String title;
        @AuraEnabled public String systemName;
        @AuraEnabled public Integer score = 0;
        @AuraEnabled public Boolean allowed = false;
        @AuraEnabled public String reason;
    }

    public static Match matchWiki(Id vehicleId, String message) {
        String msg = message == null ? '' : message;
        String line;
        if (vehicleId != null) {
            List<Vehicle__c> v = [SELECT Vehicle_Model__r.Model_Line__c FROM Vehicle__c WHERE Id = :vehicleId];
            line = v.isEmpty() || v[0].Vehicle_Model__r == null ? null : v[0].Vehicle_Model__r.Model_Line__c;
        }
        Integer minScore = minScore();
        Match best;
        for (Failure_Mode__c fm : [SELECT Id, Name, Symptom__c, System__c, Severity__c, Self_Solvable__c,
                                          Success_Count__c, Failure_Count__c, Applicable_Models__c
                                   FROM Failure_Mode__c WHERE Status__c = '게시' ORDER BY Wiki_Key__c]) {
            if (line != null && (fm.Applicable_Models__c == null || !fm.Applicable_Models__c.split(';').contains(line))) {
                continue;
            }
            Integer score = 0;
            for (String token : tokens(fm.Name + ' ' + (fm.Symptom__c == null ? '' : fm.Symptom__c))) {
                if (msg.contains(token)) {
                    score++;
                }
            }
            if (SYNONYMS.containsKey(fm.System__c)) {
                for (String s : SYNONYMS.get(fm.System__c)) {
                    if (msg.contains(s)) {
                        score++;
                        break;
                    }
                }
            }
            if (score >= minScore && (best == null || score > best.score)) {
                best = toMatch(fm, score);
            }
        }
        return best;
    }

    static Match toMatch(Failure_Mode__c fm, Integer score) {
        Match m = new Match();
        m.wikiId = fm.Id;
        m.title = fm.Name;
        m.systemName = fm.System__c;
        m.score = score;
        Decimal ok = fm.Success_Count__c == null ? 0 : fm.Success_Count__c;
        Decimal ng = fm.Failure_Count__c == null ? 0 : fm.Failure_Count__c;
        Decimal failRate = ok + ng == 0 ? 0 : ng / (ok + ng);
        List<String> blocks = new List<String>();
        if (!fm.Self_Solvable__c) {
            blocks.add('자가 해결 불가');
        }
        if (fm.Severity__c == '높음') {
            blocks.add('심각도 높음');
        }
        if (fm.System__c == '제동') {
            blocks.add('제동 계통');
        }
        if (failRate >= 0.5) {
            blocks.add('실패율 ' + (failRate * 100).setScale(0) + '%');
        }
        m.allowed = blocks.isEmpty();
        m.reason = m.allowed ? '자동 안내 허용(실패율 ' + (failRate * 100).setScale(0) + '%)' : String.join(blocks, ', ');
        return m;
    }

    /** 해결됨 → 성공 +1, 안 됨 → 실패 +1 (피드백 루프) */
    public static void recordOutcome(Id wikiId, Boolean solved) {
        if (wikiId == null) {
            return;
        }
        Failure_Mode__c fm = [SELECT Id, Success_Count__c, Failure_Count__c FROM Failure_Mode__c WHERE Id = :wikiId];
        if (solved) {
            fm.Success_Count__c = (fm.Success_Count__c == null ? 0 : fm.Success_Count__c) + 1;
        } else {
            fm.Failure_Count__c = (fm.Failure_Count__c == null ? 0 : fm.Failure_Count__c) + 1;
        }
        update fm;
    }

    static Integer minScore() {
        Aicx_Rule__mdt r = Aicx_Rule__mdt.getInstance('KR_Default');
        return r == null || r.Min_Match_Score__c == null ? 2 : r.Min_Match_Score__c.intValue();
    }

    /** 두 글자 이상 낱말(문장 부호·따옴표 제거) */
    @TestVisible
    static Set<String> tokens(String text) {
        Set<String> out = new Set<String>();
        for (String t : text.replaceAll('[^0-9A-Za-z가-힣]+', ' ').split(' ')) {
            if (t.length() >= 2) {
                out.add(t);
            }
        }
        return out;
    }
}
