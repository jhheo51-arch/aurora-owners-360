// v5 샘플 적재 후 1회 실행: 재구매 상담 생성(금융 만기·보증 만료 90일 이내) + 차주 위험·건강 점수 재계산
// sf apex run -f scripts/apex/v5-init.apex -o <org>
System.debug('재구매 상담 생성 ' + RepurchaseService.scan() + '건');
Map<Id, Contact> owners = new Map<Id, Contact>([SELECT Id FROM Contact WHERE Email LIKE '%aurora.example.com']);
CustomerRiskService.recalculate(owners.keySet());
System.debug('점수 재계산 차주 ' + owners.size() + '명');
