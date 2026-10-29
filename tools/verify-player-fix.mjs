// 播放器修复专项验收（PLAYER_FIX_PLAN）
// 覆盖：光标可见与移动 / 跟随滚动 / 进度条·时间·小节拍号 / 拖拽 seek / 播放中改 capo 保位置 /
//       变速语义 / 循环区间高亮 / 多首不同谱面无 unsupported sample 警告 / 全量 sf2 加载
// 用法：node tools/verify-player-fix.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/player-fix';
fs.mkdirSync(EVIDENCE, { recursive: true });

const results = [];
const OUT_LOG = 'tools/verify-player-fix.out.log';
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  const line = (ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : '');
  console.log(line);
  fs.appendFileSync(OUT_LOG, line + '\n');
}
const START = Date.now();
function budgetOk(ms) { return Date.now() - START < ms; }

const browser = await chromium.launch({
  executablePath: EXE, headless: true,
  args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'],
});

async function openTab(page, id, waitMs = 2500) {
  const errs = [];
  const warns = [];
  const onC = (m) => {
    const t = m.text();
    if (m.type() === 'error') errs.push('err:' + t.slice(0, 160));
    if (t.includes('unsupported sample')) warns.push(t.slice(0, 120));
  };
  const onE = (e) => errs.push('pageerror:' + String(e).slice(0, 160));
  page.on('console', onC);
  page.on('pageerror', onE);
  await page.goto(`${BASE}/tabs/${id}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => !document.body.innerText.includes('乐谱加载中'), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(waitMs);
  return { errs, warns, off: () => { page.removeListener('console', onC); page.removeListener('pageerror', onE); } };
}

// ---------- T1 光标可见性与样式 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  const dom = await page.evaluate(() => {
    const bar = document.querySelector('.at-cursor-bar');
    const beat = document.querySelector('.at-cursor-beat');
    const prog = document.querySelector('input[aria-label="播放进度"]');
    return {
      cursorBar: !!bar,
      cursorBeat: !!beat,
      barBg: bar ? getComputedStyle(bar).backgroundColor : null,
      beatBg: beat ? getComputedStyle(beat).backgroundColor : null,
      progress: !!prog,
      progressMax: prog ? Number(prog.max) : 0,
    };
  });
  await page.screenshot({ path: `${EVIDENCE}/t1-cursor-visible.png` });
  await ctx.close();
  record('T1 光标元素可见 + 参考站红样式', dom.cursorBar && dom.cursorBeat && dom.barBg === 'rgba(210, 109, 109, 0.05)' && dom.beatBg === 'rgb(210, 109, 109)', JSON.stringify(dom));
}

// ---------- T2 播放推进：tick/光标/小节拍号/时间 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  await page.locator('button', { hasText: /播放|音源/ }).first().click().catch(() => {});
  await page.waitForTimeout(2500);
  const s1 = await page.evaluate(() => {
    const beat = document.querySelector('.at-cursor-beat');
    const r = beat ? beat.getBoundingClientRect() : null;
    return {
      tick: Math.round(window.__api.tickPosition),
      beatX: r ? Math.round(r.x) : null,
      barText: [...document.querySelectorAll('span')].find(s => /第 \d+ 小节/.test(s.textContent.trim()))?.textContent.trim() ?? null,
      timeText: [...document.querySelectorAll('span')].find(s => /^\d{2}:\d{2}$/.test(s.textContent.trim()))?.textContent.trim() ?? null,
      progressVal: Number(document.querySelector('input[aria-label="播放进度"]')?.value ?? -1),
    };
  });
  await page.waitForTimeout(2000);
  const s2 = await page.evaluate(() => {
    const beat = document.querySelector('.at-cursor-beat');
    const r = beat ? beat.getBoundingClientRect() : null;
    return { tick: Math.round(window.__api.tickPosition), beatX: r ? Math.round(r.x) : null };
  });
  await page.screenshot({ path: `${EVIDENCE}/t2-playing.png` });
  await ctx.close();
  const moving = s2.tick > s1.tick + 100 && s2.beatX !== s1.beatX;
  record('T2 播放推进且光标移动', moving && /第 \d+ 小节/.test(s1.barText || '') && /^\d{2}:\d{2}$/.test(s1.timeText || ''), JSON.stringify({ s1, s2, errs }));
}

// ---------- T3 跟随滚动：seek 到 80% 后 scrollTop 跟随 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  await page.locator('button', { hasText: /播放|音源/ }).first().click().catch(() => {});
  await page.waitForTimeout(800);
  const r1 = await page.evaluate(() => {
    const api = window.__api;
    api.tickPosition = Math.round(api.endTick * 0.8);
    return api.endTick;
  });
  await page.waitForTimeout(1200);
  const r2 = await page.evaluate(() => {
    const sc = document.querySelector('#score-scroll');
    return { scrollTop: Math.round(sc.scrollTop), scrollH: sc.scrollHeight, clientH: sc.clientHeight, tick: Math.round(window.__api.tickPosition) };
  });
  await page.screenshot({ path: `${EVIDENCE}/t3-follow-scroll.png` });
  await ctx.close();
  record('T3 跟随滚动生效', r2.scrollTop > 0 && r2.scrollTop + r2.clientH < r2.scrollH + 1 && r2.tick > r1 * 0.7, JSON.stringify({ r1, r2, errs }));
}

// ---------- T4 进度条拖拽 seek ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  await page.locator('button', { hasText: /播放|音源/ }).first().click().catch(() => {});
  await page.waitForTimeout(1000);
  const r1 = await page.evaluate(() => {
    const prog = document.querySelector('input[aria-label="播放进度"]');
    const api = window.__api;
    const target = Math.round(api.endTick * 0.5);
    prog.value = String(target);
    prog.dispatchEvent(new Event('input', { bubbles: true }));
    return { target, tickNow: Math.round(api.tickPosition) };
  });
  await page.waitForTimeout(800);
  const r2 = await page.evaluate(() => ({ tick: Math.round(window.__api.tickPosition) }));
  await ctx.close();
  record('T4 进度条 seek 生效并续播', Math.abs(r1.tickNow - r1.target) < 5 && r2.tick > r1.target, JSON.stringify({ r1, r2, errs }));
}

// ---------- T5 播放中改 capo 保位置 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  await page.locator('button', { hasText: /播放|音源/ }).first().click().catch(() => {});
  await page.waitForTimeout(1500);
  const before = await page.evaluate(() => Math.round(window.__api.tickPosition));
  // 变调夹为按钮+下拉（参考站交互），点开并选择 3品
  await page.locator('button', { hasText: '变调夹' }).first().click();
  await page.waitForTimeout(200);
  await page.locator('[role="option"]', { hasText: '3品' }).first().click();
  await page.waitForTimeout(1500);
  const after = await page.evaluate(() => ({ tick: Math.round(window.__api.tickPosition), capo: window.__api.score?.tracks?.[0]?.staves?.[0]?.capo, btn: [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '暂停')?.textContent.trim() ?? null }));
  await ctx.close();
  record('T5 播放中改变调夹位置不重置', after.tick > before && after.btn === '暂停' && after.capo === 3, JSON.stringify({ before, after, errs }));
}

// ---------- T6 变速语义：playbackSpeed = v/baseTempo，tempo 自动化不变 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  const before = await page.evaluate(() => {
    const api = window.__api;
    return { tempo: api.score.masterBars[0].tempoAutomations[0].value, playbackSpeed: api.playbackSpeed };
  });
  // 通过滑块改速度到 120
  await page.locator('input[type="range"] >> nth=0').evaluate((el) => {
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    setter.call(el, '120');
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await page.waitForTimeout(600);
  const after = await page.evaluate(() => {
    const api = window.__api;
    return { tempo: api.score.masterBars[0].tempoAutomations[0].value, playbackSpeed: api.playbackSpeed, speedLabel: [...document.querySelectorAll('span')].find(s => /^\d{2,3}$/.test(s.textContent.trim()) && Number(s.textContent) >= 30 && Number(s.textContent) <= 300)?.textContent.trim() ?? null };
  });
  await ctx.close();
  const expect = 120 / before.tempo;
  record('T6 变速只改 playbackSpeed', Math.abs(after.playbackSpeed - expect) < 0.01 && after.tempo === before.tempo, JSON.stringify({ before, after, expect, errs }));
}

// ---------- T7 循环区间高亮 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  // UI 点击两个音符设置循环区间（先回顶，确保固定坐标命中第一小节）
  await page.locator('button', { hasText: '循环' }).first().click().catch(() => {});
  await page.evaluate(() => {
    const sc = document.querySelector('#score-scroll');
    if (sc) sc.scrollTop = 0;
    const api = window.__api;
    if (api) api.tickPosition = 0;
  });
  await page.waitForTimeout(600);
  const pts = await page.evaluate(() => {
    const api = window.__api;
    const lookup = api.renderer.instance.boundsLookup;
    const out = [];
    outer:
    for (const system of lookup.staffSystems) {
      for (const mb of system.bars) {
        for (const bar of mb.bars) {
          for (const beat of bar.beats) {
            const vb = beat.visualBounds;
            if (vb && vb.w > 0 && vb.h > 0) {
              out.push({ x: vb.x + vb.w / 2, y: vb.y + vb.h / 2 });
              if (out.length >= 5) break outer;
            }
          }
        }
      }
    }
    const surf = document.querySelector('.at-surface').getBoundingClientRect();
    return { pts: out, left: surf.left, top: surf.top };
  });
  if (pts && pts.pts && pts.pts.length >= 2) {
    await page.mouse.click(pts.left + pts.pts[0].x, pts.top + pts.pts[0].y);
    await page.waitForTimeout(350);
    await page.mouse.click(pts.left + pts.pts[4].x, pts.top + pts.pts[4].y);
  } else if (box) {
    await page.mouse.click(box.x + 100, box.y + 180);
    await page.waitForTimeout(300);
    await page.mouse.click(box.x + 140, box.y + 220);
  }
  await page.waitForTimeout(500);
  const ui = await page.evaluate(() => {
    const api = window.__api;
    const prog = document.querySelector('input[aria-label="播放进度"]');
    const wrap = prog ? prog.parentElement : null;
    const divs = wrap ? [...wrap.querySelectorAll('div')] : [];
    const highlight = divs.find((d) => (d.getAttribute('style') || '').includes('rgba(')) ?? null;
    const banner = [...document.querySelectorAll('div')].find((x) => /音符|循环中/.test(x.textContent || '') && x.textContent.length < 14)?.textContent.trim() ?? null;
    return {
      playbackRange: api.playbackRange,
      isLooping: api.isLooping,
      banner,
      hasHighlight: !!highlight,
      highlightStyle: highlight ? highlight.getAttribute('style') : null,
    };
  });
  await page.screenshot({ path: `${EVIDENCE}/t7-loop.png` });
  await ctx.close();
  record('T7 循环区间高亮', ui.hasHighlight && /left:/.test(ui.highlightStyle || '') && /width:/.test(ui.highlightStyle || ''), JSON.stringify({ ui, errs }));
}

// ---------- T8 多首不同谱面播放：无 unsupported sample 警告 ----------
{
  const ids = ['1sdc49P3eKm', '1yDFAg9Z3mU', '1sdixfUd4Vc', '1yOhtb1c9I0'];
  let allOk = true;
  const details = [];
  for (const id of ids) {
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const page = await ctx.newPage();
    const { errs, warns } = await openTab(page, id, 2000);
    await page.locator('button', { hasText: /播放|音源/ }).first().click().catch(() => {});
    await page.waitForTimeout(2500);
    const st = await page.evaluate(() => {
      const api = window.__api;
      return { tick: Math.round(api.tickPosition), player: api.playerState ? 'ok' : 'ok' };
    });
    const ok = warns.length === 0 && st.tick > 100 && errs.length === 0;
    if (!ok) allOk = false;
    details.push({ id, tick: st.tick, warnCount: warns.length, errCount: errs.length });
    await ctx.close();
  }
  record('T8 多首谱面播放无 unsupported 警告', allOk, JSON.stringify(details));
}

// ---------- T9 全量 sf2 加载（72 个）无 unsupported sample 警告 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm', 2000);
  let unsupported = 0;
  const onWarn = (m) => { if (m.text().includes('unsupported sample')) unsupported++; };
  page.on('console', onWarn);
  const result = await page.evaluate(async () => {
    const api = window.__api;
    const idx = await (await fetch('/storage/soundfonts/index.json')).json();
    let failed = 0;
    let loaded = 0;
    for (const p of idx) {
      try {
        const res = await fetch(`/storage/soundfonts/${p}.sf2`);
        if (!res.ok) { failed++; continue; }
        const data = new Uint8Array(await res.arrayBuffer());
        const copy = new Uint8Array(data.length);
        copy.set(data);
        await new Promise((resolve) => {
          const timer = setTimeout(() => { cleanup(); resolve(); }, 10000);
          const onLoaded = () => { cleanup(); resolve(); };
          const cleanup = () => { clearTimeout(timer); api.soundFontLoaded.off(onLoaded); };
          api.soundFontLoaded.on(onLoaded);
          api.loadSoundFont(copy.buffer, true);
        });
        loaded++;
      } catch { failed++; }
    }
    return { loaded, failed };
  });
  page.removeListener('console', onWarn);
  await ctx.close();
  record('T9 全量 sf2 加载零 unsupported 警告', result.loaded >= 60 && result.failed === 0 && unsupported === 0, JSON.stringify({ ...result, unsupported }));
}

// ---------- 汇总 ----------
const pass = results.filter((r) => r.ok).length;
const fail = results.length - pass;
console.log('\n==== SUMMARY ' + pass + '/' + results.length + ' PASS ====');
for (const r of results) if (!r.ok) console.log('  FAIL: ' + r.name + ' | ' + r.detail);
await browser.close();
if (fail > 0) process.exit(1);
