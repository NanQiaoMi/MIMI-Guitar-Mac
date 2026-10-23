import test from 'node:test';
import assert from 'node:assert/strict';
import { createRetryableLazyLoader } from '../src/lib/player/retryableLazyLoader.ts';
import { createScoreAuditionFacade } from '../src/lib/scoreAuditionFacade.ts';
import { startAfterAudioFocus } from '../src/lib/player/startAfterAudioFocus.ts';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function createRuntime() {
  let state = {
    currentTabId: null, currentTab: null, isPlaying: false, isLoading: false,
    currentTime: 0, endTime: 0, progress: 0, activeNotes: [], error: null,
  };
  const listeners = new Set();
  const calls = { plays: [], prewarms: 0, stops: 0, pauses: 0, resumes: 0, seeks: [] };
  const publish = (next) => {
    state = { ...state, ...next };
    for (const listener of listeners) listener({ ...state, activeNotes: [...state.activeNotes] });
  };
  return {
    calls,
    getState: () => ({ ...state, activeNotes: [...state.activeNotes] }),
    subscribe(listener) {
      listeners.add(listener);
      listener(this.getState());
      return () => listeners.delete(listener);
    },
    async playTab(tab) {
      calls.plays.push(tab.id);
      publish({ currentTabId: tab.id, currentTab: tab, isLoading: true, isPlaying: false, error: null });
      publish({ isLoading: false, isPlaying: true });
    },
    async togglePlayTab(tab) { await this.playTab(tab); },
    pause() { calls.pauses++; publish({ isLoading: false, isPlaying: false }); },
    async resume() { calls.resumes++; publish({ isLoading: false, isPlaying: true }); },
    stop() { calls.stops++; publish({ currentTabId: null, currentTab: null, isLoading: false, isPlaying: false }); },
    seek(ratio) { calls.seeks.push(ratio); },
    seekBySeconds() {},
    async prewarm() { calls.prewarms++; },
    publish,
  };
}

function createFakeTimers() {
  let nextId = 1;
  const scheduled = new Map();
  return {
    scheduled,
    setTimeout(callback, delay) {
      const id = nextId++;
      scheduled.set(id, { callback, delay, cancelled: false });
      return id;
    },
    clearTimeout(id) {
      const timer = scheduled.get(id);
      if (timer) timer.cancelled = true;
    },
    fire(id, { includeCancelled = false } = {}) {
      const timer = scheduled.get(id);
      if (!timer || (timer.cancelled && !includeCancelled)) return;
      timer.callback();
    },
  };
}

test('lazy loader shares concurrent imports and retries after an import failure', async () => {
  const gate = deferred();
  let attempts = 0;
  const runtime = {};
  const load = createRetryableLazyLoader(() => {
    attempts++;
    if (attempts === 1) return Promise.reject(new Error('chunk unavailable'));
    if (attempts === 2) return gate.promise;
    return Promise.resolve(runtime);
  });

  await assert.rejects(load(), /chunk unavailable/);
  const first = load();
  const concurrent = load();
  await Promise.resolve();
  assert.equal(attempts, 2);
  gate.resolve(runtime);
  assert.equal(await first, runtime);
  assert.equal(await concurrent, runtime);
  assert.equal(await load(), runtime);
  assert.equal(attempts, 2);
});

test('constructing and observing the facade stays lightweight until explicit prewarm or audition', async () => {
  let loads = 0;
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(async () => { loads++; return runtime; }, null);
  facade.getState();
  const unsubscribe = facade.subscribe(() => {});
  assert.equal(loads, 0);
  await facade.prewarm();
  assert.equal(loads, 1);
  assert.equal(runtime.calls.prewarms, 1);
  unsubscribe();
  facade.dispose();
});

test('concurrent first clicks share import and only the latest selected score starts', async () => {
  const gate = deferred();
  const runtime = createRuntime();
  let loads = 0;
  const facade = createScoreAuditionFacade(() => { loads++; return gate.promise; }, null);
  const first = facade.playTab({ id: 'first' });
  const latest = facade.playTab({ id: 'latest' });
  gate.resolve(runtime);
  await Promise.all([first, latest]);
  assert.equal(loads, 1);
  assert.deepEqual(runtime.calls.plays, ['latest']);
  assert.equal(facade.getState().currentTabId, 'latest');
  facade.dispose();
});

test('pause, stop, pagehide, and dispose cancel an audition waiting on the lazy import', async (t) => {
  for (const action of ['pause', 'stop', 'pagehide', 'dispose']) {
    await t.test(action, async () => {
      const gate = deferred();
      const target = new EventTarget();
      const runtime = createRuntime();
      const facade = createScoreAuditionFacade(() => gate.promise, target);
      const pending = facade.playTab({ id: 'late' });
      if (action === 'pagehide') target.dispatchEvent(new Event('pagehide'));
      else facade[action]();
      gate.resolve(runtime);
      await pending;
      assert.deepEqual(runtime.calls.plays, []);
      assert.equal(facade.getState().isPlaying, false);
      if (action === 'stop') assert.equal(facade.getState().currentTabId, null);
      if (action === 'dispose') assert.equal(runtime.calls.stops, 0);
    });
  }
});

test('runtime import errors reach state and a later explicit audition retries the loader', async () => {
  let attempts = 0;
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(async () => {
    attempts++;
    if (attempts === 1) throw new TypeError('AlphaTab chunk fetch failed');
    return runtime;
  }, null);

  await facade.playTab({ id: 'retry-me' });
  assert.equal(facade.getState().error, 'AlphaTab chunk fetch failed');
  assert.equal(facade.getState().isLoading, false);
  await facade.playTab({ id: 'retry-me' });
  assert.equal(attempts, 2);
  assert.deepEqual(runtime.calls.plays, ['retry-me']);
  assert.equal(facade.getState().isPlaying, true);
  facade.dispose();
});

test('disposing an initialized facade stops its runtime before dropping listeners', async () => {
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(async () => runtime, null);
  await facade.playTab({ id: 'playing' });
  facade.dispose();
  assert.equal(runtime.calls.stops, 1);
  assert.equal(facade.getState().isPlaying, false);
  assert.equal(facade.getState().currentTabId, null);
});

test('a delayed audio-focus claim cannot start after pause invalidates the resume intent', async () => {
  const claim = deferred();
  let generation = 3;
  let starts = 0;
  let releases = 0;
  const requestedGeneration = generation;
  const resume = startAfterAudioFocus({
    claim: () => claim.promise,
    isCurrent: () => generation === requestedGeneration,
    start: () => { starts++; return true; },
    onStarted() { assert.fail('cancelled resume must not retain audio focus'); },
  });

  generation++;
  claim.resolve(() => { releases++; });
  assert.equal(await resume, false);
  assert.equal(starts, 0);
  assert.equal(releases, 1);
});

test('30-second preview timing starts after playback begins, then resets and pauses', async () => {
  const loading = deferred();
  const timers = createFakeTimers();
  const runtime = createRuntime();
  runtime.playTab = async (tab) => {
    runtime.calls.plays.push(tab.id);
    runtime.publish({ currentTabId: tab.id, currentTab: tab, isLoading: true, isPlaying: false });
    await loading.promise;
    runtime.publish({ isLoading: false, isPlaying: true });
  };
  const facade = createScoreAuditionFacade(async () => runtime, null, timers);
  const handle = facade.previewTab({ id: 'short-preview' }, 30);

  for (let i = 0; i < 5 && runtime.calls.plays.length === 0; i++) await Promise.resolve();
  assert.deepEqual([...timers.scheduled.keys()], []);
  assert.equal(facade.getState().isLoading, true);

  loading.resolve();
  assert.deepEqual(await handle.promise, { status: 'started' });
  const [timerId] = timers.scheduled.keys();
  assert.equal(timers.scheduled.get(timerId).delay, 30000);
  assert.equal(runtime.calls.pauses, 0);

  timers.fire(timerId);
  assert.equal(runtime.calls.pauses, 1);
  assert.deepEqual(runtime.calls.seeks, [0]);
  assert.equal(facade.getState().isPlaying, false);
  facade.dispose();
});

test('preview defaults to 30 seconds, supports 60 seconds and bounds invalid or excessive durations', async () => {
  for (const [requested, expectedMs] of [
    [undefined, 30000], [60, 60000], [120, 60000], [0, 30000], [-1, 30000],
    [NaN, 30000], [Infinity, 30000], ['60', 30000], [0.1, 1000],
  ]) {
    const timers = createFakeTimers();
    const runtime = createRuntime();
    const facade = createScoreAuditionFacade(async () => runtime, null, timers);
    const preview = facade.previewTab({ id: 'duration-check' }, requested);
    assert.deepEqual(await preview.promise, { status: 'started' });
    const [timer] = timers.scheduled.values();
    assert.equal(timer.delay, expectedMs, `requested ${String(requested)}`);
    facade.dispose();
  }
});

test('natural score completion cancels its preview timer and cannot stop a replay', async () => {
  const timers = createFakeTimers();
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(async () => runtime, null, timers);
  await facade.previewTab({ id: 'short-score' }).promise;
  const [oldTimerId] = timers.scheduled.keys();

  runtime.publish({ isPlaying: false, isLoading: false, currentTime: 0 });
  assert.equal(timers.scheduled.get(oldTimerId).cancelled, true);
  await facade.playTab({ id: 'short-score' });
  timers.fire(oldTimerId, { includeCancelled: true });
  assert.equal(runtime.calls.pauses, 0);
  assert.equal(facade.getState().isPlaying, true);
  facade.dispose();
});

test('changing from a 30-second preview to 60 seconds invalidates the previous handle and timer', async () => {
  const timers = createFakeTimers();
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(async () => runtime, null, timers);
  const first = facade.previewTab({ id: 'one-song' }, 30);
  await first.promise;
  const [oldTimerId] = timers.scheduled.keys();
  first.cancel();
  const second = facade.previewTab({ id: 'one-song' }, 60);
  await second.promise;
  const latestTimer = [...timers.scheduled.values()].at(-1);
  assert.equal(latestTimer.delay, 60000);
  const pausedBefore = runtime.calls.pauses;
  timers.fire(oldTimerId, { includeCancelled: true });
  first.cancel();
  assert.equal(runtime.calls.pauses, pausedBefore);
  assert.equal(facade.getState().isPlaying, true);
  second.cancel();
  assert.equal(facade.getState().isPlaying, false);
  facade.dispose();
});

test('a stale preview timer and handle cannot pause a later same-ID full playback', async () => {
  const timers = createFakeTimers();
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(async () => runtime, null, timers);
  const preview = facade.previewTab({ id: 'same-score' }, 5);
  assert.deepEqual(await preview.promise, { status: 'started' });
  const [oldTimerId] = timers.scheduled.keys();

  await facade.playTab({ id: 'same-score', title: 'replayed as full score' });
  assert.equal(facade.getState().isPlaying, true);
  timers.fire(oldTimerId, { includeCancelled: true });
  preview.cancel();

  assert.equal(runtime.calls.pauses, 0);
  assert.equal(facade.getState().isPlaying, true);
  assert.deepEqual(runtime.calls.plays, ['same-score', 'same-score']);
  facade.dispose();
});

test('cancelling a preview while the lazy runtime is pending resolves immediately and never starts it', async () => {
  const load = deferred();
  const runtime = createRuntime();
  const facade = createScoreAuditionFacade(() => load.promise, null, createFakeTimers());
  const preview = facade.previewTab({ id: 'cancel-before-load' });

  preview.cancel();
  assert.deepEqual(await preview.promise, { status: 'cancelled' });
  load.resolve(runtime);
  await Promise.resolve();
  await Promise.resolve();
  assert.deepEqual(runtime.calls.plays, []);
  assert.equal(facade.getState().isPlaying, false);
  facade.dispose();
});

test('preview failures settle with failed and publish the runtime error without scheduling a timer', async () => {
  const timers = createFakeTimers();
  const runtime = createRuntime();
  runtime.playTab = async (tab) => {
    runtime.publish({ currentTabId: tab.id, currentTab: tab, isLoading: false, isPlaying: false, error: '资源不是有效乐谱' });
  };
  const facade = createScoreAuditionFacade(async () => runtime, null, timers);
  const preview = facade.previewTab({ id: 'bad-score' });

  assert.deepEqual(await preview.promise, { status: 'failed', error: '资源不是有效乐谱' });
  assert.equal(facade.getState().error, '资源不是有效乐谱');
  assert.equal(timers.scheduled.size, 0);
  facade.dispose();
});
