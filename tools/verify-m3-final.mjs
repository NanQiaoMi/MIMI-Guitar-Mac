import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
mkdirSync('tests/evidence', { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const urls = [
  'http://localhost:4321/',
  'http://localhost:4321/tabs?difficulty=2&sheetForm=1',
  'http://localhost:4321/ukulele',
  'http://localhost:4321/search?q=%E6%99%B4%E5%A4%A9',
  'http://localhost:4321/article',
  'http://localhost:4321/about',
];
const results = [];
for (const u of urls) {
  const errs = [];
  const onC = (m) => { if (m.type() === 'error') errs.push(m.text()); };
  const onE = (e) => errs.push(String(e));
  page.on('console', onC);
  page.on('pageerror', onE);
  const resp = await page.goto(u, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(600);
  const h1 = await page.locator('h1').first().textContent().catch(() => null);
  const name = u.replace('http://localhost:4321/', '').replace(/[?=&]/g, '_').slice(0, 40) || 'home';
  await page.screenshot({ path: 'tests/evidence/m3-' + name + '.png' });
  results.push({ url: u, status: resp.status(), h1: (h1 || '').trim().slice(0, 40), errors: errs });
  page.removeListener('console', onC);
  page.removeListener('pageerror', onE);
}
// player detail page deep check
const errs = [];
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
page.on('pageerror', (e) => errs.push(String(e)));
await page.goto('http://localhost:4321/tabs/1sdc49P3eKm', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(4000);
const svgCount = await page.locator('#score-scroll svg').count().catch(() => 0);
const playBtn = page.locator('button:has-text("播放")').first();
let played = false;
if (await playBtn.count()) {
  await playBtn.click();
  await page.waitForTimeout(1500);
  const cursor = await page.locator('.at-cursor-beat, .at-highlight').count().catch(() => 0);
  played = cursor > 0;
}
await page.screenshot({ path: 'tests/evidence/m3-detail-player.png' });
results.push({ url: 'http://localhost:4321/tabs/1sdc49P3eKm', svgCount, played, errors: errs });
console.log('M3FINAL:' + JSON.stringify(results, null, 2));
await browser.close();