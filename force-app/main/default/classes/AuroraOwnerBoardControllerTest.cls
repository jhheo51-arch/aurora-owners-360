@IsTest
private class AuroraOwnerBoardControllerTest {
    @TestSetup
    static void setup() {
        Vehicle_Model__c m = new Vehicle_Model__c(Name = '노스라이트 B', Model_Line__c = '노스라이트', Model_Code__c = 'T-OB-NL',
            General_Warranty_Months__c = 36, General_Warranty_Km__c = 60000);
        insert m;
        List<Contact> cs = new List<Contact>{
            new Contact(LastName = '위험차주', Phone = '010-3333-0001', Email = 'risk@aurora.example.com', Customer_Grade__c = '플래티넘'),
            new Contact(LastName = '평범차주', Phone = '010-3333-0002', Contact_Role__c = '차주', Customer_Grade__c = '일반'),
            new Contact(LastName = '공급담당', Phone = '010-3333-0003', Email = 'x@supplier.example.com', Contact_Role__c = '공급사 담당자'),
            new Contact(LastName = '실습연락처', Phone = '010-3333-0004')
        };
        insert cs;
        insert new List<Vehicle__c>{
            // 출고 35개월 전 → 일반 보증 36개월이 1개월 안에 끝남(만료 임박)
            new Vehicle__c(VIN__c = 'TESTOWNERB00001', Vehicle_Model__c = m.Id, Owner_Contact__c = cs[0].Id, Plate_Number__c = '11가 2233',
                Delivery_Date__c = Date.today().addMonths(-35), Mileage__c = 30000, Lemon_Law_Status__c = '주의'),
            new Vehicle__c(VIN__c = 'TESTOWNERB00002', Vehicle_Model__c = m.Id, Owner_Contact__c = cs[1].Id, Plate_Number__c = '22나 4455',
                Delivery_Date__c = Date.today().addMonths(-3), Mileage__c = 3000, Lemon_Law_Status__c = '해당 없음')
        };
        update new Contact(Id = cs[0].Id, Risk_Score__c = 80);
        Care_Staff__c lead = new Care_Staff__c(Name = '정원이', Role__c = '상담팀장', Staff_Number__c = 'T-OB-L', Active__c = true);
        insert lead;
        Care_Staff__c adv = new Care_Staff__c(Name = '미나미', Role__c = '상담원', Staff_Number__c = 'T-OB-1', Active__c = true, Manager__c = lead.Id);
        insert adv;
        insert new Case(Subject = '앱 오류', ContactId = cs[0].Id, Advisor__c = adv.Id, Manager_Employee__c = lead.Id,
            VOC_Category__c = '커넥티드카 앱', VOC_Status__c = '접수');
    }

    static Set<String> names(List<AuroraOwnerBoardController.OwnerRow> rows) {
        Set<String> s = new Set<String>();
        for (AuroraOwnerBoardController.OwnerRow r : rows) {
            s.add(r.name);
        }
        return s;
    }

    @IsTest
    static void onlyAuroraOwnersWithVehiclesAndVocs() {
        List<AuroraOwnerBoardController.OwnerRow> rows = AuroraOwnerBoardController.search('', null);
        System.assertEquals(new Set<String>{ '위험차주', '평범차주' }, names(rows), '공급사 담당자·실습 연락처 제외');
        AuroraOwnerBoardController.OwnerRow risky = rows[0];
        System.assertEquals('위험차주', risky.name, '위험 점수 높은 순');
        System.assertEquals(1, risky.vehicles.size());
        System.assertEquals(1, risky.openVocs.size());
        System.assert(risky.lemonFlag);
        System.assert(risky.vehicles[0].warrantyExpiring, risky.vehicles[0].nextWarrantyEnd);
        System.assert(risky.expiringFlag);
    }

    @IsTest
    static void searchByNamePlateVehicleAndPhone() {
        System.assertEquals(new Set<String>{ '평범차주' }, names(AuroraOwnerBoardController.search('평범', null)));
        System.assertEquals(new Set<String>{ '위험차주' }, names(AuroraOwnerBoardController.search('2233', null)), '번호판');
        System.assertEquals(new Set<String>{ '평범차주' }, names(AuroraOwnerBoardController.search('22나4455', null)), '공백 무시');
        System.assertEquals(new Set<String>{ '위험차주' }, names(AuroraOwnerBoardController.search('010 3333 0001', null)), '전화');
        System.assertEquals(0, AuroraOwnerBoardController.search('없는사람', null).size());
    }

    @IsTest
    static void filters() {
        System.assertEquals(new Set<String>{ '위험차주' }, names(AuroraOwnerBoardController.search('', new List<String>{ 'lemon' })));
        System.assertEquals(new Set<String>{ '위험차주' }, names(AuroraOwnerBoardController.search('', new List<String>{ 'openVoc' })));
        System.assertEquals(new Set<String>{ '위험차주' }, names(AuroraOwnerBoardController.search('', new List<String>{ 'expiring' })));
        System.assert(!names(AuroraOwnerBoardController.search('', new List<String>{ 'risk' })).contains('평범차주'), '위험 높음만');
        System.assertEquals(0, AuroraOwnerBoardController.search('평범', new List<String>{ 'lemon' }).size(), '검색 + 필터 함께');
    }
}
