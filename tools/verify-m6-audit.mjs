import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const urls = [
  ['/', 'home'],
  ['/tabs', 'tabs'],
  ['/tabs/1sdc49P3eKm', 'detail'],
  ['/search?q=晴天', 'search'],
  ['/article', 'article'],
  ['/login', 'login'],
  ['/account/0', 'account0'],
  ['/upload', 'upload'],
];
const results = [];
for (const [path, name] of urls) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  await page.goto('http://localhost:4321' + path, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(path.includes('/tabs/1sdc49P3eKm') ? 3500 : 600);
  const audit = await page.evaluate(() => {
    const vw = window.innerWidth;
    const overflow = document.documentElement.scrollWidth > vw + 1;
    // find elements wider than viewport
    const wide = [];
    document.querySelectorAll('body *').forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.right > vw + 2 || r.width > vw + 2) {
        const cls = (el.getAttribute('class') || '').slice(0, 40);
        if (wide.length < 8) wide.push({ tag: el.tagName, cls, w: Math.round(r.width), right: Math.round(r.right) });
      }
    });
    // nav links visible on mobile?
    const navLinks = [...document.querySelectorAll('nav a')].map((a) => ({ text: a.textContent.trim().slice(0, 8), visible: !!(a.offsetWidth || a.offsetHeight) }));
    return { vw, overflow, wide, navLinks };
  });
  results.push({ name, ...audit });
  await ctx.close();
}
console.log('MOBILE_AUDIT:' + JSON.stringify(results, null, 2));
await browser.close();