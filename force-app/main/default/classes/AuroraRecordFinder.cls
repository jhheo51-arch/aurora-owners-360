/**
 * v4.2 VOC Care Assistant 대상 찾기 (docs/design/v4.2-agent-anywhere.md §3). 어느 화면에서든 대화로 대상을 찾는다.
 * 우선순위: ① 대화에 명시된 대상(VOC 번호·VEH 번호·번호판·VIN·보상 번호·차주 이름) ② 열린 레코드 ③ 없으면 되묻기.
 * 결과: FOUND(1건) / MULTIPLE(최대 5건 번호 목록, D2) / NOT_FOUND(추측하지 않고 입력 예시 안내).
 * 오로라 데이터만 찾는다: VOC = VOC_Status__c가 있는 Case, 차주 = 고객 차량이나 오로라 VOC가 연결된 Contact(D1).
 * 차주 → VOC는 진행 중만, "종결 포함"이라고 하면 종결도(D3). 읽기 전용.
 */
public with sharing class AuroraRecordFinder {
    public static final String FOUND = 'FOUND';
    public static final String MULTIPLE = 'MULTIPLE';
    public static final String NOT_FOUND = 'NOT_FOUND';
    static final Integer MAX_CANDIDATES = 5;
    static final String EXAMPLES = 'VOC 번호(예: 00001028), 차량 번호(예: VEH-0007), 번호판(예: 34바 5678), 차주 이름(예: 한서아) 중 하나를 알려 주세요.';

    public class Request {
        @InvocableVariable(label='사용자 말' description='대상을 가리키는 사용자 문장 그대로(예: 00001028 정리해 줘, 한서아 고객 VOC)' required=true)
        public String query;
        @InvocableVariable(label='열린 레코드 ID' description='현재 화면의 레코드 ID(currentRecordId). 없으면 비워 둡니다.')
        public String contextRecordId;
        @InvocableVariable(label='찾을 대상' description='VOC(사례), VEHICLE(고객 차량), ANY 중 하나. VOC 요약·답변·유사 사례는 VOC, 레몬법은 ANY')
        public String targetType;
    }

    public class Result {
        @InvocableVariable(label='상태' description='FOUND, MULTIPLE, NOT_FOUND')
        public String status;
        @InvocableVariable(label='찾은 레코드 ID' description='FOUND일 때 다음 액션의 recordId·Input:Case로 사용')
        public String recordId;
        @InvocableVariable(label='대상 설명' description='찾은 대상 한 줄 또는 되물을 후보 목록·안내 문구')
        public String message;
    }

    @InvocableMethod(label='오로라 대상 찾기' description='사용자 말이나 열린 화면에서 오로라 VOC·고객 차량을 찾습니다. 여러 건이면 후보 목록, 없으면 입력 예시를 돌려줍니다. 기록을 바꾸지 않습니다.')
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            out.add(find(r.query, r.contextRecordId, String.isBlank(r.targetType) ? 'ANY' : r.targetType.toUpperCase()));
        }
        return out;
    }

    public static Result find(String query, String contextId, String target) {
        String q = query == null ? '' : query;
        Boolean includeClosed = q.contains('종결 포함') || q.contains('종결된 것도') || q.contains('지난');
        Result r = fromText(q, target, includeClosed);
        if (r == null && String.isNotBlank(contextId)) {
            r = fromContext(contextId, target, includeClosed);
        }
        if (r == null) {
            r = new Result();
            r.status = NOT_FOUND;
            r.message = '대상을 찾지 못했습니다. ' + EXAMPLES;
        }
        return r;
    }

    // ===== ① 대화에서 찾기 =====
    static Result fromText(String q, String target, Boolean includeClosed) {
        Matcher m = Pattern.compile('(?i)CMP-?\\s?(\\d{1,6})').matcher(q);
        if (m.find()) {
            String name = 'CMP-' + m.group(1).leftPad(4, '0');
            List<Compensation__c> cs = [SELECT Case__c FROM Compensation__c WHERE Name = :name LIMIT 1];
            return cs.isEmpty() ? notFound('보상 ' + name) : fromCase(cs[0].Case__c, target);
        }
        m = Pattern.compile('(?i)VEH[-\\s]?(\\d{1,6})').matcher(q);
        if (m.find()) {
            String name = 'VEH-' + m.group(1).leftPad(4, '0');
            List<Vehicle__c> vs = [SELECT Id FROM Vehicle__c WHERE Name = :name LIMIT 1];
            return vs.isEmpty() ? notFound('차량 ' + name) : fromVehicle(vs[0].Id, target, includeClosed);
        }
        m = Pattern.compile('\\b([A-HJ-NPR-Z0-9]{17})\\b').matcher(q.toUpperCase());
        if (m.find()) {
            String vin = m.group(1);
            List<Vehicle__c> vs = [SELECT Id FROM Vehicle__c WHERE VIN__c = :vin LIMIT 1];
            return vs.isEmpty() ? notFound('차대번호 ' + vin) : fromVehicle(vs[0].Id, target, includeClosed);
        }
        m = Pattern.compile('(\\d{2,3})\\s?([가-힣])\\s?(\\d{4})').matcher(q);
        if (m.find()) {
            String plate = m.group(1) + m.group(2) + m.group(3);
            for (Vehicle__c v : [SELECT Id, Plate_Number__c FROM Vehicle__c WHERE Plate_Number__c != null]) {
                if (v.Plate_Number__c.deleteWhitespace() == plate) {
                    return fromVehicle(v.Id, target, includeClosed);
                }
            }
            return notFound('번호판 ' + m.group(1) + m.group(2) + ' ' + m.group(3));
        }
        m = Pattern.compile('(?i)(?:VOC|사례)\\s*(\\d{1,8})|\\b(\\d{8})\\b').matcher(q);
        if (m.find()) {
            String num = (m.group(1) != null ? m.group(1) : m.group(2)).leftPad(8, '0');
            List<Case> cs = [SELECT Id FROM Case WHERE CaseNumber = :num AND VOC_Status__c != null LIMIT 1];
            return cs.isEmpty() ? notFound('VOC ' + num) : fromCase(cs[0].Id, target);
        }
        // 차주 이름: 오로라 차주(D1) 중 이름이 문장에 들어 있는 사람
        List<Contact> named = new List<Contact>();
        for (Contact c : auroraOwners()) {
            if (c.Name != null && c.Name.length() >= 2 && q.contains(c.Name)) {
                named.add(c);
            }
        }
        if (named.size() == 1) {
            return fromOwner(named[0], target, includeClosed);
        }
        if (named.size() > 1) {
            Result r = new Result();
            r.status = MULTIPLE;
            List<String> lines = new List<String>{ '여러 차주가 있습니다. 어느 분인가요?' };
            for (Integer i = 0; i < named.size() && i < MAX_CANDIDATES; i++) {
                lines.add((i + 1) + '. ' + named[i].Name);
            }
            r.message = String.join(lines, '\n');
            return r;
        }
        return null;
    }

    // ===== ② 열린 레코드 =====
    static Result fromContext(String contextId, String target, Boolean includeClosed) {
        Id rid;
        try {
            rid = Id.valueOf(contextId);
        } catch (Exception e) {
            return null;
        }
        String type = rid.getSObjectType().getDescribe().getName();
        if (type == 'Case') {
            return [SELECT COUNT() FROM Case WHERE Id = :rid AND VOC_Status__c != null] == 0 ? null : fromCase(rid, target);
        }
        if (type == 'Vehicle__c') {
            return fromVehicle(rid, target, includeClosed);
        }
        if (type == 'Contact') {
            for (Contact c : auroraOwners()) {
                if (c.Id == rid) {
                    return fromOwner(c, target, includeClosed);
                }
            }
        }
        return null;
    }

    // ===== 대상 종류 맞추기 =====
    static Result fromCase(Id caseId, String target) {
        Case c = [SELECT Id, CaseNumber, Subject, VOC_Status__c, Vehicle__c FROM Case WHERE Id = :caseId];
        if (target == 'VEHICLE') {
            return c.Vehicle__c == null ? notFound('VOC ' + c.CaseNumber + '의 차량') : fromVehicle(c.Vehicle__c, target, false);
        }
        return found(c.Id, caseLabel(c));
    }

    static Result fromVehicle(Id vehicleId, String target, Boolean includeClosed) {
        Vehicle__c v = [SELECT Id, Name, Plate_Number__c, Vehicle_Model__r.Name FROM Vehicle__c WHERE Id = :vehicleId];
        if (target != 'VOC') {
            return found(v.Id, vehicleLabel(v));
        }
        return pickCase([SELECT Id, CaseNumber, Subject, VOC_Status__c FROM Case WHERE Vehicle__c = :vehicleId AND VOC_Status__c != null
                         AND AI_Outcome__c != :AicxInfoService.AI_INFO ORDER BY CreatedDate DESC], includeClosed, vehicleLabel(v));
    }

    static Result fromOwner(Contact owner, String target, Boolean includeClosed) {
        if (target == 'VOC') {
            return pickCase([SELECT Id, CaseNumber, Subject, VOC_Status__c FROM Case WHERE ContactId = :owner.Id AND VOC_Status__c != null
                             AND AI_Outcome__c != :AicxInfoService.AI_INFO ORDER BY CreatedDate DESC], includeClosed, owner.Name + ' 차주');
        }
        List<Vehicle__c> vs = [SELECT Id, Name, Plate_Number__c, Vehicle_Model__r.Name FROM Vehicle__c WHERE Owner_Contact__c = :owner.Id ORDER BY Name];
        if (vs.size() == 1) {
            return found(vs[0].Id, vehicleLabel(vs[0]));
        }
        if (vs.isEmpty()) {
            return notFound(owner.Name + ' 차주의 차량');
        }
        Result r = new Result();
        r.status = MULTIPLE;
        List<String> lines = new List<String>{ owner.Name + ' 차주의 차량이 여러 대입니다. 어느 차량인가요?' };
        for (Integer i = 0; i < vs.size() && i < MAX_CANDIDATES; i++) {
            lines.add((i + 1) + '. ' + vehicleLabel(vs[i]));
        }
        r.message = String.join(lines, '\n');
        return r;
    }

    /** 진행 중을 먼저, 진행 중이 없거나 '종결 포함'이면 종결도 */
    static Result pickCase(List<Case> all, Boolean includeClosed, String whose) {
        List<Case> open = new List<Case>();
        for (Case c : all) {
            if (c.VOC_Status__c != '종결') {
                open.add(c);
            }
        }
        List<Case> pool = includeClosed || open.isEmpty() ? all : open;
        if (pool.isEmpty()) {
            return notFound(whose + '의 VOC');
        }
        if (pool.size() == 1) {
            return found(pool[0].Id, caseLabel(pool[0]));
        }
        Result r = new Result();
        r.status = MULTIPLE;
        List<String> lines = new List<String>{ whose + '의 ' + (pool == open ? '진행 중 ' : '') + 'VOC가 ' + pool.size() + '건입니다. 어느 건인가요? (VOC 번호로 답해 주세요)' };
        for (Integer i = 0; i < pool.size() && i < MAX_CANDIDATES; i++) {
            lines.add((i + 1) + '. ' + caseLabel(pool[i]));
        }
        if (pool.size() > MAX_CANDIDATES) {
            lines.add('… 외 ' + (pool.size() - MAX_CANDIDATES) + '건');
        }
        r.message = String.join(lines, '\n');
        return r;
    }

    /** D1: 고객 차량이나 오로라 VOC가 연결된 연락처만(실습 연락처·공급사 담당자 제외) */
    static List<Contact> auroraOwners() {
        Set<Id> ids = new Set<Id>();
        for (Vehicle__c v : [SELECT Owner_Contact__c FROM Vehicle__c WHERE Owner_Contact__c != null]) {
            ids.add(v.Owner_Contact__c);
        }
        for (AggregateResult ar : [SELECT ContactId c FROM Case WHERE VOC_Status__c != null AND ContactId != null GROUP BY ContactId]) {
            ids.add((Id) ar.get('c'));
        }
        return [SELECT Id, Name FROM Contact WHERE Id IN :ids ORDER BY Name];
    }

    static String caseLabel(Case c) {
        return 'VOC ' + c.CaseNumber + ' · ' + c.Subject + ' (' + c.VOC_Status__c + ')';
    }

    static String vehicleLabel(Vehicle__c v) {
        return v.Name + (v.Vehicle_Model__r == null ? '' : ' · ' + v.Vehicle_Model__r.Name) + (v.Plate_Number__c == null ? '' : ' · ' + v.Plate_Number__c);
    }

    static Result found(Id id, String label) {
        Result r = new Result();
        r.status = FOUND;
        r.recordId = id;
        r.message = label + ' 기준으로 답합니다.';
        return r;
    }

    static Result notFound(String what) {
        Result r = new Result();
        r.status = NOT_FOUND;
        r.message = what + '을(를) 찾지 못했습니다. ' + EXAMPLES;
        return r;
    }
}