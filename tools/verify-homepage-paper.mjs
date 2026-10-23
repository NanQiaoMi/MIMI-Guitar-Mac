// 首页纸纹 + 音符高级化验收
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/homepage-paper';
fs.mkdirSync(EVIDENCE, { recursive: true });

let pass = 0, fail = 0;
const failures = [];
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ✔ ' + name); }
  else { fail++; failures.push(name + (extra ? ' — ' + extra : '')); console.log('  ✖ ' + name + (extra ? ' — ' + extra : '')); }
}

const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
page.on('pageerror', e => errors.push(String(e).slice(0, 200)));
await page.addInitScript(() => sessionStorage.setItem('mimi_paper_intro_played', 'true'));
await page.goto(BASE + '/', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(2200);

console.log('== 纸纹 ==');
const bgInfo = await page.evaluate(() => {
  const body = getComputedStyle(document.body);
  const layers = body.backgroundImage.split('), ').length;
  const urls = (body.backgroundImage.match(/data:image/g) || []).length;
  const hasFibers = body.backgroundImage.includes("baseFrequency='0.02 0.55'");
  const hasClouds = body.backgroundImage.includes("baseFrequency='0.011 0.016'");
  const hasMottle = body.backgroundImage.includes("baseFrequency='0.16'");
  const hasGrain = body.backgroundImage.includes("baseFrequency='0.9'");
  const hasEdgeLight = body.backgroundImage.includes('linear-gradient');
  return { layers, urls, hasFibers, hasClouds, hasMottle, hasGrain, hasEdgeLight };
});
ok('body 背景 ≥ 6 层', bgInfo.layers >= 6, 'layers=' + bgInfo.layers);
ok('含 4 组 SVG 噪声图层', bgInfo.urls >= 4, 'urls=' + bgInfo.urls);
ok('纤维丝缕层（方向性）', bgInfo.hasFibers);
ok('云絮斑驳层', bgInfo.hasClouds);
ok('粗绒面层', bgInfo.hasMottle);
ok('细颗粒层', bgInfo.hasGrain);
ok('页缘光影（顶部受光+底部落影）', bgInfo.hasEdgeLight);

console.log('== 背景音符 ==');
const noteInfo = await page.evaluate(() => {
  const canvas = document.querySelector('.spotlight-card canvas');
  if (!canvas) return null;
  const ctx = canvas.getContext('2d');
  const w = canvas.width, h = canvas.height;
  const data = ctx.getImageData(0, 0, w, h).data;
  let warmInk = 0, gold = 0, blue = 0, other = 0;
  const total = w * h;
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], g = data[i+1], b = data[i+2], a = data[i+3];
    if (a < 8) continue;
    if (r >= 50 && r <= 110 && g >= 40 && g <= 100 && b >= 30 && b <= 90) warmInk++;      // 暖墨/灰褐
    else if (r >= 130 && r <= 200 && g >= 100 && g <= 170 && b >= 60 && b <= 120) gold++;  // 淡金/古铜
    else if (b >= 130 && b <= 220 && r <= 110 && g >= 120 && g <= 210) blue++;             // 信号蓝
    else other++;
  }
  return { warmInk, gold, blue, other, total, w, h };
});
ok('Hero canvas 存在', !!noteInfo);
if (noteInfo) {
  ok('暖墨/灰褐音符占比显著', noteInfo.warmInk > 30, 'warm=' + noteInfo.warmInk);
  ok('淡金/古铜点缀存在', noteInfo.gold > 5, 'gold=' + noteInfo.gold);
  ok('信号蓝占比克制（点缀）', noteInfo.blue < noteInfo.warmInk, 'blue=' + noteInfo.blue + ' warm=' + noteInfo.warmInk);
}
await page.screenshot({ path: path.join(EVIDENCE, 'desktop-home.png') });
const hero = page.locator('.spotlight-card');
await hero.screenshot({ path: path.join(EVIDENCE, 'desktop-hero.png') });

// 移动端
const mp = await browser.newPage({ viewport: { width: 390, height: 844 } });
const mErrors = [];
mp.on('console', m => { if (m.type() === 'error') mErrors.push(m.text().slice(0, 200)); });
mp.on('pageerror', e => mErrors.push(String(e).slice(0, 200)));
await mp.addInitScript(() => sessionStorage.setItem('mimi_paper_intro_played', 'true'));
await mp.goto(BASE + '/', { waitUntil: 'networkidle', timeout: 60000 });
await mp.waitForTimeout(1800);
const overflow = await mp.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
console.log('== 移动端 ==');
ok('移动端无横向溢出', overflow <= 0, 'overflow=' + overflow + 'px');
ok('移动端控制台零报错', mErrors.length === 0, mErrors.join(' | '));
await mp.screenshot({ path: path.join(EVIDENCE, 'mobile.png') });

console.log('== 控制台 ==');
ok('桌面端控制台零报错', errors.length === 0, errors.join(' | '));

await browser.close();
console.log(`\n结果：${pass} PASS / ${fail} FAIL`);
if (fail > 0) { console.log('失败项：'); failures.forEach(f => console.log('  - ' + f)); process.exit(1); }
