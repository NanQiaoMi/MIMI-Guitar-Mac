import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const urls = [
  ['/tabs/1sdc49P3eKm', '晴天（基准）'],
  ['/tabs/oODd6Upb', 'Dream Theater 长曲'],
  ['/tabs/a144ec0da3e3', 'Canon Rock 上传谱'],
];
const results = [];
for (const [path, label] of urls) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push(String(e)));
  const t0 = Date.now();
  await page.goto('http://localhost:4321' + path, { waitUntil: 'domcontentloaded', timeout: 60000 });
  let firstSvg = -1;
  let svgCount = 0;
  for (let i = 0; i < 200; i++) {
    await page.waitForTimeout(100);
    const n = await page.locator('#score-scroll svg').count().catch(() => 0);
    if (n > 0 && firstSvg < 0) firstSvg = Date.now() - t0;
    if (n > 0 && n === svgCount && i > 5) break;
    svgCount = n;
  }
  const total = Date.now() - t0;
  const heap = await page.evaluate(() => (performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : -1)).catch(() => -1);
  results.push({ label, firstSvgMs: firstSvg, totalMs: total, svgCount, heapMB: heap, errors });
  await ctx.close();
}
console.log('PERF:' + JSON.stringify(results, null, 2));
await browser.close();