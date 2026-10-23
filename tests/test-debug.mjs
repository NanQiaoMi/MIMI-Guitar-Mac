import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  // Capture console messages
  const consoleMessages = [];
  page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => consoleMessages.push(`[PAGE ERROR] ${err.message}`));

  // Clear sessionStorage before navigation to force intro playback
  await page.addInitScript(() => {
    sessionStorage.removeItem('mimi_paper_intro_played');
  });

  console.log('Navigating to localhost:4321...');
  const response = await page.goto('http://localhost:4321/', { waitUntil: 'domcontentloaded', timeout: 20000 });
  console.log('Response status:', response?.status());
  console.log('Response URL:', response?.url());

  // Wait for all resources including CSS
  await page.waitForTimeout(4000);

  // Check if CSS loaded
  const bodyBg = await page.evaluate(() => window.getComputedStyle(document.body).backgroundColor);
  console.log('Body background-color:', bodyBg);

  // Check if Svelte hydrated
  const svelteCount = await page.evaluate(() => document.querySelectorAll('[data-svelte-h]').length);
  console.log('Svelte hydrated elements:', svelteCount);

  // Check all script tags
  const scripts = await page.evaluate(() => Array.from(document.querySelectorAll('script[src]')).map(s => s.src));
  console.log('Script tags:', scripts.length);

  // Check for intro-root
  const introRoot = await page.evaluate(() => {
    const el = document.querySelector('.intro-root');
    if (el) return { found: true, display: window.getComputedStyle(el).display };
    return { found: false };
  });
  console.log('intro-root:', introRoot);

  // Check the full HTML body content (first 500 chars)
  const htmlContent = await page.evaluate(() => document.body.innerHTML.substring(0, 800));
  console.log('Body HTML (first 800):\n', htmlContent);

  // Print console messages
  console.log('\n--- Console Messages ---');
  consoleMessages.forEach(m => console.log(m));

  await page.screenshot({ path: 'tests/evidence/intro-debug.png', fullPage: false });
  console.log('\n✓ Debug screenshot saved');

  await browser.close();
}

test().catch(e => { console.error('Test failed:', e.message); process.exit(1); });
