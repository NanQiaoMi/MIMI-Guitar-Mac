import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  deleteDraftFromStorage,
  listLocalDrafts,
  loadLatestDraftFromStorage,
  saveDraftToStorage,
  STUDIO_DRAFT_KEY,
} from '../src/lib/studio/localScorePersistence.ts';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';

class MemoryStorage {
  values = new Map();
  get length() { return this.values.size; }
  key(index) { return [...this.values.keys()][index] ?? null; }
  getItem(key) { return this.values.get(key) ?? null; }
  setItem(key, value) { this.values.set(String(key), String(value)); }
  removeItem(key) { this.values.delete(key); }
}

function withBrowserStorage(run, storage = new MemoryStorage()) {
  const oldWindow = globalThis.window;
  const oldStorage = globalThis.localStorage;
  globalThis.window = {};
  globalThis.localStorage = storage;
  try { return run(storage); }
  finally {
    if (oldWindow === undefined) delete globalThis.window;
    else globalThis.window = oldWindow;
    if (oldStorage === undefined) delete globalThis.localStorage;
    else globalThis.localStorage = oldStorage;
  }
}

test('latest draft deletion selects the previous saved project and removes its stale snapshot', () => {
  withBrowserStorage((storage) => {
    const first = createBlankProject('guitar');
    first.title = '第一份';
    const latest = createBlankProject('bass');
    latest.title = '最近编辑';

    assert.equal(saveDraftToStorage(first), true);
    assert.equal(saveDraftToStorage(latest), true);
    assert.equal(loadLatestDraftFromStorage().id, latest.id);

    deleteDraftFromStorage(latest.id);

    assert.equal(loadLatestDraftFromStorage().id, first.id);
    assert.equal(storage.getItem(STUDIO_DRAFT_KEY), null);
    assert.deepEqual(listLocalDrafts().map((draft) => draft.id), [first.id]);
  });
});

test('old direct snapshots migrate into the versioned draft list', () => {
  withBrowserStorage((storage) => {
    const old = createBlankProject('ukulele');
    delete old.schemaVersion;
    storage.setItem(STUDIO_DRAFT_KEY, JSON.stringify(old));

    const loaded = loadLatestDraftFromStorage();

    assert.equal(loaded.id, old.id);
    assert.equal(loaded.schemaVersion, 1);
    assert.notEqual(storage.getItem(`mimi_studio_draft_${old.id}`), null);
    assert.equal(listLocalDrafts()[0].id, old.id);
  });
});

test('draft save has one atomic per-project commit and preserves prior bytes on quota failure', () => {
  const existing = createBlankProject('guitar');
  existing.title = '已有有效草稿';
  const storage = new MemoryStorage();
  const key = `mimi_studio_draft_${existing.id}`;
  storage.setItem(key, JSON.stringify(existing));
  const before = new Map(storage.values);
  const writeAttempts = [];
  storage.setItem = (target, value) => {
    writeAttempts.push(target);
    if (target === key) throw new Error('quota exceeded');
    storage.values.set(String(target), String(value));
  };

  withBrowserStorage(() => {
    const next = { ...existing, title: '未能提交的新版本' };
    assert.equal(saveDraftToStorage(next), false);
  }, storage);

  assert.deepEqual(writeAttempts, [key]);
  assert.deepEqual(storage.values, before);
  assert.equal(JSON.parse(storage.getItem(key)).title, '已有有效草稿');
});

test('a corrupt newest snapshot does not hide an older valid project', () => {
  const storage = new MemoryStorage();
  const valid = createBlankProject('guitar');
  valid.updatedAt = 100;
  const broken = createBlankProject('bass');
  broken.updatedAt = 200;
  storage.setItem(`mimi_studio_draft_${valid.id}`, JSON.stringify(valid));
  storage.setItem(`mimi_studio_draft_${broken.id}`, '{broken');

  withBrowserStorage(() => {
    assert.equal(loadLatestDraftFromStorage().id, valid.id);
  }, storage);
});
