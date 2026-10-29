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
  
  // Click on the Capo button to open the dropdown
  const capoBtn = await page.locator('button:has-text("变调夹")').first();
  if (await capoBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await capoBtn.click({ force: true }).catch(() => {});
    await page.waitForTimeout(500);
  }
  
  await page.screenshot({ path: 'tests/evidence/score-capo-zindex-fixed.png' });
  console.log('Capo dropdown screenshot saved successfully');
  await browser.close();
}

test();
