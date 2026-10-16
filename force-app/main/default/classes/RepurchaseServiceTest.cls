/** v5 S-4 재구매 상담: 금융 만기·보증 만료 90일 이내만, 차량당 열린 상담 1건 */
@IsTest
private class RepurchaseServiceTest {
    private static Vehicle__c vehicle(String vin, Id ownerId, Date delivery) {
        return new Vehicle__c(VIN__c = vin, Model__c = '시티로', Owner_Contact__c = ownerId, Delivery_Date__c = delivery);
    }

    @IsTest
    static void financeMaturityCreatesOncePerVehicle() {
        Contact owner = new Contact(LastName = '테스트재구매차주');
        insert owner;
        Vehicle__c v = vehicle('TESTRP0000000001', owner.Id, Date.today().addYears(-1));
        insert v;
        Finance_Contract__c soon = new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '리스', Status__c = '진행', End_Date__c = Date.today().addDays(60));
        Finance_Contract__c far = new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '할부', Status__c = '진행', End_Date__c = Date.today().addDays(200));
        Finance_Contract__c past = new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '할부', Status__c = '진행', End_Date__c = Date.today().addDays(-1));
        insert new List<Finance_Contract__c>{ soon, far, past };

        RepurchaseService.Request req = new RepurchaseService.Request();
        req.recordId = soon.Id;
        Test.startTest();
        RepurchaseService.run(new List<RepurchaseService.Request>{ req, req });
        RepurchaseService.createForContracts(new Set<Id>{ soon.Id, far.Id, past.Id });
        Test.stopTest();

        List<Opportunity> opps = [
            SELECT Name, StageName, CloseDate, Aurora_Type__c, Trigger_Reason__c, Customer_Contact__c, Vehicle__c, Finance_Contract__c, IsClosed
            FROM Opportunity WHERE Vehicle__c = :v.Id
        ];
        System.assertEquals(1, opps.size(), '차량당 열린 상담 1건');
        Opportunity o = opps[0];
        System.assertEquals(RepurchaseService.AURORA_TYPE, o.Aurora_Type__c);
        System.assertEquals(RepurchaseService.REASON_FINANCE, o.Trigger_Reason__c);
        System.assertEquals(owner.Id, o.Customer_Contact__c, '고객은 계약 고객(=차량 차주)');
        System.assertEquals(soon.Id, o.Finance_Contract__c);
        System.assertEquals(soon.End_Date__c, o.CloseDate);
        System.assert(!o.IsClosed);
        System.assert(o.Name.contains('테스트재구매차주'));
    }

    @IsTest
    static void closedOpportunityAllowsNewOne() {
        Contact owner = new Contact(LastName = '테스트종결차주');
        insert owner;
        Vehicle__c v = vehicle('TESTRP0000000002', owner.Id, Date.today().addYears(-1));
        insert v;
        Finance_Contract__c f = new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '리스', Status__c = '진행', End_Date__c = Date.today().addDays(10));
        insert f;
        List<OpportunityStage> lost = [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = true AND IsWon = false LIMIT 1];
        insert new Opportunity(Name = '지난 상담', StageName = lost[0].ApiName, CloseDate = Date.today(),
            Aurora_Type__c = RepurchaseService.AURORA_TYPE, Vehicle__c = v.Id);

        Test.startTest();
        Integer n = RepurchaseService.createForContracts(new Set<Id>{ f.Id }).size();
        Test.stopTest();
        System.assertEquals(1, n, '닫힌 상담만 있으면 새로 만든다');
    }

    @IsTest
    static void scanCoversWarrantyExpiry() {
        Contact owner = new Contact(LastName = '테스트보증차주');
        insert owner;
        // 일반 보증 = 출고 + 36개월 → 35일 남음 / 이미 만료 / 1년 넘게 남음
        Vehicle__c soon = vehicle('TESTRP0000000003', owner.Id, Date.today().addMonths(-36).addDays(35));
        Vehicle__c expired = vehicle('TESTRP0000000004', owner.Id, Date.today().addMonths(-40));
        Vehicle__c fresh = vehicle('TESTRP0000000005', owner.Id, Date.today().addMonths(-6));
        insert new List<Vehicle__c>{ soon, expired, fresh };

        Test.startTest();
        RepurchaseService.run(new List<RepurchaseService.Request>{ new RepurchaseService.Request() });
        Integer again = RepurchaseService.scan();
        Test.stopTest();

        List<Opportunity> opps = [SELECT Vehicle__c, Trigger_Reason__c, Finance_Contract__c FROM Opportunity WHERE Aurora_Type__c = :RepurchaseService.AURORA_TYPE];
        System.assertEquals(1, opps.size());
        System.assertEquals(soon.Id, opps[0].Vehicle__c);
        System.assertEquals(RepurchaseService.REASON_WARRANTY, opps[0].Trigger_Reason__c);
        System.assertEquals(null, opps[0].Finance_Contract__c);
        System.assertEquals(0, again, '두 번째 점검은 중복 없음');
    }
}
