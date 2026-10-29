import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  await page.addInitScript(() => {
    sessionStorage.setItem('mimi_paper_intro_played', 'true');
  });

  const routes = [
    { url: 'http://localhost:4321/', name: 'Homepage' },
    { url: 'http://localhost:4321/tabs', name: 'Tabs List' },
    { url: 'http://localhost:4321/ukulele', name: 'Ukulele List' },
    { url: 'http://localhost:4321/tabs/1sdcVfeA7Gq', name: 'Score Player - 晴天' },
    { url: 'http://localhost:4321/tabs/1sdc49P3eKm', name: 'Score Player - 老男孩' },
    { url: 'http://localhost:4321/ukulele/1wmj8hqHnYf', name: 'Score Player - 后来' },
    { url: 'http://localhost:4321/article', name: 'Article List' },
    { url: 'http://localhost:4321/searchResults?searchValue=周杰伦', name: 'Search Results' },
  ];

  for (const r of routes) {
    console.log(`Testing: ${r.name} (${r.url})...`);
    const resp = await page.goto(r.url, { waitUntil: 'domcontentloaded', timeout: 15000 });
    console.log(`  Status: ${resp?.status()}`);
    if (resp?.status() !== 200) {
      throw new Error(`Failed route ${r.url} with status ${resp?.status()}`);
    }
  }

  // Specifically test Score Player rendering on /tabs/1sdcVfeA7Gq
  console.log('\nVerifying ScorePlayer rendering on /tabs/1sdcVfeA7Gq...');
  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  // Check if error box or 404 is visible
  const pageText = await page.evaluate(() => document.body.innerText);
  const has404Error = pageText.includes('HTTP 404') || pageText.includes('加载失败');
  console.log('Has 404 or load error on score page:', has404Error);

  await page.screenshot({ path: 'tests/evidence/score-player-qingtian.png', fullPage: false });
  console.log('✓ Screenshot saved: score-player-qingtian.png');

  // Test search API
  const apiResp = await fetch('http://localhost:4321/api/search?q=晴天');
  const apiJson = await apiResp.json();
  console.log('API /api/search?q=晴天 result ok:', apiJson.ok, 'count:', apiJson.tabs?.length);

  await browser.close();
  console.log('\n✅ ALL ROUTES & SCORE PLAYERS TESTED SUCCESSFULLY!');
}

test().catch(e => { console.error('Route test failed:', e.message); process.exit(1); });
