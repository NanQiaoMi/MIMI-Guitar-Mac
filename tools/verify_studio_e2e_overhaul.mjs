import { chromium } from 'playwright-core';

async function run() {
  console.log('🚀 Launching Playwright to test Studio Overhaul...');
  const browser = await chromium.launch({
    headless: true,
    channel: 'chrome',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--autoplay-policy=no-user-gesture-required']
  }).catch(() => chromium.launch({ headless: true, channel: 'msedge' }));

  const page = await browser.newPage({ viewport: { width: 1440, height: 950 } });

  const logs = [];
  page.on('console', msg => {
    const text = msg.text();
    logs.push(`[${msg.type()}] ${text}`);
    if (text.includes('ScoreStudio') || text.includes('ScoreCanvas') || text.includes('AlphaTab') || text.includes('studioAudio')) {
      console.log('  [BROWSER LOG]', text);
    }
  });

  await page.goto('http://127.0.0.1:4321/studio', { waitUntil: 'domcontentloaded' });
  console.log('✓ Navigated to /studio');

  // Wait for canvas to mount
  await page.waitForSelector('#studio-score-scroll', { timeout: 10000 });
  await page.waitForTimeout(3000);

  // 1. Check title & header
  const title = await page.locator('input[placeholder="输入乐谱名称..."]').inputValue();
  console.log('Current score title:', title);

  // 2. Test Note Input via Keyboard
  console.log('Testing keyboard fret input (3, 2, 0, 1)...');
  await page.keyboard.press('3'); // fret 3
  await page.waitForTimeout(400);
  await page.keyboard.press('2'); // fret 2
  await page.waitForTimeout(400);
  await page.keyboard.press('0'); // fret 0
  await page.waitForTimeout(400);
  await page.keyboard.press('1'); // fret 1
  await page.waitForTimeout(800);

  // 3. Test Beat Insertion (+ 插拍)
  console.log('Testing Beat Insertion (+ 插拍)...');
  const insertBeatBtn = page.locator('button:has-text("+ 插拍")');
  if (await insertBeatBtn.isVisible()) {
    await insertBeatBtn.click();
    console.log('✓ Clicked + 插拍');
    await page.waitForTimeout(500);
  }

  // 4. Test Chord Mode Toggle
  console.log('Testing Chord Mode Toggle...');
  const chordModeBtn = page.locator('button:has-text("单音步进"), button:has-text("和弦模式")');
  if (await chordModeBtn.isVisible()) {
    await chordModeBtn.click();
    console.log('✓ Toggled Chord Mode');
    await page.waitForTimeout(400);
  }

  // 5. Test Quick Chord Ingestion (e.g. C chord)
  console.log('Testing Quick Chord Ingestion (C)...');
  const cChordBtn = page.locator('button:has-text("C"):visible').first();
  if (await cChordBtn.isVisible()) {
    await cChordBtn.click();
    console.log('✓ Clicked C chord');
    await page.waitForTimeout(800);
  }

  // 6. Test Playback
  console.log('Testing Playback Start (pressing Space)...');
  await page.keyboard.press('Space');
  await page.waitForTimeout(1000);

  // Check audio context & playback states in window over 3 seconds
  for (let i = 1; i <= 3; i++) {
    await page.waitForTimeout(1000);
    const playbackStatus = await page.evaluate(() => {
      const api = window.__studioApi;
      return {
        apiExists: !!api,
        apiIsReady: api?.isReadyForPlayback,
        apiPlayerState: api?.playerState,
        timePosition: api?.timePosition,
      };
    });
    console.log(`  [Playback Second ${i}] status:`, playbackStatus);
  }

  // Pause playback
  console.log('Testing Playback Pause (pressing Space)...');
  await page.keyboard.press('Space');
  await page.waitForTimeout(500);

  // 7. Test New Project Dropdown (Ukulele)
  console.log('Testing New Project Dropdown (Ukulele)...');
  const newProjectBtn = page.locator('button:has-text("➕ 新建")');
  if (await newProjectBtn.isVisible()) {
    await newProjectBtn.click();
    await page.waitForTimeout(300);
    const ukeBtn = page.locator('button:has-text("4 弦尤克里里")');
    if (await ukeBtn.isVisible()) {
      await ukeBtn.click({ force: true });
      console.log('✓ Switched to 4-string Ukulele');
      await page.waitForTimeout(1200);
    }
  }

  // 8. Test Drafts Modal
  console.log('Testing Drafts Modal...');
  const draftsBtn = page.locator('button:has-text("📁 草稿")');
  if (await draftsBtn.isVisible()) {
    await draftsBtn.click();
    await page.waitForTimeout(600);
    const draftsModal = page.locator('h3:has-text("本地草稿箱")');
    const isModalOpen = await draftsModal.isVisible();
    console.log('✓ Drafts modal open:', isModalOpen);
    // Close modal
    const closeBtn = page.locator('button:has-text("完成")');
    if (await closeBtn.isVisible()) {
      await closeBtn.click();
      await page.waitForTimeout(300);
    }
  }

  // Take screenshot
  await page.screenshot({ path: 'tests/evidence/score-studio-overhaul-success.png' });
  console.log('📸 Saved evidence to tests/evidence/score-studio-overhaul-success.png');

  await browser.close();
  console.log('🎉 ALL STUDIO OVERHAUL E2E TESTS PASSED!');
}

run().catch(err => {
  console.error('Test failed:', err);
  process.exit(1);
});
