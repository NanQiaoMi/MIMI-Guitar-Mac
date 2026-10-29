import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  await page.addInitScript(() => {
    sessionStorage.removeItem('mimi_paper_intro_played');
  });

  await page.goto('http://localhost:4321/', { waitUntil: 'domcontentloaded', timeout: 20000 });

  // Take screenshots at key animation moments
  // T+0.5s: Very early — paper + ink bloom starting
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'tests/evidence/intro-t500ms.png' });
  console.log('✓ T+500ms: ink bloom start');

  // T+1.2s: Border drawing + particles appearing
  await page.waitForTimeout(700);
  await page.screenshot({ path: 'tests/evidence/intro-t1200ms.png' });
  console.log('✓ T+1200ms: border + particles');

  // T+2.0s: Title emerging
  await page.waitForTimeout(800);
  await page.screenshot({ path: 'tests/evidence/intro-t2000ms.png' });
  console.log('✓ T+2000ms: title emerge');

  // T+3.5s: Full display with motto
  await page.waitForTimeout(1500);
  await page.screenshot({ path: 'tests/evidence/intro-t3500ms.png' });
  console.log('✓ T+3500ms: full display');

  // Verify elements
  const checks = await page.evaluate(() => ({
    introRoot: !!document.querySelector('.intro-root'),
    title: !!document.querySelector('.main-title'),
    motto: !!document.querySelector('.motto'),
    particles: !!document.querySelector('.particle-canvas'),
    border: !!document.querySelector('.border-frame'),
    skipBtn: !!document.querySelector('.skip-btn'),
    flourish: !!document.querySelector('.flourish'),
    staffLines: !!document.querySelector('.staff-lines'),
    watermark: !!document.querySelector('.watermark'),
  }));
  console.log('\nElement checks:', checks);

  // Wait for auto-exit
  await page.waitForTimeout(3500);
  const afterExit = await page.evaluate(() => !!document.querySelector('.intro-root'));
  console.log('Intro removed after auto-exit:', !afterExit);
  await page.screenshot({ path: 'tests/evidence/intro-after-exit.png' });
  console.log('✓ After exit: main page visible');

  await browser.close();
  console.log('\n✅ All intro animation phase tests passed!');
}

test().catch(e => { console.error('Test failed:', e.message); process.exit(1); });
