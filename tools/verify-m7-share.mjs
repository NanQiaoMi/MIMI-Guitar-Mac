import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, permissions: ['clipboard-write', 'clipboard-read'] });
const page = await ctx.newPage();
await page.goto('http://localhost:4321/tabs/1sdc49P3eKm', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(2000);
// read clipboard text
let got = '';
page.on('console', (m) => { if (m.text().includes('share')) got = m.text(); });
await page.getByRole('button', { name: '分享曲谱' }).click();
await page.waitForTimeout(500);
const btnText = await page.getByRole('button', { name: /分享曲谱|已复制链接/ }).textContent();
let clip = null;
try { clip = await page.evaluate(() => navigator.clipboard.readText().catch(() => null)); } catch { clip = null; }
console.log('SHARE:' + JSON.stringify({ btnText: btnText.trim(), clipContainsUrl: typeof clip === 'string' && clip.includes('/tabs/1sdc49P3eKm') }));
await browser.close();
