import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeHero from '@salesforce/apex/AuroraCardController.getHomeHero';

const fmt = (d) => (d ? new Date(d).toLocaleString('ko-KR', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-');

// 홈 히어로: 진행 중·기한 임박/초과·이관 대기·안전 결함 숫자 + 첫 응답 전 VOC 기한 순 5건
export default class AuroraHomeHero extends NavigationMixin(LightningElement) {
    h;
    error;

    connectedCallback() {
        this.load();
    }

    load() {
        getHomeHero()
            .then((d) => {
                this.h = d;
            })
            .catch((e) => {
                this.error = e.body ? e.body.message : e.message;
            });
    }

    get tiles() {
        if (!this.h) return [];
        return [
            { key: 'open', label: '진행 중 VOC', icon: '●', value: this.h.open, cls: 'tile info', view: 'Aurora_My_VOC' },
            { key: 'due', label: '기한 임박·초과 (2시간 이내)', icon: '⏳', value: this.h.dueSoon, cls: 'tile warn', view: 'Aurora_Safety_Overdue' },
            { key: 'esc', label: '팀장 이관 대기', icon: '↑', value: this.h.escalated, cls: 'tile warn', view: 'Aurora_Escalated_VOC' },
            { key: 'safety', label: '안전 결함 진행 중', icon: '⚠', value: this.h.safety, cls: 'tile danger', view: 'Aurora_Safety_Overdue' }
        ];
    }

    get alerts() {
        return this.h ? this.h.alerts : [];
    }

    openAlert(e) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: e.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    get rows() {
        return (this.h ? this.h.rows : []).map((r) => ({ ...r, due: fmt(r.dueAt) }));
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    openList(e) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'list' },
            state: { filterName: e.currentTarget.dataset.view }
        });
    }

    openCase(e) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: e.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}