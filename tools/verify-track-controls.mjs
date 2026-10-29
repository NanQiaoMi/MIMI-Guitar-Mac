// 音轨控件与乐器切换 UI 验收（修复 Svelte 响应式 + Instrument 自动化同步）
// 用法：node tools/verify-track-controls.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/track-controls';
fs.mkdirSync(EVIDENCE, { recursive: true });
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log((ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : ''));
}
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
await page.addInitScript(() => {
  window.__toWorker = [];
  window.__midiProgs = [];
  window.__seq = 0;
  function g(obj, key) { if (!obj) return undefined; return obj instanceof Map ? obj.get(key) : obj[key]; }
  function arr(obj, key) { const v = g(obj, key); return Array.isArray(v) ? v : []; }
  const KEEP = ['alphaSynth.setChannelMute', 'alphaSynth.setChannelSolo', 'alphaSynth.setChannelVolume', 'alphaSynth.loadMidi', 'alphaSynth.loadSoundFontBytes'];
  const origPM = Worker.prototype.postMessage;
  Worker.prototype.postMessage = function (data, ...rest) {
    try {
      if (data && typeof data === 'object' && typeof data.cmd === 'string' && KEEP.includes(data.cmd)) {
        let d = {};
        if (data.cmd === 'alphaSynth.setChannelMute') d = { ch: data.channel, v: data.mute };
        else if (data.cmd === 'alphaSynth.setChannelSolo') d = { ch: data.channel, v: data.solo };
        else if (data.cmd === 'alphaSynth.setChannelVolume') d = { ch: data.channel, v: data.volume };
        else if (data.cmd === 'alphaSynth.loadSoundFontBytes') d = { len: data.data ? data.data.byteLength : 0 };
        else if (data.cmd === 'alphaSynth.loadMidi') {
          d = { hasMidi: !!data.midi, progs: [] };
          if (data.midi) {
            for (const tr of arr(data.midi, 'tracks')) {
              for (const ev of arr(tr, 'events')) {
                if (g(ev, 'type') === 192) d.progs.push({ ch: g(ev, 'channel'), prog: g(ev, 'program') });
              }
            }
            window.__midiProgs.push(d.progs);
          }
        }
        window.__toWorker.push({ seq: ++window.__seq, cmd: data.cmd, d });
      }
    } catch (e) {}
    return origPM.call(this, data, ...rest);
  };
});
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push('err:' + m.text().slice(0, 140)); });
page.on('pageerror', (e) => errs.push('pageerror:' + String(e).slice(0, 160)));
await page.goto(BASE + '/tabs/1sdc49P3eKm', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => window.__api && window.__api._player && window.__api._player.isReadyForPlayback, { timeout: 45000 }).catch(() => {});
await page.waitForTimeout(3000);
record('C1 播放器就绪', await page.evaluate(() => window.__api._player.isReadyForPlayback), '');

await page.locator('button', { hasText: '音轨' }).first().click().catch(() => {});
await page.waitForTimeout(400);
await page.screenshot({ path: EVIDENCE + '/c1-track-panel.png' });

// C2 静音按钮文字翻转 + setChannelMute 命令
{
  await page.evaluate(() => { window.__toWorker.length = 0; window.__seq = 0; });
  await page.locator('button', { hasText: /^静音$/ }).first().click();
  await page.waitForTimeout(600);
  const after1 = await page.locator('button', { hasText: /^取消静音$/ }).count();
  const cmds1 = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelMute').map((x) => x.d));
  await page.locator('button', { hasText: /^取消静音$/ }).first().click();
  await page.waitForTimeout(600);
  const back = await page.locator('button', { hasText: /^静音$/ }).count();
  const cmds2 = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelMute').map((x) => x.d));
  const ok = after1 >= 1 && cmds1.length >= 1 && cmds1.every((d) => d.v === true) && back >= 1 && cmds2.some((d) => d.v === false);
  record('C2 静音按钮翻转（静音->取消静音->静音）且 setChannelMute 命令收发', ok, JSON.stringify({ after1, cmds1, back, cmds2, errs: errs.length }));
  await page.screenshot({ path: EVIDENCE + '/c2-mute-flip.png' });
}

// C3 独奏按钮翻转 + setChannelSolo 命令
{
  await page.evaluate(() => { window.__toWorker.length = 0; window.__seq = 0; });
  await page.locator('button', { hasText: /^独奏$/ }).first().click();
  await page.waitForTimeout(600);
  const after1 = await page.locator('button', { hasText: /^取消独奏$/ }).count();
  const cmds1 = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelSolo').map((x) => x.d));
  await page.locator('button', { hasText: /^取消独奏$/ }).first().click();
  await page.waitForTimeout(600);
  const back = await page.locator('button', { hasText: /^独奏$/ }).count();
  const cmds2 = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelSolo').map((x) => x.d));
  const ok = after1 >= 1 && cmds1.length >= 1 && cmds1.every((d) => d.v === true) && back >= 1 && cmds2.some((d) => d.v === false);
  record('C3 独奏按钮翻转且 setChannelSolo 命令收发', ok, JSON.stringify({ after1, cmds1, back, cmds2, errs: errs.length }));
  await page.screenshot({ path: EVIDENCE + '/c3-solo-flip.png' });
}

// C4 音量滑杆 50 -> setChannelVolume 0.5 且 UI 保持 50
{
  await page.evaluate(() => { window.__toWorker.length = 0; window.__seq = 0; });
  const slider = page.locator('input[type=range][min="0"][max="100"]').first();
  await slider.evaluate((el) => { el.value = '50'; el.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.waitForTimeout(600);
  const val = await slider.inputValue();
  const cmds = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelVolume').map((x) => x.d));
  const ok = val === '50' && cmds.length >= 1 && cmds.some((d) => Math.abs(d.v - 0.5) < 0.01);
  record('C4 音量滑杆 50 -> setChannelVolume 0.5 且 UI 保持 50', ok, JSON.stringify({ val, cmds, errs: errs.length }));
  await page.screenshot({ path: EVIDENCE + '/c4-volume.png' });
}

// C5 关闭音轨 = 静音（隐藏即静音）；重新打开 = 恢复（setChannelMute 命令 + UI）
{
  await page.evaluate(() => { window.__toWorker.length = 0; window.__seq = 0; });
  const res = await page.evaluate(() => {
    const chks = [...document.querySelectorAll('input[type=checkbox]')];
    const chk = chks.find((c) => {
      const row = c.closest('div');
      return row && [...row.querySelectorAll('button')].some((b) => ['静音', '取消静音', '独奏', '取消独奏'].includes(b.textContent.trim()));
    });
    if (!chk) return { err: 'no track checkbox' };
    const before = chk.checked;
    chk.click();
    return { before };
  });
  if (res.err) { record('C5 关闭音轨静音', false, res.err); } else {
    await page.waitForTimeout(1500);
    const after = await page.evaluate(() => {
      const chks = [...document.querySelectorAll('input[type=checkbox]')];
      const chk = chks.find((c) => {
        const row = c.closest('div');
        return row && [...row.querySelectorAll('button')].some((b) => ['静音', '取消静音', '独奏', '取消独奏'].includes(b.textContent.trim()));
      });
      return chk ? chk.checked : null;
    });
    const cmdsOff = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelMute').map((x) => x.d));
    const offOk = res.before === true && after === false && cmdsOff.length >= 1 && cmdsOff.every((d) => d.v === true) && errs.length === 0;
    await page.evaluate(() => { window.__toWorker.length = 0; window.__seq = 0; });
    await page.evaluate(() => {
      const chks = [...document.querySelectorAll('input[type=checkbox]')];
      const chk = chks.find((c) => {
        const row = c.closest('div');
        return row && [...row.querySelectorAll('button')].some((b) => ['静音', '取消静音', '独奏', '取消独奏'].includes(b.textContent.trim()));
      });
      if (chk && !chk.checked) chk.click();
    });
    await page.waitForTimeout(1500);
    const back = await page.evaluate(() => {
      const chks = [...document.querySelectorAll('input[type=checkbox]')];
      const chk = chks.find((c) => {
        const row = c.closest('div');
        return row && [...row.querySelectorAll('button')].some((b) => ['静音', '取消静音', '独奏', '取消独奏'].includes(b.textContent.trim()));
      });
      return chk ? chk.checked : null;
    });
    const cmdsOn = await page.evaluate(() => window.__toWorker.filter((x) => x.cmd === 'alphaSynth.setChannelMute').map((x) => x.d));
    const onOk = back === true && cmdsOn.some((d) => d.v === false) && errs.length === 0;
    record('C5 关闭音轨=静音/重开=恢复（setChannelMute 收发）', offOk && onOk, JSON.stringify({ before: res.before, after, cmdsOff, back, cmdsOn, errs: errs.length }));
    await page.screenshot({ path: EVIDENCE + '/c5-track-off-mute.png' });
  }
}

// C6 乐器切换：UI/program/自动化/sf2/MIDI 全链路生效（无旧音色覆盖）
{
  await page.evaluate(() => { window.__toWorker.length = 0; window.__midiProgs.length = 0; window.__seq = 0; });
  await page.locator('button', { hasText: '乐器' }).first().click().catch(() => {});
  await page.waitForTimeout(400);
  const sw = await page.evaluate(() => {
    const api = window.__api;
    const cur = api.score.tracks[0].playbackInfo.program;
    const target = cur === 25 ? 41 : 25;
    const sel = [...document.querySelectorAll('select')].find((s) => Number(s.value) === cur);
    if (!sel) return { err: 'select not found', cur, target };
    sel.value = String(target);
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    return { cur, target };
  });
  if (sw.err) { record('C6 乐器切换', false, sw.err); } else {
    await page.waitForTimeout(7000);
    const res = await page.evaluate(() => {
      const sel = [...document.querySelectorAll('select')].find((s) => s.options && s.options.length > 10);
      const t = window.__api.score.tracks[0];
      let auto = null;
      for (const st of t.staves) for (const bar of st.bars) for (const v of bar.voices) for (const beat of v.beats) for (const a of (beat.automations || [])) if (a.type === 2) { auto = a.value; break; }
      return { selectValue: sel ? sel.value : null, prog: t.playbackInfo.program, auto, cmds: window.__toWorker, midiProgs: window.__midiProgs };
    });
    const lastMidi = res.midiProgs[res.midiProgs.length - 1] || [];
    const ch01 = lastMidi.filter((p) => p.ch === 0 || p.ch === 1);
    const progOk = res.prog === sw.target;
    const uiOk = String(res.selectValue) === String(sw.target);
    const sfOk = res.cmds.some((x) => x.cmd === 'alphaSynth.loadSoundFontBytes' && x.d.len > 0);
    const midiOk = res.cmds.some((x) => x.cmd === 'alphaSynth.loadMidi');
    const autoOk = res.auto === sw.target;
    const noOldOverride = ch01.length > 0 && ch01.every((p) => p.prog === sw.target);
    const ok = progOk && uiOk && sfOk && midiOk && autoOk && noOldOverride && errs.length === 0;
    record('C6 乐器切换：UI/program/自动化/sf2/MIDI 全链路生效（无旧音色覆盖）', ok, JSON.stringify({ target: sw.target, selectValue: res.selectValue, prog: res.prog, auto: res.auto, ch01, loadSf: res.cmds.filter((x) => x.cmd === 'alphaSynth.loadSoundFontBytes').map((x) => x.d.len), loadMidi: res.cmds.filter((x) => x.cmd === 'alphaSynth.loadMidi').length, errs: errs.length }));
    await page.screenshot({ path: EVIDENCE + '/c6-instrument-switch.png' });
  }
}

// C7 切换谱面模式后乐器保持（rebuildTrackState 同步 Instrument 自动化，不回落旧音色）
{
  await page.evaluate(() => { window.__midiProgs.length = 0; window.__seq = 0; });
  await page.evaluate(() => {
    const b = [...document.querySelectorAll('button')].find((x) => !x.disabled && x.textContent.trim() === '全部六线谱');
    if (b) b.click();
  });
  await page.waitForTimeout(7000);
  const res = await page.evaluate(() => {
    const t = window.__api.score.tracks[0];
    let auto = null;
    for (const st of t.staves) for (const bar of st.bars) for (const v of bar.voices) for (const beat of v.beats) for (const a of (beat.automations || [])) if (a.type === 2) { auto = a.value; break; }
    const last = window.__midiProgs[window.__midiProgs.length - 1] || [];
    return { prog: t.playbackInfo.program, auto, ch01: last.filter((p) => p.ch === 0 || p.ch === 1) };
  });
  const ok = res.prog === res.auto && res.auto !== null && res.ch01.length > 0 && res.ch01.every((p) => p.prog === res.prog) && errs.length === 0;
  record('C7 切谱面模式后乐器保持（自动化与 MIDI 不回落旧音色）', ok, JSON.stringify({ prog: res.prog, auto: res.auto, ch01: res.ch01, errs: errs.length }));
  await page.screenshot({ path: EVIDENCE + '/c7-mode-keeps-instrument.png' });
}

record('C8 全程 console/pageerror 零报错', errs.length === 0, JSON.stringify(errs.slice(0, 8)));
const failed = results.filter((r) => !r.ok);
console.log('==== SUMMARY ' + (results.length - failed.length) + '/' + results.length + ' PASS ====');
if (failed.length) console.log('FAILED: ' + failed.map((f) => f.name).join(', '));
await browser.close();
process.exit(failed.length ? 1 : 0);
