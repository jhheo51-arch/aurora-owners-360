/**
 * 3D 부위 분해도(aurora3dVehicle) 데이터.
 * - VOC(Case): VOC 부품(Case_Part) 역할(의심/점검/교체) + 고장 유형 대표 부품. 둘 다 없으면 고장 유형 계통 전체를 연하게.
 * - 고객 차량: 그 차량 모든 VOC 부품 + 정비 주요 부품(교체) + 반복 결함·레몬법 근거 계통 외곽선.
 * 3D 부품은 Part__c.Mesh_Id__c와 1:1. 형태는 차량 모델 계열(노스라이트=SUV, 시티로=소형, 그 밖=세단).
 */
public with sharing class Aurora3dController {
    static final Map<String, String> ROLE_MARK = new Map<String, String>{ '의심' => 'suspect', '점검' => 'inspect', '교체' => 'replaced' };
    static final Map<String, Integer> MARK_RANK = new Map<String, Integer>{ 'suspect' => 3, 'inspect' => 2, 'replaced' => 1 };
    static final List<String> SYSTEMS = new List<String>{ '배터리', '구동', '제동', '공조', '전장', '차체' };

    public class Badge {
        @AuraEnabled public String label;
        @AuraEnabled public String tone; // danger / warn / ok / done
        Badge(String label, String tone) { this.label = label; this.tone = tone; }
    }

    public class PartInfo {
        @AuraEnabled public String meshId;
        @AuraEnabled public String name;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String systemName;
        @AuraEnabled public String grade;
        @AuraEnabled public String mark;
        @AuraEnabled public Integer vocCount = 0;
        @AuraEnabled public Integer visitCount = 0;
        @AuraEnabled public String wikiTitle;
        @AuraEnabled public Id wikiId;
    }

    public class SceneData {
        @AuraEnabled public String title;
        @AuraEnabled public String shape = 'sedan';
        @AuraEnabled public String soft;
        @AuraEnabled public List<String> outline = new List<String>();
        @AuraEnabled public List<Badge> badges = new List<Badge>();
        @AuraEnabled public List<PartInfo> parts = new List<PartInfo>();
    }

    @AuraEnabled(cacheable=true)
    public static SceneData getScene(Id recordId) {
        SceneData scene = new SceneData();
        Case voc;
        Id vehicleId;
        if (recordId.getSobjectType() == Case.SObjectType) {
            voc = [SELECT Id, CaseNumber, Subject, VOC_Category__c, Vehicle__c,
                          Failure_Mode__r.Primary_Part__c, Failure_Mode__r.System__c
                   FROM Case WHERE Id = :recordId];
            vehicleId = voc.Vehicle__c;
            scene.title = 'VOC ' + voc.CaseNumber + ' · ' + voc.Subject;
            if (voc.VOC_Category__c == '안전 결함') {
                scene.badges.add(new Badge('⚠ 안전 결함', 'danger'));
            }
        } else {
            vehicleId = recordId;
        }

        Vehicle__c v;
        if (vehicleId != null) {
            v = [SELECT Id, Name, Vehicle_Model__r.Model_Line__c, Owner_Contact__r.Name,
                        Lemon_Law_Status__c, Lemon_Law_Basis__c, Repeat_Defect__c, Repeat_Defect_System__c
                 FROM Vehicle__c WHERE Id = :vehicleId];
            String line = v.Vehicle_Model__r == null ? null : v.Vehicle_Model__r.Model_Line__c;
            scene.shape = line == '노스라이트' ? 'suv' : (line == '시티로' ? 'compact' : 'sedan');
            if (voc == null) {
                scene.title = v.Name + (line == null ? '' : ' · ' + line) + (v.Owner_Contact__r == null ? '' : ' (' + v.Owner_Contact__r.Name + ')');
            }
            addVehicleSignals(scene, v, voc == null);
        }

        Map<Id, PartInfo> byPart = new Map<Id, PartInfo>();
        for (Part__c p : [SELECT Id, Name, Part_Number__c, System__c, Defect_Grade__c, Mesh_Id__c
                          FROM Part__c WHERE Mesh_Id__c != null ORDER BY Part_Number__c]) {
            PartInfo info = new PartInfo();
            info.meshId = p.Mesh_Id__c;
            info.name = p.Name;
            info.partNumber = p.Part_Number__c;
            info.systemName = p.System__c;
            info.grade = p.Defect_Grade__c;
            byPart.put(p.Id, info);
            scene.parts.add(info);
        }
        for (Failure_Mode__c fm : [SELECT Id, Name, Primary_Part__c FROM Failure_Mode__c
                                   WHERE Status__c = '게시' AND Primary_Part__c IN :byPart.keySet()]) {
            byPart.get(fm.Primary_Part__c).wikiTitle = fm.Name;
            byPart.get(fm.Primary_Part__c).wikiId = fm.Id;
        }

        if (vehicleId != null) {
            // 같은 차량 VOC 부품 건수 + (차량 화면이면) 표시
            for (Case_Part__c cp : [SELECT Part__c, Role__c, Case__c FROM Case_Part__c
                                    WHERE Case__r.Vehicle__c = :vehicleId AND Part__c IN :byPart.keySet()]) {
                PartInfo info = byPart.get(cp.Part__c);
                info.vocCount++;
                if (voc == null) {
                    mark(info, ROLE_MARK.get(cp.Role__c));
                }
            }
            for (Service_Visit__c s : [SELECT Main_Part__c FROM Service_Visit__c
                                       WHERE Vehicle__c = :vehicleId AND Main_Part__c IN :byPart.keySet()]) {
                PartInfo info = byPart.get(s.Main_Part__c);
                info.visitCount++;
                if (voc == null) {
                    mark(info, 'replaced');
                }
            }
        }

        if (voc != null) {
            Boolean marked = false;
            for (Case_Part__c cp : [SELECT Part__c, Role__c FROM Case_Part__c
                                    WHERE Case__c = :voc.Id AND Part__c IN :byPart.keySet()]) {
                mark(byPart.get(cp.Part__c), ROLE_MARK.get(cp.Role__c));
                marked = true;
            }
            Id primary = voc.Failure_Mode__r == null ? null : voc.Failure_Mode__r.Primary_Part__c;
            if (primary != null && byPart.containsKey(primary)) {
                mark(byPart.get(primary), 'suspect');
                marked = true;
            }
            if (!marked && voc.Failure_Mode__r != null) {
                scene.soft = voc.Failure_Mode__r.System__c;
            }
        }
        return scene;
    }

    static void mark(PartInfo info, String mark) {
        if (mark == null) {
            return;
        }
        if (info.mark == null || MARK_RANK.get(mark) > MARK_RANK.get(info.mark)) {
            info.mark = mark;
        }
    }

    static void addVehicleSignals(SceneData scene, Vehicle__c v, Boolean withOutline) {
        Set<String> outline = new Set<String>();
        if (v.Repeat_Defect__c && String.isNotBlank(v.Repeat_Defect_System__c)) {
            scene.badges.add(new Badge('↻ 반복 결함 · ' + v.Repeat_Defect_System__c, 'warn'));
            for (String s : v.Repeat_Defect_System__c.split(',')) {
                outline.add(s.trim());
            }
        }
        if (v.Lemon_Law_Status__c == '대상 가능' || v.Lemon_Law_Status__c == '주의') {
            String basis = v.Lemon_Law_Basis__c == null ? '' : v.Lemon_Law_Basis__c;
            List<String> lemonSystems = new List<String>();
            for (String s : SYSTEMS) {
                if (basis.contains(s + ' 계통')) {
                    lemonSystems.add(s);
                    outline.add(s);
                }
            }
            String suffix = lemonSystems.isEmpty() ? '' : ' · ' + String.join(lemonSystems, ', ');
            scene.badges.add(v.Lemon_Law_Status__c == '대상 가능'
                ? new Badge('⚖ 레몬법 대상 가능' + suffix, 'danger')
                : new Badge('⚖ 레몬법 주의' + suffix, 'warn'));
        } else {
            scene.badges.add(new Badge('⚖ 레몬법 해당 없음', 'done'));
        }
        if (withOutline) {
            for (String s : SYSTEMS) {
                if (outline.contains(s)) {
                    scene.outline.add(s);
                }
            }
        }
    }
}
