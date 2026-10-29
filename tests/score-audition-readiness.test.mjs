import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createSerialTaskQueue,
  createScorePlaybackReadyWaiter,
  startAlphaTabPlayback,
} from '../src/lib/player/scoreAuditionReadiness.ts';

function createEmitter() {
  const handlers = new Set();
  return {
    handlers,
    on(handler) { handlers.add(handler); },
    off(handler) { handlers.delete(handler); },
    emit(value) { for (const handler of [...handlers]) handler(value); },
  };
}

function createApi({ ready = false, playerState = 2, play = () => true } = {}) {
  return {
    scoreLoaded: createEmitter(),
    playerReady: createEmitter(),
    playerStateChanged: createEmitter(),
    isReadyForPlayback: ready,
    playerState,
    play,
  };
}

test('a cancelled render keeps its queue slot until the old playerReady boundary, then latest work proceeds', async () => {
  const queue = createSerialTaskQueue();
  let releaseOldRender;
  const oldReady = new Promise((resolve) => { releaseOldRender = resolve; });
  const order = [];

  const oldRender = queue.run(async () => {
    order.push('old-render-start');
    await oldReady;
    order.push('old-player-ready');
  });
  const latestRender = queue.run(() => { order.push('latest-render'); });

  await Promise.resolve();
  assert.deepEqual(order, ['old-render-start']);
  releaseOldRender();
  await Promise.all([oldRender, latestRender]);
  assert.deepEqual(order, ['old-render-start', 'old-player-ready', 'latest-render']);
});

test('a failed render does not permanently block the next score setup', async () => {
  const queue = createSerialTaskQueue();
  await assert.rejects(queue.run(() => { throw new Error('render failed'); }), /render failed/);
  assert.equal(await queue.run(() => 'recovered'), 'recovered');
});

test('score readiness needs this render and the following playerReady event, not the prior song ready flag', async () => {
  const api = createApi({ ready: true });
  const waiter = createScorePlaybackReadyWaiter(api, { timeoutMs: 250 });
  let resolved = false;
  waiter.promise.then(() => { resolved = true; });

  // A delayed ready event from a previous MIDI load must not release this song.
  api.playerReady.emit();
  await Promise.resolve();
  assert.equal(resolved, false);

  api.scoreLoaded.emit({ title: 'new song' });
  await Promise.resolve();
  assert.equal(resolved, false);

  api.playerReady.emit();
  await waiter.promise;
  assert.equal(resolved, true);
  assert.equal(api.scoreLoaded.handlers.size, 0);
  assert.equal(api.playerReady.handlers.size, 0);
});

test('score readiness timeout and explicit cancellation remove both listeners', async (t) => {
  await t.test('timeout', async () => {
    const api = createApi();
    const waiter = createScorePlaybackReadyWaiter(api, { timeoutMs: 20 });
    await assert.rejects(waiter.promise, { name: 'ScorePlaybackReadyTimeoutError' });
    assert.equal(api.scoreLoaded.handlers.size, 0);
    assert.equal(api.playerReady.handlers.size, 0);
  });

  await t.test('cancel', async () => {
    const api = createApi();
    const waiter = createScorePlaybackReadyWaiter(api, { timeoutMs: 250 });
    waiter.cancel(new Error('render rejected'));
    await assert.rejects(waiter.promise, /render rejected/);
    assert.equal(api.scoreLoaded.handlers.size, 0);
    assert.equal(api.playerReady.handlers.size, 0);
  });
});

test('play resolves only after a playerStateChanged event confirms actual Playing', async () => {
  let api;
  api = createApi({
    ready: true,
    play: () => {
      assert.equal(api.playerStateChanged.handlers.size, 1, 'listener is installed before api.play()');
      return true;
    },
  });

  let resolved = false;
  const pending = startAlphaTabPlayback(api, { timeoutMs: 250 }).then(() => { resolved = true; });
  await Promise.resolve();
  assert.equal(resolved, false);
  api.playerState = 1;
  api.playerStateChanged.emit({ state: 1 });
  await pending;
  assert.equal(resolved, true);
  assert.equal(api.playerStateChanged.handlers.size, 0);
});

test('play rejection, start timeout, and abort all clean the pending state listener', async (t) => {
  await t.test('rejected start', async () => {
    const api = createApi({ ready: true, play: () => false });
    await assert.rejects(startAlphaTabPlayback(api), /未能开始播放/);
    assert.equal(api.playerStateChanged.handlers.size, 0);
  });

  await t.test('timeout', async () => {
    const api = createApi({ ready: true });
    await assert.rejects(startAlphaTabPlayback(api, { timeoutMs: 20 }), {
      name: 'PlaybackStartTimeoutError',
    });
    assert.equal(api.playerStateChanged.handlers.size, 0);
  });

  await t.test('abort', async () => {
    const api = createApi({ ready: true });
    const controller = new AbortController();
    const pending = startAlphaTabPlayback(api, { signal: controller.signal, timeoutMs: 250 });
    controller.abort();
    await assert.rejects(pending, { name: 'AbortError' });
    assert.equal(api.playerStateChanged.handlers.size, 0);
  });
});
