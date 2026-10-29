import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const urls = [
  'http://localhost:4321/article',
  'http://localhost:4321/article/art-newbie',
  'http://localhost:4321/article/art-tab',
  'http://localhost:4321/about',
  'http://localhost:4321/help',
  'http://localhost:4321/policy',
  'http://localhost:4321/copyrightPolicy',
  'http://localhost:4321/licenses',
  'http://localhost:4321/contact',
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
    await page.waitForTimeout(500);
  } catch (e) { pageErrors.push('goto: ' + e.message); }
  const h1 = await page.locator('h1').first().textContent().catch(() => null);
  const cards = await page.locator('a.card, .card').count().catch(() => 0);
  results.push({ url: u, status: resp ? resp.status() : null, h1: (h1 || '').trim().slice(0, 40), cards, consoleErrors, pageErrors });
  page.removeListener('console', onConsole);
  page.removeListener('pageerror', onErr);
}
console.log('M3STATIC:' + JSON.stringify(results, null, 2));
await browser.close();