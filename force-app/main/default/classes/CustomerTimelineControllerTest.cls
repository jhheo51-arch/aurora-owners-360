@IsTest
private class CustomerTimelineControllerTest {
    @IsTest
    static void vehicleAndOwnerTimelinesIncludeAllEventKinds() {
        Contact owner = new Contact(LastName = '타임라인 차주');
        insert owner;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTTIMELINE00001', Delivery_Date__c = Date.today().addMonths(-6));
        insert v;
        insert new Vehicle_Party__c(Vehicle__c = v.Id, Contact__c = owner.Id, Role__c = '소유자', Start_Date__c = v.Delivery_Date__c);
        Case c = new Case(Subject = '테스트 VOC', Vehicle__c = v.Id, ContactId = owner.Id, VOC_Status__c = '접수', VOC_Category__c = '품질 결함');
        insert c;
        Part__c part = new Part__c(Name = '테스트 부품', Part_Number__c = 'P-TEST-001', System__c = '배터리', Defect_Grade__c = '중대');
        insert part;
        insert new Case_Part__c(Case__c = c.Id, Part__c = part.Id, Role__c = '교체');
        insert new Compensation__c(Case__c = c.Id, Compensation_Type__c = '무상수리', Amount__c = 10000);
        List<Service_Visit__c> visits = new List<Service_Visit__c>();
        for (Integer i = 0; i < 2; i++) {
            visits.add(new Service_Visit__c(Vehicle__c = v.Id, Check_In_Date__c = Date.today().addMonths(-4 + i), Visit_Type__c = '하자 수리',
                Defect_System__c = '배터리', Symptom__c = '충전 불가', Mileage__c = 3000));
        }
        insert visits;

        Test.startTest();
        CustomerTimelineController.Timeline byVehicle = CustomerTimelineController.getTimeline(v.Id);
        CustomerTimelineController.Timeline byOwner = CustomerTimelineController.getTimeline(owner.Id);
        Test.stopTest();

        Set<String> kinds = new Set<String>();
        for (CustomerTimelineController.TimelineEvent e : byVehicle.events) {
            kinds.add(e.kind);
        }
        System.assertEquals(new Set<String>{ 'VOC', '정비', '보상', '부품 교체', '소유권' }, kinds);
        System.assertEquals(byVehicle.events.size(), byOwner.events.size());
        System.assert(!byVehicle.badges.isEmpty(), '레몬법 주의 또는 반복 결함 배지가 있어야 함');
        System.assert(byVehicle.events[0].eventDate >= byVehicle.events[byVehicle.events.size() - 1].eventDate, '최신순 정렬');
    }

    @IsTest
    static void unrelatedRecordReturnsEmpty() {
        Account a = new Account(Name = '타임라인 없음');
        insert a;
        System.assert(CustomerTimelineController.getTimeline(a.Id).events.isEmpty());
    }
}
