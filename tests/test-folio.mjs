import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

async function test() {
  const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const page = await context.newPage();

  // Set sessionStorage to skip intro directly so we can inspect the homepage folio sections immediately
  await page.addInitScript(() => {
    sessionStorage.setItem('mimi_paper_intro_played', 'true');
  });

  console.log('Navigating to http://localhost:4321/...');
  await page.goto('http://localhost:4321/', { waitUntil: 'domcontentloaded', timeout: 20000 });

  // Wait for client components to hydrate
  await page.waitForTimeout(2000);

  // Scroll down to the PaperFolioSection
  const folioSections = await page.$$('.folio-container');
  console.log('Found folio-container count:', folioSections.length);

  // Scroll into view
  if (folioSections.length > 0) {
    await folioSections[0].scrollIntoViewIfNeeded();
    await page.waitForTimeout(600);
  }

  // Screenshot the entire dual folio section
  await page.screenshot({ path: 'tests/evidence/paper-folio-dual.png', fullPage: false });
  console.log('✓ Screenshot saved: paper-folio-dual.png');

  // Test pagination flip on the first folio (Guitar)
  const nextBtns = await page.$$('.folio-nav-btn');
  console.log('Found folio-nav-btn count:', nextBtns.length);

  if (nextBtns.length >= 4) {
    // 1. Click Next on guitar section
    console.log('Clicking Next page on guitar folio...');
    await nextBtns[1].click();
    await page.waitForTimeout(250); // Mid-flight 3D perspective turn
    await page.screenshot({ path: 'tests/evidence/paper-folio-flip.png', fullPage: false });
    console.log('✓ Screenshot saved: paper-folio-flip.png');

    await page.waitForTimeout(300); // Settle down

    // 2. Click Next on ukulele section
    console.log('Clicking Next page on ukulele folio...');
    await nextBtns[3].click();
    await page.waitForTimeout(250); // Mid-flight
    await page.screenshot({ path: 'tests/evidence/paper-folio-uku-flip.png', fullPage: false });
    console.log('✓ Screenshot saved: paper-folio-uku-flip.png');

    await page.waitForTimeout(350);

    // 3. Test dot click on ukulele section
    const dots = await page.$$('.folio-dot');
    if (dots.length >= 15) {
      console.log('Clicking 5th dot on ukulele folio...');
      await dots[14].click();
      await page.waitForTimeout(550);
      await page.screenshot({ path: 'tests/evidence/paper-folio-dot-jump.png', fullPage: false });
      console.log('✓ Screenshot saved: paper-folio-dot-jump.png');
    }
  }

  await browser.close();
  console.log('\n✅ Folio section test completed successfully!');
}

test().catch(e => { console.error('Test failed:', e.message); process.exit(1); });
