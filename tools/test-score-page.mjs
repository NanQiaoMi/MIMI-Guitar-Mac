import { chromium } from 'playwright-core';

const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function main() {
  const browser = await chromium.launch({
    executablePath: EXE,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu']
  });

  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  page.on('console', (msg) => {
    console.log(`[BROWSER ${msg.type()}]`, msg.text());
  });

  page.on('pageerror', (err) => {
    console.error('[BROWSER ERROR]', err.message);
  });

  console.log('Opening http://localhost:4321/tabs/1sdcVfeA7Gq ...');
  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq', { waitUntil: 'domcontentloaded' });

  // Wait up to 10 seconds for score to render
  for (let i = 0; i < 10; i++) {
    await page.waitForTimeout(1000);
    const status = await page.evaluate(() => {
      const svgs = document.querySelectorAll('#score-scroll svg').length;
      const loading = document.body.innerText.includes('乐谱与音频引擎加载中');
      const err = document.body.innerText.includes('加载失败');
      return { svgs, loading, err };
    });
    console.log(`[T+${i + 1}s]`, JSON.stringify(status));
    if (status.svgs > 0 && !status.loading) {
      console.log('SUCCESS! Score rendered with', status.svgs, 'SVG elements.');
      break;
    }
  }

  await browser.close();
}

main().catch(console.error);
