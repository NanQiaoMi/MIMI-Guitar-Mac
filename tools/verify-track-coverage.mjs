#!/usr/bin/env node
// ??????????????? tools/track-mode-audit.json ???????
// ??????????????+????????????node tools/verify-track-coverage.mjs [--all]
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const USE_ALL = process.argv.includes('--all');

const audit = JSON.parse(readFileSync('tools/track-mode-audit.json', 'utf8'));
let ids = audit.details.filter((d) => d.cls === 'multiTwoPlusTuned').map((d) => d.id);
if (!USE_ALL) ids = ids.slice(0, 60);
console.log('testing', ids.length, 'multi-track scores');

const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const results = [];
for (const id of ids) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errs = [];
  page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 120)); });
  page.on('pageerror', (e) => errs.push(String(e).slice(0, 120)));
  try {
    await page.goto(BASE + '/tabs/' + id, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForFunction(() => window.__api && document.querySelector('#score-scroll svg'), { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(3500);
    const info = await page.evaluate(() => {
      const api = window.__api;
      if (!api || !api.score) return { noScore: true };
      const sc = document.getElementById('score-scroll');
      const svgCount = sc ? sc.querySelectorAll('svg').length : 0;
      return {
        flags: api.score.tracks.map((t) => t.staves.map((st) => ({ tab: st.showTablature, num: st.showNumbered }))),
        svgCount,
        loading: document.body.innerText.includes('\u4e50\u8c31\u52a0\u8f7d\u4e2d'), // ?????
      };
    });
    const mixed = info.flags && info.flags[0][0].tab === true && info.flags[1][0].tab === false && info.flags[1][0].num === true;
    const ok = !!info.flags && mixed && info.svgCount >= 3 && !info.loading && errs.length === 0;
    results.push({ id, ok, mixed, svgCount: info.svgCount, errCount: errs.length, errSample: errs.slice(0, 2) });
    if (!ok) console.log('FAIL', id, JSON.stringify({ mixed: info.mixed, svgCount: info.svgCount, errs }));
  } catch (e) {
    results.push({ id, ok: false, errSample: [String(e).slice(0, 120)] });
    console.log('FAIL', id, String(e).slice(0, 140));
  }
  await page.close();
}
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log('\n==== coverage ' + pass + '/' + results.length + ' PASS ====');
for (const r of results.filter((x) => !x.ok)) console.log('FAIL:', r.id, JSON.stringify(r.errSample || {}));

