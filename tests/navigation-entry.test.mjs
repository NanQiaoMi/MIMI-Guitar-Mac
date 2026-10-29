import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import {
  installNavigationEntryController,
  navigationEntryBootstrapScript,
} from '../src/lib/ui/navigationEntry.mjs';

class FakeEventTarget {
  listeners = new Map();

  addEventListener(type, listener) {
    const group = this.listeners.get(type) ?? new Set();
    group.add(listener);
    this.listeners.set(type, group);
  }

  removeEventListener(type, listener) {
    this.listeners.get(type)?.delete(listener);
  }

  dispatch(type, properties = {}) {
    const event = { type, ...properties };
    for (const listener of [...(this.listeners.get(type) ?? [])]) listener(event);
    return event;
  }

  listenerCount(type) {
    return this.listeners.get(type)?.size ?? 0;
  }

  totalListeners() {
    return [...this.listeners.values()].reduce((count, group) => count + group.size, 0);
  }
}

class FakeRoot {
  attributes = new Map([['data-motion', 'full']]);
  setAttribute(name, value) { this.attributes.set(name, value); }
  removeAttribute(name) { this.attributes.delete(name); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
}

function environment({ supported = true, readyState = 'complete', mode = 'full', reduced = false } = {}) {
  const windowRef = new FakeEventTarget();
  const documentRef = new FakeEventTarget();
  const root = new FakeRoot();
  root.setAttribute('data-motion', mode);
  windowRef.matchMedia = () => ({ matches: reduced });
  documentRef.readyState = readyState;
  documentRef.documentElement = root;
  if (supported) windowRef.onpagereveal = null;
  return { windowRef, documentRef, root };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

test('native View Transition success leaves the page to the browser', async () => {
  const env = environment();
  const dispose = installNavigationEntryController({ ...env, supportsPageReveal: true });
  const ready = deferred();
  env.windowRef.dispatch('pagereveal', { viewTransition: { ready: ready.promise } });
  ready.resolve();
  await ready.promise;
  await Promise.resolve();
  assert.equal(env.root.getAttribute('data-navigation-entry'), null);
  dispose();
});

test('native rejection and missing transition use a brief full or gentle fallback', async () => {
  const full = environment({ mode: 'full' });
  const disposeFull = installNavigationEntryController({ ...full, supportsPageReveal: true });
  const rejected = deferred();
  full.windowRef.dispatch('pagereveal', { viewTransition: { ready: rejected.promise } });
  rejected.reject(new Error('transition skipped'));
  await rejected.promise.catch(() => {});
  await Promise.resolve();
  assert.equal(full.root.getAttribute('data-navigation-entry'), 'fallback');
  disposeFull();

  const gentle = environment({ mode: 'gentle' });
  const disposeGentle = installNavigationEntryController({ ...gentle, supportsPageReveal: true });
  gentle.windowRef.dispatch('pagereveal', { viewTransition: null });
  assert.equal(gentle.root.getAttribute('data-navigation-entry'), 'fallback');
  disposeGentle();
});

test('off and system-reduced motion never enable the fallback', () => {
  for (const env of [environment({ mode: 'off' }), environment({ mode: 'full', reduced: true })]) {
    const dispose = installNavigationEntryController({ ...env, supportsPageReveal: true });
    env.windowRef.dispatch('pagereveal', { viewTransition: null });
    assert.equal(env.root.getAttribute('data-navigation-entry'), null);
    dispose();
  }
});

test('unsupported pagereveal falls back at DOM ready and can run again after BFCache restore', () => {
  const env = environment({ supported: false, readyState: 'loading' });
  const dispose = installNavigationEntryController({ ...env, supportsPageReveal: false });
  assert.equal(env.root.getAttribute('data-navigation-entry'), null);
  assert.equal(env.documentRef.listenerCount('DOMContentLoaded'), 1);
  env.documentRef.readyState = 'interactive';
  env.documentRef.dispatch('DOMContentLoaded');
  assert.equal(env.root.getAttribute('data-navigation-entry'), 'fallback');

  env.windowRef.dispatch('pagehide');
  assert.equal(env.root.getAttribute('data-navigation-entry'), null);
  env.windowRef.dispatch('pageshow', { persisted: true });
  assert.equal(env.root.getAttribute('data-navigation-entry'), 'fallback');
  dispose();
  assert.equal(env.windowRef.totalListeners(), 0);
  assert.equal(env.documentRef.totalListeners(), 0);
});

test('pagehide invalidates a late ready rejection and cleanup removes listeners', async () => {
  const env = environment();
  const dispose = installNavigationEntryController({ ...env, supportsPageReveal: true });
  const ready = deferred();
  env.windowRef.dispatch('pagereveal', { viewTransition: { ready: ready.promise } });
  env.windowRef.dispatch('pagehide');
  ready.reject(new Error('late transition rejection'));
  await ready.promise.catch(() => {});
  await Promise.resolve();
  assert.equal(env.root.getAttribute('data-navigation-entry'), null);
  dispose();
  assert.equal(env.windowRef.totalListeners(), 0);
});

test('the inline bootstrap is self-contained and registers before DOM readiness', () => {
  const env = environment({ readyState: 'loading' });
  vm.runInNewContext(navigationEntryBootstrapScript, {
    window: env.windowRef,
    document: env.documentRef,
  });
  assert.equal(env.windowRef.listenerCount('pagereveal'), 1);
  assert.equal(env.windowRef.listenerCount('pagehide'), 1);
});

test('CSS fallback is mild, motion-mode aware, and leaves the header outside the animation', () => {
  const css = readFileSync(new URL('../src/styles/motion.css', import.meta.url), 'utf8');
  assert.match(css, /@keyframes navigation-entry-full\s*\{\s*from \{ opacity: 0\.88; transform: translateY\(6px\); \}/);
  assert.match(css, /@keyframes navigation-entry-gentle\s*\{\s*from \{ opacity: 0\.88; \}/);
  assert.match(css, /html\[data-motion="gentle"\]\[data-navigation-entry="fallback"\] main\s*\{\s*animation: navigation-entry-gentle 140ms/);
  assert.match(css, /html\[data-motion="off"\]\[data-navigation-entry="fallback"\] main\s*\{\s*animation: none !important/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?html\[data-navigation-entry="fallback"\]\[data-motion="gentle"\] main/);
  assert.doesNotMatch(css, /data-navigation-entry[^\n]*\.site-header|\.site-header[^\n]*data-navigation-entry/);
});
