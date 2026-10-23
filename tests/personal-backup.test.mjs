import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test, { afterEach, beforeEach } from 'node:test';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import { exportPersonalBackup, previewBackup, restoreBackup } from '../src/lib/personal/backup.ts';
import { hashBytes, mutatePersonalData, readPersonalData, retryPersonalDataMigration } from '../src/lib/personal/repository.ts';
import { createEmptyPersonalData, validatePersonalData } from '../src/lib/personal/validation.ts';

const require = createRequire(import.meta.url);
const { IDBFactory } = require('fake-indexeddb');
const oldGlobals = {};

function TestStorage() {
  this.values = new Map();
  Object.defineProperty(this, 'length', { get: () => this.values.size });
  this.key = (index) => [...this.values.keys()][index] ?? null;
  this.getItem = (key) => this.values.get(key) ?? null;
  this.setItem = (key, value) => this.values.set(String(key), String(value));
  this.removeItem = (key) => this.values.delete(key);
}

beforeEach(async () => {
  for (const name of ['window', 'indexedDB', 'localStorage']) oldGlobals[name] = globalThis[name];
  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();
});
afterEach(() => {
  for (const name of ['window', 'indexedDB', 'localStorage']) {
    if (oldGlobals[name] === undefined) delete globalThis[name];
    else globalThis[name] = oldGlobals[name];
  }
});

function bytes(text) { return new TextEncoder().encode(text); }
test('incomplete legacy migration cannot produce a supposedly complete backup', async () => {
  localStorage.setItem('mimi_studio_draft_broken', '{broken');
  await mutatePersonalData((draft) => { draft.migrationCompleted = false; });
  await retryPersonalDataMigration();
  await assert.rejects(exportPersonalBackup(), /尚未完整迁移/);
  assert.equal((await readPersonalData()).migrationCompleted, false);
  assert.equal(localStorage.getItem('mimi_studio_draft_broken'), '{broken');
});

function scoreFixture(id, revision, projectId) {
  return { id, source: 'catalog', sourceId: id, revision, title: 'Shared score', artist: 'Artist', category: 'guitar', format: 'ibe', scoreUrl: '/storage/shared.ibe', projectId, createdAt: 1, updatedAt: 10 };
}
function sessionFixture(slices) {
  return { id: 'stable-session', scoreId: 'catalog:shared', scoreRevision: 'r2', state: 'paused', startedAt: 1, updatedAt: 20, timezone: 'UTC', slices, note: '' };
}

test('JSON backup round-trips optional undefined project fields and rejects tampering', async () => {
  const project = createBlankProject('guitar');
  project.album = undefined;
  project.source = { kind: 'file', id: 'original-id', fileName: 'source.gp', format: 'gp', title: undefined };
  const assetBytes = bytes('project source');
  const id = await hashBytes(assetBytes);
  await mutatePersonalData((draft) => {
    draft.projects.push(project);
    draft.originals.push({ id: 'original-id', fileName: 'source.gp', mimeType: 'application/octet-stream', assetId: id, savedAt: 1 });
  }, { assets: [{ id, mimeType: 'application/octet-stream', bytes: assetBytes.buffer }] });

  const blob = await exportPersonalBackup();
  const preview = await previewBackup(blob);
  assert.equal(preview.data.projects[0].source.title, undefined);
  assert.deepEqual(new Uint8Array(preview.assets[0].bytes), assetBytes);
  const tamperedText = (await blob.text()).replace('project source', 'changed source');
  // JSON stores the bytes as Base64, so mutate a real payload field instead.
  const parsed = JSON.parse(await blob.text());
  parsed.payload.data.projects[0].title = 'tampered';
  await assert.rejects(previewBackup(new Blob([JSON.stringify(parsed)])), /SHA-256/);
  assert.ok(tamperedText.length > 0);
});

test('restore accepts Svelte-like proxied preview data and still rejects edits after preview', async () => {
  const destinationDb = globalThis.indexedDB;
  const destinationStorage = globalThis.localStorage;
  try {
    globalThis.indexedDB = new IDBFactory();
    globalThis.localStorage = new TestStorage();
    await mutatePersonalData((draft) => { draft.scores.push(scoreFixture('proxied-score', 'r1')); });
    const backup = await exportPersonalBackup();
    globalThis.indexedDB = destinationDb;
    globalThis.localStorage = destinationStorage;

    const preview = await previewBackup(backup);
    const cache = new WeakMap();
    const deepProxy = (value) => {
      if (!value || typeof value !== 'object') return value;
      if (cache.has(value)) return cache.get(value);
      const proxy = new Proxy(value, { get(target, key, receiver) { return deepProxy(Reflect.get(target, key, receiver)); } });
      cache.set(value, proxy);
      return proxy;
    };
    const proxiedPreview = { ...preview, data: deepProxy(preview.data), manifest: deepProxy(preview.manifest) };
    const restored = await restoreBackup(proxiedPreview, preview.expectedRevision);
    assert.equal(restored.scores[0].title, 'Shared score');

    const nextPreview = await previewBackup(backup);
    const tampered = { ...nextPreview, data: deepProxy(nextPreview.data) };
    tampered.data.scores[0].title = 'Changed after preview';
    await assert.rejects(restoreBackup(tampered, nextPreview.expectedRevision), /摘要已改变|内容已改变/);
    assert.equal((await readPersonalData()).scores[0].title, 'Shared score');
  } finally {
    globalThis.indexedDB = destinationDb;
    globalThis.localStorage = destinationStorage;
  }
});

test('v1 backup round-trips deep proxied practice state and optional playbackRatio', async () => {
  const deepProxy = (value, cache = new WeakMap()) => {
    if (!value || typeof value !== 'object') return value;
    if (cache.has(value)) return cache.get(value);
    const proxy = new Proxy(value, { get(target, key, receiver) { return deepProxy(Reflect.get(target, key, receiver), cache); } });
    cache.set(value, proxy);
    return proxy;
  };
  const plan = deepProxy({
    revision: 'speed-r2', nativeAnchorBpm: 400, loopRange: { startTick: 240, endTick: 1440 },
    startBpm: 80, targetBpm: 110, stepBpm: 5, lapsPerLevel: 2, currentBpm: 85, completedLaps: 1,
  });
  await mutatePersonalData((draft) => {
    const score = scoreFixture('catalog:proxy-practice', 'r1');
    draft.scores.push(score);
    draft.resumes.push({ scoreId: score.id, scoreRevision: score.revision, tick: 300, timeMs: 1500, speed: 90, playbackRatio: 0.75, trackMix: [{ index: 2, muted: false, soloed: true, volume: 73, program: 29 }], display: { fontScale: 1.25, chordMode: 'diagram', scoreDisplayMode: 'mixed', numberTab: true, showFretboard: false }, capo: 0, transpose: 0, loop: null, trackIndexes: [], metronome: false, countIn: false, updatedAt: 20 });
    draft.sessions.push({ id: 'proxy-speed-session', scoreId: score.id, scoreRevision: score.revision, state: 'paused', startedAt: 10, updatedAt: 20, timezone: 'UTC', slices: [], note: '', speedPlan: plan });
  });
  const backup = await exportPersonalBackup();
  const preview = await previewBackup(backup);
  assert.equal(preview.data.resumes[0].playbackRatio, 0.75);
  assert.deepEqual(preview.data.resumes[0].trackMix, [{ index: 2, muted: false, soloed: true, volume: 73, program: 29 }]);
  assert.deepEqual(preview.data.resumes[0].display, { fontScale: 1.25, chordMode: 'diagram', scoreDisplayMode: 'mixed', numberTab: true, showFretboard: false });
  assert.deepEqual(preview.data.sessions[0].speedPlan.loopRange, { startTick: 240, endTick: 1440 });
  assert.equal(preview.data.sessions[0].speedPlan.nativeAnchorBpm, 400);
});

test('restore remaps a conflicting original ID in the imported studio source reference', async () => {
  const destinationDb = globalThis.indexedDB;
  const destinationStorage = globalThis.localStorage;
  const sourceDb = new IDBFactory();
  const sourceStorage = new TestStorage();
  globalThis.indexedDB = sourceDb;
  globalThis.localStorage = sourceStorage;

  const sourceBytes = bytes('backup original bytes');
  const sourceAssetId = await hashBytes(sourceBytes);
  const project = createBlankProject('guitar');
  project.source = { kind: 'file', id: 'same-original', fileName: 'backup.gp', format: 'gp' };
  await mutatePersonalData((draft) => {
    draft.projects.push(project);
    draft.originals.push({ id: 'same-original', fileName: 'backup.gp', mimeType: 'application/octet-stream', assetId: sourceAssetId, savedAt: 10 });
  }, { assets: [{ id: sourceAssetId, mimeType: 'application/octet-stream', bytes: sourceBytes.buffer }] });
  const backup = await exportPersonalBackup();

  globalThis.indexedDB = destinationDb;
  globalThis.localStorage = destinationStorage;
  const existingBytes = bytes('existing original bytes');
  const existingAssetId = await hashBytes(existingBytes);
  const existingProject = createBlankProject('ukulele');
  existingProject.source = { kind: 'file', id: 'same-original', fileName: 'existing.gp', format: 'gp' };
  await mutatePersonalData((draft) => {
    draft.projects.push(existingProject);
    draft.originals.push({ id: 'same-original', fileName: 'existing.gp', mimeType: 'application/octet-stream', assetId: existingAssetId, savedAt: 5 });
  }, { assets: [{ id: existingAssetId, mimeType: 'application/octet-stream', bytes: existingBytes.buffer }] });

  const preview = await previewBackup(backup);
  const restored = await restoreBackup(preview, preview.expectedRevision);
  const imported = restored.projects.find((item) => item.id === project.id);
  assert.ok(imported);
  assert.notEqual(imported.source.id, 'same-original');
  const referenced = restored.originals.find((item) => item.id === imported.source.id);
  assert.equal(referenced.assetId, sourceAssetId);
  assert.deepEqual(new Uint8Array((await (await import('../src/lib/personal/repository.ts')).readAsset(referenced.assetId)).bytes), sourceBytes);
  const after = await readPersonalData();
  assert.equal(after.originals.length, 2);
  const repeatedPreview = await previewBackup(backup);
  const repeated = await restoreBackup(repeatedPreview, repeatedPreview.expectedRevision);
  assert.equal(repeated.originals.length, 2);
  assert.equal(repeated.projects.length, 2);
  const repeatedProject = repeated.projects.find((item) => item.id === project.id);
  assert.equal(repeatedProject.source.id, imported.source.id);
});

test('restore rejects a preview after the local revision changes and leaves the new write intact', async () => {
  const backup = await exportPersonalBackup();
  const preview = await previewBackup(backup);
  await mutatePersonalData((draft) => { draft.settings.afterPreview = 'keep me'; });
  await assert.rejects(restoreBackup(preview, preview.expectedRevision), /revision .*当前为/);
  const current = await readPersonalData();
  assert.equal(current.settings.afterPreview, 'keep me');
});

test('strict backup validation rejects project fields that the studio normalizer would silently discard', () => {
  const project = createBlankProject('guitar');
  project.onclick = 'javascript:alert(1)';
  const data = createEmptyPersonalData();
  data.projects.push(project);
  assert.throws(() => validatePersonalData(data, { strictProjects: true }), /不支持的字段/);
});

test('re-importing one conflict backup reuses score, project, and original copies without duplicating its session', async () => {
  const destinationDb = globalThis.indexedDB;
  const destinationStorage = globalThis.localStorage;
  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  const incomingDb = globalThis.indexedDB;
  const incomingStorage = globalThis.localStorage;

  const originalBytes = bytes('incoming original');
  const incomingAssetId = await hashBytes(originalBytes);
  const incomingProject = createBlankProject('guitar');
  incomingProject.id = 'shared-project';
  incomingProject.title = 'Incoming Project';
  incomingProject.source = { kind: 'file', id: 'shared-original', fileName: 'incoming.gp', format: 'gp' };
  await mutatePersonalData((draft) => {
    draft.scores.push(scoreFixture('catalog:shared', 'r2', incomingProject.id));
    draft.favorites.push('catalog:shared');
    draft.practiceItems.push({ scoreId: 'catalog:shared', status: 'practicing', note: '', order: 0, updatedAt: 10 });
    draft.projects.push(incomingProject);
    draft.originals.push({ id: 'shared-original', fileName: 'incoming.gp', mimeType: 'application/octet-stream', assetId: incomingAssetId, savedAt: 10 });
    draft.sessions.push(sessionFixture([{ id: 'slice-1', epoch: 'epoch-a', sequence: 1, startedAt: 10, durationMs: 4_000 }]));
  }, { assets: [{ id: incomingAssetId, mimeType: 'application/octet-stream', bytes: originalBytes.slice().buffer }] });
  const backup = await exportPersonalBackup();

  globalThis.indexedDB = destinationDb;
  globalThis.localStorage = destinationStorage;
  const oldBytes = bytes('existing original');
  const oldAssetId = await hashBytes(oldBytes);
  const existingProject = createBlankProject('ukulele');
  existingProject.id = 'shared-project';
  existingProject.title = 'Existing Project';
  existingProject.source = { kind: 'file', id: 'shared-original', fileName: 'existing.gp', format: 'gp' };
  await mutatePersonalData((draft) => {
    draft.scores.push(scoreFixture('catalog:shared', 'r1', existingProject.id));
    draft.projects.push(existingProject);
    draft.originals.push({ id: 'shared-original', fileName: 'existing.gp', mimeType: 'application/octet-stream', assetId: oldAssetId, savedAt: 5 });
  }, { assets: [{ id: oldAssetId, mimeType: 'application/octet-stream', bytes: oldBytes.slice().buffer }] });

  const firstPreview = await previewBackup(backup);
  const first = await restoreBackup(firstPreview, firstPreview.expectedRevision);
  const firstScore = first.scores.find((item) => item.revision === 'r2');
  const firstProject = first.projects.find((item) => item.title === 'Incoming Project');
  const expectedCounts = [first.scores.length, first.projects.length, first.originals.length, first.favorites.length, first.practiceItems.length, first.sessions.length];
  assert.equal(firstScore.projectId, firstProject.id);
  assert.equal(firstProject.source.id, first.originals.find((item) => item.assetId === incomingAssetId).id);
  assert.equal(first.sessions[0].slices.reduce((sum, item) => sum + item.durationMs, 0), 4_000);

  const repeatedPreview = await previewBackup(backup);
  const repeated = await restoreBackup(repeatedPreview, repeatedPreview.expectedRevision);
  assert.deepEqual([repeated.scores.length, repeated.projects.length, repeated.originals.length, repeated.favorites.length, repeated.practiceItems.length, repeated.sessions.length], expectedCounts);
  assert.equal(repeated.sessions.length, 1);
  assert.equal(repeated.sessions[0].slices.reduce((sum, item) => sum + item.durationMs, 0), 4_000);
  assert.equal(repeated.scores.find((item) => item.revision === 'r2').id, firstScore.id);
  assert.equal(repeated.projects.find((item) => item.title === 'Incoming Project').id, firstProject.id);

  globalThis.indexedDB = incomingDb;
  globalThis.localStorage = incomingStorage;
});

test('two checkpoint-only backup packages merge by sequence in either order without double counting', async () => {
  const destinationDb = globalThis.indexedDB;
  const destinationStorage = globalThis.localStorage;
  const packageBlobs = [];
  for (const slice of [
    { id: 'slice-1', epoch: 'epoch-a', sequence: 1, startedAt: 10, durationMs: 3_000 },
    { id: 'slice-2', epoch: 'epoch-a', sequence: 2, startedAt: 13, durationMs: 5_000 },
  ]) {
    globalThis.indexedDB = new IDBFactory();
    globalThis.localStorage = new TestStorage();
    await mutatePersonalData((draft) => {
      draft.scores.push(scoreFixture('catalog:shared', 'r1'));
      draft.sessions.push(sessionFixture([slice]));
    });
    packageBlobs.push(await exportPersonalBackup());
  }

  async function restoreOrder(order) {
    globalThis.indexedDB = new IDBFactory();
    globalThis.localStorage = new TestStorage();
    for (const index of order) {
      const preview = await previewBackup(packageBlobs[index]);
      await restoreBackup(preview, preview.expectedRevision);
    }
    const result = await readPersonalData();
    assert.equal(result.sessions.length, 1);
    assert.deepEqual(result.sessions[0].slices.map((slice) => slice.sequence), [1, 2]);
    return result.sessions[0].slices.reduce((sum, slice) => sum + slice.durationMs, 0);
  }
  assert.equal(await restoreOrder([0, 1]), 8_000);
  assert.equal(await restoreOrder([1, 0]), 8_000);
  globalThis.indexedDB = destinationDb;
  globalThis.localStorage = destinationStorage;
});
