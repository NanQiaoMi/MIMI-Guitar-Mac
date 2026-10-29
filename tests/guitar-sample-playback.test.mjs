import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  getGlobalInstrumentSelection,
  playProgramChordStrum,
  playProgramNote,
  setGlobalProgram,
} from '../src/lib/guitarSound.ts';

const gmBytes = new Uint8Array(await readFile('public/soundfonts/sonivox.sf2'));
const ukuleleBytes = new Uint8Array(await readFile('public/storage/soundfonts/ukulele_fast.sf2'));

class FakeSource {
  listeners = new Map();
  stopped = false;
  disconnected = false;
  buffer = null;
  startTime = null;
  connect() {}
  disconnect() { this.disconnected = true; }
  addEventListener(name, callback) {
    const listeners = this.listeners.get(name) ?? new Set();
    listeners.add(callback);
    this.listeners.set(name, listeners);
  }
  removeEventListener(name, callback) { this.listeners.get(name)?.delete(callback); }
  start(when) { this.startTime = when; }
  stop() {
    this.stopped = true;
    queueMicrotask(() => {
      for (const callback of this.listeners.get('ended') ?? []) callback();
    });
  }
  finish() {
    for (const callback of this.listeners.get('ended') ?? []) callback();
  }
}

class FakeAudioContext {
  static instances = [];
  state = 'running';
  currentTime = 10;
  destination = {};
  sources = [];
  constructor() { FakeAudioContext.instances.push(this); }
  resume() { return Promise.resolve(); }
  createBuffer(channelCount, length, sampleRate) {
    const channels = Array.from({ length: channelCount }, () => new Float32Array(length));
    return {
      numberOfChannels: channelCount,
      length,
      sampleRate,
      getChannelData: (channel) => channels[channel],
    };
  }
  createBufferSource() {
    const source = new FakeSource();
    this.sources.push(source);
    return source;
  }
}

function createSession() {
  const controller = new AbortController();
  const sources = new Set();
  const cleanupBySource = new Map();
  let released = false;
  return {
    sources,
    get active() { return !released; },
    get signal() { return controller.signal; },
    track(source, cleanup) {
      if (released) {
        source.stop();
        cleanup?.();
        return;
      }
      sources.add(source);
      if (cleanup) cleanupBySource.set(source, cleanup);
      source.addEventListener('ended', () => {
        sources.delete(source);
        cleanupBySource.get(source)?.();
        cleanupBySource.delete(source);
      }, { once: true });
    },
    release() {
      if (released) return;
      released = true;
      controller.abort();
      for (const source of sources) {
        source.stop();
        cleanupBySource.get(source)?.();
      }
      sources.clear();
      cleanupBySource.clear();
    },
  };
}

function installAudioAndFetch(fetchImpl) {
  const oldWindow = globalThis.window;
  const oldFetch = globalThis.fetch;
  const oldElement = Object.getOwnPropertyDescriptor(globalThis, 'Element');
  class FakeElement {}
  FakeElement.prototype.replaceChildren = function () {};
  globalThis.Element = FakeElement;
  globalThis.window = { AudioContext: FakeAudioContext, dispatchEvent() {} };
  globalThis.fetch = fetchImpl;
  return () => {
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
    globalThis.fetch = oldFetch;
    if (oldElement) Object.defineProperty(globalThis, 'Element', oldElement);
    else delete globalThis.Element;
  };
}

async function waitFor(predicate, message, timeoutMs = 3000) {
  const startedAt = Date.now();
  while (!predicate()) {
    if (Date.now() - startedAt > timeoutMs) throw new Error(message);
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

test('session release aborts a verified font load before any Web Audio source is created', async () => {
  let beginFetch;
  let resolveFetch;
  const fetchStarted = new Promise((resolve) => { beginFetch = resolve; });
  const responseGate = new Promise((resolve) => { resolveFetch = resolve; });
  const restore = installAudioAndFetch(async (url) => {
    assert.equal(url, '/soundfonts/sonivox.sf2');
    beginFetch();
    return responseGate;
  });
  const session = createSession();
  try {
    setGlobalProgram(25, { source: 'test', flavor: 'gm', broadcast: false });
    const playback = playProgramNote(61, 25, 0.2, session, 'gm');
    await fetchStarted;
    session.release();
    await playback;
    assert.equal(FakeAudioContext.instances.at(-1)?.sources.length ?? 0, 0);
    resolveFetch(new Response(gmBytes, { status: 200 }));
    await new Promise((resolve) => setTimeout(resolve, 0));
  } finally {
    session.release();
    restore();
  }
});

test('verified ukulele bytes render to a stereo AudioBuffer and instrument changes stop the old note', async () => {
  const requestedUrls = [];
  const restore = installAudioAndFetch(async (url) => {
    requestedUrls.push(url);
    if (url === '/storage/soundfonts/ukulele_fast.sf2') return new Response(ukuleleBytes, { status: 200 });
    if (url === '/soundfonts/sonivox.sf2') return new Response(gmBytes, { status: 200 });
    throw new Error(`unexpected SoundFont URL ${url}`);
  });
  const session = createSession();
  try {
    setGlobalProgram(24, { source: 'score', flavor: 'ukulele', instrumentOverride: false, scoreId: 'uke-score', broadcast: false });
    assert.deepEqual(getGlobalInstrumentSelection(), {
      program: 24,
      flavor: 'ukulele',
      instrumentOverride: false,
      source: 'score',
      scoreId: 'uke-score',
    });

    let firstPlaybackSettled = false;
    const firstPlayback = playProgramNote(64, undefined, 0.12, session).then(() => { firstPlaybackSettled = true; });
    const context = FakeAudioContext.instances.at(-1);
    await waitFor(() => context.sources.length > 0, 'ukulele note did not reach Web Audio');
    const source = context.sources.at(-1);
    assert.equal(firstPlaybackSettled, false, 'external-session playback remains pending until source end');
    assert.ok(requestedUrls.includes('/storage/soundfonts/ukulele_fast.sf2'));
    assert.equal(source.startTime, context.currentTime);
    assert.equal(source.buffer.numberOfChannels, 2);
    assert.equal(source.buffer.sampleRate, 44_100);
    assert.ok(source.buffer.getChannelData(0).some((sample) => Math.abs(sample) > 1e-7));
    assert.equal(source.buffer.getChannelData(1).length, source.buffer.getChannelData(0).length);
    assert.ok(source.buffer.getChannelData(1).every(Number.isFinite));
    source.finish();
    await firstPlayback;
    assert.equal(firstPlaybackSettled, true);

    const oldProgramPlayback = playProgramNote(65, undefined, 0.12, session);
    await waitFor(() => context.sources.length > 1, 'second note did not reach Web Audio');
    const oldProgramSource = context.sources.at(-1);
    setGlobalProgram(25, { source: 'user', flavor: 'gm', broadcast: false });
    assert.equal(oldProgramSource.stopped, true, 'changing the active preset stops its old sample');
    assert.equal(oldProgramSource.disconnected, true);
    await oldProgramPlayback;
  } finally {
    session.release();
    restore();
  }
});

test('cancel during alphaTab render yields no late source and bank 128 is handled as percussion', async () => {
  const requestedUrls = [];
  const restore = installAudioAndFetch(async (url) => {
    requestedUrls.push(url);
    if (url === '/storage/soundfonts/ukulele_fast.sf2') return new Response(ukuleleBytes, { status: 200 });
    if (url === '/soundfonts/sonivox.sf2') return new Response(gmBytes, { status: 200 });
    throw new Error(`unexpected SoundFont URL ${url}`);
  });
  try {
    const renderSession = createSession();
    let sawRenderYield = false;
    const originalSetTimeout = globalThis.setTimeout;
    globalThis.setTimeout = function (callback, delay, ...args) {
      if (!sawRenderYield && delay === 0) {
        sawRenderYield = true;
        queueMicrotask(() => renderSession.release());
      }
      return originalSetTimeout(callback, delay, ...args);
    };
    try {
      const context = FakeAudioContext.instances.at(-1);
      const sourceCount = context?.sources.length ?? 0;
      await playProgramNote(72, 89, 1.4, renderSession, 'gm');
      assert.equal(sawRenderYield, true, 'renderer yielded between its bounded PCM chunks');
      assert.equal((context?.sources.length ?? 0), sourceCount, 'aborted PCM never becomes an AudioBufferSourceNode');
    } finally {
      globalThis.setTimeout = originalSetTimeout;
      renderSession.release();
    }

    const drumSession = createSession();
    const context = FakeAudioContext.instances.at(-1);
    const beforeDrumSources = context?.sources.length ?? 0;
    const drumPlayback = playProgramNote(36, 128, 0.12, drumSession, 'ukulele');
    await waitFor(() => context.sources.length > beforeDrumSources, 'percussion note did not reach Web Audio');
    const drumSource = context.sources.at(-1);
    assert.ok(drumSource.buffer.getChannelData(0).some((sample) => Math.abs(sample) > 1e-7));
    drumSource.finish();
    await drumPlayback;
    drumSession.release();

    const pianoSession = createSession();
    const beforePianoSources = context.sources.length;
    const pianoPlayback = playProgramNote(36, 0, 0.12, pianoSession, 'gm');
    await waitFor(() => context.sources.length > beforePianoSources, 'piano note did not reach Web Audio');
    const pianoSource = context.sources.at(-1);
    const drumSamples = drumSource.buffer.getChannelData(0);
    const pianoSamples = pianoSource.buffer.getChannelData(0);
    assert.equal(drumSamples.length, pianoSamples.length);
    assert.ok(drumSamples.some((sample, index) => Math.abs(sample - pianoSamples[index]) > 1e-5),
      'GM bank 128 percussion output differs from bank 0 piano for the same MIDI note');
    pianoSource.finish();
    await pianoPlayback;
    pianoSession.release();

    const chordSession = createSession();
    const beforeChordSources = context.sources.length;
    const chordPlayback = playProgramChordStrum([48, 52, 55, 60], 'up', 25, chordSession, 'gm');
    await waitFor(() => context.sources.length > beforeChordSources, 'chord did not reach Web Audio');
    const chordSource = context.sources.at(-1);
    let chordSettled = false;
    chordPlayback.then(() => { chordSettled = true; });
    await Promise.resolve();
    assert.equal(chordSettled, false, 'external-session chord playback remains pending until source end');
    assert.equal(chordSource.buffer.numberOfChannels, 2);
    assert.ok(chordSource.buffer.getChannelData(0).some((sample) => Math.abs(sample) > 1e-7));
    chordSource.finish();
    await chordPlayback;
    assert.equal(chordSettled, true);
    chordSession.release();
  } finally {
    restore();
  }
});
