import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  filterScoreSoundfontPreset,
  inspectScoreSoundfontPreset,
  loadVerifiedScoreSoundfont,
  loadVerifiedScoreSoundfontPlan,
  SCORE_GM_SOUNDFONT_URL,
  SCORE_UKULELE_SOUNDFONT_URL,
} from '../src/lib/player/verifiedScoreSoundfont.ts';

const gmBytes = new Uint8Array(await readFile('public/soundfonts/sonivox.sf2'));
const ukuleleBytes = new Uint8Array(await readFile('public/storage/soundfonts/ukulele_fast.sf2'));

test('the bundled full GM source has every bank 0 preset and distinct nylon, steel, pad, and drum identities', () => {
  const presets = Array.from({ length: 128 }, (_, program) => inspectScoreSoundfontPreset(gmBytes, 0, program));
  assert.equal(presets.length, 128);
  assert.equal(presets[24].presetName, 'Nylon-str.Gt');
  assert.equal(presets[25].presetName, 'Steel-str.Gt');
  assert.equal(presets[89].presetName, 'Warm Pad');
  assert.notDeepEqual(presets[24].sampleNames, presets[25].sampleNames);
  const kits = [0, 8, 32, 40].map((program) => inspectScoreSoundfontPreset(gmBytes, 128, program));
  assert.equal(kits.length, 4);
  assert.ok(kits.every((kit) => kit.presetName.length > 0 && kit.sampleNames.length > 0));
});

test('the local Uke source has real 0/24/25 presets and can expose only the selected header', () => {
  const names = new Map([0, 24, 25].map((program) => [
    program,
    inspectScoreSoundfontPreset(ukuleleBytes, 0, program).presetName,
  ]));
  assert.deepEqual([...names.values()], ['Ukulele Acoustic', 'Ukulele Nylon', 'Ukulele Steel']);
  const uke24 = inspectScoreSoundfontPreset(ukuleleBytes, 0, 24);
  const gm24 = inspectScoreSoundfontPreset(gmBytes, 0, 24);
  assert.notDeepEqual(uke24.sampleNames, gm24.sampleNames);

  for (const program of [0, 24, 25]) {
    const filtered = filterScoreSoundfontPreset(ukuleleBytes, 0, program);
    assert.deepEqual(inspectScoreSoundfontPreset(filtered, 0, program), inspectScoreSoundfontPreset(ukuleleBytes, 0, program));
    for (const otherProgram of [0, 24, 25].filter((candidate) => candidate !== program)) {
      assert.throws(() => inspectScoreSoundfontPreset(filtered, 0, otherProgram), /has 0 presets/);
    }
  }
});

test('verified loader shares a bounded fetch while one caller can abort independently', async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let fetchCount = 0;
  let resolveFetch;
  const gate = new Promise((resolve) => { resolveFetch = resolve; });
  globalThis.fetch = async (url, init) => {
    fetchCount++;
    assert.equal(url, SCORE_GM_SOUNDFONT_URL);
    assert.ok(init.signal instanceof AbortSignal);
    await gate;
    return new Response(gmBytes, { status: 200 });
  };

  const cancelledController = new AbortController();
  const cancelled = loadVerifiedScoreSoundfont({ bank: 0, program: 24, flavor: 'gm', signal: cancelledController.signal });
  const surviving = loadVerifiedScoreSoundfont({ bank: 0, program: 25, flavor: 'gm' });
  cancelledController.abort();
  await assert.rejects(cancelled, { name: 'AbortError' });
  resolveFetch();
  const font = await surviving;
  assert.equal(fetchCount, 1);
  assert.equal(font.presetName, 'Steel-str.Gt');
  assert.notEqual(font.bytes, gmBytes);
  font.bytes[0] = 0;
  const next = await loadVerifiedScoreSoundfont({ bank: 0, program: 24, flavor: 'gm' });
  assert.equal(next.bytes[0], 0x52);
});

test('failed verified fetch can be retried and invalid/missing presets never fall back', async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let fetchCount = 0;
  globalThis.fetch = async (url) => {
    fetchCount++;
    assert.equal(url, SCORE_UKULELE_SOUNDFONT_URL);
    return fetchCount === 1
      ? new Response('', { status: 503 })
      : new Response(ukuleleBytes, { status: 200 });
  };

  await assert.rejects(loadVerifiedScoreSoundfont({ bank: 0, program: 24, flavor: 'ukulele' }), /HTTP 503/);
  const font = await loadVerifiedScoreSoundfont({ bank: 0, program: 24, flavor: 'ukulele' });
  assert.equal(fetchCount, 2);
  assert.equal(font.presetName, 'Ukulele Nylon');
  assert.throws(() => inspectScoreSoundfontPreset(font.bytes, 0, 25), /has 0 presets/);
  await assert.rejects(loadVerifiedScoreSoundfont({ bank: 0, program: 23, flavor: 'ukulele' }), /unavailable/);
});

test('soundfont plan verifies every requested GM preset and returns one complete GM payload', async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let fetchCount = 0;
  globalThis.fetch = async (url) => {
    fetchCount++;
    assert.equal(url, SCORE_GM_SOUNDFONT_URL);
    return new Response(gmBytes, { status: 200 });
  };
  const fonts = await loadVerifiedScoreSoundfontPlan([
    { bank: 0, program: 24, flavor: 'gm' },
    { bank: 0, program: 25, flavor: 'gm' },
    { bank: 128, program: 0, flavor: 'gm' },
  ]);
  // The cancellation test above already populated the shared GM source cache.
  assert.equal(fetchCount, 0);
  assert.equal(fonts.length, 1);
  assert.equal(fonts[0].url, SCORE_GM_SOUNDFONT_URL);
  assert.equal(fonts[0].presetName, 'Nylon-str.Gt');

  const fullProgramPlan = [
    ...Array.from({ length: 128 }, (_, program) => ({ bank: 0, program, flavor: 'gm' })),
    ...[0, 8, 32, 40].map((program) => ({ bank: 128, program, flavor: 'gm' })),
  ];
  const allPresets = await loadVerifiedScoreSoundfontPlan(fullProgramPlan);
  assert.equal(allPresets.length, 1);
  await assert.rejects(loadVerifiedScoreSoundfontPlan([
    ...fullProgramPlan,
    { bank: 128, program: 127, flavor: 'gm' },
  ]), /bank 128, program 127 has 0 presets/);
  await assert.rejects(loadVerifiedScoreSoundfontPlan([
    { bank: 0, program: 24, flavor: 'gm' },
    { bank: 0, program: 24, flavor: 'ukulele' },
  ]), /Conflicting SoundFont flavors for bank 0, program 24/);
});
