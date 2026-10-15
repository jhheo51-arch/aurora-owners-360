@IsTest
private class VehicleWarrantyServiceTest {
    @IsTest
    static void createsTermsFromModelAndJudgesByTimeAndMileage() {
        Vehicle_Model__c m = new Vehicle_Model__c(Name = '테스트 EV', Model_Line__c = '시티로', Powertrain__c = '전기',
            General_Warranty_Months__c = 36, General_Warranty_Km__c = 60000, Battery_Warranty_Months__c = 96, Battery_Warranty_Km__c = 160000);
        insert m;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTWARRANTY00001', Vehicle_Model__c = m.Id,
            Delivery_Date__c = Date.today().addYears(-4), Mileage__c = 70000);
        insert v;
        System.assertEquals(2, [SELECT COUNT() FROM Vehicle_Warranty__c WHERE Vehicle__c = :v.Id], '일반·배터리(파워트레인 정책 없음)');

        Case general = new Case(Subject = '일반', Vehicle__c = v.Id, Warranty_Scope__c = '일반 부품');
        Case battery = new Case(Subject = '배터리', Vehicle__c = v.Id, Warranty_Scope__c = '고전압 배터리');
        insert new List<Case>{ general, battery };
        System.assertEquals(false, [SELECT Warranty_Coverage__c FROM Case WHERE Id = :general.Id].Warranty_Coverage__c, '일반 보증 기간·주행거리 초과');
        Case b = [SELECT Warranty_Coverage__c, Applied_Warranty__r.Warranty_Type__c FROM Case WHERE Id = :battery.Id];
        System.assert(b.Warranty_Coverage__c);
        System.assertEquals('배터리', b.Applied_Warranty__r.Warranty_Type__c);
    }

    @IsTest
    static void powertrainOnlyForDrivetrainDefects() {
        Vehicle_Model__c m = new Vehicle_Model__c(Name = '테스트 HEV', Model_Line__c = '오로라 GT', Powertrain__c = '하이브리드',
            General_Warranty_Months__c = 36, General_Warranty_Km__c = 60000, Powertrain_Warranty_Months__c = 60, Powertrain_Warranty_Km__c = 100000);
        insert m;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTWARRANTY00002', Vehicle_Model__c = m.Id, Delivery_Date__c = Date.today().addYears(-4), Mileage__c = 50000);
        insert v;
        Failure_Mode__c drive = new Failure_Mode__c(Name = '하이브리드 경고', System__c = '구동');
        Failure_Mode__c brake = new Failure_Mode__c(Name = '브레이크', System__c = '제동');
        insert new List<Failure_Mode__c>{ drive, brake };
        Case d = new Case(Subject = '구동', Vehicle__c = v.Id, Failure_Mode__c = drive.Id);
        Case b = new Case(Subject = '제동', Vehicle__c = v.Id, Failure_Mode__c = brake.Id);
        insert new List<Case>{ d, b };
        System.assertEquals(true, [SELECT Warranty_Coverage__c FROM Case WHERE Id = :d.Id].Warranty_Coverage__c, '파워트레인 5년 내');
        System.assertEquals(false, [SELECT Warranty_Coverage__c FROM Case WHERE Id = :b.Id].Warranty_Coverage__c, '일반 3년 만료');
    }
}
