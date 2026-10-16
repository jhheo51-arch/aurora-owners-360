import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import preview from '@salesforce/apex/RecallCampaignService.preview';
import generateTargets from '@salesforce/apex/RecallCampaignService.generateTargets';

// v5 S-2 [대상 차량 생성]: 조건과 대상 수를 먼저 보여 주고, 확인하면 만든다
export default class AuroraRecallTargets extends LightningElement {
    _recordId;
    info;
    busy = false;
    loaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this.loaded) {
            this.loaded = true;
            this.load();
        }
    }

    async load() {
        try {
            this.info = await preview({ campaignId: this._recordId });
        } catch (e) {
            this.info = { ok: false, message: '조건을 확인하지 못했습니다.' };
        }
    }

    get canCreate() {
        return this.info && this.info.ok && this.info.matched > this.info.existing && !this.busy;
    }

    get cannotCreate() {
        return !this.canCreate;
    }

    async create() {
        this.busy = true;
        try {
            const r = await generateTargets({ campaignId: this._recordId });
            this.dispatchEvent(new ShowToastEvent({ title: '대상 차량', message: r.message, variant: r.ok ? 'success' : 'warning' }));
            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.close();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: '대상 차량', message: '만들지 못했습니다.', variant: 'error' }));
            this.busy = false;
        }
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
