import { LightningElement, api, wire } from 'lwc';
import getBadges from '@salesforce/apex/AuroraCardController.getBadges';

// 상태 배지 줄: 기호+글자로 상태를 알려 준다(색만으로 전달하지 않음)
export default class AuroraStatusBadges extends LightningElement {
    @api recordId;
    badges = [];

    @wire(getBadges, { recordId: '$recordId' })
    wired({ data }) {
        if (data) {
            this.badges = data.map((b, i) => ({ key: i, label: b.label, cls: 'badge ' + b.tone }));
        }
    }

    get hasBadges() {
        return this.badges.length > 0;
    }
}