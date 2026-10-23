// XHE 文本谱渲染验收：JSON 和弦锚点谱（和弦图/歌词/标题/节奏/TAB）与纯文本谱
// 用法：node tools/verify-xhe.mjs  （需本地 dev server 4321 运行中）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/xhe';
fs.mkdirSync(EVIDENCE, { recursive: true });

let pass = 0, fail = 0;
const failures = [];

function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log(`  ✔ ${name}`); }
  else { fail++; failures.push(name + (extra ? ` — ${extra}` : '')); console.log(`  ✖ ${name}${extra ? ' — ' + extra : ''}`); }
}

async function openScore(page, url) {
  await page.goto(`${BASE}${url}`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(2500);
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 200)); });
page.on('pageerror', e => consoleErrors.push(e.message.slice(0, 200)));

console.log('== JSON 和弦锚点谱（赤伶）==');
await openScore(page, '/tabs/1Oy6kL4FS');
let r = await page.evaluate(() => ({
  xhe: !!document.querySelector('.xhe-viewer'),
  player: !!document.querySelector('#score-scroll'),
  loadFail: /加载失败/.test(document.body.innerText),
  svg: document.querySelectorAll('.xhe-viewer svg').length,
  lines: document.querySelectorAll('.xhe-line').length,
  rows: document.querySelectorAll('.xhe-chord-row').length,
  download: /免费下载/.test(document.body.innerText),
  hasDingDiao: document.body.innerText.includes('定调用'),
}));
ok('XHE 视图渲染', r.xhe && !r.player);
ok('无「加载失败」', !r.loadFail);
ok('和弦图数量 > 0', r.svg > 50, String(r.svg));
ok('歌词行渲染', r.lines > 10, String(r.lines));
ok('纯和弦行渲染', r.rows > 0, String(r.rows));
ok('XHE 不显示免费下载按钮', !r.download);
ok('歌词/和弦文本可见', r.hasDingDiao);
await page.screenshot({ path: path.join(EVIDENCE, 'json-chiling.png') });

console.log('== JSON 和弦锚点谱（平凡之路，含 HEADLINE/RHYTHM）==');
await openScore(page, '/tabs/1Oy5N2MHF');
r = await page.evaluate(() => ({
  headlines: document.querySelectorAll('.xhe-headline').length,
  lines: document.querySelectorAll('.xhe-line').length,
  rows: document.querySelectorAll('.xhe-chord-row').length,
  rhythm: document.querySelectorAll('.xhe-rhythm').length,
  hasLyric: document.body.innerText.includes('徘徊着的'),
  svg: document.querySelectorAll('.xhe-viewer svg').length,
}));
ok('HEADLINE 区块渲染', r.headlines > 5, String(r.headlines));
ok('歌词行渲染', r.lines > 10, String(r.lines));
ok('纯和弦行渲染', r.rows > 0, String(r.rows));
ok('节奏块渲染（含 RHYTHM 的谱）', r.rhythm > 0, String(r.rhythm));
ok('歌词文本可见', r.hasLyric);
ok('和弦图数量正确（176）', r.svg === 176, String(r.svg));
await page.screenshot({ path: path.join(EVIDENCE, 'json-pingfan.png') });

console.log('== 纯文本 XHE（尤克里里/吉他文本谱）==');
await openScore(page, '/ukulele/uok8Psac');
r = await page.evaluate(() => ({
  xhe: !!document.querySelector('.xhe-viewer'),
  pre: document.querySelectorAll('.xhe-text').length,
  hasTabText: document.body.innerText.includes('Ukulele tab!!'),
  loadFail: /加载失败/.test(document.body.innerText),
}));
ok('纯文本谱以 <pre> 渲染', r.xhe && r.pre === 1, String(r.pre));
ok('文本内容完整', r.hasTabText);
ok('无「加载失败」', !r.loadFail);
await page.screenshot({ path: path.join(EVIDENCE, 'text-uku.png') });

await openScore(page, '/tabs/1Oy5N2MHG');
r = await page.evaluate(() => ({
  xhe: !!document.querySelector('.xhe-viewer'),
  player: !!document.querySelector('#score-scroll'),
  loadFail: /加载失败/.test(document.body.innerText),
}));
ok('混合型（JSON+TAB）XHE 正常', r.xhe && !r.player);
ok('无「加载失败」', !r.loadFail);

console.log('== 移动端 390px ==');
await page.setViewportSize({ width: 390, height: 844 });
await openScore(page, '/tabs/1Oy5N2MHF');
r = await page.evaluate(() => ({
  xhe: !!document.querySelector('.xhe-viewer'),
  loadFail: /加载失败/.test(document.body.innerText),
  horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth + 4,
}));
ok('移动端 XHE 正常', r.xhe && !r.loadFail);
ok('移动端无整页横向溢出', !r.horizontalOverflow, String(r.horizontalOverflow));
await page.screenshot({ path: path.join(EVIDENCE, 'json-pingfan-mobile.png') });

console.log('== GP 谱不回归 ==');
await page.setViewportSize({ width: 1440, height: 1000 });
await openScore(page, '/tabs/11NiMl4Nx');
r = await page.evaluate(() => ({
  xhe: !!document.querySelector('.xhe-viewer'),
  player: !!document.querySelector('#score-scroll'),
  download: /免费下载/.test(document.body.innerText),
  loadFail: /加载失败/.test(document.body.innerText),
}));
ok('GP 谱仍走播放器', r.player && !r.xhe);
ok('GP 谱保留下载按钮', r.download);
ok('GP 谱无「加载失败」', !r.loadFail);

const netErrors = consoleErrors.filter(e => !/favicon/i.test(e));
ok('全程 console/pageerror 零报错', netErrors.length === 0, netErrors.slice(0, 3).join(' | '));

await browser.close();

console.log(`\n结果：${pass} PASS / ${fail} FAIL`);
if (fail > 0) { console.log('失败项：'); failures.forEach(f => console.log('  - ' + f)); process.exit(1); }
