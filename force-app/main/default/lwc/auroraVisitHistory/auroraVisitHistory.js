import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import VEHICLE from '@salesforce/schema/Service_Visit__c.Vehicle__c';
import VEHICLE_NAME from '@salesforce/schema/Service_Visit__c.Vehicle__r.Name';

const FIELDS = [
    'Service_Visit__c.Name',
    'Service_Visit__c.Check_In_Date__c',
    'Service_Visit__c.Visit_Type__c',
    'Service_Visit__c.Defect_System__c',
    'Service_Visit__c.Main_Part__r.Name',
    'Service_Visit__c.Completed_Date__c',
    'Service_Visit__c.Repair_Days__c',
    'Service_Visit__c.Mileage__c',
    'Service_Visit__c.Symptom__c'
];

const val = (rec, path) => {
    const parts = path.split('.');
    let node = rec;
    for (let i = 0; i < parts.length; i++) {
        const f = node && node.fields ? node.fields[parts[i]] : undefined;
        if (!f) return null;
        if (i === parts.length - 1) return f.displayValue != null ? f.displayValue : f.value;
        node = f.value;
    }
    return null;
};

// 같은 차량의 정비 이력 전체(입고일 최신순). 정비 이력 레코드 화면 오른쪽에 둔다.
// Apex 없이 UI API만 사용: 정비 → 차량 → 차량의 정비 관련 목록.
export default class AuroraVisitHistory extends NavigationMixin(LightningElement) {
    @api recordId;
    rows = [];
    error;

    @wire(getRecord, { recordId: '$recordId', fields: [VEHICLE, VEHICLE_NAME] })
    visit;

    get vehicleId() {
        return this.visit && this.visit.data ? getFieldValue(this.visit.data, VEHICLE) : undefined;
    }

    get vehicleName() {
        return this.visit && this.visit.data ? getFieldValue(this.visit.data, VEHICLE_NAME) : '';
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$vehicleId',
        relatedListId: 'Service_Visits__r',
        fields: FIELDS,
        pageSize: 50
    })
    wiredVisits({ data, error }) {
        if (data) {
            this.rows = data.records
                .map((r) => {
                    const current = r.id === this.recordId;
                    const days = val(r, 'Repair_Days__c');
                    const km = r.fields.Mileage__c ? r.fields.Mileage__c.value : null;
                    return {
                        id: r.id,
                        sortKey: r.fields.Check_In_Date__c ? r.fields.Check_In_Date__c.value || '' : '',
                        name: val(r, 'Name'),
                        date: val(r, 'Check_In_Date__c') || '입고일 미확인',
                        type: val(r, 'Visit_Type__c') || '-',
                        system: val(r, 'Defect_System__c'),
                        part: val(r, 'Main_Part__r.Name'),
                        meta: [
                            !val(r, 'Completed_Date__c') ? '수리 중(완료일 미입력)' : days != null && days !== '' ? '수리 ' + days + '일' : null,
                            km != null ? Number(km).toLocaleString('ko-KR') + 'km' : null
                        ]
                            .filter(Boolean)
                            .join(' · '),
                        symptom: val(r, 'Symptom__c'),
                        current,
                        cls: current ? 'item current' : 'item'
                    };
                })
                .sort((a, b) => (a.sortKey < b.sortKey ? 1 : a.sortKey > b.sortKey ? -1 : 0));
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
        }
    }

    get title() {
        return `같은 차량 정비 이력 (${this.rows.length})`;
    }

    get subtitle() {
        return this.vehicleName ? `${this.vehicleName} · 입고일 최신순` : '입고일 최신순';
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    open(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
