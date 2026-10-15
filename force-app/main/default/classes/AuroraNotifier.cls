/**
 * v4.4 P-3 업무 알림(docs/design/v4.4-feedback.md F1). 벨 알림 + Salesforce 모바일 앱 push(알림 유형 mobile=true).
 *  N1 팀장 이관(안전 결함이면 [안전]) · N2 보상 승인 요청 · N3 응답 기한 임박/초과 · N4 AI 상담 상담사 연결
 * 직원(Care_Staff__c)은 Salesforce 사용자가 아니라서 받는 사람은 레코드 소유자(로그인 사용자)이고, 문구에 대상 직원을 적는다.
 * 실제 회사라면 recipients()만 Care_Staff__c.User__c 기준으로 바꾸면 된다.
 * 중복 방지: 보낸 코드를 Alert_Codes_Sent__c에 남긴다(before 트리거에서 표시 → after 트리거에서 새로 표시된 것만 발송).
 */
public with sharing class AuroraNotifier {
    public static final String TYPE_NAME = 'Aurora_Work_Alert';
    static final Integer MAX_PER_TRANSACTION = 10;   // 샘플 대량 적재 때 알림 폭주 방지
    static final String SAFETY = '안전 결함';
    static Integer sentThisTransaction = 0;

    // ===== 공통 =====
    @TestVisible
    static Boolean has(String codes, String code) {
        return String.isNotBlank(codes) && (',' + codes + ',').contains(',' + code + ',');
    }

    @TestVisible
    static String add(String codes, String code) {
        return has(codes, code) ? codes : (String.isBlank(codes) ? code : codes + ',' + code);
    }

    /** 받는 사람: 레코드 소유자가 사용자면 그 사람, 아니면(대기열 등) 실행 사용자 */
    static Set<String> recipients(Id ownerId) {
        if (ownerId != null && String.valueOf(ownerId).startsWith('005')) {
            return new Set<String>{ ownerId };
        }
        return new Set<String>{ UserInfo.getUserId() };
    }

    public static void send(Id targetId, Id ownerId, String title, String body) {
        if (sentThisTransaction >= MAX_PER_TRANSACTION) {
            return;
        }
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :TYPE_NAME LIMIT 1];
        if (types.isEmpty()) {
            return;
        }
        Messaging.CustomNotification n = new Messaging.CustomNotification();
        n.setNotificationTypeId(types[0].Id);
        n.setTargetId(targetId);
        n.setTitle(title.left(250));
        n.setBody(String.isBlank(body) ? ' ' : body.left(750));
        try {
            n.send(recipients(ownerId));
            sentThisTransaction++;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, '업무 알림 실패: ' + e.getMessage());
        }
    }

    // ===== Case: N1·N4 (before에서 표시, after에서 발송) =====
    public static void markCases(List<Case> cases, Map<Id, Case> oldMap) {
        for (Case c : cases) {
            Case old = oldMap == null ? null : oldMap.get(c.Id);
            if (c.Escalation_Status__c == '요청' && (old == null || old.Escalation_Status__c != '요청')) {
                c.Alert_Codes_Sent__c = add(c.Alert_Codes_Sent__c, 'N1');
            }
            if (old == null && c.AI_Outcome__c == '상담사 연결') {
                c.Alert_Codes_Sent__c = add(c.Alert_Codes_Sent__c, 'N4');
            }
        }
    }

    public static void sendCases(List<Case> cases, Map<Id, Case> oldMap) {
        Map<Id, Set<String>> fresh = new Map<Id, Set<String>>();
        for (Case c : cases) {
            String before = oldMap == null ? null : oldMap.get(c.Id).Alert_Codes_Sent__c;
            for (String code : new List<String>{ 'N1', 'N4' }) {
                if (has(c.Alert_Codes_Sent__c, code) && !has(before, code)) {
                    if (!fresh.containsKey(c.Id)) {
                        fresh.put(c.Id, new Set<String>());
                    }
                    fresh.get(c.Id).add(code);
                }
            }
        }
        if (fresh.isEmpty()) {
            return;
        }
        for (Case c : [SELECT Id, OwnerId, CaseNumber, Subject, VOC_Category__c, Escalation_Reason__c, Handoff_Reason__c,
                              Advisor__r.Name, Manager_Employee__r.Name, Contact.Name
                       FROM Case WHERE Id IN :fresh.keySet()]) {
            Set<String> codes = fresh.get(c.Id);
            if (codes.contains('N1')) {
                Boolean safety = c.VOC_Category__c == SAFETY;
                send(c.Id, c.OwnerId,
                    (safety ? '[안전] ' : '[이관] ') + '팀장 ' + nameOr(c.Manager_Employee__r, '미지정') + '님께 이관: VOC ' + c.CaseNumber + ' ' + c.Subject,
                    '이관 사유: ' + (c.Escalation_Reason__c == null ? '-' : c.Escalation_Reason__c)
                        + (safety ? ' · 2시간 안에 확인하고 ' + AuroraStaffDirectory.label(AuroraStaffDirectory.QUALITY) + '에게 공유하세요.' : ''));
            }
            if (codes.contains('N4')) {
                send(c.Id, c.OwnerId,
                    '[AI 상담 연결] ' + nameOr(c.Advisor__r, '상담원') + '님: ' + nameOr(c.Contact, '고객') + ' 고객 · VOC ' + c.CaseNumber,
                    '연결 사유: ' + (c.Handoff_Reason__c == null ? '-' : c.Handoff_Reason__c));
            }
        }
    }

    // ===== 보상·조치: N2 =====
    /** 승인 단계는 공용 규칙 AuroraApprovalRule(수식 Approval_Level__c와 같은 기준, v4.5) */
    @TestVisible
    static String approvalLevel(Compensation__c m) {
        return AuroraApprovalRule.level(m);
    }

    public static void markCompensations(List<Compensation__c> rows, Map<Id, Compensation__c> oldMap) {
        for (Compensation__c m : rows) {
            Compensation__c old = oldMap == null ? null : oldMap.get(m.Id);
            Boolean becameRequest = m.Approval_Status__c == '요청' && (old == null || old.Approval_Status__c != '요청');
            if (becameRequest && approvalLevel(m) != AuroraApprovalRule.NONE) {
                m.Alert_Codes_Sent__c = add(m.Alert_Codes_Sent__c, 'N2');
            }
        }
    }

    public static void sendCompensations(List<Compensation__c> rows, Map<Id, Compensation__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Compensation__c m : rows) {
            String before = oldMap == null ? null : oldMap.get(m.Id).Alert_Codes_Sent__c;
            if (has(m.Alert_Codes_Sent__c, 'N2') && !has(before, 'N2')) {
                ids.add(m.Id);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        for (Compensation__c m : [SELECT Id, Name, Amount__c, Compensation_Type__c, Case__r.OwnerId, Case__r.CaseNumber,
                                         Case__r.Manager_Employee__r.Name
                                  FROM Compensation__c WHERE Id IN :ids]) {
            String level = approvalLevel(m);
            String approver = level == AuroraApprovalRule.UPPER
                ? AuroraStaffDirectory.label(AuroraStaffDirectory.COMPENSATION) + '·' + AuroraStaffDirectory.label(AuroraStaffDirectory.CENTER_HEAD)
                : '팀장 ' + nameOr(m.Case__r.Manager_Employee__r, '미지정');
            send(m.Id, m.Case__r.OwnerId,
                '[승인 요청] ' + approver + '님: ' + m.Name + ' ' + m.Compensation_Type__c + ' ' + AicxInfoService.km(m.Amount__c) + '원',
                'VOC ' + m.Case__r.CaseNumber + ' · ' + level + '. 보상·조치 화면의 [승인·반려] 버튼으로 처리하세요.');
        }
    }

    // ===== N3: 응답 기한 임박·초과 (Flow Aurora_SLA_Reminder 예약 경로에서 호출) =====
    public class SlaRequest {
        @InvocableVariable(required=true label='VOC Id') public Id recordId;
        @InvocableVariable(required=true label='구분(SOON/OVER)') public String kind;
    }

    @InvocableMethod(label='오로라 응답 기한 알림' description='첫 응답 없는 VOC의 기한 임박(1시간 전)·초과 알림. 레코드당 구분별 1회')
    public static void slaReminder(List<SlaRequest> requests) {
        Map<Id, String> kindById = new Map<Id, String>();
        for (SlaRequest r : requests) {
            kindById.put(r.recordId, r.kind == 'OVER' ? 'N3-OVER' : 'N3-SOON');
        }
        List<Case> updates = new List<Case>();
        for (Case c : [SELECT Id, OwnerId, CaseNumber, Subject, Alert_Codes_Sent__c, First_Response_At__c, VOC_Status__c,
                              Response_Due_At__c, Response_Due_KST__c, Advisor__r.Name, Current_Handler__r.Name
                       FROM Case WHERE Id IN :kindById.keySet()]) {
            String code = kindById.get(c.Id);
            // 예약 시점과 달리 이미 첫 응답·종결됐으면 보내지 않는다
            if (c.First_Response_At__c != null || c.VOC_Status__c == '종결' || c.Response_Due_At__c == null || has(c.Alert_Codes_Sent__c, code)) {
                continue;
            }
            Boolean over = code == 'N3-OVER';
            Long minutes = (c.Response_Due_At__c.getTime() - Datetime.now().getTime()) / 60000;
            String who = nameOr(c.Current_Handler__r, nameOr(c.Advisor__r, '담당자'));
            send(c.Id, c.OwnerId,
                (over ? '[기한 초과] ' : '[기한 임박] ') + who + '님 VOC ' + c.CaseNumber + ' ' + c.Subject,
                '응답 기한 ' + c.Response_Due_KST__c + (over ? ' 지남' : (minutes > 0 ? ' · ' + minutes + '분 남음' : '')) + ' · 첫 응답 전입니다.');
            updates.add(new Case(Id = c.Id, Alert_Codes_Sent__c = add(c.Alert_Codes_Sent__c, code)));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    static String nameOr(SObject rel, String fallback) {
        return rel == null || rel.get('Name') == null ? fallback : (String) rel.get('Name');
    }
}
