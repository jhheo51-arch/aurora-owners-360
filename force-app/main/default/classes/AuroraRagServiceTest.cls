/** v4.4 F4 RAG 평가: 정답 근거가 상위 5건에 들어오는지 5건 + 근거 부족 응답 + Agent 액션 */
@IsTest
private class AuroraRagServiceTest {
    @TestSetup
    static void setup() {
        Vehicle_Model__c nl = new Vehicle_Model__c(Name = '노스라이트 R', Model_Line__c = '노스라이트', Model_Code__c = 'T-RG-NL');
        insert nl;
        Contact owner = new Contact(LastName = '근거차주', Phone = '010-5555-0001', Contact_Role__c = '차주');
        insert owner;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTRAG00000001', Vehicle_Model__c = nl.Id, Owner_Contact__c = owner.Id, Plate_Number__c = '55가 0001');
        insert v;
        Care_Staff__c lead = new Care_Staff__c(Name = '정원이', Role__c = '상담팀장', Staff_Number__c = 'T-RG-L', Active__c = true);
        insert lead;
        Care_Staff__c adv = new Care_Staff__c(Name = '미나미', Role__c = '상담원', Staff_Number__c = 'T-RG-1', Active__c = true, Manager__c = lead.Id);
        insert adv;
        List<Case> closed = new List<Case>();
        for (List<String> s : new List<List<String>>{
                new List<String>{ 'RAG-1', '완속 충전 불가', '충전·배터리', 'OBC(완속 충전 장치) 고장', 'OBC 교체 후 정상 충전' },
                new List<String>{ 'RAG-2', '주행 중 브레이크 경고등 점등', '품질 결함', '브레이크 부스터 센서 오류', '부스터 센서 교체' },
                new List<String>{ 'RAG-3', '앱 원격 공조 실행 실패', '커넥티드카 앱', '텔레매틱스 모듈 통신 오류', 'TMU 재설정 후 정상' },
                new List<String>{ 'RAG-4', '에어컨 작동 시 냄새', '품질 결함', '증발기 곰팡이', '에어컨 필터 교체·증발기 세정' },
                new List<String>{ 'RAG-5', '후방 카메라 화면 깜빡임', '품질 결함', '카메라 커넥터 접촉 불량', '커넥터 재체결' } }) {
            closed.add(new Case(Subject = s[1], VOC_Key__c = s[0], ContactId = owner.Id, Vehicle__c = v.Id, Advisor__c = adv.Id,
                Manager_Employee__c = lead.Id, VOC_Category__c = s[2], VOC_Status__c = '종결', First_Response_At__c = Datetime.now(),
                Root_Cause__c = s[3], Resolution__c = s[4], Resolution_Method__c = '부품 교체'));
        }
        insert closed;
        insert new Failure_Mode__c(Name = '완속 충전 불가', Wiki_Key__c = 'T-RG-FM1', System__c = '배터리', Severity__c = '중간', Status__c = '게시',
            Applicable_Models__c = '노스라이트', Symptom__c = '완속 충전기 연결 시 충전 시작 안 됨', Cause__c = 'OBC 이상', Resolution_Steps__c = '1) 다른 충전기 2) OBC 진단');
    }

    static Id openCase(String subject, String category) {
        Contact o = [SELECT Id FROM Contact WHERE LastName = '근거차주'];
        Vehicle__c v = [SELECT Id FROM Vehicle__c WHERE VIN__c = 'TESTRAG00000001'];
        Care_Staff__c adv = [SELECT Id, Manager__c FROM Care_Staff__c WHERE Name = '미나미'];
        Case c = new Case(Subject = subject, ContactId = o.Id, Vehicle__c = v.Id, Advisor__c = adv.Id, Manager_Employee__c = adv.Manager__c,
            VOC_Category__c = category, VOC_Status__c = '접수');
        insert c;
        return c.Id;
    }

    static Boolean inTop(Id caseId, String expectedKey) {
        Id expected = [SELECT Id FROM Case WHERE VOC_Key__c = :expectedKey].Id;
        for (AuroraRagService.Evidence e : AuroraRagService.evidenceOnly(caseId)) {
            if (e.recordId == expected) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void retrievalAccuracyFiveQueries() {
        System.assert(inTop(openCase('완속 충전이 또 안 돼요', '충전·배터리'), 'RAG-1'), '충전');
        System.assert(inTop(openCase('브레이크 경고등이 떴어요', '품질 결함'), 'RAG-2'), '제동');
        System.assert(inTop(openCase('앱에서 원격 공조가 안 돼요', '커넥티드카 앱'), 'RAG-3'), '원격 공조');
        System.assert(inTop(openCase('에어컨 켜면 냄새가 나요', '품질 결함'), 'RAG-4'), '공조');
        System.assert(inTop(openCase('후방 카메라가 깜빡여요', '품질 결함'), 'RAG-5'), '카메라');
    }

    @IsTest
    static void sufficientUsesEvidenceWithLabels() {
        Id c = openCase('완속 충전이 또 안 돼요', '충전·배터리');
        AuroraRagService.Answer a = AuroraRagService.answer(c);
        System.assert(a.sufficient, a.text);
        System.assert(a.evidence.size() >= 2 && a.evidence.size() <= 5);
        System.assertEquals('근거1', a.evidence[0].label);
        System.assert(!a.usedAi, '테스트에서는 AI 호출 안 함 → 근거만');
        System.assert(a.text.contains('[근거1]'), a.text);
        Boolean hasWiki = false;
        for (AuroraRagService.Evidence e : a.evidence) {
            hasWiki = hasWiki || e.sourceType == '고장 위키';
        }
        System.assert(hasWiki, '게시 위키도 근거 후보');
    }

    @IsTest
    static void insufficientSkipsAi() {
        Id c = openCase('트렁크 등이 안 켜져요', '기타');
        AuroraRagService.Answer a = AuroraRagService.answer(c);
        System.assert(!a.sufficient);
        System.assertEquals(AuroraRagService.INSUFFICIENT, a.text);
        System.assert(!a.usedAi);
    }

    @IsTest
    static void agentActionShowsSources() {
        Id c = openCase('브레이크 경고등이 떴어요', '품질 결함');
        AuroraRagAnswerAction.Request r = new AuroraRagAnswerAction.Request();
        r.recordId = c;
        String msg = AuroraRagAnswerAction.run(new List<AuroraRagAnswerAction.Request>{ r })[0].message;
        System.assert(msg.contains('출처') && msg.contains('[근거1]'), msg);
        AuroraRagAnswerAction.Request bad = new AuroraRagAnswerAction.Request();
        bad.recordId = [SELECT Id FROM Contact LIMIT 1].Id;
        System.assertEquals(AuroraAgentSupport.NOT_VOC, AuroraRagAnswerAction.run(new List<AuroraRagAnswerAction.Request>{ bad })[0].message);
    }

    @IsTest
    static void keywordNormalization() {
        Set<String> k = AuroraRagService.keywords('[AI 상담] 브레이크 경고등이 또 떴어요');
        System.assert(k.contains('브레이크') && k.contains('경고등'), k);
        System.assert(!k.contains('AI') && !k.contains('상담'), k);
    }
}
