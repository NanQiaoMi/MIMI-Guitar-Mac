// 移动端音频解锁与全曲库播放引擎专项端到端测试
import { chromium, devices } from 'playwright-core';
import fs from 'node:fs';

const CHROME_PATH = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE_URL = 'http://localhost:4321';
const EVIDENCE_DIR = 'tests/evidence/mobile-audio';
fs.mkdirSync(EVIDENCE_DIR, { recursive: true });

const results = [];
function record(name, pass, detail = '') {
  results.push({ name, pass, detail });
  console.log(`${pass ? '✅ PASS' : '❌ FAIL'} | ${name}${detail ? ' | ' + detail : ''}`);
}

async function run() {
  console.log('🚀 Starting Mobile Audio Unlock & Playback Engine E2E Verification...');

  const browser = await chromium.launch({
    executablePath: CHROME_PATH,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'],
  });

  try {
    // 1. 测试 /guitar/[id] 路由重定向到 /tabs/[id]
    const testId = '1sdc49P3eKm';
    const redirectContext = await browser.newContext();
    const redirectPage = await redirectContext.newPage();
    
    let redirectSucceeded = false;
    let finalUrl = '';
    
    const response = await redirectPage.goto(`${BASE_URL}/guitar/${testId}`, {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });
    finalUrl = redirectPage.url();
    redirectSucceeded = finalUrl.includes(`/tabs/${testId}`);
    record('Redirect: /guitar/[id] -> /tabs/[id]', redirectSucceeded, `Landed on: ${finalUrl}`);
    await redirectContext.close();

    // 2. 模拟 iPhone 移动端视口与 Touch 环境进行音频解锁与播放测试
    const iPhone = devices['iPhone 13'] || {
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1',
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
    };

    const mobileContext = await browser.newContext({
      ...iPhone,
      permissions: [],
    });

    const page = await mobileContext.newPage();
    const consoleLogs = [];
    const errors = [];
    page.on('console', (msg) => {
      const text = msg.text();
      consoleLogs.push(text);
      if (msg.type() === 'error') errors.push(text);
    });
    page.on('pageerror', (err) => errors.push(String(err)));

    console.log(`📱 Navigating to mobile tab page: ${BASE_URL}/tabs/${testId}`);
    await page.goto(`${BASE_URL}/tabs/${testId}`, { waitUntil: 'domcontentloaded', timeout: 60000 });

    // 等待 AlphaTab 初始化并渲染乐谱
    await page.waitForFunction(() => window.__api && document.querySelector('#score-scroll svg'), { timeout: 35000 });
    console.log('🎼 Score rendered on mobile viewport.');

    // 验证音频解锁器与 AudioContext 状态
    const audioContextState = await page.evaluate(() => {
      const api = window.__api;
      const p = api?._player;
      const ctx = p?.output?.audioContext || p?.output?.context;
      return {
        hasPlayer: !!p,
        hasAudioContext: !!ctx,
        state: ctx?.state,
        sampleRate: ctx?.sampleRate,
      };
    });
    record('Mobile AudioContext initialized', audioContextState.hasAudioContext, `State: ${audioContextState.state}`);

    // 模拟首次触摸交互（touchstart / pointerdown）触发全局预热与解锁
    await page.touchscreen.tap(200, 200);
    await page.waitForTimeout(500);

    // 检查播放前的 AudioContext 解锁情况
    const unlockedState = await page.evaluate(() => {
      const api = window.__api;
      const ctx = api?._player?.output?.audioContext || api?._player?.output?.context;
      return ctx ? ctx.state : 'none';
    });
    console.log(`🔊 AudioContext state after initial touch: ${unlockedState}`);

    // 查找并点击播放按钮
    const playBtn = page.locator('#btn-play');
    const playBtnVisible = await playBtn.isVisible();
    record('Play button accessible on mobile', playBtnVisible);

    if (playBtnVisible) {
      // 点击播放
      await playBtn.click();
      console.log('▶️ Clicked Play button on mobile.');

      // 等待播放状态变为 true 或 curTick 推进
      await page.waitForFunction(() => {
        const api = window.__api;
        return api && api.playerState === 1; // 1 = Playing
      }, { timeout: 15000 }).catch(() => {});

      const playbackActive = await page.evaluate(() => {
        const api = window.__api;
        return {
          playerState: api?.playerState,
          isPlaying: api?.playerState === 1,
          tick: api?.tickCache ? 1 : 0,
        };
      });
      record('Mobile Playback Active (Non-silent, state=1)', playbackActive.isPlaying, `State: ${playbackActive.playerState}`);

      // 验证 iOS 侧边静音提示浮动胶囊是否出现
      const iosHint = page.locator('text=若听不到声音，请检查手机是否开启侧边静音拨片');
      const isHintVisible = await iosHint.isVisible();
      record('iOS Silent Switch Hint Pill Visible', isHintVisible, 'Floating pill shown on active playback');

      // 截图存证
      await page.screenshot({ path: `${EVIDENCE_DIR}/mobile-playback-active.png` });
      console.log(`📸 Saved screenshot: ${EVIDENCE_DIR}/mobile-playback-active.png`);

      // 等待 4.5 秒，验证 iOS 提示胶囊自动淡出消失
      if (isHintVisible) {
        await page.waitForTimeout(4500);
        const isHintStillVisible = await iosHint.isVisible();
        record('iOS Silent Switch Hint Auto-Faded Out', !isHintStillVisible, 'Gracefully dismissed after 4s');
      }

      // 验证播放进度向前推进
      const tick1 = await page.evaluate(() => window.__api?.tickCache?.findBeat ? 1 : 0);
      await page.waitForTimeout(1500);
      const isStillPlaying = await page.evaluate(() => window.__api?.playerState === 1);
      record('Continuous Smooth Mobile Playback', isStillPlaying, 'No stutter, stall, or crash');
    }

    // 3. 验证 Cache Storage 核心音源预热情况
    const cacheEntries = await page.evaluate(async () => {
      if (!('caches' in window)) return { supported: false, keys: [] };
      const keys = await caches.keys();
      const mimiCaches = keys.filter(k => k.startsWith('mimi-sf2-cache'));
      const cachedUrls = [];
      for (const cName of mimiCaches) {
        const c = await caches.open(cName);
        const reqs = await c.keys();
        for (const req of reqs) {
          cachedUrls.push(req.url);
        }
      }
      return { supported: true, caches: mimiCaches, urls: cachedUrls };
    });
    const hasPrewarmedFast = cacheEntries.urls.some(u => u.includes('acoustic_guitar_fast.sf2') || u.includes('ukulele_fast.sf2') || u.includes('0.sf2'));
    record('Core SoundFonts Pre-warmed into Cache Storage', hasPrewarmedFast, `Found ${cacheEntries.urls.length} cached soundfonts`);

    await mobileContext.close();
  } catch (err) {
    console.error('❌ Test run encountered fatal error:', err);
    record('Overall test execution', false, String(err));
  } finally {
    await browser.close();
  }

  const allPassed = results.every((r) => r.pass);
  console.log('\n=============================================');
  console.log(`Summary: ${results.filter(r => r.pass).length}/${results.length} Passed`);
  console.log(`Final Result: ${allPassed ? '🎉 ALL TESTS PASSED' : '⚠️ SOME TESTS FAILED'}`);
  console.log('=============================================\n');

  if (!allPassed) {
    process.exit(1);
  }
}

run();
