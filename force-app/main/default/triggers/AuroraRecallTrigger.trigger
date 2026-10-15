trigger AuroraRecallTrigger on Case (after insert, after update) {
    RecallAlertService.onCases(Trigger.new, Trigger.oldMap);
}
