/**
 * 차량-사람 관계(Vehicle_Party__c)가 원본이고 차량의 차주 Lookup은 따라간다(PRD Q44).
 * 새 '소유자' 관계가 생기면 같은 차량의 기존 현재 소유자 관계를 종료하고 '이전 소유자'로 바꾼다.
 */
public with sharing class VehiclePartyService {
    public static final String OWNER = '소유자';
    public static final String PREVIOUS_OWNER = '이전 소유자';

    public static void afterUpsert(List<Vehicle_Party__c> parties) {
        Map<Id, Vehicle_Party__c> newOwnerByVehicle = new Map<Id, Vehicle_Party__c>();
        for (Vehicle_Party__c p : parties) {
            if (p.Role__c == OWNER && p.End_Date__c == null && p.Contact__c != null) {
                newOwnerByVehicle.put(p.Vehicle__c, p);
            }
        }
        if (newOwnerByVehicle.isEmpty()) {
            return;
        }

        List<Vehicle_Party__c> toClose = new List<Vehicle_Party__c>();
        for (Vehicle_Party__c old : [
            SELECT Id, Vehicle__c, Start_Date__c
            FROM Vehicle_Party__c
            WHERE Vehicle__c IN :newOwnerByVehicle.keySet()
              AND Role__c = :OWNER AND End_Date__c = null
              AND Id NOT IN :parties
        ]) {
            Vehicle_Party__c current = newOwnerByVehicle.get(old.Vehicle__c);
            Date endDate = current.Start_Date__c != null ? current.Start_Date__c : Date.today();
            toClose.add(new Vehicle_Party__c(Id = old.Id, End_Date__c = endDate, Role__c = PREVIOUS_OWNER));
        }
        update toClose;

        List<Vehicle__c> vehicles = new List<Vehicle__c>();
        for (Vehicle_Party__c p : newOwnerByVehicle.values()) {
            vehicles.add(new Vehicle__c(Id = p.Vehicle__c, Owner_Contact__c = p.Contact__c));
        }
        update vehicles;
    }
}
