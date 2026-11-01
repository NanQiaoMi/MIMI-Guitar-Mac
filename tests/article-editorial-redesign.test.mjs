import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import sqlite3 from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { DEMO_ARTICLES } from '../src/lib/demoData.ts';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const catalogDbPath = path.join(root, 'native-macos', 'Data', 'catalog.sqlite');

test('all required tutorial and editorial articles are present in catalog.sqlite and demoData', async () => {
  const expectedIDs = [
    'art-player',
    'art-studio',
    'art-practice',
    'art-tab',
    'art-capo',
    'art-barre',
    'art-ukulele',
    'art-backup',
  ];

  // 1. Verify demoData
  const demoIDs = new Set(DEMO_ARTICLES.map((a) => a.id));
  for (const id of expectedIDs) {
    assert.ok(demoIDs.has(id), `DEMO_ARTICLES is missing expected tutorial: ${id}`);
  }

  // 2. Verify catalog.sqlite exists and has clean records
  assert.ok(fs.existsSync(catalogDbPath), 'catalog.sqlite must exist');
  
  const db = new sqlite3.DatabaseSync(catalogDbPath, { open: true, readOnly: true });
  const rows = db.prepare('SELECT id, title, category, views FROM articles').all();
  db.close();

  const dbIDs = new Set(rows.map((r) => r.id));
  for (const id of expectedIDs) {
    assert.ok(dbIDs.has(id), `catalog.sqlite is missing expected article: ${id}`);
  }

  // 3. Verify that test noise articles are filtered/cleaned
  for (const row of rows) {
    assert.ok(!row.title.startsWith('测试文章'), `Found uncleaned test article: ${row.title}`);
    assert.ok(!row.title.startsWith('M7 验收文章'), `Found uncleaned test article: ${row.title}`);
  }
});

test('tutorial diagrams exist in public and native resources and have valid SVG tags', () => {
  const diagrams = [
    'player-guide-diagram.svg',
    'studio-workflow-diagram.svg',
    'tab-reading-diagram.svg',
    'capo-chart-diagram.svg',
  ];

  for (const file of diagrams) {
    const webPath = path.join(root, 'public', 'images', 'tutorials', file);
    const nativePath = path.join(root, 'native-macos', 'Resources', 'Design', 'tutorials', file);

    assert.ok(fs.existsSync(webPath), `Web tutorial diagram must exist at ${webPath}`);
    assert.ok(fs.existsSync(nativePath), `Native tutorial diagram must exist at ${nativePath}`);

    const content = fs.readFileSync(webPath, 'utf8');
    assert.ok(content.includes('<svg'), `File ${file} must contain valid svg tag`);
    assert.ok(content.includes('</svg>'), `File ${file} must properly close svg tag`);
  }
});

test('article contents include structured headings, callout boxes, and practical tutorials', () => {
  const playerArt = DEMO_ARTICLES.find((a) => a.id === 'art-player');
  assert.ok(playerArt, 'art-player must exist');
  assert.ok(playerArt.content.includes('# '), 'art-player must include H1 title');
  assert.ok(playerArt.content.includes('## '), 'art-player must include H2 section');
  assert.ok(playerArt.content.includes('> [!TIP]'), 'art-player must include tip callout');
  assert.ok(playerArt.content.includes('A-B'), 'art-player must cover A-B loop practice');
  assert.ok(playerArt.content.includes('AlphaTab'), 'art-player must mention AlphaTab engine');

  const studioArt = DEMO_ARTICLES.find((a) => a.id === 'art-studio');
  assert.ok(studioArt, 'art-studio must exist');
  assert.ok(studioArt.content.includes('时值'), 'art-studio must explain note durations');
  assert.ok(studioArt.content.includes('品位'), 'art-studio must explain fret input');
});
