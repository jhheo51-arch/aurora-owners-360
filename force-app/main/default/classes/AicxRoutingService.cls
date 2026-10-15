/**
 * 오로라 AI 상담(AICX) 판단 — PRD §20-3·20-4. 연결·배정·자동 안내 허용은 이 Apex 규칙이 정하고,
 * AI(Prompt Template)는 안내 문장만 만든다. 기준값은 Aicx_Rule__mdt(KR_Default).
 * v4.3 판정 순서(docs/design/v4.3-aicx-intents.md §3): 즉시 연결(R1·R6·R8·R9) → 정보 조회(I1~I5, 이력 규칙은 '상담원 참고')
 * → 문제 문의(위키 + R2~R5·R7) → 어디에도 안 맞음(AI 접수).
 */
public with sharing class AicxRoutingService {
    public static final String HANDOFF = 'HANDOFF';
    public static final String GUIDE = 'GUIDE';
    public static final String NO_MATCH = 'NO_MATCH';
    public static final String INFO = 'INFO';
    public static final String SAFETY = '안전 결함';
    public static final String CHARGING = '충전·배터리';

    public class Identity {
        @AuraEnabled public Id contactId;
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public String name;
        @AuraEnabled public String grade;
        @AuraEnabled public String risk;
        @AuraEnabled public String vehicleLabel;
    }

    public class Hit {
        @AuraEnabled public String code;
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
        public Hit(String code, String label, String detail) { this.code = code; this.label = label; this.detail = detail; }
    }

    public class Decision {
        @AuraEnabled public String action;
        @AuraEnabled public String category;
        @AuraEnabled public List<Hit> rules = new List<Hit>();
        @AuraEnabled public Id advisorId;
        @AuraEnabled public String advisorName;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String managerName;
        @AuraEnabled public Boolean needsManager = false;
        @AuraEnabled public String assignReason;
        @AuraEnabled public AicxSelfHelpService.Match wiki;
        @AuraEnabled public AicxInfoService.Intent intent;
        @AuraEnabled public AicxInfoService.Answer info;
        @AuraEnabled public List<Hit> notes = new List<Hit>();   // 정보 조회일 때 이력 규칙(R2~R5) — 연결 사유가 아니라 상담원 참고
        public String handoffReason() {
            List<String> parts = new List<String>();
            for (Hit h : rules) {
                parts.add(h.code + ' ' + h.label + (String.isBlank(h.detail) ? '' : '(' + h.detail + ')'));
            }
            return String.join(parts, ' · ').left(255);
        }
    }

    // ===== 본인 확인 =====
    public static Identity identify(String phone, String plate4) {
        String p = digits(phone);
        String plate = digits(plate4);
        if (p.length() < 8 || plate.length() != 4) {
            return null;
        }
        String pattern = '%' + plate;
        for (Vehicle__c v : [SELECT Id, Name, Plate_Number__c, Vehicle_Model__r.Name, Owner_Contact__c, Owner_Contact__r.Name,
                                    Owner_Contact__r.Phone, Owner_Contact__r.Customer_Grade__c, Owner_Contact__r.Risk_Level__c
                             FROM Vehicle__c WHERE Plate_Number__c LIKE :pattern AND Owner_Contact__c != null]) {
            if (digits(v.Owner_Contact__r.Phone) == p) {
                Identity i = new Identity();
                i.contactId = v.Owner_Contact__c;
                i.vehicleId = v.Id;
                i.name = v.Owner_Contact__r.Name;
                i.grade = v.Owner_Contact__r.Customer_Grade__c;
                i.risk = v.Owner_Contact__r.Risk_Level__c;
                i.vehicleLabel = v.Name + (v.Vehicle_Model__r == null ? '' : ' ' + v.Vehicle_Model__r.Name) + ' ' + v.Plate_Number__c;
                return i;
            }
        }
        return null;
    }

    // ===== 규칙 판정 =====
    public static Decision evaluate(Id contactId, Id vehicleId, String message) {
        Aicx_Rule__mdt rule = Aicx_Rule__mdt.getInstance('KR_Default');
        String msg = message == null ? '' : message;
        Decision d = new Decision();
        d.category = categorize(msg, rule);

        // 1) 즉시 연결: 메시지 자체가 사람을 불러야 하는 경우
        List<Hit> immediate = new List<Hit>();
        String safetyWord = firstMatch(msg, rule == null ? null : rule.Safety_Keywords__c);
        if (safetyWord != null) {
            immediate.add(new Hit('R1', '안전 키워드', safetyWord));
        }
        String complaint = firstMatch(msg, rule == null ? null : rule.Complaint_Keywords__c);
        if (complaint != null) {
            immediate.add(new Hit('R6', '강한 불만', complaint));
        }
        String emotion = firstMatch(msg, rule == null ? null : rule.Emotion_Keywords__c);
        if (emotion != null) {
            immediate.add(new Hit('R8', '화남', emotion));
        }
        String human = firstMatch(msg, rule == null ? null : rule.Human_Keywords__c);
        if (human != null) {
            immediate.add(new Hit('R9', '사람 요청', human));
        }

        List<Hit> history = historyHits(contactId, vehicleId, d.category, rule);

        // 2) 정보 조회: 고객 이력은 연결 사유로 쓰지 않는다(상담원 참고만)
        if (immediate.isEmpty()) {
            d.intent = AicxInfoService.detect(msg, rule);
            if (d.intent != null) {
                d.notes = history;
                d.category = d.intent.code == AicxInfoService.MAINTENANCE || d.intent.code == AicxInfoService.REPAIR ? '정비 서비스' : '기타';
                d.info = AicxInfoService.answer(d.intent.code, contactId, vehicleId);
                if (d.info != null) {
                    if (d.intent.others > 0) {
                        d.info.text += '\n다른 것도 궁금하시면 이어서 물어봐 주세요.';
                    }
                    d.action = INFO;
                    return d;
                }
                d.rules.add(new Hit('AI', 'AI 답변 불가', d.intent.code + ' ' + d.intent.label + ' 데이터 없음'));
                d.action = HANDOFF;
                assign(d, contactId, false);
                return d;
            }
        }

        // 3) 문제 문의: 위키 + 이력 규칙
        d.rules.addAll(immediate);
        d.rules.addAll(history);
        d.wiki = AicxSelfHelpService.matchWiki(vehicleId, msg);
        if (d.wiki != null && !d.wiki.allowed) {
            d.rules.add(new Hit('R7', '자동 해결 범위 밖', d.wiki.title + ': ' + d.wiki.reason));
        }
        sortRules(d.rules);

        d.action = !d.rules.isEmpty() ? HANDOFF : (d.wiki != null ? GUIDE : NO_MATCH);
        assign(d, contactId, safetyWord != null);
        return d;
    }

    /** 고객 이력 규칙 R2~R5. AI 정보 안내 기록은 세지 않는다(D3: 단순 문의가 다음 상담을 막지 않게). */
    static List<Hit> historyHits(Id contactId, Id vehicleId, String category, Aicx_Rule__mdt rule) {
        List<Hit> hits = new List<Hit>();
        Integer threshold = rule == null || rule.VOC_90d_Threshold__c == null ? 2 : rule.VOC_90d_Threshold__c.intValue();
        Datetime since = Datetime.now().addDays(-90);
        Integer recent = [SELECT COUNT() FROM Case WHERE ContactId = :contactId AND VOC_Status__c != null AND CreatedDate >= :since
                          AND AI_Outcome__c != :AicxInfoService.AI_INFO];
        List<Case> sameOpen = vehicleId == null ? new List<Case>() : [
            SELECT CaseNumber FROM Case WHERE Vehicle__c = :vehicleId AND VOC_Category__c = :category
            AND VOC_Status__c != null AND VOC_Status__c != '종결' LIMIT 1];
        if (recent >= threshold || !sameOpen.isEmpty()) {
            hits.add(new Hit('R2', '반복 문의', recent >= threshold
                ? '최근 90일 VOC ' + recent + '건'
                : '같은 차량·같은 유형 진행 중 VOC ' + sameOpen[0].CaseNumber));
        }

        List<String> past = new List<String>();
        if ([SELECT COUNT() FROM Case WHERE ContactId = :contactId AND Escalation_Status__c IN ('요청', '처리완료')] > 0) {
            past.add('이관 이력');
        }
        if ([SELECT COUNT() FROM Case WHERE ContactId = :contactId AND VOC_Status__c = '종결' AND SLA_Met__c = false
             AND AI_Outcome__c != :AicxInfoService.AI_INFO] > 0) {
            past.add('기한 위반 종결');
        }
        if ([SELECT COUNT() FROM Compensation__c WHERE Case__r.ContactId = :contactId AND Approval_Status__c = '반려'] > 0) {
            past.add('보상 반려');
        }
        if (!past.isEmpty()) {
            hits.add(new Hit('R3', '과거 문제 이력', String.join(past, ', ')));
        }

        Contact c = [SELECT Customer_Grade__c, Risk_Level__c FROM Contact WHERE Id = :contactId];
        if (c.Customer_Grade__c == '플래티넘' || c.Risk_Level__c == '높음') {
            hits.add(new Hit('R4', 'VIP·위험', c.Customer_Grade__c == '플래티넘' ? '플래티넘' : '위험 높음'));
        }

        List<Vehicle__c> lemon = [SELECT Name, Lemon_Law_Status__c FROM Vehicle__c
                                  WHERE Owner_Contact__c = :contactId AND Lemon_Law_Status__c IN ('대상 가능', '주의') LIMIT 1];
        if (!lemon.isEmpty()) {
            hits.add(new Hit('R5', '레몬법', lemon[0].Name + ' ' + lemon[0].Lemon_Law_Status__c));
        }
        return hits;
    }

    /** 사유 표시 순서를 규칙 번호 순으로(R1 → R9) */
    static void sortRules(List<Hit> hits) {
        Map<String, List<Hit>> byCode = new Map<String, List<Hit>>();
        for (Hit h : hits) {
            if (!byCode.containsKey(h.code)) {
                byCode.put(h.code, new List<Hit>());
            }
            byCode.get(h.code).add(h);
        }
        List<String> keys = new List<String>(byCode.keySet());
        keys.sort();
        hits.clear();
        for (String k : keys) {
            hits.addAll(byCode.get(k));
        }
    }

    /** 배정 규칙(§20-4): ① 진행 중 VOC 기존 담당 ② 안전 → 상담팀장 이관 ③ 충전·배터리 → EV 기술 상담 ④ 진행 중 VOC가 가장 적은 상담원.
     *  담당자는 이름이 아니라 역할로 찾는다(AuroraStaffDirectory, v4.5). */
    public static void assign(Decision d, Id contactId, Boolean safety) {
        List<Case> existing = [SELECT Advisor__c, Advisor__r.Name, Advisor__r.Active__c, CaseNumber FROM Case
                               WHERE ContactId = :contactId AND Advisor__c != null AND VOC_Status__c != null AND VOC_Status__c != '종결'
                               ORDER BY CreatedDate DESC LIMIT 1];
        Care_Staff__c ev = AuroraStaffDirectory.firstByRole(AuroraStaffDirectory.EV_TECH);
        Care_Staff__c advisor;
        if (!existing.isEmpty() && existing[0].Advisor__r.Active__c == true) {
            advisor = new Care_Staff__c(Id = existing[0].Advisor__c, Name = existing[0].Advisor__r.Name);
            d.assignReason = '① 진행 중 VOC ' + existing[0].CaseNumber + '의 기존 담당';
        } else if (d.category == CHARGING && ev != null) {
            advisor = ev;
            d.assignReason = '③ 충전·배터리 → ' + AuroraStaffDirectory.EV_TECH;
        } else {
            advisor = leastLoaded();
            d.assignReason = '④ 진행 중 VOC가 가장 적은 상담원';
        }
        Care_Staff__c lead = AuroraStaffDirectory.firstByRole(AuroraStaffDirectory.TEAM_LEAD);
        if (safety && lead != null) {
            d.needsManager = true;
            d.assignReason = '② 안전 결함 → 담당 팀장 ' + lead.Name + ' 이관(' + AuroraStaffDirectory.label(AuroraStaffDirectory.QUALITY)
                + ' 공유) · 상담원은 ' + d.assignReason;
        }
        if (advisor != null) {
            d.advisorId = advisor.Id;
            d.advisorName = advisor.Name;
        }
        Care_Staff__c manager = lead != null ? lead : null;
        if (manager != null) {
            d.managerId = manager.Id;
            d.managerName = manager.Name;
        }
    }

    static Care_Staff__c leastLoaded() {
        Map<Id, Integer> load = new Map<Id, Integer>();
        List<Care_Staff__c> advisors = [SELECT Id, Name FROM Care_Staff__c WHERE Role__c = :AuroraStaffDirectory.ADVISOR AND Active__c = true ORDER BY Staff_Number__c];
        for (Care_Staff__c s : advisors) {
            load.put(s.Id, 0);
        }
        for (AggregateResult ar : [SELECT Advisor__c a, COUNT(Id) n FROM Case
                                   WHERE Advisor__c IN :load.keySet() AND VOC_Status__c != null AND VOC_Status__c != '종결'
                                   GROUP BY Advisor__c]) {
            load.put((Id) ar.get('a'), (Integer) ar.get('n'));
        }
        Care_Staff__c best;
        for (Care_Staff__c s : advisors) {
            if (best == null || load.get(s.Id) < load.get(best.Id)) {
                best = s;
            }
        }
        return best;
    }

    public static String categorize(String msg, Aicx_Rule__mdt rule) {
        if (firstMatch(msg, rule == null ? null : rule.Safety_Keywords__c) != null) {
            return SAFETY;
        }
        if (containsAny(msg, new List<String>{ '충전', '배터리', '충전기', '급속', '완속' })) {
            return CHARGING;
        }
        if (containsAny(msg, new List<String>{ '앱', '로그인', '원격', '블루투스', '내비' })) {
            return '커넥티드카 앱';
        }
        if (containsAny(msg, new List<String>{ '출고', '인도', '배송', '계약' })) {
            return '출고·인도';
        }
        if (containsAny(msg, new List<String>{ '정비', '예약', '서비스센터', '입고' })) {
            return '정비 서비스';
        }
        return '품질 결함';
    }

    static String firstMatch(String msg, String csv) {
        if (String.isBlank(csv)) {
            return null;
        }
        for (String w : csv.split(',')) {
            if (String.isNotBlank(w) && msg.contains(w.trim())) {
                return w.trim();
            }
        }
        return null;
    }

    static Boolean containsAny(String msg, List<String> words) {
        for (String w : words) {
            if (msg.contains(w)) {
                return true;
            }
        }
        return false;
    }

    static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }
}
