/**
 * v4.2 VOC Care Assistant 업무 조회 (docs/design/v4.2-agent-anywhere.md §4). 어느 화면에서든 쓸 수 있는 읽기 전용 목록.
 * 구분: OPEN 진행 중 / DUE_SOON 기한 임박(첫 응답 없음·2시간 이내, 초과 포함 — 홈 히어로와 같은 기준) / OVERDUE 기한 초과 /
 *       SAFETY 안전 결함 진행 중 / ESCALATED 팀장 이관 대기 / RECALL 진행 중 리콜 경보.
 * 직원 이름을 주면 그 직원(담당 상담원 또는 현재 처리 직원) 것만, 없으면 전체(D4). 연락처(전화·이메일)는 내보내지 않는다.
 */
public with sharing class AuroraWorkQueryAction {
    static final Integer MAX_ROWS = 5;
    static final Map<String, String> LABELS = new Map<String, String>{
        'OPEN' => '진행 중 VOC', 'DUE_SOON' => '기한 임박 VOC(첫 응답 전·2시간 이내, 초과 포함)', 'OVERDUE' => '응답 기한 초과 VOC',
        'SAFETY' => '안전 결함 진행 중 VOC', 'ESCALATED' => '팀장 이관 대기 VOC', 'RECALL' => '진행 중 리콜 경보'
    };

    public class Request {
        @InvocableVariable(label='조회 구분' description='OPEN, DUE_SOON, OVERDUE, SAFETY, ESCALATED, RECALL 중 하나' required=true)
        public String queryType;
        @InvocableVariable(label='직원 이름' description='특정 상담 직원 것만 볼 때 이름(예: 미나미). 없으면 비워 둡니다.')
        public String staffName;
    }

    public class Result {
        @InvocableVariable(label='업무 조회 결과' description='건수와 기한 순 최대 5건 목록')
        public String message;
    }

    @InvocableMethod(label='오로라 업무 조회' description='진행 중·기한 임박·기한 초과·안전 결함·팀장 이관 대기 VOC나 리콜 경보를 기한 순 최대 5건과 건수로 보여 줍니다. 기록을 바꾸지 않습니다.')
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            res.message = query(r.queryType == null ? 'OPEN' : r.queryType.toUpperCase().trim(), r.staffName);
            out.add(res);
        }
        return out;
    }

    public static String query(String type, String staffName) {
        if (!LABELS.containsKey(type)) {
            return '조회 구분을 알 수 없습니다. 진행 중, 기한 임박, 기한 초과, 안전 결함, 이관 대기, 리콜 경보 중에서 말씀해 주세요.';
        }
        if (type == 'RECALL') {
            return recalls();
        }
        String staff = String.isBlank(staffName) ? null : staffName.trim();
        if (staff != null && [SELECT COUNT() FROM Care_Staff__c WHERE Name = :staff] == 0) {
            return '상담 직원 "' + staff + '"을(를) 찾지 못했습니다. 직원 이름을 확인해 주세요.';
        }
        Datetime now = Datetime.now();
        Datetime soon = now.addHours(2);
        List<Case> hits = new List<Case>();
        for (Case c : [SELECT Id, CaseNumber, Subject, VOC_Status__c, VOC_Category__c, Escalation_Status__c, Response_Due_At__c,
                              Response_Due_KST__c, First_Response_At__c, Advisor__r.Name, Current_Handler__r.Name
                       FROM Case WHERE VOC_Status__c != null AND VOC_Status__c != '종결'
                       ORDER BY Response_Due_At__c ASC NULLS LAST]) {
            if (staff != null && (c.Advisor__r == null || c.Advisor__r.Name != staff) && (c.Current_Handler__r == null || c.Current_Handler__r.Name != staff)) {
                continue;
            }
            Boolean noFirst = c.First_Response_At__c == null && c.Response_Due_At__c != null;
            Boolean match = type == 'OPEN'
                || (type == 'DUE_SOON' && noFirst && c.Response_Due_At__c < soon)
                || (type == 'OVERDUE' && noFirst && c.Response_Due_At__c < now)
                || (type == 'SAFETY' && c.VOC_Category__c == '안전 결함')
                || (type == 'ESCALATED' && c.Escalation_Status__c == '요청');
            if (match) {
                hits.add(c);
            }
        }
        String title = (staff == null ? '' : staff + ' 담당 ') + LABELS.get(type) + ' ' + hits.size() + '건';
        if (hits.isEmpty()) {
            return title + ' — 없습니다.';
        }
        List<String> lines = new List<String>{ title + (hits.size() > MAX_ROWS ? ' (기한 순 상위 ' + MAX_ROWS + '건)' : '') };
        for (Integer i = 0; i < hits.size() && i < MAX_ROWS; i++) {
            Case c = hits[i];
            String due = c.Response_Due_At__c == null ? '기한 없음'
                : (c.First_Response_At__c != null ? '첫 응답 완료' : (c.Response_Due_At__c < now ? '기한 초과 ' : '기한 ') + c.Response_Due_KST__c);
            lines.add((i + 1) + '. VOC ' + c.CaseNumber + ' · ' + c.Subject + ' · ' + c.VOC_Status__c
                + (c.VOC_Category__c == '안전 결함' ? ' · ⚠ 안전 결함' : '') + ' · ' + due
                + ' · 처리 ' + (c.Current_Handler__r == null ? '-' : c.Current_Handler__r.Name));
        }
        return String.join(lines, '\n');
    }

    static String recalls() {
        List<Recall_Alert__c> alerts = [SELECT Name, Model_Line__c, System__c, VOC_Count__c, Status__c, Assigned_Staff__r.Name
                                        FROM Recall_Alert__c WHERE Status__c != '종결' ORDER BY Last_Detected_At__c DESC];
        if (alerts.isEmpty()) {
            return '진행 중 리콜 경보 0건 — 없습니다.';
        }
        List<String> lines = new List<String>{ '진행 중 리콜 경보 ' + alerts.size() + '건' };
        for (Integer i = 0; i < alerts.size() && i < MAX_ROWS; i++) {
            Recall_Alert__c a = alerts[i];
            lines.add((i + 1) + '. ' + a.Name + ' · ' + a.Model_Line__c + ' ' + a.System__c + ' 계통 안전 결함 ' + a.VOC_Count__c.intValue() + '건 · '
                + a.Status__c + ' · 담당 ' + (a.Assigned_Staff__r == null ? '-' : a.Assigned_Staff__r.Name));
        }
        return String.join(lines, '\n');
    }
}