import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
mkdirSync('tests/evidence/m6', { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const urls = [
  ['/', 'home'],
  ['/tabs?difficulty=2&sheetForm=1', 'tabs'],
  ['/tabs/1sdc49P3eKm', 'detail'],
  ['/search', 'search'],
  ['/article', 'article'],
  ['/login', 'login'],
];
for (const [path, name] of urls) {
  for (const [w, tag] of [[1440, 'd'], [390, 'm']]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: 1000 } });
    const page = await ctx.newPage();
    await page.goto('http://localhost:4321' + path, { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(path.includes('/tabs/1sdc49P3eKm') ? 3500 : 800);
    await page.screenshot({ path: 'tests/evidence/m6/' + name + '-' + tag + '.png' });
    await ctx.close();
  }
}
console.log('SHOTS_DONE');
await browser.close();