import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const urls = ['http://localhost:4321/', 'http://localhost:4321/tabs/1sdc49P3eKm', 'http://localhost:4321/ukulele/1wmj8hqHnYf'];
const results = [];
for (const u of urls) {
  const consoleErrors = [];
  const pageErrors = [];
  const onConsole = (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); };
  const onErr = (e) => pageErrors.push(String(e));
  page.on('console', onConsole);
  page.on('pageerror', onErr);
  const resp = await page.goto(u, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  const svg = await page.locator('#score-scroll svg').count().catch(() => 0);
  results.push({ url: u, status: resp.status(), svg, consoleErrors, pageErrors });
  page.removeListener('console', onConsole);
  page.removeListener('pageerror', onErr);
}
console.log('SMOKE:', JSON.stringify(results, null, 2));
await browser.close();
