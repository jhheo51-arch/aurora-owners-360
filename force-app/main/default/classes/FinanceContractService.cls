/**
 * v5 S-3 금융·리스 계약(docs/design/v5-retention.md Q73).
 * 고객이 비어 있으면 차량의 현재 차주로 채운다(샘플 CSV·화면 입력 모두). 재구매 상담 연결은 S-4.
 */
public with sharing class FinanceContractService {
    public static void fillCustomer(List<Finance_Contract__c> rows) {
        Set<Id> vehicleIds = new Set<Id>();
        for (Finance_Contract__c f : rows) {
            if (f.Customer__c == null && f.Vehicle__c != null) {
                vehicleIds.add(f.Vehicle__c);
            }
        }
        if (vehicleIds.isEmpty()) {
            return;
        }
        Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>([SELECT Id, Owner_Contact__c FROM Vehicle__c WHERE Id IN :vehicleIds]);
        for (Finance_Contract__c f : rows) {
            if (f.Customer__c == null && vehicles.containsKey(f.Vehicle__c)) {
                f.Customer__c = vehicles.get(f.Vehicle__c).Owner_Contact__c;
            }
        }
    }
}
