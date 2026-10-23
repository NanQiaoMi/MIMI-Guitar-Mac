// 乐器切换音频生效专项回归：验证 play 在 worker 完成新 MIDI 加载（midiLoaded）之后才发送
// 用法：node tools/verify-instrument-switch.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/instrument-switch';
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
  window.__fromWorker = [];
  window.__seq = 0;
  const KEEP = ['alphaSynth.play', 'alphaSynth.playPause', 'alphaSynth.pause', 'alphaSynth.stop', 'alphaSynth.loadMidi', 'alphaSynth.loadSoundFontBytes', 'alphaSynth.applyTranspositionPitches', 'alphaSynth.setTickPosition', 'alphaSynth.midiLoaded', 'alphaSynth.readyForPlayback', 'alphaSynth.soundFontLoaded', 'alphaSynth.playerStateChanged'];
  const origPM = Worker.prototype.postMessage;
  Worker.prototype.postMessage = function (data, ...rest) {
    try {
      if (data && typeof data === 'object' && typeof data.cmd === 'string' && KEEP.includes(data.cmd)) {
        const d = data.cmd === 'alphaSynth.loadSoundFontBytes' ? { len: data.data ? data.data.byteLength : 0 } : data.cmd === 'alphaSynth.loadMidi' ? { hasMidi: !!data.midi } : data.cmd === 'alphaSynth.setTickPosition' ? { v: data.value } : {};
        window.__toWorker.push({ seq: ++window.__seq, cmd: data.cmd, d });
      }
    } catch (e) {}
    return origPM.call(this, data, ...rest);
  };
  const OrigWorker = window.Worker;
  window.Worker = function (...args) {
    const w = new OrigWorker(...args);
    const origAdd = w.addEventListener.bind(w);
    w.addEventListener = (type, fn, ...rest) => {
      if (type === 'message') {
        const wrapped = (e) => {
          try {
            const d = e.data;
            if (d && typeof d === 'object' && typeof d.cmd === 'string' && KEEP.includes(d.cmd)) {
              window.__fromWorker.push({ seq: ++window.__seq, cmd: d.cmd });
            }
          } catch (e2) {}
          return fn(e);
        };
        return origAdd(type, wrapped, ...rest);
      }
      return origAdd(type, fn, ...rest);
    };
    return w;
  };
  window.Worker.prototype = OrigWorker.prototype;
});
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 160)); });
page.on('pageerror', (e) => errs.push(String(e).slice(0, 160)));
await page.goto(BASE + '/tabs/1sdc49P3eKm', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => window.__api && window.__api._player && window.__api._player.isReadyForPlayback, { timeout: 45000 }).catch(() => {});
await page.waitForTimeout(3000);
record('I1 播放器就绪', await page.evaluate(() => window.__api._player.isReadyForPlayback), '');
await page.evaluate(() => { window.__toWorker.length = 0; window.__fromWorker.length = 0; window.__seq = 0; });
await page.evaluate(() => window.__api.playPause());
await page.waitForTimeout(1500);
const playing0 = await page.evaluate(() => window.__api.player.state === 1);
await page.evaluate(() => {
  const b = [...document.querySelectorAll('button')].find((x) => !x.disabled && x.textContent.includes('乐器'));
  if (b) b.click();
});
await page.waitForTimeout(300);
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
if (sw.err) { record('I2 切换操作', false, sw.err); } else {
  await page.waitForTimeout(7000);
  const res = await page.evaluate(() => ({
    playing: window.__api.player.state === 1,
    ready: window.__api._player.isReadyForPlayback,
    prog: window.__api.score.tracks[0].playbackInfo.program,
    to: window.__toWorker,
    from: window.__fromWorker,
  }));
  const merged = [...res.to.map((x) => ({ ...x, dir: 'to' })), ...res.from.map((x) => ({ ...x, dir: 'from' }))].sort((a, b) => a.seq - b.seq);
  const byCmd = (cmd) => merged.filter((x) => x.cmd === cmd).map((x) => x.seq);
  const seqOf = (cmd, nth) => byCmd(cmd)[nth];
  const loadMidi = seqOf('alphaSynth.loadMidi', 0);
  const midiLoaded = seqOf('alphaSynth.midiLoaded', 0);
  const play = seqOf('alphaSynth.play', 0);
  const progOk = res.prog === sw.target;
  const playingOk = playing0 && res.playing;
  const raceOk = loadMidi !== undefined && midiLoaded !== undefined && play !== undefined && loadMidi < midiLoaded && play > midiLoaded;
  const sfCount = byCmd('alphaSynth.loadSoundFontBytes').length;
  const dedupeOk = sfCount <= 1;
  record('I2 播放中切乐器：program 更新', progOk, JSON.stringify({ cur: sw.cur, target: sw.target, prog: res.prog }));
  record('I3 播放恢复且未中断', playingOk, JSON.stringify({ playing0, playing: res.playing, ready: res.ready }));
  record('I4 竞态修复：play 在 midiLoaded 之后', raceOk, JSON.stringify({ loadMidiSeq: loadMidi, midiLoadedSeq: midiLoaded, playSeq: play, seq: merged.map((x) => x.seq + ':' + x.cmd).join(' > ') }));
  record('I5 音源去重：本次切换仅加载新增 sf2', dedupeOk, JSON.stringify({ loadSoundFontCount: sfCount, bytes: byCmd('alphaSynth.loadSoundFontBytes').map((s) => res.to.find((x) => x.seq === s).d.len) }));
}
record('I6 全程 console/pageerror 零报错', errs.length === 0, JSON.stringify(errs.slice(0, 5)));
const sc = await page.$('#score-scroll');
if (sc) await sc.screenshot({ path: EVIDENCE + '/instrument-switch-final.png' });
fs.writeFileSync(EVIDENCE + '/sequence.json', JSON.stringify({ to: await page.evaluate(() => window.__toWorker), from: await page.evaluate(() => window.__fromWorker) }, null, 2));
const failed = results.filter((r) => !r.ok);
console.log('==== SUMMARY ' + (results.length - failed.length) + '/' + results.length + ' PASS ====');
if (failed.length) console.log('FAILED: ' + failed.map((f) => f.name).join(', '));
await browser.close();
process.exit(failed.length ? 1 : 0);