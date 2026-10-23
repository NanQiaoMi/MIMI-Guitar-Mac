import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveManuscriptBarSeekTarget } from '../src/lib/player/manuscriptSeek.mjs';

test('resolves a clicked source bar through the actual tick-cache playback instance', () => {
  const firstPassOnlyLookup = new Map([[7, { start: 0 }]]);
  const tickCache = {
    masterBarLookup: firstPassOnlyLookup,
    masterBars: [
      { masterBar: { index: 3 }, start: 0, end: 480 },
      { masterBar: { index: 7 }, start: 480, end: 960 },
      { masterBar: { index: 3 }, start: 960, end: 1440 },
    ],
  };

  assert.deepEqual(resolveManuscriptBarSeekTarget(tickCache, 7, 1200), {
    sourceBarIndex: 7,
    tick: 480,
    occurrence: 1,
    occurrenceCount: 1,
  });
});

test('chooses the repeated source bar containing the current playback tick', () => {
  const tickCache = {
    masterBars: [
      { masterBar: { index: 4 }, start: 0, end: 600 },
      { masterBar: { index: 9 }, start: 600, end: 900 },
      { masterBar: { index: 4 }, start: 900, end: 1500 },
    ],
  };

  assert.deepEqual(resolveManuscriptBarSeekTarget(tickCache, 4, 1200), {
    sourceBarIndex: 4,
    tick: 900,
    occurrence: 2,
    occurrenceCount: 2,
  });
});

test('chooses the nearest occurrence by its playback interval and breaks ties earlier', () => {
  const tickCache = {
    masterBars: [
      { masterBar: { index: 2 }, start: 100, end: 300 },
      { masterBar: { index: 2 }, start: 700, end: 900 },
      { masterBar: { index: 2 }, start: 1300, end: 1500 },
    ],
  };

  assert.equal(resolveManuscriptBarSeekTarget(tickCache, 2, 600)?.tick, 700);
  assert.equal(resolveManuscriptBarSeekTarget(tickCache, 2, 500)?.tick, 100);
});

test('returns no target for invalid source indices or unavailable playback bars', () => {
  const tickCache = {
    masterBars: [
      { masterBar: { index: 5 }, start: 600, end: 600 },
      { masterBar: { index: 5 }, start: -10, end: 200 },
      { masterBar: { index: 5 }, start: 100, end: Number.NaN },
    ],
  };

  assert.equal(resolveManuscriptBarSeekTarget(tickCache, -1, 0), null);
  assert.equal(resolveManuscriptBarSeekTarget(tickCache, 5, 0), null);
  assert.equal(resolveManuscriptBarSeekTarget(null, 5, 0), null);
});
