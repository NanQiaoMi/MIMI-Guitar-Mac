// 首页纸页乐谱册验收
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/homepage-folio';
fs.mkdirSync(EVIDENCE, { recursive: true });

let pass = 0, fail = 0;
const failures = [];
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ✔ ' + name); }
  else { fail++; failures.push(name + (extra ? ' — ' + extra : '')); console.log('  ✖ ' + name + (extra ? ' — ' + extra : '')); }
}

const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
page.on('pageerror', e => errors.push(String(e).slice(0, 200)));
await page.addInitScript(() => sessionStorage.setItem('mimi_paper_intro_played', 'true'));
await page.goto(BASE + '/', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(2500);

console.log('== 纸页乐谱册结构 ==');
const struct = await page.evaluate(() => {
  const sections = [...document.querySelectorAll('.folio-section')];
  return sections.map((s, i) => {
    const pageEl = s.querySelector('.folio-page');
    const title = pageEl?.querySelector('h3')?.textContent?.trim();
    const artist = pageEl?.querySelector('p')?.textContent?.trim();
    const badges = [...(pageEl?.querySelectorAll('span') || [])].map(x => x.textContent?.trim()).filter(Boolean);
    const liners = s.querySelectorAll('.folio-liner').length;
    const tear = getComputedStyle(s.querySelector('.paper-tear-edge') || document.body).clipPath;
    const navBtns = s.querySelectorAll('.folio-nav').length;
    const dots = s.querySelectorAll('[role="tablist"] button').length;
    const pageNum = pageEl?.textContent?.match(/—\s*\d+\s*\/\s*\d+\s*—/)?.[0] || null;
    return { i, title, artist, badges: badges.slice(0, 5), liners, tear, navBtns, dots, pageNum };
  });
});
ok('存在 2 个纸页乐谱册区块', struct.length === 2, 'count=' + struct.length);
if (struct[0]) {
  ok('吉他册显示曲名', !!struct[0].title, struct[0].title);
  ok('吉他册显示艺人', !!struct[0].artist, struct[0].artist);
  ok('吉他册有衬纸堆叠（≥2）', struct[0].liners >= 2, 'liners=' + struct[0].liners);
  ok('吉他册撕纸边缘 clip-path 生效', struct[0].tear !== 'none', struct[0].tear);
  ok('吉他册有翻页按钮（2）', struct[0].navBtns === 2);
  ok('吉他册有页码点（≥5）', struct[0].dots >= 5, 'dots=' + struct[0].dots);
  ok('页码格式 — n / N —', /— \d+ \/ \d+ —/.test(struct[0].pageNum || ''), struct[0].pageNum);
}
if (struct[1]) ok('尤克里里册显示曲名', !!struct[1].title, struct[1].title);

console.log('== 翻页交互 ==');
const guitarSection = page.locator('.folio-section').first();
const firstHref = await guitarSection.locator('.folio-page').getAttribute('href');
const firstTitle = (await guitarSection.locator('.folio-page h3').textContent())?.trim();
const pageNum1 = (await guitarSection.locator('.folio-page').textContent())?.match(/—\s*(\d+)\s*\/\s*(\d+)\s*—/);
// 点击下一页
await guitarSection.locator('.folio-nav').nth(1).click();
await page.waitForTimeout(500);
const secondHref = await guitarSection.locator('.folio-page').getAttribute('href');
const secondTitle = (await guitarSection.locator('.folio-page h3').textContent())?.trim();
const pageNum2 = (await guitarSection.locator('.folio-page').textContent())?.match(/—\s*(\d+)\s*\/\s*(\d+)\s*—/);
ok('下一页后链接变化（曲目切换）', !!firstHref && !!secondHref && firstHref !== secondHref, firstHref + ' → ' + secondHref);
ok('下一页后曲名变化（可能同名）', firstTitle !== secondTitle || firstHref !== secondHref, firstTitle + ' → ' + secondTitle);
ok('页码从 1 → 2', pageNum1 && pageNum2 && pageNum1[1] === '1' && pageNum2[1] === '2', pageNum1?.[0] + ' → ' + pageNum2?.[0]);
// 点击上一页
await guitarSection.locator('.folio-nav').nth(0).click();
await page.waitForTimeout(500);
const backHref = await guitarSection.locator('.folio-page').getAttribute('href');
ok('上一页回退到首曲', backHref === firstHref, firstHref + ' vs ' + backHref);
// 首页时上一页禁用
const prevDisabled = await guitarSection.locator('.folio-nav').nth(0).isDisabled();
ok('首页时上一页禁用', prevDisabled);

console.log('== 3D 掀起 ==');
await guitarSection.locator('.folio-page').first().hover();
await page.waitForTimeout(500);
const liftTransform = await guitarSection.locator('.folio-page').evaluate(el => getComputedStyle(el).transform);
ok('悬停时纸页有 3D transform', liftTransform.includes('matrix') && liftTransform !== 'none', liftTransform.slice(0, 80));

console.log('== 控制台 ==');
ok('桌面端控制台零报错', errors.length === 0, errors.join(' | '));

// 截图
await page.screenshot({ path: path.join(EVIDENCE, 'desktop-top.png') });
const folioArea = page.locator('.mt-12.grid');
await folioArea.screenshot({ path: path.join(EVIDENCE, 'desktop-folio.png') });

// 移动端
const mp = await browser.newPage({ viewport: { width: 390, height: 844 } });
const mErrors = [];
mp.on('console', m => { if (m.type() === 'error') mErrors.push(m.text().slice(0, 200)); });
mp.on('pageerror', e => mErrors.push(String(e).slice(0, 200)));
await mp.addInitScript(() => sessionStorage.setItem('mimi_paper_intro_played', 'true'));
await mp.goto(BASE + '/', { waitUntil: 'networkidle', timeout: 60000 });
await mp.waitForTimeout(2000);
const overflow = await mp.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
console.log('== 移动端 ==');
ok('移动端无横向溢出', overflow <= 0, 'overflow=' + overflow + 'px');
ok('移动端控制台零报错', mErrors.length === 0, mErrors.join(' | '));
await mp.screenshot({ path: path.join(EVIDENCE, 'mobile.png') });

await browser.close();
console.log(`\n结果：${pass} PASS / ${fail} FAIL`);
if (fail > 0) { console.log('失败项：'); failures.forEach(f => console.log('  - ' + f)); process.exit(1); }
