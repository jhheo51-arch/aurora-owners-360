trigger AuroraCaseAlertTrigger on Case (before insert, before update, after insert, after update) {
    // v4.4 업무 알림 N1(팀장 이관)·N4(AI 상담 연결): before에서 보낼 코드를 표시하고 after에서 새로 표시된 것만 보낸다
    if (Trigger.isBefore) {
        AuroraNotifier.markCases(Trigger.new, Trigger.oldMap);
    } else {
        AuroraNotifier.sendCases(Trigger.new, Trigger.oldMap);
    }
}
