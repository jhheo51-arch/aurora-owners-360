import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import search from '@salesforce/apex/AuroraOwnerBoardController.search';

// v4.4 P-2 '차주·차량' 통합 탭: 오로라 차주 목록 → 펼치면 보유 차량 카드와 진행 중 VOC.
// 상태는 색 + 기호 + 글자로 함께 표시한다(v3.5 원칙).
const FILTERS = [
    { key: 'risk', label: '⚠ 위험 높음' },
    { key: 'lemon', label: '⚖ 레몬법 주의 이상' },
    { key: 'openVoc', label: '● 진행 중 VOC 있음' },
    { key: 'expiring', label: '⏳ 보증 만료 임박(90일)' },
    // v5 S-6 리텐션
    { key: 'health', label: '♡ 건강 주의' },
    { key: 'recall', label: '🔧 리콜 미조치' },
    { key: 'maturing', label: '💳 금융 만기(90일)' }
];
const RISK = { 높음: ['danger', '⚠ 위험 높음'], 주의: ['warn', '△ 위험 주의'], 낮음: ['ok', '✓ 위험 낮음'] };
const HEALTH = { 좋음: ['ok', '♥'], 보통: ['warn', '♡'], 주의: ['danger', '♡'] };

export default class AuroraOwnerVehicleBoard extends NavigationMixin(LightningElement) {
    term = '';
    active = new Set();
    rows = [];
    expanded = new Set();
    loading = false;
    error;
    timer;

    connectedCallback() {
        this.load();
    }

    get filters() {
        return FILTERS.map((f) => ({ ...f, variant: this.active.has(f.key) ? 'brand' : 'neutral', pressed: this.active.has(f.key) ? 'true' : 'false' }));
    }

    get countLabel() {
        return `차주 ${this.rows.length}명`;
    }

    get isEmpty() {
        return !this.loading && !this.error && this.rows.length === 0;
    }

    async load() {
        this.loading = true;
        try {
            const data = await search({ term: this.term, filters: [...this.active] });
            this.rows = data.map((r) => this.decorate(r));
            this.error = undefined;
        } catch (e) {
            this.error = e && e.body ? e.body.message : '목록을 불러오지 못했습니다.';
        }
        this.loading = false;
    }

    decorate(r) {
        const [tone, riskLabel] = RISK[r.risk] || ['done', '위험 미산정'];
        const open = this.expanded.has(r.id);
        const vocs = r.openVocs.map((v) => ({
            ...v,
            cls: v.safety ? 'ob-voc danger' : 'ob-voc',
            label: `${v.safety ? '⚠ ' : '● '}${v.caseNumber} · ${v.subject} — ${v.status}`
        }));
        return {
            ...r,
            open,
            toggleIcon: open ? 'utility:chevrondown' : 'utility:chevronright',
            toggleLabel: open ? '접기' : '펼치기',
            rowCls: `ob-row tone-${tone}`,
            riskCls: `ob-badge ${tone}`,
            riskLabel: `${riskLabel}${r.riskScore != null ? ' · ' + r.riskScore + '점' : ''}`,
            ...this.health(r),
            vocCount: vocs.length,
            vocLabel: vocs.length ? `진행 중 VOC ${vocs.length}건` : '진행 중 VOC 없음',
            vehicleLabel: `보유 차량 ${r.vehicles.length}대`,
            vocs,
            hasVocs: vocs.length > 0,
            vehicles: r.vehicles.map((v) => this.vehicle(v, r))
        };
    }

    // v5 S-6: 고객 건강 점수 칩(근거는 title로)
    health(r) {
        if (r.healthScore == null) {
            return { hasHealth: false };
        }
        const [tone, mark] = HEALTH[r.healthGrade] || ['done', '♡'];
        return {
            hasHealth: true,
            healthCls: `ob-badge ${tone}`,
            healthLabel: `${mark} 건강 ${r.healthScore} · ${r.healthGrade}`,
            healthTitle: r.healthBasis ? `건강 점수 근거: ${r.healthBasis}` : '건강 점수'
        };
    }

    vehicle(v, owner) {
        const badges = [];
        if (v.lemon === '대상 가능') badges.push({ k: 'l', cls: 'ob-badge danger', text: '⚖ 레몬법 대상 가능' });
        else if (v.lemon === '주의') badges.push({ k: 'l', cls: 'ob-badge warn', text: '⚖ 레몬법 주의' });
        if (v.repeatDefect) badges.push({ k: 'r', cls: 'ob-badge warn', text: `↻ 반복 결함${v.repeatSystem ? '(' + v.repeatSystem + ')' : ''}` });
        if (v.warrantyExpiring) badges.push({ k: 'w', cls: 'ob-badge warn', text: '⏳ 보증 만료 임박' });
        // v5: 리콜 미조치 · 금융 만기 · 재구매 상담
        if (v.recallOpen) badges.push({ k: 'rc', cls: 'ob-badge danger', text: `🔧 리콜 미조치 · ${v.recallOpen}` });
        if (v.maturityDays != null) badges.push({ k: 'fc', cls: 'ob-badge warn', text: `💳 금융 만기 D-${v.maturityDays}` });
        if (v.repurchaseStage) badges.push({ k: 'op', cls: 'ob-badge ok', text: `🤝 재구매 상담 ${v.repurchaseStage}` });
        if (!badges.length) badges.push({ k: 'n', cls: 'ob-badge ok', text: '✓ 품질 신호 없음' });
        return {
            ...v,
            ownerId: owner.id,
            badges,
            mileageLabel: v.mileage != null ? `${Number(v.mileage).toLocaleString('ko-KR')}km` : '주행거리 미입력',
            warrantyLabel: v.validWarranties ? `유효 보증 ${v.validWarranties}건 · 가장 먼저 끝나는 ${v.nextWarrantyEnd}` : '유효 보증 없음'
        };
    }

    // ===== 검색·필터 =====
    onTerm(e) {
        this.term = e.target.value;
        clearTimeout(this.timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.timer = setTimeout(() => this.load(), 300);
    }

    toggleFilter(e) {
        const key = e.currentTarget.dataset.key;
        const next = new Set(this.active);
        if (next.has(key)) next.delete(key);
        else next.add(key);
        this.active = next;
        this.load();
    }

    clearAll() {
        this.term = '';
        this.active = new Set();
        this.load();
    }

    toggleRow(e) {
        const id = e.currentTarget.dataset.id;
        const next = new Set(this.expanded);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        this.expanded = next;
        this.rows = this.rows.map((r) => (r.id === id ? this.decorate(r) : r));
    }

    // ===== 이동 =====
    openRecord(e) {
        e.preventDefault();
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: e.currentTarget.dataset.id, actionName: 'view' } });
    }

    newVoc(e) {
        const { owner, vehicle } = e.currentTarget.dataset;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' },
            state: { defaultFieldValues: encodeDefaultFieldValues({ ContactId: owner, Vehicle__c: vehicle, VOC_Status__c: '접수' }) }
        });
    }
}
