/** v5 S-1 서비스센터 혼잡도 */
@IsTest
private class AuroraNetworkTest {
    @IsTest
    static void preferredFirstThenLeastBusy() {
        Account busy = new Account(Name = '테스트 혼잡 센터', Customer_Segment__c = '서비스센터', Daily_Capacity__c = 2, Region__c = '서울 강남');
        Account free = new Account(Name = '테스트 여유 센터', Customer_Segment__c = '서비스센터', Daily_Capacity__c = 10, Region__c = '경기 판교');
        Account mine = new Account(Name = '테스트 담당 센터', Customer_Segment__c = '서비스센터', Daily_Capacity__c = 4, Region__c = '부산 해운대');
        Account noCap = new Account(Name = '테스트 용량 없음', Customer_Segment__c = '서비스센터');
        Account dealer = new Account(Name = '테스트 전시장', Customer_Segment__c = '딜러');
        insert new List<Account>{ busy, free, mine, noCap, dealer };

        Vehicle__c v = new Vehicle__c(VIN__c = 'KTESTNET000000001', Model__c = '노스라이트', Preferred_Center__c = mine.Id);
        insert v;
        insert new List<Service_Visit__c>{
            new Service_Visit__c(Vehicle__c = v.Id, Visit_Type__c = '정기 점검', Service_Center_Account__c = busy.Id, Check_In_Date__c = Date.today()),
            new Service_Visit__c(Vehicle__c = v.Id, Visit_Type__c = '정기 점검', Service_Center_Account__c = busy.Id, Check_In_Date__c = Date.today()),
            new Service_Visit__c(Vehicle__c = v.Id, Visit_Type__c = '정기 점검', Service_Center_Account__c = mine.Id, Check_In_Date__c = Date.today().addDays(-1)),
            // 완료된 정비는 세지 않는다
            new Service_Visit__c(Vehicle__c = v.Id, Visit_Type__c = '정기 점검', Service_Center_Account__c = free.Id, Check_In_Date__c = Date.today().addDays(-5),
                                 Completed_Date__c = Date.today().addDays(-4))
        };

        List<AuroraNetworkController.CenterLoad> rows = AuroraNetworkController.centerLoads(v.Id);
        Map<Id, AuroraNetworkController.CenterLoad> byId = new Map<Id, AuroraNetworkController.CenterLoad>();
        for (AuroraNetworkController.CenterLoad c : rows) {
            byId.put(c.id, c);
        }
        System.assert(!byId.containsKey(dealer.Id), '딜러는 혼잡도 목록에 없음');
        System.assertEquals(mine.Id, rows[0].id, '담당 센터가 맨 위');
        System.assert(rows[0].preferred);
        System.assertEquals(25, rows[0].percent);
        System.assertEquals('여유', rows[0].levelLabel);
        System.assertEquals(100, byId.get(busy.Id).percent);
        System.assertEquals('BUSY', byId.get(busy.Id).level);
        System.assertEquals(0, byId.get(free.Id).openVisits, '완료된 정비 제외');
        System.assertEquals('용량 미등록', byId.get(noCap.Id).levelLabel);
        System.assertEquals(noCap.Id, rows[rows.size() - 1].id, '용량 미등록은 맨 뒤');
        // 담당 센터 다음은 여유 있는 순: 여유(0%) → 혼잡(100%)
        Integer iFree = -1, iBusy = -1;
        for (Integer i = 0; i < rows.size(); i++) {
            if (rows[i].id == free.Id) { iFree = i; }
            if (rows[i].id == busy.Id) { iBusy = i; }
        }
        System.assert(iFree < iBusy);
    }

    @IsTest
    static void normalLevelAndNoVehicle() {
        Account a = new Account(Name = '테스트 보통 센터', Customer_Segment__c = '서비스센터', Daily_Capacity__c = 4);
        insert a;
        AuroraNetworkController.CenterLoad c = AuroraNetworkController.load(a, 2, false);
        System.assertEquals('NORMAL', c.level);
        System.assertEquals('보통', c.levelLabel);
        List<AuroraNetworkController.CenterLoad> rows = AuroraNetworkController.centerLoads(null);
        System.assertEquals(1, rows.size());
        System.assertEquals(false, rows[0].preferred);
    }
}
