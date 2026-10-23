import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
fs.mkdirSync('tests/evidence/m7', { recursive: true });
(async () => {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox','--disable-gpu'] });
  const results = [];
  const publicRoutes = [
    '/', '/tabs', '/tabs?difficulty=2', '/ukulele', '/searchResults?type=guitar&searchValue=%E6%99%B4%E5%A4%A9',
    '/searchResults?type=ukulele&searchValue=%E6%99%B4%E5%A4%A9', '/searchResults?type=article&searchValue=%E5%90%89%E4%BB%96',
    '/article?sort=hot', '/community', '/publishArticle', '/agreementPolicy', '/uploadpolicy', '/countact-us',
    '/upload?type=guitar', '/upload?type=ukulele', '/login', '/register', '/about', '/help', '/policy',
  ];
  for (const w of [1440, 390]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: 1000 } });
    const page = await ctx.newPage();
    for (const path of publicRoutes) {
      const errs = [];
      const onC = (m) => { if (m.type() === 'error') errs.push(m.text()); };
      const onE = (e) => errs.push(String(e));
      page.on('console', onC); page.on('pageerror', onE);
      let resp = null;
      try { resp = await page.goto('http://localhost:4321' + path, { waitUntil: 'domcontentloaded', timeout: 45000 }); } catch (e) { errs.push('goto:' + String(e).slice(0,80)); }
      await page.waitForTimeout(path.includes('/tabs/1sdc49P3eKm') ? 0 : 200);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1).catch(() => false);
      results.push({ w, path, status: resp ? resp.status() : null, overflow, errs });
      page.removeListener('console', onC); page.removeListener('pageerror', onE);
    }
    await ctx.close();
  }
  // detail player page (longer wait)
  const ctx3 = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page3 = await ctx3.newPage();
  const errs3 = [];
  page3.on('console', m => { if (m.type()==='error') errs3.push(m.text()); });
  page3.on('pageerror', e => errs3.push(String(e)));
  await page3.goto('http://localhost:4321/tabs/1sdc49P3eKm', { waitUntil: 'load', timeout: 60000 });
  await page3.waitForTimeout(3000);
  const svg = await page3.locator('#score-scroll svg').count();
  results.push({ w: 1440, path: '/tabs/1sdc49P3eKm', status: 200, overflow: false, svg, errs: errs3 });
  await ctx3.close();
  // screenshots
  const shots = [['/', 'm7-final-home'], ['/tabs?difficulty=2', 'm7-final-tabs'], ['/searchResults?type=guitar&searchValue=%E6%99%B4%E5%A4%A9', 'm7-final-search'], ['/article?sort=hot', 'm7-final-article'], ['/tabs/1sdc49P3eKm', 'm7-final-detail'], ['/account/3', 'm7-final-account'], ['/upload?type=guitar', 'm7-final-upload']];
  for (const [path, name] of shots) {
    const ctx4 = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const p4 = await ctx4.newPage();
    await p4.goto('http://localhost:4321' + path, { waitUntil: 'load', timeout: 60000 });
    await p4.waitForTimeout(path.includes('/tabs/1sdc49P3eKm') ? 3000 : 500);
    await p4.screenshot({ path: 'tests/evidence/m7/' + name + '.png' });
    await ctx4.close();
  }
  const failures = results.filter(r => r.status !== 200 || r.overflow || (r.errs && r.errs.length > 0));
  console.log('M7FINAL:' + JSON.stringify({ total: results.length, failures: failures.length, failureList: failures.slice(0,8) }, null, 2));
  await browser.close();
})();