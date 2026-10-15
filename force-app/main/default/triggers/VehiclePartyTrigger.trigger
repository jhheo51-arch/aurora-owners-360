trigger VehiclePartyTrigger on Vehicle_Party__c (after insert, after update) {
    VehiclePartyService.afterUpsert(Trigger.new);
}
