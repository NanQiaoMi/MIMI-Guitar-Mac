import { chromium } from 'playwright-core';

async function main() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  // Enable CDP Performance Tracing
  const client = await page.context().newCDPSession(page);
  await client.send('Performance.enable');

  console.log('--- Tracing Homepage Mount & Long Tasks ---');
  await page.addInitScript(() => {
    window.__longTasks = [];
    const observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        window.__longTasks.push({
          name: entry.name,
          duration: entry.duration,
          startTime: entry.startTime,
          attribution: entry.attribution ? entry.attribution.map(a => a.name || a.containerType) : []
        });
      }
    });
    observer.observe({ entryTypes: ['longtask'] });
  });

  await page.goto('http://localhost:4321/', { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);

  const longTasks = await page.evaluate(() => window.__longTasks);
  console.log('Homepage Long Tasks (>50ms):', longTasks);

  console.log('\n--- Tracing Score Player Page Long Tasks ---');
  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq', { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);

  const playerLongTasks = await page.evaluate(() => window.__longTasks);
  console.log('Score Player Long Tasks (>50ms):', playerLongTasks);

  // Check 128 instruments modal DOM impact
  const instrumentModalDOM = await page.evaluate(() => {
    const modal = document.querySelector('.instruments-modal');
    return {
      modalExistsInDOM: !!modal,
      instrumentsRenderedCount: document.querySelectorAll('.instrument-option-card, .instrument-pill').length
    };
  });
  console.log('Instrument DOM stats:', instrumentModalDOM);

  await browser.close();
}

main().catch(console.error);
