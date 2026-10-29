import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
  
  await page.addInitScript(() => {
    sessionStorage.setItem('mimi_paper_intro_played', 'true');
  });

  // 1. Screenshot of Homepage with fullscreen paper watermarks & clean cards
  await page.goto('http://localhost:4321/');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: 'tests/evidence/v3-homepage-particles.png' });
  console.log('Homepage screenshot saved');

  // 2. Screenshot of Player with Virtual Fretboard opened
  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq');
  await page.waitForSelector('#score-scroll svg', { timeout: 25000 });
  await page.waitForTimeout(1000);
  
  // Click "虚拟指板" or "指板" button in toolbar if available
  const fretboardBtn = await page.locator('button:has-text("虚拟指板"), button:has-text("指板")').first();
  if (await fretboardBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await fretboardBtn.click({ force: true }).catch(() => {});
    await page.waitForTimeout(500);
  }
  await page.screenshot({ path: 'tests/evidence/v3-player-fretboard.png' });
  console.log('Player fretboard screenshot saved');

  // 3. Screenshot of Showcase Page with Motion tab
  await page.goto('http://localhost:4321/showcase');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: 'tests/evidence/v3-showcase-motion.png' });
  console.log('Showcase screenshot saved');

  await browser.close();
}

test();
