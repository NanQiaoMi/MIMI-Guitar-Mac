import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
  
  await page.addInitScript(() => {
    sessionStorage.setItem('mimi_paper_intro_played', 'true');
  });

  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq');
  await page.waitForSelector('#score-scroll svg', { timeout: 25000 });
  await page.waitForTimeout(1000);
  
  // Scroll to top of score (Measure 1 - Measure 8)
  await page.evaluate(() => {
    const el = document.querySelector('#score-scroll');
    if (el) el.scrollTop = 0;
  });
  await page.waitForTimeout(500);
  
  await page.screenshot({ path: 'tests/evidence/score-chords-anticollision.png' });
  console.log('Chords anticollision screenshot saved successfully');
  await browser.close();
}

test();
