/**
 * 고객 차량·차주 통합 타임라인(PRD Q38). 차량이면 그 차량, 연락처면 보유(현재·과거 관계) 차량 전체의
 * VOC·정비·보상·부품 교체·소유권 변경을 시간 역순으로 돌려준다.
 */
public with sharing class CustomerTimelineController {
    public class TimelineEvent implements Comparable {
        @AuraEnabled public String kind;
        @AuraEnabled public String icon;
        @AuraEnabled public Date eventDate;
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public String vehicle;
        @AuraEnabled public Id recordId;

        TimelineEvent(String kind, String icon, Date eventDate, String title, String detail, String vehicle, Id recordId) {
            this.kind = kind;
            this.icon = icon;
            this.eventDate = eventDate;
            this.title = title;
            this.detail = detail;
            this.vehicle = vehicle;
            this.recordId = recordId;
        }

        public Integer compareTo(Object other) {
            Date mine = eventDate == null ? Date.newInstance(1900, 1, 1) : eventDate;
            Date theirs = ((TimelineEvent) other).eventDate == null ? Date.newInstance(1900, 1, 1) : ((TimelineEvent) other).eventDate;
            return mine == theirs ? 0 : (mine > theirs ? -1 : 1);
        }
    }

    public class Timeline {
        @AuraEnabled public List<TimelineEvent> events = new List<TimelineEvent>();
        @AuraEnabled public List<String> badges = new List<String>();
    }

    @AuraEnabled(cacheable=true)
    public static Timeline getTimeline(Id recordId) {
        Set<Id> vehicleIds = new Set<Id>();
        if (recordId.getSobjectType() == Vehicle__c.SObjectType) {
            vehicleIds.add(recordId);
        } else if (recordId.getSobjectType() == Contact.SObjectType) {
            for (Vehicle__c v : [SELECT Id FROM Vehicle__c WHERE Owner_Contact__c = :recordId]) {
                vehicleIds.add(v.Id);
            }
            for (Vehicle_Party__c p : [SELECT Vehicle__c FROM Vehicle_Party__c WHERE Contact__c = :recordId]) {
                vehicleIds.add(p.Vehicle__c);
            }
        }
        Timeline t = new Timeline();
        if (vehicleIds.isEmpty()) {
            return t;
        }

        for (Vehicle__c v : [SELECT Name, Lemon_Law_Status__c, Repeat_Defect__c, Repeat_Defect_System__c FROM Vehicle__c WHERE Id IN :vehicleIds ORDER BY Name]) {
            if (v.Lemon_Law_Status__c == LemonLawEvaluator.STATUS_ELIGIBLE || v.Lemon_Law_Status__c == LemonLawEvaluator.STATUS_WATCH) {
                t.badges.add(v.Name + ' 레몬법 ' + v.Lemon_Law_Status__c);
            }
            if (v.Repeat_Defect__c) {
                t.badges.add(v.Name + ' 반복 결함(' + v.Repeat_Defect_System__c + ')');
            }
        }
        for (Case c : [SELECT Id, CaseNumber, Subject, VOC_Category__c, VOC_Status__c, CreatedDate, Vehicle__r.Name FROM Case WHERE Vehicle__c IN :vehicleIds]) {
            t.events.add(new TimelineEvent('VOC', 'standard:case', c.CreatedDate.date(), 'VOC ' + c.CaseNumber + ' · ' + c.Subject,
                c.VOC_Category__c + ' / ' + c.VOC_Status__c, c.Vehicle__r.Name, c.Id));
        }
        for (Service_Visit__c s : [SELECT Id, Name, Check_In_Date__c, Visit_Type__c, Defect_System__c, Symptom__c, Mileage__c, Vehicle__r.Name FROM Service_Visit__c WHERE Vehicle__c IN :vehicleIds]) {
            String sys = s.Defect_System__c == null ? '' : ' · ' + s.Defect_System__c;
            t.events.add(new TimelineEvent('정비', 'standard:maintenance_plan', s.Check_In_Date__c, '정비 ' + s.Name + ' · ' + s.Visit_Type__c + sys,
                s.Symptom__c + (s.Mileage__c == null ? '' : ' (' + s.Mileage__c.format() + 'km)'), s.Vehicle__r.Name, s.Id));
        }
        for (Compensation__c m : [SELECT Id, Name, Compensation_Type__c, Amount__c, Approval_Status__c, CreatedDate, Case__r.Vehicle__r.Name FROM Compensation__c WHERE Case__r.Vehicle__c IN :vehicleIds]) {
            t.events.add(new TimelineEvent('보상', 'standard:currency', m.CreatedDate.date(), '보상 ' + m.Name + ' · ' + m.Compensation_Type__c,
                (m.Amount__c == null ? '' : m.Amount__c.format() + '원 / ') + m.Approval_Status__c, m.Case__r.Vehicle__r.Name, m.Id));
        }
        for (Case_Part__c cp : [SELECT Id, Role__c, Part__r.Name, Part__r.System__c, CreatedDate, Case__r.Vehicle__r.Name FROM Case_Part__c WHERE Case__r.Vehicle__c IN :vehicleIds AND Role__c = '교체']) {
            t.events.add(new TimelineEvent('부품 교체', 'standard:product', cp.CreatedDate.date(), '부품 교체 · ' + cp.Part__r.Name,
                cp.Part__r.System__c + ' 계통', cp.Case__r.Vehicle__r.Name, cp.Id));
        }
        for (Vehicle_Party__c p : [SELECT Id, Role__c, Start_Date__c, Contact__r.Name, Account__r.Name, Vehicle__r.Name FROM Vehicle_Party__c WHERE Vehicle__c IN :vehicleIds]) {
            String who = p.Contact__r != null ? p.Contact__r.Name : p.Account__r.Name;
            t.events.add(new TimelineEvent('소유권', 'standard:contact', p.Start_Date__c, p.Role__c + ' · ' + who,
                p.Account__r == null ? '' : '법인·가구: ' + p.Account__r.Name, p.Vehicle__r.Name, p.Id));
        }
        addRetention(t, vehicleIds);
        t.events.sort();
        return t;
    }

    /** v5 S-6: 리콜 캠페인 조치, 금융·리스 계약(시작·만기), 재구매 상담 + 상단 배지(리콜 미조치·금융 만기 D-n) */
    static void addRetention(Timeline t, Set<Id> vehicleIds) {
        Date today = Date.today();
        for (Recall_Vehicle__c r : [SELECT Id, Status__c, Notified_Date__c, Reserved_Date__c, Completed_Date__c, Vehicle__r.Name,
                                           Campaign__r.Name, Campaign__r.Title__c, Campaign__r.Start_Date__c, Campaign__r.Status__c
                                    FROM Recall_Vehicle__c WHERE Vehicle__c IN :vehicleIds]) {
            Date d = r.Completed_Date__c != null ? r.Completed_Date__c
                : (r.Reserved_Date__c != null ? r.Reserved_Date__c : (r.Notified_Date__c != null ? r.Notified_Date__c : r.Campaign__r.Start_Date__c));
            t.events.add(new TimelineEvent('리콜', 'standard:announcement', d, '리콜 ' + r.Campaign__r.Name + ' · ' + r.Campaign__r.Title__c,
                '대상 차량 ' + r.Status__c, r.Vehicle__r.Name, r.Id));
            if (r.Status__c != '조치 완료' && r.Status__c != '제외' && r.Campaign__r.Status__c != '완료') {
                t.badges.add(r.Vehicle__r.Name + ' 리콜 미조치(' + r.Campaign__r.Name + ' ' + r.Status__c + ')');
            }
        }
        for (Finance_Contract__c f : [SELECT Id, Name, Contract_Type__c, Status__c, Start_Date__c, End_Date__c, Monthly_Payment__c, Vehicle__r.Name
                                      FROM Finance_Contract__c WHERE Vehicle__c IN :vehicleIds]) {
            String pay = f.Monthly_Payment__c == null ? '' : '월 ' + f.Monthly_Payment__c.format() + '원';
            if (f.Start_Date__c != null) {
                t.events.add(new TimelineEvent('금융', 'standard:contract', f.Start_Date__c, f.Contract_Type__c + ' 계약 ' + f.Name + ' 시작',
                    pay, f.Vehicle__r.Name, f.Id));
            }
            if (f.End_Date__c != null) {
                Boolean ahead = f.Status__c == '진행' && f.End_Date__c >= today;
                t.events.add(new TimelineEvent('금융', 'standard:contract', f.End_Date__c,
                    f.Contract_Type__c + ' 계약 ' + f.Name + (ahead ? ' 만기 예정' : ' 만기'), '계약 상태 ' + f.Status__c, f.Vehicle__r.Name, f.Id));
                if (ahead && today.daysBetween(f.End_Date__c) <= RepurchaseService.WINDOW_DAYS) {
                    t.badges.add(f.Vehicle__r.Name + ' 금융 만기 D-' + today.daysBetween(f.End_Date__c));
                }
            }
        }
        for (Opportunity o : [SELECT Id, Name, StageName, Trigger_Reason__c, CreatedDate, Vehicle__r.Name FROM Opportunity
                              WHERE Vehicle__c IN :vehicleIds AND Aurora_Type__c = :RepurchaseService.AURORA_TYPE]) {
            t.events.add(new TimelineEvent('재구매 상담', 'standard:opportunity', o.CreatedDate.date(), '재구매 상담 · ' + o.Trigger_Reason__c,
                '단계 ' + o.StageName, o.Vehicle__r.Name, o.Id));
        }
    }
}
