import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTimeline from '@salesforce/apex/CustomerTimelineController.getTimeline';

export default class AuroraTimeline extends NavigationMixin(LightningElement) {
    @api recordId;
    events = [];
    badges = [];
    error;

    @wire(getTimeline, { recordId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.events = data.events.map((e, i) => ({ ...e, key: `${e.recordId}-${i}` }));
            this.badges = data.badges;
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
        }
    }

    get hasEvents() {
        return this.events.length > 0;
    }

    get hasBadges() {
        return this.badges.length > 0;
    }

    open(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
