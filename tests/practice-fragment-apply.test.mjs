import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyPracticeFragmentSafely } from '../src/lib/practice/applyPracticeFragment.ts';

function setup() {
  const events = [];
  const fragment = { id: 'f', scoreId: 's', scoreRevision: 'a'.repeat(64), name: '副歌', note: '独立备注',
    range: { startTick: 0, endTick: 3840 }, speed: { nativeAnchorBpm: 160, startBpm: 60, targetBpm: 90, stepBpm: 5, lapsPerLevel: 2 }, createdAt: 1, updatedAt: 1 };
  let current = true;
  let value = fragment;
  let application = null;
  const options = {
    scoreId: 's', scoreRevision: fragment.scoreRevision, expectedUpdatedAt: 1,
    load: async () => value, isCurrent: () => current, endTick: () => 7680,
    nativeTempoAtTick: () => 120,
    pauseAndSave: async () => { events.push('pause-save'); return true; },
    clearPlan: async () => { events.push('clear-plan'); },
    apply: (next) => { events.push('apply'); application = next; },
  };
  return { options, events, fragment, get application() { return application; }, setCurrent(v) { current = v; }, setValue(v) { value = v; } };
}

test('applying uses the current A tempo and orders durable pause, plan clear, paused settings', async () => {
  const h = setup();
  await applyPracticeFragmentSafely(h.options);
  assert.deepEqual(h.events, ['pause-save', 'clear-plan', 'apply']);
  assert.equal(h.application.nativeAnchorBpm, 120);
  assert.equal(h.application.playbackRatio, 0.5);
  assert.equal(h.fragment.speed.nativeAnchorBpm, 160);
  assert.equal(Object.hasOwn(h.application.fragment.speed, 'completedLaps'), false);
});

test('invalid revision, stale metadata and out-of-bounds loops do not even pause', async () => {
  for (const patch of [{ scoreRevision: 'b'.repeat(64) }, { updatedAt: 2 }, { deletedAt: 2 }, { range: { startTick: 0, endTick: 99999 } }]) {
    const h = setup(); h.setValue({ ...h.fragment, ...patch });
    await assert.rejects(applyPracticeFragmentSafely(h.options));
    assert.deepEqual(h.events, []);
  }
});

test('failed durable pause prevents clearing or applying the new interval', async () => {
  const h = setup(); h.options.pauseAndSave = async () => { h.events.push('failed-pause'); return false; };
  await assert.rejects(applyPracticeFragmentSafely(h.options), /保存未完成/);
  assert.deepEqual(h.events, ['failed-pause']);
});

test('a fragment edited by another tab during pause is rejected before setting changes', async () => {
  const h = setup(); h.options.pauseAndSave = async () => { h.setValue({ ...h.fragment, updatedAt: 2 }); return true; };
  await assert.rejects(applyPracticeFragmentSafely(h.options), /修改或删除/);
  assert.equal(h.application, null);
  assert.deepEqual(h.events, []);
});

test('a switch or deletion during plan persistence cannot apply to the next score', async () => {
  for (const invalidate of [h => h.setCurrent(false), h => h.setValue(null)]) {
    const h = setup(); h.options.clearPlan = async () => { invalidate(h); };
    await assert.rejects(applyPracticeFragmentSafely(h.options));
    assert.equal(h.application, null);
  }
});

test('unavailable or unreachable native tempo refuses the operation before any playback change', async () => {
  for (const tempo of [null, 1000, NaN]) {
    const h = setup(); h.options.nativeTempoAtTick = () => tempo;
    await assert.rejects(applyPracticeFragmentSafely(h.options));
    assert.deepEqual(h.events, []);
  }
});

test('a failed plan write leaves the old playback settings intact', async () => {
  const h = setup(); h.options.clearPlan = async () => { throw new Error('quota'); };
  await assert.rejects(applyPracticeFragmentSafely(h.options), /quota/);
  assert.equal(h.application, null);
});
