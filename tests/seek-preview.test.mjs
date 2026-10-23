import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  beginSeekPreview,
  observeSeekPreviewPosition,
  settleSeekPreview,
  updateSeekPreview,
} from '../src/lib/player/seekPreview.ts';

test('cancelling a preview restores the newest actual player position, never the thumb preview', () => {
  const started = beginSeekPreview(4, { tick: 480, timeMs: 1000 }, 1200);
  const dragged = updateSeekPreview(started, 2400);
  const observed = observeSeekPreviewPosition(dragged, 4, { tick: 720, timeMs: 1500 });

  assert.deepEqual(settleSeekPreview(observed, 4, 'cancel'), {
    kind: 'cancel', position: { tick: 720, timeMs: 1500 },
  });
});

test('committing returns the selected tick and a later capture-loss cancellation cannot undo it', () => {
  const preview = updateSeekPreview(beginSeekPreview(2, { tick: 100, timeMs: 500 }, 100), 900);

  assert.deepEqual(settleSeekPreview(preview, 2, 'commit'), {
    kind: 'commit', tick: 900, origin: { tick: 100, timeMs: 500 }, latestActual: { tick: 100, timeMs: 500 },
  });
  assert.equal(settleSeekPreview(null, 2, 'cancel'), null);
});

test('committing back to the starting tick still seeks when playback moved during the drag', () => {
  const started = beginSeekPreview(4, { tick: 480, timeMs: 1000 }, 900);
  const playing = observeSeekPreviewPosition(started, 4, { tick: 720, timeMs: 1500 });
  const returnedToOrigin = updateSeekPreview(playing, 480);
  const outcome = settleSeekPreview(returnedToOrigin, 4, 'commit');

  assert.deepEqual(outcome, {
    kind: 'commit',
    tick: 480,
    origin: { tick: 480, timeMs: 1000 },
    latestActual: { tick: 720, timeMs: 1500 },
  });
  assert.notEqual(outcome.tick, outcome.latestActual.tick);
});

test('cancelling after an A-B loop finish restores the confirmed loop start', () => {
  const active = updateSeekPreview(beginSeekPreview(3, { tick: 300, timeMs: 900 }, 1200), 1800);
  const finishedAtLoopStart = observeSeekPreviewPosition(active, 3, { tick: 600, timeMs: 1400 });

  assert.deepEqual(settleSeekPreview(finishedAtLoopStart, 3, 'cancel'), {
    kind: 'cancel', position: { tick: 600, timeMs: 1400 },
  });
});

test('cancelling after natural finish restores the confirmed end tick and end time', () => {
  const active = updateSeekPreview(beginSeekPreview(5, { tick: 200, timeMs: 700 }, 1500), 2000);
  const finishedAtEnd = observeSeekPreviewPosition(active, 5, { tick: 2400, timeMs: 6000 });

  assert.deepEqual(settleSeekPreview(finishedAtEnd, 5, 'cancel'), {
    kind: 'cancel', position: { tick: 2400, timeMs: 6000 },
  });
});

test('positions from an older score generation cannot replace or settle the current preview', () => {
  const preview = beginSeekPreview(8, { tick: 200, timeMs: 600 }, 1000);
  const unchanged = observeSeekPreviewPosition(preview, 7, { tick: 7000, timeMs: 9000 });

  assert.equal(unchanged, preview);
  assert.deepEqual(settleSeekPreview(preview, 7, 'cancel'), { kind: 'stale' });
  assert.deepEqual(settleSeekPreview(preview, 8, 'cancel'), {
    kind: 'cancel', position: { tick: 200, timeMs: 600 },
  });
});

test('keyboard-style preview updates use the same confirmed commit and validate ticks', () => {
  const preview = updateSeekPreview(beginSeekPreview(1, { tick: 0, timeMs: 0 }, 0), 1);
  assert.deepEqual(settleSeekPreview(preview, 1, 'commit'), {
    kind: 'commit', tick: 1, origin: { tick: 0, timeMs: 0 }, latestActual: { tick: 0, timeMs: 0 },
  });
  assert.throws(() => updateSeekPreview(preview, -1), RangeError);
});
