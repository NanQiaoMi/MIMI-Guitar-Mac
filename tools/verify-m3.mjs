import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const urls = [
  'http://localhost:4321/',
  'http://localhost:4321/tabs',
  'http://localhost:4321/tabs?difficulty=2',
  'http://localhost:4321/tabs?sort=1&no=2',
  'http://localhost:4321/ukulele',
  'http://localhost:4321/ukulele?sort=1',
  'http://localhost:4321/search',
  'http://localhost:4321/search?q=%E6%99%B4%E5%A4%A9',
  'http://localhost:4321/tabs/1sdc49P3eKm',
];
const results = [];
for (const u of urls) {
  const consoleErrors = [];
  const pageErrors = [];
  const onConsole = (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); };
  const onErr = (e) => pageErrors.push(String(e));
  page.on('console', onConsole);
  page.on('pageerror', onErr);
  let resp = null;
  try {
    resp = await page.goto(u, { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(800);
  } catch (e) {
    pageErrors.push('goto: ' + e.message);
  }
  const cards = await page.locator('a.card').count().catch(() => -1);
  const heading = await page.locator('h1, .font-display').first().textContent().catch(() => null);
  results.push({ url: u, status: resp ? resp.status() : null, cards, heading: (heading || '').trim().slice(0, 50), consoleErrors, pageErrors });
  page.removeListener('console', onConsole);
  page.removeListener('pageerror', onErr);
}
console.log('M3VERIFY:' + JSON.stringify(results, null, 2));
await browser.close();