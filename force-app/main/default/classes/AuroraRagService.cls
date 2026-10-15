/**
 * v4.4 P-4 유사 사례·고장 이력 RAG (docs/design/v4.4-feedback.md F4).
 * Retrieve(Apex 키워드 검색) → Augment(근거 블록을 Prompt에 병합) → Generate(Claude, Aurora_RAG_Answer) → 출처 표시.
 * 후보: 해결 내용이 있는 종결 VOC · 게시된 고장 위키 · 같은 모델 계열 하자 수리 정비 이력.
 * 점수: 공통 키워드 ×3(최대 9) + 같은 VOC 유형 3 + 같은 계통 3 + 같은 모델 계열 2 + 같은 차량 2 + 최근 1년 1.
 * 관련성 조건: 공통 키워드 또는 같은 계통이 있어야 근거로 쓴다. 상위 5건(E5), 2건 미만이면 AI를 부르지 않고 '부족' 안내.
 * 벡터 검색(Data Cloud)은 로드맵 — 검색기는 Retriever 인터페이스로 분리해 나중에 바꿀 수 있게 했다.
 */
public with sharing class AuroraRagService {
    public static final Integer TOP_K = 5;
    public static final Integer MIN_EVIDENCE = 2;
    public static final String INSUFFICIENT = '비슷한 해결 사례가 부족합니다(근거 2건 미만). 담당자가 직접 진단하고, 필요하면 팀장·EV 기술 상담에 확인해 주세요.';
    // 계통 키워드는 AuroraSystemKeywords(공용, v4.5)에서 넓은 검색(BASE + EXTRA)으로 쓴다
    // 흔한 말은 검색어에서 뺀다(주행·보증·차량 같은 말만 겹친 사례가 근거로 섞이지 않게)
    static final Set<String> STOP = new Set<String>{ 'AI', '상담', '테스트', '알림', '자꾸', '또', '계속', '해요', '돼요', '있어요',
        '주행', '주행거리', '보증', '차량', '고객', '문의', '확인', '발생', '현상', '이후', '오로라', '안내', '접수', '진행' };

    public class Evidence {
        @AuraEnabled public String label;      // 근거1, 근거2 …
        @AuraEnabled public String sourceType; // VOC · 고장 위키 · 정비 이력
        @AuraEnabled public Id recordId;
        @AuraEnabled public String title;
        @AuraEnabled public String text;       // Prompt에 들어가는 한 줄
        @AuraEnabled public Integer score;
        @AuraEnabled public String why;        // 점수 근거
    }

    public class Answer {
        @AuraEnabled public String text;
        @AuraEnabled public Boolean usedAi = false;
        @AuraEnabled public Boolean sufficient = false;
        @AuraEnabled public List<Evidence> evidence = new List<Evidence>();
    }

    /** 검색기 교체 지점(키워드 → 벡터) */
    public interface Retriever {
        List<Evidence> retrieve(Id caseId, Integer k);
    }

    public static Retriever retriever = new KeywordRetriever();

    // ===== 화면·Agent 진입점 =====
    @AuraEnabled
    public static Answer answer(Id caseId) {
        Answer a = new Answer();
        a.evidence = retriever.retrieve(caseId, TOP_K);
        a.sufficient = a.evidence.size() >= MIN_EVIDENCE;
        if (!a.sufficient) {
            a.text = INSUFFICIENT;   // AI 호출 없음
            return a;
        }
        try {
            if (Test.isRunningTest()) {
                throw new AuraHandledException('테스트에서는 AI 호출 안 함');
            }
            a.text = generate(caseId, evidenceBlock(a.evidence));
            a.text = a.text == null ? null : a.text.replace('**', '').replace('## ', '');   // 화면은 일반 텍스트라 마크다운 기호를 지운다
            a.usedAi = String.isNotBlank(a.text);
        } catch (Exception e) {
            a.usedAi = false;
        }
        if (String.isBlank(a.text)) {
            a.text = 'AI 해결 가이드를 만들지 못해 근거만 보여 드립니다.\n' + evidenceBlock(a.evidence);
        }
        return a;
    }

    @AuraEnabled
    public static List<Evidence> evidenceOnly(Id caseId) {
        return retriever.retrieve(caseId, TOP_K);
    }

    public static String evidenceBlock(List<Evidence> items) {
        List<String> lines = new List<String>();
        for (Evidence e : items) {
            lines.add('[' + e.label + '] ' + e.text);
        }
        return String.join(lines, '\n');
    }

    static String generate(Id caseId, String block) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.WrappedValue c = new ConnectApi.WrappedValue();
        c.value = new Map<String, String>{ 'id' => caseId };
        ConnectApi.WrappedValue ev = new ConnectApi.WrappedValue();
        ev.value = block;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Case' => c, 'Input:Evidence' => ev };
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptBuilderPreview';
        input.isPreview = false;
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation r =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Aurora_RAG_Answer', input);
        return r.generations == null || r.generations.isEmpty() ? null : r.generations[0].text;
    }

    // ===== 키워드 검색기 =====
    public class KeywordRetriever implements Retriever {
        public List<Evidence> retrieve(Id caseId, Integer k) {
            Case base = [SELECT Id, Subject, Description, VOC_Category__c, Vehicle__c, Vehicle__r.Vehicle_Model__r.Model_Line__c,
                                Failure_Mode__r.System__c, (SELECT Part__r.System__c FROM Case_Parts__r)
                         FROM Case WHERE Id = :caseId];
            String line = base.Vehicle__r == null || base.Vehicle__r.Vehicle_Model__r == null ? null : base.Vehicle__r.Vehicle_Model__r.Model_Line__c;
            String baseText = (base.Subject == null ? '' : base.Subject) + ' ' + (base.Description == null ? '' : base.Description.left(500));
            Set<String> words = keywords(baseText);
            Set<String> systems = new Set<String>();
            if (base.Failure_Mode__r != null && base.Failure_Mode__r.System__c != null) {
                systems.add(base.Failure_Mode__r.System__c);
            }
            for (Case_Part__c cp : base.Case_Parts__r) {
                systems.add(cp.Part__r.System__c);
            }
            systems.addAll(systemsOf(baseText));
            Date yearAgo = Date.today().addYears(-1);

            List<Evidence> found = new List<Evidence>();
            // 1) 해결 내용이 있는 종결 VOC
            for (Case c : [SELECT Id, CaseNumber, Subject, VOC_Category__c, Vehicle__c, Vehicle__r.Vehicle_Model__r.Model_Line__c,
                                  Root_Cause__c, Resolution__c, Resolution_Method__c, Failure_Mode__r.System__c, ClosedDate, CreatedDate
                           FROM Case WHERE Id != :caseId AND VOC_Status__c = '종결' AND AI_Outcome__c != :AicxInfoService.AI_INFO
                           AND (Resolution__c != null OR Root_Cause__c != null) ORDER BY CreatedDate DESC LIMIT 200]) {
                String text = c.Subject + ' ' + (c.Root_Cause__c == null ? '' : c.Root_Cause__c) + ' ' + (c.Resolution__c == null ? '' : c.Resolution__c);
                String sys = c.Failure_Mode__r != null && c.Failure_Mode__r.System__c != null ? c.Failure_Mode__r.System__c : firstSystem(text);
                Evidence e = score(words, systems, line, base.VOC_Category__c, base.Vehicle__c,
                    text, sys, c.Vehicle__r == null || c.Vehicle__r.Vehicle_Model__r == null ? null : c.Vehicle__r.Vehicle_Model__r.Model_Line__c,
                    c.VOC_Category__c, c.Vehicle__c, c.CreatedDate.date() >= yearAgo);
                if (e == null) {
                    continue;
                }
                e.sourceType = 'VOC';
                e.recordId = c.Id;
                e.title = 'VOC ' + c.CaseNumber + ' ' + c.Subject;
                e.text = 'VOC ' + c.CaseNumber + ' · ' + nz(c.Vehicle__r == null || c.Vehicle__r.Vehicle_Model__r == null ? null : c.Vehicle__r.Vehicle_Model__r.Model_Line__c)
                    + ' · ' + nz(sys) + ' · 증상: ' + c.Subject + ' · 원인: ' + nz(c.Root_Cause__c) + ' · 조치(' + nz(c.Resolution_Method__c) + '): ' + nz(c.Resolution__c);
                found.add(e);
            }
            // 2) 게시된 고장 위키
            for (Failure_Mode__c fm : [SELECT Id, Name, System__c, Symptom__c, Cause__c, Resolution_Steps__c, Applicable_Models__c,
                                              Success_Count__c, Failure_Count__c, Self_Solvable__c, LastModifiedDate
                                       FROM Failure_Mode__c WHERE Status__c = '게시']) {
                String text = fm.Name + ' ' + nz(fm.Symptom__c) + ' ' + nz(fm.Cause__c);
                Boolean sameLine = line != null && fm.Applicable_Models__c != null && fm.Applicable_Models__c.contains(line);
                Evidence e = score(words, systems, sameLine ? line : null, null, null, text, fm.System__c, line, null, null, true);
                if (e == null) {
                    continue;
                }
                e.sourceType = '고장 위키';
                e.recordId = fm.Id;
                e.title = '고장 위키 ' + fm.Name;
                e.text = '고장 위키 "' + fm.Name + '" · ' + nz(fm.System__c) + ' · 증상: ' + nz(fm.Symptom__c).left(120) + ' · 원인: ' + nz(fm.Cause__c).left(120)
                    + ' · 해결 단계: ' + nz(fm.Resolution_Steps__c).left(300) + ' · 결과: 성공 ' + intOf(fm.Success_Count__c) + '회/실패 ' + intOf(fm.Failure_Count__c) + '회';
                found.add(e);
            }
            // 3) 같은 모델 계열 하자 수리 정비 이력
            if (line != null) {
                for (Service_Visit__c s : [SELECT Id, Name, Check_In_Date__c, Completed_Date__c, Defect_System__c, Symptom__c, Main_Part__r.Name,
                                                  Vehicle__c, Vehicle__r.Name
                                           FROM Service_Visit__c WHERE Visit_Type__c = '하자 수리'
                                           AND Vehicle__r.Vehicle_Model__r.Model_Line__c = :line ORDER BY Check_In_Date__c DESC LIMIT 100]) {
                    String text = nz(s.Symptom__c) + ' ' + nz(s.Main_Part__r == null ? null : s.Main_Part__r.Name);
                    Evidence e = score(words, systems, line, null, base.Vehicle__c, text, s.Defect_System__c, line, null, s.Vehicle__c,
                        s.Check_In_Date__c != null && s.Check_In_Date__c >= yearAgo);
                    if (e == null) {
                        continue;
                    }
                    e.sourceType = '정비 이력';
                    e.recordId = s.Id;
                    e.title = '정비 ' + s.Name + ' ' + s.Vehicle__r.Name;
                    e.text = '정비 ' + s.Name + ' · ' + line + ' ' + s.Vehicle__r.Name + ' · ' + nz(s.Defect_System__c) + ' · 증상: ' + nz(s.Symptom__c).left(120)
                        + ' · 교체 부품: ' + nz(s.Main_Part__r == null ? null : s.Main_Part__r.Name)
                        + ' · ' + (s.Completed_Date__c == null ? '정비 중' : '수리 완료 ' + String.valueOf(s.Completed_Date__c));
                    found.add(e);
                }
            }
            sortByScore(found);
            List<Evidence> top = new List<Evidence>();
            for (Integer i = 0; i < found.size() && i < k; i++) {
                found[i].label = '근거' + (i + 1);
                top.add(found[i]);
            }
            return top;
        }
    }

    /** 관련성 없으면 null. 공통 키워드 또는 같은 계통이 있어야 근거가 된다. */
    @TestVisible
    static Evidence score(Set<String> words, Set<String> systems, String line, String category, Id vehicleId,
                          String text, String sys, String otherLine, String otherCategory, Id otherVehicle, Boolean recent) {
        Set<String> shared = keywords(text);
        shared.retainAll(words);
        Boolean sameSystem = sys != null && systems.contains(sys);
        if (shared.isEmpty() && !sameSystem) {
            return null;
        }
        Integer s = Math.min(shared.size() * 3, 9);
        List<String> why = new List<String>();
        if (!shared.isEmpty()) {
            why.add('키워드 ' + String.join(new List<String>(shared), ','));
        }
        if (category != null && category == otherCategory) {
            s += 3;
            why.add('같은 유형');
        }
        if (sameSystem) {
            s += 3;
            why.add(sys + ' 계통');
        }
        if (line != null && line == otherLine) {
            s += 2;
            why.add('같은 모델');
        }
        if (vehicleId != null && vehicleId == otherVehicle) {
            s += 2;
            why.add('같은 차량');
        }
        if (recent == true) {
            s += 1;
        }
        Evidence e = new Evidence();
        e.score = s;
        e.why = String.join(why, ' · ');
        return e;
    }

    @TestVisible
    static Set<String> keywords(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String w : text.split('[\\s·,()\\[\\]/:."\'!?~]+')) {
            String t = w.trim();
            // 조사 붙은 말 끝을 조금 다듬는다(경고등이 → 경고등)
            t = t.replaceAll('(이|가|을|를|은|는|에|에서|도|요|해요|돼요|됨|함)$', '');
            if (t.length() >= 2 && !STOP.contains(t)) {
                out.add(t);
            }
        }
        return out;
    }

    static Set<String> systemsOf(String text) {
        return AuroraSystemKeywords.systemsOf(text, true);
    }

    /** 걸리는 계통 중 공용 순서(제동 → 배터리 → …)에서 가장 앞의 것 */
    static String firstSystem(String text) {
        Set<String> s = systemsOf(text);
        for (String sys : AuroraSystemKeywords.ORDER) {
            if (s.contains(sys)) {
                return sys;
            }
        }
        return null;
    }

    static void sortByScore(List<Evidence> items) {
        for (Integer i = 1; i < items.size(); i++) {
            Evidence key = items[i];
            Integer j = i - 1;
            while (j >= 0 && items[j].score < key.score) {
                items[j + 1] = items[j];
                j--;
            }
            items[j + 1] = key;
        }
    }

    static String nz(String s) {
        return String.isBlank(s) ? '미확인' : s;
    }

    static Integer intOf(Decimal d) {
        return d == null ? 0 : d.intValue();
    }
}
