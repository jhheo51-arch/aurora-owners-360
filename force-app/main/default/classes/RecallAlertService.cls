/**
 * 리콜 조기 경보(v4, PRD §19). 안전 결함 VOC가 저장되면 같은 모델 계열 + 같은 계통의 안전 결함 VOC를
 * 기준 기간(Recall_Rule__mdt.KR_Default, 종결 포함) 안에서 세어, 기준 건수 이상이면 Recall_Alert__c를 만들거나 갱신한다.
 * 계통 추정 순서: 고장 유형 계통 → VOC 부품 계통 → 제목·내용 키워드. 담당은 역할 '품질·안전 대응' 직원(AuroraStaffDirectory),
 * 벨 알림은 로그인 사용자(대리 수신).
 */
public with sharing class RecallAlertService {
    public static final String SAFETY = '안전 결함';
    public static final String CLOSED = '종결';
    static Boolean running = false;

    // 계통 키워드는 AuroraSystemKeywords.BASE(공용, v4.5) — 정확한 말만 써서 계통을 확정한다

    public static void onCases(List<Case> cases, Map<Id, Case> oldMap) {
        if (running) {
            return;
        }
        Set<Id> touched = new Set<Id>();
        for (Case c : cases) {
            Case old = oldMap == null ? null : oldMap.get(c.Id);
            Boolean relevant = c.VOC_Category__c == SAFETY && c.Vehicle__c != null && (old == null
                || old.VOC_Category__c != c.VOC_Category__c || old.Vehicle__c != c.Vehicle__c
                || old.Failure_Mode__c != c.Failure_Mode__c || old.Subject != c.Subject);
            if (relevant) {
                touched.add(c.Id);
            }
        }
        if (!touched.isEmpty()) {
            evaluate(touched);
        }
    }

    public static void evaluate(Set<Id> caseIds) {
        Recall_Rule__mdt rule = Recall_Rule__mdt.getInstance('KR_Default');
        Integer windowDays = rule == null || rule.Window_Days__c == null ? 90 : rule.Window_Days__c.intValue();
        Integer threshold = rule == null || rule.Threshold__c == null ? 2 : rule.Threshold__c.intValue();

        Map<Id, String> keyOfTouched = new Map<Id, String>();
        Set<String> lines = new Set<String>();
        for (Case c : query(caseIds, null, null)) {
            String key = keyOf(c);
            if (key != null) {
                keyOfTouched.put(c.Id, key);
                lines.add(key.substringBefore('|'));
            }
        }
        if (lines.isEmpty()) {
            return;
        }

        Map<String, List<Case>> groups = new Map<String, List<Case>>();
        for (Case c : query(null, lines, Datetime.now().addDays(-windowDays))) {
            String key = keyOf(c);
            if (key == null || !keyOfTouched.values().contains(key)) {
                continue;
            }
            if (!groups.containsKey(key)) {
                groups.put(key, new List<Case>());
            }
            groups.get(key).add(c);
        }

        Map<String, Recall_Alert__c> openAlerts = new Map<String, Recall_Alert__c>();
        for (Recall_Alert__c a : [SELECT Id, Name, Model_Line__c, System__c, VOC_Count__c, First_Detected_At__c
                                  FROM Recall_Alert__c WHERE Status__c != :CLOSED AND Model_Line__c IN :lines
                                  ORDER BY CreatedDate]) {
            openAlerts.put(a.Model_Line__c + '|' + a.System__c, a);
        }
        Care_Staff__c quality = AuroraStaffDirectory.firstByRole(AuroraStaffDirectory.QUALITY);

        List<Recall_Alert__c> upserts = new List<Recall_Alert__c>();
        Map<String, Boolean> notify = new Map<String, Boolean>();
        for (String key : groups.keySet()) {
            List<Case> members = groups.get(key);
            if (members.size() < threshold) {
                continue;
            }
            Recall_Alert__c a = openAlerts.containsKey(key) ? openAlerts.get(key) : new Recall_Alert__c(
                Model_Line__c = key.substringBefore('|'), System__c = key.substringAfter('|'),
                Status__c = '신규', First_Detected_At__c = Datetime.now(),
                Assigned_Staff__c = quality == null ? null : quality.Id);
            Boolean increased = a.Id == null || a.VOC_Count__c == null || members.size() > a.VOC_Count__c;
            List<String> numbers = new List<String>();
            for (Case c : members) {
                numbers.add(c.CaseNumber + ' ' + c.Subject);
            }
            Case latest = members[members.size() - 1];
            a.VOC_Count__c = members.size();
            a.Last_Detected_At__c = Datetime.now();
            a.Latest_Case__c = latest.Id;
            a.Summary__c = (a.Model_Line__c + ' · ' + a.System__c + ' 계통 안전 결함 VOC ' + members.size() + '건 (최근 '
                + windowDays + '일, 기준 ' + threshold + '건)\n- ' + String.join(numbers, '\n- ')).left(2000);
            upserts.add(a);
            notify.put(key, increased);
        }
        if (upserts.isEmpty()) {
            return;
        }
        upsert upserts;

        List<Case> links = new List<Case>();
        for (Recall_Alert__c a : upserts) {
            for (Case c : groups.get(a.Model_Line__c + '|' + a.System__c)) {
                if (c.Recall_Alert__c != a.Id) {
                    links.add(new Case(Id = c.Id, Recall_Alert__c = a.Id));
                }
            }
        }
        running = true;
        try {
            update links;
        } finally {
            running = false;
        }
        sendNotifications(upserts, notify);
    }

    /** 모델 계열|계통. 둘 중 하나라도 모르면 null(묶지 않음). */
    public static String keyOf(Case c) {
        String line = c.Vehicle__r == null || c.Vehicle__r.Vehicle_Model__r == null ? null : c.Vehicle__r.Vehicle_Model__r.Model_Line__c;
        String sys = systemOf(c);
        return line == null || sys == null ? null : line + '|' + sys;
    }

    public static String systemOf(Case c) {
        if (c.Failure_Mode__r != null && String.isNotBlank(c.Failure_Mode__r.System__c)) {
            return c.Failure_Mode__r.System__c;
        }
        for (Case_Part__c cp : c.Case_Parts__r) {
            if (cp.Part__r != null && String.isNotBlank(cp.Part__r.System__c)) {
                return cp.Part__r.System__c;
            }
        }
        String text = (c.Subject == null ? '' : c.Subject) + ' ' + (c.Description == null ? '' : c.Description);
        return AuroraSystemKeywords.firstSystem(text);
    }

    static List<Case> query(Set<Id> ids, Set<String> lines, Datetime since) {
        String soql = 'SELECT Id, CaseNumber, Subject, Description, Recall_Alert__c, Vehicle__r.Vehicle_Model__r.Model_Line__c, '
            + 'Failure_Mode__r.System__c, (SELECT Part__r.System__c FROM Case_Parts__r ORDER BY CreatedDate LIMIT 1) '
            + 'FROM Case WHERE VOC_Category__c = :SAFETY';
        if (ids != null) {
            soql += ' AND Id IN :ids';
        }
        if (lines != null) {
            soql += ' AND Vehicle__r.Vehicle_Model__r.Model_Line__c IN :lines AND CreatedDate >= :since';
        }
        return Database.query(soql + ' ORDER BY CreatedDate, CaseNumber');
    }

    static void sendNotifications(List<Recall_Alert__c> alerts, Map<String, Boolean> notify) {
        List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Aurora_Recall_Alert' LIMIT 1];
        if (types.isEmpty()) {
            return;
        }
        // v4.4: 계통별 공급사·담당자(부품 카탈로그 기준)를 알림 문구에 함께 적는다
        Map<String, Set<String>> suppliers = new Map<String, Set<String>>();
        for (Part__c p : [SELECT System__c, Supplier__r.Name, Supplier_Contact__r.Name FROM Part__c WHERE Supplier__c != null]) {
            if (!suppliers.containsKey(p.System__c)) {
                suppliers.put(p.System__c, new Set<String>());
            }
            suppliers.get(p.System__c).add(p.Supplier__r.Name + (p.Supplier_Contact__r == null ? '' : ' 담당 ' + p.Supplier_Contact__r.Name));
        }
        for (Recall_Alert__c a : alerts) {
            if (!notify.get(a.Model_Line__c + '|' + a.System__c)) {
                continue;
            }
            String share = suppliers.containsKey(a.System__c)
                ? ' 공급사 ' + String.join(new List<String>(suppliers.get(a.System__c)), ', ') + '에 공유 필요.' : '';
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(types[0].Id);
            n.setTargetId(a.Id);
            n.setTitle('⚠ 리콜 조기 경보 · ' + a.Model_Line__c + ' ' + a.System__c + ' 계통 ' + a.VOC_Count__c.intValue() + '건');
            n.setBody(AuroraStaffDirectory.label(AuroraStaffDirectory.QUALITY) + ' 검토 필요. 같은 모델 계열·계통 안전 결함 VOC가 기준 이상입니다.' + share);
            try {
                n.send(new Set<String>{ UserInfo.getUserId() });
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, '리콜 경보 알림 실패: ' + e.getMessage());
            }
        }
    }
}
