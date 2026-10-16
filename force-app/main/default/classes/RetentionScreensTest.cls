/** v5 S-6 화면 연결: 타임라인(리콜·금융·재구매 상담), 차주 360 건강 점수·배지, 업무 조회 RECALL_OPEN·MATURING */
@IsTest
private class RetentionScreensTest {
    @TestSetup
    static void setup() {
        Contact owner = new Contact(LastName = '테스트리텐션차주', Email = 'retention@aurora.example.com');
        insert owner;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTRS0000000001', Model__c = '노스라이트', Owner_Contact__c = owner.Id,
                                      Delivery_Date__c = Date.today().addYears(-2));
        insert v;
        insert new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '리스', Status__c = '진행', Monthly_Payment__c = 500000,
                                       Start_Date__c = Date.today().addYears(-2), End_Date__c = Date.today().addDays(30));
        Recall_Campaign__c rc = new Recall_Campaign__c(Campaign_Key__c = 'T-RS1', Title__c = '테스트 리콜', Model_Line__c = '노스라이트',
                                                       Status__c = '진행', Start_Date__c = Date.today());
        insert rc;
        insert new Recall_Vehicle__c(Campaign__c = rc.Id, Vehicle__c = v.Id, Status__c = '미통지');
        RepurchaseService.scan();
    }

    @IsTest
    static void timelineShowsRetentionEventsAndBadges() {
        Contact owner = [SELECT Id FROM Contact WHERE LastName = '테스트리텐션차주'];
        CustomerTimelineController.Timeline t = CustomerTimelineController.getTimeline(owner.Id);
        Set<String> kinds = new Set<String>();
        for (CustomerTimelineController.TimelineEvent e : t.events) {
            kinds.add(e.kind);
        }
        System.assert(kinds.containsAll(new Set<String>{ '리콜', '금융', '재구매 상담' }), String.valueOf(kinds));
        String badges = String.join(t.badges, ' | ');
        System.assert(badges.contains('리콜 미조치'), badges);
        System.assert(badges.contains('금융 만기 D-30'), badges);
    }

    @IsTest
    static void owner360ShowsHealthAndRetentionBadges() {
        Contact owner = [SELECT Id, Health_Score__c FROM Contact WHERE LastName = '테스트리텐션차주'];
        CardResult r = new CardResult(AuroraCardController.getOwner360(owner.Id));
        System.assertNotEquals(null, r.o.healthScore, '리콜 대상 저장 시 건강 점수 계산됨');
        System.assertEquals(owner.Health_Score__c, r.o.healthScore);
        System.assert(r.labels.contains('리콜 미조치'), r.labels);
        System.assert(r.labels.contains('금융 만기 D-30'), r.labels);
        System.assert(r.labels.contains('재구매 상담'), r.labels);
    }

    @IsTest
    static void workQueryRecallOpenAndMaturing() {
        String recall = AuroraWorkQueryAction.query('RECALL_OPEN', null);
        System.assert(recall.startsWith('리콜 미조치 차량 1대'), recall);
        System.assert(recall.contains('미통지'), recall);
        String maturing = AuroraWorkQueryAction.query('MATURING', null);
        System.assert(maturing.startsWith('금융 만기 90일 이내 계약 1건'), maturing);
        System.assert(maturing.contains('D-30'), maturing);
        System.assert(!maturing.contains('재구매 상담 없음'), '스캔으로 만든 상담 단계가 보여야 함: ' + maturing);

        update new Recall_Vehicle__c(Id = [SELECT Id FROM Recall_Vehicle__c LIMIT 1].Id, Status__c = '조치 완료');
        System.assert(AuroraWorkQueryAction.query('RECALL_OPEN', null).contains('0건'));
    }

    private class CardResult {
        AuroraCardController.Owner360 o;
        String labels = '';
        CardResult(AuroraCardController.Owner360 o) {
            this.o = o;
            for (AuroraCardController.Badge b : o.badges) {
                labels += b.label + ' | ';
            }
        }
    }
}
