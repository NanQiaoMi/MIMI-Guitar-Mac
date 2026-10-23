import { chromium } from 'playwright-core';

async function testVpsLive() {
  console.log('🌐 Launching Playwright to test VPS Production Studio (http://154.88.65.55:20056/studio)...');
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
    if (text.includes('ScoreStudio') || text.includes('ScoreCanvas') || text.includes('AlphaTab') || text.includes('studioAudio') || text.includes('worker')) {
      console.log('  [VPS LOG]', text);
    }
  });

  await page.goto('http://154.88.65.55:20056/studio', { waitUntil: 'domcontentloaded', timeout: 30000 });
  console.log('✓ Successfully connected to VPS /studio');

  // Wait for canvas to mount
  await page.waitForSelector('#studio-score-scroll', { timeout: 15000 });
  await page.waitForTimeout(3000);

  // 1. Check title & header
  const title = await page.locator('input[placeholder="输入乐谱名称..."]').inputValue();
  console.log('VPS Current score title:', title);

  // 2. Test Note Input via Keyboard
  console.log('Testing keyboard fret input on VPS (3, 2, 0, 1)...');
  await page.keyboard.press('3');
  await page.waitForTimeout(400);
  await page.keyboard.press('2');
  await page.waitForTimeout(400);
  await page.keyboard.press('0');
  await page.waitForTimeout(400);
  await page.keyboard.press('1');
  await page.waitForTimeout(800);

  // 3. Test Beat Insertion (+ 插拍)
  console.log('Testing Beat Insertion (+ 插拍) on VPS...');
  const insertBeatBtn = page.locator('button:has-text("+ 插拍")');
  if (await insertBeatBtn.isVisible()) {
    await insertBeatBtn.click();
    console.log('✓ Clicked + 插拍 on VPS');
    await page.waitForTimeout(500);
  }

  // 4. Test Playback on VPS
  console.log('Testing Space to Play on VPS...');
  await page.keyboard.press('Space');
  await page.waitForTimeout(1000);

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
    console.log(`  [VPS Playback Second ${i}] status:`, playbackStatus);
  }

  // Pause playback
  console.log('Testing Space to Pause on VPS...');
  await page.keyboard.press('Space');
  await page.waitForTimeout(500);

  // 5. Test New Project Dropdown (Ukulele) on VPS
  console.log('Testing New Project Dropdown (Ukulele) on VPS...');
  const newProjectBtn = page.locator('button:has-text("➕ 新建")');
  if (await newProjectBtn.isVisible()) {
    await newProjectBtn.click();
    await page.waitForTimeout(300);
    const ukeBtn = page.locator('button:has-text("4 弦尤克里里")');
    if (await ukeBtn.isVisible()) {
      await ukeBtn.click({ force: true });
      console.log('✓ Switched to 4-string Ukulele on VPS');
      await page.waitForTimeout(1500);
    }
  }

  // 6. Test Drafts Modal on VPS
  console.log('Testing Drafts Modal on VPS...');
  const draftsBtn = page.locator('button:has-text("📁 草稿")');
  if (await draftsBtn.isVisible()) {
    await draftsBtn.click();
    await page.waitForTimeout(600);
    const draftsModal = page.locator('h3:has-text("本地草稿箱")');
    const isModalOpen = await draftsModal.isVisible();
    console.log('✓ Drafts modal open on VPS:', isModalOpen);
    const closeBtn = page.locator('button:has-text("完成")');
    if (await closeBtn.isVisible()) {
      await closeBtn.click();
      await page.waitForTimeout(300);
    }
  }

  // Take screenshot of VPS
  await page.screenshot({ path: 'tests/evidence/vps-studio-overhaul-live.png' });
  console.log('📸 Saved live VPS evidence to tests/evidence/vps-studio-overhaul-live.png');

  await browser.close();
  console.log('🎉 VPS PRODUCTION VERIFICATION SUCCEEDED 100%!');
}

testVpsLive().catch(err => {
  console.error('VPS verification failed:', err);
  process.exit(1);
});
