import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
mkdirSync('tests/evidence', { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));

// difficulty=0 should show 42 cards (only 42 records with difficulty 0)
await page.goto('http://localhost:4321/tabs?difficulty=0', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(600);
const diff0Cards = await page.locator('a.card').count();
await page.screenshot({ path: 'tests/evidence/m3-tabs-difficulty0.png', fullPage: false });

// page 1 vs page 2 titles should differ
await page.goto('http://localhost:4321/tabs?sort=1', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(600);
const p1 = await page.locator('a.card h3').allTextContents();
await page.goto('http://localhost:4321/tabs?sort=1&no=2', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(600);
const p2 = await page.locator('a.card h3').allTextContents();
const overlap = p1.filter(t => p2.includes(t)).length;

// screenshots
await page.goto('http://localhost:4321/', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(600);
await page.screenshot({ path: 'tests/evidence/m3-home.png', fullPage: false });
await page.goto('http://localhost:4321/search?q=%E6%99%B4%E5%A4%A9', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(600);
await page.screenshot({ path: 'tests/evidence/m3-search.png', fullPage: false });

console.log('DETAILS:' + JSON.stringify({ diff0Cards, p1Count: p1.length, p2Count: p2.length, p1First: p1[0], p2First: p2[0], overlap, errors }, null, 2));
await browser.close();