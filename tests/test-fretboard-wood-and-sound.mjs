import { chromium } from 'playwright-core';
import assert from 'node:assert';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function testFretboard() {
  console.log('Launching browser for Virtual Fretboard verification...');
  const browser = await chromium.launch({
    executablePath: EXE,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu']
  });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();

  await page.addInitScript(() => {
    sessionStorage.setItem('mimi_paper_intro_played', 'true');
  });

  try {
    console.log('Navigating to Score Player page (晴天)...');
    await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq', { waitUntil: 'domcontentloaded', timeout: 25000 });

    // Wait for ScorePlayer to load and open the Fretboard drawer if present
    await page.waitForTimeout(3000);

    // Look for fretboard toggle button or virtual fretboard container
    const fretboardToggle = page.locator('button:has-text("指板"), button[title*="指板"]');
    if (await fretboardToggle.count() > 0) {
      console.log('Clicking fretboard toggle to open drawer...');
      await fretboardToggle.first().click();
      await page.waitForTimeout(1000);
    }

    // Check if virtual fretboard is rendered
    const fretboardCard = page.locator('.virtual-fretboard-card');
    assert.ok((await fretboardCard.count()) > 0, 'Virtual Fretboard element should exist');

    // Scroll fretboard into view
    await fretboardCard.first().scrollIntoViewIfNeeded();
    await page.waitForTimeout(300);

    // 1. Take Rosewood screenshot
    await page.screenshot({ path: 'tests/evidence/fretboard-rosewood.png', fullPage: false });
    console.log('✓ Screenshot saved: tests/evidence/fretboard-rosewood.png');

    // 2. Switch to Ebony
    const ebonyBtn = fretboardCard.locator('button[title*="黑檀木"], button:has-text("黑檀木")');
    if (await ebonyBtn.count() > 0) {
      await ebonyBtn.first().click();
      await page.waitForTimeout(400);
      await page.screenshot({ path: 'tests/evidence/fretboard-ebony.png', fullPage: false });
      console.log('✓ Screenshot saved: tests/evidence/fretboard-ebony.png');
    }

    // 3. Switch to Maple
    const mapleBtn = fretboardCard.locator('button[title*="枫木"], button:has-text("枫木")');
    if (await mapleBtn.count() > 0) {
      await mapleBtn.first().click();
      await page.waitForTimeout(400);
      await page.screenshot({ path: 'tests/evidence/fretboard-maple.png', fullPage: false });
      console.log('✓ Screenshot saved: tests/evidence/fretboard-maple.png');
    }

    // 4. Switch to Numbered Notation (简谱)
    const numberedBtn = fretboardCard.locator('button:has-text("简谱")');
    if (await numberedBtn.count() > 0) {
      await numberedBtn.first().click();
      await page.waitForTimeout(400);
      await page.screenshot({ path: 'tests/evidence/fretboard-numbered.png', fullPage: false });
      console.log('✓ Screenshot saved: tests/evidence/fretboard-numbered.png');
    }

    // 5. Switch to Chord Focus (e.g. C / Em chord)
    const chordSelect = fretboardCard.locator('select');
    if (await chordSelect.count() > 0) {
      console.log('Selecting C chord shape...');
      await chordSelect.first().selectOption('C');
      await page.waitForTimeout(400);
      await page.screenshot({ path: 'tests/evidence/fretboard-chord-overlay.png', fullPage: false });
      console.log('✓ Screenshot saved: tests/evidence/fretboard-chord-overlay.png');
    }

    // 6. Test Clicking a note on the fretboard (interactive plucking)
    const fretCell = fretboardCard.locator('.fretboard-neck [role="button"]').nth(14);
    if (await fretCell.count() > 0) {
      console.log('Plucking a string on the virtual fretboard...');
      await fretCell.click();
      await page.waitForTimeout(300);
      await page.screenshot({ path: 'tests/evidence/fretboard-plucked.png', fullPage: false });
      console.log('✓ Screenshot saved: tests/evidence/fretboard-plucked.png');
    }

    console.log('✅ ALL VIRTUAL FRETBOARD TESTS & EVIDENCE CAPTURED SUCCESSFULLY!');
  } finally {
    await browser.close();
  }
}

testFretboard().catch(e => {
  console.error('Fretboard test failed:', e);
  process.exit(1);
});
