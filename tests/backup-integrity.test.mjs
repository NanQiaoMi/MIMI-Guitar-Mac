import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test, { after, before } from 'node:test';
import {
  calculateBackupMetrics,
  quickValidateBackup,
  verifyBackupIntegrity,
} from '../src/lib/personal/backupIntegrity.ts';
import { PERSONAL_BACKUP_VOLUME_FORMAT, PERSONAL_BACKUP_VOLUME_BYTES, preparePersonalBackupVolumes } from '../src/lib/personal/backupVolumes.ts';
import { hashBytes, mutatePersonalData, readAsset, readPersonalData, retryPersonalDataMigration } from '../src/lib/personal/repository.ts';
import { MAX_PERSONAL_BACKUP_ENTITIES, MAX_PERSONAL_BACKUP_VOLUMES } from '../src/lib/personal/limits.ts';

const require = createRequire(import.meta.url);
const { IDBFactory, IDBKeyRange } = require('fake-indexeddb');
const globalNames = ['window', 'indexedDB', 'localStorage', 'IDBKeyRange'];
const oldGlobals = new Map();
let backupManifest;
let backupVolumes;
let backupPlan;
let fixtureAsset;

function TestStorage() {
  this.values = new Map();
  Object.defineProperty(this, 'length', { get: () => this.values.size });
  this.key = (index) => [...this.values.keys()][index] ?? null;
  this.getItem = (key) => this.values.get(key) ?? null;
  this.setItem = (key, value) => this.values.set(String(key), String(value));
  this.removeItem = (key) => this.values.delete(key);
}

before(async () => {
  for (const name of globalNames) {
    oldGlobals.set(name, Object.hasOwn(globalThis, name)
      ? { present: true, value: globalThis[name] }
      : { present: false });
  }

  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  globalThis.IDBKeyRange = IDBKeyRange;
  globalThis.localStorage = new TestStorage();
  await retryPersonalDataMigration();

  const bytes = makeBytes(PERSONAL_BACKUP_VOLUME_BYTES + 17);
  const assetId = await hashBytes(bytes);
  fixtureAsset = { id: assetId, bytes };
  await mutatePersonalData((draft) => {
    draft.scores.push({
      id: 'private:backup-integrity-fixture',
      source: 'private',
      sourceId: assetId,
      revision: assetId,
      title: '吉他练习完整性校验',
      artist: 'Local Test',
      category: 'guitar',
      format: 'ibe',
      assetId,
      createdAt: 100,
      updatedAt: 101,
    });
  }, {
    assets: [{ id: assetId, mimeType: 'application/vnd.mimi.ibe', bytes: bytes.buffer }],
  });

  backupPlan = await preparePersonalBackupVolumes();
  const wrapper = JSON.parse(await backupPlan.manifest.text());
  assert.equal(wrapper.format, PERSONAL_BACKUP_VOLUME_FORMAT);
  backupManifest = wrapper.manifest;
  backupVolumes = [];
  for (let sequence = 1; sequence <= backupPlan.volumeCount; sequence++) {
    backupVolumes.push(await backupPlan.createVolume(sequence));
  }
  assert.equal(backupVolumes.length, 2, 'fixture should exercise multiple real volume files');
});

after(() => {
  for (const name of globalNames) {
    const saved = oldGlobals.get(name);
    if (saved?.present) globalThis[name] = saved.value;
    else delete globalThis[name];
  }
  backupPlan?.cancel();
});

function makeBytes(length) {
  const bytes = new Uint8Array(length);
  for (let index = 0; index < length; index++) bytes[index] = (index * 31 + 19) & 0xff;
  return bytes;
}

async function stagedCount() {
  const request = indexedDB.open('mimi-personal');
  const db = await new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  try {
    const transaction = db.transaction('restoreStaging', 'readonly');
    const countRequest = transaction.objectStore('restoreStaging').count();
    return await new Promise((resolve, reject) => {
      countRequest.onsuccess = () => resolve(countRequest.result);
      countRequest.onerror = () => reject(countRequest.error);
    });
  } finally {
    db.close();
  }
}

function watchIndexedDbWrites() {
  const factory = globalThis.indexedDB;
  const writeTransactions = [];
  const wrappedDatabases = new Map();

  function wrapDatabase(db) {
    if (wrappedDatabases.has(db)) return;
    const originalTransaction = db.transaction;
    const hadOwnTransaction = Object.hasOwn(db, 'transaction');
    db.transaction = function (...args) {
      const mode = args[1];
      if (mode && mode !== 'readonly') writeTransactions.push({ stores: args[0], mode });
      return originalTransaction.apply(this, args);
    };
    wrappedDatabases.set(db, () => {
      if (hadOwnTransaction) db.transaction = originalTransaction;
      else delete db.transaction;
    });
  }

  globalThis.indexedDB = new Proxy(factory, {
    get(target, property) {
      if (property === 'open') {
        return (...args) => {
          const request = target.open(...args);
          request.addEventListener('success', () => wrapDatabase(request.result), { once: true });
          return request;
        };
      }
      const value = Reflect.get(target, property, target);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });

  return {
    writeTransactions,
    restore() {
      globalThis.indexedDB = factory;
      for (const restoreDatabase of wrappedDatabases.values()) restoreDatabase();
    },
  };
}

test('accepts a real generated backup and all integrity details pass', async () => {
  const result = await verifyBackupIntegrity(backupManifest, backupVolumes, backupManifest.data);

  assert.equal(result.isValid, true, result.errors.join('\n'));
  assert.deepEqual(Object.values(result.details), [true, true, true, true, true, true]);
});

test('rejects a manifest whose snapshot digest no longer matches', async () => {
  const tamperedManifest = structuredClone(backupManifest);
  tamperedManifest.snapshotId = 'tampered-snapshot';

  const result = await verifyBackupIntegrity(tamperedManifest, backupVolumes, tamperedManifest.data);
  assert.equal(result.isValid, false);
  assert.equal(result.details.manifestChecksum, false);
});

test('rejects payload tampering and a missing volume', async () => {
  const corruptedBytes = new Uint8Array(await backupVolumes[0].arrayBuffer());
  corruptedBytes[corruptedBytes.length - 1] ^= 0xff;
  const corrupted = new Blob([corruptedBytes], { type: backupVolumes[0].type });

  const payloadResult = await verifyBackupIntegrity(backupManifest, [corrupted, backupVolumes[1]], backupManifest.data);
  assert.equal(payloadResult.isValid, false);
  assert.equal(payloadResult.details.assetChecksums, false);

  const missingVolumeResult = await verifyBackupIntegrity(backupManifest, [backupVolumes[0]], backupManifest.data);
  assert.equal(missingVolumeResult.isValid, false);
  assert.equal(missingVolumeResult.details.volumeCount, false);
});

test('rejects entity-count and asset-reference mismatches', async () => {
  const wrongCounts = structuredClone(backupManifest);
  wrongCounts.counts.scores += 1;
  const countResult = await verifyBackupIntegrity(wrongCounts, backupVolumes, wrongCounts.data);
  assert.equal(countResult.isValid, false);
  assert.equal(countResult.details.entityCounts, false);

  const missingAsset = structuredClone(backupManifest);
  missingAsset.assets = [];
  const referenceResult = await verifyBackupIntegrity(missingAsset, backupVolumes, missingAsset.data);
  assert.equal(referenceResult.isValid, false);
  assert.equal(referenceResult.details.assetReferences, false);
});

test('rejects supplied data that differs from the manifest snapshot', async () => {
  const differentData = structuredClone(backupManifest.data);
  differentData.scores[0].title += '（已修改）';

  const result = await verifyBackupIntegrity(backupManifest, backupVolumes, differentData);
  assert.equal(result.isValid, false);
  assert.equal(result.details.dataChecksum, false);
});

test('validates real multi-volume backups when files are supplied out of order', async () => {
  const result = await verifyBackupIntegrity(backupManifest, [...backupVolumes].reverse(), backupManifest.data);

  assert.equal(result.isValid, true, result.errors.join('\n'));
  assert.equal(result.details.volumeCount, true);
  assert.equal(result.details.assetChecksums, true);
});

test('quick structural validation rejects unsupported format and count limits', () => {
  const unsupportedFormat = structuredClone(backupManifest);
  unsupportedFormat.formatVersion += 1;
  assert.equal(quickValidateBackup(unsupportedFormat).valid, false);

  const tooManyVolumes = structuredClone(backupManifest);
  tooManyVolumes.volumes = Array.from({ length: MAX_PERSONAL_BACKUP_VOLUMES + 1 }, () => structuredClone(backupManifest.volumes[0]));
  assert.equal(quickValidateBackup(tooManyVolumes).valid, false);

  const tooManyEntities = structuredClone(backupManifest);
  tooManyEntities.counts.scores = MAX_PERSONAL_BACKUP_ENTITIES + 1;
  assert.equal(quickValidateBackup(tooManyEntities).valid, false);
});

test('metrics count the UTF-8 wrapped manifest and only the selected volumes', () => {
  const selectedVolumes = [backupVolumes[1]];
  const metrics = calculateBackupMetrics(backupManifest, selectedVolumes);
  const wrappedManifest = JSON.stringify({ format: PERSONAL_BACKUP_VOLUME_FORMAT, manifest: backupManifest });
  const expectedSize = new TextEncoder().encode(wrappedManifest).byteLength + selectedVolumes.reduce((sum, volume) => sum + volume.size, 0);
  const expectedEntities = Object.entries(backupManifest.counts)
    .filter(([name]) => name !== 'assets')
    .reduce((sum, [, count]) => sum + count, 0);

  assert.match(wrappedManifest, /吉他练习完整性校验/);
  assert.equal(metrics.totalSize, expectedSize);
  assert.equal(metrics.entityCount, expectedEntities);
  assert.equal(metrics.assetCount, backupManifest.counts.assets);
  assert.equal(metrics.assetBytes, backupManifest.assetBytes);
  assert.equal(metrics.volumeCount, backupManifest.volumes.length);
  assert.equal(metrics.selectedVolumeCount, 1);
  assert.equal(metrics.selectedSizesMatch, false);

  const completeMetrics = calculateBackupMetrics(backupManifest, backupVolumes);
  assert.equal(completeMetrics.selectedVolumeCount, backupManifest.volumes.length);
  assert.equal(completeMetrics.selectedSizesMatch, true);
});

test('integrity verification is read-only and does not change revision, assets, or restore staging', async () => {
  const before = await readPersonalData();
  const beforeStageCount = await stagedCount();
  const beforeAsset = await readAsset(fixtureAsset.id);
  const writeSpy = watchIndexedDbWrites();

  try {
    const result = await verifyBackupIntegrity(backupManifest, backupVolumes, backupManifest.data);
    assert.equal(result.isValid, true, result.errors.join('\n'));
  } finally {
    writeSpy.restore();
  }

  const afterData = await readPersonalData();
  const afterAsset = await readAsset(fixtureAsset.id);
  assert.equal(afterData.revision, before.revision);
  assert.deepEqual(new Uint8Array(afterAsset.bytes), new Uint8Array(beforeAsset.bytes));
  assert.equal(await stagedCount(), beforeStageCount);
  assert.deepEqual(writeSpy.writeTransactions, [], 'verification must not open a writable IndexedDB transaction');
});
