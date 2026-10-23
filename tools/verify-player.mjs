
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = 'tests/evidence/';
fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const ctx = await browser.newContext({ acceptDownloads: true, viewport: { width: 1440, height: 1000 } });

async function runSuite(url, label) {
  const page = await ctx.newPage();
  const results = { label };
  const consoleErrors = [];
  const pageErrors = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', (e) => pageErrors.push(String(e)));
  const resp = await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
  results.http = resp.status();
  try { await page.waitForSelector('#score-scroll svg', { timeout: 30000 }); results.render = true; } catch { results.render = false; }
  await page.waitForTimeout(2000);
  // play
  try { await page.locator('button', { hasText: '播放' }).first().click({ timeout: 8000 }); results.play = true; } catch { results.play = false; }
  await page.waitForTimeout(3000);
  try { await page.waitForSelector('.at-cursor-beat', { state: 'visible', timeout: 8000 }); results.cursor = true; } catch { results.cursor = false; }
  // stop
  try { await page.locator('button', { hasText: '重来' }).first().click({ timeout: 5000 }); results.stop = true; } catch { results.stop = false; }
  // screenshot
  await page.screenshot({ path: OUT + label + '-score.png', fullPage: true });
  results.consoleErrors = consoleErrors;
  results.pageErrors = pageErrors;
  await page.close();
  return results;
}

const guitar = await runSuite('http://localhost:4321/tabs/1sdc49P3eKm', 'guitar');
const uku = await runSuite('http://localhost:4321/ukulele/1wmj8hqHnYf', 'ukulele');
console.log('GUITAR:', JSON.stringify(guitar, null, 2));
console.log('UKULELE:', JSON.stringify(uku, null, 2));
await browser.close();
