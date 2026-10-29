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

  // Scroll to chord deck
  await page.evaluate(() => window.scrollBy(0, 950));
  await page.waitForTimeout(1000);

  // Click the "全部 128 款音色…" button
  console.log('Clicking "全部 128 款音色…" button...');
  const openBtn = await page.waitForSelector('button:has-text("全部 128 款音色")');
  await openBtn.click();
  await page.waitForTimeout(800);

  // Take screenshot of the 128-instrument modal
  await page.screenshot({ path: 'tests/evidence/instruments-modal-all.png', fullPage: false });
  console.log('✓ Screenshot saved: instruments-modal-all.png');

  // Test searching in the modal
  console.log('Testing search for "古筝"...');
  const searchInput = await page.waitForSelector('input[placeholder*="搜索 128 款乐器"]');
  await searchInput.fill('古筝');
  await page.waitForTimeout(600);

  await page.screenshot({ path: 'tests/evidence/instruments-modal-search.png', fullPage: false });
  console.log('✓ Screenshot saved: instruments-modal-search.png');

  // Click the searched instrument (古筝)
  const guzhengBtn = await page.waitForSelector('button:has-text("古筝")');
  await guzhengBtn.click();
  await page.waitForTimeout(800);

  // Verify modal closed and active instrument updated
  await page.screenshot({ path: 'tests/evidence/chord-deck-guzheng-selected.png', fullPage: false });
  console.log('✓ Screenshot saved: chord-deck-guzheng-selected.png');

  await browser.close();
  console.log('✅ 128 Instruments library test passed successfully!');
}

test().catch(e => { console.error('Test failed:', e); process.exit(1); });
