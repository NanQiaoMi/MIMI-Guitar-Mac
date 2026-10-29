import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const DEFAULT_CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const MIN_GAP_PX = 8;

function waitForServer(child) {
  return new Promise((resolve, reject) => {
    let output = '';
    const timeout = setTimeout(() => {
      reject(new Error(`Timed out waiting for layout test server. Output: ${output}`));
    }, 30_000);

    const onData = (chunk) => {
      output += String(chunk);
      const match = output.match(/Server listening on (http:\/\/127\.0\.0\.1:\d+)/);
      if (!match) return;
      clearTimeout(timeout);
      resolve(match[1]);
    };

    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.once('error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.once('exit', (code) => {
      clearTimeout(timeout);
      reject(new Error(`Layout test server exited before becoming ready (code ${code}). Output: ${output}`));
    });
  });
}

async function startLocalServer() {
  const entry = fileURLToPath(new URL('../dist/server/entry.mjs', import.meta.url));
  if (!existsSync(entry)) throw new Error('Missing dist/server/entry.mjs. Run npm run build first.');

  const child = spawn(process.execPath, [entry], {
    cwd: ROOT,
    env: {
      ...process.env,
      HOST: '127.0.0.1',
      PORT: '0',
      NODE_ENV: 'production',
      JWT_SECRET: 'lyrics-layout-test-only-not-a-production-secret',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  return { baseUrl: await waitForServer(child), child };
}

function getSpacing() {
  const svgs = [...document.querySelectorAll('#score svg.at-surface-svg')];
  const target = svgs.find((svg) => {
    const text = svg.textContent || '';
    return text.includes('好想再') && text.includes('你会等待还是离开');
  });
  if (!target) throw new Error('Could not find the 晴天 lyrics system used by this regression test.');

  const targetLyrics = new Set(['好', '想', '再', '淋', '一', '遍']);
  const lyrics = [...target.querySelectorAll('text')]
    .filter((element) => targetLyrics.has((element.textContent || '').trim()))
    .map((element) => {
      const rect = element.getBoundingClientRect();
      return { lyric: (element.textContent || '').trim(), left: rect.left, right: rect.right, top: rect.top };
    });
  if (lyrics.length === 0) throw new Error('Could not find visible lyric glyphs in the 晴天 lyrics system.');

  const notation = [...target.querySelectorAll('path,line,rect,polyline,polygon,circle,ellipse')]
    .map((element) => {
      const rect = element.getBoundingClientRect();
      return { left: rect.left, right: rect.right, bottom: rect.bottom, width: rect.width, height: rect.height };
    })
    .filter((rect) => rect.width > 0 && rect.height >= 0);

  const gaps = lyrics.map((lyric) => {
    const nearest = notation
      .filter((ink) => ink.right > lyric.left && ink.left < lyric.right && ink.bottom <= lyric.top)
      .sort((a, b) => b.bottom - a.bottom)[0];
    return {
      lyric: lyric.lyric,
      gap: nearest ? Number((lyric.top - nearest.bottom).toFixed(2)) : null,
    };
  });

  const numericGaps = gaps.map((entry) => entry.gap).filter((gap) => gap !== null);
  if (numericGaps.length === 0) throw new Error('Could not measure a notation-to-lyric gap.');
  return { gaps, minGap: Math.min(...numericGaps) };
}

let child;
let browser;
try {
  const started = process.env.MIMI_TEST_BASE_URL
    ? { baseUrl: process.env.MIMI_TEST_BASE_URL, child: null }
    : await startLocalServer();
  child = started.child;

  const chrome = process.env.CHROME_PATH || DEFAULT_CHROME;
  if (!existsSync(chrome)) throw new Error(`Chrome executable not found: ${chrome}`);

  browser = await chromium.launch({
    executablePath: chrome,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu'],
  });
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  const consoleErrors = [];
  const pageErrors = [];
  page.on('console', (message) => {
    if (message.type() !== 'error' && message.type() !== 'warning') return;

    // Chrome requests /favicon.ico automatically when the diagnostic route has
    // no favicon. That 404 does not originate in the score renderer and would
    // otherwise hide the layout assertion behind a baseline browser request.
    const location = message.location();
    const isImplicitFavicon404 =
      location.url.endsWith('/favicon.ico') &&
      message.text() === 'Failed to load resource: the server responded with a status of 404 (Not Found)';
    if (!isImplicitFavicon404) consoleErrors.push(`${message.text()} (${location.url})`);
  });
  page.on('pageerror', (error) => pageErrors.push(error.message));

  await page.goto(
    `${started.baseUrl}/render?file=/storage/scores/qingtian.ibe&width=1200&scale=0.84`,
    { waitUntil: 'domcontentloaded', timeout: 60_000 },
  );
  await page.waitForFunction(
    () => document.title.startsWith('RENDER_ERR:') || document.querySelectorAll('#score svg.at-surface-svg').length > 10,
    { timeout: 60_000 },
  );

  const title = await page.title();
  assert.ok(!title.startsWith('RENDER_ERR:'), `Score renderer failed: ${title}`);
  assert.deepEqual(consoleErrors, [], `Browser console errors: ${consoleErrors.join('\n')}`);
  assert.deepEqual(pageErrors, [], `Browser page errors: ${pageErrors.join('\n')}`);

  const spacing = await page.evaluate(getSpacing);
  const failures = spacing.gaps.filter((entry) => entry.gap === null || entry.gap < MIN_GAP_PX);
  assert.deepEqual(
    failures,
    [],
    `Lyrics must stay at least ${MIN_GAP_PX}px below notation. Measured: ${JSON.stringify(spacing.gaps)}`,
  );
  console.log(`Lyrics beam spacing passed: min ${spacing.minGap}px (threshold ${MIN_GAP_PX}px).`);
} finally {
  await browser?.close();
  if (child && !child.killed) child.kill();
}
