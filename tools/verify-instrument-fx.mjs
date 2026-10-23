// 乐器效果补齐专项回归：验证全 129 program 音源覆盖 + 切换不再回退钢琴 + 无控制台报错
// 用法：node tools/verify-instrument-fx.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/instrument-fx';
fs.mkdirSync(EVIDENCE, { recursive: true });
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log((ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : ''));
}
const TARGETS = [17, 40, 49, 56, 64, 73, 108, 128]; // 此前缺失的代表性音色 + 鼓组
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 200)); });
page.on('pageerror', (e) => errs.push(String(e).slice(0, 200)));
const sf2Requests = [];
page.on('request', (r) => { const u = r.url(); if (/\/storage\/soundfonts\/\d+\.sf2$/.test(u)) sf2Requests.push(u.split('/').pop()); });
await page.goto(BASE + '/tabs/1sdc49P3eKm', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => window.__api && window.__api._player && window.__api._player.isReadyForPlayback, { timeout: 60000 }).catch(() => {});
await page.waitForTimeout(2500);
record('F1 播放器就绪', await page.evaluate(() => window.__api._player.isReadyForPlayback), '');

// 打开乐器面板
await page.evaluate(() => {
  const b = [...document.querySelectorAll('button')].find((x) => !x.disabled && x.textContent.includes('乐器'));
  if (b) b.click();
});
await page.waitForTimeout(400);

// index.json 完整性（页面内 fetch）
const manifest = await page.evaluate(async () => {
  try {
    const res = await fetch('/storage/soundfonts/index.json');
    const arr = await res.json();
    const missing = [];
    for (let i = 0; i <= 128; i++) if (!arr.includes(i)) missing.push(i);
    return { len: arr.length, missing };
  } catch (e) { return { err: String(e) }; }
});
record('F2 index.json 覆盖 0-128 全量', manifest.len === 129 && manifest.missing.length === 0, JSON.stringify(manifest));

// 逐个切换乐器并断言加载了对应 sf2 且未回退 0.sf2
let switchOk = true;
const switchDetails = [];
const beforeCount = sf2Requests.length;
for (const prog of TARGETS) {
  const beforeSwitch = sf2Requests.length;
  const r = await page.evaluate((target) => {
    const api = window.__api;
    const cur = api.score.tracks[0].playbackInfo.program;
    const sel = [...document.querySelectorAll('select')].find((s) => Number(s.value) === cur);
    if (!sel) return { err: 'select not found', cur, target };
    sel.value = String(target);
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    return { cur, target };
  }, prog);
  if (r.err) { switchOk = false; switchDetails.push({ prog, err: r.err }); continue; }
  await page.waitForTimeout(3500);
  const newRequests = sf2Requests.slice(beforeSwitch);
  const got = newRequests.find((f) => f === `${prog}.sf2`);
  const fellBack = newRequests.includes('0.sf2');
  const liveProg = await page.evaluate(() => window.__api.score.tracks[0].playbackInfo.program);
  const ok = !!got && !fellBack && liveProg === prog;
  if (!ok) switchOk = false;
  switchDetails.push({ prog, got, fellBack, liveProg, newRequests });
  record('F3 切至 #' + prog + ' 加载对应 sf2 且不回退钢琴', ok, JSON.stringify({ got, fellBack, liveProg }));
}

// 鼓组单独断言（走通道 9/9 映射 128 的逻辑）
record('F4 鼓组(128) 音源加载', sf2Requests.includes('128.sf2'), JSON.stringify(sf2Requests.filter((f) => f === '128.sf2')));

record('F5 全程 console/pageerror 零报错', errs.length === 0, JSON.stringify(errs.slice(0, 5)));
fs.writeFileSync(EVIDENCE + '/sf2-requests.json', JSON.stringify(sf2Requests, null, 2));
fs.writeFileSync(EVIDENCE + '/switch-details.json', JSON.stringify(switchDetails, null, 2));
await page.screenshot({ path: EVIDENCE + '/instrument-fx-final.png', fullPage: false });
const failed = results.filter((r) => !r.ok);
console.log('==== SUMMARY ' + (results.length - failed.length) + '/' + results.length + ' PASS ====');
if (failed.length) console.log('FAILED: ' + failed.map((f) => f.name).join(', '));
await browser.close();
process.exit(failed.length ? 1 : 0);