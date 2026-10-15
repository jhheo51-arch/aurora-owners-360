import { LightningElement, api, wire } from 'lwc';
import getWarrantyGauges from '@salesforce/apex/AuroraCardController.getWarrantyGauges';

const STATE = { ok: '유효', warn: '만료 임박', done: '만료' };

// 보증 게이지: 차량 보증 레코드(v3)별 기간·주행거리 사용률
export default class AuroraWarrantyGauge extends LightningElement {
    @api recordId;
    rows = [];

    @wire(getWarrantyGauges, { vehicleId: '$recordId' })
    wired({ data }) {
        if (data) {
            this.rows = data.map((g, i) => {
                const pct = Math.max(g.timePct || 0, g.kmPct || 0);
                const color = { ok: '#2E844A', warn: '#DD7A01', done: '#8A94A6' }[g.tone];
                return {
                    key: i,
                    type: g.type,
                    badge: 'badge ' + g.tone,
                    state: (g.tone === 'ok' ? '✓ ' : g.tone === 'warn' ? '⏳ ' : '◇ ') + STATE[g.tone] + (g.endDate ? ' · ' + g.endDate : ''),
                    fill: `width:${g.tone === 'done' ? 100 : pct}%;background:${color}`,
                    detail: g.detail
                };
            });
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }
}