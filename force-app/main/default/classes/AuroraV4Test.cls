@IsTest
private class AuroraV4Test {
    @TestSetup
    static void setup() {
        Vehicle_Model__c nl = new Vehicle_Model__c(Name = '노스라이트 T', Model_Line__c = '노스라이트', Model_Code__c = 'T-V4-NL');
        Vehicle_Model__c ct = new Vehicle_Model__c(Name = '시티로 T', Model_Line__c = '시티로', Model_Code__c = 'T-V4-CT');
        insert new List<Vehicle_Model__c>{ nl, ct };
        Contact owner = new Contact(LastName = 'v4 차주');
        insert owner;
        insert new List<Vehicle__c>{
            new Vehicle__c(VIN__c = 'TESTV4NL000000001', Vehicle_Model__c = nl.Id, Owner_Contact__c = owner.Id, Delivery_Date__c = Date.today().addMonths(-8)),
            new Vehicle__c(VIN__c = 'TESTV4NL000000002', Vehicle_Model__c = nl.Id),
            new Vehicle__c(VIN__c = 'TESTV4CT000000003', Vehicle_Model__c = ct.Id)
        };
        Care_Staff__c manager = new Care_Staff__c(Name = '팀장', Role__c = '상담팀장', Staff_Number__c = 'T-V4-M');
        insert manager;
        insert new List<Care_Staff__c>{
            new Care_Staff__c(Name = '상담원', Role__c = '상담원', Staff_Number__c = 'T-V4-A', Manager__c = manager.Id),
            new Care_Staff__c(Name = '테스트품질담당', Role__c = '품질·안전 대응', Staff_Number__c = 'T-V4-Q')
        };
    }

    static Map<String, Id> ids() {
        Map<String, Id> m = new Map<String, Id>();
        for (Vehicle__c v : [SELECT Id, VIN__c FROM Vehicle__c WHERE VIN__c LIKE 'TESTV4%']) {
            m.put(v.VIN__c.right(1), v.Id);
        }
        for (Care_Staff__c s : [SELECT Id, Staff_Number__c FROM Care_Staff__c WHERE Staff_Number__c LIKE 'T-V4-%']) {
            m.put(s.Staff_Number__c, s.Id);
        }
        return m;
    }

    static Case safety(Id vehicleId, String subject, Map<String, Id> m) {
        return new Case(Subject = subject, Vehicle__c = vehicleId, Advisor__c = m.get('T-V4-A'), Manager_Employee__c = m.get('T-V4-M'),
            VOC_Category__c = '안전 결함', VOC_Status__c = '접수', Priority = 'High');
    }

    @IsTest
    static void recallAlertCountsSameLineAndSystem() {
        Map<String, Id> m = ids();
        Test.startTest();
        insert safety(m.get('1'), '주행 중 브레이크 경고등', m);
        System.assertEquals(0, [SELECT COUNT() FROM Recall_Alert__c], '1건은 경보 없음');
        insert safety(m.get('3'), '브레이크 페달 밀림', m); // 다른 모델 계열
        insert safety(m.get('2'), '급제동 시 제동력 저하', m);
        Test.stopTest();

        Recall_Alert__c a = [SELECT Model_Line__c, System__c, VOC_Count__c, Status__c, Assigned_Staff__c, Summary__c,
                             (SELECT Id FROM Cases__r) FROM Recall_Alert__c];
        System.assertEquals('노스라이트', a.Model_Line__c);
        System.assertEquals('제동', a.System__c);
        System.assertEquals(2, a.VOC_Count__c);
        System.assertEquals('신규', a.Status__c);
        System.assertEquals(m.get('T-V4-Q'), a.Assigned_Staff__c, '담당 = 역할이 품질·안전 대응인 직원');
        System.assertEquals(2, a.Cases__r.size());

        insert safety(m.get('1'), 'ABS 경고등 점등', m);
        a = [SELECT VOC_Count__c FROM Recall_Alert__c];
        System.assertEquals(3, a.VOC_Count__c, '같은 경보에 건수만 갱신');
        System.assertEquals(1, [SELECT COUNT() FROM Recall_Alert__c]);
    }

    @IsTest
    static void systemFallsBackToKeywords() {
        System.assertEquals('배터리', RecallAlertService.systemOf(new Case(Subject = '급속 충전 중 화재 냄새')));
        System.assertEquals(null, RecallAlertService.systemOf(new Case(Subject = '기타 문의')));
    }

    @IsTest
    static void safetyCategoryCannotBeLoweredBeforeEscalationDone() {
        Map<String, Id> m = ids();
        Case c = safety(m.get('1'), '브레이크 경고등', m);
        insert c;
        c.VOC_Category__c = '품질 결함';
        try {
            update c;
            System.assert(false, '유효성 규칙으로 막혀야 함');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('안전 결함'), e.getMessage());
        }
    }

    @IsTest
    static void escalationActionUsesSameRules() {
        Map<String, Id> m = ids();
        Case c = new Case(Subject = '앱 오류', Vehicle__c = m.get('1'), Advisor__c = m.get('T-V4-A'),
            VOC_Category__c = '커넥티드카 앱', VOC_Status__c = '접수', Priority = 'Low');
        insert c;
        AuroraEscalationAction.Request r = new AuroraEscalationAction.Request();
        r.recordId = c.Id;
        r.reason = '차주가 같은 문제로 세 번째 연락';
        Test.startTest();
        AuroraEscalationAction.Result res = AuroraEscalationAction.run(new List<AuroraEscalationAction.Request>{ r })[0];
        AuroraEscalationAction.Result again = AuroraEscalationAction.run(new List<AuroraEscalationAction.Request>{ r })[0];
        Test.stopTest();
        System.assert(res.success, res.message);
        Case after = [SELECT Needs_Manager__c, Assistance_Reason__c, Escalation_Status__c FROM Case WHERE Id = :c.Id];
        System.assert(after.Needs_Manager__c);
        System.assert(after.Assistance_Reason__c.startsWith('[AI 에이전트]'));
        System.assertEquals('요청', after.Escalation_Status__c, 'v1 Flow가 이관 처리');
        System.assert(again.message.contains('이미'), again.message);

        AuroraEscalationAction.Request bad = new AuroraEscalationAction.Request();
        bad.recordId = m.get('1'); // 차량 ID → VOC 아님
        bad.reason = 'x';
        System.assertEquals(AuroraAgentSupport.NOT_VOC, AuroraEscalationAction.run(new List<AuroraEscalationAction.Request>{ bad })[0].message);
    }

    @IsTest
    static void lemonAndSimilarActionsAreReadOnly() {
        Map<String, Id> m = ids();
        insert new List<Service_Visit__c>{
            new Service_Visit__c(Vehicle__c = m.get('1'), Check_In_Date__c = Date.today().addMonths(-6), Completed_Date__c = Date.today().addMonths(-6).addDays(2), Visit_Type__c = '하자 수리', Defect_System__c = '배터리'),
            new Service_Visit__c(Vehicle__c = m.get('1'), Check_In_Date__c = Date.today().addMonths(-4), Completed_Date__c = Date.today().addMonths(-4).addDays(2), Visit_Type__c = '하자 수리', Defect_System__c = '배터리'),
            new Service_Visit__c(Vehicle__c = m.get('1'), Check_In_Date__c = Date.today().addMonths(-2), Completed_Date__c = Date.today().addMonths(-2).addDays(2), Visit_Type__c = '하자 수리', Defect_System__c = '배터리')
        };
        Failure_Mode__c wiki = new Failure_Mode__c(Name = '완속 충전 불가', System__c = '배터리', Status__c = '게시', Resolution_Steps__c = '1. 충전기 재연결');
        insert wiki;
        Case a = new Case(Subject = '완속 충전 불가', Vehicle__c = m.get('1'), Advisor__c = m.get('T-V4-A'), VOC_Category__c = '충전·배터리', VOC_Status__c = '접수', Priority = 'Medium');
        Case b = new Case(Subject = '완속 충전 안 됨', Vehicle__c = m.get('2'), Advisor__c = m.get('T-V4-A'), VOC_Category__c = '충전·배터리', VOC_Status__c = '접수', Priority = 'Medium', Failure_Mode__c = wiki.Id);
        insert new List<Case>{ a, b };

        AuroraLemonCheckAction.Request lr = new AuroraLemonCheckAction.Request();
        lr.recordId = a.Id;
        AuroraSimilarCasesAction.Request sr = new AuroraSimilarCasesAction.Request();
        sr.recordId = a.Id;
        Test.startTest();
        String lemon = AuroraLemonCheckAction.run(new List<AuroraLemonCheckAction.Request>{ lr })[0].message;
        String similar = AuroraSimilarCasesAction.run(new List<AuroraSimilarCasesAction.Request>{ sr })[0].message;
        AuroraLemonCheckAction.Request none = new AuroraLemonCheckAction.Request();
        none.recordId = 'not-an-id';
        String notVehicle = AuroraLemonCheckAction.run(new List<AuroraLemonCheckAction.Request>{ none })[0].message;
        Test.stopTest();

        System.assert(lemon.contains('대상 가능') && lemon.contains('배터리'), lemon);
        System.assert(lemon.contains('법적 판단이 아닙니다'), lemon);
        System.assert(similar.contains('완속 충전 안 됨') && similar.contains('충전기 재연결'), similar);
        System.assert(notVehicle.startsWith(AuroraAgentSupport.NOT_VEHICLE), notVehicle);
    }
}
