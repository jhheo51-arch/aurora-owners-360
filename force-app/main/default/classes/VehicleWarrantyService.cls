/**
 * 차량 보증 고도화(PRD Q45). 출고일과 모델이 있는 차량에 모델 보증 정책으로 일반·파워트레인·배터리 보증을 만들고,
 * VOC 저장 전에 보증 구분(일반 부품/고전압 배터리)에 맞는 보증이 접수일·현재 주행거리 기준으로 유효한지 판정한다.
 */
public with sharing class VehicleWarrantyService {
    public static void createMissing(List<Vehicle__c> vehicles) {
        Set<Id> ids = new Set<Id>();
        for (Vehicle__c v : vehicles) {
            if (v.Delivery_Date__c != null && v.Vehicle_Model__c != null) {
                ids.add(v.Id);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        List<Vehicle_Warranty__c> created = new List<Vehicle_Warranty__c>();
        for (Vehicle__c v : [
            SELECT Id, Delivery_Date__c, Vehicle_Model__r.General_Warranty_Months__c, Vehicle_Model__r.General_Warranty_Km__c,
                Vehicle_Model__r.Powertrain_Warranty_Months__c, Vehicle_Model__r.Powertrain_Warranty_Km__c,
                Vehicle_Model__r.Battery_Warranty_Months__c, Vehicle_Model__r.Battery_Warranty_Km__c,
                (SELECT Id FROM Warranties__r WHERE Warranty_Type__c != '연장')
            FROM Vehicle__c WHERE Id IN :ids
        ]) {
            if (!v.Warranties__r.isEmpty()) {
                continue;
            }
            Vehicle_Model__c m = v.Vehicle_Model__r;
            addTerm(created, v, '일반', m.General_Warranty_Months__c, m.General_Warranty_Km__c);
            addTerm(created, v, '파워트레인', m.Powertrain_Warranty_Months__c, m.Powertrain_Warranty_Km__c);
            addTerm(created, v, '배터리', m.Battery_Warranty_Months__c, m.Battery_Warranty_Km__c);
        }
        insert created;
    }

    private static void addTerm(List<Vehicle_Warranty__c> out, Vehicle__c v, String kind, Decimal months, Decimal km) {
        if (months == null) {
            return;
        }
        out.add(new Vehicle_Warranty__c(Vehicle__c = v.Id, Warranty_Type__c = kind, Start_Date__c = v.Delivery_Date__c,
            End_Date__c = v.Delivery_Date__c.addMonths(months.intValue()), Mileage_Limit_Km__c = km));
    }

    public static void judgeCases(List<Case> cases) {
        Set<Id> vehicleIds = new Set<Id>();
        Set<Id> failureModeIds = new Set<Id>();
        for (Case c : cases) {
            if (c.Vehicle__c != null) {
                vehicleIds.add(c.Vehicle__c);
            }
            if (c.Failure_Mode__c != null) {
                failureModeIds.add(c.Failure_Mode__c);
            }
        }
        // 파워트레인 보증은 구동 계통 하자에만 적용한다(고장 유형 또는 VOC 부품의 계통)
        Set<Id> drivetrainModes = new Map<Id, Failure_Mode__c>([SELECT Id FROM Failure_Mode__c WHERE Id IN :failureModeIds AND System__c = '구동']).keySet();
        Set<Id> drivetrainCases = new Set<Id>();
        for (Case_Part__c cp : [SELECT Case__c FROM Case_Part__c WHERE Case__c IN :cases AND Part__r.System__c = '구동']) {
            drivetrainCases.add(cp.Case__c);
        }
        Map<Id, Vehicle__c> vehicles = vehicleIds.isEmpty() ? new Map<Id, Vehicle__c>() : new Map<Id, Vehicle__c>([
            SELECT Id, Mileage__c,
                (SELECT Id, Warranty_Type__c, End_Date__c, Mileage_Limit_Km__c FROM Warranties__r ORDER BY End_Date__c DESC)
            FROM Vehicle__c WHERE Id IN :vehicleIds
        ]);
        for (Case c : cases) {
            c.Warranty_Coverage__c = false;
            c.Applied_Warranty__c = null;
            Vehicle__c v = vehicles.get(c.Vehicle__c);
            if (v == null) {
                continue;
            }
            Date asOf = c.CreatedDate == null ? Date.today() : c.CreatedDate.date();
            Set<String> kinds = c.Warranty_Scope__c == '고전압 배터리'
                ? new Set<String>{ '배터리', '연장' } : new Set<String>{ '일반', '연장' };
            if (drivetrainModes.contains(c.Failure_Mode__c) || (c.Id != null && drivetrainCases.contains(c.Id))) {
                kinds.add('파워트레인');
            }
            for (Vehicle_Warranty__c w : v.Warranties__r) {
                Boolean inTime = w.End_Date__c != null && w.End_Date__c >= asOf;
                Boolean inKm = w.Mileage_Limit_Km__c == null || v.Mileage__c == null || v.Mileage__c <= w.Mileage_Limit_Km__c;
                if (kinds.contains(w.Warranty_Type__c) && inTime && inKm) {
                    c.Warranty_Coverage__c = true;
                    c.Applied_Warranty__c = w.Id;
                    break;
                }
            }
        }
    }
}
