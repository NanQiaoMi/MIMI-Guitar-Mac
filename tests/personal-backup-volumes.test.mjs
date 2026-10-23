import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test, { afterEach, beforeEach } from 'node:test';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import { countPackedPersonalBackupVolumes, MAX_PERSONAL_BACKUP_ASSET_BYTES, MAX_PERSONAL_BACKUP_VOLUMES } from '../src/lib/personal/limits.ts';
import {
  cancelPersonalBackupVolumesPreview,
  PERSONAL_BACKUP_VOLUME_BYTES,
  preparePersonalBackupVolumes,
  previewPersonalBackupVolumes,
  restorePersonalBackupVolumes,
} from '../src/lib/personal/backupVolumes.ts';
import { hashBytes, mutatePersonalData, readAsset, readPersonalData, retryPersonalDataMigration } from '../src/lib/personal/repository.ts';

const require = createRequire(import.meta.url);
const { IDBFactory, IDBKeyRange } = require('fake-indexeddb');
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
  for (const name of ['window', 'indexedDB', 'localStorage', 'IDBKeyRange']) oldGlobals[name] = globalThis[name];
  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  globalThis.IDBKeyRange = IDBKeyRange;
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();
});

afterEach(() => {
  for (const name of ['window', 'indexedDB', 'localStorage', 'IDBKeyRange']) {
    if (oldGlobals[name] === undefined) delete globalThis[name];
    else globalThis[name] = oldGlobals[name];
  }
});

function makeBytes(length) {
  const data = new Uint8Array(length);
  for (let index = 0; index < length; index++) data[index] = (index * 31 + 19) & 0xff;
  return data;
}

async function seedProjectCache(length = PERSONAL_BACKUP_VOLUME_BYTES + 17) {
  const bytes = makeBytes(length);
  const assetId = await hashBytes(bytes);
  const project = createBlankProject('guitar');
  project.id = 'project-volume-fixture';
  project.title = 'Project cache fixture';
  const score = {
    id: 'project:project-volume-fixture',
    source: 'project',
    sourceId: 'project:project-volume-fixture',
    revision: 'project-cache-r1',
    title: project.title,
    artist: '',
    category: 'guitar',
    format: 'project',
    projectId: project.id,
    assetId,
    createdAt: 10,
    updatedAt: 11,
  };
  await mutatePersonalData((draft) => {
    draft.projects.push(project);
    draft.scores.push(score);
    draft.resumes.push({
      scoreId: score.id, scoreRevision: score.revision, tick: 480, timeMs: 2500, speed: 90, playbackRatio: 1.25,
      trackMix: [{ index: 1, muted: false, soloed: true, volume: 80, program: 24 }],
      display: { fontScale: 1.2, chordMode: 'diagram', scoreDisplayMode: 'tab', numberTab: true, showFretboard: false },
      capo: 0, transpose: 0, loop: null, trackIndexes: [1], metronome: false, countIn: false, updatedAt: 12,
    });
    draft.sessions.push({
      id: 'volume-session', scoreId: score.id, scoreRevision: score.revision, state: 'paused',
      startedAt: 10, updatedAt: 12, timezone: 'UTC', slices: [], note: '',
      speedPlan: { revision: 'plan-r1', nativeAnchorBpm: 400, loopRange: { startTick: 0, endTick: 960 }, startBpm: 80, targetBpm: 100, stepBpm: 5, lapsPerLevel: 2, currentBpm: 80, completedLaps: 0 },
    });
  }, { assets: [{ id: assetId, mimeType: 'application/vnd.mimi.ibe', bytes: bytes.buffer }] });
  return { assetId, bytes, score, project };
}

async function storeStateNames() {
  const request = indexedDB.open('mimi-personal');
  const db = await new Promise((resolve, reject) => { request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
  try { return [...db.objectStoreNames]; } finally { db.close(); }
}

async function setAssetMetadataSize(id, size) {
  const request = indexedDB.open('mimi-personal');
  const db = await new Promise((resolve, reject) => { request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
  try {
    const tx = db.transaction('assetMetadata', 'readwrite');
    tx.objectStore('assetMetadata').put({ id, size, mimeType: 'application/vnd.mimi.ibe' });
    await new Promise((resolve, reject) => { tx.oncomplete = resolve; tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error); });
  } finally { db.close(); }
}

async function seedPrivateScore(scoreId, content) {
  const bytes = new TextEncoder().encode(content);
  const assetId = await hashBytes(bytes);
  const score = {
    id: scoreId, source: 'private', sourceId: assetId, revision: assetId, title: scoreId, artist: 'Local Test',
    category: 'guitar', format: 'ibe', assetId, createdAt: 100, updatedAt: 100,
  };
  await mutatePersonalData((draft) => { draft.scores.push(score); }, {
    assets: [{ id: assetId, mimeType: 'application/vnd.mimi.ibe', bytes: bytes.slice().buffer }],
  });
  return { score, assetId };
}

async function stagedCount() {
  const request = indexedDB.open('mimi-personal');
  const db = await new Promise((resolve, reject) => { request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
  try {
    const tx = db.transaction('restoreStaging', 'readonly');
    return await new Promise((resolve, reject) => {
      const count = tx.objectStore('restoreStaging').count();
      count.onsuccess = () => resolve(count.result);
      count.onerror = () => reject(count.error);
    });
  } finally { db.close(); }
}

async function buildPackage() {
  await seedProjectCache();
  const plan = await preparePersonalBackupVolumes();
  const volumes = [];
  for (let sequence = 1; sequence <= plan.volumeCount; sequence++) volumes.push(await plan.createVolume(sequence));
  return { manifest: plan.manifest, volumes, plan };
}

test('v2 native volumes round-trip project IBE cache and playback resume/plan metadata', async () => {
  const sourceDb = indexedDB;
  const sourceStorage = localStorage;
  const { assetId, bytes, score, project } = await seedProjectCache();
  const plan = await preparePersonalBackupVolumes();
  assert.equal(plan.volumeCount, 2);
  const first = await plan.createVolume(1);
  const second = await plan.createVolume(2);
  assert.equal(first.size <= PERSONAL_BACKUP_VOLUME_BYTES + 256 * 1024 + 12, true);
  assert.equal(second.size <= PERSONAL_BACKUP_VOLUME_BYTES + 256 * 1024 + 12, true);

  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();
  const preview = await previewPersonalBackupVolumes(plan.manifest, [second, first]);
  assert.equal(preview.data.scores[0].source, 'project');
  assert.equal(preview.data.scores[0].projectId, project.id);
  assert.equal(preview.data.scores[0].assetId, assetId);
  assert.equal(preview.data.sessions[0].speedPlan.nativeAnchorBpm, 400);
  assert.equal(preview.data.resumes[0].playbackRatio, 1.25);
  assert.deepEqual(preview.data.resumes[0].trackMix, [{ index: 1, muted: false, soloed: true, volume: 80, program: 24 }]);
  assert.deepEqual(preview.data.resumes[0].display, { fontScale: 1.2, chordMode: 'diagram', scoreDisplayMode: 'tab', numberTab: true, showFretboard: false });
  const restored = await restorePersonalBackupVolumes(preview, preview.expectedRevision);
  assert.equal(restored.scores[0].id, score.id);
  assert.equal(restored.projects[0].id, project.id);
  assert.equal(restored.sessions[0].speedPlan.nativeAnchorBpm, 400);
  assert.equal(restored.resumes[0].playbackRatio, 1.25);
  assert.deepEqual(restored.resumes[0].trackMix, [{ index: 1, muted: false, soloed: true, volume: 80, program: 24 }]);
  assert.deepEqual(restored.resumes[0].display, { fontScale: 1.2, chordMode: 'diagram', scoreDisplayMode: 'tab', numberTab: true, showFretboard: false });
  assert.deepEqual(new Uint8Array((await readAsset(assetId)).bytes), bytes);
  assert.equal(await stagedCount(), 0);

  globalThis.indexedDB = sourceDb;
  globalThis.localStorage = sourceStorage;
});

test('missing, mixed-snapshot and tampered volumes fail before changing personal data', async () => {
  const sourceDb = indexedDB;
  const sourceStorage = localStorage;
  const firstPackage = await buildPackage();
  await mutatePersonalData((draft) => { draft.settings.secondSnapshot = true; });
  const secondPlan = await preparePersonalBackupVolumes();
  const secondVolumes = [];
  for (let sequence = 1; sequence <= secondPlan.volumeCount; sequence++) secondVolumes.push(await secondPlan.createVolume(sequence));
  const secondPackage = { manifest: secondPlan.manifest, volumes: secondVolumes };

  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();
  const before = await readPersonalData();
  await assert.rejects(previewPersonalBackupVolumes(firstPackage.manifest, []), /需要 2 卷/);
  await assert.rejects(previewPersonalBackupVolumes(firstPackage.manifest, [firstPackage.volumes[0], secondPackage.volumes[1]]), /快照不一致/);
  const corruptBytes = new Uint8Array(await firstPackage.volumes[0].arrayBuffer());
  corruptBytes[corruptBytes.length - 1] ^= 0xff;
  await assert.rejects(previewPersonalBackupVolumes(firstPackage.manifest, [new Blob([corruptBytes]), firstPackage.volumes[1]]), /SHA-256/);
  assert.equal((await readPersonalData()).revision, before.revision);
  assert.equal((await readPersonalData()).scores.length, 0);
  assert.equal(await stagedCount(), 0);

  globalThis.indexedDB = sourceDb;
  globalThis.localStorage = sourceStorage;
});

test('cancelled and stale v2 restores clear only their staging data and never overwrite local edits', async () => {
  const sourceDb = indexedDB;
  const sourceStorage = localStorage;
  const pkg = await buildPackage();

  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();
  const cancelled = new AbortController();
  cancelled.abort();
  await assert.rejects(previewPersonalBackupVolumes(pkg.manifest, pkg.volumes, cancelled.signal), /取消/);
  assert.equal(await stagedCount(), 0);

  const preview = await previewPersonalBackupVolumes(pkg.manifest, pkg.volumes);
  await mutatePersonalData((draft) => { draft.settings.keep = 'newer local data'; });
  await assert.rejects(restorePersonalBackupVolumes(preview, preview.expectedRevision), /预期 revision|revision/);
  assert.equal((await readPersonalData()).settings.keep, 'newer local data');
  assert.equal((await readPersonalData()).scores.length, 0);
  assert.equal(await stagedCount(), 0);

  const cleanPreview = await previewPersonalBackupVolumes(pkg.manifest, pkg.volumes);
  await cancelPersonalBackupVolumesPreview(cleanPreview);
  assert.equal(await stagedCount(), 0);
  assert.deepEqual(await storeStateNames(), ['assetMetadata', 'assets', 'restoreStaging', 'state']);

  globalThis.indexedDB = sourceDb;
  globalThis.localStorage = sourceStorage;
});

test('export plan rejects data changed between preparation and a later volume download', async () => {
  await seedProjectCache();
  const plan = await preparePersonalBackupVolumes();
  await mutatePersonalData((draft) => { draft.settings.changed = true; });
  await assert.rejects(plan.createVolume(1), /发生变化/);
  plan.cancel();
  await assert.rejects(plan.createVolume(1), /已取消/);
});

test('packed volume budget follows sorted 8 MiB next-fit chunks and caps referenced attachment bytes', () => {
  const fiveMiBAssets = (count) => Array.from({ length: count }, (_, index) => ({ id: String(index).padStart(64, '0'), size: 5 * 1024 * 1024 }));
  assert.equal(countPackedPersonalBackupVolumes(fiveMiBAssets(MAX_PERSONAL_BACKUP_VOLUMES)), MAX_PERSONAL_BACKUP_VOLUMES);
  assert.equal(countPackedPersonalBackupVolumes(fiveMiBAssets(MAX_PERSONAL_BACKUP_VOLUMES + 1)), MAX_PERSONAL_BACKUP_VOLUMES + 1);
  assert.equal(MAX_PERSONAL_BACKUP_ASSET_BYTES / 1024 / 1024, 927);
});

test('v2 restore applies the referenced-byte growth budget and keeps pre-existing over-budget assets', async () => {
  const targetDb = indexedDB;
  const targetStorage = localStorage;
  const { assetId: existingId } = await seedPrivateScore('private:existing-budget', 'existing local bytes');
  await setAssetMetadataSize(existingId, MAX_PERSONAL_BACKUP_ASSET_BYTES);
  const before = await readPersonalData();

  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();
  await seedPrivateScore('private:incoming-budget', 'incoming backup bytes');
  const plan = await preparePersonalBackupVolumes();
  const volumes = [];
  for (let sequence = 1; sequence <= plan.volumeCount; sequence++) volumes.push(await plan.createVolume(sequence));

  globalThis.indexedDB = targetDb;
  globalThis.localStorage = targetStorage;
  const preview = await previewPersonalBackupVolumes(plan.manifest, volumes);
  await assert.rejects(restorePersonalBackupVolumes(preview, preview.expectedRevision), /927 MiB/);
  assert.equal((await readPersonalData()).revision, before.revision);
  assert.deepEqual((await readPersonalData()).scores.map((score) => score.id), ['private:existing-budget']);
  assert.equal(await stagedCount(), 0);
});
