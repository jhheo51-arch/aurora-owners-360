trigger AuroraCaseWarrantyTrigger on Case (before insert, before update) {
    VehicleWarrantyService.judgeCases(Trigger.new);
}
