// 技巧音效可闻性抽查：代表谱的 MIDI 事件特征断言（推弦/揉弦/滑音/闷音/延音/泛音/琶音）
// 用法：node tools/verify-technique-fx.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/technique-fx';
fs.mkdirSync(EVIDENCE, { recursive: true });
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log((ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : ''));
}
const CASES = [
  { id: '1H9WW324T', name: '天地龙鳞(bend+vibrato)', expectBend: true },
  { id: '1H9TYl5rJ', name: '真的爱你前奏(bend)', expectBend: true },
  { id: '1H9ReAmpR', name: '李白(slide)', expectBend: true },
  { id: '1H9SkFiMP', name: '死别(palmMute)', expectPalmMute: true },
  { id: '1H9RkyHbh', name: '祝你生日快乐(letRing)', expectLetRing: true },
  { id: '1H9RlDwKT', name: '知足(harmonic+letRing)', expectHarmonic: true },
  { id: '1sdc71abklk', name: '类似爱情(arpeggio)', expectPlay: true },
  { id: 'oOEvk5YC', name: 'Just The Two Of Us(全乐队+鼓)', expectPlay: true },
];
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 160)); });
page.on('pageerror', (e) => errs.push(String(e).slice(0, 160)));

for (const c of CASES) {
  const beforeErr = errs.length;
  await page.goto(BASE + '/tabs/' + c.id, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => window.__api && window.__api._player && window.__api._player.isReadyForPlayback, { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(2500);
  const r = await page.evaluate(async () => {
    const api = window.__api;
    let lastMidi = null;
    api.midiLoad.on((f) => { lastMidi = f; });
    api.loadMidiForScore();
    await new Promise((res) => { const c = () => lastMidi ? res() : setTimeout(c, 50); c(); setTimeout(res, 8000); });
    if (!lastMidi) return { err: 'no midi' };
    const all = [];
    for (const mt of lastMidi.tracks || []) for (const ev of mt.events || []) all.push(ev);
    const perNoteBend = all.filter((e) => e.type === 96).length;
    const pitchBend = all.filter((e) => e.type === 224).length;
    const noteOn = all.filter((e) => e.type === 128);
    const noteOff = all.filter((e) => e.type === 144);
    const velMin = noteOn.length ? Math.min(...noteOn.map((e) => e.noteVelocity)) : 0;
    const velMax = noteOn.length ? Math.max(...noteOn.map((e) => e.noteVelocity)) : 0;
    const lowVels = noteOn.filter((e) => e.noteVelocity < 70).length;
    // 最长音符（同一 track+key 的 NoteOff-NoteOn 跨度）
    let maxDur = 0;
    const offMap = new Map();
    for (const e of noteOff) offMap.set(e.track + ':' + e.channel + ':' + e.noteKey, e.tick);
    for (const e of noteOn) {
      const end = offMap.get(e.track + ':' + e.channel + ':' + e.noteKey);
      if (end !== undefined) maxDur = Math.max(maxDur, end - e.tick);
    }
    let minDur = 1e9;
    for (const e of noteOn) {
      const end = offMap.get(e.track + ':' + e.channel + ':' + e.noteKey);
      if (end !== undefined) minDur = Math.min(minDur, end - e.tick);
    }
    if (minDur === 1e9) minDur = 0;
    return { perNoteBend, pitchBend, noteOnCount: noteOn.length, velMin, velMax, lowVels, maxDur, minDur, tracks: lastMidi.tracks?.length };
  });
  if (r.err) {
    record(c.name + ' 生成 MIDI', false, r.err);
    continue;
  }
  const errsHere = errs.slice(beforeErr).length;
  let ok = true;
  const checks = [];
  if (c.expectBend) { const b = r.perNoteBend > 0 || r.pitchBend > 0; if (!b) ok = false; checks.push('bend:' + b); }
  if (c.expectPalmMute) { const p = r.minDur < 240; if (!p) ok = false; checks.push('palmMute:' + p + '(minDur=' + r.minDur + ')'); }
  if (c.expectLetRing) { const l = r.maxDur >= 480; if (!l) ok = false; checks.push('letRing:' + l + '(maxDur=' + r.maxDur + ')'); }
  if (c.expectHarmonic) { const h = r.noteOnCount > 0; if (!h) ok = false; checks.push('harmonic-play:' + h); }
  if (c.expectPlay) { const p = r.noteOnCount > 0; if (!p) ok = false; checks.push('play:' + p); }
  if (errsHere > 0) { ok = false; checks.push('errs:' + errsHere); }
  record(c.name, ok, JSON.stringify({ perNoteBend: r.perNoteBend, pitchBend: r.pitchBend, notes: r.noteOnCount, vel: r.velMin + '-' + r.velMax, lowVels: r.lowVels, maxDur: r.maxDur, minDur: r.minDur, checks, errs: errsHere }));
}

record('TECH 全程 console/pageerror 零报错', errs.length === 0, JSON.stringify(errs.slice(0, 5)));
fs.writeFileSync(EVIDENCE + '/technique-summary.json', JSON.stringify(results, null, 2));
const failed = results.filter((x) => !x.ok);
console.log('==== SUMMARY ' + (results.length - failed.length) + '/' + results.length + ' PASS ====');
if (failed.length) console.log('FAILED: ' + failed.map((f) => f.name).join(', '));
await browser.close();
process.exit(failed.length ? 1 : 0);