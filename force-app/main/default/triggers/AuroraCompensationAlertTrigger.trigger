trigger AuroraCompensationAlertTrigger on Compensation__c (before insert, before update, after insert, after update) {
    // v4.4 업무 알림 N2(보상 승인 요청)
    if (Trigger.isBefore) {
        AuroraNotifier.markCompensations(Trigger.new, Trigger.oldMap);
    } else {
        AuroraNotifier.sendCompensations(Trigger.new, Trigger.oldMap);
    }
}
