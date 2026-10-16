# v5 설계 — 리텐션·재구매 (서비스 네트워크·리콜 캠페인·금융 만기·재구매 상담·고객 건강 점수)

> 상태: **구현 완료 `v5.0` (2026-10-16)**, 결과·수용 테스트는 PRD §24 — 스무고개 Q65~Q76은 사용자 위임으로 **추천안 그대로 확정**("추천하는 걸로 작성하고 바로 다음 진행").
> 진행: **S-1 완료**(서비스센터 4·딜러 3, 차량 9·정비 14 Lookup 이전, 혼잡도 카드 `auroraCenterLoad`·`AuroraNetworkController`, AI 상담 점검 안내는 담당 서비스센터 이름 사용, `scripts/build-network.py`·`data/v5/`) / **S-2 완료**(`Recall_Campaign__c`·`Recall_Vehicle__c`, [대상 차량 생성] LWC 빠른 작업 + `RecallCampaignService`, 상태 날짜 자동 기록·정비 완료 → 조치 완료, 차량 배지 '리콜 미조치', 경보 화면에 캠페인 관련 목록, RC-0001 노스라이트 2023 출고 → 대상 2대, `scripts/build-recall-campaign.py`) / **S-3 완료**(`Finance_Contract__c` FC- 6건: 만기 90일 이내 2·만기 1, 만기까지 일수·만기 단계 수식, 리스트 뷰 '만기 90일 이내', 고객은 차량 차주로 자동 채움 `FinanceContractService`, `scripts/build-finance.py`) / **S-4 완료**(Opportunity 필드 6·`Aurora_Type__c`='재구매 상담', `RepurchaseService`(차량당 열린 상담 1건, 실행 시 0~90일 재확인), Flow `Aurora_Finance_Maturity_Repurchase`(만기 90일 전 예약 경로)·`Aurora_Warranty_Expiry_Repurchase`(매일 전체 점검 — 차량 일반 보증 만료일이 수식이라 예약 경로 기준 불가), 리스트 뷰 '오로라 재구매 상담'·오로라 전용 페이지 `Aurora_Repurchase_Record_Page`·앱 탭 기회, 초기 적재 `RepurchaseService.scan()` → 3건(FC-0001·FC-0002 금융 만기, VEH-0009 보증 만료), `scripts/build-repurchase.py`) / **S-5 완료**(Contact `Health_Score__c`·`Health_Grade__c`·`Health_Basis__c`, `CustomerHealthService`(위험 점수 계산과 같은 저장에서 채움, 리콜 대상 차량 상태 변경 시도 재계산), 기준 `Health_Rule__mdt` KR_Default, CSAT 1~5 유효성 `Aurora_CSAT_Range`, VOC 화면 '④ 종결 만족도'·Path 종결 안내, 샘플 CSAT VOC-A 5·VOC-E 4·VOC-D 2(`data/v5/case-csat.csv`) → 차주 8명: 좋음 3·보통 2·주의 3, `scripts/build-health.py`) / **S-6 완료**(차주·차량 보드: 건강 칩·차량 배지 🔧 리콜 미조치·💳 금융 만기 D-n·🤝 재구매 상담, 필터 건강 주의·리콜 미조치·금융 만기 / 차주 360: 건강 점수 칸·근거·리텐션 배지 / 타임라인: 리콜·금융(시작·만기)·재구매 상담 사건과 배지 / 홈 카드 '오로라 재구매 상담'·'오로라 건강 주의 차주'(Contact 리스트 뷰 `Aurora_Health_Watch`) / 업무 조회 `RECALL_OPEN`·`MATURING` + Agent v17, `RetentionScreensTest`, `scripts/build-retention-screens.py`).
> 원칙: Developer Edition만, 저장소만으로 재현, 실습 앱·실습 데이터 무변경, Step마다 결과 보고 후 멈춤(PRD Q19), 레코드 삭제·org 전역 설정 변경은 먼저 확인.

## 0. 왜 v5인가
v1~v4는 **문제가 생긴 고객**(VOC)을 잘 처리하는 데 집중했다. v5는 생애주기의 다음 칸, **"이 고객이 다시 오로라를 살까?"** 를 다룬다.

```
구매·출고 ──▶ 보유·정비 ──▶ 문제·VOC ──▶ 보상·해결 ──▶ [재구매·추천]
  v5 딜러       v5 서비스센터·리콜 캠페인                  v5 금융 만기 → 재구매 상담, 고객 건강 점수
```

| 질문 | 지금 답할 수 없는 이유 | v5 |
|---|---|---|
| 이 차는 어느 서비스센터에 가나? 그 센터는 붐비나? | 서비스센터가 선택 목록(텍스트) | 서비스센터·딜러를 **Account**로, 센터별 하루 용량·진행 중 정비 |
| 리콜 경보가 났다. 해당 차량 몇 대에 알렸고 몇 대 고쳤나? | 경보(`Recall_Alert__c`)는 VOC 묶음일 뿐 차량 단위 조치가 없음 | **리콜 캠페인**(`Recall_Campaign__c`) + **대상 차량**(`Recall_Vehicle__c`) |
| 할부·리스가 끝나는 고객은 누구? | 금융 계약 데이터 없음 | **금융·리스 계약**(`Finance_Contract__c`), 만기 90일 전 재구매 상담 자동 생성 |
| 재구매 상담은 어디서 관리? | 없음 | 표준 **Opportunity**(영업 기회) 재사용 |
| 이 고객은 건강한가(남을 것인가)? | 위험 점수(불만 신호)만 있음 | **고객 건강 점수** = 위험 + 만족도(CSAT) + 리콜 미조치 + 보증·만기 상태 |

## 1. 스무고개 (추천안으로 확정)
| Q | 질문 | 추천(확정) | 이유 |
|---|---|---|---|
| Q65 | v5 범위 | **서비스 네트워크 · 리콜 캠페인 · 금융 만기 → 재구매 상담 · 고객 건강 점수·CSAT**. 시승 리드(Lead, 보류 주제 A)는 **v5.1**로 미룸 | 기존 차주 리텐션이 한 줄로 이어짐. 신규 고객 획득(시승)은 별도 흐름이라 분리 |
| Q66 | 서비스센터·딜러 표현 | **Account + `Customer_Segment__c` 값 '서비스센터'·'딜러' 추가**(레코드 유형 안 씀) | 함정 21(레코드 유형이 실습 앱 생성 화면에 뜸). v4.4 공급사와 같은 방식 |
| Q67 | 네트워크 규모·이름 | 서비스센터 **4곳**(기존 선택 목록 값과 같은 지역: 서울 강남·서울 성수·경기 판교·부산 해운대) + 딜러 **3곳**(강남·판교·해운대 전시장). 이름은 "오로라 ○○ 서비스센터/전시장" | 기존 차량·정비 값과 1:1로 옮길 수 있음. 가상 브랜드 이름 |
| Q68 | 기존 서비스센터 선택 목록 | **선택 목록은 남기고 Lookup 추가 + 값 이전**(`Vehicle__c.Preferred_Center__c`, `Service_Visit__c.Service_Center_Account__c`). 화면은 Lookup으로 교체 | Flow·리포트·Apex가 선택 목록을 참조할 수 있어 삭제는 위험(함정 12). v1 `Under_Warranty__c`와 같은 처리 |
| Q69 | 서비스센터 용량 | Account `Daily_Capacity__c`(하루 입고 가능 대수) + 화면에서 **진행 중 정비(입고~완료 전) 수 / 용량 = 혼잡도** 계산(Apex, 저장 안 함) | 예약 시스템 없이도 "어디가 붐비나"를 보여 줌 |
| Q70 | 리콜 캠페인 구조 | `Recall_Campaign__c`(RC-) + `Recall_Vehicle__c`(RV-, 캠페인 M-D, 차량 Lookup). 대상 조건 = **모델 계열 + 출고일 범위**. [대상 차량 생성] 버튼(Apex) | Automotive Cloud의 차량 단위 리콜과 같은 구조. 조건이 단순해야 설명 가능 |
| Q71 | 리콜 경보 → 캠페인 | 캠페인에 `Source_Alert__c`(경보 Lookup). 경보 화면에서 캠페인으로 이어 만들 수 있게 | v4 조기 경보 → v5 시정 조치로 이야기가 이어짐 |
| Q72 | 대상 차량 상태 | 미통지 → 통지 → 입고 예약 → 조치 완료 (+ 제외: 폐차·수출 등). 조치 완료는 정비 이력(`Service_Visit__c`, 방문 유형 '리콜') 연결 | 실제 리콜 이행률 관리 방식 |
| Q73 | 금융·리스 계약 | `Finance_Contract__c`(FC-): 차량·고객·유형(할부/리스/장기렌트)·시작일·만기일·월 납입금·잔존가치·상태. 샘플 **6건**(만기 90일 이내 2건 포함) | 만기 = 재구매의 가장 강한 신호 |
| Q74 | 재구매 상담 | **표준 Opportunity 재사용** + 필드(`Aurora_Type__c`='재구매 상담', 고객 Contact·차량·계약·추천 모델·계기). 단계는 org 표준 값(Prospecting → … → Closed Won/Lost) 그대로, 오로라 앱 전용 레코드 페이지·리스트 뷰 | 포트폴리오에서 표준 영업 기회 활용을 보여 줌. org 공용 단계·레이아웃은 바꾸지 않음(같은 org의 다른 데이터 보호) |
| Q75 | 재구매 상담 자동 생성 | **만기 90일 전**(금융 계약 기록 트리거 Flow 예약 경로 → Apex) + **보증 만료 90일 전**(차량). 차량당 열린 상담 1건만(중복 방지). 이미 90일 이내인 샘플은 적재 시 바로 생성 | 함정 34(예약 Flow는 매시간 없음 → 날짜 기준 예약 경로) |
| Q76 | 고객 건강 점수·CSAT | Contact `Health_Score__c`(0~100)·`Health_Grade__c`(좋음/보통/주의). 100에서 감점: 위험 점수×0.4, 최근 CSAT 낮음(1~2점) −15, 리콜 미조치 −10, 레몬법 주의 이상 −10, 진행 중 VOC당 −5. CSAT는 **VOC 종결 시 상담원이 통화로 받은 점수(1~5) 입력**(선택, 기존 `CSAT__c` 재사용). 기준값은 커스텀 메타데이터 `Health_Rule__mdt` | 위험 점수(불만)와 다른 "남을 가능성"을 한 숫자로. 기준은 배포 없이 조정 |

## 2. 데이터 구조
| 오브젝트 | 핵심 필드 | 관계·자동화 |
|---|---|---|
| Account(재사용) | `Customer_Segment__c` +'서비스센터'·'딜러', `Region__c`(지역), `Daily_Capacity__c`(숫자), `Aurora_Key__c`(기존 외부 ID) | 서비스센터 4·딜러 3 |
| `Vehicle__c` | `Preferred_Center__c`(→ Account 서비스센터), `Selling_Dealer__c`(→ Account 딜러) | 기존 선택 목록 값 이전 |
| `Service_Visit__c` | `Service_Center_Account__c`(→ Account), `Recall_Vehicle__c`(→ 리콜 대상 차량, 리콜 조치 기록) | 방문 유형에 '리콜' 값 추가 |
| `Recall_Campaign__c` (RC-) | 캠페인명, 모델 계열, 계통, 출고일 시작·끝, 조치 내용, 상태(계획/진행/완료), `Source_Alert__c`, 롤업: 대상·통지·조치 완료 수, 이행률 수식 | [대상 차량 생성] |
| `Recall_Vehicle__c` (RV-) | 캠페인(M-D), 차량, 상태, 통지일, 예약일, 조치일, 서비스센터 | 차량·차주 화면에 '리콜 미조치' 배지 |
| `Finance_Contract__c` (FC-) | 차량, 고객(Contact), 유형, 시작일, 만기일, 월 납입금, 잔존가치, 상태(진행/만기/중도 해지), 만기까지 일수(수식) | 만기 90일 전 재구매 상담 |
| Opportunity(재사용) | `Aurora_Type__c`, `Customer_Contact__c`, `Vehicle__c`, `Finance_Contract__c`, `Recommended_Model__c`(→ `Vehicle_Model__c`), `Trigger_Reason__c`(금융 만기/보증 만료/고객 요청) | 오로라 전용 리스트 뷰·레코드 페이지 |
| Contact(재사용) | `Health_Score__c`, `Health_Grade__c`, `Health_Basis__c`(근거 문장) | Apex가 저장(위험 점수와 같은 방식) |
| `Health_Rule__mdt` | 감점 기준값 | KR_Default |

## 3. 구현 Step (S, Step마다 보고 후 멈춤)
| Step | 내용 | 확인 |
|---|---|---|
| S-1 | **서비스 네트워크**: Account 값·필드, 서비스센터 4·딜러 3 데이터, 차량·정비 Lookup + 값 이전, 서비스센터 혼잡도 Apex·LWC 카드(차량 화면) | org 조회: Account 7, 차량 9대·정비 14건 Lookup 채움 |
| S-2 | **리콜 캠페인**: 오브젝트 2·탭·리스트 뷰·레이아웃, `RecallCampaignService`(대상 생성·상태 집계), 버튼, 차량 배지, 샘플 캠페인 1건 | 대상 차량 생성 → 모델·출고일 조건과 일치 |
| S-3 | **금융·리스 계약**: 오브젝트·탭, 샘플 6건 | org 조회 |
| S-4 | **재구매 상담**: Opportunity 필드·리스트 뷰·오로라 전용 페이지, `RepurchaseService` + 금융 만기·보증 만료 예약 경로 Flow | 만기 90일 이내 2건 + 보증 만료 임박 차량 → 상담 자동 생성, 중복 없음 |
| S-5 | **고객 건강 점수·CSAT**: `CustomerHealthService`·`Health_Rule__mdt`, 종결 단계 CSAT 입력 안내 | 차주 8명 점수·근거 |
| S-6 | **화면 연결**: 차주·차량 보드(건강 점수·리콜·만기 칩), 타임라인(리콜·금융·상담), 홈 카드, Agent 업무 조회('리콜 미조치'·'만기 임박') | Chrome 확인 |
| S-7 | 마무리: 수용 테스트, 검증 배포(RunLocalTests), PRD §24·§12·§13, CLAUDE.md, README, 커밋·태그 `v5.0` | |

## 4. 범위 밖
- 시승 리드(Lead) → v5.1. 실제 고객 통지 발송(문자·메일) → 통지일 기록만.
- org 공용 Opportunity 단계·페이지 레이아웃·Path 변경 → 하지 않음.
- 공개 저장소 반영 → 사용자 요청 시(같은 정리 규칙).

## 5. 예상 AI 호출
없음(S-6 Agent 업무 조회 확인 1~2회).
