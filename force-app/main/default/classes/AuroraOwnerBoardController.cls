/**
 * v4.4 P-2 '차주·차량' 통합 탭(docs/design/v4.4-feedback.md F2). 오로라 차주와 보유 차량·진행 중 VOC를 한 목록으로.
 * 오로라 차주 = 연락처 구분 '차주' 또는 이메일 @aurora.example.com(실습 연락처·공급사 담당자는 제외).
 * 검색: 이름·전화·번호판·차량 번호(VEH-) / 필터: 위험 높음·레몬법 주의 이상·진행 중 VOC·보증 만료 임박(90일).
 */
public with sharing class AuroraOwnerBoardController {
    static final Integer EXPIRING_DAYS = 90;
    static final String AI_INFO = 'AI 정보 안내';

    public class VocLine {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public Boolean safety;
    }

    public class VehicleCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String plate;
        @AuraEnabled public String model;
        @AuraEnabled public Decimal mileage;
        @AuraEnabled public String lemon;
        @AuraEnabled public Boolean repeatDefect;
        @AuraEnabled public String repeatSystem;
        @AuraEnabled public Integer validWarranties = 0;
        @AuraEnabled public String nextWarrantyEnd;   // 가장 먼저 끝나는 유효 보증 '종류 YYYY-MM-DD'
        @AuraEnabled public Boolean warrantyExpiring = false;
    }

    public class OwnerRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String grade;
        @AuraEnabled public String risk;
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public List<VehicleCard> vehicles = new List<VehicleCard>();
        @AuraEnabled public List<VocLine> openVocs = new List<VocLine>();
        @AuraEnabled public Boolean lemonFlag = false;
        @AuraEnabled public Boolean expiringFlag = false;
    }

    @AuraEnabled(cacheable=false)
    public static List<OwnerRow> search(String term, List<String> filters) {
        Set<String> f = filters == null ? new Set<String>() : new Set<String>(filters);
        String t = term == null ? '' : term.trim();

        List<Contact> owners = [SELECT Id, Name, Phone, Customer_Grade__c, Risk_Level__c, Risk_Score__c
                                FROM Contact
                                WHERE Contact_Role__c = '차주' OR Email LIKE '%@aurora.example.com'
                                ORDER BY Risk_Score__c DESC NULLS LAST, Name];
        Map<Id, OwnerRow> rows = new Map<Id, OwnerRow>();
        for (Contact c : owners) {
            OwnerRow r = new OwnerRow();
            r.id = c.Id;
            r.name = c.Name;
            r.phone = c.Phone;
            r.grade = c.Customer_Grade__c;
            r.risk = c.Risk_Level__c;
            r.riskScore = c.Risk_Score__c;
            rows.put(c.Id, r);
        }
        Date today = Date.today();
        for (Vehicle__c v : [SELECT Id, Name, Plate_Number__c, Vehicle_Model__r.Name, Model__c, Mileage__c, Owner_Contact__c,
                                    Lemon_Law_Status__c, Repeat_Defect__c, Repeat_Defect_System__c,
                                    (SELECT Warranty_Type__c, End_Date__c, Status__c FROM Warranties__r ORDER BY End_Date__c)
                             FROM Vehicle__c WHERE Owner_Contact__c IN :rows.keySet() ORDER BY Name]) {
            VehicleCard card = new VehicleCard();
            card.id = v.Id;
            card.name = v.Name;
            card.plate = v.Plate_Number__c;
            card.model = v.Vehicle_Model__r == null ? v.Model__c : v.Vehicle_Model__r.Name;
            card.mileage = v.Mileage__c;
            card.lemon = v.Lemon_Law_Status__c;
            card.repeatDefect = v.Repeat_Defect__c == true;
            card.repeatSystem = v.Repeat_Defect_System__c;
            for (Vehicle_Warranty__c w : v.Warranties__r) {
                if (w.Status__c != '유효') {
                    continue;
                }
                card.validWarranties++;
                if (card.nextWarrantyEnd == null) {
                    card.nextWarrantyEnd = w.Warranty_Type__c + ' ' + String.valueOf(w.End_Date__c);
                    card.warrantyExpiring = w.End_Date__c <= today.addDays(EXPIRING_DAYS);
                }
            }
            OwnerRow r = rows.get(v.Owner_Contact__c);
            r.vehicles.add(card);
            r.lemonFlag = r.lemonFlag || v.Lemon_Law_Status__c == '주의' || v.Lemon_Law_Status__c == '대상 가능';
            r.expiringFlag = r.expiringFlag || card.warrantyExpiring;
        }
        for (Case c : [SELECT Id, CaseNumber, Subject, VOC_Status__c, VOC_Category__c, ContactId FROM Case
                       WHERE ContactId IN :rows.keySet() AND VOC_Status__c != null AND VOC_Status__c != '종결'
                       AND AI_Outcome__c != :AI_INFO ORDER BY CreatedDate DESC]) {
            VocLine l = new VocLine();
            l.id = c.Id;
            l.caseNumber = c.CaseNumber;
            l.subject = c.Subject;
            l.status = c.VOC_Status__c;
            l.category = c.VOC_Category__c;
            l.safety = c.VOC_Category__c == '안전 결함';
            rows.get(c.ContactId).openVocs.add(l);
        }

        List<OwnerRow> out = new List<OwnerRow>();
        for (OwnerRow r : rows.values()) {
            if (matches(r, t) && passes(r, f)) {
                out.add(r);
            }
        }
        return out;
    }

    @TestVisible
    static Boolean matches(OwnerRow r, String term) {
        if (String.isBlank(term)) {
            return true;
        }
        String q = term.toLowerCase().deleteWhitespace();
        String digits = term.replaceAll('[^0-9]', '');
        List<String> hay = new List<String>{ r.name };
        for (VehicleCard v : r.vehicles) {
            hay.add(v.name);
            hay.add(v.plate);
        }
        for (String h : hay) {
            if (h != null && h.toLowerCase().deleteWhitespace().contains(q)) {
                return true;
            }
        }
        // 전화번호는 숫자만 비교(010-0000-0003 = 01000000003 = 0003)
        return digits.length() >= 3 && r.phone != null && r.phone.replaceAll('[^0-9]', '').contains(digits);
    }

    @TestVisible
    static Boolean passes(OwnerRow r, Set<String> f) {
        if (f.contains('risk') && r.risk != '높음') {
            return false;
        }
        if (f.contains('lemon') && !r.lemonFlag) {
            return false;
        }
        if (f.contains('openVoc') && r.openVocs.isEmpty()) {
            return false;
        }
        if (f.contains('expiring') && !r.expiringFlag) {
            return false;
        }
        return true;
    }
}
