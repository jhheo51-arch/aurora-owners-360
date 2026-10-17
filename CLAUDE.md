# 오로라 오너스 360 — 작업 컨텍스트 (Claude Code용)

오로라모터스(가상 전기차 OEM) 고객센터의 차주 VOC 처리 앱에서 출발해 고객 생애주기 CRM으로 넓힌 Salesforce 프로젝트입니다. 앱 API 이름 `Aurora_Owners_360`.
기준 문서는 [docs/PRD.md](docs/PRD.md)(설계 결정 Q1~Q76, 버전별 수용 테스트), 버전별 설계는 [docs/design/](docs/design/), 설치 순서는 [README.md](README.md) §6입니다.

> **이 저장소는 공개 저장소이자 유일한 작업 저장소입니다.** org 주소·사용자 이름·이메일·로그인 정보·토큰·레코드 ID·로컬 경로·발표 자료를 커밋하지 않습니다.

## 환경
- Salesforce **Developer Edition** org 1개. CLI 별칭은 개발 org `sesac`(스크립트 기본값), README 설치 예시는 `aurora`.
- 다른 PC에서 같은 org로 이어서 작업: `sf org login web --alias sesac` → `sf config set target-org sesac`. 새 org에 처음부터 만들기: README §6.
- 필요 도구: Salesforce CLI(`sf`), Python 3, git.
- Windows: `sf … --json`은 Git Bash에서 빈 출력이 나므로 PowerShell로. 한글이 든 Python은 `python -X utf8 script.py`(stdin heredoc 금지, 스크래치 스크립트 이름은 매번 새로).
- 같은 org에 다른 실습 앱·데이터(`Employee__c`, 실습 연락처, 실습 Agent 등)가 있습니다. **오로라 작업에서는 쓰지도 바꾸지도 않습니다.**

## 작업 규칙
- 답변은 한국어. 코드·API 이름은 원문.
- Developer Edition 기능만 사용. 저장소만으로 다른 Developer Edition org에 재현 가능해야 함(새 Apex 클래스·구성 요소는 `manifest/package.xml`에 직접 추가).
- 배포 전: 참고 파일 구조 확인 → 배포 계획 → 배포 후 고려사항을 먼저 보여 주기.
- 레코드 삭제·org 전역 설정 변경·사용자 레코드 수정은 먼저 확인받기. 자동 권한 검사가 막은 작업을 브라우저로 우회하지 않기.
- **Step마다 결과 보고 후 멈추고 사용자 확인 뒤 다음 Step**(PRD Q19). AI 호출은 최소로.
- 요청한 대상만 바꾸고, 범위가 애매하면 확인. 발표·포트폴리오 자료는 요청이 있을 때만.
- 오로라 직원은 `Care_Staff__c` 10명(추가 시 이름을 사용자에게 질문). 실제 자동차 브랜드 사용 금지, 색만으로 정보 전달 금지.
- git push는 사용자가 요청할 때만. 기존 태그는 옮기지 않음. 커밋 메시지 끝에 `Co-Authored-By` 줄.
- 새 오브젝트: AutoNumber `startingNumber` 명시, "All" 리스트 뷰, 탭, 오로라 앱 탭 추가, 권한은 `scripts/build-permissions.py`에 필드 추가 후 재생성, 레이아웃 필드 배치.
- 배포 후 org 조회(SOQL/describe/Tooling)로 검증하고, 화면은 오로라 앱 안에서 확인. 단계 끝에는 RunLocalTests 검증.

## 버전 요약
| 버전 | 핵심 |
|---|---|
| v1 | `Vehicle__c`(VEH-)·`Compensation__c`(CMP-)·`Care_Staff__c`, Case 커스텀 필드, Flow `VOC_Case_Before_Save`, Path, 레코드 페이지, 권한 세트 `Aurora_Owners_360_User`, 샘플 `scripts/build-data.py` |
| v2 | 홈 `Aurora_Home`, Screen Flow `Compensation_Approval`·`Aurora_Quick_VOC_Intake`, 보상 2단계 승인, 리포트(`scripts/build-reports.py`) |
| v3 | `Vehicle_Model__c`·`Vehicle_Party__c`·`Vehicle_Warranty__c`·`Service_Visit__c`·`Part__c`·`Failure_Mode__c`·`Case_Part__c`, `Lemon_Law_Rule__mdt`, Apex 서비스·트리거, LWC 타임라인·유사 사례 |
| v3.5 | 브랜드·가독성, LWC 카드들, three.js 3D(정적 리소스 `three147`) |
| v4 | Agent `Aurora_Care_Copilot`(Agent Script), Prompt Template 3, 리콜 경보 `Recall_Alert__c` |
| v4.1·4.3 | 고객용 AI 상담 `Aurora_AI_Care_Demo`(`Aicx*` Apex, `Aicx_Rule__mdt`), 정보 조회는 Apex 문장(AI 0회) |
| v4.2·4.4 | Agent 대상 찾기·업무 조회, 공급사, 차주·차량 보드, 알림, RAG |
| v4.5 | 공개 준비(가상 이름, 역할 조회 `AuroraStaffDirectory`) |
| v5 | 서비스센터·딜러, `Recall_Campaign__c`·`Recall_Vehicle__c`, `Finance_Contract__c`, 재구매 상담(표준 Opportunity `Aurora_Type__c`), 고객 건강 점수·CSAT. 샘플 적재 후 `scripts/apex/v5-init.apex` |

## 꼭 기억할 함정
1. AutoNumber는 `startingNumber` 생략 시 0부터. 커스텀 오브젝트는 `<nameField>` 안에 둔다. 메타데이터로 카운터를 낮출 수 없음. 롤백해도 번호는 소모됨.
2. 메타데이터로 만든 오브젝트에는 "All" 리스트 뷰·레이아웃 필드가 자동 생성되지 않음.
3. 리스트 뷰의 Lookup 필터는 Name으로 비교 → ID 필터는 `CASESAFEID()` 수식 필드로.
4. Dynamic Forms 필드 섹션은 최대 2열, 같은 필드는 페이지에 한 번만.
5. Published Prompt Template 버전은 수정 불가 → 새 버전 + `activeVersionIdentifier`. 새로 배포 시 `versionIdentifier`(첫 버전 `…=_1`) 필요. 날짜 병합값은 UTC.
6. Lightning은 라벨·페이지를 캐시함 → Ctrl+Shift+R, 안 되면 해당 org 탭의 IndexedDB 삭제 후 새로고침. App Builder에는 최신본이 보임.
7. 익명 Apex는 줄바꿈 많은 긴 한글 리터럴에서 컴파일 실패 → CSV `sf data upsert bulk`(external id) 사용. `--line-ending LF` 필요, CSV는 BOM 없이(PowerShell `Set-Content -Encoding utf8`은 BOM을 붙임).
8. Agent는 `aiAuthoringBundles/*.agent` 원본 → `sf agent validate/publish authoring-bundle` → `sf agent activate`. 게시 시 내려받는 `aiAgents` 등은 `.forceignore`, 다시 내려받힌 Prompt Template는 `git checkout`으로 원복. 권한 세트 `agentAccesses`는 Agent 게시 후 배포. Agent Script 큰따옴표 문자열 안에 큰따옴표 금지.
9. 수식 필드에 `defaultValue`·`<length>` 넣으면 배포 실패. 배포는 전부 아니면 전무.
10. 메타데이터로 만든 필드는 FLS가 없으면 describe에 안 보임 → Tooling `CustomField`로 확인. 권한 배포 전엔 Apex DML도 '필드 접근 불가'.
11. FlexiPage를 상위 페이지 없이 만들면 영역에 `<mode>` 금지. 커스텀 관계 이름은 `__r`. 앱 전용 할당은 `CustomApplication.actionOverrides`. identifier는 영숫자·밑줄만.
12. Flow가 참조하는 필드는 삭제 불가 → 비활성화 후 Tooling으로 Flow 버전 삭제. 같은 이름 재생성은 `--purge-on-delete`.
13. 이 org의 클래식 레이아웃 편집기는 오류가 남 → 레이아웃은 메타데이터로 수정. Case·Contact 레이아웃은 org 공용이라 오로라 페이지는 LWC `auroraRelatedList`.
14. CreatedDate는 API로 지정 불가 → 시간 상황은 기한·첫 응답 필드로 재현.
15. Screen Flow 화면은 `allowBack`·`allowFinish`를 둘 다 false로 못 함. 롤업 필터는 AND만.
16. 앱 탐색 개인 설정이 켜져 있으면 앱 탭을 바꿔도 사용자 화면은 그대로 → 연필 → '원래대로 재설정'.
17. Account 레코드 유형은 같은 org 다른 앱 생성 화면에도 선택 창을 띄움 → 선택 목록 필드(`Customer_Segment__c`)로.
18. 앱 로고는 `<brand>` 안 `<logo>`(ContentAsset)+`<logoVersion>`. 탭 `<motif>`는 번호만 의미 있음.
19. LWC 클래스명이 전역 CSS와 겹치면 깨짐 → 접두어. three.js는 `loadScript`로 동작.
20. Agentforce 라우터가 사람 연결 요청을 `Inappropriate_Content`로 분류할 수 있음 → 트레이스는 `sf agent preview`의 tracesPath. 패널 Agent 선택기는 생성일 순, 페이지 이동마다 기본 Agent로 돌아갈 수 있음.
21. Apex에서 Prompt Template 호출은 `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`, 테스트에서는 `Test.isRunningTest()`로 대체.
22. Apex 수정은 Edit/Write 도구로(heredoc Python이 `'\n'`을 줄바꿈으로 바꿔 컴파일 오류). PowerShell에서 `R`은 `Invoke-History` 별칭.
23. 예약 Flow는 매일·매주만, 시간 기반 알림은 기록 트리거 Flow 예약 경로(시스템 사용자로 실행 → 수신자는 레코드 소유자). 수식 날짜 필드는 예약 경로 기준 불가 → 매일 예약 Flow가 Apex 점검 호출. `startTime`은 org 시간대로 해석.
24. VOC·정비 저장마다 위험·건강 점수가 재계산됨 → 이 경로에 쿼리를 더하면 SOQL 101. 쿼리는 합치고 테스트는 한 번에 저장.
25. Master-Detail 자식 `update`에 부모 필드까지 보내면 '필드 접근 불가' → `new X(Id = ..., 바꿀 필드만)`. Apex에서 null == null은 true.
26. 사용자 레코드 수정·Dev Hub 활성화는 자동 권한 검사에서 막힘 → 사용자가 설정 화면에서 직접.
27. 브라우저 확인은 Claude in Chrome(사용자 로그인 세션). 페이지가 멈추면 새 탭을 열었다 닫기, 내용 확인은 `get_page_text`가 스크린샷보다 안정적.
