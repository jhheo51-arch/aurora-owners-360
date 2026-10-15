@IsTest
private class AuroraNotifierTest {
    @TestSetup
    static void setup() {
        Care_Staff__c lead = new Care_Staff__c(Name = '정원이', Role__c = '상담팀장', Staff_Number__c = 'T-NT-L', Active__c = true);
        insert lead;
        insert new Care_Staff__c(Name = '미나미', Role__c = '상담원', Staff_Number__c = 'T-NT-1', Active__c = true, Manager__c = lead.Id);
        insert new Contact(LastName = '알림차주', Phone = '010-4444-0001', Contact_Role__c = '차주');
    }

    static Case newCase(String category, String outcome) {
        Care_Staff__c adv = [SELECT Id, Manager__c FROM Care_Staff__c WHERE Name = '미나미'];
        return new Case(Subject = '테스트 VOC', ContactId = [SELECT Id FROM Contact WHERE LastName = '알림차주'].Id,
            Advisor__c = adv.Id, Manager_Employee__c = adv.Manager__c, VOC_Category__c = category, VOC_Status__c = '접수',
            Priority = 'Medium', AI_Outcome__c = outcome);
    }

    static String codes(Id caseId) {
        return [SELECT Alert_Codes_Sent__c FROM Case WHERE Id = :caseId].Alert_Codes_Sent__c;
    }

    @IsTest
    static void codeHelpers() {
        System.assertEquals('N1', AuroraNotifier.add(null, 'N1'));
        System.assertEquals('N1,N4', AuroraNotifier.add('N1', 'N4'));
        System.assertEquals('N1,N4', AuroraNotifier.add('N1,N4', 'N1'), '중복 추가 안 함');
        System.assert(AuroraNotifier.has('N1,N3-SOON', 'N3-SOON'));
        System.assert(!AuroraNotifier.has('N3-SOON', 'N3'), '부분 일치 아님');
    }

    @IsTest
    static void n1SafetyEscalationOnce() {
        Case c = newCase('안전 결함', null);
        Test.startTest();
        insert c;
        Test.stopTest();
        System.assertEquals('요청', [SELECT Escalation_Status__c FROM Case WHERE Id = :c.Id].Escalation_Status__c, 'v1 Flow가 이관');
        System.assertEquals('N1', codes(c.Id));
        update new Case(Id = c.Id, Description = '내용 추가');
        System.assertEquals('N1', codes(c.Id), '같은 레코드에 N1은 한 번만');
    }

    @IsTest
    static void n4AiHandoff() {
        Case c = newCase('커넥티드카 앱', '상담사 연결');
        insert c;
        System.assertEquals('N4', codes(c.Id));
        Case plain = newCase('커넥티드카 앱', null);
        insert plain;
        System.assertEquals(null, codes(plain.Id), '일반 VOC는 알림 없음');
    }

    @IsTest
    static void n2ApprovalRequestOnlyWhenNeeded() {
        Case c = newCase('품질 결함', null);
        insert c;
        Compensation__c big = new Compensation__c(Case__c = c.Id, Compensation_Type__c = '대차 지원', Amount__c = 500000, Approval_Status__c = '요청');
        Compensation__c small = new Compensation__c(Case__c = c.Id, Compensation_Type__c = '포인트 지급', Amount__c = 10000, Approval_Status__c = '요청');
        insert new List<Compensation__c>{ big, small };
        System.assertEquals('N2', [SELECT Alert_Codes_Sent__c FROM Compensation__c WHERE Id = :big.Id].Alert_Codes_Sent__c);
        System.assertEquals(null, [SELECT Alert_Codes_Sent__c FROM Compensation__c WHERE Id = :small.Id].Alert_Codes_Sent__c, '승인 불필요');
        System.assertEquals('상위 승인', AuroraNotifier.approvalLevel(new Compensation__c(Amount__c = 1000000)));
        System.assertEquals('상위 승인', AuroraNotifier.approvalLevel(new Compensation__c(Amount__c = 0, Compensation_Type__c = '보증 연장')));
        System.assertEquals('팀장 승인', AuroraNotifier.approvalLevel(new Compensation__c(Amount__c = 300000)));
    }

    @IsTest
    static void n3SoonThenOverOncePerKind() {
        Case c = newCase('품질 결함', null);
        insert c;
        Case answered = newCase('품질 결함', null);
        insert answered;
        update new Case(Id = answered.Id, First_Response_At__c = Datetime.now());
        AuroraNotifier.SlaRequest soon = new AuroraNotifier.SlaRequest();
        soon.recordId = c.Id;
        soon.kind = 'SOON';
        AuroraNotifier.SlaRequest skip = new AuroraNotifier.SlaRequest();
        skip.recordId = answered.Id;
        skip.kind = 'OVER';
        Test.startTest();
        AuroraNotifier.slaReminder(new List<AuroraNotifier.SlaRequest>{ soon, skip });
        AuroraNotifier.slaReminder(new List<AuroraNotifier.SlaRequest>{ soon });
        Test.stopTest();
        System.assertEquals('N3-SOON', codes(c.Id), '임박은 한 번만');
        System.assertEquals(null, codes(answered.Id), '첫 응답이 있으면 보내지 않음');
        AuroraNotifier.SlaRequest over = new AuroraNotifier.SlaRequest();
        over.recordId = c.Id;
        over.kind = 'OVER';
        AuroraNotifier.slaReminder(new List<AuroraNotifier.SlaRequest>{ over });
        System.assertEquals('N3-SOON,N3-OVER', codes(c.Id));
    }
}
