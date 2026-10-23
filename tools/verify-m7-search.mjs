import { chromium } from 'playwright-core';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const results = [];
const KW = encodeURIComponent('晴天');

async function newPage(ctx) {
  const page = await ctx.newPage();
  const errs = [];
  page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
  page.on('pageerror', (e) => errs.push(String(e)));
  return { page, errs };
}

// 1) desktop searchResults with all tabs / counts / filters / pagination
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const { page, errs } = await newPage(ctx);
  const resp = await page.goto('http://localhost:4321/searchResults?type=guitar&searchValue=' + KW, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(800);
  const body = await page.textContent('body');
  const checks = {
    status200: resp ? resp.status() === 200 : false,
    hasFound: /共找到\s*\d+\s*个结果/.test(body),
    hasGuitarTab: body.includes('吉他'),
    hasUkuTab: body.includes('尤克里里'),
    hasArticleTab: body.includes('文章'),
    hasSort: body.includes('最热') && body.includes('最新'),
    hasDifficultyFilter: body.includes('难度'),
    hasResults: body.includes('晴天'),
  };
  await page.locator('a[href*="searchResults"][href*="type=ukulele"]').first().click();
  await page.waitForTimeout(800);
  checks.ukuTabUrl = page.url().includes('type=ukulele');
  const ukuBody = await page.textContent('body');
  checks.ukuHasResults = /共找到\s*\d+\s*个结果/.test(ukuBody);
  await page.goto('http://localhost:4321/searchResults?type=guitar&searchValue=' + KW + '&difficulty=1&page=1', { waitUntil: 'networkidle' });
  await page.waitForTimeout(600);
  const filtBody = await page.textContent('body');
  checks.filterApplied = /共找到\s*\d+\s*个结果/.test(filtBody);
  await page.screenshot({ path: 'tests/evidence/m7/m7-search-d.png', fullPage: false });
  results.push({ path: '/searchResults?type=guitar', checks, overflow: await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1), errs });
  await ctx.close();
}

// 2) legacy /search?q= redirects to /searchResults
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const { page, errs } = await newPage(ctx);
  await page.goto('http://localhost:4321/search?q=' + KW, { waitUntil: 'networkidle', timeout: 60000 });
  const checks = {
    redirected: page.url().includes('/searchResults'),
    hasParams: page.url().includes('searchValue='),
  };
  results.push({ path: '/search?q=', checks, errs });
  await ctx.close();
}

// 3) mobile no overflow / no errors
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const { page, errs } = await newPage(ctx);
  const resp = await page.goto('http://localhost:4321/searchResults?type=guitar&searchValue=' + KW, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(600);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  await page.screenshot({ path: 'tests/evidence/m7/m7-search-m.png', fullPage: false });
  results.push({ path: '/searchResults (mobile)', status: resp ? resp.status() : null, overflow, errs });
  await ctx.close();
}

const failures = results.filter((r) => {
  if (r.errs && r.errs.length) return true;
  if (r.checks) { for (const v of Object.values(r.checks)) if (!v) return true; }
  if (r.overflow) return true;
  if (r.status && r.status !== 200) return true;
  return false;
});
console.log('M73:' + JSON.stringify({ total: results.length, failures: failures.length, results }, null, 2));
await browser.close();
