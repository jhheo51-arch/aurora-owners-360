/**
 * VOC Care Assistant 액션: AI 해결 가이드(RAG, v4.4 F4). 과거 해결 사례를 Apex로 찾아 근거로 주고, 근거 표시가 붙은 답을 만든다.
 * 근거가 2건 미만이면 AI를 부르지 않고 '부족' 안내. 기록을 바꾸지 않는다.
 */
public with sharing class AuroraRagAnswerAction {
    public class Request {
        @InvocableVariable(label='VOC 레코드 ID' description='현재 열린 오로라 VOC(Case) ID' required=true)
        public String recordId;
    }

    public class Result {
        @InvocableVariable(label='AI 해결 가이드' description='근거 표시가 붙은 해결 가이드와 출처 목록')
        public String message;
    }

    @InvocableMethod(label='오로라 AI 해결 가이드(RAG)' description='현재 VOC와 비슷한 과거 해결 사례·게시 위키·정비 이력을 근거로 해결 방법을 정리합니다. 문장마다 근거 번호가 붙고, 근거가 부족하면 그렇게 알립니다. 기록을 바꾸지 않습니다.')
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            Case base = AuroraAgentSupport.vocOrNull(r.recordId);
            if (base == null) {
                res.message = AuroraAgentSupport.NOT_VOC;
            } else {
                AuroraRagService.Answer a = AuroraRagService.answer(base.Id);
                List<String> lines = new List<String>{ a.text, '', '출처' };
                for (AuroraRagService.Evidence e : a.evidence) {
                    lines.add('[' + e.label + '] ' + e.sourceType + ' · ' + e.title + ' (' + e.why + ')');
                }
                if (a.evidence.isEmpty()) {
                    lines.add('- 없음');
                }
                res.message = String.join(lines, '\n');
            }
            out.add(res);
        }
        return out;
    }
}