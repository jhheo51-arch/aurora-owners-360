@IsTest
private class AuroraV3Test {
    private static Vehicle__c newVehicle(String vin, Date delivered) {
        Vehicle__c v = new Vehicle__c(VIN__c = vin, Delivery_Date__c = delivered, Mileage__c = 1000);
        insert v;
        return v;
    }

    private static Service_Visit__c repair(Id vehicleId, Date day, String sys, Integer days) {
        return new Service_Visit__c(Vehicle__c = vehicleId, Check_In_Date__c = day, Completed_Date__c = day.addDays(days - 1),
            Mileage__c = 5000, Visit_Type__c = '하자 수리', Defect_System__c = sys);
    }

    @IsTest
    static void majorDefectRepairedTwiceThenRecursIsEligible() {
        Vehicle__c v = newVehicle('TESTLEMON00000001', Date.today().addMonths(-11));
        insert new List<Service_Visit__c>{
            repair(v.Id, Date.today().addMonths(-9), '배터리', 2),
            repair(v.Id, Date.today().addMonths(-6), '배터리', 2),
            repair(v.Id, Date.today().addMonths(-2), '배터리', 2)
        };
        v = [SELECT Lemon_Law_Status__c, Lemon_Law_Basis__c, Repeat_Defect__c, Repeat_Defect_System__c FROM Vehicle__c WHERE Id = :v.Id];
        System.assertEquals(LemonLawEvaluator.STATUS_ELIGIBLE, v.Lemon_Law_Status__c, v.Lemon_Law_Basis__c);
        System.assert(v.Repeat_Defect__c);
        System.assertEquals('배터리', v.Repeat_Defect_System__c);
    }

    @IsTest
    static void minorDefectTwiceIsWatch() {
        Vehicle__c v = newVehicle('TESTLEMON00000002', Date.today().addMonths(-10));
        insert new List<Service_Visit__c>{
            repair(v.Id, Date.today().addMonths(-8), '전장', 1),
            repair(v.Id, Date.today().addMonths(-4), '전장', 1)
        };
        System.assertEquals(LemonLawEvaluator.STATUS_WATCH, [SELECT Lemon_Law_Status__c FROM Vehicle__c WHERE Id = :v.Id].Lemon_Law_Status__c);
    }

    @IsTest
    static void cumulativeRepairDaysOverLimitIsEligible() {
        Vehicle__c v = newVehicle('TESTLEMON00000003', Date.today().addMonths(-6));
        insert repair(v.Id, Date.today().addMonths(-3), '공조', 35);
        System.assertEquals(LemonLawEvaluator.STATUS_ELIGIBLE, [SELECT Lemon_Law_Status__c FROM Vehicle__c WHERE Id = :v.Id].Lemon_Law_Status__c);
    }

    @IsTest
    static void repairsAfterWindowAreRepeatDefectOnly() {
        Vehicle__c v = newVehicle('TESTLEMON00000004', Date.today().addYears(-3));
        insert new List<Service_Visit__c>{
            repair(v.Id, Date.today().addYears(-1), '제동', 1),
            repair(v.Id, Date.today().addMonths(-1), '제동', 1)
        };
        v = [SELECT Lemon_Law_Status__c, Repeat_Defect__c FROM Vehicle__c WHERE Id = :v.Id];
        System.assertEquals(LemonLawEvaluator.STATUS_NONE, v.Lemon_Law_Status__c);
        System.assert(v.Repeat_Defect__c);
    }

    @IsTest
    static void eligibleButClaimWindowPassedIsNone() {
        Vehicle__c v = newVehicle('TESTLEMON00000005', Date.today().addMonths(-30));
        insert new List<Service_Visit__c>{
            repair(v.Id, Date.today().addMonths(-29), '구동', 1),
            repair(v.Id, Date.today().addMonths(-27), '구동', 1),
            repair(v.Id, Date.today().addMonths(-25), '구동', 1)
        };
        v = [SELECT Lemon_Law_Status__c, Lemon_Law_Basis__c FROM Vehicle__c WHERE Id = :v.Id];
        System.assertEquals(LemonLawEvaluator.STATUS_NONE, v.Lemon_Law_Status__c);
        System.assert(v.Lemon_Law_Basis__c.contains('요구 기한'), v.Lemon_Law_Basis__c);
        delete [SELECT Id FROM Service_Visit__c WHERE Vehicle__c = :v.Id];
    }

    @IsTest
    static void newOwnerClosesPreviousAndSyncsVehicle() {
        Contact a = new Contact(LastName = '테스트 이전 차주');
        Contact b = new Contact(LastName = '테스트 새 차주');
        insert new List<Contact>{ a, b };
        Vehicle__c v = newVehicle('TESTPARTY00000001', Date.today().addYears(-2));
        insert new Vehicle_Party__c(Vehicle__c = v.Id, Contact__c = a.Id, Role__c = '소유자', Start_Date__c = Date.today().addYears(-2));
        System.assertEquals(a.Id, [SELECT Owner_Contact__c FROM Vehicle__c WHERE Id = :v.Id].Owner_Contact__c);

        insert new Vehicle_Party__c(Vehicle__c = v.Id, Contact__c = b.Id, Role__c = '소유자', Start_Date__c = Date.today());
        System.assertEquals(b.Id, [SELECT Owner_Contact__c FROM Vehicle__c WHERE Id = :v.Id].Owner_Contact__c);
        Vehicle_Party__c old = [SELECT Role__c, End_Date__c FROM Vehicle_Party__c WHERE Contact__c = :a.Id];
        System.assertEquals('이전 소유자', old.Role__c);
        System.assertEquals(Date.today(), old.End_Date__c);
    }
}
