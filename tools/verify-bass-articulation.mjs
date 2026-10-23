// 贝斯击勾 tap/slap/pop MIDI 力度增强专项回归
// 对照实验：同一谱面分别以「增强开/关」生成 MIDI，断言击勾拍音符力度差 == 增强值
// 用法：node tools/verify-bass-articulation.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/bass-articulation';
fs.mkdirSync(EVIDENCE, { recursive: true });
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log((ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : ''));
}
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 200)); });
page.on('pageerror', (e) => errs.push(String(e).slice(0, 200)));
await page.goto(BASE + '/tabs/oOEvk5YC', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => window.__api && window.__api._player && window.__api._player.isReadyForPlayback, { timeout: 60000 }).catch(() => {});
await page.waitForTimeout(3000);
record('B1 播放器就绪', await page.evaluate(() => window.__api._player.isReadyForPlayback), '');

const r = await page.evaluate(async () => {
  const api = window.__api;
  function capture() {
    return new Promise((resolve) => {
      let lastMidi = null;
      api.midiLoad.on((f) => { lastMidi = f; });
      api.loadMidiForScore();
      const c = () => lastMidi ? resolve(lastMidi) : setTimeout(c, 50);
      c();
      setTimeout(() => resolve(lastMidi), 8000);
    });
  }
  // 统计击勾拍 (track, tick, boost)
  const beats = [];
  for (const t of api.score.tracks) {
    for (const st of t.staves || []) {
      for (const b of st.bars || []) {
        for (const v of b.voices || []) {
          for (const beat of v.beats || []) {
            const boost = beat.slap ? 22 : beat.pop ? 18 : beat.tap ? 10 : 0;
            if (!boost) continue;
            const tick = api.tickCache?.getBeatStart(beat) ?? 0;
            if (tick <= 0) continue;
            beats.push({ track: t.index, tick, boost, slap: !!beat.slap, pop: !!beat.pop });
          }
        }
      }
    }
  }
  const boosted = await capture();
  window.__disableBassBoost = true;
  const plain = await capture();
  function velMap(midi) {
    const m = new Map();
    for (const mt of midi.tracks || []) for (const ev of mt.events || []) {
      if (ev.type === 128) m.set(ev.track + ':' + ev.tick, ev.noteVelocity);
    }
    return m;
  }
  const bm = velMap(boosted);
  const pm = velMap(plain);
  let checked = 0, okDelta = 0;
  const samples = [];
  for (const bt of beats) {
    const k = bt.track + ':' + bt.tick;
    const p = pm.get(k);
    const b = bm.get(k);
    if (p === undefined || b === undefined) continue;
    checked++;
    const expect = Math.min(127, p + bt.boost);
    const ok = b === expect;
    if (ok) okDelta++;
    if (samples.length < 6) samples.push({ track: bt.track, tick: bt.tick, boost: bt.boost, slap: bt.slap, pop: bt.pop, plain: p, boosted: b, expect });
  }
  return {
    beatCount: beats.length, checked, okDelta, samples,
    slapCount: beats.filter((b) => b.slap).length, popCount: beats.filter((b) => b.pop).length,
  };
});
if (r.err) {
  record('B2 捕获 MIDI', false, r.err);
} else {
  record('B2 检测到击勾拍（slap/pop/tap）', r.beatCount > 0, JSON.stringify({ beats: r.beatCount, slap: r.slapCount, pop: r.popCount }));
  record('B3 击勾拍力度差 = 增强值（关 vs 开）', r.checked > 0 && r.okDelta === r.checked, JSON.stringify({ checked: r.checked, okDelta: r.okDelta, samples: r.samples.slice(0, 4) }));
}
record('B4 全程 console/pageerror 零报错', errs.length === 0, JSON.stringify(errs.slice(0, 5)));
fs.writeFileSync(EVIDENCE + '/bass-detail.json', JSON.stringify(r, null, 2));
await page.screenshot({ path: EVIDENCE + '/bass-final.png' });
const failed = results.filter((x) => !x.ok);
console.log('==== SUMMARY ' + (results.length - failed.length) + '/' + results.length + ' PASS ====');
if (failed.length) console.log('FAILED: ' + failed.map((f) => f.name).join(', '));
await browser.close();
process.exit(failed.length ? 1 : 0);