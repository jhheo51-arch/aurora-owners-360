/**
 * 오로라 AI 상담(AICX) 화면 컨트롤러 — PRD §20-6·20-7. 대화 상태는 LWC가 들고 있고,
 * 이 클래스는 매 호출마다 서버에서 규칙을 다시 판정한다(화면이 보낸 판정 결과를 믿지 않음).
 * VOC 생성은 사람과 같은 v1 Flow·v2 유효성 규칙·v4 리콜 경보 트리거를 그대로 통과한다.
 */
public with sharing class AicxController {
    public static final String REFUSE = 'REFUSE';
    static final List<String> INJECTION = new List<String>{
        '관리자 모드', '개발자 모드', '다른 고객', '모든 고객', '전체 고객', '고객 목록', '시스템 프롬프트', '이전 지시', 'ignore'
    };
    static final String REFUSAL = '죄송하지만 다른 고객의 정보나 내부 정보는 안내할 수 없습니다. 본인 차량에 대한 문의만 도와드릴 수 있어요.';

    public class EvalResult {
        @AuraEnabled public String action;
        @AuraEnabled public String message;
        @AuraEnabled public AicxRoutingService.Decision decision;
    }

    public class GuideResult {
        @AuraEnabled public String text;
        @AuraEnabled public Boolean usedAi = false;
    }

    public class Outcome {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String outcome;
        @AuraEnabled public String message;
        @AuraEnabled public AicxRoutingService.Decision decision;
    }

    @AuraEnabled
    public static AicxRoutingService.Identity identify(String phone, String plate4) {
        return AicxRoutingService.identify(phone, plate4);
    }

    @AuraEnabled
    public static EvalResult evaluate(Id contactId, Id vehicleId, String message) {
        EvalResult r = new EvalResult();
        if (isInjection(message)) {
            r.action = REFUSE;
            r.message = REFUSAL;
            return r;
        }
        r.decision = AicxRoutingService.evaluate(contactId, vehicleId, message);
        r.action = r.decision.action;
        if (r.action == AicxRoutingService.INFO) {
            r.message = r.decision.info.text;
        }
        return r;
    }

    /** v4.3 정보 안내 후 '궁금증 해결됐어요' → 별점과 함께 종결 기록(AI 정보 안내, D3). 상담원 배정 없음 → 지표·위험 점수 제외 */
    @AuraEnabled
    public static Outcome finishInfo(Id contactId, Id vehicleId, String message, Integer csat) {
        AicxRoutingService.Decision d = AicxRoutingService.evaluate(contactId, vehicleId, message);
        if (d.action != AicxRoutingService.INFO) {
            throw new AuraHandledException('정보 안내 대상이 아닙니다.');
        }
        Case c = new Case(
            Subject = ('[AI 상담] ' + message).left(255),
            Description = ('AI 상담 정보 안내 (' + d.intent.code + ' ' + d.intent.label + ')\n차주 문의: ' + message
                + '\n안내: ' + d.info.text + '\n사용한 데이터: ' + d.info.sources).left(32000),
            ContactId = contactId,
            Vehicle__c = vehicleId,
            VOC_Category__c = d.category,
            Priority = 'Low',
            VOC_Status__c = '종결',
            AI_Outcome__c = AicxInfoService.AI_INFO,
            CSAT__c = csat,
            First_Response_At__c = Datetime.now(),
            Resolution_Method__c = '상담 안내',
            Resolution__c = 'AI 정보 안내: ' + d.intent.label + ' (만족도 ' + csat + '점)'
        );
        insert c;
        Outcome o = new Outcome();
        o.caseId = c.Id;
        o.caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
        o.outcome = AicxInfoService.AI_INFO;
        o.decision = d;
        o.message = '도움이 되어 다행입니다. 이용해 주셔서 감사합니다.';
        return o;
    }

    /** v4.3 정보 안내 후 '상담사 연결해 주세요' → R9 사람 요청으로 연결. 이때는 고객 이력(R2~R5)도 연결 사유에 함께 남긴다. */
    @AuraEnabled
    public static Outcome connectHuman(Id contactId, Id vehicleId, String message) {
        if (isInjection(message)) {
            throw new AuraHandledException(REFUSAL);
        }
        AicxRoutingService.Decision d = AicxRoutingService.evaluate(contactId, vehicleId, message);
        List<AicxRoutingService.Hit> reasons = new List<AicxRoutingService.Hit>{
            new AicxRoutingService.Hit('R9', '사람 요청', 'AI 안내 후 상담사 연결 요청') };
        reasons.addAll(d.notes);
        reasons.addAll(d.rules);
        d.rules = reasons;
        d.notes = new List<AicxRoutingService.Hit>();   // 연결 사유로 옮겼으니 '상담원 참고'에서는 뺀다(화면 중복 표시 방지)
        d.action = AicxRoutingService.HANDOFF;
        if (d.advisorId == null) {
            AicxRoutingService.assign(d, contactId, d.category == AicxRoutingService.SAFETY);
        }
        return createCase(contactId, vehicleId, message, d, '상담사 연결', null, null);
    }

    /** 위키 단계를 차주용 문장으로(AI). 실패하면 위키 원문 단계를 그대로 보여 준다. */
    @AuraEnabled
    public static GuideResult guide(Id wikiId, Id vehicleId) {
        GuideResult g = new GuideResult();
        Failure_Mode__c fm = [SELECT Name, Resolution_Steps__c FROM Failure_Mode__c WHERE Id = :wikiId];
        try {
            if (Test.isRunningTest()) {
                throw new AuraHandledException('테스트에서는 AI 호출 안 함');
            }
            g.text = generate('Aurora_Customer_Guide', new Map<String, Id>{ 'Input:Wiki' => wikiId, 'Input:Vehicle' => vehicleId });
            g.usedAi = String.isNotBlank(g.text);
        } catch (Exception e) {
            g.usedAi = false;
        }
        if (String.isBlank(g.text)) {
            g.text = (fm.Resolution_Steps__c == null ? '자세한 확인을 위해 상담사를 연결해 드리겠습니다.' : fm.Resolution_Steps__c)
                + '\n계속되면 상담사를 연결해 드리겠습니다.';
        }
        return g;
    }

    /** 상담사 연결(HANDOFF) 또는 AI 접수(NO_MATCH). 서버에서 다시 판정해 VOC를 만든다. */
    @AuraEnabled
    public static Outcome submit(Id contactId, Id vehicleId, String message) {
        if (isInjection(message)) {
            throw new AuraHandledException(REFUSAL);
        }
        AicxRoutingService.Decision d = AicxRoutingService.evaluate(contactId, vehicleId, message);
        if (d.action == AicxRoutingService.GUIDE || d.action == AicxRoutingService.INFO) {
            throw new AuraHandledException('자동 안내 대상입니다. 안내 결과(해결 여부)를 먼저 받아 주세요.');
        }
        return createCase(contactId, vehicleId, message, d, d.action == AicxRoutingService.HANDOFF ? '상담사 연결' : 'AI 접수', null, null);
    }

    /** 안내 후 결과: 해결됨 → 위키 성공 +1, VOC 생성·종결(AI 자가 해결) / 안 됨 → 위키 실패 +1, 상담사 연결 */
    @AuraEnabled
    public static Outcome resolve(Id contactId, Id vehicleId, String message, Id wikiId, Boolean solved, Integer csat) {
        AicxRoutingService.Decision d = AicxRoutingService.evaluate(contactId, vehicleId, message);
        AicxSelfHelpService.recordOutcome(wikiId, solved);
        if (solved) {
            return createCase(contactId, vehicleId, message, d, 'AI 자가 해결', wikiId, csat);
        }
        d.rules.add(new AicxRoutingService.Hit('AI', 'AI 안내 실패', '안내 후 해결 안 됨'));
        d.action = AicxRoutingService.HANDOFF;
        return createCase(contactId, vehicleId, message, d, '상담사 연결', wikiId, null);
    }

    /** 상담사 인계 요약(v4 Aurora_Handover_Summary 재사용, AI). 화면의 버튼으로만 호출 */
    @AuraEnabled
    public static String handoverSummary(Id caseId) {
        try {
            return generate('Aurora_Handover_Summary', new Map<String, Id>{ 'Input:Case' => caseId });
        } catch (Exception e) {
            throw new AuraHandledException('인계 요약을 만들지 못했습니다: ' + e.getMessage());
        }
    }

    static Outcome createCase(Id contactId, Id vehicleId, String message, AicxRoutingService.Decision d, String outcome, Id wikiId, Integer csat) {
        Boolean selfSolved = outcome == 'AI 자가 해결';
        Case c = new Case(
            Subject = ('[AI 상담] ' + message).left(255),
            Description = 'AI 상담 대화\n차주 문의: ' + message + '\n판정: ' + d.action + ' · 유형 ' + d.category
                + (d.wiki == null ? '' : '\n매칭 위키: ' + d.wiki.title + ' (점수 ' + d.wiki.score + ', ' + d.wiki.reason + ')')
                + '\n배정: ' + d.assignReason,
            ContactId = contactId,
            Vehicle__c = vehicleId,
            VOC_Category__c = d.category,
            Priority = d.category == AicxRoutingService.SAFETY ? 'High' : 'Medium',
            VOC_Status__c = selfSolved ? '종결' : '접수',
            Advisor__c = d.advisorId,
            Manager_Employee__c = d.managerId,
            AI_Outcome__c = outcome,
            Handoff_Reason__c = selfSolved ? null : (d.rules.isEmpty() ? null : d.handoffReason()),
            AI_Wiki__c = wikiId,
            CSAT__c = csat
        );
        if (d.needsManager) {
            c.Needs_Manager__c = true;
            c.Assistance_Reason__c = ('[AI 상담] ' + d.handoffReason()).left(255);
        }
        if (selfSolved) {
            c.First_Response_At__c = Datetime.now();
            c.Failure_Mode__c = wikiId;
            c.Resolution_Method__c = 'AI 자가 해결';
            c.Resolution__c = 'AI 상담 위키 안내로 차주가 직접 해결 (만족도 ' + csat + '점)';
        }
        insert c;
        if (!selfSolved && d.wiki == null) {
            attachRagMemo(c);
        }
        Case saved = [SELECT Id, CaseNumber, Current_Handler__r.Name, Escalation_Status__c FROM Case WHERE Id = :c.Id];
        Outcome o = new Outcome();
        o.caseId = saved.Id;
        o.caseNumber = saved.CaseNumber;
        o.outcome = outcome;
        o.decision = d;
        if (selfSolved) {
            o.message = '해결되어 다행입니다. 상담 기록(VOC ' + saved.CaseNumber + ')을 남기고 종결했습니다. 이용해 주셔서 감사합니다.';
        } else if (outcome == '상담사 연결') {
            o.message = '상담사 ' + d.advisorName + '님께 연결해 드렸습니다(VOC ' + saved.CaseNumber + ').'
                + (d.needsManager ? ' 안전과 관련된 문의라 담당 팀장 ' + d.managerName + '님이 함께 확인합니다. 안전을 위해 운행을 자제해 주세요.' : '')
                + ' 곧 연락드리겠습니다.';
        } else {
            o.message = '문의를 접수했습니다(VOC ' + saved.CaseNumber + '). 담당 상담원 ' + d.advisorName + '님이 확인 후 연락드리겠습니다.';
        }
        return o;
    }

    /** v4.4 F4: 위키가 없는 문의는 RAG 검색 근거를 상담원 인계 메모로만 남긴다(고객에게 노출 안 함, AI 호출 없음) */
    static void attachRagMemo(Case c) {
        try {
            List<AuroraRagService.Evidence> ev = AuroraRagService.evidenceOnly(c.Id);
            String memo = ev.size() < AuroraRagService.MIN_EVIDENCE
                ? '비슷한 해결 사례 부족(근거 ' + ev.size() + '건) — 직접 진단 필요'
                : AuroraRagService.evidenceBlock(ev) + '\nVOC 화면 [AI 해결 가이드]로 근거 기반 정리를 볼 수 있습니다.';
            update new Case(Id = c.Id, Description = (c.Description + '\n\n[상담원 인계 메모 · 비슷한 해결 사례(RAG 검색)]\n' + memo).left(32000));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'RAG 인계 메모 실패: ' + e.getMessage());
        }
    }

    static String generate(String template, Map<String, Id> inputs) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
        for (String key : inputs.keySet()) {
            ConnectApi.WrappedValue w = new ConnectApi.WrappedValue();
            w.value = new Map<String, String>{ 'id' => inputs.get(key) };
            params.put(key, w);
        }
        input.inputParams = params;
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptBuilderPreview';
        input.isPreview = false;
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation r =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(template, input);
        return r.generations == null || r.generations.isEmpty() ? null : r.generations[0].text;
    }

    @TestVisible
    static Boolean isInjection(String message) {
        String m = message == null ? '' : message.toLowerCase();
        for (String w : INJECTION) {
            if (m.contains(w.toLowerCase())) {
                return true;
            }
        }
        return false;
    }
}
