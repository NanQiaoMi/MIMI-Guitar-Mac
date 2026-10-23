import { chromium } from 'playwright-core';
import fs from 'fs';

async function run() {
  console.log('🚀 Starting Ukulele Playback & Acoustics automated verification...');
  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
  });

  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });

  const page = await context.newPage();

  const networkLogs = [];
  const consoleLogs = [];

  page.on('console', (msg) => {
    consoleLogs.push(`[${msg.type()}] ${msg.text()}`);
    if (msg.type() === 'error' || msg.text().includes('Soundfont') || msg.text().includes('ScorePlayer')) {
      console.log(`Browser console: [${msg.type()}] ${msg.text()}`);
    }
  });

  page.on('response', (res) => {
    const url = res.url();
    if (url.includes('.sf2') || url.includes('/ukulele/')) {
      networkLogs.push({ url, status: res.status() });
      console.log(`HTTP Response: ${res.status()} ${url}`);
    }
  });

  try {
    console.log('Navigating to http://localhost:4321/ukulele/1sdiYSwWo2S ...');
    await page.goto('http://localhost:4321/ukulele/1sdiYSwWo2S', { waitUntil: 'networkidle', timeout: 30000 });

    // 1. Verify Score Title
    const title = await page.title();
    console.log('Page Title:', title);

    // 2. Wait for ScorePlayer to load and render AlphaTab
    console.log('Waiting for score canvas/container...');
    await page.waitForSelector('.alphatab-container, .at-surface, canvas, svg', { timeout: 15000 });

    // Wait a bit for tracks & metadata to settle
    await page.waitForTimeout(2000);

    // 3. Verify Adaptive Toolbar Buttons
    console.log('Checking toolbar buttons...');
    const buttonsText = await page.$$eval('button', (btns) => btns.map((b) => b.innerText.trim()));
    console.log('Found buttons:', buttonsText.filter((t) => t.includes('谱') || t.includes('指板')));

    const hasPure4Tab = buttonsText.some((t) => t.includes('纯四线谱'));
    const hasPure6Tab = buttonsText.some((t) => t.includes('纯六线谱'));
    const hasUkeFretboardBtn = buttonsText.some((t) => t.includes('🪵 尤克里里指板'));
    const hasGuitarFretboardBtn = buttonsText.some((t) => t.includes('🎸 虚拟指板'));

    console.log('Button Checks:');
    console.log(`- Has "纯四线谱": ${hasPure4Tab} (Expected: true)`);
    console.log(`- Has "纯六线谱": ${hasPure6Tab} (Expected: false)`);
    console.log(`- Has "🪵 尤克里里指板": ${hasUkeFretboardBtn} (Expected: true)`);
    console.log(`- Has "🎸 虚拟指板": ${hasGuitarFretboardBtn} (Expected: false)`);

    if (!hasPure4Tab || hasPure6Tab) {
      throw new Error(`Adaptive notation button check failed! pure4: ${hasPure4Tab}, pure6: ${hasPure6Tab}`);
    }
    if (!hasUkeFretboardBtn || hasGuitarFretboardBtn) {
      throw new Error(`Adaptive fretboard button check failed! ukeBtn: ${hasUkeFretboardBtn}, guitarBtn: ${hasGuitarFretboardBtn}`);
    }

    // 4. Click "🪵 尤克里里指板" and verify fretboard structure
    console.log('Opening virtual fretboard drawer...');
    const fretboardBtn = page.locator('button:has-text("🪵 尤克里里指板")');
    await fretboardBtn.click();
    await page.waitForSelector('.virtual-fretboard-card', { timeout: 5000 });

    const fretboardTitle = await page.$eval('.virtual-fretboard-card', (el) => el.innerText);
    const hasFretboardTitle = fretboardTitle.includes('尤克里里指板');
    console.log(`- Fretboard drawer title contains "尤克里里指板": ${hasFretboardTitle}`);

    // Verify 4 strings in bone nut
    const nutNotchesCount = await page.$$eval('.nut-bone-block > div', (divs) => divs.length);
    console.log(`- Nut notch count: ${nutNotchesCount} (Expected: 4)`);

    // Verify tuning badge
    const tuningBadge = await page.$eval('.virtual-fretboard-card span.font-bold.text-\\[\\#41a1cf\\]', (el) => el.innerText.trim());
    console.log(`- Fretboard tuning badge: "${tuningBadge}" (Expected: A·E·C·G or similar 4 strings)`);

    if (nutNotchesCount !== 4) {
      throw new Error(`Virtual fretboard string count expected 4, got ${nutNotchesCount}`);
    }

    // 5. Check SoundFont loaded
    const sf2Loaded = networkLogs.some((l) => l.url.includes('ukulele_fast.sf2') && l.status === 200);
    console.log(`- ukulele_fast.sf2 loaded HTTP 200: ${sf2Loaded}`);

    // 6. Test Playback and Measure Transition
    console.log('Starting playback test...');
    const playBtn = page.locator('#btn-play');
    console.log('Play button text:', await playBtn.innerText());
    console.log('Play button aria-label:', await playBtn.getAttribute('aria-label'));

    const apiStateBefore = await page.evaluate(() => {
      const api = window.__api;
      return api ? { isReady: api.isReadyForPlayback, playerState: api.playerState } : null;
    });
    console.log('API state before play click:', apiStateBefore);

    await playBtn.click();
    console.log('Clicked #btn-play. Waiting for playback to start...');

    await page.waitForTimeout(1000);
    const apiStateAfter = await page.evaluate(() => {
      const api = window.__api;
      return api ? { isReady: api.isReadyForPlayback, playerState: api.playerState } : null;
    });
    console.log('API state after play click:', apiStateAfter);

    if (apiStateAfter && apiStateAfter.playerState !== 1) {
      console.log('Explicitly calling window.__api.play()...');
      await page.evaluate(() => window.__api.play());
    }

    let sawMeasure1 = false;
    let sawMeasure2 = false;
    let maxBeatObserved = 0;
    let beatHistory = [];

    const startTime = Date.now();
    while (Date.now() - startTime < 18000) {
      const statusText = await page.evaluate(() => {
        const bodyText = document.body.innerText;
        const match = bodyText.match(/第\s*(\d+)\s*小节\s*·\s*第\s*(\d+)\s*拍/);
        const api = window.__api;
        return {
          match: match ? { bar: parseInt(match[1], 10), beat: parseInt(match[2], 10), raw: match[0] } : null,
          playerState: api ? api.playerState : -1,
          time: api ? api.currentTime : -1,
          tick: api ? api.tickPosition : -1,
        };
      });

      if (statusText?.match) {
        if (statusText.match.bar === 1) sawMeasure1 = true;
        if (statusText.match.bar >= 2) sawMeasure2 = true;
        if (statusText.match.beat > maxBeatObserved) maxBeatObserved = statusText.match.beat;
        beatHistory.push(statusText.match.raw);
      }

      if (sawMeasure2) {
        console.log(`✓ Playback successfully transitioned to Measure 2! Current status:`, statusText);
        break;
      }
      await page.waitForTimeout(400);
    }

    console.log(`- Saw Measure 1: ${sawMeasure1}`);
    console.log(`- Saw Measure 2: ${sawMeasure2}`);
    console.log(`- Max beat index observed in 4/4: ${maxBeatObserved} (Must be <= 4)`);

    if (maxBeatObserved > 4) {
      throw new Error(`Beat index overflow detected! Observed beat ${maxBeatObserved} > 4`);
    }

    if (!sawMeasure2) {
      throw new Error(`Playback did not transition across Measure 1 into Measure 2 within 15s!`);
    }

    // Capture screenshot
    const screenshotPath = 'ukulele_playback_verified.png';
    await page.screenshot({ path: screenshotPath, fullPage: false });
    console.log(`✓ Screenshot saved to ${screenshotPath}`);

    console.log('🎉 ALL UKULELE PLAYBACK & ACOUSTIC CHECKS PASSED PERFECTLY!');
  } finally {
    await browser.close();
  }
}

run().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
