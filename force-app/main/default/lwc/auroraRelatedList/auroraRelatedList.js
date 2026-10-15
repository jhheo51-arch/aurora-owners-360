import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

// 페이지 레이아웃과 무관하게 관련 레코드를 보여 주는 작은 목록.
// 표준 관련 목록 컴포넌트는 레이아웃에 있는 목록만 그리는데, Case 레이아웃은 org 공용이라 바꾸지 않는다(v3.5 S4).
export default class AuroraRelatedList extends NavigationMixin(LightningElement) {
    @api recordId;
    @api title;
    @api iconName = 'standard:related_list';
    @api relatedListId; // 예: Compensations__r
    @api childObject; // 예: Compensation__c
    @api parentField; // 예: Case__c (새로 만들기 기본값)
    @api fields; // 쉼표 구분, 첫 필드가 링크. 조회 필드는 Part__r.Name 형식
    @api emptyMessage = '아직 없습니다.';

    rows = [];
    error;
    labels = {};

    get fieldList() {
        return (this.fields || '').split(',').map((f) => f.trim()).filter(Boolean);
    }

    get qualifiedFields() {
        return this.fieldList.map((f) => `${this.childObject}.${f}`);
    }

    @wire(getObjectInfo, { objectApiName: '$childObject' })
    wiredInfo({ data }) {
        if (data) {
            const labels = {};
            this.fieldList.forEach((f) => {
                const base = f.includes('.') ? f.split('.')[0].replace(/__r$/, '__c') : f;
                labels[f] = data.fields[base] ? data.fields[base].label : f;
            });
            this.labels = labels;
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$relatedListId',
        fields: '$qualifiedFields',
        pageSize: 20
    })
    wiredRecords({ data, error }) {
        if (data) {
            this.rows = data.records.map((rec) => ({
                id: rec.id,
                cells: this.fieldList.map((f, i) => ({
                    key: `${rec.id}-${f}`,
                    value: this.read(rec, f),
                    isLink: i === 0
                }))
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
        }
    }

    read(rec, path) {
        let node = rec;
        const parts = path.split('.');
        for (let i = 0; i < parts.length; i++) {
            const f = node && node.fields ? node.fields[parts[i]] : undefined;
            if (!f) return '';
            if (i === parts.length - 1) {
                if (f.displayValue != null) return f.displayValue;
                if (typeof f.value === 'number') return f.value.toLocaleString('ko-KR');
                return f.value != null ? String(f.value) : '';
            }
            node = f.value;
        }
        return '';
    }

    get columns() {
        return this.fieldList.map((f) => ({ key: f, label: this.labels[f] || f }));
    }

    get cardTitle() {
        return `${this.title} (${this.rows.length})`;
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

    createNew() {
        const page = {
            type: 'standard__objectPage',
            attributes: { objectApiName: this.childObject, actionName: 'new' }
        };
        if (this.parentField) {
            page.state = { defaultFieldValues: encodeDefaultFieldValues({ [this.parentField]: this.recordId }) };
        }
        this[NavigationMixin.Navigate](page);
    }
}
