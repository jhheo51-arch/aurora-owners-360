trigger AuroraCaseRiskTrigger on Case (after insert, after update, after delete) {
    CustomerRiskService.recalculateForCases(Trigger.isDelete ? Trigger.old : Trigger.new);
}
