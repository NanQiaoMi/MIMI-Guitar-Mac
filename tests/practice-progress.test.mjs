import { test } from 'node:test';
import assert from 'node:assert/strict';
import { advanceSpeedPlan, assertPracticeSessionWriteContext, canCountLoopCompletion, canPersistResume, cloneSpeedPlan, CompletedPracticeSessionError, createLoopLapProgress, createPracticeSession, createSpeedPlan, hasSpeedPlanAnchor, isCompletedLoopLap, isResumeCheckpointDue, isSpeedPlanApplied, isValidPlaybackRatio, isValidPracticeLoopRange, makePracticeSlice, normalizePracticeLoopSelection, normalizePracticeSessionUpdate, observeLoopLapProgress, preparePracticeResumeSettings, reconcilePracticeSession, sameResumeContent, speedMultiplierAtAnchor, speedPlanMatchesLoop, startsCompleteLoopLap, updatePracticeSessionIfOpen } from '../src/lib/practice/practiceProgress.ts';

test('practice slices have stable IDs and monotonic sequences', () => {
  const session = { id: 's1' };
  const slice = makePracticeSlice(session, 4, 1000, 5000, 'epoch-a');
  assert.equal(slice.id, 's1:epoch-a:4');
  assert.equal(slice.sequence, 4);
  assert.throws(() => makePracticeSlice(session, 0, 1000, 5000, 'epoch-a'), RangeError);
});

test('clock rollback cannot make a note or completion lose timestamp-based session merging', () => {
  const original = {
    id: 'session-1', scoreId: 'score-1', scoreRevision: 'hash-1', state: 'paused',
    startedAt: 15_000, updatedAt: 20_000, timezone: 'UTC', note: '旧备注',
    slices: [{ id: 'slice-1', sequence: 1, epoch: 'epoch-1', startedAt: 16_000, durationMs: 4_000 }],
  };
  const afterNote = normalizePracticeSessionUpdate(
    original,
    { ...original, note: '回拨后仍要保存的新备注', updatedAt: 10_000 },
    10_000,
  );
  assert.equal(afterNote.updatedAt, original.updatedAt + 1);
  assert.equal(afterNote.note, '回拨后仍要保存的新备注');

  const afterCompletion = normalizePracticeSessionUpdate(
    afterNote,
    { ...afterNote, state: 'completed', endedAt: 9_000, updatedAt: 9_000 },
    9_000,
  );
  assert.equal(afterCompletion.updatedAt, afterNote.updatedAt + 1);
  assert.equal(afterCompletion.state, 'completed');
  assert.equal(afterCompletion.note, '回拨后仍要保存的新备注');
  assert.ok(afterCompletion.endedAt >= afterCompletion.startedAt);
  assert.equal(afterCompletion.endedAt, afterCompletion.startedAt);
  assert.deepEqual(afterCompletion.slices, original.slices);
  assert.equal(afterCompletion.slices[0].durationMs, 4_000);

  const futureProposal = normalizePracticeSessionUpdate(
    afterCompletion,
    { ...afterCompletion, updatedAt: 30_000 },
    9_000,
  );
  assert.equal(futureProposal.updatedAt, 30_000);
});

test('refresh clears completed or deleted local sessions and hydrates a newer open session', () => {
  const local = createPracticeSession('score-1', 'hash-1', 1000);
  local.state = 'interrupted';
  const completed = { ...local, state: 'completed', endedAt: 2000 };
  assert.equal(reconcilePracticeSession(local, [completed], 'score-1', 'hash-1'), null);
  assert.equal(reconcilePracticeSession(local, [], 'score-1', 'hash-1'), null);

  const newer = { ...createPracticeSession('score-1', 'hash-1', 3000), state: 'active' };
  const reconciled = reconcilePracticeSession(local, [completed, newer], 'score-1', 'hash-1');
  assert.equal(reconciled.id, newer.id);
  assert.equal(reconciled.state, 'interrupted');
});

test('a delayed session write cannot reopen the canonical completed record', () => {
  const completed = { ...createPracticeSession('score-1', 'hash-1', 1000), state: 'completed', endedAt: 2000 };
  const sessions = [completed];
  assert.throws(() => updatePracticeSessionIfOpen(
    sessions,
    completed.id,
    (latest) => ({ ...latest, state: 'active', endedAt: undefined }),
    3000,
  ), CompletedPracticeSessionError);
  assert.deepEqual(sessions, [completed]);
});

test('queued session writes are rejected after the active score or session changes', () => {
  const original = { scoreId: 'score-1', scoreRevision: 'hash-1', sessionId: 'session-1' };
  assert.doesNotThrow(() => assertPracticeSessionWriteContext(original, { ...original }));
  assert.throws(() => assertPracticeSessionWriteContext(original, {
    scoreId: 'score-2', scoreRevision: 'hash-2', sessionId: 'session-2',
  }), /已切换/);
  assert.throws(() => assertPracticeSessionWriteContext(original, null), /已切换/);
});

test('resume checkpoint cadence follows monotonic elapsed time through wall-clock rollback', () => {
  const lastPerformanceWrite = 12_000;
  const wallClockBefore = 1_800_000_000_000;
  const wallClockAfterRollback = 1_799_996_400_000;
  assert.ok(wallClockAfterRollback < wallClockBefore);
  assert.equal(isResumeCheckpointDue(16_999, lastPerformanceWrite), false);
  assert.equal(isResumeCheckpointDue(17_000, lastPerformanceWrite), true);
  assert.equal(isResumeCheckpointDue(100, null), true);
});

test('only a real non-seek crossing completes a lap; duplicate lap IDs do not advance twice', () => {
  const range = { startTick: 100, endTick: 500 };
  assert.equal(isCompletedLoopLap(490, 105, range, false), false);
  assert.equal(isCompletedLoopLap(490, 500, range, false), true);
  assert.equal(isCompletedLoopLap(490, 500, range, true), false);
  const seen = new Set();
  const plan = createSpeedPlan('hash', 60, 70, 5, 2);
  const first = advanceSpeedPlan(plan, 'session:lap:1', seen);
  const duplicate = advanceSpeedPlan(first.plan, 'session:lap:1', seen);
  const second = advanceSpeedPlan(first.plan, 'session:lap:2', seen);
  assert.equal(duplicate.changed, false);
  assert.equal(second.plan.currentBpm, 65);
  const atGoal = { ...second.plan, currentBpm: 70, completedLaps: 0 };
  const held = advanceSpeedPlan(atGoal, 'session:lap:3', seen);
  assert.equal(held.changed, false);
  assert.equal(held.plan.completedLaps, 0);
  assert.equal(held.plan.currentBpm, 70);
  assert.equal(speedMultiplierAtAnchor(60, 120), 0.5);
});

test('playback ratios are constrained to the actual AlphaTab setter range', () => {
  assert.equal(isValidPlaybackRatio(0.125), true);
  assert.equal(isValidPlaybackRatio(8), true);
  assert.equal(isValidPlaybackRatio(0.1249), false);
  assert.equal(isValidPlaybackRatio(8.001), false);
  assert.equal(isValidPlaybackRatio(Number.NaN), false);
  assert.equal(isValidPlaybackRatio(Number.POSITIVE_INFINITY), false);
  assert.throws(() => createSpeedPlan('hash', 20, 100, 5, 1, 200), RangeError);
});

test('playerFinished lap counts only after uninterrupted A-B playback with matching unfolded range', () => {
  const event = { startTick: 100, endTick: 500 };
  const range = { ...event };
  const eligible = { playing: true, focused: true, visible: true, observedFromA: true, event, range };
  assert.equal(canCountLoopCompletion(eligible), true);
  assert.equal(canCountLoopCompletion({ ...eligible, observedFromA: false }), false);
  assert.equal(canCountLoopCompletion({ ...eligible, focused: false }), false);
  assert.equal(canCountLoopCompletion({ ...eligible, visible: false }), false);
  assert.equal(canCountLoopCompletion({ ...eligible, event: { startTick: 700, endTick: 900 } }), false);
  assert.equal(canCountLoopCompletion({ ...eligible, event: null }), false);
});

test('seeking to the middle of A-B cannot arm a partial lap', () => {
  const range = { startTick: 100, endTick: 500 };
  assert.equal(startsCompleteLoopLap(null, 100, range, true), true);
  assert.equal(startsCompleteLoopLap(null, 101, range, true), true);
  assert.equal(startsCompleteLoopLap(null, 99, range, true), false);
  assert.equal(startsCompleteLoopLap(null, 102, range, true), false);
  assert.equal(startsCompleteLoopLap(null, 280, range, true), false);
  assert.equal(startsCompleteLoopLap(null, 280, range, false), false);
  assert.equal(startsCompleteLoopLap(80, 120, range, false), true);
});

test('a quantized seek at A arms and its matching finished event can complete a lap', () => {
  const range = { startTick: 80_162, endTick: 80_640 };
  const quantizedSeekTick = 80_163;
  const armed = startsCompleteLoopLap(null, quantizedSeekTick, range, true);
  const event = { ...range };
  assert.equal(armed, true);
  assert.equal(canCountLoopCompletion({
    playing: true, focused: true, visible: true, observedFromA: armed, event, range,
  }), true);
  assert.equal(canCountLoopCompletion({
    playing: true, focused: true, visible: true,
    observedFromA: startsCompleteLoopLap(null, 80_200, range, true), event, range,
  }), false);
});

test('loading an existing resume does not authorize an overwrite until user state is dirty', () => {
  const loaded = { dirty: false, joined: true, dataReady: true, playerReady: true, hasPosition: true, restoring: false };
  assert.equal(canPersistResume(loaded), false);
  assert.equal(canPersistResume({ ...loaded, dirty: true }), true);
  assert.equal(canPersistResume({ ...loaded, dirty: true, restoring: true }), false);
  assert.equal(canPersistResume({ ...loaded, explicitSnapshot: true }), true);
  assert.equal(canPersistResume({ ...loaded, explicitSnapshot: true, playerReady: false }), false);
  assert.equal(canPersistResume({ ...loaded, explicitSnapshot: true, hasPosition: false }), false);
});

test('unchanged resume content is idempotent regardless of updatedAt', () => {
  const saved = {
    scoreId: 'score:1', scoreRevision: 'hash-1', tick: 80162, timeMs: 12000, speed: 60,
    capo: 0, transpose: 0, loop: { startTick: 80162, endTick: 80640 },
    trackIndexes: [0, 2], metronome: false, countIn: false, updatedAt: 100,
  };
  assert.equal(sameResumeContent(saved, { ...saved, updatedAt: 999 }), true);
  assert.equal(sameResumeContent(saved, { ...saved, tick: 80163, updatedAt: 999 }), false);
  assert.equal(sameResumeContent(saved, { ...saved, trackIndexes: [0], updatedAt: 999 }), false);
  assert.equal(sameResumeContent(saved, { ...saved, trackMix: [{ index: 0, muted: true, soloed: false, volume: 65, program: 24 }] }), false);
  assert.equal(sameResumeContent(saved, { ...saved, display: { fontScale: 1, chordMode: 'diagram', scoreDisplayMode: 'mixed', numberTab: true, showFretboard: false } }), false);
  assert.equal(sameResumeContent(saved, { ...saved, useSourceCapo: false }), true);
  assert.equal(sameResumeContent({ ...saved, useSourceCapo: true }, { ...saved, useSourceCapo: true }), true);
  assert.equal(sameResumeContent({ ...saved, useSourceCapo: true }, saved), false);
});

test('practice resume snapshots retain optional instrumentOverride while older rows remain compatible', () => {
  const base = {
    scoreId: 'score-1', scoreRevision: 'hash-1', tick: 0, timeMs: 0, speed: 80,
    capo: 0, transpose: 0, loop: null, trackIndexes: [0], metronome: false, countIn: false,
    updatedAt: 1,
  };
  const current = preparePracticeResumeSettings({
    ...base,
    trackMix: [{ index: 0, muted: false, soloed: false, volume: 100, program: 0, instrumentOverride: true }],
  }, 'hash-1', 1);
  assert.equal(current.trackMix[0].instrumentOverride, true);

  const legacy = preparePracticeResumeSettings({
    ...base,
    trackMix: [{ index: 0, muted: false, soloed: false, volume: 100, program: 0 }],
  }, 'hash-1', 1);
  assert.equal('instrumentOverride' in legacy.trackMix[0], false);
});

test('A-B normalization includes the current beat, accepts the exact score end, and supports one beat', () => {
  assert.deepEqual(normalizePracticeLoopSelection({
    pointATick: 7_200, pointABeatEndTick: 7_680,
    currentTick: 7_500, currentBeatEndTick: 7_680, scoreEndTick: 7_680,
  }), { startTick: 7_200, endTick: 7_680 });
  assert.deepEqual(normalizePracticeLoopSelection({
    pointATick: 1_920, pointABeatEndTick: 3_840,
    currentTick: 1_920, currentBeatEndTick: 3_840, scoreEndTick: 7_680,
  }), { startTick: 1_920, endTick: 3_840 });
  assert.deepEqual(normalizePracticeLoopSelection({
    pointATick: 1, pointABeatEndTick: 480,
    currentTick: 7_680, currentBeatEndTick: 7_680, scoreEndTick: 7_680,
  }), { startTick: 1, endTick: 7_680 });
  assert.throws(() => normalizePracticeLoopSelection({
    pointATick: 1, pointABeatEndTick: 480,
    currentTick: 7_681, currentBeatEndTick: 7_681, scoreEndTick: 7_680,
  }), /当前位置已超出/);
  assert.throws(() => normalizePracticeLoopSelection({
    pointATick: 1, pointABeatEndTick: 480,
    currentTick: 7_680, currentBeatEndTick: 7_681, scoreEndTick: 7_680,
  }), /无法确认当前拍末/);
  assert.equal(isValidPracticeLoopRange({ startTick: 7_200, endTick: 7_680 }, 7_680), true);
});

test('reverse A-B selection uses the beat end captured at A and rejects unknown or corrupt metadata', () => {
  assert.deepEqual(normalizePracticeLoopSelection({
    pointATick: 4_000, pointABeatEndTick: 4_800,
    currentTick: 2_000, currentBeatEndTick: 2_880, scoreEndTick: 7_680,
  }), { startTick: 2_000, endTick: 4_800 });
  assert.throws(() => normalizePracticeLoopSelection({
    pointATick: 4_000, pointABeatEndTick: null,
    currentTick: 2_000, currentBeatEndTick: 2_880, scoreEndTick: 7_680,
  }), /无法确认 A 点当时的拍末/);
  for (const currentBeatEndTick of [0, 1_999, 7_681, 2_880.5, Number.NaN]) {
    assert.throws(() => normalizePracticeLoopSelection({
      pointATick: 2_000, pointABeatEndTick: 2_880,
      currentTick: 2_000, currentBeatEndTick, scoreEndTick: 7_680,
    }));
  }
  assert.throws(() => normalizePracticeLoopSelection({
    pointATick: 7_680, pointABeatEndTick: 7_680,
    currentTick: 7_680, currentBeatEndTick: 7_680, scoreEndTick: 7_680,
  }));
  assert.equal(isValidPracticeLoopRange({ startTick: 0, endTick: 7_681 }, 7_680), false);
});

test('loop progress discards seek and interruption state and only re-arms at A', () => {
  const range = { startTick: 100, endTick: 500 };
  let progress = createLoopLapProgress(3, 8, range);
  progress = observeLoopLapProgress(progress, { tick: 100, isSeek: true, generation: 3, interruptionRevision: 8, range, playing: true, focused: true, visible: true });
  assert.equal(progress.observedFromA, true);
  progress = observeLoopLapProgress(progress, { tick: 240, isSeek: false, generation: 3, interruptionRevision: 9, range, playing: true, focused: true, visible: true });
  assert.equal(progress.observedFromA, false);
  assert.equal(progress.previousTick, 240);
  progress = observeLoopLapProgress(progress, { tick: 300, isSeek: false, generation: 3, interruptionRevision: 9, range, playing: true, focused: false, visible: true });
  assert.equal(progress.observedFromA, false);
  assert.equal(progress.previousTick, null);
  progress = observeLoopLapProgress(progress, { tick: 250, isSeek: false, generation: 3, interruptionRevision: 10, range, playing: true, focused: true, visible: true });
  assert.equal(progress.observedFromA, false);
  progress = observeLoopLapProgress(progress, { tick: 100, isSeek: true, generation: 3, interruptionRevision: 10, range, playing: true, focused: true, visible: true });
  assert.equal(progress.observedFromA, true);
});

test('speed plans are plain snapshots with detached loop ranges before persistence', () => {
  const plan = createSpeedPlan('hash', 60, 65, 5, 1, 200, { startTick: 80_162, endTick: 80_640 });
  const persisted = cloneSpeedPlan(plan);
  assert.deepEqual(structuredClone(persisted), persisted);
  assert.notEqual(persisted.loopRange, plan.loopRange);
  persisted.loopRange.startTick = 1;
  assert.equal(plan.loopRange.startTick, 80_162);
});

test('speed plan keeps its native A tempo and unfolded A-B binding after reload', () => {
  const range = { startTick: 12_000, endTick: 24_000 };
  const plan = createSpeedPlan('score-hash', 60, 90, 5, 2, 90, range);
  const reloaded = JSON.parse(JSON.stringify(plan));

  assert.equal(reloaded.currentBpm, 60);
  assert.equal(reloaded.nativeAnchorBpm, 90);
  assert.equal(speedMultiplierAtAnchor(reloaded.currentBpm, reloaded.nativeAnchorBpm), 60 / 90);
  assert.equal(hasSpeedPlanAnchor(reloaded), true);
  assert.equal(speedPlanMatchesLoop(reloaded, range), true);
  assert.equal(speedPlanMatchesLoop(reloaded, { startTick: 12_001, endTick: 24_000 }), false);
  assert.equal(hasSpeedPlanAnchor({ ...reloaded, nativeAnchorBpm: undefined }), false);
  assert.throws(() => createSpeedPlan('score-hash', 60, 90, 5, 2, 0, range), RangeError);
});

test('a persisted speed plan is pending until its saved loop and actual ratio are restored', () => {
  const range = { startTick: 12_000, endTick: 24_000 };
  const plan = createSpeedPlan('score-hash', 80, 100, 5, 2, 120, range);

  assert.equal(isSpeedPlanApplied(plan, null, 1), false);
  assert.equal(isSpeedPlanApplied(plan, range, 1), false);
  assert.equal(isSpeedPlanApplied(plan, { startTick: 12_001, endTick: 24_000 }, 80 / 120), false);
  assert.equal(isSpeedPlanApplied(plan, range, 80 / 120), true);
});
