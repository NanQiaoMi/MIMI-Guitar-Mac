import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAudioContextRegistry } from '../src/lib/audioUnlocker.ts';

function deferred() {
  let resolve;
  const promise = new Promise((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

function fakeContext({ state = 'suspended', resume = () => Promise.resolve() } = {}) {
  return {
    state,
    resumeCalls: 0,
    resume() {
      this.resumeCalls++;
      return resume.call(this);
    },
  };
}

function nextTurn() {
  return new Promise((resolve) => setImmediate(resolve));
}

test('a synchronous reentrant unlock shares the in-flight resume', () => {
  const registry = createAudioContextRegistry();
  const pending = deferred();
  let ctx;
  ctx = fakeContext({
    resume() {
      registry.unlock(ctx);
      return pending.promise;
    },
  });

  registry.unlock(ctx);

  assert.equal(ctx.resumeCalls, 1);
  pending.resolve();
  return nextTurn();
});

test('pending resumes are deduplicated per context while other contexts can resume', async () => {
  const registry = createAudioContextRegistry();
  const firstPending = deferred();
  const secondPending = deferred();
  const first = fakeContext({ resume: () => firstPending.promise });
  const second = fakeContext({ resume: () => secondPending.promise });
  registry.register(first);
  registry.register(second);

  registry.unlock(first);
  registry.unlock(first);
  registry.unlock(second);
  registry.unlock(second);

  assert.equal(first.resumeCalls, 1);
  assert.equal(second.resumeCalls, 1);
  firstPending.resolve();
  secondPending.resolve();
  await nextTurn();
});

test('register, unlock, and unlockAll do not repeat a pending resume', () => {
  const registry = createAudioContextRegistry();
  const pending = deferred();
  const ctx = fakeContext({ resume: () => pending.promise });

  registry.register(ctx);
  registry.unlock(ctx);
  registry.register(ctx);
  registry.unlock(ctx);
  registry.unlockAll();
  registry.unlockAll();

  assert.equal(ctx.resumeCalls, 1);
  pending.resolve();
  return nextTurn();
});

test('unlockAll resumes four independent suspended contexts', () => {
  const registry = createAudioContextRegistry();
  const pending = Array.from({ length: 4 }, () => deferred());
  const contexts = pending.map((item) => fakeContext({ resume: () => item.promise }));
  contexts.forEach((ctx) => registry.register(ctx));

  registry.unlockAll();

  assert.deepEqual(contexts.map((ctx) => ctx.resumeCalls), [1, 1, 1, 1]);
  pending.forEach((item) => item.resolve());
  return nextTurn();
});

test('synchronous throws and rejected resumes are contained and can be retried', async () => {
  const registry = createAudioContextRegistry();
  let syncAttempts = 0;
  const syncThrow = fakeContext({
    resume() {
      syncAttempts++;
      if (syncAttempts === 1) throw new Error('blocked synchronously');
      return Promise.resolve();
    },
  });
  assert.doesNotThrow(() => registry.unlock(syncThrow));
  assert.doesNotThrow(() => registry.unlock(syncThrow));
  assert.equal(syncThrow.resumeCalls, 2);

  let asyncAttempts = 0;
  const rejected = fakeContext({
    resume() {
      asyncAttempts++;
      return asyncAttempts === 1
        ? Promise.reject(new Error('blocked asynchronously'))
        : Promise.resolve();
    },
  });
  assert.doesNotThrow(() => registry.unlock(rejected));
  await nextTurn();
  assert.doesNotThrow(() => registry.unlock(rejected));
  assert.equal(rejected.resumeCalls, 2);
  await nextTurn();
});

test('running and closed contexts are not resumed', () => {
  const registry = createAudioContextRegistry();
  const running = fakeContext({ state: 'running' });
  const closed = fakeContext({ state: 'closed' });
  registry.register(running);
  registry.register(closed);

  registry.unlock(running);
  registry.unlock(closed);
  registry.unlockAll();

  assert.equal(running.resumeCalls, 0);
  assert.equal(closed.resumeCalls, 0);
});

test('unregistered contexts are not resumed by unlockAll', () => {
  const registry = createAudioContextRegistry();
  const ctx = fakeContext();
  const unregister = registry.register(ctx);
  unregister();

  registry.unlockAll();

  assert.equal(ctx.resumeCalls, 0);
});
