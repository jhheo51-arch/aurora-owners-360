/**
 * VOC Care Assistant 액션: 팀장 이관 요청 (v4). Agent는 실행 전에 사용자 확인을 받는다(PRD Q55).
 * '팀장 도움 필요'와 사유만 저장하고, 실제 이관(담당 팀장·현재 처리 직원·이관 상태)은 v1 Flow가 처리한다.
 * 유효성 규칙 등 사람과 같은 규칙이 그대로 적용된다(가드레일).
 */
public with sharing class AuroraEscalationAction {
    public class Request {
        @InvocableVariable(label='VOC 레코드 ID' description='현재 열린 오로라 VOC(Case) ID' required=true)
        public String recordId;
        @InvocableVariable(label='이관 사유' description='팀장에게 넘기는 이유(사용자가 확인한 문장)' required=true)
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='이관 결과' description='이관 상태·담당 팀장·현재 처리 직원 또는 실패 사유')
        public String message;
        @InvocableVariable(label='성공 여부')
        public Boolean success;
    }

    @InvocableMethod(label='오로라 팀장 이관 요청' description='현재 VOC에 팀장 도움 필요와 사유를 저장해 v1 Flow가 상담팀장에게 이관하게 합니다. 사용자 확인 후에만 실행합니다.')
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            out.add(escalate(r.recordId, r.reason));
        }
        return out;
    }

    static Result escalate(String recordId, String reason) {
        Result res = new Result();
        res.success = false;
        Case c = AuroraAgentSupport.vocOrNull(recordId);
        if (c == null) {
            res.message = AuroraAgentSupport.NOT_VOC;
            return res;
        }
        if (c.VOC_Status__c == '종결') {
            res.message = '종결된 VOC는 이관할 수 없습니다.';
            return res;
        }
        if (c.Escalation_Status__c == '요청') {
            res.message = '이미 팀장 이관이 요청된 VOC입니다.' + current(c.Id);
            res.success = true;
            return res;
        }
        if (String.isBlank(reason)) {
            res.message = '이관 사유가 필요합니다.';
            return res;
        }
        try {
            Case upd = new Case(Id = c.Id, Needs_Manager__c = true, Assistance_Reason__c = ('[AI 에이전트] ' + reason.trim()).left(255));
            if (c.Manager_Employee__c == null && c.Advisor__r != null && c.Advisor__r.Manager__c != null) {
                upd.Manager_Employee__c = c.Advisor__r.Manager__c; // 사람이 하듯 담당 상담원의 팀장을 지정
            }
            update upd;
        } catch (DmlException e) {
            res.message = '저장하지 못했습니다(사람과 같은 규칙 적용): ' + e.getDmlMessage(0);
            return res;
        }
        res.success = true;
        res.message = '팀장 이관 요청을 저장했습니다.' + current(c.Id);
        return res;
    }

    static String current(Id caseId) {
        Case c = [SELECT Escalation_Status__c, Escalation_Reason__c, Manager_Employee__r.Name, Current_Handler__r.Name
                  FROM Case WHERE Id = :caseId];
        return ' 이관 상태: ' + c.Escalation_Status__c
            + ' · 담당 팀장: ' + (c.Manager_Employee__r == null ? '미지정' : c.Manager_Employee__r.Name)
            + ' · 현재 처리 직원: ' + (c.Current_Handler__r == null ? '미지정' : c.Current_Handler__r.Name)
            + (c.Escalation_Reason__c == null ? '' : ' · 이관 사유: ' + c.Escalation_Reason__c);
    }
}