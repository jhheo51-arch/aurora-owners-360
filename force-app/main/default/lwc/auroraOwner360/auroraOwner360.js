import { LightningElement, api, wire } from 'lwc';
import getOwner360 from '@salesforce/apex/AuroraCardController.getOwner360';

// 차주 360 카드: 위험 등급·최근 90일 VOC·진행 중 VOC·보유 차량을 한눈에
export default class AuroraOwner360 extends LightningElement {
    @api recordId;
    o;

    @wire(getOwner360, { contactId: '$recordId' })
    wired({ data }) {
        if (data) this.o = data;
    }

    get cardClass() {
        return 'card tone-' + (this.o ? this.o.tone : 'ok');
    }

    get initial() {
        return this.o && this.o.name ? this.o.name.substring(0, 1) : '';
    }

    get riskText() {
        if (!this.o.riskLevel) return '-';
        return (this.o.tone === 'ok' ? '✓ ' : '⚠ ') + this.o.riskLevel + ' · ' + (this.o.riskScore || 0) + '점';
    }

    get riskClass() {
        return 'v ' + (this.o ? this.o.tone : '');
    }

    get badges() {
        return this.o.badges.map((b, i) => ({ key: i, label: b.label, cls: 'badge ' + b.tone }));
    }

    get contactLine() {
        return [this.o.phone, this.o.email].filter(Boolean).join(' · ');
    }
}