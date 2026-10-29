// 首页纸页乐谱册「Air 克制化」验收（AIR_REDESIGN_PLAN 验收清单）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/homepage-folio-motion';
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

const guitar = page.locator('.folio-section').first();
const face = guitar.locator('.folio-page').first();
const pageNum = async () => (await face.textContent())?.match(/—\s*(\d+)\s*\/\s*(\d+)\s*—/)?.[1];
const faceTitle = async () => (await face.locator('h3').textContent())?.trim();
const ghost = guitar.locator('.folio-ghost');

console.log('== 克制化结构 ==');
ok('存在 2 个纸页乐谱册区块', await page.locator('.folio-section').count() === 2);
ok('纸页卡片存在', await face.count() === 1);
ok('衬纸层存在（≥2）', await guitar.locator('.folio-liner').count() >= 2);
const tearEdge = await face.evaluate(el => getComputedStyle(el.querySelector('.paper-tear-edge') || el).clipPath);
ok('撕纸边缘 clip-path 保留（装饰）', tearEdge.includes('polygon'), tearEdge.slice(0, 40));
ok('初始无旧页快照', await ghost.count() === 0);
ok('无撕页元素（tear-piece/corner/shred 全部移除）',
  await guitar.locator('.tear-piece, .tear-corner, .tear-shred, .tear-face, .tear-back, .tear-remain').count() === 0);
const faceShadow = await face.evaluate(el => getComputedStyle(el).boxShadow);
ok('卡片无阴影（Air: No elevation）', faceShadow === 'none', faceShadow.slice(0, 40));
const faceAnim = await face.evaluate(el => getComputedStyle(el).animationName);
ok('新页 page-in 淡入动画', faceAnim.includes('page-in'), faceAnim);
ok('无呼吸/扫光动画', !faceAnim.includes('breathe') && !faceAnim.includes('shine'), faceAnim);

console.log('== 交叉淡化切换（下一页） ==');
const firstHref = await face.getAttribute('href');
const firstTitle = await faceTitle();
const p1 = await pageNum();
// stagger：各元素 animation-delay 递增
const delays = await face.evaluate(el => ({
  cover: getComputedStyle(el.querySelector('.folio-cover')).animationDelay,
  title: getComputedStyle(el.querySelector('.folio-title')).animationDelay,
  artist: getComputedStyle(el.querySelector('.folio-artist')).animationDelay,
  badges: getComputedStyle(el.querySelector('.folio-badges')).animationDelay,
}));
ok('stagger 错位：封面先于标题', parseFloat(delays.cover) < parseFloat(delays.title), JSON.stringify(delays));
ok('stagger 错位：艺人先于徽章', parseFloat(delays.artist) < parseFloat(delays.badges));
await guitar.locator('.folio-nav').nth(1).click();
await page.waitForTimeout(120);
ok('旧页快照 ghost 立即出现（无空白）', await ghost.count() === 1);
const ghostTitle = await ghost.locator('h3').textContent();
ok('快照内容为旧页（第 1 首）', ghostTitle?.trim() === firstTitle, ghostTitle?.trim());
const ghostNum = await ghost.textContent();
ok('快照页码为旧页码（1 / N）', ghostNum?.includes('— 1 /'), ghostNum?.match(/— \d+ \/ \d+ —/)?.[0]);
const inAnim2 = await face.evaluate(el => getComputedStyle(el).animationName);
ok('新页 page-in 淡入播放', inAnim2.includes('page-in'), inAnim2);
ok('切换中按钮禁用（防连点）', await guitar.locator('.folio-nav').nth(1).isDisabled());
await page.waitForTimeout(350); // 累计 470ms，快照 340ms 已移除
const p2 = await pageNum();
ok('切换完成页码 1 → 2', p1 === '1' && p2 === '2', p1 + ' → ' + p2);
const secondHref = await face.getAttribute('href');
ok('正面切换为第 2 首', !!secondHref && secondHref !== firstHref, firstHref + ' → ' + secondHref);
ok('正面标题更新（可能同名）', (await faceTitle()) !== firstTitle || secondHref !== firstHref);
ok('快照已消失', await ghost.count() === 0);
ok('切换完成后按钮恢复可用', await guitar.locator('.folio-nav').nth(1).isEnabled());

console.log('== 上一页回退 ==');
await guitar.locator('.folio-nav').nth(0).click();
await page.waitForTimeout(400);
const p3 = await pageNum();
ok('上一页翻回页码 1', p3 === '1', p3);
ok('正面内容恢复第 1 首', (await faceTitle()) === firstTitle);

console.log('== 克制 hover（CSS :hover） ==');
const b = await face.boundingBox();
await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 5 });
await page.waitForTimeout(450);
const hoverInfo = await face.evaluate(el => {
  const cs = getComputedStyle(el);
  const img = el.querySelector('.folio-cover-img');
  return { tf: cs.transform, bc: cs.borderColor, img: img ? getComputedStyle(img).transform : 'no-img' };
});
ok('hover 2D 微抬（translateY -2px）', hoverInfo.tf.includes('matrix') && hoverInfo.tf.includes('-2'), hoverInfo.tf.slice(0, 50));
ok('hover 边框微亮（信号蓝调）', hoverInfo.bc.includes('43, 127, 255') || hoverInfo.bc !== 'rgb(23, 23, 23)', hoverInfo.bc);
ok('hover 封面微缩放 1.02', hoverInfo.img.includes('matrix'), hoverInfo.img.slice(0, 50));
await page.mouse.move(700, 500);
await page.waitForTimeout(400);
const unhoverTf = await face.evaluate(el => getComputedStyle(el).transform);
ok('移开后回正（identity 或 none）', unhoverTf === 'none' || unhoverTf === 'matrix(1, 0, 0, 1, 0, 0)', unhoverTf.slice(0, 40));

console.log('== 页码点 ==');
const dots = await guitar.locator('[role="tablist"] button').count();
ok('页码点数量 ≥ 5', dots >= 5, 'dots=' + dots);
const curDot = await guitar.locator('.folio-dot.bg-signal').count();
ok('当前页点高亮（信号蓝）', curDot >= 1, 'count=' + curDot);
ok('页码点无弹性动画（克制）',
  (await guitar.locator('.folio-dot').first().evaluate(el => getComputedStyle(el).animationName)) === 'none');

console.log('== 控制台与截图 ==');
ok('桌面端控制台零报错', errors.length === 0, errors.join(' | '));
await page.screenshot({ path: path.join(EVIDENCE, 'desktop-top.png') });
await guitar.screenshot({ path: path.join(EVIDENCE, 'folio-idle.png'), animations: 'disabled' });
// 切换中帧
await guitar.locator('.folio-nav').nth(1).click();
await page.waitForTimeout(100);
await page.screenshot({ path: path.join(EVIDENCE, 'switch-out.png') });
await page.waitForTimeout(500);
await guitar.screenshot({ path: path.join(EVIDENCE, 'folio-flipped.png'), animations: 'disabled' });
await guitar.locator('.folio-nav').nth(0).click();
await page.waitForTimeout(600);

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
