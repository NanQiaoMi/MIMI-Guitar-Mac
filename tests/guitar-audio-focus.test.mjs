import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { claimAudioFocus, closeAudioFocusChannelForTests } from '../src/lib/player/audioFocus.ts';
import { playProgramNote } from '../src/lib/guitarSound.ts';
import { StudioAudioEngine } from '../src/lib/studio/studioAudioEngine.ts';

const gmSoundfont = new Uint8Array(await readFile('public/soundfonts/sonivox.sf2'));

class FakeParam {
  value = 0;
  setValueAtTime(value) { this.value = value; }
  exponentialRampToValueAtTime(value) { this.value = value; }
}
class FakeNode {
  listeners = new Map();
  stopped = false;
  disconnected = false;
  connect() {}
  disconnect() { this.disconnected = true; }
  addEventListener(name, callback) {
    const listeners = this.listeners.get(name) ?? new Set();
    listeners.add(callback);
    this.listeners.set(name, listeners);
  }
  removeEventListener(name, callback) { this.listeners.get(name)?.delete(callback); }
  start() {}
  stop() { this.stopped = true; }
  finish() { for (const callback of this.listeners.get('ended') ?? []) callback(); }
}
class FakeAudioContext {
  static instances = [];
  state = 'running'; sampleRate = 8000; currentTime = 0; destination = {};
  sources = [];
  nodes = [];
  constructor() { FakeAudioContext.instances.push(this); }
  add(node) { this.nodes.push(node); return node; }
  createBuffer(channels, length, sampleRate) {
    const data = Array.from({ length: channels }, () => new Float32Array(length));
    return { numberOfChannels: channels, length, sampleRate, getChannelData: (channel) => data[channel] };
  }
  createBufferSource() { const n = this.add(new FakeNode()); this.sources.push(n); return n; }
  createBiquadFilter() { return this.add(Object.assign(new FakeNode(), { frequency: new FakeParam(), Q: new FakeParam(), gain: new FakeParam() })); }
  createGain() { return this.add(Object.assign(new FakeNode(), { gain: new FakeParam() })); }
  createWaveShaper() { return this.add(Object.assign(new FakeNode(), { curve: null, oversample: '' })); }
  createOscillator() { return this.add(Object.assign(new FakeNode(), { frequency: new FakeParam(), type: 'sine' })); }
  resume() { return Promise.resolve(); }
}

function installBrowser() {
  const oldWindow = globalThis.window;
  const oldFetch = globalThis.fetch;
  const oldElement = Object.getOwnPropertyDescriptor(globalThis, 'Element');
  class FakeElement {}
  FakeElement.prototype.replaceChildren = function () {};
  globalThis.Element = FakeElement;
  const oldNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  globalThis.window = { AudioContext: FakeAudioContext };
  globalThis.fetch = async (url) => {
    assert.equal(url, '/soundfonts/sonivox.sf2');
    return new Response(gmSoundfont, { status: 200 });
  };
  let held = false;
  const queue = [];
  const pump = () => {
    if (held || !queue.length) return;
    held = true;
    const item = queue.shift();
    Promise.resolve(item.callback({})).then(item.resolve, item.reject).finally(() => { held = false; pump(); });
  };
  Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { locks: { request(_name, options, callback) {
    return new Promise((resolve, reject) => {
      if (options.signal?.aborted) { reject(options.signal.reason); return; }
      options.signal?.addEventListener('abort', () => reject(options.signal.reason), { once: true });
      queue.push({ callback, resolve, reject });
      pump();
    });
  } } } });
  closeAudioFocusChannelForTests();
  return {
    async restore() {
      closeAudioFocusChannelForTests();
      if (oldWindow === undefined) delete globalThis.window; else globalThis.window = oldWindow;
      globalThis.fetch = oldFetch;
      if (oldElement) Object.defineProperty(globalThis, 'Element', oldElement); else delete globalThis.Element;
      if (oldNavigator) Object.defineProperty(globalThis, 'navigator', oldNavigator); else delete globalThis.navigator;
    },
  };
}

test('reentrant guitar one-shots share one focus lease and stop their sources on preemption', async () => {
  const browser = installBrowser();
  try {
    const first = playProgramNote(64, 25, 0.1);
    const second = playProgramNote(67, 25, 0.1);
    const startedAt = Date.now();
    while ((FakeAudioContext.instances[0]?.sources.length ?? 0) < 2 && Date.now() - startedAt < 5000) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    const contexts = FakeAudioContext.instances;
    assert.equal(contexts[0]?.sources.length, 2, 'both requested notes rendered to audio sources');
    await claimAudioFocus('score-player', () => {});
    await Promise.all([first, second]);
    assert.equal(contexts.length, 1);
    assert.equal(contexts[0].sources.length, 2);
    assert.ok(contexts[0].sources.every((source) => source.stopped));
    assert.ok(contexts[0].nodes.every((node) => node.disconnected));
  } finally { await browser.restore(); }
});

test('Studio remains inactive until focus is acquired and stops on focus loss without end callback', async () => {
  const browser = installBrowser();
  try {
    const engine = new StudioAudioEngine();
    let ended = 0;
    let lost = 0;
    const project = { tracks: [{ id: 't', program: 25, tuning: [64, 59, 55, 50, 45, 40] }], bars: [{ trackBeats: { t: [{ isRest: true, notes: [], duration: 4 }] } }], initialTempo: 120 };
    const context = FakeAudioContext.instances[0];
    const previousNodeCount = context?.nodes.length ?? 0;
    const started = await engine.startPlayback(project, 0, 0, undefined, () => ended++, 0, true, false, () => lost++);
    assert.equal(started, true);
    assert.equal(engine.active, true);
    await claimAudioFocus('main-score-player', () => {});
    assert.equal(engine.active, false);
    assert.equal(lost, 1);
    assert.equal(ended, 0);
    assert.ok(context.nodes.slice(previousNodeCount).every((node) => node.disconnected));
  } finally { await browser.restore(); }
});

test('stopping while focus acquisition is pending prevents delayed playback from starting', async () => {
  const browser = installBrowser();
  try {
    const engine = new StudioAudioEngine();
    // Existing lock owner makes the following claim wait for handoff.
    const first = await claimAudioFocus('held', () => {});
    const pending = engine.startPlayback({ tracks: [{ id: 't', program: 25 }], bars: [], initialTempo: 120 });
    engine.stopPlayback();
    first();
    assert.equal(await pending, false);
    assert.equal(engine.active, false);
  } finally { await browser.restore(); }
});

test('a superseded one-shot that is still awaiting focus never creates a late sample', async () => {
  const browser = installBrowser();
  FakeAudioContext.instances.length = 0;
  try {
    const lateNote = playProgramNote(69, 25, 0.1);
    const releasePlayer = await claimAudioFocus('score-player', () => {});
    await lateNote;
    assert.equal(FakeAudioContext.instances.length, 0);
    releasePlayer();
  } finally { await browser.restore(); }
});
