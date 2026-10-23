import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test, { afterEach, beforeEach } from 'node:test';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import { addCatalogFavorite } from '../src/lib/personal/catalog.ts';
import { updatePracticeSessionIfOpen } from '../src/lib/practice/practiceProgress.ts';
import { createEmptyPersonalData, validatePersonalData } from '../src/lib/personal/validation.ts';
import { MAX_PERSONAL_ASSET_BYTES, MAX_PERSONAL_BACKUP_ASSET_BYTES, MAX_PERSONAL_BACKUP_VOLUMES } from '../src/lib/personal/limits.ts';
import {
  getPersonalMigrationWarnings,
  hashBytes,
  mutatePersonalData,
  readAsset,
  readPersonalAssetMetadata,
  readPersonalData,
  retryPersonalDataMigration,
  subscribePersonalData,
} from '../src/lib/personal/repository.ts';

const require = createRequire(import.meta.url);
const { IDBFactory, IDBObjectStore } = require('fake-indexeddb');
const oldGlobals = {};

function TestStorage(entries = []) {
  this.values = new Map(entries);
  Object.defineProperty(this, 'length', { get: () => this.values.size });
  this.key = (index) => [...this.values.keys()][index] ?? null;
  this.getItem = (key) => this.values.get(key) ?? null;
  this.setItem = (key, value) => this.values.set(String(key), String(value));
  this.removeItem = (key) => this.values.delete(key);
}

beforeEach(() => {
  oldGlobals.window = globalThis.window;
  oldGlobals.indexedDB = globalThis.indexedDB;
  oldGlobals.localStorage = globalThis.localStorage;
  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
});

afterEach(() => {
  for (const name of ['window', 'indexedDB', 'localStorage']) {
    if (oldGlobals[name] === undefined) delete globalThis[name];
    else globalThis[name] = oldGlobals[name];
  }
});

function catalogScore(id = 'catalog:fixture', revision = 'revision-1') {
  return {
    id,
    source: 'catalog',
    sourceId: id.replace(/^catalog:/, ''),
    revision,
    title: 'Fixture',
    artist: 'Local Test',
    category: 'guitar',
    format: 'ibe',
    scoreUrl: '/storage/scores/fixture.ibe',
    createdAt: 100,
    updatedAt: 100,
  };
}

function practiceSession(slices = []) {
  return {
    id: 'session-stable',
    scoreId: 'catalog:fixture',
    scoreRevision: 'revision-1',
    state: 'paused',
    startedAt: 100,
    updatedAt: 200,
    timezone: 'Asia/Shanghai',
    slices,
    note: '',
  };
}

async function seedScoreAndSession(slices = [], revision = 'revision-1') {
  await mutatePersonalData((draft) => {
    draft.scores = [catalogScore('catalog:fixture', revision)];
    draft.sessions = [practiceSession(slices)];
  });
}

async function setAssetMetadataSize(id, size) {
  const request = indexedDB.open('mimi-personal');
  const db = await new Promise((resolve, reject) => { request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
  try {
    const tx = db.transaction('assetMetadata', 'readwrite');
    tx.objectStore('assetMetadata').put({ id, size, mimeType: 'application/octet-stream' });
    await new Promise((resolve, reject) => { tx.oncomplete = resolve; tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error); });
  } finally { db.close(); }
}

test('mutations commit atomically, increment revision and reject stale writers', async () => {
  const initial = await readPersonalData();
  const current = await mutatePersonalData((draft) => { draft.settings.mode = 'practice'; });
  assert.equal(current.revision, initial.revision + 1);
  await assert.rejects(
    mutatePersonalData((draft) => { draft.settings.mode = 'stale'; }, { expectedRevision: initial.revision }),
    { name: 'PersonalRevisionConflictError' },
  );
  assert.equal((await readPersonalData()).settings.mode, 'practice');

  await assert.rejects(mutatePersonalData((draft) => {
    draft.settings.partial = true;
    throw new Error('abort this transaction');
  }));
  assert.equal((await readPersonalData()).settings.partial, undefined);
});

test('score and content-addressed asset commit together; bad digest or missing reference writes nothing', async () => {
  const bytes = new TextEncoder().encode('private score bytes');
  const assetId = await hashBytes(bytes);
  const revision = (await readPersonalData()).revision;
  const asset = { id: assetId, mimeType: 'application/octet-stream', bytes: bytes.slice().buffer };
  const score = { ...catalogScore('private:fixture', assetId), source: 'private', sourceId: assetId, assetId };

  await assert.rejects(mutatePersonalData((draft) => { draft.scores.push(score); }, { assets: [{ ...asset, id: '0'.repeat(64) }] }), /摘要不匹配/);
  assert.equal((await readPersonalData()).revision, revision);
  assert.equal(await readAsset(assetId), null);

  await assert.rejects(mutatePersonalData((draft) => { draft.scores.push(score); }), /附件不存在/);
  assert.equal((await readPersonalData()).revision, revision);
  assert.equal(await readAsset(assetId), null);

  const committed = await mutatePersonalData((draft) => { draft.scores.push(score); }, { assets: [asset] });
  assert.equal(committed.revision, revision + 1);
  assert.deepEqual(new Uint8Array((await readAsset(assetId)).bytes), bytes);
  assert.deepEqual(await readPersonalAssetMetadata([assetId]), [{ id: assetId, size: bytes.byteLength, mimeType: 'application/octet-stream' }]);
});

test('shared asset write boundary rejects invalid MIME and attachments beyond the backup size limit', async () => {
  const revision = (await readPersonalData()).revision;
  await assert.rejects(mutatePersonalData(() => {}, {
    assets: [{ id: '0'.repeat(64), mimeType: 'audio/guitar/soundfont', bytes: new ArrayBuffer(1) }],
  }), /附件格式无效/);
  await assert.rejects(mutatePersonalData(() => {}, {
    assets: [{ id: '0'.repeat(64), mimeType: 'application/octet-stream', bytes: new ArrayBuffer(MAX_PERSONAL_ASSET_BYTES + 1) }],
  }), /30 MiB/);
  assert.equal((await readPersonalData()).revision, revision);
  assert.equal(await readAsset('0'.repeat(64)), null);
});

test('legacy projects, browsing history and original files migrate idempotently without deletion', async () => {
  const project = createBlankProject('guitar');
  project.title = 'Old local draft';
  localStorage.setItem(`mimi_studio_draft_${project.id}`, JSON.stringify(project));
  localStorage.setItem('guitarHistoryList', JSON.stringify([{ id: 'tab-1', title: 'History item', artist: 'Artist', url: '/tabs/tab-1', time: 1234 }]));
  const oldBytes = new TextEncoder().encode('old imported source');
  const open = indexedDB.open('mimi-studio-originals', 1);
  const oldDb = await new Promise((resolve, reject) => {
    open.onupgradeneeded = () => open.result.createObjectStore('scoreFiles', { keyPath: 'id' });
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
  await new Promise((resolve, reject) => {
    const tx = oldDb.transaction('scoreFiles', 'readwrite');
    tx.objectStore('scoreFiles').put({ id: 'old-original-id', fileName: 'source.gp', mimeType: 'application/octet-stream', data: oldBytes.slice().buffer, savedAt: 55 });
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
  oldDb.close();

  const migrated = await readPersonalData();
  assert.equal(migrated.migrationCompleted, true);
  assert.equal(migrated.projects[0].title, 'Old local draft');
  assert.equal(migrated.history[0].id, 'tab-1');
  assert.equal(migrated.originals[0].id, 'old-original-id');
  const assetId = await hashBytes(oldBytes);
  assert.deepEqual(new Uint8Array((await readAsset(assetId)).bytes), oldBytes);
  assert.notEqual(localStorage.getItem(`mimi_studio_draft_${project.id}`), null);

  await retryPersonalDataMigration();
  const retried = await readPersonalData();
  assert.equal(retried.projects.length, 1);
  assert.equal(retried.history.length, 1);
  assert.equal(retried.originals.length, 1);
});

test('database v3 upgrade backfills compact asset metadata while preserving v2 asset bytes', async () => {
  const bytes = new TextEncoder().encode('preserved database v2 asset');
  const assetId = await hashBytes(bytes);
  const data = createEmptyPersonalData();
  data.revision = 7;
  data.migrationCompleted = true;
  data.scores.push({ ...catalogScore('private:upgrade-fixture', assetId), source: 'private', sourceId: assetId, assetId });
  const open = indexedDB.open('mimi-personal', 2);
  const db = await new Promise((resolve, reject) => {
    open.onupgradeneeded = () => {
      const database = open.result;
      database.createObjectStore('state', { keyPath: 'key' });
      database.createObjectStore('assets', { keyPath: 'id' });
      const staging = database.createObjectStore('restoreStaging', { keyPath: 'key' });
      staging.createIndex('sessionId', 'sessionId', { unique: false });
    };
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
  await new Promise((resolve, reject) => {
    const tx = db.transaction(['state', 'assets'], 'readwrite');
    tx.objectStore('state').put({ key: 'current', data });
    tx.objectStore('assets').put({ id: assetId, mimeType: 'application/octet-stream', bytes: bytes.slice().buffer });
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
  db.close();

  const upgraded = await readPersonalData();
  assert.equal(upgraded.revision, 7);
  assert.equal(upgraded.scores[0].assetId, assetId);
  assert.deepEqual(await readPersonalAssetMetadata([assetId]), [{ id: assetId, size: bytes.byteLength, mimeType: 'application/octet-stream' }]);
  assert.deepEqual(new Uint8Array((await readAsset(assetId)).bytes), bytes);
});

test('shared writes enforce the 927 MiB referenced-byte budget while allowing existing over-budget data to shrink', async () => {
  const existingBytes = new TextEncoder().encode('existing over-budget asset');
  const existingId = await hashBytes(existingBytes);
  await mutatePersonalData((draft) => {
    draft.scores.push({ ...catalogScore('private:over-budget', existingId), source: 'private', sourceId: existingId, assetId: existingId });
  }, { assets: [{ id: existingId, mimeType: 'application/octet-stream', bytes: existingBytes.slice().buffer }] });
  await setAssetMetadataSize(existingId, MAX_PERSONAL_BACKUP_ASSET_BYTES);
  const before = await readPersonalData();
  const addedBytes = new TextEncoder().encode('new asset should be rejected');
  const addedId = await hashBytes(addedBytes);
  await assert.rejects(mutatePersonalData((draft) => {
    draft.scores.push({ ...catalogScore('private:over-budget-growth', addedId), source: 'private', sourceId: addedId, assetId: addedId });
  }, { assets: [{ id: addedId, mimeType: 'application/octet-stream', bytes: addedBytes.slice().buffer }] }), /927 MiB/);
  assert.equal((await readPersonalData()).revision, before.revision);
  assert.equal(await readAsset(addedId), null);

  const reduced = await mutatePersonalData((draft) => { draft.scores = []; });
  assert.equal(reduced.scores.length, 0);
  assert.equal(reduced.revision, before.revision + 1);
  assert.equal(await readAsset(existingId) !== null, true);
});

test('shared writes reject a new asset when exact v2 packing would exceed 128 volumes', async () => {
  await readPersonalData();
  const open = indexedDB.open('mimi-personal', 3);
  const db = await new Promise((resolve, reject) => { open.onsuccess = () => resolve(open.result); open.onerror = () => reject(open.error); });
  const data = createEmptyPersonalData();
  data.revision = 1;
  data.migrationCompleted = true;
  const mimeType = 'application/octet-stream';
  await new Promise((resolve, reject) => {
    const tx = db.transaction(['state', 'assets', 'assetMetadata'], 'readwrite');
    const assets = tx.objectStore('assets');
    const metadata = tx.objectStore('assetMetadata');
    for (let index = 0; index < MAX_PERSONAL_BACKUP_VOLUMES; index++) {
      const id = index.toString(16).padStart(64, '0');
      data.scores.push({ ...catalogScore(`private:volume-${index}`, id), source: 'private', sourceId: id, assetId: id });
      assets.put({ id, mimeType, bytes: new ArrayBuffer(1) });
      metadata.put({ id, size: 5 * 1024 * 1024, mimeType });
    }
    tx.objectStore('state').put({ key: 'current', data });
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
  db.close();

  const bytes = new Uint8Array(5 * 1024 * 1024);
  for (let index = 0; index < bytes.length; index++) bytes[index] = index & 0xff;
  const id = await hashBytes(bytes);
  await assert.rejects(mutatePersonalData((draft) => {
    draft.scores.push({ ...catalogScore('private:volume-overflow', id), source: 'private', sourceId: id, assetId: id });
  }, { assets: [{ id, mimeType, bytes: bytes.buffer }] }), /128 卷/);
  assert.equal((await readPersonalData()).revision, 1);
  assert.equal(await readAsset(id), null);
});

test('shared writes reject same-volume asset growth in an already over-budget legacy store', async () => {
  await readPersonalData();
  const open = indexedDB.open('mimi-personal', 3);
  const db = await new Promise((resolve, reject) => { open.onsuccess = () => resolve(open.result); open.onerror = () => reject(open.error); });
  const data = createEmptyPersonalData();
  data.revision = 1;
  data.migrationCompleted = true;
  const mimeType = 'application/octet-stream';
  await new Promise((resolve, reject) => {
    const tx = db.transaction(['state', 'assets', 'assetMetadata'], 'readwrite');
    for (let index = 0; index < 129; index++) {
      const id = index.toString(16).padStart(64, '0');
      data.scores.push({ ...catalogScore(`private:legacy-${index}`, id), source: 'private', sourceId: id, assetId: id });
      tx.objectStore('assets').put({ id, mimeType, bytes: new ArrayBuffer(1) });
      tx.objectStore('assetMetadata').put({ id, size: 7 * 1024 * 1024, mimeType });
    }
    tx.objectStore('state').put({ key: 'current', data });
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
  db.close();

  const bytes = new Uint8Array(512 * 1024);
  const id = await hashBytes(bytes);
  assert.ok(id > data.scores.at(-1).assetId);
  await assert.rejects(mutatePersonalData((draft) => {
    draft.scores.push({ ...catalogScore('private:legacy-growth', id), source: 'private', sourceId: id, assetId: id });
  }, { assets: [{ id, mimeType, bytes: bytes.buffer }] }), /仍超过完整备份预算/);
  assert.equal((await readPersonalData()).revision, 1);
  assert.equal(await readAsset(id), null);
  const edited = await mutatePersonalData((draft) => { draft.scores[0].title = '元数据仍可编辑'; });
  assert.equal(edited.scores[0].title, '元数据仍可编辑');
  const reduced = await mutatePersonalData((draft) => { draft.scores.pop(); });
  assert.equal(reduced.scores.length, 128);
});

test('catalog favorites persist without duplication and removal preserves stored score metadata', async () => {
  const input = { id: 'catalog-favorite', title: '完整曲谱', artist: '本地测试', category: 'guitar', format: 'gp', scoreUrl: '/storage/scores/catalog-favorite.gp' };
  await addCatalogFavorite(input);
  await addCatalogFavorite(input);
  const before = await readPersonalData();
  assert.deepEqual(before.favorites, ['catalog:catalog-favorite']);
  assert.equal(before.scores.length, 1);
  await addCatalogFavorite({ ...input, title: '离线演示标题', format: 'xhe', scoreUrl: undefined }, false);
  const after = await readPersonalData();
  assert.deepEqual(after.favorites, []);
  assert.deepEqual(after.scores, before.scores);
});

test('damaged legacy entries stay in place and keep migration incomplete with warnings', async () => {
  localStorage.setItem('mimi_studio_draft_corrupt', '{bad json');
  localStorage.setItem('ukuleleHistoryList', JSON.stringify([{ id: 'uke-1', title: 'Uke', url: '/ukulele/uke-1', time: 10 }]));
  const data = await readPersonalData();
  assert.equal(data.migrationCompleted, false);
  assert.equal(data.history.length, 1);
  assert.match(getPersonalMigrationWarnings().join('\n'), /mimi_studio_draft_corrupt/);
  assert.equal(localStorage.getItem('mimi_studio_draft_corrupt'), '{bad json');
});

test('subscriber failures do not reject a committed write or block other subscribers', async () => {
  let called = 0;
  const unsubscribeFailing = subscribePersonalData(() => { throw new Error('observer failure'); });
  const unsubscribe = subscribePersonalData(() => { called++; });
  try {
    const data = await mutatePersonalData((draft) => { draft.settings.subscribed = true; });
    assert.equal(data.settings.subscribed, true);
    assert.equal(called, 1);
  } finally {
    unsubscribeFailing();
    unsubscribe();
  }
});

test('a committed write broadcasts to other tabs with no local subscriber and closes its temporary channel', async () => {
  const previousBroadcastChannel = globalThis.BroadcastChannel;
  class FakeBroadcastChannel {
    static instances = [];
    constructor(name) { this.name = name; this.closed = false; FakeBroadcastChannel.instances.push(this); }
    postMessage(data) {
      for (const channel of FakeBroadcastChannel.instances) if (channel !== this && !channel.closed && channel.name === this.name) channel.onmessage?.({ data });
    }
    close() { this.closed = true; }
  }
  globalThis.BroadcastChannel = FakeBroadcastChannel;
  const remote = new FakeBroadcastChannel('mimi-personal-updates');
  const messages = [];
  remote.onmessage = (event) => messages.push(event.data);
  try {
    await mutatePersonalData((draft) => { draft.settings.broadcast = true; });
    assert.deepEqual(messages, [{ type: 'personal-data-changed' }]);
    assert.equal(FakeBroadcastChannel.instances.filter((channel) => channel !== remote && channel.closed).length, 1);
  } finally {
    remote.close();
    if (previousBroadcastChannel === undefined) delete globalThis.BroadcastChannel;
    else globalThis.BroadcastChannel = previousBroadcastChannel;
  }
});

test('a quota failure after asset put aborts both the asset and root data writes', async () => {
  await mutatePersonalData((draft) => { draft.settings.before = 'preserve'; });
  const before = await readPersonalData();
  const bytes = new TextEncoder().encode('quota failure asset');
  const assetId = await hashBytes(bytes);
  const asset = { id: assetId, mimeType: 'application/octet-stream', bytes: bytes.slice().buffer };
  const originalPut = IDBObjectStore.prototype.put;
  let calls = 0;
  IDBObjectStore.prototype.put = function putWithQuotaFailure(...args) {
    calls++;
    if (calls === 2) {
      const error = new Error('simulated storage quota');
      error.name = 'QuotaExceededError';
      throw error;
    }
    return originalPut.apply(this, args);
  };
  try {
    await assert.rejects(mutatePersonalData((draft) => {
      draft.scores.push({ ...catalogScore('private:quota', assetId), source: 'private', sourceId: assetId, assetId });
    }, { assets: [asset] }), { name: 'QuotaExceededError' });
  } finally {
    IDBObjectStore.prototype.put = originalPut;
  }
  assert.equal((await readPersonalData()).revision, before.revision);
  assert.equal((await readPersonalData()).settings.before, 'preserve');
  assert.equal(await readAsset(assetId), null);
});

test('resume speed is stored and validated as BPM; external history URLs are rejected', async () => {
  await mutatePersonalData((draft) => {
    draft.scores.push(catalogScore());
    draft.resumes.push({ scoreId: 'catalog:fixture', scoreRevision: 'revision-1', tick: 0, timeMs: 0, speed: 80, capo: 0, transpose: 0, loop: null, trackIndexes: [], metronome: false, countIn: false, updatedAt: 1 });
  });
  assert.equal((await readPersonalData()).resumes[0].speed, 80);
  const unsafe = createEmptyPersonalData();
  unsafe.history.push({ id: 'x', title: 'x', url: 'javascript:alert(1)', time: 1 });
  assert.throws(() => validatePersonalData(unsafe), /安全路径/);
});

test('mutation normalizes nested Svelte-like speed-plan proxies before session merging', async () => {
  const deepProxy = (value, cache = new WeakMap()) => {
    if (!value || typeof value !== 'object') return value;
    if (cache.has(value)) return cache.get(value);
    const proxy = new Proxy(value, { get(target, key, receiver) { return deepProxy(Reflect.get(target, key, receiver), cache); } });
    cache.set(value, proxy);
    return proxy;
  };
  const plan = deepProxy({
    revision: 'speed-r1', nativeAnchorBpm: 400, loopRange: { startTick: 120, endTick: 960 },
    startBpm: 80, targetBpm: 120, stepBpm: 5, lapsPerLevel: 2, currentBpm: 85, completedLaps: 1,
  });
  await mutatePersonalData((draft) => {
    draft.scores.push(catalogScore());
    draft.sessions = [{ ...practiceSession(), speedPlan: plan }];
  });
  const stored = await readPersonalData();
  assert.deepEqual(stored.sessions[0].speedPlan.loopRange, { startTick: 120, endTick: 960 });
  assert.equal(stored.sessions[0].speedPlan.nativeAnchorBpm, 400);
  assert.doesNotThrow(() => structuredClone(stored.sessions[0]));
});

test('a delayed checkpoint after completion cannot write to a later practice session', async () => {
  await seedScoreAndSession([]);
  await mutatePersonalData((draft) => { draft.sessions[0].state = 'active'; });

  let releaseCheckpoint;
  const checkpointGate = new Promise((resolve) => { releaseCheckpoint = resolve; });
  const delayedCheckpoint = checkpointGate.then(() => mutatePersonalData((draft) => {
    updatePracticeSessionIfOpen(draft.sessions, 'session-stable', (latest) => ({
      ...latest,
      slices: [...latest.slices, { id: 'session-stable:epoch-old:1', sequence: 1, epoch: 'epoch-old', startedAt: 200, durationMs: 5000 }],
      updatedAt: 300,
    }), 300);
  }));

  await mutatePersonalData((draft) => {
    draft.sessions[0].state = 'completed';
    draft.sessions[0].endedAt = 250;
    draft.sessions[0].updatedAt = 250;
  });
  await mutatePersonalData((draft) => {
    draft.sessions.push({ ...practiceSession(), id: 'session-next', state: 'active', slices: [], startedAt: 260, updatedAt: 260 });
  });
  releaseCheckpoint();

  await assert.rejects(delayedCheckpoint, /练习会话已结束/);
  const stored = await readPersonalData();
  assert.equal(stored.sessions.find((item) => item.id === 'session-stable').state, 'completed');
  assert.deepEqual(stored.sessions.find((item) => item.id === 'session-stable').slices, []);
  assert.deepEqual(stored.sessions.find((item) => item.id === 'session-next').slices, []);
});

test('playbackRatio is optional for older resumes and rejects values outside AlphaTab bounds', () => {
  const legacy = createEmptyPersonalData();
  legacy.scores.push(catalogScore());
  const resume = { scoreId: 'catalog:fixture', scoreRevision: 'revision-1', tick: 0, timeMs: 0, speed: 80, capo: 0, transpose: 0, loop: null, trackIndexes: [], metronome: false, countIn: false, updatedAt: 1 };
  legacy.resumes.push(resume);
  assert.doesNotThrow(() => validatePersonalData(legacy));
  legacy.resumes[0].playbackRatio = 0.125;
  assert.doesNotThrow(() => validatePersonalData(legacy));
  legacy.resumes[0].playbackRatio = 8;
  assert.doesNotThrow(() => validatePersonalData(legacy));
  legacy.resumes[0].playbackRatio = 8.001;
  assert.throws(() => validatePersonalData(legacy), /playbackRatio/);
  legacy.resumes[0].playbackRatio = Number.NaN;
  assert.throws(() => validatePersonalData(legacy), /playbackRatio/);

  legacy.resumes[0].playbackRatio = 1;
  legacy.resumes[0].trackMix = [{ index: 1023, muted: true, soloed: false, volume: 100, program: 127 }];
  legacy.resumes[0].display = { fontScale: 0.6, chordMode: 'name', scoreDisplayMode: 'tab', numberTab: false, showFretboard: true };
  assert.doesNotThrow(() => validatePersonalData(legacy));
  legacy.resumes[0].trackMix = [{ index: 1024, muted: false, soloed: false, volume: 50, program: 0 }];
  assert.throws(() => validatePersonalData(legacy), /index/);
  legacy.resumes[0].trackMix = [{ index: 0, muted: false, soloed: false, volume: 101, program: 0 }];
  assert.throws(() => validatePersonalData(legacy), /volume/);
  legacy.resumes[0].trackMix = [{ index: 0, muted: false, soloed: false, volume: 50, program: 128 }];
  assert.throws(() => validatePersonalData(legacy), /program/);
  legacy.resumes[0].trackMix = [{ index: 0, muted: false, soloed: false, volume: 50, program: 0, instrumentOverride: true }];
  assert.doesNotThrow(() => validatePersonalData(legacy));
  legacy.resumes[0].trackMix[0].instrumentOverride = 'yes';
  assert.throws(() => validatePersonalData(legacy), /instrumentOverride/);
  legacy.resumes[0].trackMix = [
    { index: 0, muted: false, soloed: false, volume: 50, program: 0 },
    { index: 0, muted: false, soloed: false, volume: 50, program: 0 },
  ];
  assert.throws(() => validatePersonalData(legacy), /唯一/);
  legacy.resumes[0].trackMix = [];
  legacy.resumes[0].display.fontScale = 1.61;
  assert.throws(() => validatePersonalData(legacy), /fontScale/);
  legacy.resumes[0].display.fontScale = 1;
  legacy.resumes[0].display.chordMode = 'other';
  assert.throws(() => validatePersonalData(legacy), /chordMode/);
  legacy.resumes[0].display.chordMode = 'name';
  legacy.resumes[0].display.numberTab = 'yes';
  assert.throws(() => validatePersonalData(legacy), /布尔/);
  legacy.resumes[0].display.numberTab = true;
  legacy.sessions.push({ ...practiceSession(), speedPlan: { revision: 'plan-r1', nativeAnchorBpm: 400, startBpm: 80, targetBpm: 100, stepBpm: 5, lapsPerLevel: 2, currentBpm: 80, completedLaps: 0 } });
  assert.doesNotThrow(() => validatePersonalData(legacy));
  legacy.sessions[0].speedPlan.nativeAnchorBpm = 1001;
  assert.throws(() => validatePersonalData(legacy), /nativeAnchorBpm/);
});
