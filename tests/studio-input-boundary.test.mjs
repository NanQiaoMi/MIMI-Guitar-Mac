import test from 'node:test';
import assert from 'node:assert/strict';
import { createStudioFretInput } from '../src/lib/studio/studioFretInput.ts';
import { createStudioSaveBoundary } from '../src/lib/studio/studioSaveBoundary.ts';

function inputHarness() {
  let context = 'project-a:rev1:beat1';
  const commits = [];
  const scheduled = [];
  const pendingChanges = [];
  const input = createStudioFretInput({
    context: () => context,
    commit: (fret) => commits.push({ fret, context }),
    onPendingChange: (pending) => pendingChanges.push(pending),
    schedule(callback, delay) { assert.equal(delay, 320); scheduled.push(callback); return scheduled.length; },
    cancel() {}, // Deliberately deliver cancelled callbacks to test their generation guards.
  });
  return { input, commits, scheduled, pendingChanges, change(value) { context = value; } };
}

test('fret entry combines 10 through 24 once and invalidates old timer delivery', () => {
  const h = inputHarness();
  h.input.push('1'); h.input.push('2');
  h.scheduled[0]();
  h.input.push('2'); h.input.push('4');
  h.scheduled[1]();
  assert.deepEqual(h.commits.map((entry) => entry.fret), [12, 24]);
});

test('single digit settles before switching target; later callbacks cannot follow the cursor', () => {
  const h = inputHarness();
  h.input.push('1'); h.input.flush();
  h.change('project-b:rev1:beat2'); h.scheduled[0]();
  assert.deepEqual(h.commits, [{ fret: 1, context: 'project-a:rev1:beat1' }]);
  h.input.push('2'); h.change('project-b:rev2:beat2'); h.scheduled[1]();
  assert.equal(h.commits.length, 1);
});

test('a stale pending digit cannot combine with a new context and teardown discards input', () => {
  const h = inputHarness();
  h.input.push('1'); h.change('new-track'); h.input.push('3');
  h.scheduled[0]();
  assert.deepEqual(h.commits, [{ fret: 3, context: 'new-track' }]);
  h.input.push('2'); h.input.cancel(); h.scheduled[1]();
  assert.equal(h.commits.length, 1);
});

test('over-limit pair retains both notes and flush clears itself before reentrant commits', () => {
  const h = inputHarness();
  h.input.push('2'); h.input.push('9'); h.input.push('0'); h.input.push('no');
  assert.deepEqual(h.commits.map((entry) => entry.fret), [2, 9, 0]);
  let commits = 0;
  const input = createStudioFretInput({ context: () => 'same', commit() { commits++; input.flush(); } });
  input.push('1'); input.flush();
  assert.equal(commits, 1);
});

test('delayed fret input exposes pending state before flush so unload guards cannot miss it', () => {
  const h = inputHarness();
  h.input.push('1');
  assert.equal(h.input.hasPending, true);
  assert.deepEqual(h.pendingChanges, [true]);
  h.input.flush();
  assert.equal(h.input.hasPending, false);
  assert.deepEqual(h.pendingChanges, [true, false]);
});

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

test('save boundary includes a newer save issued while waiting', async () => {
  const boundary = createStudioSaveBoundary();
  const first = deferred(), second = deferred();
  boundary.track(first.promise);
  let settled = false;
  const waiting = boundary.settle().then(() => { settled = true; });
  boundary.track(second.promise);
  first.resolve();
  await Promise.resolve(); await Promise.resolve();
  assert.equal(settled, false);
  second.resolve(); await waiting;
  assert.equal(settled, true);
});

test('failed latest save blocks replacement until an explicit successful retry', async () => {
  const boundary = createStudioSaveBoundary();
  await boundary.settle();
  const failed = deferred();
  boundary.track(failed.promise).catch(() => {});
  failed.reject(new Error('quota'));
  await assert.rejects(boundary.settle(), /quota/);
  boundary.track(Promise.resolve());
  await boundary.settle();
});

test('superseded failed save cannot reject a successful later queued snapshot', async () => {
  const boundary = createStudioSaveBoundary();
  const failed = deferred(), retry = deferred();
  boundary.track(failed.promise).catch(() => {});
  const waiting = boundary.settle();
  boundary.track(retry.promise);
  failed.reject(new Error('old failure')); retry.resolve();
  await waiting;
});

test('save boundary publishes pending and failed states, then clears them after a successful retry', async () => {
  const boundary = createStudioSaveBoundary();
  const snapshots = [];
  const unsubscribe = boundary.subscribe((snapshot) => snapshots.push(snapshot));
  assert.deepEqual(snapshots.at(-1), { pending: false, error: null });

  const failed = deferred();
  boundary.track(failed.promise).catch(() => {});
  assert.deepEqual(boundary.getSnapshot(), { pending: true, error: null });
  failed.reject(new Error('disk full'));
  await assert.rejects(boundary.settle(), /disk full/);
  assert.equal(boundary.getSnapshot().pending, false);
  assert.match(boundary.getSnapshot().error.message, /disk full/);

  const retry = deferred();
  boundary.track(retry.promise);
  assert.deepEqual(boundary.getSnapshot(), { pending: true, error: null });
  retry.resolve();
  await boundary.settle();
  assert.deepEqual(boundary.getSnapshot(), { pending: false, error: null });
  assert.ok(snapshots.some((snapshot) => snapshot.pending));
  unsubscribe();
});
