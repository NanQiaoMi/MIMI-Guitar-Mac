import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test, { afterEach, beforeEach } from 'node:test';
import {
  createPracticeFragment,
  deletePracticeFragment,
  listPracticeFragments,
  PracticeFragmentConflictError,
  updatePracticeFragment,
  validatePracticeFragmentApply,
} from '../src/lib/personal/practiceFragments.ts';
import { canonicalJson, dataCounts, exportPersonalBackup, mergePersonalBackupData, PERSONAL_BACKUP_FORMAT, previewBackup, restoreBackup } from '../src/lib/personal/backup.ts';
import { hashBytes, mutatePersonalData, readAsset, readPersonalData, retryPersonalDataMigration } from '../src/lib/personal/repository.ts';
import { cancelPersonalBackupVolumesPreview, PERSONAL_BACKUP_VOLUME_FORMAT, preparePersonalBackupVolumes, previewPersonalBackupVolumes, restorePersonalBackupVolumes } from '../src/lib/personal/backupVolumes.ts';
import { createEmptyPersonalData, normalizePersonalData, validatePersonalData } from '../src/lib/personal/validation.ts';

const require = createRequire(import.meta.url);
const { IDBFactory, IDBKeyRange } = require('fake-indexeddb');
const oldGlobals = {};
const revision = 'a'.repeat(64);

function TestStorage() {
  this.values = new Map();
  Object.defineProperty(this, 'length', { get: () => this.values.size });
  this.key = (index) => [...this.values.keys()][index] ?? null;
  this.getItem = (key) => this.values.get(key) ?? null;
  this.setItem = (key, value) => this.values.set(String(key), String(value));
  this.removeItem = (key) => this.values.delete(key);
}

beforeEach(async () => {
  for (const name of ['window', 'indexedDB', 'localStorage', 'IDBKeyRange']) oldGlobals[name] = globalThis[name];
  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  globalThis.IDBKeyRange = IDBKeyRange;
  await retryPersonalDataMigration();
  await mutatePersonalData((draft) => {
    draft.scores.push({ id: 'score-1', source: 'private', sourceId: 'score-bytes', revision, title: 'Score', artist: 'Artist', category: 'guitar', format: 'ibe', createdAt: 1, updatedAt: 1 });
  });
});

afterEach(() => {
  for (const name of ['window', 'indexedDB', 'localStorage', 'IDBKeyRange']) {
    if (oldGlobals[name] === undefined) delete globalThis[name];
    else globalThis[name] = oldGlobals[name];
  }
});

const input = (overrides = {}) => ({
  scoreId: 'score-1', scoreRevision: revision, name: '  Verse 1  ', note: 'practice slowly',
  range: { startTick: 120, endTick: 960 },
  speed: { nativeAnchorBpm: 120, startBpm: 60, targetBpm: 90, stepBpm: 5, lapsPerLevel: 2 },
  ...overrides,
});

test('fragment creation binds the exact stored score revision and validates all reusable inputs', async () => {
  const created = await createPracticeFragment(input(), 100);
  assert.equal(created.name, 'Verse 1');
  assert.equal(created.scoreRevision, revision);
  assert.deepEqual(created.range, { startTick: 120, endTick: 960 });
  assert.equal(created.createdAt, 100);
  assert.equal((await readPersonalData()).practiceFragments.length, 1);

  const mutable = input({ name: 'snapshot', range: { startTick: 10, endTick: 20 } });
  const pending = createPracticeFragment(mutable, 101);
  mutable.name = 'changed after call';
  mutable.range.startTick = 19;
  const snapshotted = await pending;
  assert.equal(snapshotted.name, 'snapshot');
  assert.deepEqual(snapshotted.range, { startTick: 10, endTick: 20 });

  await assert.rejects(createPracticeFragment(input({ scoreRevision: 'b'.repeat(64) }), 101), /版本已变化/);
  await assert.rejects(createPracticeFragment(input({ scoreRevision: 'unverified' }), 101), /可信/);
  await assert.rejects(createPracticeFragment(input({ name: 'x'.repeat(121) }), 101), /名称/);
  await assert.rejects(createPracticeFragment(input({ note: 'x'.repeat(5001) }), 101), /备注/);
  await assert.rejects(createPracticeFragment(input({ range: { startTick: 1.5, endTick: 2 } }), 101), /A-B/);
  await assert.rejects(createPracticeFragment(input({ speed: { ...input().speed, targetBpm: 301 } }), 101), /提速参数/);
  assert.equal((await readPersonalData()).practiceFragments.length, 2);
});

test('metadata updates use compare-and-swap, monotonic timestamps, and tombstone deletion', async () => {
  const created = await createPracticeFragment(input(), 200);
  const updated = await updatePracticeFragment(created.id, created.updatedAt, { name: 'Refrain', note: '' }, 100);
  assert.equal(updated.updatedAt, created.updatedAt + 1);
  assert.equal(updated.note, '');
  await assert.rejects(updatePracticeFragment(created.id, created.updatedAt, { name: 'stale' }, 300), PracticeFragmentConflictError);

  await deletePracticeFragment(created.id, updated.updatedAt, 150);
  const current = await readPersonalData();
  assert.equal(listPracticeFragments(current, 'score-1').length, 0);
  assert.equal(listPracticeFragments(current, 'score-1', true)[0].deletedAt, updated.updatedAt + 1);
  await assert.rejects(deletePracticeFragment(created.id, updated.updatedAt, 400), PracticeFragmentConflictError);
  await assert.rejects(updatePracticeFragment(created.id, updated.updatedAt + 1, { name: 'revive?' }, 500), PracticeFragmentConflictError);
});

test('application rejects deleted, stale-revision, and out-of-score ranges without mutation', async () => {
  const created = await createPracticeFragment(input(), 300);
  assert.doesNotThrow(() => validatePracticeFragmentApply(created, 'score-1', revision, 960));
  assert.throws(() => validatePracticeFragmentApply(created, 'other-score', revision, 1000), /其他曲谱/);
  assert.throws(() => validatePracticeFragmentApply(created, 'score-1', 'c'.repeat(64), 1000), /旧版本/);
  assert.throws(() => validatePracticeFragmentApply(created, 'score-1', revision, 959), /超出/);
  await deletePracticeFragment(created.id, created.updatedAt, 301);
  const deleted = listPracticeFragments(await readPersonalData(), 'score-1', true)[0];
  assert.throws(() => validatePracticeFragmentApply(deleted, 'score-1', revision, 1000), /已删除/);
});

test('legacy schema-1 snapshots validate unchanged and normalize only into a new schema-2 object', () => {
  const current = createEmptyPersonalData();
  const { practiceFragments: _ignored, ...legacy } = current;
  legacy.schemaVersion = 1;
  validatePersonalData(legacy);
  const normalized = normalizePersonalData(legacy);
  assert.equal(legacy.schemaVersion, 1);
  assert.equal(Object.hasOwn(legacy, 'practiceFragments'), false);
  assert.equal(normalized.schemaVersion, 2);
  assert.deepEqual(normalized.practiceFragments, []);
  assert.throws(() => validatePersonalData({ ...legacy, practiceFragments: [{ id: 'untrusted' }] }), /不支持 practiceFragments/);
  const missingCurrent = { ...current };
  delete missingCurrent.practiceFragments;
  assert.throws(() => validatePersonalData(missingCurrent), /practiceFragments/);
});

function scoreFixture(id, scoreRevision, updatedAt = 10) {
  return { id, source: 'private', sourceId: id, revision: scoreRevision, title: `Score ${scoreRevision.slice(0, 4)}`, artist: '', category: 'guitar', format: 'ibe', createdAt: 1, updatedAt };
}

function fragmentFixture(overrides = {}) {
  return {
    id: 'fragment-stable', scoreId: 'score-merge', scoreRevision: 'a'.repeat(64), name: 'Main riff', note: '',
    range: { startTick: 0, endTick: 960 },
    speed: { nativeAnchorBpm: 120, startBpm: 60, targetBpm: 90, stepBpm: 5, lapsPerLevel: 2 },
    createdAt: 1, updatedAt: 10, ...overrides,
  };
}

function dataWith(score, fragments = []) {
  const data = createEmptyPersonalData();
  data.scores.push(score);
  data.practiceFragments.push(...fragments);
  return data;
}

test('restoring an old active fragment cannot resurrect a matching tombstone after the score row moved to a new revision', () => {
  const oldRevision = 'a'.repeat(64);
  const newRevision = 'b'.repeat(64);
  const current = dataWith(scoreFixture('score-merge', newRevision), [fragmentFixture({ scoreRevision: oldRevision, updatedAt: 100, deletedAt: 100 })]);
  const oldBackup = dataWith(scoreFixture('score-merge', oldRevision, 20), [fragmentFixture({ scoreRevision: oldRevision, updatedAt: 90 })]);
  const merged = mergePersonalBackupData(current, oldBackup);
  assert.equal(merged.practiceFragments.length, 1);
  assert.equal(merged.practiceFragments[0].deletedAt, 100);
  assert.equal(merged.practiceFragments[0].scoreId, 'score-merge');
});

test('conflicting score and fragment identities get stable IDs, LWW updates, and idempotent tombstone restores', () => {
  const revA = 'a'.repeat(64);
  const revB = 'b'.repeat(64);
  const current = dataWith(scoreFixture('score-merge', revA), [fragmentFixture({ scoreRevision: revA, updatedAt: 10 })]);
  const backupAt = (updatedAt, name = `saved-${updatedAt}`, deleted = false) => dataWith(
    scoreFixture('score-merge', revB, updatedAt),
    [fragmentFixture({ scoreRevision: revB, updatedAt, name, ...(deleted ? { deletedAt: updatedAt } : {}) })],
  );

  const first = mergePersonalBackupData(current, backupAt(20));
  assert.equal(first.practiceFragments.length, 2);
  const branchId = first.practiceFragments.find((fragment) => fragment.scoreRevision === revB).id;
  const branchScoreId = first.practiceFragments.find((fragment) => fragment.scoreRevision === revB).scoreId;
  assert.notEqual(branchId, 'fragment-stable');
  assert.notEqual(branchScoreId, 'score-merge');

  const newer = mergePersonalBackupData(first, backupAt(30, 'renamed-current'));
  assert.equal(newer.practiceFragments.length, 2);
  assert.equal(newer.practiceFragments.find((fragment) => fragment.id === branchId).name, 'renamed-current');
  assert.equal(newer.scores.filter((score) => score.revision === revB).length, 1);
  const repeatOld = mergePersonalBackupData(newer, backupAt(20));
  assert.equal(repeatOld.practiceFragments.length, 2);
  assert.equal(repeatOld.practiceFragments.find((fragment) => fragment.id === branchId).name, 'renamed-current');

  const deleted = mergePersonalBackupData(repeatOld, backupAt(40, 'deleted', true));
  const afterOldRestore = mergePersonalBackupData(deleted, backupAt(20));
  assert.equal(afterOldRestore.practiceFragments.length, 2);
  assert.equal(afterOldRestore.practiceFragments.find((fragment) => fragment.id === branchId).deletedAt, 40);
});

test('a newer remapped branch tombstone wins over a repeated earlier source-side candidate', () => {
  const revA = 'a'.repeat(64);
  const revB = 'b'.repeat(64);
  const current = dataWith(scoreFixture('score-merge', revA), [fragmentFixture({ scoreRevision: revA, updatedAt: 50 })]);
  const backup = dataWith(scoreFixture('score-merge', revB, 30), [fragmentFixture({ scoreRevision: revA, updatedAt: 100 })]);
  const first = mergePersonalBackupData(current, backup);
  const branch = first.practiceFragments.find((fragment) => fragment.scoreId !== 'score-merge');
  assert.ok(branch);
  branch.updatedAt = 400;
  branch.deletedAt = 400;

  const repeated = mergePersonalBackupData(first, backup);
  assert.equal(repeated.practiceFragments.length, 2);
  assert.equal(repeated.practiceFragments.find((fragment) => fragment.id === branch.id).deletedAt, 400);
});

test('schema-1 JSON preview preserves the original signed object, then restore upgrades only persisted state', async () => {
  const currentData = await readPersonalData();
  const empty = createEmptyPersonalData();
  const { practiceFragments: _discard, ...legacyData } = empty;
  legacyData.schemaVersion = 1;
  const payload = { data: legacyData, assets: [] };
  const payloadSha256 = await hashBytes(new TextEncoder().encode(canonicalJson(payload)));
  const legacyCounts = {
    scores: legacyData.scores.length, favorites: legacyData.favorites.length, practiceItems: legacyData.practiceItems.length,
    resumes: legacyData.resumes.length, sessions: legacyData.sessions.length, projects: legacyData.projects.length,
    originals: legacyData.originals.length, history: legacyData.history.length, assets: 0,
  };
  assert.deepEqual(dataCounts(legacyData, 0), legacyCounts);
  assert.equal(Object.hasOwn(legacyCounts, 'practiceFragments'), false);
  const manifest = {
    formatVersion: 1, schemaVersion: 1, revision: legacyData.revision, generatedAt: new Date(0).toISOString(),
    counts: legacyCounts, assets: [], payloadSha256, assetBytes: 0,
  };
  const file = new Blob([JSON.stringify({ format: PERSONAL_BACKUP_FORMAT, manifest, payload })]);
  const preview = await previewBackup(file);
  assert.equal(preview.data.schemaVersion, 1);
  assert.equal(Object.hasOwn(preview.data, 'practiceFragments'), false);
  const restored = await restoreBackup(preview, preview.expectedRevision);
  assert.equal(restored.schemaVersion, 2);
  assert.deepEqual(restored.practiceFragments, []);
  assert.equal(currentData.revision + 1, restored.revision);

  const volumeBase = {
    formatVersion: 2, snapshotId: 'fixture-schema1-0001', schemaVersion: 1, revision: legacyData.revision,
    generatedAt: new Date(0).toISOString(), counts: legacyCounts, assetBytes: 0, assets: [], volumes: [], data: legacyData,
  };
  const snapshotSha256 = await hashBytes(new TextEncoder().encode(canonicalJson(volumeBase)));
  const volumeManifest = new Blob([JSON.stringify({ format: PERSONAL_BACKUP_VOLUME_FORMAT, manifest: { ...volumeBase, snapshotSha256 } })]);
  const volumePreview = await previewPersonalBackupVolumes(volumeManifest, []);
  assert.equal(volumePreview.data.schemaVersion, 1);
  assert.equal(Object.hasOwn(volumePreview.data, 'practiceFragments'), false);
  await cancelPersonalBackupVolumesPreview(volumePreview);
});

test('schema-2 JSON and v2 volume snapshots preserve fragments and include tombstones in signed counts', async () => {
  const fragment = await createPracticeFragment(input(), 500);
  await deletePracticeFragment(fragment.id, fragment.updatedAt, 501);
  const persisted = await readPersonalData();
  assert.equal(dataCounts(persisted, 0).practiceFragments, 1);

  const jsonPreview = await previewBackup(await exportPersonalBackup());
  assert.equal(jsonPreview.data.schemaVersion, 2);
  assert.equal(jsonPreview.manifest.counts.practiceFragments, 1);
  assert.equal(jsonPreview.data.practiceFragments[0].deletedAt, 501);
  const jsonRestored = await restoreBackup(jsonPreview, jsonPreview.expectedRevision);
  assert.equal(jsonRestored.practiceFragments.length, 1);
  assert.equal(jsonRestored.practiceFragments[0].deletedAt, 501);

  const plan = await preparePersonalBackupVolumes();
  const volumePreview = await previewPersonalBackupVolumes(plan.manifest, []);
  assert.equal(volumePreview.data.schemaVersion, 2);
  assert.equal(volumePreview.manifest.counts.practiceFragments, 1);
  assert.equal(volumePreview.data.practiceFragments[0].deletedAt, 501);
  const volumeRestored = await restorePersonalBackupVolumes(volumePreview, volumePreview.expectedRevision);
  assert.equal(volumeRestored.practiceFragments.length, 1);
  assert.equal(volumeRestored.practiceFragments[0].deletedAt, 501);
  plan.cancel();
  await cancelPersonalBackupVolumesPreview(volumePreview);
});

test('fragment tombstones count toward the shared 10,000-entity write budget', async () => {
  await mutatePersonalData((draft) => {
    draft.practiceFragments = Array.from({ length: 9_999 }, (_, index) => fragmentFixture({
      id: `budget-fragment-${index}`,
      scoreId: 'score-1',
      updatedAt: 1,
      deletedAt: 1,
    }));
  });
  assert.equal((await readPersonalData()).practiceFragments.length, 9_999);
  await assert.rejects(createPracticeFragment(input(), 2), /10,000 个实体预算/);
  assert.equal((await readPersonalData()).practiceFragments.length, 9_999);
});

test('v2 staged restore keeps data and asset unchanged on stale CAS or abort, then commits both together', async () => {
  const sourceDatabase = globalThis.indexedDB;
  const sourceStorage = globalThis.localStorage;
  const assetBytes = new TextEncoder().encode('small atomic restore asset');
  const assetId = await hashBytes(assetBytes);
  await mutatePersonalData((draft) => {
    draft.scores[0].assetId = assetId;
    draft.scores[0].sourceId = assetId;
  }, { assets: [{ id: assetId, mimeType: 'application/octet-stream', bytes: assetBytes.slice().buffer }] });
  await createPracticeFragment(input(), 600);
  const plan = await preparePersonalBackupVolumes();
  const volume = await plan.createVolume(1);
  const manifest = plan.manifest;

  try {
    globalThis.indexedDB = new IDBFactory();
    globalThis.localStorage = new TestStorage();
    await retryPersonalDataMigration();
    await mutatePersonalData((draft) => { draft.settings.localOnly = 'keep'; });

    const stalePreview = await previewPersonalBackupVolumes(manifest, [volume]);
    await mutatePersonalData((draft) => { draft.settings.afterPreview = true; });
    await assert.rejects(restorePersonalBackupVolumes(stalePreview, stalePreview.expectedRevision), /其他页面更新/);
    let destination = await readPersonalData();
    assert.equal(destination.settings.localOnly, 'keep');
    assert.equal(destination.settings.afterPreview, true);
    assert.equal(destination.scores.length, 0);
    assert.equal(destination.practiceFragments.length, 0);
    assert.equal(await readAsset(assetId), null);

    const abortedPreview = await previewPersonalBackupVolumes(manifest, [volume]);
    const controller = new AbortController();
    controller.abort();
    await assert.rejects(restorePersonalBackupVolumes(abortedPreview, abortedPreview.expectedRevision, controller.signal), /已取消/);
    destination = await readPersonalData();
    assert.equal(destination.settings.afterPreview, true);
    assert.equal(destination.scores.length, 0);
    assert.equal(destination.practiceFragments.length, 0);
    assert.equal(await readAsset(assetId), null);

    const validPreview = await previewPersonalBackupVolumes(manifest, [volume]);
    const committed = await restorePersonalBackupVolumes(validPreview, validPreview.expectedRevision);
    assert.equal(committed.practiceFragments.length, 1);
    assert.equal(committed.scores[0].assetId, assetId);
    assert.deepEqual(new Uint8Array((await readAsset(assetId)).bytes), assetBytes);
  } finally {
    plan.cancel();
    globalThis.indexedDB = sourceDatabase;
    globalThis.localStorage = sourceStorage;
  }
});
