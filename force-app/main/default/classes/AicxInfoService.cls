/**
 * 오로라 AI 상담 v4.3 정보 조회 답변 — docs/design/v4.3-aicx-intents.md §5.
 * 숫자·날짜가 틀리면 안 되는 답이라 AI 없이 Apex가 데이터로 문장을 만든다(D2).
 * 본인 확인된 contactId·vehicleId의 데이터만 조회한다. 답할 데이터가 없으면 null → 상담사 연결.
 */
public with sharing class AicxInfoService {
    public static final String MAINTENANCE = 'I1';
    public static final String REPAIR = 'I2';
    public static final String WARRANTY = 'I3';
    public static final String VEHICLE = 'I4';
    public static final String CASES = 'I5';
    public static final Map<String, String> LABELS = new Map<String, String>{
        MAINTENANCE => '정기점검', REPAIR => '수리 진행', WARRANTY => '보증', VEHICLE => '차량 정보', CASES => '내 VOC 상태'
    };
    public static final String AI_INFO = 'AI 정보 안내';

    public class Answer {
        @AuraEnabled public String text;
        @AuraEnabled public String sources;
        public Answer(String text, String sources) { this.text = text; this.sources = sources; }
    }

    /** 의도 판별: 키워드가 가장 먼저 나온 의도 하나. 여러 개면 others에 개수를 남긴다. */
    public class Intent {
        @AuraEnabled public String code;
        @AuraEnabled public String label;
        @AuraEnabled public String keyword;
        @AuraEnabled public Integer others = 0;
    }

    public static Intent detect(String message, Aicx_Rule__mdt rule) {
        if (rule == null || String.isBlank(message)) {
            return null;
        }
        Map<String, String> csv = new Map<String, String>{
            MAINTENANCE => rule.Intent_Maintenance__c, REPAIR => rule.Intent_Repair_Status__c,
            WARRANTY => rule.Intent_Warranty__c, VEHICLE => rule.Intent_Vehicle_Info__c, CASES => rule.Intent_Case_Status__c
        };
        Intent best;
        Integer bestPos;
        Integer matched = 0;
        for (String code : new List<String>{ MAINTENANCE, REPAIR, WARRANTY, VEHICLE, CASES }) {
            Object[] hit = position(message, csv.get(code));
            if (hit == null) {
                continue;
            }
            matched++;
            if (best == null || (Integer) hit[0] < bestPos) {
                best = new Intent();
                best.code = code;
                best.label = LABELS.get(code);
                best.keyword = (String) hit[1];
                bestPos = (Integer) hit[0];
            }
        }
        if (best != null) {
            best.others = matched - 1;
        }
        return best;
    }

    /** 키워드 중 메시지에서 가장 앞에 나오는 것의 [위치, 키워드]. 공백을 뺀 비교도 함께 한다. */
    static Object[] position(String message, String csv) {
        if (String.isBlank(csv)) {
            return null;
        }
        String m = message.toLowerCase();
        String compact = m.deleteWhitespace();
        Object[] best;
        for (String raw : csv.split(',')) {
            String w = raw.trim().toLowerCase();
            if (String.isBlank(w)) {
                continue;
            }
            Integer p = m.indexOf(w);
            if (p < 0) {
                Integer q = compact.indexOf(w.deleteWhitespace());
                p = q < 0 ? -1 : q;
            }
            if (p >= 0 && (best == null || p < (Integer) best[0])) {
                best = new Object[]{ p, raw.trim() };
            }
        }
        return best;
    }

    public static Answer answer(String code, Id contactId, Id vehicleId) {
        if (code == MAINTENANCE) {
            return maintenance(vehicleId);
        } else if (code == REPAIR) {
            return repair(contactId, vehicleId);
        } else if (code == WARRANTY) {
            return warranty(vehicleId);
        } else if (code == VEHICLE) {
            return vehicleInfo(vehicleId);
        } else if (code == CASES) {
            return caseStatus(contactId);
        }
        return null;
    }

    // ===== I1 정기점검 =====
    static Answer maintenance(Id vehicleId) {
        Vehicle__c v = vehicle(vehicleId);
        if (v == null || v.Vehicle_Model__r == null || v.Vehicle_Model__r.Maintenance_Interval_Months__c == null
                || v.Vehicle_Model__r.Maintenance_Interval_Km__c == null) {
            return null;
        }
        List<Service_Visit__c> last = [SELECT Check_In_Date__c, Mileage__c FROM Service_Visit__c
                                       WHERE Vehicle__c = :vehicleId AND Visit_Type__c = '정기 점검' AND Check_In_Date__c != null
                                       ORDER BY Check_In_Date__c DESC LIMIT 1];
        Date base;
        Decimal baseKm;
        String first;
        if (!last.isEmpty()) {
            base = last[0].Check_In_Date__c;
            baseKm = last[0].Mileage__c == null ? 0 : last[0].Mileage__c;
            first = '마지막 정기 점검은 ' + String.valueOf(base) + '(' + km(baseKm) + 'km)입니다.';
        } else if (v.Delivery_Date__c != null) {
            base = v.Delivery_Date__c;
            baseKm = 0;
            first = '정기 점검 기록이 없어 출고일 ' + String.valueOf(base) + ' 기준으로 계산했습니다.';
        } else {
            return null;
        }
        Integer months = v.Vehicle_Model__r.Maintenance_Interval_Months__c.intValue();
        Decimal stepKm = v.Vehicle_Model__r.Maintenance_Interval_Km__c;
        Date dueDate = base.addMonths(months);
        Decimal dueKm = baseKm + stepKm;
        Decimal current = v.Mileage__c;
        String text = first + '\n' + v.Vehicle_Model__r.Model_Line__c + ' 모델은 ' + months + '개월 또는 ' + km(stepKm)
            + 'km 중 먼저 오는 때가 점검 시기라, ' + (last.isEmpty() ? '첫' : '다음') + ' 점검 시기는 '
            + String.valueOf(dueDate) + ' 또는 ' + km(dueKm) + 'km입니다'
            + (current == null ? '.' : '(현재 ' + km(current) + 'km).');
        Boolean overByKm = current != null && current >= dueKm;
        Boolean overByDate = Date.today() >= dueDate;
        if (overByKm || overByDate) {
            text += '\n→ ' + (overByKm ? '주행거리' : '기간') + ' 기준으로 이미 점검 시기가 지났어요. 서비스센터에 예약해 주세요.';
        } else {
            text += '\n→ 기간 기준으로 약 ' + Date.today().daysBetween(dueDate) + '일 남았습니다.';
        }
        // v5: 담당 서비스센터(Account)가 있으면 그 이름, 없으면 예전 선택 목록 값
        if (v.Preferred_Center__r != null) {
            text += '\n관리 서비스센터: ' + v.Preferred_Center__r.Name;
        } else if (String.isNotBlank(v.Service_Center__c)) {
            text += '\n관리 서비스센터: ' + v.Service_Center__c + ' 서비스센터';
        }
        text += '\n(점검 주기는 오로라 가상 기준입니다)';
        return new Answer(text, '정비 이력(정기 점검) · 차량 주행거리 · 모델 점검 주기');
    }

    // ===== I2 수리 진행 =====
    static Answer repair(Id contactId, Id vehicleId) {
        Vehicle__c v = vehicle(vehicleId);
        if (v == null) {
            return null;
        }
        List<String> lines = new List<String>();
        for (Service_Visit__c s : [SELECT Check_In_Date__c, Service_Center__c, Visit_Type__c, Symptom__c FROM Service_Visit__c
                                   WHERE Vehicle__c = :vehicleId AND Completed_Date__c = null AND Check_In_Date__c != null
                                   ORDER BY Check_In_Date__c DESC LIMIT 2]) {
            Integer days = s.Check_In_Date__c.daysBetween(Date.today());
            lines.add(String.valueOf(s.Check_In_Date__c) + ' ' + (s.Service_Center__c == null ? '' : s.Service_Center__c + ' 서비스센터에 ')
                + '\'' + s.Visit_Type__c + '\'' + ro(s.Visit_Type__c) + ' 입고되어 ' + (days <= 0 ? '오늘 입고된 상태' : days + '일째 정비 중') + '입니다'
                + (String.isBlank(s.Symptom__c) ? '.' : '(증상: ' + s.Symptom__c.left(40) + ').'));
        }
        if (lines.isEmpty()) {
            lines.add('지금 오로라 서비스센터에 입고되어 정비 중인 기록은 없습니다.');
        }
        List<Case> open = openCases(contactId, 1);
        if (!open.isEmpty()) {
            Case c = open[0];
            lines.add('관련 문의(VOC ' + c.CaseNumber + ') 상태는 \'' + c.VOC_Status__c + '\''
                + (c.Advisor__r == null ? '입니다.' : '이고, 담당은 ' + c.Advisor__r.Name + ' 상담원입니다.'));
        }
        return new Answer(String.join(lines, '\n'), '정비 이력(완료일 없는 입고) · 진행 중 VOC');
    }

    // ===== I3 보증 =====
    static Answer warranty(Id vehicleId) {
        Vehicle__c v = vehicle(vehicleId);
        if (v == null) {
            return null;
        }
        List<Vehicle_Warranty__c> ws = [SELECT Warranty_Type__c, Status__c, End_Date__c, Mileage_Limit_Km__c
                                        FROM Vehicle_Warranty__c WHERE Vehicle__c = :vehicleId ORDER BY End_Date__c DESC];
        if (ws.isEmpty()) {
            return null;
        }
        List<String> valid = new List<String>();
        List<String> ended = new List<String>();
        for (Vehicle_Warranty__c w : ws) {
            if (w.Status__c == '유효') {
                String left = w.Mileage_Limit_Km__c == null || v.Mileage__c == null ? ''
                    : ', 남은 ' + km(w.Mileage_Limit_Km__c - v.Mileage__c) + 'km';
                valid.add(w.Warranty_Type__c + '(' + String.valueOf(w.End_Date__c) + '까지' + left + ')');
            } else {
                ended.add(w.Warranty_Type__c + ' 보증은 ' + (w.Status__c == '주행거리 초과'
                    ? '주행거리 한도(' + km(w.Mileage_Limit_Km__c) + 'km)를 넘었습니다'
                    : String.valueOf(w.End_Date__c) + '에 끝났습니다'));
            }
        }
        String text = valid.isEmpty() ? '지금 유효한 보증은 없습니다.' : '유효한 보증 ' + valid.size() + '건: ' + String.join(valid, ', ') + '.';
        if (!ended.isEmpty()) {
            text += '\n' + String.join(ended, '. ') + '.';
        }
        text += '\n보증 수리 여부는 증상 확인 후 서비스센터에서 최종 판단합니다.';
        return new Answer(text, '차량 보증(종류·만료일·주행거리 한도) · 차량 주행거리');
    }

    // ===== I4 차량 정보 =====
    static Answer vehicleInfo(Id vehicleId) {
        Vehicle__c v = vehicle(vehicleId);
        if (v == null) {
            return null;
        }
        String text = v.Name + ' ' + (v.Vehicle_Model__r == null ? v.Model__c : v.Vehicle_Model__r.Name)
            + (String.isBlank(v.Model_Year__c) ? '' : '(' + v.Model_Year__c + '년식)')
            + (v.Delivery_Date__c == null ? '' : ', ' + String.valueOf(v.Delivery_Date__c) + ' 출고')
            + (v.Mileage__c == null ? '' : ', 현재 ' + km(v.Mileage__c) + 'km')
            + (v.Vehicle_Model__r == null || v.Vehicle_Model__r.Battery_Capacity_kWh__c == null ? ''
                : ', 배터리 ' + v.Vehicle_Model__r.Battery_Capacity_kWh__c + 'kWh') + '입니다.';
        return new Answer(text, '고객 차량 · 차량 모델');
    }

    // ===== I5 내 VOC 상태 =====
    static Answer caseStatus(Id contactId) {
        List<Case> open = openCases(contactId, 3);
        if (open.isEmpty()) {
            return new Answer('지금 진행 중인 문의는 없습니다.', '진행 중 VOC');
        }
        List<String> lines = new List<String>{ '진행 중인 문의 ' + open.size() + '건:' };
        for (Case c : open) {
            lines.add('- ' + c.CaseNumber + ' ' + c.Subject.removeStart('[AI 상담] ').left(30) + ' — ' + c.VOC_Status__c
                + (c.Advisor__r == null ? '' : ', 담당 ' + c.Advisor__r.Name)
                + (String.isBlank(c.Response_Due_KST__c) ? '' : ', 응답 기한 ' + c.Response_Due_KST__c));
        }
        return new Answer(String.join(lines, '\n'), '진행 중 VOC(번호·상태·담당·응답 기한)');
    }

    static List<Case> openCases(Id contactId, Integer n) {
        return [SELECT CaseNumber, Subject, VOC_Status__c, Advisor__r.Name, Response_Due_KST__c FROM Case
                WHERE ContactId = :contactId AND VOC_Status__c != null AND VOC_Status__c != '종결' AND AI_Outcome__c != :AI_INFO
                ORDER BY CreatedDate DESC LIMIT :n];
    }

    static Vehicle__c vehicle(Id vehicleId) {
        if (vehicleId == null) {
            return null;
        }
        List<Vehicle__c> vs = [SELECT Name, Model__c, Model_Year__c, Delivery_Date__c, Mileage__c, Service_Center__c, Preferred_Center__r.Name,
                                      Vehicle_Model__r.Name, Vehicle_Model__r.Model_Line__c, Vehicle_Model__r.Battery_Capacity_kWh__c,
                                      Vehicle_Model__r.Maintenance_Interval_Months__c, Vehicle_Model__r.Maintenance_Interval_Km__c
                               FROM Vehicle__c WHERE Id = :vehicleId];
        return vs.isEmpty() ? null : vs[0];
    }

    /** 조사 '로/으로': 받침 없음·ㄹ 받침이면 '로' ('하자 수리'로, '정기 점검'으로) */
    @TestVisible
    static String ro(String word) {
        if (String.isBlank(word)) {
            return '로';
        }
        Integer ch = word.trim().right(1).codePointAt(0);
        if (ch < 44032 || ch > 55203) {
            return '로';
        }
        Integer jong = Math.mod(ch - 44032, 28);
        return jong == 0 || jong == 8 ? '로' : '으로';
    }

    /** 1234567 → '1,234,567' (사용자 로캘과 무관하게) */
    @TestVisible
    public static String km(Decimal n) {
        if (n == null) {
            return '';
        }
        String s = String.valueOf(n.setScale(0).abs());
        String out = '';
        while (s.length() > 3) {
            out = ',' + s.right(3) + out;
            s = s.left(s.length() - 3);
        }
        return (n < 0 ? '-' : '') + s + out;
    }
}
