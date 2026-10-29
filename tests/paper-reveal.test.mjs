import assert from 'node:assert/strict';
import test from 'node:test';
import { paperReveal } from '../src/lib/ui/paperReveal.ts';
import { MOTION_PREFERENCE_STORAGE_KEY, setMotionPreference, startMotionPreferenceRuntime } from '../src/lib/ui/motionPreferences.ts';

function fixture(preference, run, { initiallyVisible = false } = {}) {
  const previousObserver = Object.getOwnPropertyDescriptor(globalThis, 'IntersectionObserver');
  const previousComputed = Object.getOwnPropertyDescriptor(globalThis, 'getComputedStyle');
  const previousWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const observers = [];
  const calls = [];
  let finished = 0;
  let cancelled = 0;
  class Observer {
    constructor(callback) { this.callback = callback; this.disconnected = false; observers.push(this); }
    observe() { this.callback([{ isIntersecting: initiallyVisible }]); }
    disconnect() { this.disconnected = true; }
    enter() { this.callback([{ isIntersecting: true }]); }
  }
  Object.defineProperty(globalThis, 'IntersectionObserver', { configurable: true, value: Observer });
  Object.defineProperty(globalThis, 'getComputedStyle', { configurable: true, value: () => ({ transform: 'matrix(1, 0, 0, 1, 4, 0)', opacity: '0.9' }) });
  const values = new Map([[MOTION_PREFERENCE_STORAGE_KEY, preference]]);
  const browserWindow = {
    localStorage: { getItem: (key) => values.get(key) ?? null, setItem: (key, value) => values.set(key, value) },
    matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }),
    addEventListener() {}, removeEventListener() {},
  };
  Object.defineProperty(globalThis, 'window', { configurable: true, value: browserWindow });
  const release = startMotionPreferenceRuntime(null, { window: browserWindow });
  const listeners = new Map();
  const node = { addEventListener: (name, listener) => listeners.set(name, listener), removeEventListener: (name) => listeners.delete(name), animate(frames, options) {
    calls.push({ frames, options });
    return { finish() { finished += 1; }, cancel() { cancelled += 1; }, onfinish: null };
  } };
  try { run({ node, observers, calls, listeners, counts: () => ({ finished, cancelled }) }); }
  finally {
    release();
    if (previousObserver) Object.defineProperty(globalThis, 'IntersectionObserver', previousObserver); else delete globalThis.IntersectionObserver;
    if (previousComputed) Object.defineProperty(globalThis, 'getComputedStyle', previousComputed); else delete globalThis.getComputedStyle;
    if (previousWindow) Object.defineProperty(globalThis, 'window', previousWindow); else delete globalThis.window;
  }
}

test('paper reveal waits for visibility, runs once and caps the total entry budget', () => {
  fixture('system', ({ node, observers, calls }) => {
    const action = paperReveal(node, { delay: 800 });
    assert.equal(calls.length, 0);
    observers[0].enter();
    observers[0].enter();
    assert.equal(calls.length, 1);
    assert.equal(calls[0].options.duration + calls[0].options.delay, 280);
    assert.equal(calls[0].frames[1].opacity, 0.9);
    assert.match(calls[0].frames[0].transform, /matrix.*translateY/);
    assert.equal(observers[0].disconnected, true);
    action.destroy();
  });
});

test('gentle paper reveal only fades and has no stagger', () => {
  fixture('gentle', ({ node, observers, calls }) => {
    const action = paperReveal(node, { delay: 40 });
    observers[0].enter();
    assert.equal(calls[0].frames[0].transform, calls[0].frames[1].transform);
    assert.equal(calls[0].options.duration, 140);
    assert.equal(calls[0].options.delay, 0);
    action.destroy();
  });
});

test('switching motion off settles the owned reveal without touching child animations', () => {
  fixture('system', ({ node, observers, calls, counts }) => {
    const action = paperReveal(node);
    observers[0].enter();
    setMotionPreference('off');
    assert.equal(counts().finished, 1);
    assert.equal(calls.length, 1);
    action.destroy();
    assert.equal(counts().cancelled, 0);
  });
});

test('off creates no animation; destroy cancels pending owned work', () => {
  fixture('off', ({ node, observers, calls }) => {
    const action = paperReveal(node);
    assert.equal(observers.length, 0);
    assert.equal(calls.length, 0);
    action.destroy();
  });
  fixture('system', ({ node, observers, counts }) => {
    const action = paperReveal(node);
    observers[0].enter();
    action.destroy();
    assert.equal(counts().cancelled, 1);
    setMotionPreference('off');
    assert.equal(counts().finished, 0);
  });
});

test('already-visible SSR content is never hidden on hydration', () => {
  fixture('system', ({ node, calls, observers }) => {
    const action = paperReveal(node);
    assert.equal(calls.length, 0);
    assert.equal(observers[0].disconnected, true);
    action.destroy();
  }, { initiallyVisible: true });
});

test('keyboard focus settles a reveal and removes the focus listener on destroy', () => {
  fixture('system', ({ node, calls, observers, listeners, counts }) => {
    const action = paperReveal(node);
    observers[0].enter();
    listeners.get('focusin')();
    assert.equal(calls.length, 1);
    assert.equal(counts().finished, 1);
    action.destroy();
    assert.equal(listeners.size, 0);
  });
});
