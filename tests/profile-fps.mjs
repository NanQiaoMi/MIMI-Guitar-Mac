import { chromium } from 'playwright-core';

async function main() {
  const browser = await chromium.launch({
    headless: true,
    args: ['--enable-gpu', '--disable-gpu-vsync']
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  console.log('--- Testing Homepage Performance ---');
  await page.goto('http://localhost:4321/', { waitUntil: 'domcontentloaded' });

  // Profile FPS and frame times during the first 4 seconds
  const metrics = await page.evaluate(async () => {
    return new Promise((resolve) => {
      const frameDeltas = [];
      let last = performance.now();
      let frames = 0;

      function loop(now) {
        const delta = now - last;
        last = now;
        frameDeltas.push(delta);
        frames++;
        if (frames < 180) {
          requestAnimationFrame(loop);
        } else {
          const avgDelta = frameDeltas.reduce((a, b) => a + b, 0) / frameDeltas.length;
          const fps = 1000 / avgDelta;
          const janks = frameDeltas.filter(d => d > 25).length;
          const maxDelta = Math.max(...frameDeltas);
          resolve({ fps: Math.round(fps), avgDelta: avgDelta.toFixed(2), janks, maxDelta: maxDelta.toFixed(2) });
        }
      }
      requestAnimationFrame(loop);
    });
  });

  console.log('Homepage FPS Profile during intro/mount:', metrics);

  // Measure after intro exits or on player page
  console.log('\n--- Testing Score Player Page Performance ---');
  await page.goto('http://localhost:4321/tabs/1sdcVfeA7Gq', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1000);

  const playerMetrics = await page.evaluate(async () => {
    return new Promise((resolve) => {
      const frameDeltas = [];
      let last = performance.now();
      let frames = 0;

      function loop(now) {
        const delta = now - last;
        last = now;
        frameDeltas.push(delta);
        frames++;
        if (frames < 180) {
          requestAnimationFrame(loop);
        } else {
          const avgDelta = frameDeltas.reduce((a, b) => a + b, 0) / frameDeltas.length;
          const fps = 1000 / avgDelta;
          const janks = frameDeltas.filter(d => d > 25).length;
          const maxDelta = Math.max(...frameDeltas);
          resolve({ fps: Math.round(fps), avgDelta: avgDelta.toFixed(2), janks, maxDelta: maxDelta.toFixed(2) });
        }
      }
      requestAnimationFrame(loop);
    });
  });

  console.log('Score Player FPS Profile:', playerMetrics);

  // Check DOM element count and style complexity
  const domInfo = await page.evaluate(() => {
    return {
      totalElements: document.querySelectorAll('*').length,
      svgElements: document.querySelectorAll('svg').length,
      canvases: document.querySelectorAll('canvas').length,
      animations: document.getAnimations ? document.getAnimations().length : 0
    };
  });
  console.log('Score Player DOM & Animation info:', domInfo);

  await browser.close();
}

main().catch(console.error);
