import assert from 'node:assert/strict';
import test from 'node:test';
import {
  fadeMotion,
  motionStyle,
  motionTokens,
  prefersReducedMotion,
  registerMotionSurface,
  surfaceMotion,
} from '../src/lib/ui/motion.ts';

function withWindow(value, run) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'window');
  Object.defineProperty(globalThis, 'window', { configurable: true, writable: true, value });
  try {
    run();
  } finally {
    if (previous) Object.defineProperty(globalThis, 'window', previous);
    else delete globalThis.window;
  }
}

function motionWindow(preference = 'system', reduced = false) {
  return {
    localStorage: { getItem: () => preference },
    matchMedia: (query) => {
      assert.equal(query, '(prefers-reduced-motion: reduce)');
      return { matches: reduced };
    },
  };
}

function motionNode() {
  const baseline = { transform: 'matrix(1, 0, 0, 1, 4, 0)', opacity: '0.8' };
  return {
    ownerDocument: { defaultView: { getComputedStyle: () => baseline } },
    baseline,
  };
}

test('motion tokens stay inside the interaction budget and feed the CSS variables', () => {
  assert.deepEqual(motionTokens.duration, {
    micro: 120,
    control: 200,
    panel: 260,
    page: 280,
    exit: 160,
    folio: 360,
  });
  assert.ok(motionTokens.duration.exit < motionTokens.duration.panel);

  const properties = Object.fromEntries(
    motionStyle.split(';').map((declaration) => {
      const separator = declaration.indexOf(':');
      return [declaration.slice(0, separator), declaration.slice(separator + 1)];
    }),
  );
  for (const token of ['micro', 'control', 'panel', 'page', 'exit', 'folio']) {
    assert.equal(properties[`--motion-duration-${token}`], `${motionTokens.duration[token]}ms`);
  }
  assert.equal(properties['--motion-ease-standard'], motionTokens.easing.standard.css);
  assert.equal(properties['--motion-ease-settle'], motionTokens.easing.settle.css);
});

test('easing functions have stable endpoints and monotonic progress', () => {
  for (const easing of [motionTokens.easing.standard.fn, motionTokens.easing.settle.fn]) {
    assert.equal(easing(0), 0);
    assert.equal(easing(1), 1);

    let previous = 0;
    for (let step = 1; step <= 100; step += 1) {
      const progress = easing(step / 100);
      assert.ok(Number.isFinite(progress));
      assert.ok(progress >= previous - 1e-8);
      assert.ok(progress >= 0 && progress <= 1);
      previous = progress;
    }
  }
});

test('reduced motion is the server and unsupported-environment default', () => {
  assert.equal(typeof globalThis.window, 'undefined');
  assert.equal(prefersReducedMotion(), true);

  // The SSR path must return before inspecting a node or reading browser APIs.
  assert.equal(surfaceMotion(undefined, { kind: 'panel' }).duration, 0);
  assert.equal(fadeMotion(undefined, { kind: 'notice' }).duration, 0);
});

test('reduced motion follows the current media preference when called in a browser', () => {
  let queried = '';
  withWindow({
    matchMedia(query) {
      queried = query;
      return { matches: false };
    },
  }, () => {
    assert.equal(prefersReducedMotion(), false);
  });
  assert.equal(queried, '(prefers-reduced-motion: reduce)');

  withWindow({ matchMedia: () => ({ matches: true }) }, () => {
    assert.equal(prefersReducedMotion(), true);
  });
  withWindow({}, () => {
    assert.equal(prefersReducedMotion(), true);
  });
  withWindow({ matchMedia: () => { throw new Error('media query unavailable'); } }, () => {
    assert.equal(prefersReducedMotion(), true);
  });
});

test('full surface motion composes its transition with the computed baseline', () => {
  const node = motionNode();
  withWindow(motionWindow('system', false), () => {
    const transition = surfaceMotion(node, { kind: 'panel', y: 12, scale: 0.985 });
    assert.equal(transition.duration, motionTokens.duration.panel);
    assert.match(transition.css(0), /transform:matrix\(1, 0, 0, 1, 4, 0\) translate3d\(0,12px,0\) scale\(0\.985\)/);
    assert.match(transition.css(1), /transform:matrix\(1, 0, 0, 1, 4, 0\) translate3d\(0,0px,0\) scale\(1\)/);
    assert.match(transition.css(1), /opacity:0\.8/);
  });
});

test('gentle surface motion fades the baseline only, with no offset or scale', () => {
  const node = motionNode();
  withWindow(motionWindow('gentle', false), () => {
    const transition = surfaceMotion(node, { kind: 'panel', y: 24, scale: 0.8, duration: 500 });
    assert.ok(transition.duration <= 140, 'gentle duration stays within the 140ms interaction budget');
    assert.match(transition.css(0), /opacity:0;transform:matrix\(1, 0, 0, 1, 4, 0\)$/);
    assert.match(transition.css(1), /opacity:0\.8;transform:matrix\(1, 0, 0, 1, 4, 0\)$/);
    assert.doesNotMatch(transition.css(0), /translate|scale/);
  });
});

test('off surface motion reaches its terminal state immediately', () => {
  withWindow(motionWindow('off', false), () => {
    assert.equal(surfaceMotion(motionNode(), { kind: 'panel' }).duration, 0);
    assert.equal(fadeMotion(motionNode(), { kind: 'panel' }).duration, 0);
  });
});


test('registerMotionSurface finishes only wrapper-owned animations on a shared preference change', () => {
  let listenerAdds = 0;
  let listenerRemoves = 0;
  const listeners = new Set();
  const media = {
    matches: false,
    addEventListener(type, listener) {
      assert.equal(type, 'change');
      listenerAdds += 1;
      listeners.add(listener);
    },
    removeEventListener(type, listener) {
      assert.equal(type, 'change');
      listenerRemoves += 1;
      listeners.delete(listener);
    },
    change(matches) {
      this.matches = matches;
      for (const listener of [...listeners]) listener({ matches });
    },
  };
  const finished = [];
  const descendant = { finish() { finished.push('descendant'); } };
  const ownFirst = { finish() { finished.push('first'); } };
  const ownSecond = { finish() { finished.push('second'); } };
  const getAnimationOptions = [];
  const firstNode = {
    getAnimations(options) {
      getAnimationOptions.push(options);
      return options?.subtree === false ? [ownFirst] : [ownFirst, descendant];
    },
  };
  const secondNode = {
    getAnimations(options) {
      getAnimationOptions.push(options);
      return options?.subtree === false ? [ownSecond] : [ownSecond, descendant];
    },
  };

  withWindow({ matchMedia: () => media }, () => {
    const first = registerMotionSurface(firstNode);
    const second = registerMotionSurface(secondNode);
    assert.equal(listenerAdds, 1, 'multiple wrappers share one media listener');
    assert.equal(listeners.size, 1);

    media.change(true);
    assert.deepEqual(finished, ['first', 'second']);
    assert.deepEqual(getAnimationOptions, [{ subtree: false }, { subtree: false }]);

    first.destroy();
    media.change(false);
    media.change(true);
    assert.deepEqual(finished, ['first', 'second'], 'same Animation objects are attempted at most once');

    second.destroy();
    assert.equal(listenerRemoves, 1, 'last destroy removes the shared listener');
    assert.equal(listeners.size, 0);
  });
});

test('registerMotionSurface guards re-entry and tolerates finish failures', () => {
  const listeners = new Set();
  const media = {
    matches: false,
    addEventListener(_type, listener) { listeners.add(listener); },
    removeEventListener(_type, listener) { listeners.delete(listener); },
    change(matches) {
      this.matches = matches;
      for (const listener of [...listeners]) listener({ matches });
    },
  };
  let firstAttempts = 0;
  let laterAttempts = 0;
  const reentrantAnimation = {
    finish() {
      firstAttempts += 1;
      media.change(true);
    },
  };
  const throwingAnimation = { finish() { throw new Error('cannot finish'); } };
  const laterAnimation = { finish() { laterAttempts += 1; } };
  const registrations = [];

  withWindow({ matchMedia: () => media }, () => {
    registrations.push(registerMotionSurface({ getAnimations: () => [reentrantAnimation] }));
    registrations.push(registerMotionSurface({ getAnimations: () => [throwingAnimation, laterAnimation] }));
    assert.doesNotThrow(() => media.change(true));
    assert.equal(firstAttempts, 1, 'a finish-triggered change cannot recurse');
    assert.equal(laterAttempts, 1, 'one throwing animation does not block the remaining snapshot');
  });
  for (const registration of registrations) registration.destroy();
});

test('registerMotionSurface is an SSR no-op', () => {
  assert.equal(typeof globalThis.window, 'undefined');
  let getAnimationsCalls = 0;
  const registration = registerMotionSurface({
    getAnimations() { getAnimationsCalls += 1; return [{ finish() {} }]; },
  });
  assert.doesNotThrow(() => registration.destroy());

  const listeners = new Set();
  let browserSurfaceCalls = 0;
  const media = {
    matches: false,
    addEventListener(_type, listener) { listeners.add(listener); },
    removeEventListener(_type, listener) { listeners.delete(listener); },
  };
  withWindow({ matchMedia: () => media }, () => {
    const browserRegistration = registerMotionSurface({
      getAnimations() {
        browserSurfaceCalls += 1;
        return [{ finish() {} }];
      },
    });
    media.matches = true;
    for (const listener of [...listeners]) listener({ matches: true });
    browserRegistration.destroy();
  });
  assert.equal(getAnimationsCalls, 0, 'SSR calls do not leave a surface registered for browser updates');
  assert.equal(browserSurfaceCalls, 1, 'the browser surface still responds to its own preference change');
  assert.equal(listeners.size, 0, 'browser listeners are removed after the last surface is destroyed');
});
