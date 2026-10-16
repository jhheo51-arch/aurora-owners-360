trigger FinanceContractTrigger on Finance_Contract__c (before insert, before update) {
    // v5: 고객이 비어 있으면 차량의 현재 차주로
    FinanceContractService.fillCustomer(Trigger.new);
}
