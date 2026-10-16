trigger RecallVehicleTrigger on Recall_Vehicle__c (before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        // v5: 상태가 통지·입고 예약·조치 완료로 바뀌면 비어 있는 날짜를 오늘로
        RecallCampaignService.stampDates(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
        return;
    }
    // v5 S-5: 리콜 미조치 여부가 바뀌면 차주 위험·건강 점수 재계산
    Set<Id> vehicleIds = new Set<Id>();
    for (Recall_Vehicle__c r : Trigger.isDelete ? Trigger.old : Trigger.new) {
        vehicleIds.add(r.Vehicle__c);
    }
    vehicleIds.remove(null);
    CustomerRiskService.recalculateForVehicles(vehicleIds);
}
