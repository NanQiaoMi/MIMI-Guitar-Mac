import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1200 } });
  const page = await context.newPage();

  await page.addInitScript(() => {
    sessionStorage.setItem('mimi_paper_intro_played', 'true');
  });

  console.log('Navigating to http://localhost:4321/tabs/1sdcVfeA7Gq ...');
  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);

  // Scroll down to the specs deck & chords area
  await page.evaluate(() => window.scrollBy(0, 950));
  await page.waitForTimeout(1500);

  await page.screenshot({ path: 'tests/evidence/deck-and-chords-preview.png', fullPage: false });
  console.log('✓ Screenshot saved: deck-and-chords-preview.png');

  // Scroll further down to related recommended tabs
  await page.evaluate(() => window.scrollBy(0, 600));
  await page.waitForTimeout(1000);

  await page.screenshot({ path: 'tests/evidence/related-tabs-preview.png', fullPage: false });
  console.log('✓ Screenshot saved: related-tabs-preview.png');

  await browser.close();
  console.log('✅ Visual verification complete!');
}

test().catch(e => { console.error('Test failed:', e); process.exit(1); });
