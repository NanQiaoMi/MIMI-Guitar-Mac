import { chromium } from 'playwright-core';

async function benchmarkSpeed() {
  const browser = await chromium.launch({
    headless: true,
    channel: 'chrome',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  }).catch(() => chromium.launch({ headless: true, channel: 'msedge' }));

  const page = await browser.newPage({ viewport: { width: 1440, height: 1050 } });
  
  const networkRequests = [];
  page.on('response', res => {
    const url = res.url();
    const headers = res.headers();
    const status = res.status();
    networkRequests.push({
      url: url.split('/').pop().substring(0, 30),
      status,
      contentEncoding: headers['content-encoding'] || 'none',
      cacheControl: headers['cache-control'] || 'none',
      size: headers['content-length'] ? `${(parseInt(headers['content-length'])/1024).toFixed(1)} KB` : 'unknown'
    });
  });

  console.log('--- Benchmarking /studio load speed ---');
  const t0 = Date.now();
  await page.goto('http://154.88.65.55:20056/studio', { waitUntil: 'domcontentloaded' });
  const domTime = Date.now() - t0;
  await page.waitForTimeout(1000);
  const totalTime = Date.now() - t0;

  console.log(`✓ DOMContentLoaded in ${domTime}ms, Total load in ${totalTime}ms`);
  console.log('Network Requests Sample:', networkRequests.slice(0, 10));

  console.log('--- Benchmarking / (Homepage) load speed ---');
  const tHome0 = Date.now();
  await page.goto('http://154.88.65.55:20056/', { waitUntil: 'domcontentloaded' });
  const homeDomTime = Date.now() - tHome0;
  console.log(`✓ Homepage DOMContentLoaded in ${homeDomTime}ms`);

  await browser.close();
}

benchmarkSpeed().catch(console.error);
