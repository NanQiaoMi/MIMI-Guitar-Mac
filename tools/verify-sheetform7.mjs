import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
fs.mkdirSync('tests/evidence/m7', { recursive: true });

const results = [];
const log = (name, ok, detail) => { results.push({ name, ok, detail }); console.log((ok ? 'PASS' : 'FAIL') + ' ' + name + (detail ? ' :: ' + detail : '')); };

const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await ctx.newPage();
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
page.on('pageerror', (e) => errs.push(String(e)));

// 1. 详情页 sheetForm=7 标题与标签
await page.goto(BASE + '/tabs/oOEeEQKJ', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(1500);
const title = await page.title();
log('详情页 title 含六线谱', title.includes('六线谱'), title);
const h1 = (await page.locator('h1').first().textContent().catch(() => '')) || '';
log('详情页 h1 含六线谱', h1.includes('六线谱'), h1.trim().slice(0, 60));
const badge = (await page.locator('text=六线谱').first().textContent().catch(() => '')) || '';
log('详情页出现六线谱标签', badge.includes('六线谱'));
await page.screenshot({ path: 'tests/evidence/m7/sheetform7-detail.png' });

// 2. 列表筛选 sheetForm=4 应包含 sheetForm=7 曲目
await page.goto(BASE + '/tabs?sheetForm=4', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(500);
const listHas = await page.getByText('Master Of Puppets').count();
log('列表 sheetForm=4 含 sheetForm=7 曲目', listHas > 0, 'count=' + listHas);
await page.screenshot({ path: 'tests/evidence/m7/sheetform7-list.png' });

// 3. 首页难度矩阵：六线谱列计数与 DB 一致（含 7 并入 4）
await page.goto(BASE + '/', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(800);
const table = page.locator('table');
const tblCount = await table.count();
let matrixOk = false, matrixDetail = '';
if (tblCount > 0) {
  // 找表头含「六线谱」的列，统计该列全部数字单元格之和
  const data = await page.evaluate(() => {
    const t = document.querySelector('table');
    if (!t) return { headers: [], sums: [] };
    const headers = Array.from(t.querySelectorAll('thead th')).map((th) => th.textContent.trim());
    const sums = [];
    for (let ci = 1; ci < headers.length; ci++) {
      let s = 0;
      t.querySelectorAll('tbody tr').forEach((tr) => {
        const td = tr.children[ci];
        if (td) { const n = parseInt((td.textContent || '').replace(/[^0-9]/g, ''), 10); if (!isNaN(n)) s += n; }
      });
      sums.push(s);
    }
    return { headers, sums };
  });
  const idx = data.headers.findIndex((h) => h.includes('六线谱'));
  if (idx >= 0) {
    const sum = idx > 0 ? (data.sums[idx - 1] ?? 0) : 0; // sums 不含「难度」列
    matrixDetail = 'headers=' + JSON.stringify(data.headers) + ' sums=' + JSON.stringify(data.sums) + ' 六线谱sum=' + sum;
    matrixOk = sum >= 1;
  } else {
    matrixDetail = '未找到六线谱列: ' + JSON.stringify(data.headers);
  }
}
log('首页矩阵含六线谱列且有计数', matrixOk, matrixDetail);
await page.screenshot({ path: 'tests/evidence/m7/sheetform7-home.png' });

log('控制台零报错', errs.length === 0, errs.slice(0, 5).join(' | '));
await browser.close();

const fail = results.filter((r) => !r.ok);
console.log('SHEETFORM7_RESULT: ' + JSON.stringify({ total: results.length, pass: results.length - fail.length, fail: fail.length }));
process.exit(fail.length ? 1 : 0);
