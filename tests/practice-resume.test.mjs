import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createResumeWriteQueue, preparePracticeResumeSettings } from '../src/lib/practice/practiceProgress.ts';

const baseResume = {
  scoreId: 'score:1',
  scoreRevision: 'revision-1',
  tick: 240,
  timeMs: 8000,
  speed: 90,
  capo: 0,
  transpose: 0,
  loop: null,
  trackIndexes: [3, 1, 3, -1, 99],
  metronome: false,
  countIn: false,
  updatedAt: 100,
};

test('resume settings only map valid track indexes from the exact current score revision', () => {
  const settings = preparePracticeResumeSettings({
    ...baseResume,
    trackMix: [
      { index: 1, muted: true, soloed: false, volume: 60, program: 24 },
      { index: 12, muted: false, soloed: true, volume: 90, program: 25 },
    ],
    display: { fontScale: 1.2, chordMode: 'name', scoreDisplayMode: 'tab', numberTab: false, showFretboard: true },
  }, 'revision-1', 4);

  assert.deepEqual(settings.visibleTrackIndexes, [1, 3]);
  assert.deepEqual(settings.trackMix, [{ index: 1, muted: true, soloed: false, volume: 60, program: 24 }]);
  assert.deepEqual(settings.display, { fontScale: 1.2, chordMode: 'name', scoreDisplayMode: 'tab', numberTab: false, showFretboard: true });
  assert.throws(() => preparePracticeResumeSettings(baseResume, 'revision-2', 4), /版本不一致/);
});

test('resume settings preserve explicit instrument overrides and accept legacy rows without the marker', () => {
  const current = preparePracticeResumeSettings({
    ...baseResume,
    trackMix: [{ index: 1, muted: false, soloed: false, volume: 100, program: 0, instrumentOverride: true }],
  }, 'revision-1', 4);
  assert.deepEqual(current.trackMix, [{ index: 1, muted: false, soloed: false, volume: 100, program: 0, instrumentOverride: true }]);

  const legacy = preparePracticeResumeSettings({
    ...baseResume,
    trackMix: [{ index: 1, muted: false, soloed: false, volume: 100, program: 0 }],
  }, 'revision-1', 4);
  assert.deepEqual(legacy.trackMix, [{ index: 1, muted: false, soloed: false, volume: 100, program: 0 }]);
});

test('old resumes without optional display or mix restore safely to all current tracks', () => {
  const oldResume = { ...baseResume, trackIndexes: [], trackMix: undefined, display: undefined };
  const settings = preparePracticeResumeSettings(oldResume, 'revision-1', 3);
  assert.deepEqual(settings.visibleTrackIndexes, [0, 1, 2]);
  assert.deepEqual(settings.trackMix, []);
  assert.equal(settings.display, undefined);
});

test('a final pause boundary is written after any older in-flight resume snapshot', async () => {
  let releaseCheckpoint;
  const checkpointGate = new Promise((resolve) => { releaseCheckpoint = resolve; });
  const persistedTicks = [];
  const enqueue = createResumeWriteQueue(async (snapshot) => {
    if (snapshot.kind === 'checkpoint') await checkpointGate;
    persistedTicks.push(snapshot.tick);
  });

  const staleWrite = enqueue({ kind: 'checkpoint', tick: 18_400 });
  await new Promise((resolve) => setImmediate(resolve));
  const endBoundary = { kind: 'end', tick: 36_481 };
  const finalWrite = enqueue(endBoundary);
  const playerTickAfterStop = 1;
  releaseCheckpoint();
  await Promise.all([staleWrite, finalWrite]);

  assert.deepEqual(persistedTicks, [18_400, 36_481]);
  assert.equal(persistedTicks.at(-1), endBoundary.tick);
  assert.notEqual(persistedTicks.at(-1), playerTickAfterStop);
});
