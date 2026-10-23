import { test } from 'node:test';
import assert from 'node:assert/strict';
import { claimAudioFocus, closeAudioFocusChannelForTests, hasAudioFocus } from '../src/lib/player/audioFocus.ts';

test('new local audio owner pauses the previous owner and stale releases are harmless', async () => {
  const oldWindow = globalThis.window;
  const oldNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  globalThis.window = {};
  let held = false;
  Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { locks: { async request(_name, _options, callback) {
    if (held) return callback(null);
    held = true;
    try { return await callback({}); }
    finally { held = false; }
  } } } });
  closeAudioFocusChannelForTests();
  try {
    const losses = [];
    const releaseFirst = await claimAudioFocus('score-player', (reason) => losses.push(reason));
    assert.equal(hasAudioFocus('score-player'), true);
    const releaseSecond = await claimAudioFocus('audition', (reason) => losses.push(reason));
    assert.deepEqual(losses, ['superseded']);
    assert.equal(hasAudioFocus('audition'), true);
    releaseFirst();
    assert.equal(hasAudioFocus('audition'), true);
    releaseSecond();
    assert.equal(hasAudioFocus('audition'), false);
    releaseSecond();
  } finally {
    closeAudioFocusChannelForTests();
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
    if (oldNavigator) Object.defineProperty(globalThis, 'navigator', oldNavigator);
    else delete globalThis.navigator;
  }
});

test('a claim waits for the real lock handover before resolving', async () => {
  const oldWindow = globalThis.window;
  const oldNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  globalThis.window = {};
  let held = true;
  const queued = [];
  const pump = () => {
    if (held || queued.length === 0) return;
    held = true;
    const next = queued.shift();
    void Promise.resolve(next.callback({})).finally(() => { held = false; pump(); });
  };
  Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { locks: { request(_name, options, callback) {
    return new Promise((resolve, reject) => {
      const entry = { callback, resolve, reject };
      if (options.signal?.aborted) reject(options.signal.reason);
      else {
        options.signal?.addEventListener('abort', () => reject(options.signal.reason), { once: true });
        queued.push(entry);
        pump();
      }
    });
  } } } });
  closeAudioFocusChannelForTests();
  try {
    let resolved = false;
    const pending = claimAudioFocus('handover', () => {}).then((release) => { resolved = true; return release; });
    await Promise.resolve();
    assert.equal(resolved, false);
    held = false;
    pump();
    const release = await pending;
    assert.equal(hasAudioFocus('handover'), true);
    release();
  } finally {
    closeAudioFocusChannelForTests();
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
    if (oldNavigator) Object.defineProperty(globalThis, 'navigator', oldNavigator);
    else delete globalThis.navigator;
  }
});

test('a remote claim invalidates a locally queued claim', async () => {
  const oldWindow = globalThis.window;
  const oldNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  const oldBroadcastChannel = globalThis.BroadcastChannel;
  const listeners = new Set();
  class FakeBroadcastChannel {
    addEventListener(_type, listener) { listeners.add(listener); }
    postMessage() {}
    close() {}
  }
  globalThis.window = {};
  globalThis.BroadcastChannel = FakeBroadcastChannel;
  let held = true;
  const queued = [];
  Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { locks: { request(_name, options, callback) {
    return new Promise((resolve, reject) => {
      const entry = { callback, resolve, reject };
      options.signal?.addEventListener('abort', () => reject(options.signal.reason), { once: true });
      queued.push(entry);
      if (!held) {
        const next = queued.shift();
        void Promise.resolve(next.callback({})).then(resolve, reject);
      }
    });
  } } } });
  closeAudioFocusChannelForTests();
  try {
    const pending = claimAudioFocus('local-pending', () => {});
    await Promise.resolve();
    for (const listener of listeners) listener({ data: { ownerId: 'remote', kind: 'claim', tabId: 'other-tab' } });
    held = false;
    const next = queued.shift();
    void Promise.resolve(next.callback({})).then(next.resolve, next.reject);
    await assert.rejects(pending, /已被更新/);
  } finally {
    closeAudioFocusChannelForTests();
    listeners.clear();
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
    if (oldNavigator) Object.defineProperty(globalThis, 'navigator', oldNavigator);
    else delete globalThis.navigator;
    if (oldBroadcastChannel === undefined) delete globalThis.BroadcastChannel;
    else globalThis.BroadcastChannel = oldBroadcastChannel;
  }
});
