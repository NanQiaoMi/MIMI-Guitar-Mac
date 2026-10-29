import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu', '--autoplay-policy=no-user-gesture-required'] });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 1000 } })).newPage();
await page.goto('http://localhost:4321/tabs/1sdc49P3eKm', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForFunction(() => {
  const b = [...document.querySelectorAll('button')].find((x) => x.textContent.includes('播放') || x.textContent.includes('暂停'));
  return b && !b.disabled && !b.textContent.includes('加载');
}, { timeout: 25000 });
await page.waitForTimeout(500);
await page.locator('button', { hasText: '循环' }).first().click();
const box = await page.locator('#score-scroll').boundingBox();
const state = () => page.evaluate(() => {
  const d = [...document.querySelectorAll('div')].find((x) => /音符|循环中/.test(x.textContent || '') && x.textContent.length < 14);
  const input = document.querySelector('input[aria-label="播放进度"]');
  const divs = input && input.parentElement ? [...input.parentElement.querySelectorAll('div')] : [];
  const hl = divs.filter((x) => (x.getAttribute('style') || '').includes('rgba(65,161,207')).length;
  return { txt: d ? d.textContent.trim() : null, hl };
});
console.log('ARMED', JSON.stringify(await state()));
const cands = [[100,180],[140,220],[120,200],[100,200],[160,240],[300,200],[500,200]];
for (const [dx,dy] of cands) {
  await page.mouse.click(box.x + dx, box.y + dy);
  await page.waitForTimeout(300);
  console.log('CLICK', dx, dy, JSON.stringify(await state()));
  const s = await state();
  if (s.hl > 0) break;
}
await browser.close();