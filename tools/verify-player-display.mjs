// 播放器对齐专项验收（变调夹/降半调调弦/整曲转调/音符高亮/数字谱/显示细节）
// 用法：node tools/verify-player-display.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/display';
fs.mkdirSync(EVIDENCE, { recursive: true });

const results = [];
const OUT_LOG = 'tools/verify-player-display.out.log';
fs.writeFileSync(OUT_LOG, '');
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  const line = (ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : '');
  console.log(line);
  fs.appendFileSync(OUT_LOG, line + '\n');
}

const browser = await chromium.launch({
  executablePath: EXE, headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'],
});

async function openTab(page) {
  const errs = [];
  const onC = (m) => { if (m.type() === 'error') errs.push('err:' + m.text().slice(0, 160)); };
  const onE = (e) => errs.push('pageerror:' + String(e).slice(0, 160));
  page.on('console', onC);
  page.on('pageerror', onE);
  await page.goto(BASE + '/tabs/1sdc49P3eKm', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => {
    const b = [...document.querySelectorAll('button')].find((x) => /播放|暂停|音源/.test(x.textContent) && !x.disabled);
    return !!b;
  }, { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1500);
  return { errs, off: () => { page.removeListener('console', onC); page.removeListener('pageerror', onE); } };
}

async function clickBtn(page, matcher) {
  return page.evaluate((m) => {
    const b = [...document.querySelectorAll('button')].find((x) => !x.disabled && (x.textContent.includes(m) || (x.getAttribute('aria-label') || '').includes(m)));
    if (!b) throw new Error('btn not found: ' + m);
    b.click();
  }, matcher);
}

async function readFrets(page) {
  return page.evaluate(() => {
    const sc = document.querySelector('#score-scroll');
    if (!sc) return [];
    const bars = [...sc.querySelectorAll('g')].filter((g) => /^b\d+$/.test(g.getAttribute('class') || ''));
    return bars.slice(0, 8).map((g) => {
      const t = [...g.children].find((c) => c.tagName === 'text' && /^[0-9]+$/.test(c.textContent.trim()));
      return t ? t.textContent.trim() : null;
    });
  });
}

async function readDisplayState(page) {
  return page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    const showNum = window.__api.score.tracks.flatMap((t) => t.staves.map((s) => !!s.showNumbered));
    let multi = 0;
    let digits = 0;
    for (const g of sc.querySelectorAll('g')) {
      const cls = g.getAttribute('class') || '';
      if (!/^b\d+$/.test(cls)) continue;
      const nums = [...g.children].filter((c) => c.tagName === 'text' && /^[0-9]+$/.test((c.textContent || '').trim()));
      const xs = {};
      for (const n of nums) {
        digits++;
        const x = Math.round(parseFloat(n.getAttribute('x') || '0') * 10);
        xs[x] = (xs[x] || 0) + 1;
      }
      for (const k in xs) if (xs[k] > 1) multi++;
    }
    return {
      hasNumbered: showNum.some(Boolean),
      showNum,
      multi,
      digits,
      scrollH: sc.scrollHeight,
    };
  });
}

const EXPECTED_CAPO_ITEMS = ['降半调调弦', '不夹', '1品', '2品', '3品', '4品', '5品', '6品'];

// ---------- 页面 A：显示状态（数字谱 / 变调夹 / 降半调 / 转调） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);

  // A1 数字谱默认开启：简谱（numbered）行可见，六线谱和弦品数完整
  const off0 = await readDisplayState(page);
  await page.screenshot({ path: EVIDENCE + '/a1-number-default.png' });
  record('A1 数字谱默认开启：简谱行可见且六线谱和弦品数完整', off0.hasNumbered && off0.multi > 0, JSON.stringify({ off0, errs }));

  // A2 数字谱关闭：简谱行隐藏（showNumbered=false、SVG 变矮），六线谱和弦品数保留
  await clickBtn(page, '数字谱');
  await page.waitForTimeout(700);
  const off1 = await readDisplayState(page);
  await page.screenshot({ path: EVIDENCE + '/a2-number-off.png' });
  record('A2 数字谱关闭：简谱隐藏且六线谱品数保留', !off1.hasNumbered && off1.scrollH < off0.scrollH && off1.multi === off0.multi && off1.multi > 0, JSON.stringify({ off0, off1, errs }));

  // A3 数字谱重新打开：简谱恢复、品数保持完整
  await clickBtn(page, '数字谱');
  await page.waitForTimeout(700);
  const on2 = await readDisplayState(page);
  await page.screenshot({ path: EVIDENCE + '/a3-number-on.png' });
  record('A3 数字谱重新打开：简谱恢复', on2.hasNumbered && on2.multi === off0.multi, JSON.stringify({ on2, errs }));

  // A4 变调夹下拉项集合（参考站一致）
  const capoBtnTextBefore = await page.evaluate(() => [...document.querySelectorAll('button')].find((x) => x.textContent.includes('变调夹'))?.textContent.trim() ?? null);
  await clickBtn(page, '变调夹');
  await page.waitForTimeout(300);
  const items = await page.evaluate(() => [...document.querySelectorAll('[role="option"]')].map((x) => x.textContent.trim()));
  await page.screenshot({ path: EVIDENCE + '/a3-capo-menu.png' });
  const itemsOk = JSON.stringify(items) === JSON.stringify(EXPECTED_CAPO_ITEMS);
  record('A4 变调夹下拉 8 项与参考站一致', itemsOk, JSON.stringify({ items, capoBtnTextBefore, errs }));

  // A5 选 3品 → 显示不变（staff.capo=3，只改变发声音高）
  const frets0 = await readFrets(page);
  await page.evaluate(() => {
    const opt = [...document.querySelectorAll('[role="option"]')].find((x) => x.textContent.trim() === '3品');
    opt.click();
  });
  await page.waitForTimeout(1500);
  const a4 = await page.evaluate(() => ({
    capo: window.__api.score.tracks[0].staves[0].capo,
    btnText: [...document.querySelectorAll('button')].find((x) => x.textContent.includes('变调夹'))?.textContent.trim() ?? null,
  }));
  a4.frets = await readFrets(page);
  await page.screenshot({ path: EVIDENCE + '/a4-capo-3.png' });
  const fretsSame4 = JSON.stringify(a4.frets) === JSON.stringify(frets0);
  record('A5 变调夹 3品：显示不变且 capo=3', fretsSame4 && a4.capo === 3 && /3品/.test(a4.btnText), JSON.stringify({ frets0, after: a4.frets, capo: a4.capo, errs }));

  // A6 降半调调弦 → 显示不变（capo=-1，发声音高降半音）
  await clickBtn(page, '变调夹');
  await page.waitForTimeout(200);
  await page.evaluate(() => {
    const opt = [...document.querySelectorAll('[role="option"]')].find((x) => x.textContent.trim() === '降半调调弦');
    opt.click();
  });
  await page.waitForTimeout(1500);
  const a5 = await page.evaluate(() => ({ capo: window.__api.score.tracks[0].staves[0].capo, btnText: [...document.querySelectorAll('button')].find((x) => x.textContent.includes('变调夹'))?.textContent.trim() ?? null }));
  a5.frets = await readFrets(page);
  await page.screenshot({ path: EVIDENCE + '/a5-half-down.png' });
  const fretsSame5 = JSON.stringify(a5.frets) === JSON.stringify(frets0);
  record('A6 降半调调弦：显示不变且 capo=-1', fretsSame5 && a5.capo === -1 && /降半调/.test(a5.btnText), JSON.stringify({ frets0, after: a5.frets, capo: a5.capo, errs }));

  // A7 恢复不夹，转调 +2 → 品数 +2，transpositionPitch=-2，UI 显示 +2
  await clickBtn(page, '变调夹');
  await page.waitForTimeout(200);
  await page.evaluate(() => {
    const opt = [...document.querySelectorAll('[role="option"]')].find((x) => x.textContent.trim() === '不夹');
    opt.click();
  });
  await page.waitForTimeout(1500);
  const fretsBase = await readFrets(page);
  await clickBtn(page, '转调升高半音');
  await page.waitForTimeout(300);
  await clickBtn(page, '转调升高半音');
  await page.waitForTimeout(1500);
  const a6 = await page.evaluate(() => ({
    transpositionPitch: window.__api.score.tracks[0].staves[0].transpositionPitch,
    ui: [...document.querySelectorAll('span')].filter((x) => /^[+]?-?\d+$/.test(x.textContent.trim())).map((x) => x.textContent.trim()).slice(0, 3),
  }));
  a6.frets = await readFrets(page);
  await page.screenshot({ path: EVIDENCE + '/a6-transpose-2.png' });
  const fretsPlus2 = fretsBase.every((v, i) => v && a6.frets[i] && Number(a6.frets[i]) === Number(v) + 2);
  record('A7 整曲转调 +2：品数+2 且 transpositionPitch=-2 且 UI=+2', fretsPlus2 && a6.transpositionPitch === -2 && a6.ui.includes('+2'), JSON.stringify({ fretsBase, after: a6.frets, transpositionPitch: a6.transpositionPitch, ui: a6.ui, errs }));

  // A8 转调回 0
  await clickBtn(page, '转调降低半音');
  await page.waitForTimeout(300);
  await clickBtn(page, '转调降低半音');
  await page.waitForTimeout(1200);

  await ctx.close();
}

// ---------- 页面 B：播放状态（高亮 / 光标 / 播放中切换不重置） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);

  // B1 播放 → 高亮 signal 蓝 + 光标参考站红 + tick 推进
  await page.locator('button', { hasText: /播放|音源/ }).first().click().catch(() => {});
  await page.waitForTimeout(3000);
  const b1 = await page.evaluate(() => {
    const hl = document.querySelectorAll('.at-highlight');
    const first = hl[0];
    const bar = document.querySelector('.at-cursor-bar');
    const beat = document.querySelector('.at-cursor-beat');
    return {
      highlightCount: hl.length,
      fill: first ? getComputedStyle(first).fill : null,
      stroke: first ? getComputedStyle(first).stroke : null,
      barBg: bar ? getComputedStyle(bar).backgroundColor : null,
      beatBg: beat ? getComputedStyle(beat).backgroundColor : null,
      tick: Math.round(window.__api.tickPosition),
      playing: window.__api.player.state === 1,
    };
  });
  await page.screenshot({ path: EVIDENCE + '/b1-highlight-playing.png' });
  record('B1 播放高亮 signal 蓝 + 光标参考站红', b1.highlightCount > 0 && b1.fill === 'rgb(65, 161, 207)' && b1.stroke === 'rgb(65, 161, 207)' && b1.beatBg === 'rgb(210, 109, 109)' && b1.playing, JSON.stringify(b1));

  // B2 播放中改变调夹：tick 不重置、继续播放
  const tick1 = await page.evaluate(() => Math.round(window.__api.tickPosition));
  await page.locator('button', { hasText: '变调夹' }).first().click();
  await page.waitForTimeout(200);
  await page.locator('[role="option"]', { hasText: '2品' }).first().click();
  await page.waitForTimeout(1500);
  const b2 = await page.evaluate(() => ({
    tick: Math.round(window.__api.tickPosition),
    playing: window.__api.player.state === 1,
    capo: window.__api.score.tracks[0].staves[0].capo,
  }));
  record('B2 播放中改变调夹不重置位置', b2.tick > tick1 && b2.playing && b2.capo === 2, JSON.stringify({ tick1, b2, errs }));

  // B3 播放中整曲转调：tick 不重置、继续播放
  const tick2 = await page.evaluate(() => Math.round(window.__api.tickPosition));
  await page.locator('button[aria-label="转调升高半音"]').first().click();
  await page.waitForTimeout(1500);
  const b3 = await page.evaluate(() => ({
    tick: Math.round(window.__api.tickPosition),
    playing: window.__api.player.state === 1,
    transpositionPitch: window.__api.score.tracks[0].staves[0].transpositionPitch,
  }));
  record('B3 播放中转调不重置位置', b3.tick > tick2 && b3.playing && b3.transpositionPitch === -1, JSON.stringify({ tick2, b3, errs }));

  // B4 停止 → 高亮清除、光标停止
  await page.locator('button', { hasText: '重来' }).first().click().catch(() => {});
  await page.waitForTimeout(800);
  const b4 = await page.evaluate(() => ({
    highlightCount: document.querySelectorAll('.at-highlight').length,
    tick: Math.round(window.__api.tickPosition),
  }));
  await page.screenshot({ path: EVIDENCE + '/b4-stopped.png' });
  record('B4 停止后高亮清除', b4.highlightCount === 0 && b4.tick < 100, JSON.stringify({ b4, errs }));

  await ctx.close();
}

// ---------- 汇总 ----------
const pass = results.filter((r) => r.ok).length;
const fail = results.length - pass;
console.log('\n==== SUMMARY ' + pass + '/' + results.length + ' PASS ====');
for (const r of results) if (!r.ok) console.log('  FAIL: ' + r.name + ' | ' + r.detail);
await browser.close();
if (fail > 0) process.exit(1);
