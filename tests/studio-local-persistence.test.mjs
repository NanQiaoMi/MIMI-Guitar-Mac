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
  const other = createBlankProject('bass');
  other.title = '其他项目';
  const storage = new MemoryStorage();
  const key = `mimi_studio_draft_${existing.id}`;
  storage.setItem(key, JSON.stringify(existing));
  storage.setItem(`mimi_studio_draft_${other.id}`, JSON.stringify(other));
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

test('a successful save writes once to the project key and creates no backup key', () => {
  const project = createBlankProject('guitar');
  const key = `mimi_studio_draft_${project.id}`;
  const storage = new MemoryStorage();
  storage.setItem(key, JSON.stringify({ ...project, title: '旧版本' }));
  const originalSetItem = storage.setItem.bind(storage);
  const writeAttempts = [];
  storage.setItem = (target, value) => {
    writeAttempts.push(String(target));
    originalSetItem(target, value);
  };

  withBrowserStorage(() => {
    assert.equal(saveDraftToStorage({ ...project, title: '新版本' }), true);
  }, storage);

  assert.deepEqual(writeAttempts, [key]);
  assert.equal(storage.getItem(`${key}_backup`), null);
  assert.equal(JSON.parse(storage.getItem(key)).title, '新版本');
});

test('valid primary wins over a newer backup and backup entries merge by id', () => {
  const primary = createBlankProject('guitar');
  primary.title = '主键版本';
  primary.updatedAt = 100;
  const backup = { ...primary, title: '较新的备份版本', updatedAt: 900 };
  const other = createBlankProject('bass');
  other.title = '其他项目';
  other.updatedAt = 500;
  const primaryKey = `mimi_studio_draft_${primary.id}`;
  const storage = new MemoryStorage();
  storage.setItem(primaryKey, JSON.stringify(primary));
  storage.setItem(`${primaryKey}_backup`, JSON.stringify(backup));
  storage.setItem(`mimi_studio_draft_${other.id}`, JSON.stringify(other));
  const beforeRead = new Map(storage.values);

  withBrowserStorage(() => {
    assert.equal(loadLatestDraftFromStorage().id, other.id);
    const listed = listLocalDrafts().map(({ id, title }) => ({ id, title }));
    assert.deepEqual(listed, [
      { id: other.id, title: other.title },
      { id: primary.id, title: primary.title },
    ]);
  }, storage);

  assert.deepEqual(storage.values, beforeRead);
});

test('corrupt or missing primaries recover valid legacy backups without duplicate rows', () => {
  const corruptPrimary = createBlankProject('guitar');
  corruptPrimary.title = '损坏主键的恢复版本';
  corruptPrimary.updatedAt = 500;
  const missingPrimary = createBlankProject('bass');
  missingPrimary.title = '缺失主键的恢复版本';
  missingPrimary.updatedAt = 400;
  const corruptKey = `mimi_studio_draft_${corruptPrimary.id}`;
  const missingKey = `mimi_studio_draft_${missingPrimary.id}`;
  const storage = new MemoryStorage();
  storage.setItem(corruptKey, '{broken');
  storage.setItem(`${corruptKey}_backup`, JSON.stringify(corruptPrimary));
  storage.setItem(`${missingKey}_backup`, JSON.stringify(missingPrimary));
  const beforeRead = new Map(storage.values);

  withBrowserStorage(() => {
    const latest = loadLatestDraftFromStorage();
    assert.equal(latest.id, corruptPrimary.id);
    assert.equal(latest.title, corruptPrimary.title);
    const listed = listLocalDrafts();
    assert.deepEqual(listed.map(({ id }) => id), [corruptPrimary.id, missingPrimary.id]);
    assert.equal(listed.filter(({ id }) => id === corruptPrimary.id).length, 1);
    assert.equal(listed.filter(({ id }) => id === missingPrimary.id).length, 1);
  }, storage);

  assert.deepEqual(storage.values, beforeRead);
});

test('deleting a draft removes its primary and backup without restoring it on reload', () => {
  const deleted = createBlankProject('guitar');
  deleted.title = '待删除项目';
  deleted.updatedAt = 300;
  const other = createBlankProject('bass');
  other.title = '保留项目';
  other.updatedAt = 200;
  const deletedKey = `mimi_studio_draft_${deleted.id}`;
  const otherKey = `mimi_studio_draft_${other.id}`;
  const storage = new MemoryStorage();
  storage.setItem(deletedKey, JSON.stringify(deleted));
  storage.setItem(`${deletedKey}_backup`, JSON.stringify({ ...deleted, title: '遗留备份' }));
  storage.setItem(otherKey, JSON.stringify(other));

  withBrowserStorage(() => {
    deleteDraftFromStorage(deleted.id);

    assert.equal(storage.getItem(deletedKey), null);
    assert.equal(storage.getItem(`${deletedKey}_backup`), null);
    assert.equal(storage.getItem(otherKey), JSON.stringify(other));
    assert.equal(loadLatestDraftFromStorage().id, other.id);
    assert.deepEqual(listLocalDrafts().map(({ id }) => id), [other.id]);
  }, storage);
});

test('deleting a draft preserves another project whose id ends in _backup', () => {
  withBrowserStorage((storage) => {
    const first = createBlankProject('guitar');
    const other = { ...createBlankProject('bass'), id: `${first.id}_backup` };
    storage.setItem(`mimi_studio_draft_${first.id}`, JSON.stringify(first));
    storage.setItem(`mimi_studio_draft_${other.id}`, JSON.stringify(other));

    deleteDraftFromStorage(first.id);

    assert.equal(storage.getItem(`mimi_studio_draft_${other.id}`), JSON.stringify(other));
    assert.deepEqual(listLocalDrafts().map(({ id }) => id), [other.id]);
  });
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
