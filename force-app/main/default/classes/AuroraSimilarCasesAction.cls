/**
 * VOC Care Assistant 액션: 유사 사례·고장 위키 (v4). v3 SimilarCaseService 재사용 + 게시 위키 해결 단계.
 * 읽기 전용.
 */
public with sharing class AuroraSimilarCasesAction {
    public class Request {
        @InvocableVariable(label='VOC 레코드 ID' description='현재 열린 오로라 VOC(Case) ID' required=true)
        public String recordId;
    }

    public class Result {
        @InvocableVariable(label='유사 사례 결과' description='상위 3건과 게시 위키 해결 단계')
        public String message;
    }

    @InvocableMethod(label='오로라 유사 사례·위키 조회' description='현재 VOC와 비슷한 사례 상위 3건과 게시된 고장 위키 해결 단계를 반환합니다. 기록을 바꾸지 않습니다.')
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
        Case base = AuroraAgentSupport.vocOrNull(recordId);
        if (base == null) {
            return AuroraAgentSupport.NOT_VOC;
        }
        List<SimilarCaseService.Suggestion> items = SimilarCaseService.getSimilar(base.Id);
        Set<String> titles = new Set<String>();
        for (SimilarCaseService.Suggestion s : items) {
            if (s.wikiTitle != null) {
                titles.add(s.wikiTitle);
            }
        }
        Map<String, Failure_Mode__c> wiki = new Map<String, Failure_Mode__c>();
        for (Failure_Mode__c fm : [SELECT Name, Status__c, Resolution_Steps__c, Self_Solvable__c FROM Failure_Mode__c WHERE Name IN :titles]) {
            wiki.put(fm.Name, fm);
        }
        List<String> lines = new List<String>{ 'VOC ' + base.CaseNumber + ' · ' + base.Subject + ' 와 비슷한 사례' };
        if (items.isEmpty()) {
            lines.add('- 비슷한 사례가 없습니다.');
        }
        Integer i = 0;
        for (SimilarCaseService.Suggestion s : items) {
            i++;
            String line = i + '. VOC ' + s.caseNumber + ' · ' + s.subject + ' (점수 ' + s.score + ' · ' + s.reason + ' · ' + s.status + ')';
            Failure_Mode__c fm = s.wikiTitle == null ? null : wiki.get(s.wikiTitle);
            if (fm != null && fm.Status__c == '게시') {
                line += '\n   게시 위키 "' + fm.Name + '"' + (fm.Self_Solvable__c ? ' (차주 자가 해결 가능)' : '')
                    + (String.isBlank(fm.Resolution_Steps__c) ? '' : ' 해결 단계: ' + fm.Resolution_Steps__c.left(300));
            } else if (fm != null) {
                line += '\n   위키 "' + fm.Name + '" (' + fm.Status__c + ' — 게시 전이라 안내에 쓰지 않음)';
            }
            if (String.isNotBlank(s.resolution)) {
                line += '\n   그때 해결: ' + s.resolution.left(200);
            }
            lines.add(line);
        }
        return String.join(lines, '\n');
    }
}