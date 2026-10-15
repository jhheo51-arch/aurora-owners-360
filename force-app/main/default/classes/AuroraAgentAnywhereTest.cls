/** v4.2 어디서든 Agent: 대상 찾기(AuroraRecordFinder)·업무 조회(AuroraWorkQueryAction) 테스트 */
@IsTest
private class AuroraAgentAnywhereTest {
    @TestSetup
    static void setup() {
        Vehicle_Model__c m = new Vehicle_Model__c(Name = '시티로 A', Model_Line__c = '시티로', Model_Code__c = 'T-AW-CT');
        insert m;
        List<Contact> cs = new List<Contact>{
            new Contact(LastName = '남궁테스트', Phone = '010-6666-0001'),
            new Contact(LastName = '한테스트', Phone = '010-6666-0002'),
            new Contact(LastName = '실습앤디', Phone = '010-6666-0003')
        };
        insert cs;
        insert new List<Vehicle__c>{
            new Vehicle__c(VIN__c = 'TESTAWAY000000001', Vehicle_Model__c = m.Id, Owner_Contact__c = cs[0].Id, Plate_Number__c = '34바 9876'),
            new Vehicle__c(VIN__c = 'TESTAWAY000000002', Vehicle_Model__c = m.Id, Owner_Contact__c = cs[1].Id, Plate_Number__c = '12가 1111'),
            new Vehicle__c(VIN__c = 'TESTAWAY000000003', Vehicle_Model__c = m.Id, Owner_Contact__c = cs[1].Id, Plate_Number__c = '12가 2222')
        };
        Care_Staff__c lead = new Care_Staff__c(Name = '정원이', Role__c = '상담팀장', Staff_Number__c = 'T-AW-L', Active__c = true);
        insert lead;
        Care_Staff__c adv = new Care_Staff__c(Name = '미나미', Role__c = '상담원', Staff_Number__c = 'T-AW-1', Active__c = true, Manager__c = lead.Id);
        insert adv;
        Vehicle__c v1 = [SELECT Id FROM Vehicle__c WHERE VIN__c = 'TESTAWAY000000001'];
        insert new List<Case>{
            new Case(Subject = '완속 충전 불가', ContactId = cs[0].Id, Vehicle__c = v1.Id, Advisor__c = adv.Id, Manager_Employee__c = lead.Id,
                VOC_Category__c = '충전·배터리', VOC_Status__c = '접수', Response_Due_At__c = Datetime.now().addMinutes(30)),
            new Case(Subject = '브레이크 소음', ContactId = cs[0].Id, Vehicle__c = v1.Id, Advisor__c = adv.Id, Manager_Employee__c = lead.Id,
                VOC_Category__c = '안전 결함', VOC_Status__c = '접수'),
            new Case(Subject = '지난 문의', ContactId = cs[0].Id, Vehicle__c = v1.Id, Advisor__c = adv.Id, Manager_Employee__c = lead.Id,
                VOC_Category__c = '기타', VOC_Status__c = '종결', First_Response_At__c = Datetime.now(), Proposed_Failure_Mode__c = '기타'),
            new Case(Subject = '실습 문의', ContactId = cs[2].Id)
        };
        // 실습 Case는 VOC 상태가 비어 있다(VOC 상태 기본값 '접수'가 들어가므로 비워 둔다) → 찾지 않음
        Case practice = [SELECT Id FROM Case WHERE Subject = '실습 문의'];
        practice.VOC_Status__c = null;
        update practice;
    }

    static AuroraRecordFinder.Result find(String q, String ctx, String target) {
        AuroraRecordFinder.Request r = new AuroraRecordFinder.Request();
        r.query = q;
        r.contextRecordId = ctx;
        r.targetType = target;
        return AuroraRecordFinder.run(new List<AuroraRecordFinder.Request>{ r })[0];
    }

    static String caseNo(String subject) {
        return [SELECT CaseNumber FROM Case WHERE Subject = :subject].CaseNumber;
    }

    @IsTest
    static void byCaseNumberFullAndShort() {
        String num = caseNo('완속 충전 불가');
        AuroraRecordFinder.Result r = find(num + ' 정리해 줘', null, 'VOC');
        System.assertEquals('FOUND', r.status, r.message);
        System.assert(r.message.contains(num) && r.message.contains('기준으로 답합니다'), r.message);
        AuroraRecordFinder.Result shortForm = find('VOC ' + Integer.valueOf(num) + ' 요약', null, 'VOC');
        System.assertEquals(r.recordId, shortForm.recordId, '뒷자리만도 허용');
    }

    @IsTest
    static void ownerWithTwoOpenVocsAsksBack() {
        AuroraRecordFinder.Result r = find('남궁테스트 고객 VOC 요약해 줘', null, 'VOC');
        System.assertEquals('MULTIPLE', r.status);
        System.assert(r.message.contains('진행 중 VOC가 2건') && !r.message.contains('지난 문의'), r.message);
        AuroraRecordFinder.Result all = find('남궁테스트 고객 VOC 종결 포함해서 보여 줘', null, 'VOC');
        System.assert(all.message.contains('지난 문의'), all.message);
    }

    @IsTest
    static void vehicleByNumberPlateAndVin() {
        Id v1 = [SELECT Id FROM Vehicle__c WHERE VIN__c = 'TESTAWAY000000001'].Id;
        String vehName = [SELECT Name FROM Vehicle__c WHERE Id = :v1].Name;
        System.assertEquals(v1, find(vehName + ' 레몬법 해당돼?', null, 'ANY').recordId, 'VEH 번호 ' + vehName);
        System.assertEquals(v1, find(vehName.replace('-', ' ') + ' 레몬법', null, 'ANY').recordId, 'VEH 7 형태');
        System.assertEquals(v1, find('34바9876 반복 결함 있어?', null, 'ANY').recordId, '번호판 공백 무시');
        System.assertEquals(v1, find('TESTAWAY000000001 차', null, 'VEHICLE').recordId, 'VIN');
        System.assertEquals('MULTIPLE', find('한테스트 차량 레몬법', null, 'VEHICLE').status, '차량 2대');
    }

    @IsTest
    static void contextAndNotFound() {
        Id caseId = [SELECT Id FROM Case WHERE Subject = '브레이크 소음'].Id;
        AuroraRecordFinder.Result ctx = find('이거 정리해 줘', caseId, 'VOC');
        System.assertEquals(caseId, ctx.recordId, '열린 VOC 사용');
        AuroraRecordFinder.Result none = find('그거 정리해 줘', null, 'VOC');
        System.assertEquals('NOT_FOUND', none.status);
        System.assert(none.message.contains('VOC 번호'), none.message);
        System.assertEquals('NOT_FOUND', find('실습앤디 고객 VOC 보여 줘', null, 'VOC').status, '실습 데이터는 찾지 않음');
        Id practice = [SELECT Id FROM Case WHERE Subject = '실습 문의'].Id;
        System.assertEquals('NOT_FOUND', find('이거 요약', practice, 'VOC').status, '실습 Case 화면');
        System.assertEquals('NOT_FOUND', find('99999999 정리', null, 'VOC').status);
    }

    @IsTest
    static void workQueries() {
        String open = AuroraWorkQueryAction.query('OPEN', null);
        System.assert(open.startsWith('진행 중 VOC 2건'), open);
        String due = AuroraWorkQueryAction.query('DUE_SOON', null);
        System.assert(due.contains('완속 충전 불가') && due.contains('2건'), '안전 결함도 기한 2시간 안: ' + due);
        System.assert(AuroraWorkQueryAction.query('SAFETY', null).contains('브레이크 소음'));
        System.assert(AuroraWorkQueryAction.query('ESCALATED', null).contains('브레이크 소음'), '안전 결함은 자동 이관');
        System.assert(AuroraWorkQueryAction.query('OPEN', '미나미').startsWith('미나미 담당'));
        System.assert(AuroraWorkQueryAction.query('OPEN', '없는직원').contains('찾지 못했습니다'));
        System.assert(AuroraWorkQueryAction.query('RECALL', null).contains('리콜 경보'));
        System.assert(AuroraWorkQueryAction.query('WHATEVER', null).contains('알 수 없습니다'));
        AuroraWorkQueryAction.Request r = new AuroraWorkQueryAction.Request();
        r.queryType = 'overdue';
        System.assert(AuroraWorkQueryAction.run(new List<AuroraWorkQueryAction.Request>{ r })[0].message.contains('기한 초과'));
    }
}
