trigger AuroraVehicleWarrantyTrigger on Vehicle__c (after insert, after update) {
    VehicleWarrantyService.createMissing(Trigger.new);
}
