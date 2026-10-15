/**
 * v3.5 디자인 LWC 데이터: VOC 상황 카드·상태 배지·차주 360·보증 게이지·홈 히어로.
 * 배지는 기호+글자(색만으로 전달하지 않음). tone = danger / warn / ok / done / info.
 */
public with sharing class AuroraCardController {
    public class Badge {
        @AuraEnabled public String label;
        @AuraEnabled public String tone;
        Badge(String label, String tone) { this.label = label; this.tone = tone; }
    }

    public class Situation {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String category;
        @AuraEnabled public String priority;
        @AuraEnabled public String vocStatus;
        @AuraEnabled public Integer step;
        @AuraEnabled public Datetime dueAt;
        @AuraEnabled public Datetime firstResponseAt;
        @AuraEnabled public Boolean slaMet;
        @AuraEnabled public String handlerName;
        @AuraEnabled public String advisorName;
        @AuraEnabled public String managerName;
        @AuraEnabled public String escalationStatus;
        @AuraEnabled public Datetime escalatedAt;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String ownerRisk;
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public String vehicleLabel;
        @AuraEnabled public String tone;
        @AuraEnabled public List<Badge> badges = new List<Badge>();
    }

    public class Owner360 {
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String riskLevel;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public Decimal voc90;
        @AuraEnabled public Integer openVoc = 0;
        @AuraEnabled public Integer vehicleCount = 0;
        @AuraEnabled public String handlers;
        @AuraEnabled public String tone;
        @AuraEnabled public List<Badge> badges = new List<Badge>();
    }

    public class Gauge {
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Integer timePct;
        @AuraEnabled public Integer kmPct;
        @AuraEnabled public String detail;
        @AuraEnabled public String tone;
    }

    public class HomeRow {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String display;
        @AuraEnabled public Datetime dueAt;
        @AuraEnabled public String handlerName;
    }

    public class AlertRow {
        @AuraEnabled public Id alertId;
        @AuraEnabled public String label;
    }

    public class HomeHero {
        @AuraEnabled public List<AlertRow> alerts = new List<AlertRow>();
        @AuraEnabled public Integer open = 0;
        @AuraEnabled public Integer dueSoon = 0;
        @AuraEnabled public Integer escalated = 0;
        @AuraEnabled public Integer safety = 0;
        @AuraEnabled public List<HomeRow> rows = new List<HomeRow>();
    }

    static final Map<String, Integer> STEP = new Map<String, Integer>{ '접수' => 1, '확인 중' => 2, '조치 검토' => 3, '종결' => 4 };

    // ===== VOC =====
    @AuraEnabled(cacheable=true)
    public static Situation getVocSituation(Id caseId) {
        Case c = [SELECT Id, CaseNumber, Subject, VOC_Category__c, Priority, VOC_Status__c, Response_Due_At__c,
                         First_Response_At__c, SLA_Met__c, Escalation_Status__c, Escalated_At__c,
                         Current_Handler__r.Name, Advisor__r.Name, Manager_Employee__r.Name,
                         ContactId, Contact.Name, Contact.Risk_Level__c,
                         Vehicle__c, Vehicle__r.Name, Vehicle__r.Plate_Number__c, Vehicle__r.Vehicle_Model__r.Name,
                         Vehicle__r.Repeat_Defect__c, Vehicle__r.Repeat_Defect_System__c, Vehicle__r.Lemon_Law_Status__c,
                         Warranty_Scope__c, Warranty_Coverage__c, Applied_Warranty__r.Warranty_Type__c,
                         Total_Compensation__c, Pending_Approval_Count__c
                  FROM Case WHERE Id = :caseId];
        Situation s = new Situation();
        s.caseId = c.Id;
        s.caseNumber = c.CaseNumber;
        s.subject = c.Subject;
        s.category = c.VOC_Category__c;
        s.priority = c.Priority;
        s.vocStatus = c.VOC_Status__c;
        s.step = STEP.containsKey(c.VOC_Status__c) ? STEP.get(c.VOC_Status__c) : null;
        s.dueAt = c.Response_Due_At__c;
        s.firstResponseAt = c.First_Response_At__c;
        s.slaMet = c.SLA_Met__c;
        s.handlerName = c.Current_Handler__r == null ? null : c.Current_Handler__r.Name;
        s.advisorName = c.Advisor__r == null ? null : c.Advisor__r.Name;
        s.managerName = c.Manager_Employee__r == null ? null : c.Manager_Employee__r.Name;
        s.escalationStatus = c.Escalation_Status__c;
        s.escalatedAt = c.Escalated_At__c;
        s.ownerId = c.ContactId;
        s.ownerName = c.Contact == null ? null : c.Contact.Name;
        s.ownerRisk = c.Contact == null ? null : c.Contact.Risk_Level__c;
        s.vehicleId = c.Vehicle__c;
        if (c.Vehicle__r != null) {
            s.vehicleLabel = c.Vehicle__r.Name
                + (c.Vehicle__r.Vehicle_Model__r == null ? '' : ' ' + c.Vehicle__r.Vehicle_Model__r.Name)
                + (c.Vehicle__r.Plate_Number__c == null ? '' : ' ' + c.Vehicle__r.Plate_Number__c);
        }
        s.badges = caseBadges(c);
        s.tone = 'info';
        for (Badge b : s.badges) {
            if (b.tone == 'danger') { s.tone = 'danger'; break; }
            if (b.tone == 'warn') { s.tone = 'warn'; }
        }
        if (c.VOC_Status__c == '종결') {
            s.tone = 'done';
        }
        return s;
    }

    static List<Badge> caseBadges(Case c) {
        List<Badge> out = new List<Badge>();
        Boolean closed = c.VOC_Status__c == '종결';
        if (closed) {
            out.add(new Badge('✓ 종결', 'done'));
        }
        if (c.VOC_Category__c == '안전 결함') {
            out.add(new Badge('⚠ 안전 결함', 'danger'));
        }
        if (c.Escalation_Status__c == '요청') {
            out.add(new Badge('↑ 팀장 이관 요청' + (c.Manager_Employee__r == null ? '' : ' · ' + c.Manager_Employee__r.Name), 'warn'));
        } else if (c.Escalation_Status__c == '처리완료') {
            out.add(new Badge('↑ 이관 처리완료', 'done'));
        }
        if (c.Vehicle__r != null && c.Vehicle__r.Repeat_Defect__c) {
            out.add(new Badge('↻ 반복 결함 · ' + c.Vehicle__r.Repeat_Defect_System__c, 'warn'));
        }
        if (c.Vehicle__r != null && c.Vehicle__r.Lemon_Law_Status__c == '대상 가능') {
            out.add(new Badge('⚖ 레몬법 대상 가능', 'danger'));
        } else if (c.Vehicle__r != null && c.Vehicle__r.Lemon_Law_Status__c == '주의') {
            out.add(new Badge('⚖ 레몬법 주의', 'warn'));
        }
        if (!closed) {
            if (c.First_Response_At__c != null) {
                out.add(c.SLA_Met__c ? new Badge('✓ 기한 준수', 'ok') : new Badge('⏱ 기한 초과 응답', 'danger'));
            } else if (c.Response_Due_At__c != null && c.Response_Due_At__c < Datetime.now()) {
                out.add(new Badge('⏱ 기한 초과', 'danger'));
            } else if (c.Response_Due_At__c != null && c.Response_Due_At__c < Datetime.now().addHours(2)) {
                out.add(new Badge('⏳ 기한 임박', 'warn'));
            }
        }
        if (c.Warranty_Coverage__c) {
            out.add(new Badge('🛡 보증 적용' + (c.Applied_Warranty__r == null ? '' : ' · ' + c.Applied_Warranty__r.Warranty_Type__c), 'ok'));
        } else if (c.Warranty_Scope__c != null) {
            out.add(new Badge('🛡 보증 미적용 · ' + c.Warranty_Scope__c, 'done'));
        }
        if (c.Pending_Approval_Count__c != null && c.Pending_Approval_Count__c > 0) {
            out.add(new Badge('₩ 승인 대기 ' + c.Pending_Approval_Count__c.intValue() + '건', 'warn'));
        }
        if (c.Total_Compensation__c != null && c.Total_Compensation__c > 0) {
            out.add(new Badge('₩ 보상 승인 · ' + c.Total_Compensation__c.format() + '원', 'ok'));
        }
        return out;
    }

    // ===== 공용 배지 (Case / 고객 차량 / 연락처) =====
    @AuraEnabled(cacheable=true)
    public static List<Badge> getBadges(Id recordId) {
        Schema.SObjectType t = recordId.getSobjectType();
        if (t == Case.SObjectType) {
            return getVocSituation(recordId).badges;
        }
        if (t == Contact.SObjectType) {
            return getOwner360(recordId).badges;
        }
        List<Badge> out = new List<Badge>();
        if (t == Vehicle__c.SObjectType) {
            Vehicle__c v = [SELECT Repeat_Defect__c, Repeat_Defect_System__c, Lemon_Law_Status__c, Warranty_End_Date__c
                            FROM Vehicle__c WHERE Id = :recordId];
            if (v.Lemon_Law_Status__c == '대상 가능') {
                out.add(new Badge('⚖ 레몬법 대상 가능', 'danger'));
            } else if (v.Lemon_Law_Status__c == '주의') {
                out.add(new Badge('⚖ 레몬법 주의', 'warn'));
            }
            if (v.Repeat_Defect__c) {
                out.add(new Badge('↻ 반복 결함 · ' + v.Repeat_Defect_System__c, 'warn'));
            }
            if (v.Warranty_End_Date__c != null && v.Warranty_End_Date__c < Date.today()) {
                out.add(new Badge('🛡 일반 보증 만료', 'done'));
            }
            if (out.isEmpty()) {
                out.add(new Badge('✓ 정상', 'ok'));
            }
        }
        return out;
    }

    // ===== 차주 360 =====
    @AuraEnabled(cacheable=true)
    public static Owner360 getOwner360(Id contactId) {
        Contact c = [SELECT Name, Phone, Email, Risk_Level__c, Risk_Score__c, VOC_Count_90d__c FROM Contact WHERE Id = :contactId];
        Owner360 o = new Owner360();
        o.name = c.Name;
        o.phone = c.Phone;
        o.email = c.Email;
        o.riskLevel = c.Risk_Level__c;
        o.riskScore = c.Risk_Score__c;
        o.voc90 = c.VOC_Count_90d__c;
        Set<String> handlers = new Set<String>();
        Boolean escalated = false;
        for (Case k : [SELECT Current_Handler__r.Name, Escalation_Status__c FROM Case
                       WHERE ContactId = :contactId AND VOC_Status__c != null AND VOC_Status__c != '종결']) {
            o.openVoc++;
            if (k.Current_Handler__r != null) {
                handlers.add(k.Current_Handler__r.Name);
            }
            escalated = escalated || k.Escalation_Status__c == '요청';
        }
        o.handlers = String.join(new List<String>(handlers), ' / ');
        Boolean risky = false;
        for (Vehicle__c v : [SELECT Repeat_Defect__c, Lemon_Law_Status__c FROM Vehicle__c WHERE Owner_Contact__c = :contactId]) {
            o.vehicleCount++;
            risky = risky || v.Repeat_Defect__c || v.Lemon_Law_Status__c == '대상 가능';
        }
        o.tone = c.Risk_Level__c == '높음' ? 'danger' : (c.Risk_Level__c == '주의' ? 'warn' : 'ok');
        if (String.isNotBlank(c.Risk_Level__c)) {
            o.badges.add(new Badge((o.tone == 'ok' ? '✓ 위험 ' : '⚠ 위험 ') + c.Risk_Level__c
                + (c.Risk_Score__c == null ? '' : ' · ' + c.Risk_Score__c.intValue() + '점'), o.tone));
        }
        if (escalated) {
            o.badges.add(new Badge('↑ 팀장 이관 진행 중', 'warn'));
        }
        if (risky) {
            o.badges.add(new Badge('↻ 반복 결함·레몬법 차량 보유', 'warn'));
        }
        return o;
    }

    // ===== 보증 게이지 =====
    @AuraEnabled(cacheable=true)
    public static List<Gauge> getWarrantyGauges(Id vehicleId) {
        Vehicle__c v = [SELECT Mileage__c FROM Vehicle__c WHERE Id = :vehicleId];
        List<Gauge> out = new List<Gauge>();
        for (Vehicle_Warranty__c w : [SELECT Warranty_Type__c, Status__c, Start_Date__c, End_Date__c, Mileage_Limit_Km__c
                                      FROM Vehicle_Warranty__c WHERE Vehicle__c = :vehicleId ORDER BY End_Date__c]) {
            Gauge g = new Gauge();
            g.type = w.Warranty_Type__c;
            g.status = w.Status__c;
            g.endDate = w.End_Date__c;
            if (w.Start_Date__c != null && w.End_Date__c != null && w.End_Date__c > w.Start_Date__c) {
                Decimal pct = 100.0 * w.Start_Date__c.daysBetween(Date.today()) / w.Start_Date__c.daysBetween(w.End_Date__c);
                g.timePct = Integer.valueOf(Math.min(100, Math.max(0, pct.round())));
            }
            if (w.Mileage_Limit_Km__c != null && w.Mileage_Limit_Km__c > 0 && v.Mileage__c != null) {
                g.kmPct = Integer.valueOf(Math.min(100, (100.0 * v.Mileage__c / w.Mileage_Limit_Km__c).round()));
            }
            Boolean expired = (w.End_Date__c != null && w.End_Date__c < Date.today())
                || (w.Mileage_Limit_Km__c != null && v.Mileage__c != null && v.Mileage__c > w.Mileage_Limit_Km__c);
            Integer worst = Math.max(g.timePct == null ? 0 : g.timePct, g.kmPct == null ? 0 : g.kmPct);
            g.tone = expired ? 'done' : (worst >= 85 ? 'warn' : 'ok');
            g.detail = '기간 ' + (g.timePct == null ? '-' : g.timePct + '%')
                + ' · 주행 ' + (v.Mileage__c == null ? '-' : v.Mileage__c.format()) + ' / '
                + (w.Mileage_Limit_Km__c == null ? '-' : w.Mileage_Limit_Km__c.format()) + 'km';
            out.add(g);
        }
        return out;
    }

    // ===== 홈 히어로 =====
    @AuraEnabled
    public static HomeHero getHomeHero() {
        HomeHero h = new HomeHero();
        for (Recall_Alert__c a : [SELECT Id, Name, Model_Line__c, System__c, VOC_Count__c, Status__c FROM Recall_Alert__c
                                  WHERE Status__c != '종결' ORDER BY Last_Detected_At__c DESC LIMIT 3]) {
            AlertRow r = new AlertRow();
            r.alertId = a.Id;
            r.label = a.Name + ' · ' + a.Model_Line__c + ' ' + a.System__c + ' 계통 안전 결함 ' + a.VOC_Count__c.intValue() + '건 · ' + a.Status__c;
            h.alerts.add(r);
        }
        Datetime soon = Datetime.now().addHours(2);
        for (Case c : [SELECT Id, CaseNumber, Subject, VOC_Status_Display__c, VOC_Category__c, Escalation_Status__c,
                              Response_Due_At__c, First_Response_At__c, Current_Handler__r.Name
                       FROM Case WHERE VOC_Status__c != null AND VOC_Status__c != '종결'
                       ORDER BY Response_Due_At__c ASC NULLS LAST]) {
            h.open++;
            if (c.First_Response_At__c == null && c.Response_Due_At__c != null && c.Response_Due_At__c < soon) {
                h.dueSoon++;
            }
            if (c.Escalation_Status__c == '요청') {
                h.escalated++;
            }
            if (c.VOC_Category__c == '안전 결함') {
                h.safety++;
            }
            if (h.rows.size() < 5 && c.First_Response_At__c == null) {
                HomeRow r = new HomeRow();
                r.caseId = c.Id;
                r.caseNumber = c.CaseNumber;
                r.subject = c.Subject;
                r.display = c.VOC_Status_Display__c;
                r.dueAt = c.Response_Due_At__c;
                r.handlerName = c.Current_Handler__r == null ? null : c.Current_Handler__r.Name;
                h.rows.add(r);
            }
        }
        return h;
    }
}
