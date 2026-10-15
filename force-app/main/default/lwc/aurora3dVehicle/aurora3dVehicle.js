import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import THREE_ZIP from '@salesforce/resourceUrl/three147';
import getScene from '@salesforce/apex/Aurora3dController.getScene';

// 브랜드 가이드 §7 계통 색과 분해 방향
const SYS = {
    배터리: { color: 0x3bb7aa, dir: [0, -1.7, 0] },
    구동: { color: 0x7a6bd8, dir: [-2.2, -0.3, 0] },
    제동: { color: 0x5b6472, dir: [0.4, -0.2, 2.1] },
    공조: { color: 0x4f8be0, dir: [2.1, 0.7, 0] },
    전장: { color: 0x8a94a6, dir: [-0.6, 2.2, 0] },
    차체: { color: 0xdce3ee, dir: [0, 1.2, -2.2] }
};
const MARK = {
    suspect: { color: 0xc23934, label: '의심' },
    inspect: { color: 0xdd7a01, label: '점검' },
    replaced: { color: 0x8a94a6, label: '교체' },
    soft: { color: 0xf2a7a4, label: '계통' }
};
const SHAPES = {
    sedan: { L: 4.6, W: 1.85, H: 0.55, cabinL: 2.4, cabinH: 0.5, cabinX: -0.2, wheel: 0.34, label: '세단' },
    suv: { L: 4.7, W: 1.95, H: 0.75, cabinL: 3.0, cabinH: 0.62, cabinX: -0.35, wheel: 0.4, label: 'SUV' },
    compact: { L: 3.7, W: 1.75, H: 0.65, cabinL: 2.3, cabinH: 0.62, cabinX: -0.15, wheel: 0.3, label: '소형' }
};
const TONE = { danger: 'badge danger', warn: 'badge warn', ok: 'badge ok', done: 'badge done' };

export default class Aurora3dVehicle extends NavigationMixin(LightningElement) {
    @api recordId;
    scene;
    error;
    libLoaded = false;
    started = false;
    exploded = false;
    shapeKey = 'sedan';
    hidden = {};
    selected;

    @wire(getScene, { recordId: '$recordId' })
    wiredScene({ data, error }) {
        if (data) {
            this.scene = data;
            this.shapeKey = data.shape || 'sedan';
            this.partById = {};
            data.parts.forEach((p) => {
                this.partById[p.meshId] = p;
            });
            this.tryStart();
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
        }
    }

    renderedCallback() {
        if (this.libRequested) return;
        this.libRequested = true;
        loadScript(this, THREE_ZIP + '/three.min.js')
            .then(() => loadScript(this, THREE_ZIP + '/OrbitControls.js'))
            .then(() => {
                this.libLoaded = true;
                this.tryStart();
            })
            .catch((e) => {
                this.error = '3D 라이브러리를 불러오지 못했습니다: ' + (e && e.message ? e.message : e);
            });
    }

    disconnectedCallback() {
        this.stopped = true;
        if (this.raf) cancelAnimationFrame(this.raf);
        if (this.resizeObs) this.resizeObs.disconnect();
        if (this.controls) this.controls.dispose();
        this.disposeCar();
        if (this.renderer) {
            this.renderer.dispose();
            if (this.renderer.forceContextLoss) this.renderer.forceContextLoss();
        }
    }

    // ===== 장면 =====
    tryStart() {
        if (this.started || !this.libLoaded || !this.scene) return;
        const THREE = window.THREE;
        if (!THREE || !THREE.OrbitControls) {
            this.error = '3D 라이브러리(THREE)를 찾지 못했습니다.';
            return;
        }
        const stage = this.template.querySelector('.a3d-stage');
        if (!stage) return;
        this.started = true;
        this.THREE = THREE;
        const canvas = document.createElement('canvas');
        canvas.style.width = '100%';
        canvas.style.height = '100%';
        canvas.style.display = 'block';
        canvas.setAttribute('aria-label', '오로라 차량 3D 모델');
        const pins = document.createElement('div');
        pins.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
        stage.appendChild(canvas);
        stage.appendChild(pins);
        this.stage = stage;
        this.canvas = canvas;
        this.pinBox = pins;

        try {
            this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
        } catch (e) {
            this.error = '이 브라우저 환경에서 WebGL을 쓸 수 없습니다: ' + e.message;
            return;
        }
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
        this.scene3 = new THREE.Scene();
        this.camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
        this.controls = new THREE.OrbitControls(this.camera, canvas);
        this.controls.enableDamping = true;
        this.controls.minDistance = 3;
        this.controls.maxDistance = 18;
        this.scene3.add(new THREE.HemisphereLight(0xffffff, 0xc8d2e0, 0.9));
        const sun = new THREE.DirectionalLight(0xffffff, 0.7);
        sun.position.set(4, 8, 6);
        this.scene3.add(sun);
        const floor = new THREE.Mesh(
            new THREE.CircleGeometry(3.6, 48),
            new THREE.MeshBasicMaterial({ color: 0xd8dee8, transparent: true, opacity: 0.6 })
        );
        floor.rotation.x = -Math.PI / 2;
        floor.position.y = -0.62;
        this.scene3.add(floor);

        this.ray = new THREE.Raycaster();
        this.mouse = new THREE.Vector2();
        canvas.addEventListener('pointerdown', (e) => {
            this.down = [e.clientX, e.clientY];
        });
        canvas.addEventListener('pointerup', (e) => this.pick(e));

        this.resizeObs = new ResizeObserver(() => this.resize());
        this.resizeObs.observe(stage);
        this.build();
        this.resize();
        this.resetView();
        const loop = (now) => {
            if (this.stopped) return;
            this.raf = requestAnimationFrame(loop);
            this.frame(now);
        };
        this.raf = requestAnimationFrame(loop);
    }

    mat(color, opacity) {
        return new this.THREE.MeshStandardMaterial({
            color,
            roughness: 0.75,
            metalness: 0.05,
            transparent: true,
            opacity: opacity == null ? 1 : opacity
        });
    }

    disposeCar() {
        if (!this.car) return;
        this.scene3.remove(this.car);
        this.car.traverse((o) => {
            if (o.geometry) o.geometry.dispose();
            if (o.material) o.material.dispose();
        });
        this.car = null;
    }

    build() {
        const THREE = this.THREE;
        this.disposeCar();
        const s = SHAPES[this.shapeKey];
        const car = new THREE.Group();
        const groups = {};
        const meshes = [];
        Object.keys(SYS).forEach((k) => {
            const g = new THREE.Group();
            g.userData = { sys: k, dir: new THREE.Vector3().fromArray(SYS[k].dir) };
            groups[k] = g;
            car.add(g);
        });
        const add = (sys, id, geo, pos, rot) => {
            const m = new THREE.Mesh(geo, this.mat(SYS[sys].color));
            m.position.set(pos[0], pos[1], pos[2]);
            if (rot) m.rotation.set(rot[0], rot[1], rot[2]);
            m.userData = { id };
            groups[sys].add(m);
            meshes.push(m);
        };
        const hw = s.W / 2;
        const hl = s.L / 2;
        const shell = new THREE.Mesh(new THREE.BoxGeometry(s.L, s.H, s.W), this.mat(0xdce3ee, 0.35));
        groups['차체'].add(shell);
        const cabin = new THREE.Mesh(new THREE.BoxGeometry(s.cabinL, s.cabinH, s.W * 0.92), this.mat(0x0b3d91, 0.22));
        cabin.position.set(s.cabinX, s.H / 2 + s.cabinH / 2, 0);
        groups['차체'].add(cabin);
        add('차체', 'door_seal', new THREE.BoxGeometry(1.1, 0.5, 0.05), [s.cabinX + 0.3, s.H / 2, hw + 0.03]);
        add('차체', 'a_pillar', new THREE.BoxGeometry(0.08, s.cabinH, 0.08), [s.cabinX + s.cabinL / 2, s.H / 2 + s.cabinH / 2, hw - 0.1], [0, 0, -0.4]);
        [[1, 1], [1, -1], [-1, 1], [-1, -1]].forEach((p) => {
            const w = new THREE.Mesh(new THREE.CylinderGeometry(s.wheel, s.wheel, 0.28, 20), this.mat(0x4a5363, 0.85));
            w.rotation.x = Math.PI / 2;
            w.position.set(p[0] * (hl - 0.8), -s.H / 2 + 0.05, p[1] * (hw - 0.05));
            car.add(w);
        });
        add('배터리', 'battery_pack', new THREE.BoxGeometry(s.L * 0.55, 0.14, s.W * 0.8), [0, -s.H / 2 - 0.02, 0]);
        add('배터리', 'junction_box', new THREE.BoxGeometry(0.35, 0.18, 0.4), [s.L * 0.3, -s.H / 2 + 0.05, 0]);
        add('배터리', 'charge_port', new THREE.BoxGeometry(0.35, 0.22, 0.12), [-hl + 0.5, 0.05, -hw + 0.02]);
        add('구동', 'rear_motor', new THREE.CylinderGeometry(0.22, 0.22, 0.5, 16), [-(hl - 0.8), -0.12, 0], [Math.PI / 2, 0, 0]);
        add('구동', 'reducer', new THREE.CylinderGeometry(0.14, 0.14, 0.3, 12), [-(hl - 0.8), -0.12, 0.42], [Math.PI / 2, 0, 0]);
        add('구동', 'hcu', new THREE.BoxGeometry(0.4, 0.2, 0.35), [hl - 0.6, 0.12, -0.3]);
        add('제동', 'brake_pad_front', new THREE.BoxGeometry(0.22, 0.3, 0.06), [hl - 0.8, -s.H / 2 + 0.05, hw - 0.25]);
        add('제동', 'abs_sensor', new THREE.SphereGeometry(0.08, 12, 8), [hl - 0.8, -s.H / 2 + 0.05, -(hw - 0.25)]);
        add('제동', 'brake_booster', new THREE.CylinderGeometry(0.2, 0.2, 0.25, 18), [hl - 1.2, 0.15, 0.45], [0, 0, Math.PI / 2]);
        add('공조', 'evaporator', new THREE.BoxGeometry(0.3, 0.25, 0.7), [s.cabinX + s.cabinL / 2 - 0.15, s.H / 2 - 0.05, 0]);
        add('공조', 'heat_pump', new THREE.BoxGeometry(0.25, 0.3, 0.8), [hl - 0.2, 0, 0]);
        add('전장', 'tmu', new THREE.BoxGeometry(0.4, 0.06, 0.3), [s.cabinX - 0.4, s.H / 2 + s.cabinH + 0.04, 0]);
        add('전장', 'rear_camera', new THREE.BoxGeometry(0.06, 0.1, 0.16), [-hl - 0.02, 0.12, 0]);
        this.scene3.add(car);
        this.car = car;
        this.groups = groups;
        this.meshes = meshes;
        this.exploded = false;
        this.anim = null;
        this.setExplode(0);
        Object.keys(this.hidden).forEach((k) => {
            groups[k].visible = !this.hidden[k];
        });
        this.applyHighlight();
    }

    applyHighlight() {
        const THREE = this.THREE;
        const sc = this.scene;
        const outline = sc.outline || [];
        const any = this.meshes.some((m) => this.markOf(m.userData.id));
        this.meshes.forEach((m) => {
            const part = this.partById[m.userData.id];
            const sys = part ? part.systemName : null;
            const mk = this.markOf(m.userData.id);
            m.userData.mark = mk;
            m.material.color.setHex(mk ? MARK[mk].color : SYS[sys || '차체'].color);
            m.material.emissive.setHex(mk && mk !== 'soft' ? MARK[mk].color : 0x000000);
            m.material.emissiveIntensity = mk === 'inspect' ? 0.35 : 0;
            m.material.opacity = mk ? (mk === 'soft' ? 0.6 : 1) : any ? 0.15 : 1;
            if (sys && outline.includes(sys)) {
                m.add(new THREE.LineSegments(new THREE.EdgesGeometry(m.geometry), new THREE.LineBasicMaterial({ color: 0xc23934 })));
                if (!mk) m.material.opacity = 0.5;
            }
        });
        this.renderPins();
    }

    markOf(meshId) {
        const p = this.partById[meshId];
        if (!p) return null;
        if (p.mark) return p.mark;
        return this.scene.soft && this.scene.soft === p.systemName ? 'soft' : null;
    }

    renderPins() {
        this.pinBox.innerHTML = '';
        this.pinEls = [];
        this.meshes.forEach((m) => {
            const mk = m.userData.mark;
            if (!mk || mk === 'soft') return;
            const el = document.createElement('div');
            el.textContent = this.partById[m.userData.id].name + ' · ' + MARK[mk].label;
            el.style.cssText =
                'position:absolute;transform:translate(-50%,-100%);background:#0B3D91;color:#fff;font-size:12px;' +
                'padding:3px 8px;border-radius:6px;white-space:nowrap;box-shadow:0 2px 6px rgba(0,0,0,.2);';
            this.pinBox.appendChild(el);
            this.pinEls.push([el, m]);
        });
    }

    setExplode(f) {
        Object.keys(this.groups).forEach((k) => {
            const g = this.groups[k];
            g.position.copy(g.userData.dir).multiplyScalar(f);
        });
    }

    resize() {
        if (!this.renderer) return;
        const w = this.stage.clientWidth;
        const h = this.stage.clientHeight;
        if (!w || !h) return;
        this.renderer.setSize(w, h, false);
        this.camera.aspect = w / h;
        this.camera.updateProjectionMatrix();
    }

    resetView() {
        this.camera.position.set(4.6, 2.6, 4.9);
        this.controls.target.set(0, 0, 0);
        this.controls.update();
    }

    frame(now) {
        if (this.anim) {
            const k = Math.min((now - this.anim.t0) / 600, 1);
            const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
            this.setExplode(this.anim.from + (this.anim.to - this.anim.from) * e);
            if (k === 1) this.anim = null;
        }
        const blink = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin((now / 1000) * Math.PI * 2));
        this.meshes.forEach((m) => {
            if (m.userData.mark === 'suspect') m.material.emissiveIntensity = blink;
        });
        this.controls.update();
        this.updatePins();
        this.renderer.render(this.scene3, this.camera);
    }

    updatePins() {
        const THREE = this.THREE;
        const w = this.stage.clientWidth;
        const h = this.stage.clientHeight;
        const v = new THREE.Vector3();
        (this.pinEls || []).forEach(([el, m]) => {
            m.getWorldPosition(v);
            v.y += 0.25;
            v.project(this.camera);
            el.style.display = !m.parent.visible || v.z > 1 ? 'none' : '';
            el.style.left = ((v.x + 1) / 2) * w + 'px';
            el.style.top = ((1 - v.y) / 2) * h + 'px';
        });
    }

    pick(e) {
        if (!this.down || Math.abs(e.clientX - this.down[0]) + Math.abs(e.clientY - this.down[1]) > 5) return;
        const r = this.canvas.getBoundingClientRect();
        this.mouse.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
        this.ray.setFromCamera(this.mouse, this.camera);
        const hit = this.ray.intersectObjects(this.meshes.filter((m) => m.parent.visible), false)[0];
        if (!hit) return;
        const p = this.partById[hit.object.userData.id];
        if (!p) return;
        const mk = hit.object.userData.mark;
        this.selected = {
            ...p,
            markLabel: mk && mk !== 'soft' ? MARK[mk].label : null,
            gradeClass: p.grade === '중대' ? 'badge danger' : 'badge info'
        };
    }

    // ===== 버튼 =====
    get explodeLabel() {
        return this.exploded ? '조립' : '분해';
    }

    toggleExplode() {
        if (!this.groups) return;
        this.exploded = !this.exploded;
        this.anim = { t0: performance.now(), from: this.exploded ? 0 : 1, to: this.exploded ? 1 : 0 };
    }

    handleReset() {
        if (this.camera) this.resetView();
    }

    get shapeButtons() {
        return Object.keys(SHAPES).map((k) => ({
            key: k,
            label: SHAPES[k].label,
            variant: k === this.shapeKey ? 'brand' : 'neutral'
        }));
    }

    setShape(e) {
        this.shapeKey = e.currentTarget.dataset.key;
        if (this.THREE) this.build();
    }

    get systemButtons() {
        return Object.keys(SYS).map((k) => ({
            key: k,
            label: k,
            pressed: String(!this.hidden[k]),
            variant: this.hidden[k] ? 'neutral' : 'brand-outline',
            swatch: 'background:#' + SYS[k].color.toString(16).padStart(6, '0')
        }));
    }

    toggleSystem(e) {
        const k = e.currentTarget.dataset.key;
        this.hidden = { ...this.hidden, [k]: !this.hidden[k] };
        if (this.groups) this.groups[k].visible = !this.hidden[k];
    }

    // ===== 글자 정보 (색만으로 전달하지 않음) =====
    get title() {
        return this.scene ? this.scene.title : '3D 부위 분해도';
    }

    get badges() {
        return (this.scene ? this.scene.badges : []).map((b, i) => ({ key: i, label: b.label, cls: TONE[b.tone] || 'badge info' }));
    }

    get markedList() {
        if (!this.scene) return [];
        const rows = this.scene.parts
            .filter((p) => p.mark)
            .map((p) => ({ key: p.meshId, text: `${p.name} (${p.systemName})`, label: MARK[p.mark].label }));
        (this.scene.outline || []).forEach((s) => rows.push({ key: 'o-' + s, text: `${s} 계통 전체`, label: '빨간 외곽선' }));
        if (this.scene.soft) rows.push({ key: 'soft', text: `${this.scene.soft} 계통(고장 유형)`, label: '연한 표시' });
        return rows;
    }

    get hasMarked() {
        return this.markedList.length > 0;
    }

    openWiki() {
        if (!this.selected || !this.selected.wikiId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.selected.wikiId, actionName: 'view' }
        });
    }
}
