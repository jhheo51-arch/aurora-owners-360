/** v4.3 AI 상담 정보 조회 수용 테스트 Y1~Y12 (docs/design/v4.3-aicx-intents.md §9). X 회귀는 AicxTest. */
@IsTest
private class AicxInfoServiceTest {
    @TestSetup
    static void setup() {
        Vehicle_Model__c nl = new Vehicle_Model__c(Name = '노스라이트 Y', Model_Line__c = '노스라이트', Model_Code__c = 'T-AY-NL',
            Battery_Capacity_kWh__c = 84, Maintenance_Interval_Months__c = 12, Maintenance_Interval_Km__c = 15000,
            General_Warranty_Months__c = 36, General_Warranty_Km__c = 60000, Battery_Warranty_Months__c = 96, Battery_Warranty_Km__c = 160000);
        Vehicle_Model__c noCycle = new Vehicle_Model__c(Name = '주기 없음 Y', Model_Line__c = '시티로', Model_Code__c = 'T-AY-NC');
        insert new List<Vehicle_Model__c>{ nl, noCycle };
        List<Contact> owners = new List<Contact>{
            new Contact(LastName = '이력많음', Phone = '010-2222-0001', Customer_Grade__c = '플래티넘'),
            new Contact(LastName = '정비중', Phone = '010-2222-0002', Customer_Grade__c = '일반'),
            new Contact(LastName = '주기없음', Phone = '010-2222-0003', Customer_Grade__c = '일반')
        };
        insert owners;
        insert new List<Vehicle__c>{
            new Vehicle__c(VIN__c = 'TESTAICXY000001', Vehicle_Model__c = nl.Id, Owner_Contact__c = owners[0].Id, Plate_Number__c = '34나 0001',
                Model_Year__c = '2023', Delivery_Date__c = Date.today().addMonths(-30), Mileage__c = 41000, Service_Center__c = '서울 강남',
                Lemon_Law_Status__c = '대상 가능'),
            new Vehicle__c(VIN__c = 'TESTAICXY000002', Vehicle_Model__c = nl.Id, Owner_Contact__c = owners[1].Id, Plate_Number__c = '34나 0002',
                Model_Year__c = '2024', Delivery_Date__c = Date.today().addMonths(-6), Mileage__c = 5000, Service_Center__c = '서울 성수',
                Lemon_Law_Status__c = '해당 없음'),
            new Vehicle__c(VIN__c = 'TESTAICXY000003', Vehicle_Model__c = noCycle.Id, Owner_Contact__c = owners[2].Id, Plate_Number__c = '34나 0003',
                Delivery_Date__c = Date.today().addMonths(-3), Mileage__c = 2000, Lemon_Law_Status__c = '해당 없음')
        };
        Care_Staff__c lead = new Care_Staff__c(Name = '정원이', Role__c = '상담팀장', Staff_Number__c = 'T-AY-L', Active__c = true);
        insert lead;
        insert new Care_Staff__c(Name = '미나미', Role__c = '상담원', Staff_Number__c = 'T-AY-1', Active__c = true, Manager__c = lead.Id);
    }

    static Contact owner(String name) {
        return [SELECT Id, (SELECT Id FROM Owned_Vehicles__r) FROM Contact WHERE LastName = :name];
    }

    static AicxController.EvalResult ask(Contact c, String message) {
        return AicxController.evaluate(c.Id, c.Owned_Vehicles__r[0].Id, message);
    }

    static Set<String> codes(List<AicxRoutingService.Hit> hits) {
        Set<String> s = new Set<String>();
        for (AicxRoutingService.Hit h : hits) {
            s.add(h.code);
        }
        return s;
    }

    @IsTest
    static void y1MaintenanceAnsweredDespiteHistory() {
        Contact c = owner('이력많음');
        Id vid = c.Owned_Vehicles__r[0].Id;
        insert new Service_Visit__c(Vehicle__c = vid, Visit_Type__c = '정기 점검', Check_In_Date__c = Date.today().addMonths(-11),
            Completed_Date__c = Date.today().addMonths(-11), Mileage__c = 18000, Visit_Key__c = 'T-AY-SV1');
        // 정비 저장 시 레몬법이 다시 계산되므로 그 뒤에 '대상 가능'으로 둔다(R5 상황)
        update new Vehicle__c(Id = vid, Lemon_Law_Status__c = '대상 가능');
        AicxController.EvalResult r = ask(c, '정기점검 언제 받아야 해요?');
        System.assertEquals('INFO', r.action, r.decision.handoffReason());
        System.assertEquals('I1', r.decision.intent.code);
        System.assert(r.decision.rules.isEmpty(), '정보 조회는 연결 사유 없음');
        Set<String> notes = codes(r.decision.notes);
        System.assert(notes.contains('R4') && notes.contains('R5'), '이력 규칙은 상담원 참고로: ' + notes);
        System.assert(r.message.contains('18,000km') && r.message.contains('33,000km'), r.message);
        System.assert(r.message.contains('주행거리 기준으로 이미'), '41,000km > 33,000km: ' + r.message);
        System.assert(r.message.contains('가상 기준'), r.message);
    }

    @IsTest
    static void y2RepairInProgress() {
        Contact c = owner('정비중');
        Id vid = c.Owned_Vehicles__r[0].Id;
        insert new Service_Visit__c(Vehicle__c = vid, Visit_Type__c = '하자 수리', Check_In_Date__c = Date.today().addDays(-1),
            Service_Center__c = '서울 성수', Symptom__c = '급속 충전 속도 저하', Mileage__c = 5000, Visit_Key__c = 'T-AY-SV2');
        AicxController.EvalResult r = ask(c, '수리 맡긴 거 언제 끝나요?');
        System.assertEquals('INFO', r.action);
        System.assertEquals('I2', r.decision.intent.code);
        System.assert(r.message.contains('1일째 정비 중') && r.message.contains('서울 성수'), r.message);
    }

    @IsTest
    static void y3WarrantyList() {
        AicxController.EvalResult r = ask(owner('정비중'), '배터리 보증 아직 남았어요?');
        System.assertEquals('INFO', r.action, r.decision.handoffReason());
        System.assertEquals('I3', r.decision.intent.code);
        System.assert(r.message.contains('유효한 보증') && r.message.contains('배터리'), r.message);
        System.assert(r.message.contains('남은 155,000km'), '배터리 160,000 - 5,000: ' + r.message);
    }

    @IsTest
    static void y4VehicleInfo() {
        AicxController.EvalResult r = ask(owner('이력많음'), '제 차 연식이 어떻게 돼요?');
        System.assertEquals('INFO', r.action);
        System.assertEquals('I4', r.decision.intent.code);
        System.assert(r.message.contains('2023년식') && r.message.contains('41,000km') && r.message.contains('84'), r.message);
    }

    @IsTest
    static void y5MyCaseStatus() {
        Contact c = owner('정비중');
        Care_Staff__c adv = [SELECT Id FROM Care_Staff__c WHERE Name = '미나미'];
        Care_Staff__c lead = [SELECT Id FROM Care_Staff__c WHERE Name = '정원이'];
        Case open = new Case(Subject = '급속 충전 속도 저하', ContactId = c.Id, Vehicle__c = c.Owned_Vehicles__r[0].Id, Advisor__c = adv.Id,
            Manager_Employee__c = lead.Id, VOC_Category__c = '충전·배터리', VOC_Status__c = '확인 중');
        insert open;
        String num = [SELECT CaseNumber FROM Case WHERE Id = :open.Id].CaseNumber;
        AicxController.EvalResult r = ask(c, '제가 접수한 거 어떻게 됐어요?');
        System.assertEquals('INFO', r.action);
        System.assertEquals('I5', r.decision.intent.code);
        System.assert(r.message.contains(num) && r.message.contains('확인 중') && r.message.contains('미나미'), r.message);
    }

    @IsTest
    static void y6SolvedIsRecordedButNotCounted() {
        Contact c = owner('정비중');
        Id vid = c.Owned_Vehicles__r[0].Id;
        Test.startTest();
        AicxController.Outcome o1 = AicxController.finishInfo(c.Id, vid, '제 차 연식이 어떻게 돼요?', 5);
        AicxController.finishInfo(c.Id, vid, '배터리 보증 아직 남았어요?', 4);
        Test.stopTest();
        Case saved = [SELECT AI_Outcome__c, VOC_Status__c, CSAT__c, Advisor__c, VOC_Category__c, Resolution_Method__c FROM Case WHERE Id = :o1.caseId];
        System.assertEquals('AI 정보 안내', saved.AI_Outcome__c);
        System.assertEquals('종결', saved.VOC_Status__c);
        System.assertEquals(5, saved.CSAT__c);
        System.assertEquals(null, saved.Advisor__c, '상담원 배정 없음 → 홈 리포트·위험 점수 제외');
        // D3: 정보 안내 2건이 있어도 다음 문제 문의에서 R2(90일 VOC 2건)가 걸리지 않음
        AicxRoutingService.Decision d = AicxRoutingService.evaluate(c.Id, vid, '트렁크 등이 안 켜져요');
        System.assert(!codes(d.rules).contains('R2'), d.handoffReason());
        System.assertEquals('NO_MATCH', d.action);
    }

    @IsTest
    static void y7HumanRequestAfterInfo() {
        Contact c = owner('이력많음');
        Test.startTest();
        AicxController.Outcome o = AicxController.connectHuman(c.Id, c.Owned_Vehicles__r[0].Id, '정기점검 언제 받아야 해요?');
        Test.stopTest();
        Case saved = [SELECT AI_Outcome__c, Handoff_Reason__c, Advisor__c FROM Case WHERE Id = :o.caseId];
        System.assertEquals('상담사 연결', saved.AI_Outcome__c);
        System.assert(saved.Handoff_Reason__c.startsWith('R9 사람 요청'), saved.Handoff_Reason__c);
        System.assert(saved.Handoff_Reason__c.contains('R4'), '연결할 때는 이력도 사유로 남김: ' + saved.Handoff_Reason__c);
        System.assertNotEquals(null, saved.Advisor__c);
    }

    @IsTest
    static void y8EmotionHandsOff() {
        AicxController.EvalResult r = ask(owner('정비중'), '몇 번째 말하는 건지, 짜증나네요');
        System.assertEquals('HANDOFF', r.action);
        System.assert(codes(r.decision.rules).contains('R8'), r.decision.handoffReason());
    }

    @IsTest
    static void y9EmotionBeatsInfo() {
        AicxController.EvalResult r = ask(owner('정비중'), '수리 맡겼는데 아직도 안 끝나서 화나요');
        System.assertEquals('HANDOFF', r.action);
        System.assertEquals(null, r.decision.intent, '화남이 정보 조회보다 먼저');
        System.assert(codes(r.decision.rules).contains('R8'));
    }

    @IsTest
    static void y10SafetyBeatsInfo() {
        AicxController.EvalResult r = ask(owner('정비중'), '정기점검 받으러 가는데 브레이크 경고등도 떠요');
        System.assertEquals('HANDOFF', r.action);
        System.assert(codes(r.decision.rules).contains('R1'));
        System.assert(r.decision.needsManager, '안전 → 팀장');
        System.assertEquals('안전 결함', r.decision.category);
    }

    @IsTest
    static void y11MaintenanceFromDeliveryDate() {
        AicxController.EvalResult r = ask(owner('정비중'), '정기 점검 주기가 어떻게 돼요?');
        System.assertEquals('INFO', r.action);
        System.assert(r.message.contains('출고일'), r.message);
        System.assert(r.message.contains('15,000km'), r.message);
    }

    @IsTest
    static void y12NoCycleHandsOff() {
        AicxController.EvalResult r = ask(owner('주기없음'), '정기점검 언제 받아야 해요?');
        System.assertEquals('HANDOFF', r.action);
        System.assert(r.decision.handoffReason().contains('AI 답변 불가'), r.decision.handoffReason());
        System.assertNotEquals(null, r.decision.advisorId);
    }

    @IsTest
    static void humanKeywordHandsOffImmediately() {
        AicxController.EvalResult r = ask(owner('정비중'), '상담사랑 통화하고 싶어요');
        System.assertEquals('HANDOFF', r.action);
        System.assert(codes(r.decision.rules).contains('R9'));
        try {
            AicxController.finishInfo(owner('정비중').Id, owner('정비중').Owned_Vehicles__r[0].Id, '상담사랑 통화하고 싶어요', 5);
            System.assert(false, '정보 안내 대상이 아니면 기록하지 않음');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void kmFormatsWithoutLocale() {
        System.assertEquals('41,000', AicxInfoService.km(41000));
        System.assertEquals('155,000', AicxInfoService.km(155000));
        System.assertEquals('500', AicxInfoService.km(500));
        System.assertEquals('1,234,567', AicxInfoService.km(1234567));
        System.assertEquals('-2,000', AicxInfoService.km(-2000));
        System.assertEquals('로', AicxInfoService.ro('하자 수리'));
        System.assertEquals('으로', AicxInfoService.ro('정기 점검'));
        System.assertEquals('로', AicxInfoService.ro('리콜·무상수리'));
    }
}
