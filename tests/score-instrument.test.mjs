import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isUkuleleScore, primaryStringTrackIndex } from '../src/lib/player/scoreInstrument.ts';

test('explicit personal score category prevents a four-string bass track from changing the guitar UI', () => {
  const primaryBassTuning = [43, 38, 33, 28];
  assert.equal(isUkuleleScore('guitar', primaryBassTuning), false);
  assert.equal(isUkuleleScore('bass', primaryBassTuning), false);
  assert.equal(isUkuleleScore('ukulele', [69, 64, 60, 67]), true);
});

test('legacy instrument inference inspects only the selected primary track', () => {
  const guitarTuning = [64, 59, 55, 50, 45, 40];
  assert.equal(primaryStringTrackIndex(3, 0, [0, 1, 2]), 0);
  assert.equal(isUkuleleScore('', guitarTuning), false);
  assert.equal(primaryStringTrackIndex(3, 8, [2, 1]), 2);
  assert.equal(isUkuleleScore('', [69, 64, 60, 67]), true);
});
