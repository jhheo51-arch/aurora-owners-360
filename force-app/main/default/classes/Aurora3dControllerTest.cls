@IsTest
private class Aurora3dControllerTest {
    static Map<String, Aurora3dController.PartInfo> byMesh(Aurora3dController.SceneData s) {
        Map<String, Aurora3dController.PartInfo> m = new Map<String, Aurora3dController.PartInfo>();
        for (Aurora3dController.PartInfo p : s.parts) {
            m.put(p.meshId, p);
        }
        return m;
    }

    @IsTest
    static void vocAndVehicleScenes() {
        Vehicle_Model__c model = new Vehicle_Model__c(Name = '노스라이트 테스트', Model_Line__c = '노스라이트', Model_Code__c = 'T-NL');
        insert model;
        Vehicle__c v = new Vehicle__c(VIN__c = 'TEST3D00000000001', Vehicle_Model__c = model.Id);
        insert v;
        Part__c booster = new Part__c(Name = '부스터', Part_Number__c = 'P-T-1', System__c = '제동', Defect_Grade__c = '중대', Mesh_Id__c = 'brake_booster');
        Part__c relay = new Part__c(Name = '릴레이', Part_Number__c = 'P-T-2', System__c = '배터리', Defect_Grade__c = '중대', Mesh_Id__c = 'junction_box');
        Part__c pad = new Part__c(Name = '패드', Part_Number__c = 'P-T-3', System__c = '제동', Defect_Grade__c = '중대', Mesh_Id__c = 'brake_pad_front');
        insert new List<Part__c>{ booster, relay, pad };
        Failure_Mode__c wiki = new Failure_Mode__c(Name = '경고등 점등', System__c = '제동', Status__c = '게시', Primary_Part__c = booster.Id);
        Failure_Mode__c hvac = new Failure_Mode__c(Name = '냄새', System__c = '공조', Status__c = '게시');
        insert new List<Failure_Mode__c>{ wiki, hvac };
        Care_Staff__c manager = new Care_Staff__c(Name = '팀장', Role__c = '상담팀장', Staff_Number__c = 'T-3D-M');
        insert manager;
        Care_Staff__c adv = new Care_Staff__c(Name = '상담원', Role__c = '상담원', Staff_Number__c = 'T-3D', Manager__c = manager.Id);
        insert adv;
        Case brakeVoc = new Case(Subject = '경고등', Vehicle__c = v.Id, Advisor__c = adv.Id, Manager_Employee__c = manager.Id, VOC_Category__c = '안전 결함',
            VOC_Status__c = '접수', Failure_Mode__c = wiki.Id);
        Case relayVoc = new Case(Subject = '충전', Vehicle__c = v.Id, Advisor__c = adv.Id, VOC_Category__c = '충전·배터리', VOC_Status__c = '접수');
        Case smellVoc = new Case(Subject = '냄새', Advisor__c = adv.Id, VOC_Category__c = '품질 결함', VOC_Status__c = '접수', Failure_Mode__c = hvac.Id);
        insert new List<Case>{ brakeVoc, relayVoc, smellVoc };
        insert new List<Case_Part__c>{
            new Case_Part__c(Case__c = brakeVoc.Id, Part__c = booster.Id, Role__c = '의심'),
            new Case_Part__c(Case__c = relayVoc.Id, Part__c = relay.Id, Role__c = '점검')
        };
        insert new List<Service_Visit__c>{
            new Service_Visit__c(Vehicle__c = v.Id, Check_In_Date__c = Date.today().addMonths(-6), Visit_Type__c = '하자 수리', Defect_System__c = '제동', Main_Part__c = pad.Id),
            new Service_Visit__c(Vehicle__c = v.Id, Check_In_Date__c = Date.today().addMonths(-2), Visit_Type__c = '하자 수리', Defect_System__c = '제동', Main_Part__c = pad.Id)
        };

        Test.startTest();
        Aurora3dController.SceneData vocScene = Aurora3dController.getScene(brakeVoc.Id);
        Aurora3dController.SceneData vehScene = Aurora3dController.getScene(v.Id);
        Aurora3dController.SceneData softScene = Aurora3dController.getScene(smellVoc.Id);
        Test.stopTest();

        Map<String, Aurora3dController.PartInfo> vp = byMesh(vocScene);
        System.assertEquals('suv', vocScene.shape);
        System.assertEquals('suspect', vp.get('brake_booster').mark);
        System.assertEquals(null, vp.get('junction_box').mark, 'VOC 화면은 그 VOC 부품만');
        System.assertEquals('경고등 점등', vp.get('brake_booster').wikiTitle);
        System.assertEquals('⚠ 안전 결함', vocScene.badges[0].label);
        System.assert(vocScene.outline.isEmpty());

        Map<String, Aurora3dController.PartInfo> hp = byMesh(vehScene);
        System.assertEquals('suspect', hp.get('brake_booster').mark);
        System.assertEquals('inspect', hp.get('junction_box').mark);
        System.assertEquals('replaced', hp.get('brake_pad_front').mark);
        System.assertEquals(2, hp.get('brake_pad_front').visitCount);
        System.assertEquals(new List<String>{ '제동' }, vehScene.outline, '반복 결함 계통 외곽선');

        System.assertEquals('sedan', softScene.shape, '차량 없음 → 기본 형태');
        System.assertEquals('공조', softScene.soft, '부품이 없으면 고장 유형 계통을 연하게');
    }
}
