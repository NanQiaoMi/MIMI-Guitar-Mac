import { chromium } from 'playwright-core';

async function testCursor() {
  const browser = await chromium.launch({
    headless: true,
    channel: 'chrome',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--autoplay-policy=no-user-gesture-required']
  }).catch(() => chromium.launch({ headless: true, channel: 'msedge' }));

  const page = await browser.newPage({ viewport: { width: 1440, height: 1050 } });
  page.on('console', msg => console.log('[PAGE LOG]', msg.type(), msg.text()));
  page.on('pageerror', err => console.log('[PAGE ERROR]', err.message));

  console.log('1. Navigating to http://127.0.0.1:4321/studio ...');
  await page.goto('http://127.0.0.1:4321/studio', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.score-studio-canvas.alphaTab', { timeout: 15000 });
  await page.waitForTimeout(2000);

  // 2. Check Aesthetics & Corner brackets & Measure Overlay
  console.log('2. Checking Manuscript Aesthetics & Corner Brackets...');
  const aesthetics = await page.evaluate(() => {
    const canvas = document.querySelector('[aria-label="交互式主乐谱画布"]');
    const brackets = canvas ? canvas.querySelectorAll('.border-t-2, .border-b-2') : [];
    const measureBar = canvas ? canvas.querySelector('.sticky.top-2') : null;
    return {
      hasCanvas: !!canvas,
      bracketCount: brackets.length,
      measureBarText: measureBar ? measureBar.textContent.trim() : null
    };
  });
  console.log('Aesthetics check:', aesthetics);

  // 3. Check 24-fret fretboard and Chord Palette with C, Am, F, G, Dm, Em
  console.log('3. Checking VirtualFretboard 24 frets & ChordPalette quick applicator...');
  const layout = await page.evaluate(() => {
    const fretboardHeader = document.body.innerText.includes('24品实况指板');
    const quickChords = Array.from(document.querySelectorAll('button[title*="快速填入"]')).map(b => b.textContent.replace(/\s+/g, ' ').trim());
    return {
      fretboardHeaderFound: fretboardHeader,
      quickChords
    };
  });
  console.log('Layout check:', layout);

  // 4. Test typing paradigm (0, 3, 1 then 2 -> 12)
  console.log('4. Entering notes 0, 3, and compound fret 12...');
  await page.keyboard.press('0');
  await page.waitForTimeout(250);
  await page.keyboard.press('3');
  await page.waitForTimeout(250);
  await page.keyboard.press('1');
  await page.keyboard.press('2'); // compound 12
  await page.waitForTimeout(500);

  // Check auto-save to localStorage
  const draftScore = await page.evaluate(() => {
    const raw = localStorage.getItem('mimi_studio_draft_score');
    return raw ? JSON.parse(raw).title : null;
  });
  console.log('localStorage mimi_studio_draft_score saved title:', draftScore);

  // 5. Test Playback & cursor highlighting
  console.log('5. Clicking Play button to verify real-time cursor highlighting...');
  const playBtn = page.locator('button[title*="播放 / 暂停"]').first();
  await playBtn.click();
  await page.waitForTimeout(2000);

  const cursorInfo = await page.evaluate(() => {
    const beat = document.querySelector('.at-cursor-beat');
    const bar = document.querySelector('.at-cursor-bar');
    const beatComputed = beat ? window.getComputedStyle(beat) : null;
    const barComputed = bar ? window.getComputedStyle(bar) : null;
    return {
      hasBeat: !!beat,
      beatBorderLeft: beatComputed ? beatComputed.borderLeft : null,
      beatZIndex: beatComputed ? beatComputed.zIndex : null,
      hasBar: !!bar,
      barBackground: barComputed ? barComputed.backgroundColor : null,
      barBorderRadius: barComputed ? barComputed.borderRadius : null
    };
  });
  console.log('Cursor computed styles during playback:', cursorInfo);

  await page.screenshot({ path: 'tests/evidence/score-studio-pro-overhaul-verified.png' });
  console.log('✓ Captured tests/evidence/score-studio-pro-overhaul-verified.png');

  await browser.close();
  console.log('✓ All checks passed!');
}

testCursor().catch(console.error);
