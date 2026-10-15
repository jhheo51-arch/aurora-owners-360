/**
 * v4.5 상담 직원 조회 공용 클래스. 코드에 직원 이름을 쓰지 않고 역할(Care_Staff__c.Role__c)로 담당자를 찾는다.
 * 같은 역할이 여러 명이면 직원 코드(Staff_Number__c)가 가장 앞선 재직자. 실제 회사라면 여기서 근무표·부재를 반영하면 된다.
 */
public with sharing class AuroraStaffDirectory {
    public static final String CENTER_HEAD = '고객케어센터장';
    public static final String TEAM_LEAD = '상담팀장';
    public static final String ADVISOR = '상담원';
    public static final String EV_TECH = 'EV 기술 상담';
    public static final String COMPENSATION = '보상 심사';
    public static final String QUALITY = '품질·안전 대응';
    public static final String SERVICE_CENTER = '서비스센터 협력';

    static Map<String, Care_Staff__c> cache;

    /** 역할별 대표 담당자(재직, 직원 코드 순 첫 번째). 없으면 null */
    public static Care_Staff__c firstByRole(String role) {
        if (cache == null) {
            cache = new Map<String, Care_Staff__c>();
            for (Care_Staff__c s : [SELECT Id, Name, Role__c, Staff_Number__c, Manager__c FROM Care_Staff__c
                                    WHERE Active__c = true ORDER BY Staff_Number__c NULLS LAST, Name]) {
                if (s.Role__c != null && !cache.containsKey(s.Role__c)) {
                    cache.put(s.Role__c, s);
                }
            }
        }
        return cache.get(role);
    }

    /** 문구용: '품질·안전 대응 홍길동'처럼 역할 + 이름, 담당자가 없으면 역할만 */
    public static String label(String role) {
        Care_Staff__c s = firstByRole(role);
        return s == null ? role : role + ' ' + s.Name;
    }

    @TestVisible
    static void resetCache() {
        cache = null;
    }
}
