import { chromium } from 'playwright-core';

const CHROME_EXE = process.env.CHROME_PATH ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';

/** 用无头 Chrome 打开 render 页渲染 .ibe 并截取首屏谱面；成功返回 true */
export async function renderScreenshot(
  baseUrl: string,
  fileUrl: string,
  outPath: string,
  opts: { scale?: number; width?: number } = {},
): Promise<boolean> {
  let browser;
  try {
    browser = await chromium.launch({ executablePath: CHROME_EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  } catch {
    return false;
  }
  try {
    const scale = opts.scale ?? 1.1;
    const width = opts.width ?? 1200;
    const page = await browser.newPage({ viewport: { width, height: 1600 } });
    const url = baseUrl + '/render?file=' + encodeURIComponent(fileUrl) + '&scale=' + scale + '&width=' + width;
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });

    let rendered = false;
    for (let i = 0; i < 80; i++) {
      const title = await page.title().catch(() => '');
      if (title.startsWith('RENDER_ERR')) break;
      const count = await page.locator('#score svg').count().catch(() => 0);
      if (count > 0) {
        rendered = true;
        break;
      }
      await page.waitForTimeout(500);
    }
    if (!rendered) return false;
    await page.waitForTimeout(900);
    // 截取首页 SVG（预览用）
    const first = page.locator('#score svg').first();
    await first.screenshot({ path: outPath });
    return true;
  } catch {
    return false;
  } finally {
    await browser.close().catch(() => {});
  }
}