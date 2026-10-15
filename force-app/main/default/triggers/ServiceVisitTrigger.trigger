trigger ServiceVisitTrigger on Service_Visit__c (after insert, after update, after delete, after undelete) {
    Set<Id> vehicleIds = new Set<Id>();
    for (Service_Visit__c s : Trigger.isDelete ? Trigger.old : Trigger.new) {
        vehicleIds.add(s.Vehicle__c);
    }
    LemonLawEvaluator.evaluate(vehicleIds);
    CustomerRiskService.recalculateForVehicles(vehicleIds);
}
