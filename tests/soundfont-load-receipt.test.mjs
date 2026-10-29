import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isSoundfontReceiptPoisoned,
  loadSoundfontWithReceipt,
} from '../src/lib/player/soundfontLoadReceipt.ts';

function createEvent() {
  const listeners = new Set();
  return {
    on(listener) { listeners.add(listener); },
    off(listener) { listeners.delete(listener); },
    emit(value) { for (const listener of [...listeners]) listener(value); },
    get size() { return listeners.size; },
  };
}

function createApi({ accept = true } = {}) {
  const soundFontLoaded = createEvent();
  const soundFontLoadFailed = createEvent();
  const calls = [];
  return {
    soundFontLoaded,
    soundFontLoadFailed,
    calls,
    loadSoundFont(bytes, append) {
      calls.push({ bytes, append });
      return typeof accept === 'function' ? accept(bytes, append) : accept;
    },
  };
}

async function flushMicrotasks() {
  for (let index = 0; index < 12; index++) await Promise.resolve();
}

async function withFakeClock(run) {
  const realSetTimeout = globalThis.setTimeout;
  const realClearTimeout = globalThis.clearTimeout;
  let nextId = 1;
  let now = 0;
  const timers = new Map();
  globalThis.setTimeout = (callback, delay = 0, ...args) => {
    const id = nextId++;
    timers.set(id, { at: now + Math.max(0, Number(delay) || 0), callback: () => callback(...args) });
    return id;
  };
  globalThis.clearTimeout = (id) => { timers.delete(id); };
  const tick = async (duration) => {
    const target = now + duration;
    while (true) {
      let dueId;
      let dueTimer;
      for (const [id, timer] of timers) {
        if (timer.at <= target && (!dueTimer || timer.at < dueTimer.at)) {
          dueId = id;
          dueTimer = timer;
        }
      }
      if (!dueTimer) break;
      now = dueTimer.at;
      timers.delete(dueId);
      dueTimer.callback();
      await flushMicrotasks();
    }
    now = target;
    await flushMicrotasks();
  };
  try {
    await run({ tick, pendingTimers: () => timers.size });
  } finally {
    globalThis.setTimeout = realSetTimeout;
    globalThis.clearTimeout = realClearTimeout;
  }
}

test('one API serializes worker requests and each request waits for its own loaded receipt', async () => {
  const api = createApi();
  const bytes = new Uint8Array([1]);
  const first = loadSoundfontWithReceipt(api, bytes, false);
  const second = loadSoundfontWithReceipt(api, bytes, true);
  await flushMicrotasks();
  assert.equal(api.calls.length, 1);

  api.soundFontLoaded.emit();
  await flushMicrotasks();
  assert.deepEqual(await first, { status: 'loaded' });
  assert.equal(api.calls.length, 2);
  let secondSettled = false;
  void second.then(() => { secondSettled = true; });
  await flushMicrotasks();
  assert.equal(secondSettled, false);

  api.soundFontLoaded.emit();
  assert.deepEqual(await second, { status: 'loaded' });
  assert.equal(api.soundFontLoaded.size, 0);
  assert.equal(api.soundFontLoadFailed.size, 0);
});

test('caller abort resolves immediately but an in-flight receipt keeps the API barrier', async () => {
  const api = createApi();
  const controller = new AbortController();
  const bytes = new Uint8Array([2]);
  const first = loadSoundfontWithReceipt(api, bytes, false, { signal: controller.signal });
  await flushMicrotasks();
  assert.equal(api.calls.length, 1);

  controller.abort();
  assert.deepEqual(await first, { status: 'cancelled' });
  assert.equal(api.soundFontLoaded.size, 1, 'the worker receipt listener must survive caller cancellation');
  const second = loadSoundfontWithReceipt(api, bytes, true);
  await flushMicrotasks();
  assert.equal(api.calls.length, 1, 'second request must wait for the first worker receipt');

  api.soundFontLoaded.emit();
  await flushMicrotasks();
  assert.equal(api.calls.length, 2, 'the old acknowledgement only unlocks dispatch of the second request');
  let secondSettled = false;
  void second.then(() => { secondSettled = true; });
  await flushMicrotasks();
  assert.equal(secondSettled, false, 'the old acknowledgement must not settle the second request');

  api.soundFontLoaded.emit();
  assert.deepEqual(await second, { status: 'loaded' });
  assert.equal(api.soundFontLoaded.size, 0);
  assert.equal(api.soundFontLoadFailed.size, 0);
});

test('timeout poisons one API and a late acknowledgement cannot release a later request', async () => {
  await withFakeClock(async ({ tick, pendingTimers }) => {
    const api = createApi();
    const bytes = new Uint8Array([3]);
    const first = loadSoundfontWithReceipt(api, bytes, false, { timeoutMs: 20 });
    await flushMicrotasks();
    assert.equal(api.calls.length, 1);
    assert.equal(pendingTimers(), 1);

    await tick(20);
    const firstReceipt = await first;
    assert.equal(firstReceipt.status, 'timeout');
    assert.match(firstReceipt.error.message, /timed out/);
    assert.equal(isSoundfontReceiptPoisoned(api), true);
    assert.equal(api.soundFontLoaded.size, 0);
    assert.equal(pendingTimers(), 0);

    const second = await loadSoundfontWithReceipt(api, bytes, true, { timeoutMs: 20 });
    assert.equal(second.status, 'failed');
    assert.match(second.error.message, /poisoned/);
    api.soundFontLoaded.emit();
    await flushMicrotasks();
    assert.equal(api.calls.length, 1, 'poisoned API must never dispatch another request');
  });
});

test('a queued request cancelled before dispatch is skipped without poisoning the API', async () => {
  const api = createApi();
  const bytes = new Uint8Array([4]);
  const first = loadSoundfontWithReceipt(api, bytes, false);
  await flushMicrotasks();
  const controller = new AbortController();
  const queued = loadSoundfontWithReceipt(api, bytes, true, { signal: controller.signal });
  controller.abort();
  assert.deepEqual(await queued, { status: 'cancelled' });
  api.soundFontLoaded.emit();
  assert.deepEqual(await first, { status: 'loaded' });
  await flushMicrotasks();
  assert.equal(api.calls.length, 1);
  const next = loadSoundfontWithReceipt(api, bytes, true);
  await flushMicrotasks();
  assert.equal(api.calls.length, 2);
  api.soundFontLoaded.emit();
  assert.deepEqual(await next, { status: 'loaded' });
});

test('a failed worker event poisons its API while a separate API loads independently', async () => {
  const failedApi = createApi();
  const independentApi = createApi();
  assert.equal(isSoundfontReceiptPoisoned(failedApi), false);
  const bytes = new Uint8Array([5]);
  const failedRequest = loadSoundfontWithReceipt(failedApi, bytes, false);
  const independentRequest = loadSoundfontWithReceipt(independentApi, bytes, false);
  await flushMicrotasks();
  assert.equal(failedApi.calls.length, 1);
  assert.equal(independentApi.calls.length, 1);

  const expectedError = new Error('worker decode failed');
  failedApi.soundFontLoadFailed.emit(expectedError);
  assert.deepEqual(await failedRequest, { status: 'failed', error: expectedError });
  assert.equal(isSoundfontReceiptPoisoned(failedApi), true);
  assert.equal(isSoundfontReceiptPoisoned(independentApi), false);
  const poisoned = await loadSoundfontWithReceipt(failedApi, bytes, true);
  assert.equal(poisoned.status, 'failed');
  assert.match(poisoned.error.message, /poisoned/);
  assert.equal(failedApi.calls.length, 1);

  independentApi.soundFontLoaded.emit();
  assert.deepEqual(await independentRequest, { status: 'loaded' });
});

test('loadSoundFont false and synchronous exceptions fail and poison the API', async () => {
  const rejectedApi = createApi({ accept: false });
  const rejected = await loadSoundfontWithReceipt(rejectedApi, new Uint8Array([6]), false);
  assert.equal(rejected.status, 'failed');
  assert.match(rejected.error.message, /did not accept/);
  assert.equal(rejectedApi.soundFontLoaded.size, 0);
  assert.equal(rejectedApi.soundFontLoadFailed.size, 0);
  assert.equal((await loadSoundfontWithReceipt(rejectedApi, new Uint8Array([6]), true)).status, 'failed');

  const throwingApi = createApi({ accept() { throw new Error('dispatch throw'); } });
  const thrown = await loadSoundfontWithReceipt(throwingApi, new Uint8Array([7]), false);
  assert.equal(thrown.status, 'failed');
  assert.equal(thrown.error.message, 'dispatch throw');
  assert.equal(throwingApi.soundFontLoaded.size, 0);
  assert.equal(throwingApi.soundFontLoadFailed.size, 0);
});

test('already-aborted and invalid input requests do not touch the API', async () => {
  const api = createApi();
  const controller = new AbortController();
  controller.abort();
  assert.deepEqual(await loadSoundfontWithReceipt(api, new Uint8Array([8]), false, { signal: controller.signal }), { status: 'cancelled' });
  assert.equal((await loadSoundfontWithReceipt(api, new Uint8Array(), false)).status, 'failed');
  assert.equal(api.calls.length, 0);
});
