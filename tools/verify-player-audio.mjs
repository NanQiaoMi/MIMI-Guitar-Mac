
// 播放器音频生效专项验收（转调/变调夹/降半调/乐器切换 → loadMidiForScore 重生成 + 播放音高正确）
// 用法：node tools/verify-player-audio.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/audio';
fs.mkdirSync(EVIDENCE, { recursive: true });

const results = [];
const OUT_LOG = 'tools/verify-player-audio.out.log';
fs.writeFileSync(OUT_LOG, '');
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  const line = (ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : '');
  console.log(line);
  fs.appendFileSync(OUT_LOG, line + '\n');
}

const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push('err:' + m.text().slice(0, 160)); });
page.on('pageerror', (e) => errs.push('pageerror:' + String(e).slice(0, 160)));

await page.goto(BASE + '/tabs/1sdc49P3eKm', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => window.__api && document.querySelector('#score-scroll svg'), { timeout: 30000 }).catch(() => {});
await page.waitForTimeout(4000);

// 安装捕获器：loadMidiFile（记录 MIDI 文件）、loadMidiForScore（计数）、applyTranspositionPitches（记录移调表）
await page.evaluate(() => {
  const api = window.__api;
  window.__cap = { count: 0, files: [], applied: [] };
  const player = api._player;
  const origLMF = player.loadMidiFile.bind(player);
  player.loadMidiFile = (file) => { window.__cap.files.push(file); return origLMF(file); };
  const origLMS = api.loadMidiForScore.bind(api);
  api.loadMidiForScore = () => { window.__cap.count++; return origLMS(); };
  const origATP = player.applyTranspositionPitches.bind(player);
  player.applyTranspositionPitches = (m) => { window.__cap.applied.push(m ? Object.fromEntries([...m.entries()]) : null); return origATP(m); };
  // 记录第一个多音符和弦（用于音程保持断言）
  outer: for (const t of api.score.tracks) for (const st of t.staves) for (const b of st.bars) for (const v of b.voices) for (const beat of v.beats) {
    if (beat.notes && beat.notes.length >= 3) { window.__chordNotes = beat.notes; break outer; }
  }
});

async function clickBtn(matcher) {
  return page.evaluate((m) => {
    const b = [...document.querySelectorAll('button')].find((x) => !x.disabled && (x.textContent.includes(m) || (x.getAttribute('aria-label') || '').includes(m)));
    if (!b) throw new Error('btn not found: ' + m);
    b.click();
  }, matcher);
}
async function clickCapoOption(label) {
  await clickBtn('变调夹');
  await page.waitForTimeout(200);
  await page.evaluate((lb) => {
    const o = [...document.querySelectorAll('button[role="option"]')].find((x) => x.textContent.trim() === lb);
    if (!o) throw new Error('capo option not found: ' + lb);
    o.click();
  }, label);
}
async function waitCount(min, timeout = 30000) {
  await page.waitForFunction((m) => window.__cap && window.__cap.count >= m, min, { timeout });
}
async function waitReady() {
  await page.waitForFunction(() => window.__api._player.isReadyForPlayback, null, { timeout: 15000 });
}
async function isPlaying() {
  return page.evaluate(() => {
    const b = [...document.querySelectorAll('button')].find((x) => (x.textContent || '').includes('暂停') || ((x.getAttribute('aria-label') || '').includes('暂停')));
    return !!b;
  });
}
async function noteKeys() {
  return page.evaluate(() => {
    const f = window.__cap.files[window.__cap.files.length - 1];
    if (!f) return null;
    return f.tracks[0].events.filter((e) => e.type === 128).slice(0, 8).map((e) => e.noteKey);
  });
}
async function appliedPitches() {
  return page.evaluate(() => window.__cap.applied[window.__cap.applied.length - 1] || null);
}
async function modelCapo() {
  return page.evaluate(() => window.__api.score.tracks.flatMap((t) => t.staves).map((s) => s.capo).slice(0, 2));
}
async function modelTP() {
  return page.evaluate(() => window.__api.score.tracks.flatMap((t) => t.staves).map((s) => s.transpositionPitch).slice(0, 2));
}
function allSame(arr) { return arr.length > 0 && arr.every((v) => v === arr[0]); }

// A1 基线：捕获器安装、播放器就绪、初始无计数
{
  const ok = await page.evaluate(() => {
    const api = window.__api;
    return typeof api.loadMidiForScore === 'function' && api._player.isReadyForPlayback && window.__cap.count === 0 && !!window.__chordNotes;
  });
  record('A1 播放器就绪 + 捕获器安装', ok, JSON.stringify({ ready: await page.evaluate(() => window.__api._player.isReadyForPlayback), chordNotes: await page.evaluate(() => window.__chordNotes.length) }));
}

// 基线 MIDI：触发一次「不夹」reload 拿到 base noteKeys
await clickCapoOption('不夹');
await waitCount(1); await waitReady(); await page.waitForTimeout(800);
const baseKeys = await noteKeys();
record('A2 基线 MIDI 捕获（capo=0, transpose=0）', !!baseKeys && baseKeys.length >= 5, JSON.stringify({ keys: baseKeys, count: await page.evaluate(() => window.__cap.count) }));

// A3 变调夹 3品 → MIDI noteKeys 精确 +3
await clickCapoOption('3品');
await waitCount(2); await waitReady(); await page.waitForTimeout(800);
{
  const k = await noteKeys();
  const diffs = baseKeys.map((b, i) => k[i] - b);
  const capo = await modelCapo();
  const ok = allSame(diffs) && diffs[0] === 3 && capo[0] === 3;
  record('A3 变调夹 3品：MIDI 音高 +3', ok, JSON.stringify({ base: baseKeys, keys: k, diffs, capo }));
}

// A4 降半调调弦 → MIDI noteKeys 精确 -1
await clickCapoOption('降半调调弦');
await waitCount(3); await waitReady(); await page.waitForTimeout(800);
{
  const k = await noteKeys();
  const diffs = baseKeys.map((b, i) => k[i] - b);
  const capo = await modelCapo();
  const ok = allSame(diffs) && diffs[0] === -1 && capo[0] === -1;
  record('A4 降半调调弦：MIDI 音高 -1', ok, JSON.stringify({ diffs, capo }));
}

// 复位 capo=0，然后整曲转调
await clickCapoOption('不夹');
await waitCount(4); await waitReady(); await page.waitForTimeout(600);

// A5 整曲转调 +1 → player.applyTranspositionPitches 收到 {ch:+1}
await clickBtn('转调升高半音');
await waitCount(5); await waitReady(); await page.waitForTimeout(800);
{
  const p = await appliedPitches();
  const tp = await modelTP();
  const vals = Object.values(p || {});
  const ok = !!p && allSame(vals) && vals[0] === 1 && tp[0] === -1;
  record('A5 整曲转调 +1：player 移调表 +1', ok, JSON.stringify({ applied: p, modelTP: tp }));
}

// A6 整曲转调 +2 → {+2}；复位 → {0}
await clickBtn('转调升高半音');
await waitCount(6); await waitReady(); await page.waitForTimeout(600);
const p2 = await appliedPitches();
await clickBtn('转调降低半音');
await clickBtn('转调降低半音');
await waitCount(8); await waitReady(); await page.waitForTimeout(800);
{
  const p0 = await appliedPitches();
  const tp = await modelTP();
  const ok = p0 && Object.values(p0).every((v) => v === 0) && tp.every((v) => v === 0) && p2 && p2[Object.keys(p2)[0]] === 2;
  record('A6 转调 +2 → 归零：移调表 2 → 0', ok, JSON.stringify({ plusTwo: p2, afterReset: p0, modelTP: tp }));
}

// A7 和弦音程保持：转调 +2 前后每个音符平移 +2
{
  const before = await page.evaluate(() => window.__chordNotes.map((n) => n.calculateRealValue(true, true)));
  await clickBtn('转调升高半音');
  await clickBtn('转调升高半音');
  await waitCount(10); await waitReady(); await page.waitForTimeout(600);
  const after = await page.evaluate(() => window.__chordNotes.map((n) => n.calculateRealValue(true, true)));
  const diffs = after.map((v, i) => v - before[i]);
  const ok = before.length >= 3 && allSame(diffs) && diffs[0] === 2;
  record('A7 和弦音程保持：转调 +2 各音符平移一致', ok, JSON.stringify({ before, after, diffs }));
  // 复位转调
  await clickBtn('转调降低半音');
  await clickBtn('转调降低半音');
  await waitCount(12); await waitReady(); await page.waitForTimeout(600);
}

// A8 纯显示操作不触发 MIDI 重生成（字体缩放 / 和弦模式 / 数字谱）
{
  const c0 = await page.evaluate(() => window.__cap.count);
  // 字体缩放（纯显示，re-render 但不应 reloadMidi）
  await page.locator('input[type="range"][min="0.6"]').evaluate((el) => { el.value = '1.1'; el.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.waitForTimeout(1200);
  const c1 = await page.evaluate(() => window.__cap.count);
  // 和弦模式 → 仅字母（re-render，不应 reloadMidi）
  await clickBtn('仅字母');
  await page.waitForTimeout(1200);
  const c2 = await page.evaluate(() => window.__cap.count);
  // 数字谱（纯 CSS 开关，无 re-render）
  await clickBtn('数字谱');
  await page.waitForTimeout(600);
  const c3 = await page.evaluate(() => window.__cap.count);
  const ok = c0 === c1 && c1 === c2 && c2 === c3;
  record('A8 纯显示操作不误刷新 MIDI', ok, JSON.stringify({ before: c0, afterFont: c1, afterChordMode: c2, afterNumberTab: c3 }));
  // 恢复显示状态：字体 1.0、和弦模式 diagram、数字谱关
  await page.locator('input[type="range"][min="0.6"]').evaluate((el) => { el.value = '1'; el.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.waitForTimeout(800);
  await clickBtn('字母+指法图');
  await page.waitForTimeout(800);
  await clickBtn('数字谱');
  await page.waitForTimeout(400);
}

// A9 播放中切变调夹：位置不重置、续播、MIDI 刷新
{
  await clickBtn('播放');
  await page.waitForTimeout(1500);
  const playing1 = await isPlaying();
  const tick1 = await page.evaluate(() => window.__api.tickPosition);
  const c1 = await page.evaluate(() => window.__cap.count);
  await clickCapoOption('2品');
  await waitCount(c1 + 1); await waitReady(); await page.waitForTimeout(1000);
  const playing2 = await isPlaying();
  const tick2 = await page.evaluate(() => window.__api.tickPosition);
  const capo = await modelCapo();
  const ok = playing1 && playing2 && tick2 >= tick1 && capo[0] === 2;
  record('A9 播放中切变调夹：位置保留 + 续播', ok, JSON.stringify({ playing1, tick1, playing2, tick2, capo }));
  // 复位 capo 不夹
  await clickCapoOption('不夹');
  await waitCount(c1 + 2); await waitReady(); await page.waitForTimeout(600);
}

// A10 播放中转调：位置不重置、移调表更新
{
  const tick1 = await page.evaluate(() => window.__api.tickPosition);
  const c1 = await page.evaluate(() => window.__cap.count);
  await clickBtn('转调升高半音');
  await waitCount(c1 + 1); await waitReady(); await page.waitForTimeout(800);
  const playing = await isPlaying();
  const tick2 = await page.evaluate(() => window.__api.tickPosition);
  const p = await appliedPitches();
  const vals = Object.values(p || {});
  const ok = playing && tick2 >= tick1 && allSame(vals) && vals[0] === 1;
  record('A10 播放中转调：位置保留 + 移调表更新', ok, JSON.stringify({ tick1, tick2, playing, applied: p }));
  // 复位转调
  await clickBtn('转调降低半音');
  await waitCount(c1 + 2); await waitReady(); await page.waitForTimeout(600);
  await clickBtn('重来');
  await page.waitForTimeout(500);
}

// A11 乐器切换：program 改变 + MIDI 重生成 + 新 program 进入 MIDI
{
  const c1 = await page.evaluate(() => window.__cap.count);
  // 先打开「乐器」面板，select 才存在于 DOM
  await clickBtn('乐器');
  await page.waitForTimeout(500);
  const res = await page.evaluate(() => {
    const api = window.__api;
    const cur = api.score.tracks[0].playbackInfo.program;
    const target = cur === 25 ? 41 : 25;
    const sel = [...document.querySelectorAll('select')].find((s) => Number(s.value) === cur);
    if (!sel) return { err: 'select not found', cur };
    sel.value = String(target);
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    return { cur, target };
  });
  if (res.err) throw new Error(res.err);
  await waitCount(c1 + 1, 45000); await waitReady(); await page.waitForTimeout(1500);
  const prog = await page.evaluate((tg) => window.__api.score.tracks[0].playbackInfo.program === tg, res.target);
  const inMidi = await page.evaluate((tg) => {
    const f = window.__cap.files[window.__cap.files.length - 1];
    if (!f) return false;
    return f.tracks[0].events.some((e) => e.type === 192 && e.program === tg);
  }, res.target);
  const ok = !!res.target && prog && inMidi;
  record('A11 乐器切换：program 生效且进入重生成 MIDI', ok, JSON.stringify({ cur: res.cur, target: res.target, modelOk: prog, inMidi, count: await page.evaluate(() => window.__cap.count) }));
}

// A12 全程控制台/页面错误为零
{
  const ok = errs.length === 0;
  record('A12 全程 console/pageerror 零报错', ok, JSON.stringify(errs.slice(0, 5)));
}

// 截图证据
await page.waitForTimeout(800);
const sc = await page.$('#score-scroll');
if (sc) await sc.screenshot({ path: EVIDENCE + '/audio-final.png' });

const failed = results.filter((r) => !r.ok);
console.log('==== SUMMARY ' + (results.length - failed.length) + '/' + results.length + ' PASS ====');
if (failed.length) console.log('FAILED: ' + failed.map((f) => f.name).join(', '));
await browser.close();
process.exit(failed.length ? 1 : 0);

