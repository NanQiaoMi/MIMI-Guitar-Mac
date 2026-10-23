import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const results = [];
for (const w of [1440, 390]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: 1000 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
  page.on('pageerror', (e) => errs.push(String(e)));
  const resp = await page.goto('http://localhost:4321/', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1200);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  // hot tab switch
  const hotBtns = page.locator('button.chip');
  const hotCount = await hotBtns.count();
  if (w === 1440 && hotCount >= 3) {
    await hotBtns.nth(1).click();
    await page.waitForTimeout(200);
  }
  // difficulty toggle to ukulele
  const diffBtns = page.locator('section >> nth=3 >> button.chip');
  if (w === 1440) {
    await diffBtns.nth(1).click();
    await page.waitForTimeout(200);
  }
  results.push({ w, status: resp ? resp.status() : null, overflow, hotBtns: hotCount, errs });
  if (w === 1440) await page.screenshot({ path: 'tests/evidence/m7/m7-home-new.png', fullPage: false });
  await ctx.close();
}
const failures = results.filter((r) => r.status !== 200 || r.overflow || r.errs.length);
console.log('M74:' + JSON.stringify({ total: results.length, failures: failures.length, results }, null, 2));
await browser.close();
