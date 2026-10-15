/**
 * v4.5 차량 계통(배터리·구동·제동·공조·전장·차체) 키워드 공용 목록. 한곳에서만 고친다.
 * - BASE: 계통을 확정할 때 쓰는 정확한 말(리콜 조기 경보의 계통 추정)
 * - EXTRA: 비슷한 사례를 넓게 찾을 때만 더하는 말(RAG 검색). 정확도보다 재현율이 중요할 때
 * 순서가 의미 있다: 여러 계통 말이 섞이면 앞의 계통이 먼저 걸린다(제동 → 배터리 → …).
 */
public with sharing class AuroraSystemKeywords {
    public static final List<String> ORDER = new List<String>{ '제동', '배터리', '구동', '공조', '전장', '차체' };

    public static final Map<String, List<String>> BASE = new Map<String, List<String>>{
        '제동' => new List<String>{ '브레이크', '제동', 'ABS', '부스터' },
        '배터리' => new List<String>{ '배터리', '충전', '고전압' },
        '구동' => new List<String>{ '모터', '감속기', '구동', '출력 저하', '하이브리드' },
        '공조' => new List<String>{ '에어컨', '공조', '히트펌프', '히터' },
        '전장' => new List<String>{ '카메라', '계기판', '전장', '텔레매틱스', '소프트웨어' },
        '차체' => new List<String>{ '도어', '차체', '풍절음', '누수', '필러' }
    };

    public static final Map<String, List<String>> EXTRA = new Map<String, List<String>>{
        '배터리' => new List<String>{ 'OBC' },
        '구동' => new List<String>{ '출력' },
        '공조' => new List<String>{ '냄새' },
        '전장' => new List<String>{ '원격', '앱' }
    };

    /** 정확한 말(BASE)로 첫 번째로 걸리는 계통. 없으면 null — 리콜 경보용 */
    public static String firstSystem(String text) {
        for (String sys : ORDER) {
            if (matches(text, BASE.get(sys))) {
                return sys;
            }
        }
        return null;
    }

    /** 걸리는 계통 전부. broad면 EXTRA까지 — RAG 검색용 */
    public static Set<String> systemsOf(String text, Boolean broad) {
        Set<String> out = new Set<String>();
        for (String sys : ORDER) {
            if (matches(text, BASE.get(sys)) || (broad && EXTRA.containsKey(sys) && matches(text, EXTRA.get(sys)))) {
                out.add(sys);
            }
        }
        return out;
    }

    static Boolean matches(String text, List<String> words) {
        if (String.isBlank(text)) {
            return false;
        }
        for (String w : words) {
            if (text.containsIgnoreCase(w)) {
                return true;
            }
        }
        return false;
    }
}
