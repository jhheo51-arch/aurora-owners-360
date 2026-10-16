/** v5 S-5 고객 건강 점수: 감점 항목·등급·근거, 리콜 조치 완료 시 재계산, CSAT 1~5 유효성 */
@IsTest
private class CustomerHealthServiceTest {
    @IsTest
    static void scoresPenaltiesAndRecalculatesOnRecall() {
        Contact owner = new Contact(LastName = '테스트건강차주');
        insert owner;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTHS0000000001', Model__c = '시티로', Owner_Contact__c = owner.Id,
                                      Delivery_Date__c = Date.today().addYears(-1));
        insert v;
        insert new List<Case>{
            new Case(Subject = '종결 VOC', ContactId = owner.Id, Vehicle__c = v.Id, VOC_Category__c = '기타', VOC_Status__c = '종결',
                     First_Response_At__c = Datetime.now(), Proposed_Failure_Mode__c = '기타', CSAT__c = 2),
            new Case(Subject = '진행 중 VOC', ContactId = owner.Id, Vehicle__c = v.Id, VOC_Category__c = '기타', VOC_Status__c = '접수')
        };
        Recall_Campaign__c rc = new Recall_Campaign__c(Campaign_Key__c = 'T-HS1', Title__c = '테스트 캠페인', Model_Line__c = '시티로', Status__c = '진행');
        insert rc;
        Recall_Vehicle__c target = new Recall_Vehicle__c(Campaign__c = rc.Id, Vehicle__c = v.Id, Status__c = '미통지');

        Test.startTest();
        insert target;   // 트리거 → 위험·건강 점수 재계산
        Contact got = [SELECT Risk_Score__c, Health_Score__c, Health_Grade__c, Health_Basis__c FROM Contact WHERE Id = :owner.Id];
        Integer riskCut = (got.Risk_Score__c * Health_Rule__mdt.getInstance('KR_Default').Risk_Weight__c).round(System.RoundingMode.HALF_UP).intValue();
        System.assertEquals(100 - riskCut - 15 - 10 - 5, got.Health_Score__c, got.Health_Basis__c);
        System.assert(got.Health_Basis__c.contains('최근 CSAT 2점'), got.Health_Basis__c);
        System.assert(got.Health_Basis__c.contains('리콜 미조치'), got.Health_Basis__c);
        System.assert(got.Health_Basis__c.contains('진행 중 VOC 1건'), got.Health_Basis__c);

        update new Recall_Vehicle__c(Id = target.Id, Status__c = '조치 완료');   // Master-Detail 캠페인은 다시 보내지 않음
        Test.stopTest();
        Contact after = [SELECT Health_Score__c, Health_Basis__c FROM Contact WHERE Id = :owner.Id];
        System.assertEquals(got.Health_Score__c + 10, after.Health_Score__c, '조치 완료 → 리콜 감점 해제');
        System.assert(!after.Health_Basis__c.contains('리콜'), after.Health_Basis__c);
    }

    @IsTest
    static void gradesByThreshold() {
        List<Contact> rows = new List<Contact>{
            new Contact(LastName = '좋음', Risk_Score__c = 0),
            new Contact(LastName = '보통', Risk_Score__c = 60),
            new Contact(LastName = '주의', Risk_Score__c = 100)
        };
        insert rows;
        CustomerHealthService.apply(rows);
        System.assertEquals(100, rows[0].Health_Score__c);
        System.assertEquals(CustomerHealthService.GRADE_GOOD, rows[0].Health_Grade__c);
        System.assertEquals(76, rows[1].Health_Score__c);
        System.assertEquals(CustomerHealthService.GRADE_FAIR, rows[1].Health_Grade__c);
        System.assertEquals(60, rows[2].Health_Score__c);
        System.assertEquals(CustomerHealthService.GRADE_FAIR, rows[2].Health_Grade__c, '60점은 보통');
    }

    @IsTest
    static void csatMustBeOneToFive() {
        Case c = new Case(Subject = 'CSAT 범위', CSAT__c = 7);
        try {
            insert c;
            System.assert(false, 'CSAT 7은 저장되면 안 됨');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('1~5'), e.getMessage());
        }
    }
}
