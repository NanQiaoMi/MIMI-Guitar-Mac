import assert from 'node:assert/strict';
import test from 'node:test';
import {
  MOTION_PREFERENCE_MEDIA_QUERY,
  MOTION_PREFERENCE_STORAGE_KEY,
  getMotionPreferenceSnapshot,
  motionPreferenceBootstrapScript,
  readMotionPreference,
  resolveMotionMode,
  setMotionPreference,
  startMotionPreferenceRuntime,
  subscribeMotionPreference,
} from '../src/lib/ui/motionPreferences.ts';
import { shouldRunFolioFlip } from '../src/lib/ui/folioMotion.ts';

function makeStorage(initial = null, options = {}) {
  let value = initial;
  return {
    getItem(key) {
      assert.equal(key, MOTION_PREFERENCE_STORAGE_KEY);
      if (options.failRead) throw new Error('storage read denied');
      return value;
    },
    setItem(key, next) {
      assert.equal(key, MOTION_PREFERENCE_STORAGE_KEY);
      if (options.failWrite) throw new Error('storage write denied');
      value = next;
    },
    get value() { return value; },
  };
}

function executeBootstrap({ storedValue = null, reduced = false, failStorage = false, noMedia = false } = {}) {
  const attributes = {};
  const root = { setAttribute(name, value) { attributes[name] = value; } };
  const documentRef = { documentElement: root };
  const windowRef = {
    localStorage: {
      getItem(key) {
        assert.equal(key, MOTION_PREFERENCE_STORAGE_KEY);
        if (failStorage) throw new Error('storage disabled');
        return storedValue;
      },
    },
    matchMedia(query) {
      assert.equal(query, MOTION_PREFERENCE_MEDIA_QUERY);
      if (noMedia) throw new Error('media query unavailable');
      return { matches: reduced };
    },
  };

  new Function('window', 'document', motionPreferenceBootstrapScript)(windowRef, documentRef);
  return attributes;
}

test('motion modes honor system reduce before every saved preference', () => {
  assert.equal(resolveMotionMode('system', false), 'full');
  assert.equal(resolveMotionMode('gentle', false), 'gentle');
  assert.equal(resolveMotionMode('off', false), 'off');
  for (const preference of ['system', 'gentle', 'off']) {
    assert.equal(resolveMotionMode(preference, true), 'off');
    assert.equal(resolveMotionMode(preference, null), 'off', 'unknown system state fails closed');
  }
  assert.equal(shouldRunFolioFlip('full'), true);
  assert.equal(shouldRunFolioFlip('gentle'), false);
  assert.equal(shouldRunFolioFlip('off'), false);
});

test('preference storage defaults invalid and inaccessible values to system', () => {
  assert.equal(readMotionPreference(makeStorage('gentle')), 'gentle');
  assert.equal(readMotionPreference(makeStorage(null)), 'system');
  assert.equal(readMotionPreference(makeStorage('unknown')), 'system');
  assert.equal(readMotionPreference(makeStorage(null, { failRead: true })), 'system');
  assert.equal(readMotionPreference(null), 'system');
});

test('head bootstrap applies persisted choice synchronously and clamps it to system reduce', () => {
  assert.deepEqual(executeBootstrap({ storedValue: 'gentle', reduced: false }), {
    'data-motion': 'gentle',
    'data-motion-preference': 'gentle',
  });
  assert.deepEqual(executeBootstrap({ storedValue: 'gentle', reduced: true }), {
    'data-motion': 'off',
    'data-motion-preference': 'gentle',
  });
  assert.deepEqual(executeBootstrap({ storedValue: 'corrupt', reduced: false }), {
    'data-motion': 'full',
    'data-motion-preference': 'system',
  });
  assert.deepEqual(executeBootstrap({ failStorage: true, noMedia: true }), {
    'data-motion': 'off',
    'data-motion-preference': 'system',
  });
});

test('runtime applies same-tab choices, system changes, cross-tab storage and cleans shared listeners', () => {
  const storage = makeStorage(null);
  const rootAttributes = {};
  const root = { setAttribute(name, value) { rootAttributes[name] = value; } };
  const mediaListeners = new Set();
  const storageListeners = new Set();
  const listenerCounts = { mediaAdd: 0, mediaRemove: 0, storageAdd: 0, storageRemove: 0 };
  const media = {
    matches: false,
    addEventListener(type, listener) {
      assert.equal(type, 'change');
      listenerCounts.mediaAdd += 1;
      mediaListeners.add(listener);
    },
    removeEventListener(type, listener) {
      assert.equal(type, 'change');
      listenerCounts.mediaRemove += 1;
      mediaListeners.delete(listener);
    },
  };
  const browserWindow = {
    localStorage: storage,
    matchMedia(query) {
      assert.equal(query, MOTION_PREFERENCE_MEDIA_QUERY);
      return media;
    },
    addEventListener(type, listener) {
      assert.equal(type, 'storage');
      listenerCounts.storageAdd += 1;
      storageListeners.add(listener);
    },
    removeEventListener(type, listener) {
      assert.equal(type, 'storage');
      listenerCounts.storageRemove += 1;
      storageListeners.delete(listener);
    },
  };
  const releaseRuntime = startMotionPreferenceRuntime(root, { window: browserWindow, root });
  const receivedA = [];
  const receivedB = [];
  const unsubscribeA = subscribeMotionPreference((value) => receivedA.push(value));
  const unsubscribeB = subscribeMotionPreference((value) => receivedB.push(value));

  assert.equal(listenerCounts.mediaAdd, 1);
  assert.equal(listenerCounts.storageAdd, 1);
  assert.equal(receivedA.at(-1).mode, 'full');
  assert.equal(rootAttributes['data-motion'], 'full');

  const selected = setMotionPreference('gentle');
  assert.equal(selected.preference, 'gentle');
  assert.equal(selected.mode, 'gentle');
  assert.equal(selected.persistence, 'saved');
  assert.equal(selected.hasStoredPreference, true);
  assert.equal(storage.value, 'gentle');
  assert.equal(rootAttributes['data-motion-preference'], 'gentle');

  media.matches = true;
  for (const listener of [...mediaListeners]) listener({ matches: true });
  assert.equal(getMotionPreferenceSnapshot().preference, 'gentle', 'system reduce does not overwrite the saved choice');
  assert.equal(getMotionPreferenceSnapshot().mode, 'off');

  media.matches = false;
  for (const listener of [...mediaListeners]) listener({ matches: false });
  assert.equal(getMotionPreferenceSnapshot().mode, 'gentle', 'explicit choice resumes when system reduce turns off');

  for (const listener of [...storageListeners]) listener({ key: MOTION_PREFERENCE_STORAGE_KEY, newValue: 'system' });
  assert.equal(getMotionPreferenceSnapshot().preference, 'system');
  assert.equal(getMotionPreferenceSnapshot().mode, 'full');
  assert.equal(rootAttributes['data-motion-preference'], 'system');

  unsubscribeA();
  assert.equal(listenerCounts.mediaRemove, 0, 'one remaining subscriber retains the shared listeners');
  unsubscribeB();
  releaseRuntime();
  assert.equal(listenerCounts.mediaRemove, 1);
  assert.equal(listenerCounts.storageRemove, 1);
  assert.equal(mediaListeners.size, 0);
  assert.equal(storageListeners.size, 0);
  assert.ok(receivedA.some((value) => value.mode === 'off'));
  assert.ok(receivedB.some((value) => value.preference === 'system'));
});

test('failed writes retain the selected mode for this page and report session-only', () => {
  const storage = makeStorage(null, { failWrite: true });
  const media = { matches: false };
  const browserWindow = {
    localStorage: storage,
    matchMedia() { return media; },
  };
  const root = { setAttribute() {} };
  const release = startMotionPreferenceRuntime(root, { window: browserWindow, root });
  const selected = setMotionPreference('gentle');
  assert.equal(selected.preference, 'gentle');
  assert.equal(selected.mode, 'gentle');
  assert.equal(selected.persistence, 'session-only');
  assert.equal(selected.hasStoredPreference, false);
  release();
});

test('SSR snapshot does not expose a previous browser runtime value', () => {
  const storage = makeStorage('off');
  const browserWindow = {
    localStorage: storage,
    matchMedia() { return { matches: false }; },
  };
  const release = startMotionPreferenceRuntime(undefined, { window: browserWindow, root: null });
  assert.equal(getMotionPreferenceSnapshot().preference, 'off');
  release();

  assert.deepEqual(getMotionPreferenceSnapshot(), {
    preference: 'system',
    mode: 'off',
    systemReducedMotion: null,
    persistence: 'session-only',
    hasStoredPreference: false,
  });

  const received = [];
  const unsubscribe = subscribeMotionPreference((value) => received.push(value));
  assert.equal(received.length, 1);
  assert.equal(received[0].preference, 'system');
  unsubscribe();
});
