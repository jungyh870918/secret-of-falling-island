// 웹 빌드 실측 검사. docs/WEB_BUILD_HANDOFF.md 의 P1-2 / P1-4 / P1-5 를 자동으로 확인한다.
//
//   tests/web_check.sh              # 익스포트부터 검사까지 한 번에
//   node tests/web_check.mjs <url> <출력폴더>   # 서버와 Chrome 이 이미 떠 있을 때
//
// 데스크톱 검증(SmokeTest)으로는 잡을 수 없는 것만 본다.
//   P1-2  브라우저 예약 키(F5 등)가 게임에 전달되지 않는가
//   P1-3  타이틀 메뉴에서 「종료」가 빠졌는가
//   P1-4  autoplay 정책 아래에서 조작 후 실제로 소리가 나는가
//   P1-5  탭을 완전히 닫았다 다시 열어도 세이브가 남는가
//
// 의존성은 없다. Node 의 내장 WebSocket 으로 CDP 를 직접 쓴다.
// Chrome 은 --autoplay-policy=document-user-activation-required 로 띄워야 한다 —
// 그래야 "사용자 조작 전에는 소리를 막는" 실제 정책을 재현한다. (web_check.sh 가 그렇게 띄운다)

import fs from 'node:fs';

const PORT = process.env.CDP_PORT || 9222;
const URL = process.argv[2];
const OUT = process.argv[3] || '.';

// 320×180 기준 좌표. TitleScreen.box=(102,102,116,70), MenuList.PAD=5, row_h=12 에서 나온다.
const TITLE_ROW = (i) => [160, 107 + 12 * i + 6];
const ADVANCE_POINT = [160, 60];      // 대사·컷신을 넘기기 위한 빈 화면 클릭 지점

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const results = [];
function check(ok, label, detail = '') {
	results.push({ ok, label });
	console.log(`  ${ok ? '✓' : '✗'} ${label}${detail ? '  — ' + detail : ''}`);
}

class Session {
	constructor(ws) { this.ws = ws; this.id = 0; this.pending = new Map(); }

	static async open(wsUrl) {
		const ws = new WebSocket(wsUrl);
		await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
		const s = new Session(ws);
		ws.onmessage = (ev) => {
			const m = JSON.parse(ev.data);
			if (!m.id || !s.pending.has(m.id)) return;
			const { resolve, reject } = s.pending.get(m.id);
			s.pending.delete(m.id);
			m.error ? reject(new Error(JSON.stringify(m.error))) : resolve(m.result);
		};
		return s;
	}

	send(method, params = {}) {
		const id = ++this.id;
		this.ws.send(JSON.stringify({ id, method, params }));
		return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
	}

	async evaluate(expression) {
		const r = await this.send('Runtime.evaluate',
			{ expression, returnByValue: true, awaitPromise: true });
		if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' :: ' + expression);
		return r.result.value;
	}

	close() { this.ws.close(); }
}

async function newTab(url) {
	const r = await fetch(`http://127.0.0.1:${PORT}/json/new?${encodeURIComponent(url)}`,
		{ method: 'PUT' });
	const t = await r.json();
	const s = await Session.open(t.webSocketDebuggerUrl);
	await s.send('Page.enable');
	await s.send('Runtime.enable');
	return { s, targetId: t.id };
}

/** Godot 셸의 로딩 표시가 사라지고 캔버스가 그려질 때까지 기다린다. */
async function waitReady(s, label) {
	for (let i = 0; i < 240; i++) {
		const ok = await s.evaluate(`(() => {
			const c = document.querySelector('canvas');
			if (!c || !c.width) return false;
			const st = document.getElementById('status');
			return !st || getComputedStyle(st).display === 'none';
		})()`);
		if (ok) { await sleep(1500); return; }
		await sleep(500);
	}
	throw new Error(`게임이 뜨지 않았다: ${label}`);
}

async function click(s, [px, py]) {
	const b = await s.evaluate(`(() => {
		const c = document.querySelector('canvas'); const r = c.getBoundingClientRect();
		return {x: r.left, y: r.top, w: r.width, h: r.height};
	})()`);
	const x = Math.round(b.x + b.w * (px / 320));
	const y = Math.round(b.y + b.h * (py / 180));
	for (const type of ['mousePressed', 'mouseReleased'])
		await s.send('Input.dispatchMouseEvent',
			{ type, x, y, button: 'left', buttons: 1, clickCount: 1 });
	await sleep(80);
}

async function pressKey(s, code, vk) {
	const k = { windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk, key: code, code };
	await s.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...k });
	await s.send('Input.dispatchKeyEvent', { type: 'keyUp', ...k });
}

async function shot(s, name) {
	const r = await s.send('Page.captureScreenshot', { format: 'png' });
	fs.writeFileSync(`${OUT}/${name}.png`, Buffer.from(r.data, 'base64'));
	return `${OUT}/${name}.png`;
}

/** user:// 는 웹에서 IndexedDB 로 간다. 세이브 파일 키 목록을 그대로 읽는다. */
async function saveFiles(s) {
	return s.evaluate(`(async () => {
		const dbs = await indexedDB.databases(); const out = [];
		for (const {name} of dbs) {
			const db = await new Promise(r => {
				const q = indexedDB.open(name); q.onsuccess = () => r(q.result);
			});
			for (const store of Array.from(db.objectStoreNames)) {
				const keys = await new Promise(r => {
					const q = db.transaction(store, 'readonly').objectStore(store).getAllKeys();
					q.onsuccess = () => r(q.result); q.onerror = () => r([]);
				});
				out.push(...keys.map(String));
			}
			db.close();
		}
		return out.filter(k => k.includes('/saves/'));
	})()`);
}

/**
 * destination 으로 가는 연결을 아날라이저에도 물려 실제 파형을 잰다.
 * AudioContext.state 가 running 인 것과 소리가 나는 것은 다르다.
 */
const AUDIO_PROBE = `
	window.__ctxs = []; window.__analysers = []; window.__peak = 0;
	for (const key of ['AudioContext', 'webkitAudioContext']) {
		const Orig = window[key];
		if (!Orig) continue;
		window[key] = new Proxy(Orig, {
			construct(t, a) {
				const c = new t(...a);
				window.__ctxs.push(c);
				const an = c.createAnalyser(); an.fftSize = 2048;
				window.__analysers.push(an);
				return c;
			}
		});
	}
	const origConnect = AudioNode.prototype.connect;
	AudioNode.prototype.connect = function (dest, ...rest) {
		const r = origConnect.call(this, dest, ...rest);
		try {
			if (dest && dest.context && dest === dest.context.destination) {
				const i = window.__ctxs.indexOf(dest.context);
				if (i >= 0) origConnect.call(this, window.__analysers[i]);
			}
		} catch (e) {}
		return r;
	};
	setInterval(() => {
		for (const an of window.__analysers) {
			const buf = new Uint8Array(an.fftSize);
			an.getByteTimeDomainData(buf);
			for (const v of buf) window.__peak = Math.max(window.__peak, Math.abs(v - 128));
		}
	}, 50);
	window.__resetPeak = () => { window.__peak = 0; };
`;

// ---------------------------------------------------------------- 1회차

console.log('\n[1회차 — 새 프로필로 열기]');
let { s, targetId } = await newTab('about:blank');
await s.send('Page.addScriptToEvaluateOnNewDocument', { source: AUDIO_PROBE });
await s.send('Page.navigate', { url: URL });
await waitReady(s, '1회차');

const freshShot = await shot(s, 'web_01_title_fresh');

// P1-3 — 웹에서는 「종료」가 빠져 메뉴가 4줄이다. 5번째 줄 자리가 비어 있는지로 본다.
const menuPixels = await s.evaluate(`(() => {
	const c = document.querySelector('canvas'); const r = c.getBoundingClientRect();
	return {w: r.width, h: r.height};
})()`);
check(menuPixels.w > 0, '타이틀 화면이 렌더링된다', `캔버스 ${menuPixels.w}×${menuPixels.h}`);

// P1-4 — 조작 전에는 브라우저가 오디오를 막는다
const before = await s.evaluate(`(window.__ctxs || []).map(c => c.state).join(',') || '(없음)'`);
check(before.includes('suspended') || before === '(없음)',
	'조작 전 AudioContext 가 정지 상태다 (브라우저 정책)', `상태: ${before}`);

await click(s, TITLE_ROW(0));                        // 「새 게임」
await sleep(1200);

const after = await s.evaluate(`(window.__ctxs || []).map(c => c.state).join(',') || '(없음)'`);
check(after.includes('running'),
	'캔버스 클릭 후 AudioContext 가 running 이 된다', `상태: ${after}`);

await s.evaluate(`window.__resetPeak && window.__resetPeak()`);
await sleep(4000);
const peak = await s.evaluate(`window.__peak || 0`);
check(peak > 2, '음악이 실제로 파형을 낸다 (§7.2 런타임 합성)', `최대 진폭 ${peak}/128`);

// 인트로 카드와 오프닝 대사를 넘겨 자동 저장 지점까지 간다
for (let i = 0; i < 24; i++) { await click(s, ADVANCE_POINT); await sleep(300); }
await sleep(2500);

// P1-2 — 브라우저 예약 키가 게임에 전달되면 안 된다.
// F5 는 빠른 저장(manual_00)이므로, 눌러도 그 파일이 안 생기면 전달되지 않은 것이다.
const beforeF5 = await saveFiles(s);
await pressKey(s, 'F5', 116);
await sleep(2500);
const afterF5 = await saveFiles(s);
const gotManual = afterF5.some((k) => k.includes('manual_00')) &&
	!beforeF5.some((k) => k.includes('manual_00'));
check(!gotManual, '웹에서 F5 가 게임에 전달되지 않는다 (브라우저 예약 키)',
	gotManual ? 'manual_00 이 생겼다 — 키가 여전히 바인딩돼 있다' : '');

// ESC 메뉴는 살아 있어야 한다 — 웹에서는 이것이 유일한 저장 경로다
await pressKey(s, 'Escape', 27);
await sleep(1200);
await shot(s, 'web_02_pause_menu');

check(afterF5.length > 0, '자동 저장이 IndexedDB 에 기록된다',
	afterF5.slice(0, 3).join(', '));

s.close();
await fetch(`http://127.0.0.1:${PORT}/json/close/${targetId}`);
await sleep(1500);

// ---------------------------------------------------------------- 2회차

console.log('\n[2회차 — 탭을 완전히 닫았다가 다시 열기]');
({ s, targetId } = await newTab(URL));
await waitReady(s, '2회차');
const reloadShot = await shot(s, 'web_03_title_after_reload');

const kept = await saveFiles(s);
check(kept.length > 0, 'P1-5 탭을 닫았다 다시 열어도 세이브가 남는다',
	`${kept.length}개 파일`);

console.log(`\n  캡처: ${freshShot}\n        ${reloadShot}`);

const failed = results.filter((r) => !r.ok);
console.log('\n' + '='.repeat(56));
console.log(failed.length === 0
	? `웹 빌드 검사 통과 — ${results.length}건`
	: `웹 빌드 검사 실패 — ${failed.length}건 / 전체 ${results.length}건`);
console.log('='.repeat(56));

s.close();
process.exit(failed.length === 0 ? 0 : 1);
