/** v5 S-2 리콜 캠페인: 대상 생성(조건·중복 방지), 날짜 자동 기록, 정비 완료 → 조치 완료, 차량 배지 */
@IsTest
private class RecallCampaignTest {
    @TestSetup
    static void setup() {
        Vehicle_Model__c nl = new Vehicle_Model__c(Name = '노스라이트 R', Model_Line__c = '노스라이트', Model_Code__c = 'T-RC-NL');
        Vehicle_Model__c ct = new Vehicle_Model__c(Name = '시티로 R', Model_Line__c = '시티로', Model_Code__c = 'T-RC-CT');
        insert new List<Vehicle_Model__c>{ nl, ct };
        Account center = new Account(Name = '테스트 리콜 센터', Customer_Segment__c = '서비스센터', Daily_Capacity__c = 4);
        insert center;
        insert new List<Vehicle__c>{
            new Vehicle__c(VIN__c = 'TESTRC0000000001', Vehicle_Model__c = nl.Id, Delivery_Date__c = Date.newInstance(2023, 3, 1), Preferred_Center__c = center.Id),
            new Vehicle__c(VIN__c = 'TESTRC0000000002', Vehicle_Model__c = nl.Id, Delivery_Date__c = Date.newInstance(2023, 11, 30)),
            new Vehicle__c(VIN__c = 'TESTRC0000000003', Vehicle_Model__c = nl.Id, Delivery_Date__c = Date.newInstance(2025, 6, 1)),   // 기간 밖
            new Vehicle__c(VIN__c = 'TESTRC0000000004', Vehicle_Model__c = nl.Id),                                                  // 출고 전
            new Vehicle__c(VIN__c = 'TESTRC0000000005', Vehicle_Model__c = ct.Id, Delivery_Date__c = Date.newInstance(2023, 5, 1))     // 다른 모델
        };
        insert new Recall_Campaign__c(Campaign_Key__c = 'T-RC1', Title__c = '테스트 캠페인', Model_Line__c = '노스라이트', System__c = '제동',
                                      Delivery_From__c = Date.newInstance(2023, 1, 1), Delivery_To__c = Date.newInstance(2023, 12, 31), Status__c = '진행');
    }

    static Recall_Campaign__c campaign() {
        return [SELECT Id, Target_Count__c, Notified_Count__c, Completed_Count__c, Completion_Rate__c FROM Recall_Campaign__c WHERE Campaign_Key__c = 'T-RC1'];
    }

    @IsTest
    static void generateMatchesConditionAndIsIdempotent() {
        Id cid = campaign().Id;
        RecallCampaignService.Result p = RecallCampaignService.preview(cid);
        System.assertEquals(2, p.matched, '노스라이트 + 2023 출고만');
        System.assertEquals(0, [SELECT COUNT() FROM Recall_Vehicle__c], '미리보기는 만들지 않음');
        System.assert(p.condition.contains('노스라이트'));

        RecallCampaignService.Result r = RecallCampaignService.generateTargets(cid);
        System.assertEquals(2, r.created);
        Recall_Vehicle__c first = [SELECT Target_Key__c, Status__c, Service_Center__c FROM Recall_Vehicle__c WHERE Vehicle__r.VIN__c = 'TESTRC0000000001'];
        System.assertEquals('T-RC1|TESTRC0000000001', first.Target_Key__c);
        System.assertEquals('미통지', first.Status__c);
        System.assertNotEquals(null, first.Service_Center__c, '담당 서비스센터가 기본 조치 센터');

        RecallCampaignService.Result again = RecallCampaignService.generateTargets(cid);
        System.assertEquals(0, again.created, '다시 눌러도 중복 없음');
        System.assertEquals(2, again.existing);
        System.assertEquals(2, campaign().Target_Count__c);
    }

    @IsTest
    static void statusDatesAndVisitCompletion() {
        Id cid = campaign().Id;
        RecallCampaignService.generateTargets(cid);
        List<Recall_Vehicle__c> rows = [SELECT Id, Vehicle__c FROM Recall_Vehicle__c ORDER BY Target_Key__c];
        rows[0].Status__c = '입고 예약';
        rows[1].Status__c = '제외';
        rows[1].Exclusion_Reason__c = '수출';
        update rows;
        Recall_Vehicle__c reserved = [SELECT Notified_Date__c, Reserved_Date__c FROM Recall_Vehicle__c WHERE Id = :rows[0].Id];
        System.assertEquals(Date.today(), reserved.Notified_Date__c, '입고 예약이면 통지일도 채움');
        System.assertEquals(Date.today(), reserved.Reserved_Date__c);

        Test.startTest();
        insert new Service_Visit__c(Vehicle__c = rows[0].Vehicle__c, Visit_Type__c = '리콜·무상수리', Recall_Vehicle__c = rows[0].Id,
                                    Check_In_Date__c = Date.today(), Completed_Date__c = Date.today());
        Test.stopTest();
        Recall_Vehicle__c done = [SELECT Status__c, Completed_Date__c FROM Recall_Vehicle__c WHERE Id = :rows[0].Id];
        System.assertEquals('조치 완료', done.Status__c);
        System.assertEquals(Date.today(), done.Completed_Date__c);
        Recall_Campaign__c c = campaign();
        System.assertEquals(1, c.Target_Count__c, '제외는 대상에서 뺌');
        System.assertEquals(1, c.Completed_Count__c);
        System.assertEquals(100, c.Completion_Rate__c);
    }

    @IsTest
    static void vehicleBadgeAndMissingModelLine() {
        Id cid = campaign().Id;
        RecallCampaignService.generateTargets(cid);
        Id vid = [SELECT Id FROM Vehicle__c WHERE VIN__c = 'TESTRC0000000001'].Id;
        Boolean found = false;
        for (AuroraCardController.Badge b : AuroraCardController.getBadges(vid)) {
            found = found || b.label.contains('리콜 미조치');
        }
        System.assert(found, '미조치 리콜 배지');

        Recall_Campaign__c blank = new Recall_Campaign__c(Title__c = '모델 없음');
        insert blank;
        RecallCampaignService.Result r = RecallCampaignService.generateTargets(blank.Id);
        System.assertEquals(false, r.ok);
    }
}
