import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import identify from '@salesforce/apex/AicxController.identify';
import evaluate from '@salesforce/apex/AicxController.evaluate';
import guide from '@salesforce/apex/AicxController.guide';
import submit from '@salesforce/apex/AicxController.submit';
import resolve from '@salesforce/apex/AicxController.resolve';
import finishInfo from '@salesforce/apex/AicxController.finishInfo';
import connectHuman from '@salesforce/apex/AicxController.connectHuman';
import handoverSummary from '@salesforce/apex/AicxController.handoverSummary';

// 오로라 AI 상담(AICX) — PRD §20-6. 대화 상태는 이 컴포넌트가 들고, 판단은 Apex 규칙이 한다.
// 상태: IDENTIFY → ASK → (HANDOFF | GUIDE → CONFIRM → CSAT | NO_MATCH) → END
// v4.3: ASK → INFO(정보 안내, 이어서 질문 가능) → (해결됐어요 → INFO_CSAT | 상담사 연결) → END
const MAX_ID_TRY = 3;
let seq = 0;

export default class AuroraCustomerChat extends NavigationMixin(LightningElement) {
    // 좁은 영역(홈 왼쪽 열)에서는 채팅과 판단 근거를 위아래로 쌓는다
    @api stacked = false;
    get gridClass() {
        return this.stacked ? 'grid stacked' : 'grid';
    }

    state = 'IDENTIFY';
    messages = [];
    phone = '';
    plate = '';
    question = '';
    idTries = 0;
    busy = false;
    who; // 본인 확인 결과
    decision;
    wikiId;
    lastQuestion;
    infoQuestion; // 마지막 정보 안내 질문(해결 기록·상담사 연결에 사용)
    outcome;
    handover;
    handoverBusy = false;

    connectedCallback() {
        this.say('bot', '안녕하세요, 오로라 AI 상담입니다. 본인 확인을 위해 휴대폰 번호와 차량 번호 뒤 4자리를 입력해 주세요.');
    }

    // ===== 화면 상태 =====
    get isIdentify() { return this.state === 'IDENTIFY'; }
    get isAsk() { return this.state === 'ASK' || this.state === 'INFO'; }
    get isInfo() { return this.state === 'INFO'; }
    get askLabel() { return this.state === 'INFO' ? '이어서 질문' : '문의 내용'; }
    get isConfirm() { return this.state === 'CONFIRM'; }
    get isCsat() { return this.state === 'CSAT' || this.state === 'INFO_CSAT'; }
    get isEnd() { return this.state === 'END'; }
    get stars() { return [1, 2, 3, 4, 5].map((n) => ({ n, label: '★'.repeat(n) })); }
    get rules() { return this.decision ? this.decision.rules : []; }
    get hasRules() { return this.rules.length > 0; }
    get actionLabel() {
        if (!this.decision) return '-';
        return { HANDOFF: '상담사 연결', GUIDE: 'AI 안내(위키)', NO_MATCH: 'AI 접수', INFO: 'AI 정보 안내' }[this.decision.action] || this.decision.action;
    }
    get noAssign() { return !!this.decision && !this.decision.advisorName; }
    get notes() { return this.decision && this.decision.notes ? this.decision.notes : []; }
    get hasNotes() { return this.notes.length > 0; }
    get intentLine() {
        const i = this.decision && this.decision.intent;
        return i ? `${i.code} ${i.label} · 키워드 '${i.keyword}'${i.others > 0 ? ` · 다른 의도 ${i.others}개` : ''}` : '-';
    }
    get infoSources() {
        return this.decision && this.decision.info ? this.decision.info.sources : '-';
    }
    get wikiLine() {
        const w = this.decision && this.decision.wiki;
        return w ? `${w.title} · 점수 ${w.score} · ${w.reason}` : '매칭 위키 없음';
    }

    say(from, text) {
        seq += 1;
        this.messages = [...this.messages, { id: seq, text, cls: from === 'me' ? 'bubble me' : 'bubble bot' }];
        Promise.resolve().then(() => {
            const box = this.template.querySelector('.log');
            if (box) box.scrollTop = box.scrollHeight;
        });
    }

    onPhone(e) { this.phone = e.target.value; }
    onPlate(e) { this.plate = e.target.value; }
    onQuestion(e) { this.question = e.target.value; }

    // ===== IDENTIFY =====
    async doIdentify() {
        if (this.busy) return;
        this.busy = true;
        this.say('me', `${this.phone} / 차량 뒤 4자리 ${this.plate}`);
        try {
            const who = await identify({ phone: this.phone, plate4: this.plate });
            if (who) {
                this.who = who;
                this.state = 'ASK';
                this.say('bot', `${who.name} 고객님, 확인되었습니다(${who.vehicleLabel}). 어떤 점이 불편하신가요?`);
            } else {
                this.idTries += 1;
                if (this.idTries >= MAX_ID_TRY) {
                    this.state = 'END';
                    this.say('bot', '본인 확인에 3번 실패해 상담을 종료합니다. 고객센터 1588-0000으로 전화 주세요. (상담 기록은 남기지 않았습니다)');
                } else {
                    this.say('bot', `입력하신 정보와 일치하는 차량이 없습니다. 다시 확인해 주세요. (${this.idTries}/${MAX_ID_TRY})`);
                }
            }
        } catch (e) {
            this.fail(e);
        }
        this.busy = false;
    }

    // ===== ASK → 규칙 판정 =====
    async doAsk() {
        const q = (this.question || '').trim();
        if (!q || this.busy) return;
        this.busy = true;
        this.lastQuestion = q;
        this.question = '';
        this.say('me', q);
        try {
            const r = await evaluate({ contactId: this.who.contactId, vehicleId: this.who.vehicleId, message: q });
            if (r.action === 'REFUSE') {
                this.say('bot', r.message);
                this.busy = false;
                return;
            }
            this.decision = r.decision;
            if (r.action === 'INFO') {
                // 정보 조회: 답하고 대화를 이어 간다(판정 한 번으로 끝내지 않음)
                this.infoQuestion = q;
                this.say('bot', r.message);
                this.say('bot', '궁금증이 풀리셨나요? 다른 것도 이어서 물어보셔도 돼요.');
                this.state = 'INFO';
            } else if (r.action === 'GUIDE') {
                this.wikiId = r.decision.wiki.wikiId;
                const g = await guide({ wikiId: this.wikiId, vehicleId: this.who.vehicleId });
                this.say('bot', g.text + (g.usedAi ? '' : '\n(안내 문장 생성이 어려워 위키 원문 단계를 보여 드렸어요)'));
                this.say('bot', '안내대로 해 보셨나요? 해결되셨나요?');
                this.state = 'CONFIRM';
            } else {
                await this.finishWith(submit({ contactId: this.who.contactId, vehicleId: this.who.vehicleId, message: q }));
            }
        } catch (e) {
            this.fail(e);
        }
        this.busy = false;
    }

    // ===== INFO 빠른 답 =====
    infoSolved() {
        this.say('me', '궁금증 해결됐어요');
        this.say('bot', '다행입니다. 이번 상담은 어떠셨나요? 별점을 골라 주세요.');
        this.state = 'INFO_CSAT';
    }

    async infoHuman() {
        if (this.busy) return;
        this.busy = true;
        this.say('me', '상담사 연결해 주세요');
        try {
            await this.finishWith(connectHuman({ contactId: this.who.contactId, vehicleId: this.who.vehicleId, message: this.infoQuestion }));
        } catch (e) {
            this.fail(e);
        }
        this.busy = false;
    }

    // ===== CONFIRM =====
    solved() {
        this.say('me', '해결됐어요');
        this.say('bot', '다행입니다. 이번 상담은 어떠셨나요? 별점을 골라 주세요.');
        this.state = 'CSAT';
    }

    async notSolved() {
        if (this.busy) return;
        this.busy = true;
        this.say('me', '아직이요');
        try {
            await this.finishWith(resolve({
                contactId: this.who.contactId, vehicleId: this.who.vehicleId, message: this.lastQuestion,
                wikiId: this.wikiId, solved: false, csat: null
            }));
        } catch (e) {
            this.fail(e);
        }
        this.busy = false;
    }

    async rate(e) {
        if (this.busy) return;
        this.busy = true;
        const n = Number(e.currentTarget.dataset.n);
        this.say('me', '★'.repeat(n));
        try {
            if (this.state === 'INFO_CSAT') {
                await this.finishWith(finishInfo({
                    contactId: this.who.contactId, vehicleId: this.who.vehicleId, message: this.infoQuestion, csat: n
                }));
            } else {
                await this.finishWith(resolve({
                    contactId: this.who.contactId, vehicleId: this.who.vehicleId, message: this.lastQuestion,
                    wikiId: this.wikiId, solved: true, csat: n
                }));
            }
        } catch (err) {
            this.fail(err);
        }
        this.busy = false;
    }

    async finishWith(promise) {
        const o = await promise;
        this.outcome = o;
        this.decision = o.decision;
        this.say('bot', o.message);
        this.state = 'END';
    }

    // ===== 상담원 쪽 패널 =====
    async makeHandover() {
        if (!this.outcome || this.handoverBusy) return;
        this.handoverBusy = true;
        try {
            this.handover = await handoverSummary({ caseId: this.outcome.caseId });
        } catch (e) {
            this.handover = e && e.body ? e.body.message : '인계 요약을 만들지 못했습니다.';
        }
        this.handoverBusy = false;
    }

    get canHandover() {
        return this.outcome && this.outcome.outcome === '상담사 연결';
    }

    openCase() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.outcome.caseId, actionName: 'view' } });
    }

    restart() {
        this.state = 'IDENTIFY';
        this.messages = [];
        this.phone = '';
        this.plate = '';
        this.idTries = 0;
        this.who = undefined;
        this.decision = undefined;
        this.infoQuestion = undefined;
        this.outcome = undefined;
        this.handover = undefined;
        this.connectedCallback();
    }

    fail(e) {
        this.say('bot', '처리 중 문제가 생겼습니다: ' + (e && e.body ? e.body.message : e && e.message ? e.message : e));
    }
}
