/**
 * v5 S-4 재구매 상담(docs/design/v5-retention.md Q74·Q75).
 * 금융 만기 또는 일반 보증 만료가 90일 이내인 차량에 표준 Opportunity(Aurora_Type__c='재구매 상담')를 만든다.
 * - 계약: Flow Aurora_Finance_Maturity_Repurchase(만기일 90일 전 예약 경로)가 recordId로 호출
 * - 보증: Warranty_End_Date__c가 수식이라 예약 경로 기준이 될 수 없음 → Flow Aurora_Warranty_Expiry_Repurchase(매일)가 recordId 없이 호출 = 전체 점검
 * 차량당 열린 재구매 상담은 1건만. 실행 시점에 남은 기간(0~90일)을 다시 확인한다.
 * 예약 경로·예약 Flow는 시스템 사용자로 실행되므로 중복 확인이 모든 상담을 보도록 without sharing.
 */
public without sharing class RepurchaseService {
    public static final Integer WINDOW_DAYS = 90;
    public static final String AURORA_TYPE = '재구매 상담';
    public static final String REASON_FINANCE = '금융 만기';
    public static final String REASON_WARRANTY = '보증 만료';

    public class Request {
        @InvocableVariable(label='금융 계약 ID' description='비우면 금융 만기·보증 만료 전체 점검')
        public Id recordId;
    }

    @InvocableMethod(label='오로라 재구매 상담 생성' description='만기·보증 만료 90일 이내 차량에 재구매 상담(Opportunity)을 만든다. 중복 없음.')
    public static void run(List<Request> requests) {
        Set<Id> contractIds = new Set<Id>();
        Boolean scanAll = false;
        for (Request r : requests) {
            if (r == null || r.recordId == null) {
                scanAll = true;
            } else {
                contractIds.add(r.recordId);
            }
        }
        if (scanAll) {
            scan();
        }
        if (!contractIds.isEmpty()) {
            createForContracts(contractIds);
        }
    }

    /** 전체 점검: 금융 만기 먼저(계기가 더 강함), 그다음 보증 만료. 만든 건수 반환. */
    public static Integer scan() {
        Date today = Date.today();
        Date limitDate = today.addDays(WINDOW_DAYS);
        Map<Id, Finance_Contract__c> contracts = new Map<Id, Finance_Contract__c>(
            [SELECT Id FROM Finance_Contract__c WHERE Status__c = '진행' AND End_Date__c >= :today AND End_Date__c <= :limitDate]);
        Integer created = createForContracts(contracts.keySet()).size();
        Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>(
            [SELECT Id FROM Vehicle__c WHERE Warranty_End_Date__c >= :today AND Warranty_End_Date__c <= :limitDate]);
        return created + createForWarranties(vehicles.keySet()).size();
    }

    public static List<Opportunity> createForContracts(Set<Id> contractIds) {
        List<Candidate> candidates = new List<Candidate>();
        for (Finance_Contract__c f : [
            SELECT Id, Name, OwnerId, Status__c, End_Date__c, Contract_Type__c, Vehicle__c, Vehicle__r.Name,
                   Vehicle__r.Vehicle_Model__c, Vehicle__r.Owner_Contact__c, Customer__c, Customer__r.Name, Vehicle__r.Owner_Contact__r.Name
            FROM Finance_Contract__c WHERE Id IN :contractIds
        ]) {
            if (f.Status__c != '진행' || f.Vehicle__c == null || !inWindow(f.End_Date__c)) {
                continue;
            }
            Candidate c = new Candidate();
            c.ownerId = f.OwnerId;
            c.vehicleId = f.Vehicle__c;
            c.vehicleName = f.Vehicle__r.Name;
            c.modelId = f.Vehicle__r.Vehicle_Model__c;
            c.contactId = f.Customer__c != null ? f.Customer__c : f.Vehicle__r.Owner_Contact__c;
            c.contactName = f.Customer__c != null ? f.Customer__r.Name : f.Vehicle__r.Owner_Contact__r.Name;
            c.contractId = f.Id;
            c.dueDate = f.End_Date__c;
            c.reason = REASON_FINANCE;
            c.basis = f.Contract_Type__c + ' 계약 ' + f.Name + ' 만기 ' + String.valueOf(f.End_Date__c) + '(' + daysLeft(f.End_Date__c) + '일 남음)';
            candidates.add(c);
        }
        return insertNew(candidates);
    }

    public static List<Opportunity> createForWarranties(Set<Id> vehicleIds) {
        List<Candidate> candidates = new List<Candidate>();
        for (Vehicle__c v : [
            SELECT Id, Name, OwnerId, Warranty_End_Date__c, Vehicle_Model__c, Owner_Contact__c, Owner_Contact__r.Name
            FROM Vehicle__c WHERE Id IN :vehicleIds
        ]) {
            if (v.Owner_Contact__c == null || !inWindow(v.Warranty_End_Date__c)) {
                continue;
            }
            Candidate c = new Candidate();
            c.ownerId = v.OwnerId;
            c.vehicleId = v.Id;
            c.vehicleName = v.Name;
            c.modelId = v.Vehicle_Model__c;
            c.contactId = v.Owner_Contact__c;
            c.contactName = v.Owner_Contact__r.Name;
            c.dueDate = v.Warranty_End_Date__c;
            c.reason = REASON_WARRANTY;
            c.basis = '일반 보증 만료 ' + String.valueOf(v.Warranty_End_Date__c) + '(' + daysLeft(v.Warranty_End_Date__c) + '일 남음)';
            candidates.add(c);
        }
        return insertNew(candidates);
    }

    private static List<Opportunity> insertNew(List<Candidate> candidates) {
        List<Opportunity> created = new List<Opportunity>();
        if (candidates.isEmpty()) {
            return created;
        }
        Set<Id> vehicleIds = new Set<Id>();
        for (Candidate c : candidates) {
            vehicleIds.add(c.vehicleId);
        }
        Set<Id> taken = new Set<Id>();
        for (Opportunity o : [
            SELECT Vehicle__c FROM Opportunity
            WHERE Aurora_Type__c = :AURORA_TYPE AND IsClosed = false AND Vehicle__c IN :vehicleIds
        ]) {
            taken.add(o.Vehicle__c);
        }
        String firstStage = firstOpenStage();
        for (Candidate c : candidates) {
            if (taken.contains(c.vehicleId)) {
                continue;
            }
            taken.add(c.vehicleId);
            String who = c.contactName == null ? '차주 미지정' : c.contactName;
            created.add(new Opportunity(
                Name = (AURORA_TYPE + ' · ' + who + ' · ' + c.vehicleName).left(120),
                StageName = firstStage,
                CloseDate = c.dueDate,
                OwnerId = c.ownerId,
                Aurora_Type__c = AURORA_TYPE,
                Trigger_Reason__c = c.reason,
                Customer_Contact__c = c.contactId,
                Vehicle__c = c.vehicleId,
                Finance_Contract__c = c.contractId,
                Recommended_Model__c = c.modelId,
                Description = '계기: ' + c.basis + '. 추천 모델은 현재 차종을 기본으로 넣었으니 상담 후 바꿔 주세요.'
            ));
        }
        if (!created.isEmpty()) {
            insert created;
        }
        return created;
    }

    /** org마다 단계 이름이 다를 수 있어 첫 번째 열린 단계를 쓴다(이 org는 Prospecting). */
    private static String firstOpenStage() {
        List<OpportunityStage> stages = [
            SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
        ];
        return stages.isEmpty() ? 'Prospecting' : stages[0].ApiName;
    }

    private static Boolean inWindow(Date d) {
        if (d == null) {
            return false;
        }
        Integer left = daysLeft(d);
        return left >= 0 && left <= WINDOW_DAYS;
    }

    private static Integer daysLeft(Date d) {
        return Date.today().daysBetween(d);
    }

    private class Candidate {
        Id ownerId;
        Id vehicleId;
        String vehicleName;
        Id modelId;
        Id contactId;
        String contactName;
        Id contractId;
        Date dueDate;
        String reason;
        String basis;
    }
}
