/** v5 S-3 금융·리스 계약: 고객 자동 채움, 만기 단계 수식 */
@IsTest
private class FinanceContractTest {
    @IsTest
    static void fillsCustomerAndMaturityStage() {
        Contact owner = new Contact(LastName = '테스트금융차주');
        Contact other = new Contact(LastName = '테스트다른고객');
        insert new List<Contact>{ owner, other };
        Vehicle__c v = new Vehicle__c(VIN__c = 'TESTFC0000000001', Model__c = '시티로', Owner_Contact__c = owner.Id);
        insert v;
        List<Finance_Contract__c> rows = new List<Finance_Contract__c>{
            new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '리스', Status__c = '진행', End_Date__c = Date.today().addDays(30)),
            new Finance_Contract__c(Vehicle__c = v.Id, Customer__c = other.Id, Contract_Type__c = '할부', Status__c = '진행', End_Date__c = Date.today().addDays(400)),
            new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '할부', Status__c = '진행', End_Date__c = Date.today().addDays(-1)),
            new Finance_Contract__c(Vehicle__c = v.Id, Contract_Type__c = '할부', Status__c = '만기', End_Date__c = Date.today().addDays(-100))
        };
        insert rows;
        Map<Id, Finance_Contract__c> got = new Map<Id, Finance_Contract__c>(
            [SELECT Customer__c, Maturity_Stage__c, Days_To_Maturity__c FROM Finance_Contract__c]);
        System.assertEquals(owner.Id, got.get(rows[0].Id).Customer__c, '비어 있으면 차량 차주');
        System.assertEquals(other.Id, got.get(rows[1].Id).Customer__c, '입력한 고객은 그대로');
        System.assertEquals(30, got.get(rows[0].Id).Days_To_Maturity__c);
        System.assert(got.get(rows[0].Id).Maturity_Stage__c.contains('90일 이내'));
        System.assert(got.get(rows[1].Id).Maturity_Stage__c.contains('진행'));
        System.assert(got.get(rows[2].Id).Maturity_Stage__c.contains('만기 지남'));
        System.assert(got.get(rows[3].Id).Maturity_Stage__c.contains('만기'));
    }
}
