import { chromium } from 'playwright-core';
const EXE = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://localhost:4321';
const EVIDENCE = 'tests/evidence/score-details';
import fs from 'node:fs';
fs.mkdirSync(EVIDENCE, { recursive: true });

const results = [];
const OUT_LOG = 'tools/verify-score-details.out.log';
fs.writeFileSync(OUT_LOG, '');
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  const line = (ok ? 'PASS' : 'FAIL') + ' | ' + name + (detail ? ' | ' + detail : '');
  console.log(line);
  fs.appendFileSync(OUT_LOG, line + '\n');
}

const browser = await chromium.launch({ executablePath: EXE, headless: true, args: ['--no-sandbox','--disable-gpu'] });

async function openTab(page, id = '1sdc49P3eKm') {
  const errs = [];
  const onC = (m) => { if (m.type() === 'error') errs.push('err:' + m.text().slice(0, 140)); };
  const onE = (e) => errs.push('pageerror:' + String(e).slice(0, 160));
  page.on('console', onC);
  page.on('pageerror', onE);
  await page.goto(BASE + '/tabs/' + id, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => window.__api && document.querySelector('#score-scroll svg'), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3500);
  return { errs, off: () => { page.removeListener('console', onC); page.removeListener('pageerror', onE); } };
}

async function countLyrics(page) {
  return page.evaluate(() => {
    const sc = document.querySelector('#score-scroll');
    const cjk = [...sc.querySelectorAll('text')].filter(t => /[\u4e00-\u9fff]/.test(t.textContent || '')).map(t => t.textContent.trim());
    return { total: cjk.length, joined: cjk.join('') };
  });
}


// ---------- S1 �����Ⱦ�����죺��ʼ�ɼ����������µ�С�ƻ�����----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  const lyr = await countLyrics(page);
  const hasVerse = lyr.joined.includes('\u6545\u4e8b\u7684\u5c0f\u9ec4\u82b1');
  await page.screenshot({ path: EVIDENCE + '/s1-lyrics.png' });
  record('S1 �����Ⱦ�����캬�����µ�С�ƻ���', lyr.total > 20 && hasVerse, JSON.stringify({ total: lyr.total, hasVerse, errs }));
  await ctx.close();
}

// ---------- S2 ��������أ��������׺��β�����Ⱦ���ޱ��� ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  await page.evaluate(() => { const sc = document.getElementById('score-scroll'); if (sc) sc.scrollTop = sc.scrollHeight; });
  await page.waitForTimeout(1800);
  const lyr = await countLyrics(page);
  const bottomOk = lyr.total > 20 && !lyr.joined.startsWith('故事'); // bottom shows later verse, not the intro verse
  record('S2 �����ع������׸����Ⱦ', bottomOk && errs.length === 0, JSON.stringify({ total: lyr.total, sample: lyr.joined.slice(0, 30), errs }));
  await ctx.close();
}

// ---------- S3 和弦名按拍/按 system 分布（对齐参考站；不渲染顶部统一和弦列表） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  const chords = await page.evaluate(() => {
    const surface = document.querySelector('.at-surface');
    const items = [];
    surface.querySelectorAll('text').forEach((el) => {
      const t = (el.textContent || '').trim();
      if (!t || t.length > 12 || /^[0-9]+$/.test(t)) return;
      if (!/^[A-G][#b]?/.test(t) || /^[A-G]$/.test(t)) return;
      if (!/m|7|9|add|sus|6|dim|aug|[/]|maj|[0-9]/.test(t)) return;
      const r = el.getBoundingClientRect();
      items.push({ t, y: Math.round(r.y), x: Math.round(r.x) });
    });
    const rows = [...new Set(items.map((i) => Math.round(i.y / 60) * 60))].sort((a, b) => a - b);
    const row0 = items.filter((i) => Math.round(i.y / 60) * 60 === rows[0]).sort((a, b) => a.x - b.x).map((i) => i.t);
    return { chordNames: items.length, rows: rows.length, row0Seq: row0.join(','), firstRowY: rows[0] ?? null };
  });
  // 参考站第一行序列：Em7,Cadd9,G6,Em7,Cadd9,G6,Em,Em7,Cmaj7,Cadd9
  const seqOk = chords.row0Seq === 'Em7,Cadd9,G6,Em7,Cadd9,G6,Em,Em7,Cmaj7,Cadd9';
  record('S3 和弦名按 system 分布且第一行序列对齐参考站', chords.chordNames > 10 && chords.rows >= 2 && seqOk, JSON.stringify({ chords, errs }));
  await ctx.close();
}

// ---------- S4 ����ͷ���� + ת����ʾ ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  const meta = await page.evaluate(() => {
    const m = document.querySelector('.score-meta-line');
    const text = m ? m.textContent.trim() : null;
    const hint = [...document.querySelectorAll('span')].map(s => s.textContent.trim()).find(t => t.includes('\u2192'));
    return { metaText: text, transposeHint: hint || null };
  });
  record('S4 ͷ�� key �� + ת����ʾ', meta.metaText === 'key = G 4/4 \u2669= 69', JSON.stringify({ meta, errs }));
  await ctx.close();
}

// ---------- S5 数字谱：默认含简谱行，关闭后简谱隐藏且六线谱品数保留 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  const before = await page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    const showNum = window.__api.score.tracks.flatMap((t) => t.staves.map((s) => !!s.showNumbered));
    const digits = [...sc.querySelectorAll('text')].filter((t) => /^\d+$/.test((t.textContent || '').trim()));
    return { hasNumbered: showNum.some(Boolean), digits: digits.length, scrollH: sc.scrollHeight };
  });
  await page.evaluate(() => { [...document.querySelectorAll('button')].find(x => x.textContent.trim() === '\u6570\u5b57\u8c31').click(); });
  await page.waitForTimeout(800);
  const after = await page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    const showNum = window.__api.score.tracks.flatMap((t) => t.staves.map((s) => !!s.showNumbered));
    const digits = [...sc.querySelectorAll('text')].filter((t) => /^\d+$/.test((t.textContent || '').trim()));
    return { hasNumbered: showNum.some(Boolean), digits: digits.length, scrollH: sc.scrollHeight };
  });
  await page.screenshot({ path: EVIDENCE + '/s5-number-tab.png' });
  record('S5 数字谱：默认简谱可见、关闭后简谱隐藏且六线谱品数保留', before.hasNumbered && !after.hasNumbered && after.digits > 0 && after.digits < before.digits && after.scrollH < before.scrollH, JSON.stringify({ before, after, errs }));
  await ctx.close();
}
// ---------- S6 �ƶ��� 390 ����� ----------
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  const overflow = await page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    if (!sc) return null;
    return { scrollWidth: sc.scrollWidth, clientWidth: sc.clientWidth };
  });
  await page.screenshot({ path: EVIDENCE + '/s6-mobile.png' });
  record('S6 �ƶ��� 390 �޺������', overflow && overflow.scrollWidth <= overflow.clientWidth + 2, JSON.stringify({ overflow, errs }));
  await ctx.close();
}

// ---------- S7 �޸�����治��ʾ��ʡ��㱨������ ukulele ������Ⱦ�ع飩----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const errs = [];
  page.on('console', m => { if (m.type() === 'error') errs.push('err:' + m.text().slice(0, 120)); });
  page.on('pageerror', e => errs.push('pageerror:' + String(e).slice(0, 140)));
  await page.goto(BASE + '/ukulele/1wmj8hqHnYf', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => window.__api && document.querySelector('#score-scroll svg'), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3500);
  const lyr = await countLyrics(page);
  record('S7 ukulele ����Ⱦ�������/���ԣ�', lyr.total > 30 && errs.length === 0, JSON.stringify({ total: lyr.total, errs }));
  await ctx.close();
}

// ---------- S8 和弦显示模式：仅字母 vs 字母+完整指法图（原生逐拍内联，歌词共存） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  const { errs } = await openTab(page);
  const snap = () => page.evaluate(() => {
    const sc = document.getElementById('score-scroll');
    const cjk = [...sc.querySelectorAll('text')].filter(x => /[\u4e00-\u9fff]/.test(x.textContent || '')).length;
    const names = ['Em7','Cadd9','G6','Em','Cmaj7','Dadd9/F#','C','G','D/F#','D','G(1)','Em7(2)','Cadd9(1)','Dsus4(1)','B7'];
    const nameEls = [...sc.querySelectorAll('text')].filter(t => names.includes((t.textContent || '').trim()));
    const rows = new Set(nameEls.map(t => Math.round(t.getBoundingClientRect().top / 20)));
    return {
      svgCount: sc.querySelectorAll('svg').length,
      barGroups: sc.querySelectorAll('g[class^="b"]').length,
      cjk, nameCount: nameEls.length, distinctRows: rows.size,
      rects: sc.querySelectorAll('rect').length,
      scrollH: sc.scrollHeight,
      chartStrip: !!document.getElementById('chord-chart'),
    };
  });
  const diagram = await snap();
  await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === '\u4ec5\u5b57\u6bcd'); if (!b) throw new Error('name btn missing'); b.click(); });
  await page.waitForTimeout(2000);
  const nameOnly = await snap();
  await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === '\u5b57\u6bcd+\u6307\u6cd5\u56fe'); if (!b) throw new Error('diagram btn missing'); b.click(); });
  await page.waitForTimeout(2000);
  const diagram2 = await snap();
  await page.screenshot({ path: EVIDENCE + '/s8-chord-mode-toggle.png' });
  const fullOk = diagram.svgCount >= 4 && diagram.barGroups > 300 && diagram.cjk > 10;
  const inlineOk = diagram.nameCount >= 15 && diagram.distinctRows >= 10 && diagram.rects > 4000 && !diagram.chartStrip;
  const toggleOk = nameOnly.rects < diagram.rects && nameOnly.scrollH < diagram.scrollH && nameOnly.cjk === diagram.cjk && nameOnly.nameCount === diagram.nameCount;
  const restoreOk = diagram2.rects === diagram.rects && diagram2.cjk === diagram.cjk && diagram2.scrollH === diagram.scrollH;
  record('S8 和弦显示模式切换（仅字母/字母+指法图，原生逐拍内联+歌词共存）', fullOk && inlineOk && toggleOk && restoreOk && errs.length === 0, JSON.stringify({ diagram, nameOnly, diagram2, errs }));
  await ctx.close();
}
const pass = results.filter(r => r.ok).length;
console.log('\n==== SUMMARY ' + pass + '/' + results.length + ' PASS ====');
for (const r of results.filter(r => !r.ok)) console.log('  FAIL: ' + r.name + ' | ' + r.detail);
await browser.close();
process.exit(pass === results.length ? 0 : 1);
