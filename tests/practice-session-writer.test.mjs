import { test } from 'node:test';
import assert from 'node:assert/strict';
import { advanceSpeedPlan, createPracticeSession, createSpeedPlan, speedMultiplierAtAnchor, StalePracticeSessionWriteError } from '../src/lib/practice/practiceProgress.ts';
import { assertPracticeNoteUnchanged, createPracticeSessionWriter, PracticeNoteConflictError } from '../src/lib/practice/practiceSessionWriter.ts';

const baseContext = { scoreId: 'score-1', scoreRevision: 'revision-1', sessionId: 'session-1' };

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((accept, fail) => { resolve = accept; reject = fail; });
  return { promise, resolve, reject };
}

function createHarness(options = {}) {
  const session = {
    ...createPracticeSession(baseContext.scoreId, baseContext.scoreRevision, 100),
    id: baseContext.sessionId,
    state: 'active',
    note: '保留原备注',
  };
  let data = { sessions: [session] };
  let currentContext = { ...baseContext };
  let generation = 1;
  let localSession = structuredClone(session);
  let wall = 1_800_000_000_000;
  let monotonic = 1_000;
  let mutateCount = 0;
  const failures = [];
  const writes = [];

  const mutatePersonalData = async (mutator) => {
    mutateCount++;
    const draft = structuredClone(data);
    if (options.beforeMutation) await options.beforeMutation({ mutateCount, draft, currentContext, generation });
    mutator(draft);
    if (options.beforeCommit) await options.beforeCommit({ mutateCount, draft, currentContext, generation });
    if (options.failMutation?.(mutateCount)) throw new Error('simulated storage failure');
    writes.push(draft.sessions.map((item) => ({ id: item.id, state: item.state, slices: item.slices.length })));
    data = draft;
    return structuredClone(data);
  };

  const writer = createPracticeSessionWriter({
    mutatePersonalData,
    getCurrentContext: () => currentContext,
    getCurrentGeneration: () => generation,
    getSession: () => localSession,
    onSessionSaved: (saved) => { localSession = structuredClone(saved); },
    onTimingFailure: (error, context, operationGeneration) => failures.push({ error, context, generation: operationGeneration }),
    nowWall: () => wall,
    nowMonotonic: () => monotonic,
    createEpoch: () => 'epoch-a',
  });

  return {
    writer,
    get data() { return structuredClone(data); },
    get localSession() { return structuredClone(localSession); },
    get failures() { return [...failures]; },
    get writes() { return [...writes]; },
    get mutateCount() { return mutateCount; },
    setContext(value) { currentContext = value ? { ...value } : null; },
    setGeneration(value) { generation = value; },
    setLocalSession(value) { localSession = value ? structuredClone(value) : null; },
    setData(value) { data = structuredClone(value); },
    setWall(value) { wall = value; },
    setMonotonic(value) { monotonic = value; },
  };
}

test('queued writes reject a stale context and never retarget the next session', async () => {
  const entered = deferred();
  const release = deferred();
  const h = createHarness({ beforeCommit: async ({ mutateCount }) => {
    if (mutateCount === 1) { entered.resolve(); await release.promise; }
  } });

  const first = h.writer.persist((latest) => ({ ...latest, note: '在途旧会话写入' }), baseContext, 1);
  await entered.promise;
  const queued = h.writer.persist((latest) => ({ ...latest, note: '不得写入新会话' }), baseContext, 1);
  h.setContext({ scoreId: 'score-2', scoreRevision: 'revision-2', sessionId: 'session-2' });
  h.setLocalSession({ ...h.localSession, id: 'session-2', scoreId: 'score-2', scoreRevision: 'revision-2' });
  release.resolve();

  await first;
  await assert.rejects(queued, /已切换/);
  assert.equal(h.data.sessions[0].note, '在途旧会话写入');
  assert.equal(h.data.sessions.some((item) => item.id === 'session-2'), false);
  assert.equal(h.localSession.id, 'session-2');
});

test('generation changes while entering the storage transaction abort the command before mutation', async () => {
  const h = createHarness({ beforeMutation: () => { h.setGeneration(2); } });

  await assert.rejects(
    h.writer.persist((latest) => ({ ...latest, note: '过期命令' }), baseContext, 1),
    /已切换/,
  );
  assert.equal(h.data.sessions[0].note, '保留原备注');
  assert.equal(h.failures.length, 0);
});

test('completed-lap speed progress uses the session generation and survives the following pause write', async () => {
  const h = createHarness();
  const range = { startTick: 12_288, endTick: 15_360 };
  const initialPlan = createSpeedPlan('revision-1', 45, 60, 15, 1, 90, range);
  const advanced = advanceSpeedPlan(initialPlan, 'session-1:loop-generation-7:lap-1', new Set());
  const loopGeneration = 7;
  const practiceGeneration = 1;

  assert.notEqual(loopGeneration, practiceGeneration);
  await assert.rejects(
    h.writer.persist((latest) => ({ ...latest, speedPlan: advanced.plan, updatedAt: 200 }), baseContext, loopGeneration),
    StalePracticeSessionWriteError,
  );
  await h.writer.persistCurrent((latest) => ({ ...latest, speedPlan: advanced.plan, updatedAt: 200 }));
  await h.writer.persistCurrent((latest) => ({ ...latest, state: 'paused', updatedAt: 201 }));

  assert.equal(h.data.sessions[0].state, 'paused');
  assert.equal(h.data.sessions[0].speedPlan.currentBpm, 60);
  assert.equal(h.data.sessions[0].speedPlan.completedLaps, 0);
  assert.equal(speedMultiplierAtAnchor(h.data.sessions[0].speedPlan.currentBpm, 90), 2 / 3);
});

test('late stale-generation failure cannot clear a new timer for the same session context', async () => {
  const h = createHarness({ beforeMutation: () => {
    h.setGeneration(2);
    h.writer.startTiming(baseContext, 2);
  } });
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(6_000);

  // The old checkpoint becomes stale after entering the transaction. Its
  // finally/error path must not clear the timer installed by generation 2.
  await h.writer.checkpoint({ playing: true, focused: true, visible: true });

  assert.equal(h.writer.isTiming(), true);
  assert.deepEqual(h.writer.getTimingState(), { context: baseContext, generation: 2 });
  assert.equal(h.writer.getPendingSlice(), null);
  assert.equal(h.data.sessions[0].slices.length, 0);
  assert.equal(h.failures.length, 0);

  h.setMonotonic(11_000);
  await h.writer.checkpoint({ playing: true, focused: true, visible: true });
  assert.equal(h.data.sessions[0].slices.length, 1);
  assert.equal(h.data.sessions[0].slices[0].durationMs, 5_000);
});

test('a failed checkpoint keeps one stable slice for an idempotent retry despite wall-clock rollback', async () => {
  const h = createHarness({ failMutation: (count) => count === 1 });
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  const initialWall = 1_800_000_000_000;
  h.setWall(initialWall - 10_000_000);
  h.setMonotonic(6_500);

  await h.writer.checkpoint({ playing: true, focused: true, visible: true });
  const pendingAfterFailure = h.writer.getPendingSlice();
  assert.ok(pendingAfterFailure);
  assert.equal(pendingAfterFailure.slice.startedAt, initialWall);
  assert.equal(pendingAfterFailure.slice.durationMs, 5_500);
  assert.equal(h.failures.length, 1);

  await h.writer.flushPending(pendingAfterFailure.context, pendingAfterFailure.generation);
  const saved = h.data.sessions[0].slices;
  assert.equal(saved.length, 1);
  assert.equal(saved[0].id, pendingAfterFailure.slice.id);
  assert.equal(saved[0].durationMs, 5_500);
  assert.equal(h.writer.getPendingSlice(), null);

  await h.writer.flushPending(baseContext, 1);
  assert.equal(h.data.sessions[0].slices.length, 1);
});

test('retrying a failed checkpoint before close does not duplicate its elapsed interval', async () => {
  const h = createHarness({ failMutation: (count) => count === 1 });
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(6_500);
  h.setWall(1_800_000_000_005);

  await h.writer.checkpoint({ playing: true, focused: true, visible: true });
  const pending = h.writer.getPendingSlice();
  assert.ok(pending);
  assert.equal(pending.closesTimer, true);
  assert.equal(pending.boundaryPerf, 6_500);

  await h.writer.flushPending(pending.context, pending.generation);
  h.setMonotonic(10_000);
  h.setWall(1_800_000_000_010);
  await h.writer.closeSlice(baseContext, 1);

  assert.equal(h.data.sessions[0].slices.length, 1);
  assert.equal(h.data.sessions[0].slices[0].durationMs, 5_500);
  assert.equal(h.data.sessions[0].slices.reduce((total, slice) => total + slice.durationMs, 0), 5_500);
  assert.equal(h.writer.isTiming(), false);
});

test('failed close retry preserves its first monotonic boundary while storage is unavailable', async () => {
  const h = createHarness({ failMutation: (count) => count === 1 });
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(4_000);
  h.setWall(1_800_000_003_000);

  await h.writer.closeSlice(baseContext, 1);
  const pending = h.writer.getPendingSlice();
  assert.ok(pending);
  assert.equal(pending.closesTimer, true);
  assert.equal(pending.boundaryPerf, 4_000);
  assert.equal(pending.slice.durationMs, 3_000);
  assert.equal(h.writer.isTiming(), false);

  // Time spent waiting for a durable local write is outside the paused session.
  h.setMonotonic(104_000);
  h.setWall(1_800_000_103_000);
  await h.writer.closeSlice(baseContext, 1);

  assert.equal(h.data.sessions[0].slices.length, 1);
  assert.equal(h.data.sessions[0].slices[0].durationMs, 3_000);
  assert.equal(h.data.sessions[0].slices[0].startedAt, 1_800_000_000_000);
  assert.equal(h.writer.getPendingSlice(), null);
  assert.equal(h.writer.isTiming(), false);
});

test('a monotonic clock starting at zero is a valid timing baseline', async () => {
  const h = createHarness();
  h.writer.startNewSession('epoch-a');
  h.setMonotonic(0);
  h.writer.startTiming(baseContext, 1);
  assert.equal(h.writer.isTiming(), true);

  h.setMonotonic(5_000);
  h.setWall(1_800_000_000_005);
  await h.writer.checkpoint({ playing: true, focused: true, visible: true });

  assert.equal(h.data.sessions[0].slices.length, 1);
  assert.equal(h.data.sessions[0].slices[0].durationMs, 5_000);
  assert.equal(h.writer.isTiming(), true);
});

test('close waits for an in-flight checkpoint, then persists the monotonic-clock tail slice', async () => {
  const entered = deferred();
  const release = deferred();
  const h = createHarness({ beforeCommit: async ({ mutateCount }) => {
    if (mutateCount === 1) { entered.resolve(); await release.promise; }
  } });
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(6_000);
  h.setWall(1_800_000_000_005);

  const checkpoint = h.writer.checkpoint({ playing: true, focused: true, visible: true });
  await entered.promise;
  h.setMonotonic(9_500);
  h.setWall(1_800_000_000_009);
  const close = h.writer.closeSlice(baseContext, 1);
  release.resolve();
  await Promise.all([checkpoint, close]);

  const slices = h.data.sessions[0].slices;
  assert.deepEqual(slices.map((slice) => slice.sequence), [1, 2]);
  assert.deepEqual(slices.map((slice) => slice.durationMs), [5_000, 3_500]);
  assert.deepEqual(slices.map((slice) => slice.id), ['session-1:epoch-a:1', 'session-1:epoch-a:2']);
  assert.equal(slices.reduce((total, slice) => total + slice.durationMs, 0), 8_500);
  assert.equal(h.writer.isTiming(), false);
});

test('finish orders tail slice, resume snapshot, completed write, then stop callback', async () => {
  const h = createHarness();
  const events = [];
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(2_000);
  h.setWall(1_800_000_000_001);

  const result = await h.writer.finish(baseContext, 1, {
    note: '最终备注草稿',
    saveResume: async () => { events.push('resume'); return true; },
    onCommitted: () => { events.push('stop'); },
  });

  assert.equal(result, 'completed');
  assert.equal(h.data.sessions[0].state, 'completed');
  assert.equal(h.data.sessions[0].note, '最终备注草稿');
  assert.equal(h.data.sessions[0].slices.reduce((total, slice) => total + slice.durationMs, 0), 1_000);
  assert.deepEqual(events, ['resume', 'stop']);
  assert.equal(h.writes.length, 2);
  assert.deepEqual(h.writes.map((write) => write[0].state), ['active', 'completed']);
});

test('finish storage failure does not call stop or replace the persisted note', async () => {
  const h = createHarness({ failMutation: (count) => count === 2 });
  let stopCount = 0;
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(2_000);

  await assert.rejects(h.writer.finish(baseContext, 1, {
    note: '未提交草稿',
    saveResume: async () => true,
    onCommitted: () => { stopCount++; },
  }), /simulated storage failure/);

  assert.equal(stopCount, 0);
  assert.equal(h.data.sessions[0].state, 'active');
  assert.equal(h.data.sessions[0].note, '保留原备注');
  assert.equal(h.data.sessions[0].slices.length, 1);
});

test('a completed session rejects a pending slice and leaves its terminal record untouched', async () => {
  const h = createHarness({ failMutation: (count) => count === 1 });
  h.writer.startNewSession('epoch-a');
  h.writer.startTiming(baseContext, 1);
  h.setMonotonic(6_000);
  await h.writer.checkpoint({ playing: true, focused: true, visible: true });
  assert.ok(h.writer.getPendingSlice());

  const completed = h.data.sessions[0];
  completed.state = 'completed';
  completed.endedAt = 1_800_000_000_000;
  h.setLocalSession(completed);
  // Simulate the canonical row being completed by another tab after the local checkpoint failed.
  const current = h.data;
  current.sessions[0].state = 'completed';
  current.sessions[0].endedAt = completed.endedAt;
  h.setData(current);
  h.setContext(baseContext);
  h.setLocalSession(completed);

  const next = h.writer.getPendingSlice();
  assert.ok(next);
  await h.writer.flushPending(next.context, next.generation);
  assert.equal(h.data.sessions[0].state, 'completed');
  assert.equal(h.data.sessions[0].slices.length, 0);
  assert.equal(h.writer.getPendingSlice(), null);
});

test('note compare-and-set accepts unrelated timing changes and rejects another note writer', async () => {
  const h = createHarness();
  const baseline = h.data.sessions[0].note;
  await h.writer.persist((latest) => ({ ...latest, updatedAt: latest.updatedAt + 1 }), baseContext, 1);
  await h.writer.persist((latest) => {
    assertPracticeNoteUnchanged(latest.note, baseline);
    return { ...latest, note: '本页确认保存' };
  }, baseContext, 1);
  const beforeConflict = h.data;
  await assert.rejects(h.writer.persist((latest) => {
    assertPracticeNoteUnchanged(latest.note, baseline);
    return { ...latest, note: '旧基准不得覆盖' };
  }, baseContext, 1), PracticeNoteConflictError);
  assert.deepEqual(h.data, beforeConflict);
});

test('finish checks the note after asynchronous resume saving and never marks a conflict completed', async () => {
  const h = createHarness();
  const baseline = h.data.sessions[0].note;
  let committed = 0;
  await assert.rejects(h.writer.finish(baseContext, 1, {
    note: '本页尚未提交的草稿',
    expectedNote: baseline,
    saveResume: async () => {
      const peerData = h.data;
      peerData.sessions[0].note = '另一页在断点保存期间写入的新备注';
      h.setData(peerData);
      return true;
    },
    onCommitted: () => { committed++; },
  }), PracticeNoteConflictError);
  assert.equal(committed, 0);
  assert.equal(h.data.sessions[0].note, '另一页在断点保存期间写入的新备注');
  assert.equal(h.data.sessions[0].state, 'active');
  assert.equal(h.data.sessions[0].endedAt, undefined);

  const resolvedBaseline = h.data.sessions[0].note;
  assert.equal(await h.writer.finish(baseContext, 1, {
    note: '查看新备注后重新提交的内容',
    expectedNote: resolvedBaseline,
    saveResume: async () => true,
    onCommitted: () => { committed++; },
  }), 'completed');
  assert.equal(committed, 1);
  assert.equal(h.data.sessions[0].note, '查看新备注后重新提交的内容');
});
