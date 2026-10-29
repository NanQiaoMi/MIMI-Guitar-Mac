// Read-only local smoke check. Run from this checkout with base URL and original storage root.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { DEMO_TABS } from '../../../src/lib/demoData.ts';
import { installNodeAr } from '../../../src/lib/ar.node.ts';
import { decodeIbeToJsonNode } from '../../../src/lib/ibe.node.ts';
import { assertRenderableScore } from '../../../src/lib/scoreLoadGuard.mjs';

const base = new URL(process.argv[2]);
assert.equal(base.protocol, 'http:');
assert.ok(base.hostname === '127.0.0.1' || base.hostname === 'localhost' || base.hostname.endsWith('.localhost'));
assert.ok(['4336', '4338'].includes(base.port));
const storageRoot = process.argv[3];
assert.ok(path.isAbsolute(storageRoot));
installNodeAr();
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const rows = [];
async function verifyAsset(url, decode = false) {
  assert.ok(url.startsWith('/storage/'));
  const relative = url.slice('/storage/'.length);
  assert.ok(relative.split('/').every((part) => part && part !== '.' && part !== '..'));
  const original = await readFile(path.join(storageRoot, ...relative.split('/')));
  const response = await fetch(new URL(url, base), { cache: 'reload' });
  assert.equal(response.status, 200, url);
  assert.ok(!/text\/html/i.test(response.headers.get('content-type') ?? ''), url);
  const bytes = new Uint8Array(await response.arrayBuffer());
  assert.ok(bytes.length > 0, url);
  assert.equal(digest(bytes), digest(original), url);
  let score;
  if (decode) score = assertRenderableScore(decodeIbeToJsonNode(bytes));
  rows.push({ url, status: response.status, bytes: bytes.length, originalHashMatches: true, ...(decode ? { decoded: true, tracks: score.tracks.length, decodedTitle: score.title } : {}) });
}
for (const tab of DEMO_TABS) await verifyAsset(tab.scoreUrl, true);
for (const url of new Set(DEMO_TABS.map((tab) => tab.screenshotUrl).filter(Boolean))) await verifyAsset(url);
for (const name of ['acoustic_guitar_fast.sf2', 'ukulele_fast.sf2', '0.sf2']) await verifyAsset(`/storage/soundfonts/${name}`);
const textScore = (await readdir(path.join(storageRoot, 'xhe'))).sort().find((name) => name.endsWith('.json'));
assert.ok(textScore);
await verifyAsset(`/storage/xhe/${textScore}`);
console.log(JSON.stringify({ capturedAt: new Date().toISOString(), base: base.origin, demoScoresChecked: DEMO_TABS.length, samplesChecked: rows.length, rows }, null, 2));
