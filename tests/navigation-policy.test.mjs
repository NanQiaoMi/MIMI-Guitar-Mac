import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  NAVIGATION_HTML_CACHE_MAX_AGE_SECONDS,
  getNavigationCachePolicy,
  getNavigationPrefetchAttribute,
  isNavigationPrefetchAllowed,
  applyNavigationCachePolicy,
} from '../src/lib/ui/navigationPolicy.ts';
import { installNavigationFeedbackRuntime } from '../src/lib/ui/navigationRuntime.ts';
import { resolveMotionMode } from '../src/lib/ui/motionPreferences.ts';

const BASE_URL = 'https://mimi.example/home';

test('prefetch is limited to anonymous same-origin top-level reading routes', () => {
  for (const route of ['/', '/tabs', '/ukulele', '/article']) {
    assert.equal(isNavigationPrefetchAllowed(route, BASE_URL), true, `${route} is allowlisted`);
    assert.equal(getNavigationPrefetchAttribute(route, BASE_URL), 'hover');
    assert.equal(getNavigationPrefetchAttribute(route, BASE_URL, true), 'false');
  }

  for (const href of [
    '/tabs/123',
    '/tabs?sort=recent',
    '/tabs#latest',
    '/upload',
    '/studio',
    '/library',
    'https://other.example/tabs',
    '//other.example/tabs',
  ]) {
    assert.equal(isNavigationPrefetchAllowed(href, BASE_URL), false, `${href} is excluded`);
    assert.equal(getNavigationPrefetchAttribute(href, BASE_URL), undefined);
  }

  assert.equal(isNavigationPrefetchAllowed('/tabs', 'https://mimi.example/tabs'), false, 'current page is not prefetched');
  assert.equal(isNavigationPrefetchAllowed('/tabs', BASE_URL, true), false, 'cookie-authenticated pages are not prefetched');
});

test('only successful anonymous GET/HEAD allowlisted HTML receives a short private cache', () => {
  const publicPolicy = getNavigationCachePolicy({
    url: 'https://mimi.example/tabs',
    method: 'GET',
    status: 200,
    authenticated: false,
  });
  assert.deepEqual(publicPolicy, {
    cacheControl: `private, max-age=${NAVIGATION_HTML_CACHE_MAX_AGE_SECONDS}`,
    varyCookie: true,
  });

  const cases = [
    { method: 'HEAD', status: 200 },
    { method: 'GET', status: 302 },
    { method: 'GET', status: 500 },
    { method: 'POST', status: 200 },
  ];
  assert.equal(getNavigationCachePolicy({ url: 'https://mimi.example/tabs', method: 'HEAD', status: 200, authenticated: false }).cacheControl,
    `private, max-age=${NAVIGATION_HTML_CACHE_MAX_AGE_SECONDS}`);
  for (const { method, status } of cases.slice(1)) {
    assert.equal(getNavigationCachePolicy({ url: 'https://mimi.example/tabs', method, status, authenticated: false }).cacheControl, 'no-store');
  }
  for (const extra of [
    { authenticated: true },
    { hasCookie: true },
    { hasSetCookie: true },
  ]) {
    assert.equal(getNavigationCachePolicy({ url: 'https://mimi.example/tabs', method: 'GET', status: 200, authenticated: false, ...extra }).cacheControl,
      'no-store');
  }
  for (const url of ['https://mimi.example/tabs?sort=recent', 'https://mimi.example/studio']) {
    const policy = getNavigationCachePolicy({ url, method: 'GET', status: 200, authenticated: false });
    assert.equal(policy.cacheControl, 'no-store');
    assert.equal(policy.varyCookie, false);
  }
});

test('response policy merges Vary safely and leaves wildcard Vary untouched', () => {
  const values = new Map([['vary', 'Accept-Encoding, cookie']]);
  const headers = {
    get(name) { return values.get(name.toLowerCase()) ?? null; },
    set(name, value) { values.set(name.toLowerCase(), value); },
  };
  applyNavigationCachePolicy(headers, { cacheControl: 'private, max-age=10', varyCookie: true });
  assert.equal(values.get('cache-control'), 'private, max-age=10');
  assert.equal(values.get('vary'), 'Accept-Encoding, cookie');

  values.set('vary', '*');
  applyNavigationCachePolicy(headers, { cacheControl: 'no-store', varyCookie: true });
  assert.equal(values.get('vary'), '*');
  assert.equal(values.get('cache-control'), 'no-store');
});

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
    const event = {
      type,
      defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; },
      ...properties,
    };
    for (const listener of [...(this.listeners.get(type) ?? [])]) listener(event);
    return event;
  }

  listenerCount(type) {
    return this.listeners.get(type)?.size ?? 0;
  }

  totalListeners() {
    return [...this.listeners.values()].reduce((sum, group) => sum + group.size, 0);
  }
}

class FakeAnchor {
  attributes = new Map();

  constructor(href = 'https://mimi.example/tabs') {
    this.href = href;
    this.attributes.set('href', href);
    this.attributes.set('data-navigation-feedback', '');
  }

  setAttribute(name, value) { this.attributes.set(name, value); }
  removeAttribute(name) { this.attributes.delete(name); }
  hasAttribute(name) { return this.attributes.has(name); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  closest(selector) {
    if (selector === 'a[href]') return this.hasAttribute('href') ? this : null;
    if (selector === 'a[data-astro-prefetch]') return this.hasAttribute('data-astro-prefetch') ? this : null;
    if (selector === 'nav, footer') return {};
    return selector === 'a[data-navigation-feedback]' && this.hasAttribute('data-navigation-feedback') ? this : null;
  }
}

class FakeNetworkConnection extends FakeEventTarget {
  saveData = false;
  effectiveType = '4g';
}

test('navigation feedback follows pointer and keyboard presses, then clears on cancel and lifecycle changes', () => {
  const documentRef = new FakeEventTarget();
  documentRef.visibilityState = 'visible';
  documentRef.location = { href: BASE_URL };
  const windowRef = new FakeEventTarget();
  const anchor = new FakeAnchor();
  const nestedTarget = { closest: (selector) => anchor.closest(selector) };
  const dispose = installNavigationFeedbackRuntime(documentRef, windowRef);

  documentRef.dispatch('pointerdown', { target: nestedTarget, button: 0, isPrimary: true, ctrlKey: true });
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), true);
  const modifiedClick = documentRef.dispatch('click', { target: nestedTarget, ctrlKey: true, metaKey: true });
  assert.equal(modifiedClick.defaultPrevented, false, 'modifier clicks keep native browser behavior');
  const ordinaryClick = documentRef.dispatch('click', { target: nestedTarget });
  assert.equal(ordinaryClick.defaultPrevented, false, 'ordinary clicks keep native browser behavior');
  documentRef.dispatch('pointerup', { target: nestedTarget, button: 0 });
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), false);

  const external = new FakeAnchor('https://other.example/tabs');
  const externalTarget = { closest: (selector) => external.closest(selector) };
  documentRef.dispatch('pointerdown', { target: externalTarget, button: 0, isPrimary: true });
  assert.equal(external.hasAttribute('data-navigation-pressed'), false, 'external destinations are not marked');
  assert.equal(documentRef.dispatch('click', { target: externalTarget }).defaultPrevented, false);

  const newTab = new FakeAnchor();
  newTab.attributes.set('target', '_blank');
  documentRef.dispatch('pointerdown', { target: { closest: (selector) => newTab.closest(selector) }, button: 0, isPrimary: true });
  assert.equal(newTab.hasAttribute('data-navigation-pressed'), false, 'targeted links retain browser semantics');
  const download = new FakeAnchor();
  download.attributes.set('download', 'score.gp');
  documentRef.dispatch('pointerdown', { target: { closest: (selector) => download.closest(selector) }, button: 0, isPrimary: true });
  assert.equal(download.hasAttribute('data-navigation-pressed'), false, 'downloads are not treated as page navigation');

  documentRef.dispatch('keydown', { target: nestedTarget, key: 'Enter', repeat: false });
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), true);
  documentRef.dispatch('keyup', { target: nestedTarget, key: 'Enter' });
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), false);

  documentRef.dispatch('keydown', { target: nestedTarget, key: 'Enter', repeat: false });
  documentRef.dispatch('keydown', { target: nestedTarget, key: 'Escape', repeat: false });
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), false, 'Escape clears a pending press');
  documentRef.dispatch('pointerdown', { target: nestedTarget, button: 0, isPrimary: true });
  documentRef.dispatch('pointercancel', { target: nestedTarget });
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), false, 'pointer cancellation clears immediately');

  for (const eventName of ['pagehide', 'pageshow', 'blur']) {
    documentRef.dispatch('pointerdown', { target: nestedTarget, button: 0, isPrimary: true });
    windowRef.dispatch(eventName);
    assert.equal(anchor.hasAttribute('data-navigation-pressed'), false, `${eventName} clears stale state`);
  }
  documentRef.dispatch('pointerdown', { target: nestedTarget, button: 0, isPrimary: true });
  documentRef.visibilityState = 'hidden';
  documentRef.dispatch('visibilitychange');
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), false, 'backgrounding clears state');

  documentRef.dispatch('pointerdown', { target: nestedTarget, button: 0, isPrimary: true });
  dispose();
  assert.equal(anchor.hasAttribute('data-navigation-pressed'), false, 'dispose clears a held press');
  assert.equal(documentRef.totalListeners(), 0);
  assert.equal(windowRef.totalListeners(), 0);
  assert.equal(documentRef.listenerCount('click'), 0, 'clicks are never intercepted');
  assert.equal(windowRef.listenerCount('beforeunload'), 0, 'the runtime does not disqualify bfcache');
  dispose();
});

test('slow-connection guard blocks Astro tap fallback and restores bounded opt-in values', () => {
  const documentRef = new FakeEventTarget();
  documentRef.visibilityState = 'visible';
  documentRef.location = { href: BASE_URL };
  const windowRef = new FakeEventTarget();
  const connection = new FakeNetworkConnection();
  const anchors = [new FakeAnchor(), new FakeAnchor()];
  anchors[0].attributes.set('data-astro-prefetch', 'hover');
  anchors[1].attributes.set('data-astro-prefetch', '');
  const navigatorRef = { connection };
  const dispose = installNavigationFeedbackRuntime(documentRef, windowRef, navigatorRef);

  connection.effectiveType = '2g';
  connection.dispatch('change');
  assert.equal(anchors[0].getAttribute('data-astro-prefetch'), 'hover', 'Astro keeps its hover/focus listeners and applies its own slow-network check');
  assert.equal(anchors[1].getAttribute('data-astro-prefetch'), '', 'untouched tap strategies keep their original values');

  const dynamicMenuLink = new FakeAnchor();
  dynamicMenuLink.attributes.set('data-astro-prefetch', 'hover');
  let prevented = false;
  let stopped = false;
  const nestedIcon = {
    closest: (selector) => selector === 'a[data-astro-prefetch]' ? dynamicMenuLink : null,
  };
  const touch = documentRef.dispatch('touchstart', {
    target: nestedIcon,
    preventDefault() { prevented = true; },
    stopPropagation() { stopped = true; },
  });
  assert.equal(dynamicMenuLink.getAttribute('data-astro-prefetch'), 'false', 'capture catches nested taps in links added after setup');
  assert.equal(touch.defaultPrevented, false);
  assert.equal(prevented, false, 'the guard does not cancel the native tap');
  assert.equal(stopped, false, 'the guard does not stop propagation');

  connection.saveData = true;
  connection.effectiveType = '4g';
  connection.dispatch('change');
  assert.equal(dynamicMenuLink.getAttribute('data-astro-prefetch'), 'false', 'Save-Data remains a slow connection signal');
  connection.saveData = false;
  connection.dispatch('change');
  assert.equal(dynamicMenuLink.getAttribute('data-astro-prefetch'), 'hover');

  const tapLink = anchors[1];
  const tapTarget = { closest: (selector) => selector === 'a[data-astro-prefetch]' ? tapLink : null };
  connection.effectiveType = 'slow-2g';
  connection.dispatch('change');
  documentRef.dispatch('mousedown', { target: tapTarget });
  assert.equal(tapLink.getAttribute('data-astro-prefetch'), 'false', 'mousedown capture blocks Astro tap fallback on slow-2g');
  connection.effectiveType = '4g';
  windowRef.dispatch('pageshow');
  assert.equal(tapLink.getAttribute('data-astro-prefetch'), '', 'bfcache restore returns the exact tap opt-in value');

  connection.effectiveType = '2g';
  documentRef.dispatch('touchstart', { target: { closest: (selector) => selector === 'a[data-astro-prefetch]' ? anchors[0] : null } });
  assert.equal(anchors[0].getAttribute('data-astro-prefetch'), 'false');
  connection.dispatch('change');
  dispose();
  assert.equal(anchors[0].getAttribute('data-astro-prefetch'), 'hover', 'dispose restores guarded links');
  assert.equal(connection.listenerCount('change'), 0, 'connection listener is removed');
  assert.equal(documentRef.totalListeners(), 0);
  assert.equal(windowRef.totalListeners(), 0);
});

test('navigation feedback remains compatible with reduced-motion modes and Astro fetch prefetch only', () => {
  const motionCss = readFileSync(new URL('../src/styles/motion.css', import.meta.url), 'utf8');
  const astroConfig = readFileSync(new URL('../astro.config.mjs', import.meta.url), 'utf8');
  const pressedRule = motionCss.match(/a\[data-navigation-pressed\]\s*\{([^}]*)\}/)?.[1] ?? '';

  assert.equal(resolveMotionMode('system', true), 'off');
  assert.equal(resolveMotionMode('gentle', true), 'off');
  assert.equal(resolveMotionMode('system', false), 'full');
  assert.match(pressedRule, /background-color:/);
  assert.doesNotMatch(pressedRule, /padding|margin|transform/);
  assert.match(motionCss, /\.site-navigation-link\s*\{[^}]*transition-property:\s*background-color,\s*border-color,\s*color/s);
  assert.match(motionCss, /html\[data-motion="gentle"\][\s\S]*?transition-duration:\s*140ms\s*!important/);
  assert.match(motionCss, /html\[data-motion="off"\][\s\S]*?transition-duration:\s*0s\s*!important/);
  assert.match(motionCss, /@view-transition\s*\{\s*navigation:\s*auto/);
  assert.match(astroConfig, /prefetch:\s*\{\s*prefetchAll:\s*false,\s*defaultStrategy:\s*'hover'/);
  assert.match(astroConfig, /clientPrerender:\s*false/);
  assert.doesNotMatch(astroConfig, /ClientRouter/);
});
