import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import centerLoads from '@salesforce/apex/AuroraNetworkController.centerLoads';

const TONE = {
    FREE: { cls: 'ok', mark: '○ ', color: '#2E844A' },
    NORMAL: { cls: 'warn', mark: '◐ ', color: '#DD7A01' },
    BUSY: { cls: 'danger', mark: '● ', color: '#BA0517' },
    UNKNOWN: { cls: 'done', mark: '– ', color: '#8A94A6' }
};

// v5 S-1 서비스센터 혼잡도: 담당 센터 먼저, 나머지는 여유 있는 순. 색 + 기호 + 글자로 표시
export default class AuroraCenterLoad extends NavigationMixin(LightningElement) {
    @api recordId;
    rows = [];
    error;

    @wire(centerLoads, { vehicleId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.error = undefined;
            this.rows = data.map((c) => {
                const t = TONE[c.level] || TONE.UNKNOWN;
                const pct = c.percent == null ? 0 : Math.min(c.percent, 100);
                return {
                    key: c.id,
                    id: c.id,
                    name: c.name,
                    preferred: c.preferred,
                    badge: 'badge ' + t.cls,
                    state: t.mark + c.levelLabel + (c.percent == null ? '' : ' ' + c.percent + '%'),
                    fill: `width:${pct}%;background:${t.color}`,
                    detail: c.capacity == null
                        ? `진행 중 정비 ${c.openVisits}대`
                        : `진행 중 정비 ${c.openVisits}대 / 하루 ${c.capacity}대` + (c.region ? ` · ${c.region}` : ''),
                    rowClass: c.preferred ? 'center mine' : 'center'
                };
            });
        } else if (error) {
            this.error = '서비스센터 정보를 불러오지 못했습니다.';
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    open(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
