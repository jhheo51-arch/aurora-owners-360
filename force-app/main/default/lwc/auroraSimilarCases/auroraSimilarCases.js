import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSimilar from '@salesforce/apex/SimilarCaseService.getSimilar';
import ragAnswer from '@salesforce/apex/AuroraRagService.answer';

export default class AuroraSimilarCases extends NavigationMixin(LightningElement) {
    @api recordId;
    items = [];
    error;
    // v4.4 RAG: 버튼을 눌렀을 때만 AI를 부른다(근거 2건 미만이면 AI 없이 '부족' 안내)
    guide;
    guideBusy = false;
    guideError;

    @wire(getSimilar, { caseId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.items = data;
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
        }
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get guideNote() {
        if (!this.guide) return '';
        if (!this.guide.sufficient) return '근거가 부족해 AI를 부르지 않았습니다.';
        return this.guide.usedAi ? 'AI(Claude)가 아래 근거만으로 정리 · 상담원 확인용' : 'AI 생성에 실패해 근거만 표시';
    }

    async makeGuide() {
        if (this.guideBusy) return;
        this.guideBusy = true;
        this.guideError = undefined;
        try {
            this.guide = await ragAnswer({ caseId: this.recordId });
        } catch (e) {
            this.guideError = e && e.body ? e.body.message : 'AI 해결 가이드를 만들지 못했습니다.';
        }
        this.guideBusy = false;
    }

    open(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }
}
