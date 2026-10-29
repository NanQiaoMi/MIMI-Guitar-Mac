import assert from 'node:assert/strict';
import test from 'node:test';
import { createPracticeLeaveGuardCoordinator } from '../src/lib/practice/practiceLeaveGuard.ts';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

test('cleanup only unregisters the guard instance that created it', async () => {
  const coordinator = createPracticeLeaveGuardCoordinator();
  let oldCalls = 0;
  let currentCalls = 0;
  const releaseOld = coordinator.register(async () => { oldCalls++; return true; });
  const releaseCurrent = coordinator.register(async () => { currentCalls++; return true; });

  releaseOld();
  const committed = [];
  assert.equal(await coordinator.requestSelection(() => committed.push('next')), true);
  assert.deepEqual(committed, ['next']);
  assert.equal(oldCalls, 0);
  assert.equal(currentCalls, 1);

  releaseCurrent();
  assert.equal(await coordinator.requestSelection(() => committed.push('without-player')), true);
  assert.deepEqual(committed, ['next', 'without-player']);
  assert.equal(currentCalls, 1);
});

test('a guard result from a replaced player cannot authorize a selection', async () => {
  const coordinator = createPracticeLeaveGuardCoordinator();
  const oldLeave = deferred();
  const oldRelease = coordinator.register(() => oldLeave.promise);
  const committed = [];
  const request = coordinator.requestSelection(() => committed.push('stale-player'));

  coordinator.register(async () => true);
  oldLeave.resolve(true);

  assert.equal(await request, false);
  assert.deepEqual(committed, []);
  oldRelease();
  assert.equal(await coordinator.requestSelection(() => committed.push('current-player')), true);
  assert.deepEqual(committed, ['current-player']);
});

test('rapid selection requests share the guard and only the latest choice commits', async () => {
  const coordinator = createPracticeLeaveGuardCoordinator();
  const leave = deferred();
  let guardCalls = 0;
  coordinator.register(() => { guardCalls++; return leave.promise; });
  const committed = [];

  const first = coordinator.requestSelection(() => committed.push('first'));
  const latest = coordinator.requestSelection(() => committed.push('latest'));
  assert.equal(guardCalls, 0, 'guard starts on the next microtask');
  await Promise.resolve();
  assert.equal(guardCalls, 1);

  leave.resolve(true);
  assert.equal(await first, false);
  assert.equal(await latest, true);
  assert.deepEqual(committed, ['latest']);
});

test('rejected, throwing, or invalidated guards never commit an action', async () => {
  const coordinator = createPracticeLeaveGuardCoordinator();
  let committed = 0;
  coordinator.register(async () => false);
  assert.equal(await coordinator.requestSelection(() => { committed++; }), false);
  assert.equal(committed, 0);

  const waiting = deferred();
  coordinator.register(() => waiting.promise);
  const request = coordinator.requestSelection(() => { committed++; });
  coordinator.invalidate();
  waiting.resolve(true);
  assert.equal(await request, false);
  assert.equal(committed, 0);

  coordinator.register(async () => { throw new Error('save failed'); });
  assert.equal(await coordinator.requestSelection(() => { committed++; }), false);
  assert.equal(committed, 0);
});

test('a denied leave can be retried and a later approved selection commits', async () => {
  const coordinator = createPracticeLeaveGuardCoordinator();
  let attempts = 0;
  coordinator.register(async () => ++attempts > 1);
  const committed = [];

  assert.equal(await coordinator.requestSelection(() => committed.push('first attempt')), false);
  assert.deepEqual(committed, []);
  assert.equal(await coordinator.requestSelection(() => committed.push('retry')), true);
  assert.deepEqual(committed, ['retry']);
  assert.equal(attempts, 2);
});

test('invalidating an obsolete selection lets a fresh restore request commit', async () => {
  const coordinator = createPracticeLeaveGuardCoordinator();
  const obsoleteLeave = deferred();
  let guardCalls = 0;
  coordinator.register(() => ++guardCalls === 1 ? obsoleteLeave.promise : Promise.resolve(true));
  const committed = [];

  const obsolete = coordinator.requestSelection(() => committed.push('obsolete target'));
  coordinator.invalidate();
  obsoleteLeave.resolve(true);

  assert.equal(await obsolete, false);
  assert.deepEqual(committed, []);
  assert.equal(await coordinator.requestSelection(() => committed.push('restored current target')), true);
  assert.deepEqual(committed, ['restored current target']);
  assert.equal(guardCalls, 2);
});
