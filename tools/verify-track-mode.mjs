// 谱面显示模式专项验收（方案 C：主音轨六线谱 + 其余音轨简谱，与全部六线谱可切换）
// 用法：node tools/verify-track-mode.mjs （需 dev server 运行在 4321）
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/track-mode';
fs.mkdirSync(EVIDENCE, { recursive: true });

const results = [];
const OUT_LOG = 'tools/verify-track-mode.out.log';
fs.writeFileSync(OUT_LOG, '');
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  const line = (ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : '');
  console.log(line);
  fs.appendFileSync(OUT_LOG, line + '\n');
}

const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });

async function openTab(page, id) {
  const errs = [];
  const onC = (m) => { if (m.type() === 'error') errs.push('err:' + m.text().slice(0, 140)); };
  const onE = (e) => errs.push('pageerror:' + String(e).slice(0, 160));
  page.on('console', onC);
  page.on('pageerror', onE);
  await page.goto(BASE + '/tabs/' + id, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => window.__api && document.querySelector('#score-scroll svg'), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(4000);
  return { errs, off: () => { page.removeListener('console', onC); page.removeListener('pageerror', onE); } };
}

async function snap(page) {
  return page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    const svgs = [...sc.querySelectorAll('svg')].filter((sv) => parseFloat(sv.getAttribute('height') || '0') > 100);
    const sys1 = svgs[0];
    const texts = sys1 ? [...sys1.querySelectorAll('text')].map((t) => (t.textContent || '').trim()).filter(Boolean) : [];
    const digits = texts.filter((t) => /^[0-9]+$/.test(t));
    const hasBigFret = digits.some((d) => Number(d) > 7); // 六线谱品数可 >7（如 21/22/24）；简谱数字只有 0-7
    return {
      flags: window.__api.score.tracks.map((t, i) => t.staves.map((st) => ({ tab: st.showTablature, num: st.showNumbered }))),
      sysCount: svgs.length,
      sys1Digits: digits.length,
      hasBigFret,
      scrollH: sc.scrollHeight,
    };
  });
}

async function clickMode(page, label) {
  await page.evaluate((l) => {
    const b = [...document.querySelectorAll('button')].find((x) => !x.disabled && x.textContent.trim() === l);
    if (!b) throw new Error('mode btn missing: ' + l);
    b.click();
  }, label);
  await page.waitForTimeout(3500);
}

// ---------- T1 安和桥默认 = 吉他谱+简谱（mixed） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1H9U5lzfB');
  const s = await snap(page);
  const modeBtns = await page.evaluate(() => [...document.querySelectorAll('button')].filter((b) => /吉他谱\+简谱|全部六线谱/.test(b.textContent)).map((b) => ({ t: b.textContent.trim(), d: b.disabled })));
  await page.screenshot({ path: EVIDENCE + '/t1-mixed-default.png' });
  const ok = s.flags[0][0].tab === true && s.flags[1][0].tab === false && s.flags[1][0].num === true && !s.hasBigFret && modeBtns.length === 2 && modeBtns.every((b) => !b.d);
  record('T1 安和桥默认吉他谱+简谱（主轨六线谱/次轨简谱，切换按钮可用）', ok, JSON.stringify({ flags: s.flags, hasBigFret: s.hasBigFret, sys1Digits: s.sys1Digits, modeBtns, errs }));
  await ctx.close();
}

// ---------- T2 切换到全部六线谱 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1H9U5lzfB');
  await clickMode(page, '全部六线谱');
  const s = await snap(page);
  await page.screenshot({ path: EVIDENCE + '/t2-all-tab.png' });
  const ok = s.flags[0][0].tab === true && s.flags[1][0].tab === true && s.flags[1][0].num === false && s.hasBigFret;
  record('T2 全部六线谱：两轨均为六线谱（出现 >7 品数）', ok, JSON.stringify({ flags: s.flags, hasBigFret: s.hasBigFret, sysCount: s.sysCount, errs }));
  await ctx.close();
}

// ---------- T3 切回吉他谱+简谱 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1H9U5lzfB');
  await clickMode(page, '全部六线谱');
  await clickMode(page, '吉他谱+简谱');
  const s = await snap(page);
  await page.screenshot({ path: EVIDENCE + '/t3-back-mixed.png' });
  const ok = s.flags[0][0].tab === true && s.flags[1][0].tab === false && s.flags[1][0].num === true && !s.hasBigFret && errs.length === 0;
  record('T3 切回吉他谱+简谱且全程零报错', ok, JSON.stringify({ flags: s.flags, hasBigFret: s.hasBigFret, errs }));
  await ctx.close();
}

// ---------- T4 晴天（吉他+钢琴，单吉他轨）：两模式按钮可用、往返切换零报错 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1sdc49P3eKm');
  const s1 = await snap(page);
  const modeBtns = await page.evaluate(() => [...document.querySelectorAll('button')].filter((b) => /吉他谱\+简谱|全部六线谱/.test(b.textContent)).map((b) => ({ t: b.textContent.trim(), d: b.disabled })));
  await page.screenshot({ path: EVIDENCE + '/t4-qingtian-mixed.png' });
  const ok1 = s1.flags[0][0].tab === true && s1.flags[1][0].num === true && s1.flags[1][0].tab === false &&
    modeBtns.length === 2 && modeBtns.every((b) => !b.d) && errs.length === 0;
  await clickMode(page, '全部六线谱');
  const s2 = await snap(page);
  await page.screenshot({ path: EVIDENCE + '/t4-qingtian-alltab.png' });
  await clickMode(page, '吉他谱+简谱');
  const s3 = await snap(page);
  const ok = ok1 && s2.flags[1][0].num === true && s3.flags[1][0].num === true && errs.length === 0;
  record('T4 晴天（单吉他轨）两模式按钮可用、往返切换零报错', ok, JSON.stringify({ flags1: s1.flags, flags2: s2.flags, flags3: s3.flags, modeBtns, errs }));
  await ctx.close();
}

// ---------- T5 移动端 390 无横向溢出 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1H9U5lzfB');
  const s = await snap(page);
  const overflow = await page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    if (!sc) return null;
    return { scrollWidth: sc.scrollWidth, clientWidth: sc.clientWidth };
  });
  await page.screenshot({ path: EVIDENCE + '/t5-mobile.png' });
  const ok = s.flags[1][0].num === true && overflow && overflow.scrollWidth <= overflow.clientWidth + 2 && errs.length === 0;
  record('T5 移动端 390 混合模式无横向溢出', ok, JSON.stringify({ overflow, flags: s.flags, errs }));
  await ctx.close();
}

// ---------- T6 Hello 型（次轨含全音符休止符）：剥离后正常转简谱、零报错、切回恢复 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page, '1yOhtb1c9I0');
  const s1 = await snap(page);
  const modeBtns = await page.evaluate(() => [...document.querySelectorAll('button')].filter((b) => /吉他谱\+简谱|全部六线谱/.test(b.textContent)).map((b) => ({ t: b.textContent.trim(), d: b.disabled })));
  await page.screenshot({ path: EVIDENCE + '/t6-hello-strip.png' });
  const ok1 = s1.flags[0][0].tab === true && s1.flags[1][0].tab === false && s1.flags[1][0].num === true && modeBtns.every((b) => !b.d) && !s1.hasBigFret && errs.length === 0;
  // 切到全部六线谱再切回：无报错
  await clickMode(page, '全部六线谱');
  const s2 = await snap(page);
  const ok2 = s2.flags[1][0].tab === true && s2.flags[1][0].num === false;
  await clickMode(page, '吉他谱+简谱');
  const s3 = await snap(page);
  const ok3 = s3.flags[1][0].num === true && !s3.hasBigFret && errs.length === 0;
  record('T6 Hello（次轨含全音符休止符）替换后转简谱、往返切换零报错', ok1 && ok2 && ok3, JSON.stringify({ s1: { flags: s1.flags, hasBigFret: s1.hasBigFret }, modeBtns, s2: { flags: s2.flags, hasBigFret: s2.hasBigFret }, s3: { flags: s3.flags, hasBigFret: s3.hasBigFret }, errs }));
  await ctx.close();
}

// ---------- 汇总 ----------
const pass = results.filter((r) => r.ok).length;
const fail = results.length - pass;
console.log('\n==== SUMMARY ' + pass + '/' + results.length + ' PASS ====');
for (const r of results) if (!r.ok) console.log('  FAIL: ' + r.name + ' | ' + r.detail);
await browser.close();
if (fail > 0) process.exit(1);

