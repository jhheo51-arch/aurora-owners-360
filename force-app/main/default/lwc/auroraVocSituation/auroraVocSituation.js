import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getVocSituation from '@salesforce/apex/AuroraCardController.getVocSituation';

const fmtTime = (d) =>
    d ? new Date(d).toLocaleString('ko-KR', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-';

function span(ms) {
    const m = Math.round(Math.abs(ms) / 60000);
    const h = Math.floor(m / 60);
    return (h ? h + '시간 ' : '') + (m % 60) + '분';
}

// VOC 상황 카드: Case 축소 레이아웃(org 공용) 대신 오로라 VOC 페이지 맨 위에 핵심을 모아 보여 준다
export default class AuroraVocSituation extends NavigationMixin(LightningElement) {
    @api recordId;
    s;
    now = Date.now();

    @wire(getVocSituation, { caseId: '$recordId' })
    wired({ data }) {
        if (data) this.s = data;
    }

    connectedCallback() {
        this.timer = setInterval(() => {
            this.now = Date.now();
        }, 30000);
    }

    disconnectedCallback() {
        clearInterval(this.timer);
    }

    get cardClass() {
        return 'card tone-' + (this.s ? this.s.tone : 'info');
    }

    get headline() {
        return `VOC ${this.s.caseNumber} · ${this.s.category || '-'} · ${this.s.priority || '-'}`;
    }

    get stepText() {
        return this.s.step ? `(${this.s.step}/4)` : '';
    }

    get badges() {
        return this.s.badges.map((b, i) => ({ key: i, label: b.label, cls: 'badge ' + b.tone }));
    }

    get due() {
        const s = this.s;
        const dueLabel = '응답 기한 ' + fmtTime(s.dueAt);
        if (s.vocStatus === '종결') return { label: dueLabel, main: '✓ 종결', sub: '', cls: 'big done' };
        if (s.firstResponseAt) {
            const diff = new Date(s.dueAt) - new Date(s.firstResponseAt);
            return s.slaMet
                ? { label: dueLabel, main: '✓ 첫 응답 ' + fmtTime(s.firstResponseAt), sub: '기한보다 ' + span(diff) + ' 앞', cls: 'big ok' }
                : { label: dueLabel, main: '⏱ 늦은 응답 ' + fmtTime(s.firstResponseAt), sub: span(diff) + ' 초과', cls: 'big danger' };
        }
        if (!s.dueAt) return { label: '응답 기한', main: '-', sub: '', cls: 'big' };
        const left = new Date(s.dueAt) - this.now;
        if (left < 0) return { label: dueLabel, main: '⏱ ' + span(left) + ' 초과', sub: '첫 응답 없음', cls: 'big danger' };
        return {
            label: dueLabel,
            main: '⏳ ' + span(left) + ' 남음',
            sub: '첫 응답 전',
            cls: left < 2 * 3600000 ? 'big warn' : 'big ok'
        };
    }

    get handlerSub() {
        const s = this.s;
        const parts = [];
        if (s.advisorName) parts.push('담당 상담원 ' + s.advisorName);
        if (s.escalationStatus === '요청' || s.escalationStatus === '처리완료') parts.push('이관 ' + fmtTime(s.escalatedAt));
        return parts.join(' · ');
    }

    get ownerText() {
        return this.s.ownerName + (this.s.ownerRisk ? ` (위험 ${this.s.ownerRisk})` : '');
    }

    openOwner() {
        this.go(this.s.ownerId);
    }

    openVehicle() {
        this.go(this.s.vehicleId);
    }

    go(id) {
        if (!id) return;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }
}