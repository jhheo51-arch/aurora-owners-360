@IsTest
private class AuroraCardControllerTest {
    @IsTest
    static void cardsShowBadgesGaugesAndHomeCounts() {
        Contact owner = new Contact(LastName = '카드 테스트', Email = 'card@aurora.example.com');
        insert owner;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTCARD000000001', Owner_Contact__c = owner.Id, Mileage__c = 30000,
            Delivery_Date__c = Date.today().addYears(-4));
        insert v;
        insert new List<Vehicle_Warranty__c>{
            new Vehicle_Warranty__c(Vehicle__c = v.Id, Warranty_Type__c = '일반', Start_Date__c = Date.today().addYears(-3),
                End_Date__c = Date.today().addDays(-1), Mileage_Limit_Km__c = 60000),
            new Vehicle_Warranty__c(Vehicle__c = v.Id, Warranty_Type__c = '배터리', Start_Date__c = Date.today().addYears(-2),
                End_Date__c = Date.today().addYears(6), Mileage_Limit_Km__c = 160000)
        };
        Care_Staff__c manager = new Care_Staff__c(Name = '팀장', Role__c = '상담팀장', Staff_Number__c = 'T-CARD-M');
        insert manager;
        Care_Staff__c adv = new Care_Staff__c(Name = '상담원', Role__c = '상담원', Staff_Number__c = 'T-CARD-A', Manager__c = manager.Id);
        insert adv;
        Case safety = new Case(Subject = '브레이크 경고등', ContactId = owner.Id, Vehicle__c = v.Id, Advisor__c = adv.Id,
            Manager_Employee__c = manager.Id, VOC_Category__c = '안전 결함', VOC_Status__c = '접수', Priority = 'High');
        insert safety;

        Test.startTest();
        AuroraCardController.Situation s = AuroraCardController.getVocSituation(safety.Id);
        List<AuroraCardController.Badge> vehBadges = AuroraCardController.getBadges(v.Id);
        List<AuroraCardController.Badge> ownerBadges = AuroraCardController.getBadges(owner.Id);
        List<AuroraCardController.Badge> caseBadges = AuroraCardController.getBadges(safety.Id);
        AuroraCardController.Owner360 o = AuroraCardController.getOwner360(owner.Id);
        List<AuroraCardController.Gauge> gauges = AuroraCardController.getWarrantyGauges(v.Id);
        AuroraCardController.HomeHero h = AuroraCardController.getHomeHero();
        Test.stopTest();

        System.assertEquals('danger', s.tone, '안전 결함은 빨간 테두리');
        Set<String> labels = new Set<String>();
        for (AuroraCardController.Badge b : s.badges) {
            labels.add(b.label);
        }
        System.assert(labels.contains('⚠ 안전 결함'), labels);
        System.assertEquals(s.badges.size(), caseBadges.size());
        System.assertEquals('🛡 일반 보증 만료', vehBadges[vehBadges.size() - 1].label);
        System.assertEquals(1, o.openVoc);
        System.assertEquals(1, o.vehicleCount);
        System.assertEquals(o.badges.size(), ownerBadges.size());
        Map<String, AuroraCardController.Gauge> byType = new Map<String, AuroraCardController.Gauge>();
        for (AuroraCardController.Gauge g : gauges) {
            byType.put(g.type, g);
        }
        System.assertEquals('done', byType.get('일반').tone, '기간 지난 일반 보증은 만료');
        System.assertEquals('ok', byType.get('배터리').tone);
        System.assertEquals(1, h.open);
        System.assertEquals(1, h.safety);
    }
}
