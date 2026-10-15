@IsTest
private class AuroraInsightTest {
    @IsTest
    static void riskScoreCombinesVocEscalationGradeAndRiskyVehicle() {
        Contact c = new Contact(LastName = '위험 점수', Customer_Grade__c = '플래티넘');
        insert c;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTRISK000000001', Owner_Contact__c = c.Id, Delivery_Date__c = Date.today().addYears(-3));
        insert v;
        Care_Staff__c manager = new Care_Staff__c(Name = '팀장', Role__c = '상담팀장', Staff_Number__c = 'T-MGR');
        insert manager;
        Care_Staff__c advisor = new Care_Staff__c(Name = '상담원', Role__c = '상담원', Staff_Number__c = 'T-ADV', Manager__c = manager.Id);
        insert advisor;

        Test.startTest();
        insert new Case(Subject = '브레이크 경고', ContactId = c.Id, Vehicle__c = v.Id, Advisor__c = advisor.Id, Manager_Employee__c = manager.Id,
            VOC_Status__c = '접수', VOC_Category__c = '안전 결함', Priority = 'High');
        insert new List<Service_Visit__c>{
            new Service_Visit__c(Vehicle__c = v.Id, Check_In_Date__c = Date.today().addMonths(-6), Visit_Type__c = '하자 수리', Defect_System__c = '제동'),
            new Service_Visit__c(Vehicle__c = v.Id, Check_In_Date__c = Date.today().addMonths(-2), Visit_Type__c = '하자 수리', Defect_System__c = '제동')
        };
        Test.stopTest();

        c = [SELECT VOC_Count_90d__c, Risk_Score__c, Risk_Level__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(1, c.VOC_Count_90d__c);
        // VOC 15 + 안전 결함 이관 15 + 플래티넘 10 + 반복 결함 차량 25
        System.assertEquals(65, c.Risk_Score__c);
        System.assertEquals('높음', c.Risk_Level__c);
    }

    @IsTest
    static void similarCasesRankSameVehicleFirst() {
        Contact c = new Contact(LastName = '유사 사례');
        insert c;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTSIM0000000001', Owner_Contact__c = c.Id);
        Vehicle__c other = new Vehicle__c(VIN__c = 'TESTSIM0000000002');
        insert new List<Vehicle__c>{ v, other };
        Care_Staff__c adv = new Care_Staff__c(Name = '상담원', Role__c = '상담원', Staff_Number__c = 'T-ADV2');
        insert adv;
        Part__c brake = new Part__c(Name = '부스터', Part_Number__c = 'P-T-BRK', System__c = '제동', Defect_Grade__c = '중대');
        insert brake;
        Failure_Mode__c wiki = new Failure_Mode__c(Name = '경고등', System__c = '제동', Status__c = '게시', Success_Count__c = 3);
        insert wiki;
        Case current = new Case(Subject = '브레이크 경고등 점등', Vehicle__c = v.Id, Advisor__c = adv.Id, VOC_Category__c = '품질 결함', VOC_Status__c = '접수');
        Case sameVehicle = new Case(Subject = '소음', Vehicle__c = v.Id, Advisor__c = adv.Id, VOC_Category__c = '기타', VOC_Status__c = '접수');
        Case sameSystem = new Case(Subject = '브레이크 경고등', Vehicle__c = other.Id, Advisor__c = adv.Id, VOC_Category__c = '품질 결함',
            VOC_Status__c = '접수', Failure_Mode__c = wiki.Id);
        Case unrelated = new Case(Subject = '출고 일정', Advisor__c = adv.Id, VOC_Category__c = '출고·인도', VOC_Status__c = '접수');
        insert new List<Case>{ current, sameVehicle, sameSystem, unrelated };
        insert new Case_Part__c(Case__c = current.Id, Part__c = brake.Id, Role__c = '의심');

        List<SimilarCaseService.Suggestion> result = SimilarCaseService.getSimilar(current.Id);
        System.assertEquals(2, result.size(), '관련 없는 VOC는 제외');
        System.assertEquals(sameVehicle.Id, result[0].caseId, '같은 차량(100)이 가장 높음: ' + result[0].reason);
        System.assertEquals(sameSystem.Id, result[1].caseId, result[1].reason);
        System.assert(result[1].reason.contains('제동') && result[1].reason.contains('키워드'), result[1].reason);
    }
}
