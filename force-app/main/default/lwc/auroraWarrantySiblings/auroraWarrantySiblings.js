import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import VEHICLE from '@salesforce/schema/Vehicle_Warranty__c.Vehicle__c';
import VEHICLE_NAME from '@salesforce/schema/Vehicle_Warranty__c.Vehicle__r.Name';
import VEHICLE_KM from '@salesforce/schema/Vehicle_Warranty__c.Vehicle__r.Mileage__c';

const FIELDS = [
    'Vehicle_Warranty__c.Name',
    'Vehicle_Warranty__c.Warranty_Type__c',
    'Vehicle_Warranty__c.Status__c',
    'Vehicle_Warranty__c.Start_Date__c',
    'Vehicle_Warranty__c.End_Date__c',
    'Vehicle_Warranty__c.Mileage_Limit_Km__c'
];

const field = (rec, name) => (rec.fields[name] ? rec.fields[name] : { value: null, displayValue: null });
const shown = (rec, name) => {
    const f = field(rec, name);
    return f.displayValue != null ? f.displayValue : f.value;
};

// 같은 차량의 보증 전체(만료일 순). 차량 보증 레코드 화면 오른쪽에 둔다.
// Apex 없이 UI API만 사용: 보증 → 차량 → 차량의 보증 관련 목록. 상태는 기호+글자로 표시.
export default class AuroraWarrantySiblings extends NavigationMixin(LightningElement) {
    @api recordId;
    rows = [];
    error;

    @wire(getRecord, { recordId: '$recordId', fields: [VEHICLE, VEHICLE_NAME, VEHICLE_KM] })
    warranty;

    get vehicleId() {
        return this.warranty && this.warranty.data ? getFieldValue(this.warranty.data, VEHICLE) : undefined;
    }

    get vehicleKm() {
        return this.warranty && this.warranty.data ? getFieldValue(this.warranty.data, VEHICLE_KM) : null;
    }

    get subtitle() {
        const name = this.warranty && this.warranty.data ? getFieldValue(this.warranty.data, VEHICLE_NAME) : '';
        const km = this.vehicleKm != null ? ` · 현재 주행 ${Number(this.vehicleKm).toLocaleString('ko-KR')}km` : '';
        return `${name || ''}${km} · 만료일 순`;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$vehicleId',
        relatedListId: 'Warranties__r',
        fields: FIELDS,
        pageSize: 50
    })
    wiredWarranties({ data, error }) {
        if (data) {
            this.rows = data.records
                .map((r) => {
                    const status = shown(r, 'Status__c') || '-';
                    const valid = status === '유효';
                    const limit = field(r, 'Mileage_Limit_Km__c').value;
                    const current = r.id === this.recordId;
                    return {
                        id: r.id,
                        sortKey: field(r, 'End_Date__c').value || '9999',
                        name: shown(r, 'Name'),
                        type: shown(r, 'Warranty_Type__c') || '-',
                        badge: (valid ? '✓ ' : '◇ ') + status,
                        badgeCls: valid ? 'badge ok' : 'badge done',
                        period: `${shown(r, 'Start_Date__c') || '?'} ~ ${shown(r, 'End_Date__c') || '?'}`,
                        limit: limit != null ? `한도 ${Number(limit).toLocaleString('ko-KR')}km` : '',
                        current,
                        cls: current ? 'item current' : 'item'
                    };
                })
                .sort((a, b) => (a.sortKey < b.sortKey ? -1 : a.sortKey > b.sortKey ? 1 : 0));
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
        }
    }

    get title() {
        return `같은 차량 보증 (${this.rows.length})`;
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
