@IsTest
private class AuroraStaffDirectoryTest {
    @IsTest
    static void firstActiveByRoleInStaffNumberOrder() {
        insert new List<Care_Staff__c>{
            new Care_Staff__c(Name = '퇴직자', Role__c = '보상 심사', Staff_Number__c = 'T-SD-1', Active__c = false),
            new Care_Staff__c(Name = '나중 직원', Role__c = '보상 심사', Staff_Number__c = 'T-SD-3', Active__c = true),
            new Care_Staff__c(Name = '먼저 직원', Role__c = '보상 심사', Staff_Number__c = 'T-SD-2', Active__c = true)
        };
        AuroraStaffDirectory.resetCache();
        System.assertEquals('먼저 직원', AuroraStaffDirectory.firstByRole(AuroraStaffDirectory.COMPENSATION).Name, '재직자 중 직원 코드 순');
        System.assertEquals('보상 심사 먼저 직원', AuroraStaffDirectory.label(AuroraStaffDirectory.COMPENSATION));
        System.assertEquals(null, AuroraStaffDirectory.firstByRole(AuroraStaffDirectory.SERVICE_CENTER));
        System.assertEquals('서비스센터 협력', AuroraStaffDirectory.label(AuroraStaffDirectory.SERVICE_CENTER), '담당자가 없으면 역할만');
    }
}
