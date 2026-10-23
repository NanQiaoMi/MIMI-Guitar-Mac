import { normalizeStudioProject } from '../studio/studioScoreModel.ts';
import type { PersonalAsset, PersonalData, PersonalMutationOptions, OriginalReference } from './types.ts';
import { createEmptyPersonalData, isSafeLocalPath, normalizePersonalData, PERSONAL_SCHEMA_VERSION, validatePersonalData } from './validation.ts';
import {
  isValidPersonalMimeType,
  MAX_PERSONAL_ASSET_BYTES,
  MAX_PERSONAL_BACKUP_ASSETS,
  MAX_PERSONAL_BACKUP_ASSET_BYTES,
  MAX_PERSONAL_BACKUP_ENTITIES,
  MAX_PERSONAL_BACKUP_VOLUMES,
  MAX_PERSONAL_DATA_JSON_BYTES,
  countPackedPersonalBackupVolumes,
  enforcePersonalBackupAssetGrowthBudget,
} from './limits.ts';

const DATABASE_NAME = 'mimi-personal';
const DATABASE_VERSION = 3;
const STATE_STORE = 'state';
const ASSET_STORE = 'assets';
const ASSET_METADATA_STORE = 'assetMetadata';
const RESTORE_STAGE_STORE = 'restoreStaging';
const STATE_KEY = 'current';
const LEGACY_DRAFT_PREFIX = 'mimi_studio_draft_';
const LEGACY_HISTORY_KEYS = ['guitarHistoryList', 'ukuleleHistoryList'];
const LEGACY_ORIGINALS_DATABASE = 'mimi-studio-originals';
const LEGACY_ORIGINALS_STORE = 'scoreFiles';

interface RestoreStagingRecord {
  key: string;
  sessionId: string;
  assetId: string;
  mimeType: string;
  bytes: ArrayBuffer;
  size: number;
  createdAt: number;
}

export type PersonalRestoreTransform = (current: PersonalData) => PersonalData;

export interface PersonalRestoreAssetMetadata {
  id: string;
  size: number;
  mimeType: string;
}

export class PersonalRevisionConflictError extends Error {
  readonly expectedRevision: number;
  readonly actualRevision: number;

  constructor(expectedRevision: number, actualRevision: number) {
    super(`个人资料已在其他页面更新（预期 revision ${expectedRevision}，当前为 ${actualRevision}）；请重新读取后再试`);
    this.name = 'PersonalRevisionConflictError';
    this.expectedRevision = expectedRevision;
    this.actualRevision = actualRevision;
  }
}

export class PersonalStorageUnavailableError extends Error {
  constructor(message = '当前环境未开放 IndexedDB，个人数据没有保存') {
    super(message);
    this.name = 'PersonalStorageUnavailableError';
  }
}

let channel: BroadcastChannel | null = null;
const subscribers = new Set<() => void>();
const upgradeSubscribers = new Set<(version: number) => void>();
let migrationAttempt: Promise<void> | null = null;
let migrationDeferred = false;
let lastMigrationWarnings: string[] = [];

function getChannel(): BroadcastChannel | null {
  if (typeof window === 'undefined' || typeof BroadcastChannel === 'undefined') return null;
  if (channel) return channel;
  try {
    channel = new BroadcastChannel('mimi-personal-updates');
    channel.onmessage = () => {
      for (const callback of subscribers) {
        try { callback(); } catch { /* observers cannot prevent the rest from refreshing */ }
      }
    };
    return channel;
  } catch {
    return null;
  }
}

function notifySubscribers(): void {
  for (const callback of subscribers) {
    try { callback(); } catch { /* observers cannot change a committed write into a reported failure */ }
  }
  try {
    if (subscribers.size) {
      getChannel()?.postMessage({ type: 'personal-data-changed' });
    } else if (typeof window !== 'undefined' && typeof BroadcastChannel !== 'undefined') {
      const temporaryChannel = new BroadcastChannel('mimi-personal-updates');
      try { temporaryChannel.postMessage({ type: 'personal-data-changed' }); }
      finally { temporaryChannel.close(); }
    }
  } catch { /* a notification failure cannot change the committed transaction result */ }
}

export function subscribePersonalData(callback: () => void): () => void {
  subscribers.add(callback);
  getChannel();
  return () => {
    subscribers.delete(callback);
    if (!subscribers.size && channel) {
      try { channel.close(); } catch { /* no listeners remain */ }
      finally { channel = null; }
    }
  };
}

/** Notifies open UI when a newer app version upgrades the personal database. */
export function subscribePersonalStorageUpgrade(callback: (version: number) => void): () => void {
  upgradeSubscribers.add(callback);
  return () => upgradeSubscribers.delete(callback);
}

function notifyPersonalStorageUpgrade(version: number): void {
  for (const callback of upgradeSubscribers) {
    try { callback(version); } catch { /* an observer cannot interfere with the upgrade */ }
  }
}

export function getPersonalMigrationWarnings(): string[] {
  return [...lastMigrationWarnings];
}

function openDatabase(): Promise<IDBDatabase> {
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') {
    return Promise.reject(new PersonalStorageUnavailableError());
  }
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
    let settled = false;
    request.onupgradeneeded = (event) => {
      const db = request.result;
      const upgradeTransaction = request.transaction;
      if (!db.objectStoreNames.contains(STATE_STORE)) db.createObjectStore(STATE_STORE, { keyPath: 'key' });
      if (!db.objectStoreNames.contains(ASSET_STORE)) db.createObjectStore(ASSET_STORE, { keyPath: 'id' });
      const metadataStore = db.objectStoreNames.contains(ASSET_METADATA_STORE)
        ? upgradeTransaction!.objectStore(ASSET_METADATA_STORE)
        : db.createObjectStore(ASSET_METADATA_STORE, { keyPath: 'id' });
      if (event.oldVersion < 3) {
        const cursorRequest = upgradeTransaction!.objectStore(ASSET_STORE).openCursor();
        cursorRequest.onsuccess = () => {
          const cursor = cursorRequest.result;
          if (!cursor) return;
          const record = cursor.value as { id?: unknown; mimeType?: unknown; bytes?: unknown };
          const bytes = record.bytes;
          const size = bytes instanceof ArrayBuffer
            ? bytes.byteLength
            : ArrayBuffer.isView(bytes) ? bytes.byteLength : -1;
          metadataStore.put({ id: record.id, size, mimeType: record.mimeType });
          cursor.continue();
        };
      }
      if (!db.objectStoreNames.contains(RESTORE_STAGE_STORE)) {
        const staging = db.createObjectStore(RESTORE_STAGE_STORE, { keyPath: 'key' });
        staging.createIndex('sessionId', 'sessionId', { unique: false });
      }
    };
    request.onsuccess = () => {
      const db = request.result;
      db.onversionchange = (event) => {
        db.close();
        notifyPersonalStorageUpgrade((event as IDBVersionChangeEvent).newVersion ?? DATABASE_VERSION);
      };
      if (settled) db.close();
      else { settled = true; resolve(db); }
    };
    request.onerror = () => {
      if (settled) return;
      settled = true;
      const cause = request.error;
      reject(cause?.name === 'VersionError'
        ? new Error('个人资料库已由新版本升级，请刷新页面后再继续')
        : cause ?? new Error('无法打开个人资料库'));
    };
    request.onblocked = () => {
      if (settled) return;
      settled = true;
      reject(new Error('个人资料库升级被其他页面阻止，请关闭旧标签后重试'));
    };
  });
}

function requestValue<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('个人资料读取失败'));
  });
}

function transactionResult<T>(transaction: IDBTransaction, result: () => T): Promise<T> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => {
      try { resolve(result()); } catch (error) { reject(error); }
    };
    transaction.onerror = () => reject(transaction.error ?? new Error('个人资料事务失败'));
    transaction.onabort = () => reject(transaction.error ?? new Error('个人资料事务已回滚'));
  });
}

async function readStateWithoutMigration(): Promise<PersonalData> {
  const db = await openDatabase();
  try {
    const transaction = db.transaction(STATE_STORE, 'readonly');
    const record = await requestValue(transaction.objectStore(STATE_STORE).get(STATE_KEY)) as { data?: unknown } | undefined;
    return record?.data ? normalizePersonalData(record.data) : createEmptyPersonalData();
  } finally {
    db.close();
  }
}

function toBytes(value: ArrayBuffer | ArrayBufferView): Uint8Array {
  if (value instanceof ArrayBuffer) return new Uint8Array(value.slice(0));
  return new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
}

export async function hashBytes(bytes: Uint8Array): Promise<string> {
  if (!globalThis.crypto?.subtle) throw new PersonalStorageUnavailableError('当前浏览器缺少 SHA-256 支持，个人附件未保存');
  const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function assetReferences(data: PersonalData): Set<string> {
  const ids = new Set<string>();
  for (const score of data.scores) {
    if (score.assetId) ids.add(score.assetId);
    if (score.originalAssetId) ids.add(score.originalAssetId);
  }
  for (const original of data.originals) ids.add(original.assetId);
  return ids;
}

function jsonPlainPersonalData(value: PersonalData): PersonalData {
  try {
    const serialized = JSON.stringify(value);
    if (serialized === undefined) throw new Error('not serializable');
    return JSON.parse(serialized) as PersonalData;
  } catch {
    throw new Error('个人资料必须可序列化为普通 JSON 对象；个人数据没有保存');
  }
}

function personalEntityCount(data: PersonalData): number {
  return data.scores.length + data.favorites.length + data.practiceItems.length + data.practiceFragments.length + data.resumes.length + data.sessions.length + data.projects.length + data.originals.length + data.history.length;
}

function serializedPersonalDataBytes(data: PersonalData): number {
  const serialized = JSON.stringify(data);
  return serialized === undefined ? Number.POSITIVE_INFINITY : new TextEncoder().encode(serialized).byteLength;
}

function enforceWriteBackupBudget(current: PersonalData, proposed: PersonalData): void {
  const previousEntities = personalEntityCount(current);
  const nextEntities = personalEntityCount(proposed);
  if (nextEntities > MAX_PERSONAL_BACKUP_ENTITIES && nextEntities > previousEntities) {
    throw new Error(`个人资料超过完整备份的 ${MAX_PERSONAL_BACKUP_ENTITIES.toLocaleString()} 个实体预算；请先整理或减少现有条目，本次新增未保存`);
  }
  const previousAssetCount = assetReferences(current).size;
  const nextAssetCount = assetReferences(proposed).size;
  if (nextAssetCount > MAX_PERSONAL_BACKUP_ASSETS && nextAssetCount > previousAssetCount) {
    throw new Error(`个人资料超过完整备份的 ${MAX_PERSONAL_BACKUP_ASSETS} 份附件预算；请先整理引用，本次新增未保存`);
  }
  const previousBytes = serializedPersonalDataBytes(current);
  const nextBytes = serializedPersonalDataBytes(proposed);
  if (nextBytes > MAX_PERSONAL_DATA_JSON_BYTES && nextBytes > previousBytes) {
    throw new Error('个人资料清单超过 60 MiB 写入预算（为完整备份的 manifest 与分块摘要保留 4 MiB）；本次新增未保存，请先整理资料');
  }
}

function enforceAssetWriteBackupBudget(
  currentData: PersonalData,
  proposedData: PersonalData,
  currentBytes: number,
  proposedBytes: number,
  currentVolumes: number,
  proposedVolumes: number,
): void {
  enforcePersonalBackupAssetGrowthBudget({
    assetBytes: currentBytes,
    assetCount: assetReferences(currentData).size,
    volumeCount: currentVolumes,
    entityCount: personalEntityCount(currentData),
    dataJsonBytes: serializedPersonalDataBytes(currentData),
  }, {
    assetBytes: proposedBytes,
    assetCount: assetReferences(proposedData).size,
    volumeCount: proposedVolumes,
    entityCount: personalEntityCount(proposedData),
    dataJsonBytes: serializedPersonalDataBytes(proposedData),
  });
}

interface PersonalAssetMetadata {
  id: string;
  size: number;
  mimeType: string;
}

function mergeSessionCheckpoints(previous: PersonalData['sessions'], proposed: PersonalData['sessions']): PersonalData['sessions'] {
  const merged = new Map(proposed.map((session) => [session.id, structuredClone(session)]));
  for (const oldSession of previous) {
    const nextSession = merged.get(oldSession.id);
    if (!nextSession) {
      merged.set(oldSession.id, structuredClone(oldSession));
      continue;
    }
    if (oldSession.scoreId !== nextSession.scoreId || oldSession.scoreRevision !== nextSession.scoreRevision) {
      throw new Error(`练习记录 ${oldSession.id} 已关联不同曲谱版本，不能覆盖；请另存为独立会话`);
    }
    const slices = new Map(oldSession.slices.map((slice) => [slice.id, slice]));
    for (const slice of nextSession.slices) {
      const oldSlice = slices.get(slice.id);
      if (!oldSlice || slice.sequence > oldSlice.sequence || (slice.sequence === oldSlice.sequence && slice.durationMs > oldSlice.durationMs)) slices.set(slice.id, slice);
    }
    const bySequence = new Map<string, typeof nextSession.slices[number]>();
    for (const slice of slices.values()) {
      const key = `${slice.epoch}\0${slice.sequence}`;
      const old = bySequence.get(key);
      if (!old || slice.durationMs > old.durationMs) bySequence.set(key, slice);
    }
    const latest = nextSession.updatedAt >= oldSession.updatedAt ? nextSession : oldSession;
    merged.set(oldSession.id, {
      ...structuredClone(latest),
      slices: [...bySequence.values()].sort((a, b) => a.epoch.localeCompare(b.epoch) || a.sequence - b.sequence),
    });
  }
  return [...merged.values()];
}

async function prepareAssets(assets: PersonalAsset[] = []): Promise<PersonalAsset[]> {
  if (!Array.isArray(assets) || assets.length > MAX_PERSONAL_BACKUP_ASSETS) throw new Error('单次保存附件最多 500 份；个人资料没有保存');
  const output: PersonalAsset[] = [];
  const ids = new Set<string>();
  for (const asset of assets) {
    if (!asset || typeof asset.id !== 'string' || !isValidPersonalMimeType(asset.mimeType) || !(asset.bytes instanceof ArrayBuffer)) {
      throw new Error('附件格式无效，个人资料没有保存');
    }
    if (asset.bytes.byteLength > MAX_PERSONAL_ASSET_BYTES) throw new Error('单附件超过 30 MiB 备份预算；个人资料没有保存');
    const bytes = new Uint8Array(asset.bytes.slice(0));
    const actualId = await hashBytes(bytes);
    if (actualId !== asset.id) throw new Error(`附件摘要不匹配：${asset.id}`);
    if (ids.has(asset.id)) throw new Error(`附件 ID 重复：${asset.id}`);
    ids.add(asset.id);
    output.push({ id: asset.id, mimeType: asset.mimeType || 'application/octet-stream', bytes: bytes.buffer });
  }
  return output;
}

async function commitMutation(mutator: (draft: PersonalData) => void, options: PersonalMutationOptions = {}): Promise<PersonalData> {
  const assets = await prepareAssets(options.assets);
  const db = await openDatabase();
  try {
    const transaction = db.transaction([STATE_STORE, ASSET_STORE, ASSET_METADATA_STORE], 'readwrite');
    const stateStore = transaction.objectStore(STATE_STORE);
    const assetStore = transaction.objectStore(ASSET_STORE);
    const metadataStore = transaction.objectStore(ASSET_METADATA_STORE);
    const currentRequest = stateStore.get(STATE_KEY);
    const assetKeysRequest = assetStore.getAllKeys();
    let current: PersonalData | null = null;
    let existingAssetIds = new Set<string>();
    let currentReady = false;
    let keysReady = false;
    let started = false;
    let next: PersonalData | null = null;
    let mutationError: unknown;
    const committed = transactionResult(transaction, () => {
      if (mutationError) throw mutationError;
      return next ?? createEmptyPersonalData();
    });

    const fail = (error: unknown) => {
      if (mutationError) return;
      mutationError = error;
      try { transaction.abort(); } catch { /* preserve the first failure */ }
    };

    const finish = () => {
      if (!currentReady || !keysReady || started || mutationError) return;
      started = true;
      try {
        current ??= createEmptyPersonalData();
        if (options.expectedRevision !== undefined && current.revision !== options.expectedRevision) {
          throw new PersonalRevisionConflictError(options.expectedRevision, current.revision);
        }
        const draft = structuredClone(current);
        const result: unknown = (mutator as (value: PersonalData) => unknown)(draft);
        if (result && typeof (result as unknown as { then?: unknown }).then === 'function') {
          throw new Error('mutatePersonalData mutator 必须同步完成');
        }
        validatePersonalData(draft);
        const plainDraft = jsonPlainPersonalData(draft);
        plainDraft.sessions = mergeSessionCheckpoints(current.sessions, plainDraft.sessions);
        plainDraft.schemaVersion = PERSONAL_SCHEMA_VERSION;
        plainDraft.revision = current.revision + 1;
        validatePersonalData(plainDraft);
        enforceWriteBackupBudget(current, plainDraft);
        const allAssetIds = new Set([...existingAssetIds, ...assets.map((asset) => asset.id)]);
        const referencedAssetIds = assetReferences(plainDraft);
        for (const asset of assets) if (!referencedAssetIds.has(asset.id)) throw new Error(`新附件 ${asset.id} 没有被个人资料引用；个人资料没有保存`);
        for (const id of referencedAssetIds) {
          if (!allAssetIds.has(id)) throw new Error(`个人资料引用的附件不存在：${id}`);
        }
        const currentReferences = assetReferences(current);
        const changedReferences = currentReferences.size !== referencedAssetIds.size
          || [...currentReferences].some((id) => !referencedAssetIds.has(id));
        const incomingMetadata = new Map(assets.map((asset) => [asset.id, { id: asset.id, size: asset.bytes.byteLength, mimeType: asset.mimeType }]));
        const storedMetadata = new Map<string, PersonalAssetMetadata>();
        const writeMutation = () => {
          try {
            if (changedReferences) {
              const readMetadata = (id: string): PersonalAssetMetadata => {
                const metadata = storedMetadata.get(id);
                if (!metadata || !Number.isSafeInteger(metadata.size) || metadata.size < 0 || !isValidPersonalMimeType(metadata.mimeType)) {
                  throw new Error(`附件 ${id} 的预算 metadata 缺失或无效；本次资料没有保存`);
                }
                return metadata;
              };
              const currentAssetMetadata = [...currentReferences].map(readMetadata);
              const proposedAssetMetadata = [...referencedAssetIds].map((id) => incomingMetadata.get(id) ?? readMetadata(id));
              const currentBytes = currentAssetMetadata.reduce((total, item) => total + item.size, 0);
              const proposedBytes = proposedAssetMetadata.reduce((total, item) => total + item.size, 0);
              const currentVolumes = countPackedPersonalBackupVolumes(currentAssetMetadata);
              const proposedVolumes = countPackedPersonalBackupVolumes(proposedAssetMetadata);
              enforceAssetWriteBackupBudget(current!, plainDraft, currentBytes, proposedBytes, currentVolumes, proposedVolumes);
            }
            for (const asset of assets) {
              assetStore.put(asset);
              metadataStore.put({ id: asset.id, size: asset.bytes.byteLength, mimeType: asset.mimeType });
            }
            stateStore.put({ key: STATE_KEY, data: plainDraft });
            next = plainDraft;
          } catch (error) { fail(error); }
        };

        if (!changedReferences) {
          writeMutation();
          return;
        }
        const metadataIds = new Set([...currentReferences, ...referencedAssetIds]);
        let pendingMetadata = metadataIds.size;
        if (!pendingMetadata) {
          writeMutation();
          return;
        }
        for (const id of metadataIds) {
          const request = metadataStore.get(id);
          request.onsuccess = () => {
            const record = request.result as PersonalAssetMetadata | undefined;
            if (record) storedMetadata.set(id, record);
            pendingMetadata--;
            if (!pendingMetadata) writeMutation();
          };
          request.onerror = () => fail(request.error ?? new Error(`附件 ${id} 的预算 metadata 读取失败`));
        }
      } catch (error) {
        fail(error);
      }
    };

    currentRequest.onsuccess = () => {
      const record = currentRequest.result as { data?: unknown } | undefined;
      try {
        current = record?.data ? normalizePersonalData(record.data) : createEmptyPersonalData();
        currentReady = true;
        finish();
      } catch (error) {
        fail(error);
      }
    };
    currentRequest.onerror = () => fail(currentRequest.error ?? new Error('个人资料读取失败'));
    assetKeysRequest.onsuccess = () => {
      existingAssetIds = new Set(assetKeysRequest.result.map(String));
      keysReady = true;
      finish();
    };
    assetKeysRequest.onerror = () => fail(assetKeysRequest.error ?? new Error('个人附件清单读取失败'));

    try {
      const result = await committed;
      notifySubscribers();
      return result;
    } catch (error) {
      if (mutationError) throw mutationError;
      throw error;
    }
  } finally {
    db.close();
  }
}

export async function mutatePersonalData(mutator: (draft: PersonalData) => void, options: PersonalMutationOptions = {}): Promise<PersonalData> {
  await ensureLegacyMigrated();
  return commitMutation(mutator, options);
}

function mergeById<T extends { id: string; updatedAt?: number }>(target: T[], incoming: T[]): T[] {
  const merged = new Map(target.map((item) => [item.id, item]));
  for (const item of incoming) {
    const current = merged.get(item.id);
    if (!current || (item.updatedAt ?? 0) >= (current.updatedAt ?? 0)) merged.set(item.id, item);
  }
  return [...merged.values()];
}

interface LegacySnapshot {
  projects: PersonalData['projects'];
  history: PersonalData['history'];
  originals: OriginalReference[];
  assets: PersonalAsset[];
  warnings: string[];
  complete: boolean;
}

async function collectLegacySnapshot(): Promise<LegacySnapshot> {
  const snapshot: LegacySnapshot = { projects: [], history: [], originals: [], assets: [], warnings: [], complete: true };
  if (typeof localStorage !== 'undefined') {
    try {
      for (let index = 0; index < localStorage.length; index++) {
        const key = localStorage.key(index);
        if (!key || (!key.startsWith(LEGACY_DRAFT_PREFIX) && !LEGACY_HISTORY_KEYS.includes(key))) continue;
        try {
          const raw = localStorage.getItem(key);
          if (!raw) continue;
          const parsed = JSON.parse(raw);
          if (key.startsWith(LEGACY_DRAFT_PREFIX)) {
            const project = normalizeStudioProject(parsed);
            const existingIndex = snapshot.projects.findIndex((candidate) => candidate.id === project.id);
            if (existingIndex < 0 || project.updatedAt >= snapshot.projects[existingIndex].updatedAt) {
              if (existingIndex < 0) snapshot.projects.push(project);
              else snapshot.projects[existingIndex] = project;
            }
          } else if (Array.isArray(parsed)) {
            for (const entry of parsed) {
              if (!entry || typeof entry.id !== 'string' || typeof entry.title !== 'string' || typeof entry.url !== 'string' || !Number.isFinite(entry.time) || !isSafeLocalPath(entry.url)) {
                snapshot.complete = false;
                snapshot.warnings.push(`旧数据 ${key} 包含无效或不安全的浏览记录；原数据已保留`);
                continue;
              }
              snapshot.history.push({ id: entry.id, title: entry.title, artist: typeof entry.artist === 'string' ? entry.artist : '', url: entry.url, time: entry.time, category: key.startsWith('ukulele') ? 'ukulele' : 'guitar' });
            }
          } else {
            throw new Error('历史记录不是数组');
          }
        } catch (error) {
          snapshot.complete = false;
          snapshot.warnings.push(`旧数据 ${key} 未迁移：${error instanceof Error ? error.message : String(error)}；原数据已保留`);
        }
      }
    } catch (error) {
      snapshot.complete = false;
      snapshot.warnings.push(`无法读取旧 localStorage：${error instanceof Error ? error.message : String(error)}；原数据已保留`);
    }
  }

  if (typeof indexedDB !== 'undefined') {
    try {
      const oldDb = await openLegacyOriginalsDatabase();
      if (oldDb) {
        try {
          if (!oldDb.objectStoreNames.contains(LEGACY_ORIGINALS_STORE)) {
            snapshot.complete = false;
            snapshot.warnings.push(`旧原件库缺少 ${LEGACY_ORIGINALS_STORE} store；原数据库已保留`);
          } else {
            const tx = oldDb.transaction(LEGACY_ORIGINALS_STORE, 'readonly');
            const records = await requestValue(tx.objectStore(LEGACY_ORIGINALS_STORE).getAll()) as Array<{ id?: string; fileName?: string; mimeType?: string; data?: ArrayBuffer | ArrayBufferView; savedAt?: number }>;
            for (const [index, record] of records.entries()) {
              try {
                if (!record.id || !record.fileName || !record.data) throw new Error('原件记录字段不完整');
                const bytes = toBytes(record.data);
                const id = await hashBytes(bytes);
                snapshot.assets.push({ id, mimeType: record.mimeType || 'application/octet-stream', bytes: bytes.slice().buffer as ArrayBuffer });
                snapshot.originals.push({ id: record.id, fileName: record.fileName, mimeType: record.mimeType || 'application/octet-stream', assetId: id, savedAt: Number.isFinite(record.savedAt) ? Number(record.savedAt) : 0 });
              } catch (error) {
                snapshot.complete = false;
                snapshot.warnings.push(`旧原件 ${record.id ?? index} 未迁移：${error instanceof Error ? error.message : String(error)}；原数据已保留`);
              }
            }
          }
        } finally {
          oldDb.close();
        }
      }
    } catch (error) {
      snapshot.complete = false;
      snapshot.warnings.push(`旧原件库无法检查：${error instanceof Error ? error.message : String(error)}；原数据已保留`);
    }
  }
  return snapshot;
}

function openLegacyOriginalsDatabase(): Promise<IDBDatabase | null> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(LEGACY_ORIGINALS_DATABASE);
    let newDatabase = false;
    let settled = false;
    request.onupgradeneeded = () => {
      newDatabase = true;
      request.transaction?.abort();
    };
    request.onsuccess = () => {
      if (newDatabase) {
        request.result.close();
        if (!settled) { settled = true; resolve(null); }
      } else if (settled) request.result.close();
      else {
        settled = true;
        request.result.onversionchange = () => request.result.close();
        resolve(request.result);
      }
    };
    request.onerror = () => {
      if (settled) return;
      settled = true;
      if (newDatabase) resolve(null);
      else reject(request.error ?? new Error('无法打开旧原件库'));
    };
    request.onblocked = () => {
      if (settled) return;
      settled = true;
      reject(new Error('旧原件库被其他页面阻止打开'));
    };
  });
}

async function runLegacyMigration(): Promise<void> {
  const first = await readStateWithoutMigration();
  if (first.migrationCompleted) return;
  const legacy = await collectLegacySnapshot();
  lastMigrationWarnings = [...legacy.warnings];
  const warningText = JSON.stringify(legacy.warnings);
  await commitMutation((draft) => {
    if (draft.migrationCompleted) return;
    draft.projects = mergeById(draft.projects, legacy.projects);
    draft.originals = mergeById(draft.originals, legacy.originals);
    const history = new Map(draft.history.map((entry) => [`${entry.id}\0${entry.url}\0${entry.time}`, entry]));
    for (const entry of legacy.history) history.set(`${entry.id}\0${entry.url}\0${entry.time}`, entry);
    draft.history = [...history.values()].sort((a, b) => b.time - a.time);
    draft.settings.migrationWarnings = warningText;
    draft.migrationCompleted = legacy.complete;
  }, { assets: legacy.assets });
  migrationDeferred = !legacy.complete;
}

async function ensureLegacyMigrated(): Promise<void> {
  if (migrationDeferred) return;
  if (migrationAttempt) return migrationAttempt;
  migrationAttempt = runLegacyMigration().finally(() => { migrationAttempt = null; });
  await migrationAttempt;
}

export async function readPersonalData(): Promise<PersonalData> {
  await ensureLegacyMigrated();
  return readStateWithoutMigration();
}

export async function readAsset(id: string): Promise<PersonalAsset | null> {
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  const db = await openDatabase();
  try {
    const transaction = db.transaction(ASSET_STORE, 'readonly');
    const record = await requestValue(transaction.objectStore(ASSET_STORE).get(id)) as PersonalAsset | undefined;
    return record ? { id: record.id, mimeType: record.mimeType, bytes: record.bytes.slice(0) } : null;
  } finally {
    db.close();
  }
}

export async function readPersonalAssetIds(): Promise<Set<string>> {
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  const db = await openDatabase();
  try {
    const transaction = db.transaction(ASSET_STORE, 'readonly');
    const keys = await requestValue(transaction.objectStore(ASSET_STORE).getAllKeys());
    return new Set(keys.map(String));
  } finally {
    db.close();
  }
}

/** Reads compact size/MIME records without loading attachment ArrayBuffers. */
export async function readPersonalAssetMetadata(ids: readonly string[]): Promise<PersonalRestoreAssetMetadata[]> {
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  if (new Set(ids).size !== ids.length) throw new Error('附件 metadata 查询清单重复');
  const db = await openDatabase();
  try {
    const transaction = db.transaction(ASSET_METADATA_STORE, 'readonly');
    const store = transaction.objectStore(ASSET_METADATA_STORE);
    return await Promise.all(ids.map(async (id) => {
      const record = await requestValue(store.get(id)) as PersonalRestoreAssetMetadata | undefined;
      if (!record) throw new Error(`附件 ${id} 缺少预算 metadata`);
      return { id: record.id, size: record.size, mimeType: record.mimeType };
    }));
  } finally {
    db.close();
  }
}

function assertRestoreSessionId(sessionId: string): void {
  if (!/^[a-zA-Z0-9_-]{8,128}$/.test(sessionId)) throw new Error('备份暂存会话编号无效');
}

/** Saves one already validated asset into an isolated restore staging session. */
export async function stagePersonalRestoreAsset(sessionId: string, asset: PersonalAsset): Promise<void> {
  assertRestoreSessionId(sessionId);
  if (!asset || !/^[a-f0-9]{64}$/.test(asset.id) || !isValidPersonalMimeType(asset.mimeType) || !(asset.bytes instanceof ArrayBuffer) || asset.bytes.byteLength > MAX_PERSONAL_ASSET_BYTES) {
    throw new Error('恢复暂存附件字段或大小无效');
  }
  if (await hashBytes(new Uint8Array(asset.bytes)) !== asset.id) throw new Error(`恢复暂存附件 SHA-256 不匹配：${asset.id}`);
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  const db = await openDatabase();
  try {
    const transaction = db.transaction(RESTORE_STAGE_STORE, 'readwrite');
    const record: RestoreStagingRecord = {
      key: `${sessionId}:${asset.id}`,
      sessionId,
      assetId: asset.id,
      mimeType: asset.mimeType || 'application/octet-stream',
      bytes: asset.bytes,
      size: asset.bytes.byteLength,
      createdAt: Date.now(),
    };
    transaction.objectStore(RESTORE_STAGE_STORE).put(record);
    await transactionResult(transaction, () => undefined);
  } catch (error) {
    if ((error as { name?: string })?.name === 'QuotaExceededError') {
      throw new Error('浏览器没有足够空间暂存完整备份；当前资料保持不变，请释放空间后重试');
    }
    throw error;
  } finally {
    db.close();
  }
}

export async function clearPersonalRestoreStage(sessionId: string): Promise<void> {
  assertRestoreSessionId(sessionId);
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  const db = await openDatabase();
  try {
    const transaction = db.transaction(RESTORE_STAGE_STORE, 'readwrite');
    const index = transaction.objectStore(RESTORE_STAGE_STORE).index('sessionId');
    const request = index.openCursor(IDBKeyRange.only(sessionId));
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      cursor.delete();
      cursor.continue();
    };
    await transactionResult(transaction, () => undefined);
  } finally {
    db.close();
  }
}

/** Removes only abandoned scratch sessions; active personal assets are never touched. */
export async function clearExpiredPersonalRestoreStages(now = Date.now(), maxAgeMs = 7 * 24 * 60 * 60 * 1000): Promise<void> {
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  const db = await openDatabase();
  try {
    const transaction = db.transaction(RESTORE_STAGE_STORE, 'readwrite');
    const request = transaction.objectStore(RESTORE_STAGE_STORE).openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return;
      const record = cursor.value as RestoreStagingRecord;
      if (!Number.isFinite(record.createdAt) || now - record.createdAt > maxAgeMs) cursor.delete();
      cursor.continue();
    };
    await transactionResult(transaction, () => undefined);
  } finally {
    db.close();
  }
}

/**
 * Commits a fully validated staged restore in one IndexedDB transaction.
 * The transform is synchronous; staged bytes are copied by cursor without any
 * promise boundary that could make the transaction inactive.
 */
export async function commitPersonalRestoreStage(
  sessionId: string,
  expectedRevision: number,
  expectedRestoreAssetIds: readonly string[],
  expectedRestoreAssetMetadata: readonly PersonalRestoreAssetMetadata[],
  transform: PersonalRestoreTransform,
  signal?: AbortSignal,
): Promise<PersonalData> {
  assertRestoreSessionId(sessionId);
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error('恢复预览 revision 无效');
  if (typeof transform !== 'function') throw new Error('恢复资料转换函数无效');
  const expectedIds = new Set(expectedRestoreAssetIds);
  if (expectedIds.size !== expectedRestoreAssetIds.length || [...expectedIds].some((id) => !/^[a-f0-9]{64}$/.test(id))) {
    throw new Error('恢复附件清单无效');
  }
  const restoreMetadata = new Map<string, PersonalAssetMetadata>();
  for (const item of expectedRestoreAssetMetadata) {
    if (!item || !expectedIds.has(item.id) || restoreMetadata.has(item.id) || !Number.isSafeInteger(item.size) || item.size < 0 || item.size > MAX_PERSONAL_ASSET_BYTES || !isValidPersonalMimeType(item.mimeType)) {
      throw new Error('恢复附件预算 metadata 无效');
    }
    restoreMetadata.set(item.id, { id: item.id, size: item.size, mimeType: item.mimeType });
  }
  if (restoreMetadata.size !== expectedIds.size) throw new Error('恢复附件预算 metadata 与附件清单不一致');
  await ensureLegacyMigrated();
  if (typeof window === 'undefined' || typeof indexedDB === 'undefined') throw new PersonalStorageUnavailableError();
  if (signal?.aborted) throw new Error('恢复已取消；当前资料保持不变');
  const db = await openDatabase();
  let transaction: IDBTransaction | null = null;
  let mutationError: unknown;
  let next: PersonalData | null = null;
  const abortForCancel = () => {
    if (!transaction) return;
    mutationError = new Error('恢复已取消；当前资料保持不变');
    try { transaction.abort(); } catch { /* the transaction may already be complete */ }
  };
  signal?.addEventListener('abort', abortForCancel, { once: true });
  try {
    transaction = db.transaction([STATE_STORE, ASSET_STORE, ASSET_METADATA_STORE, RESTORE_STAGE_STORE], 'readwrite');
    const stateStore = transaction.objectStore(STATE_STORE);
    const assetStore = transaction.objectStore(ASSET_STORE);
    const metadataStore = transaction.objectStore(ASSET_METADATA_STORE);
    const stagingIndex = transaction.objectStore(RESTORE_STAGE_STORE).index('sessionId');
    const stateRequest = stateStore.get(STATE_KEY);
    const keysRequest = assetStore.getAllKeys();
    let current: PersonalData | null = null;
    let existingAssetIds = new Set<string>();
    let stateReady = false;
    let keysReady = false;
    let started = false;

    const committed = transactionResult(transaction, () => {
      if (mutationError) throw mutationError;
      if (!next) throw new Error('恢复事务没有写入资料');
      return next;
    });

    const fail = (error: unknown) => {
      if (mutationError) return;
      mutationError = error;
      try { transaction?.abort(); } catch { /* preserve the first failure */ }
    };

    const beginCommit = () => {
      if (!stateReady || !keysReady || started || mutationError) return;
      started = true;
      try {
        current ??= createEmptyPersonalData();
        if (current.revision !== expectedRevision) throw new PersonalRevisionConflictError(expectedRevision, current.revision);
        let merged = transform(structuredClone(current));
        merged = jsonPlainPersonalData(merged);
        merged.schemaVersion = PERSONAL_SCHEMA_VERSION;
        merged.revision = current.revision + 1;
        validatePersonalData(merged);
        enforceWriteBackupBudget(current, merged);
        const referenced = assetReferences(merged);
        for (const id of referenced) {
          if (!existingAssetIds.has(id) && !expectedIds.has(id)) throw new Error(`个人资料引用的附件不存在：${id}`);
        }
        const currentReferences = assetReferences(current);
        const changedReferences = currentReferences.size !== referenced.size
          || [...currentReferences].some((id) => !referenced.has(id));
        const commitAssetsAndState = () => {
          const seenStageIds = new Set<string>();
          const cursorRequest = stagingIndex.openCursor(IDBKeyRange.only(sessionId));
          cursorRequest.onerror = () => fail(cursorRequest.error ?? new Error('恢复暂存读取失败'));
          cursorRequest.onsuccess = () => {
            if (signal?.aborted) { abortForCancel(); return; }
            const cursor = cursorRequest.result;
            if (!cursor) {
              try {
                for (const id of expectedIds) if (!seenStageIds.has(id) && !existingAssetIds.has(id)) throw new Error(`恢复附件缺失：${id}`);
                for (const id of seenStageIds) if (!expectedIds.has(id)) throw new Error(`恢复暂存含有未预览附件：${id}`);
                stateStore.put({ key: STATE_KEY, data: merged });
                next = merged;
              } catch (error) {
                fail(error);
              }
              return;
            }
            try {
              const staged = cursor.value as RestoreStagingRecord;
              const expected = restoreMetadata.get(staged.assetId);
              if (staged.sessionId !== sessionId || !expected || !expectedIds.has(staged.assetId) || staged.key !== `${sessionId}:${staged.assetId}` || seenStageIds.has(staged.assetId) || !(staged.bytes instanceof ArrayBuffer) || staged.size !== staged.bytes.byteLength || staged.size > MAX_PERSONAL_ASSET_BYTES || staged.size !== expected.size || staged.mimeType !== expected.mimeType) {
                throw new Error('恢复暂存附件与已校验清单不一致');
              }
              seenStageIds.add(staged.assetId);
              if (!existingAssetIds.has(staged.assetId)) {
                assetStore.put({ id: staged.assetId, mimeType: staged.mimeType, bytes: staged.bytes });
                metadataStore.put({ id: staged.assetId, size: staged.size, mimeType: staged.mimeType });
              }
              cursor.delete();
              cursor.continue();
            } catch (error) {
              fail(error);
            }
          };
        };

        if (!changedReferences) {
          commitAssetsAndState();
          return;
        }
        const metadataIds = new Set([...currentReferences, ...referenced]);
        const storedMetadata = new Map<string, PersonalAssetMetadata>();
        let pendingMetadata = metadataIds.size;
        const continueAfterMetadata = () => {
          if (pendingMetadata) return;
          try {
            const readStored = (id: string): PersonalAssetMetadata => {
              const item = storedMetadata.get(id);
              if (!item || !Number.isSafeInteger(item.size) || item.size < 0 || !isValidPersonalMimeType(item.mimeType)) {
                throw new Error(`附件 ${id} 的预算 metadata 缺失或无效；恢复没有提交`);
              }
              return item;
            };
            const currentMetadata = [...currentReferences].map(readStored);
            const proposedMetadata = [...referenced].map((id) => {
              if (existingAssetIds.has(id)) return readStored(id);
              const item = restoreMetadata.get(id);
              if (!item) throw new Error(`恢复附件 ${id} 的预算 metadata 缺失`);
              return item;
            });
            const currentBytes = currentMetadata.reduce((total, item) => total + item.size, 0);
            const proposedBytes = proposedMetadata.reduce((total, item) => total + item.size, 0);
            enforceAssetWriteBackupBudget(
              current!,
              merged,
              currentBytes,
              proposedBytes,
              countPackedPersonalBackupVolumes(currentMetadata),
              countPackedPersonalBackupVolumes(proposedMetadata),
            );
            commitAssetsAndState();
          } catch (error) { fail(error); }
        };
        if (!pendingMetadata) {
          continueAfterMetadata();
          return;
        }
        for (const id of metadataIds) {
          const request = metadataStore.get(id);
          request.onsuccess = () => {
            const record = request.result as PersonalAssetMetadata | undefined;
            if (record) storedMetadata.set(id, record);
            pendingMetadata--;
            continueAfterMetadata();
          };
          request.onerror = () => fail(request.error ?? new Error(`附件 ${id} 的预算 metadata 读取失败`));
        }
      } catch (error) {
        fail(error);
      }
    };

    stateRequest.onsuccess = () => {
      try {
        const record = stateRequest.result as { data?: unknown } | undefined;
        current = record?.data ? normalizePersonalData(record.data) : createEmptyPersonalData();
        stateReady = true;
        beginCommit();
      } catch (error) { fail(error); }
    };
    stateRequest.onerror = () => fail(stateRequest.error ?? new Error('个人资料读取失败'));
    keysRequest.onsuccess = () => {
      existingAssetIds = new Set(keysRequest.result.map(String));
      keysReady = true;
      beginCommit();
    };
    keysRequest.onerror = () => fail(keysRequest.error ?? new Error('个人附件清单读取失败'));

    const result = await committed;
    notifySubscribers();
    return result;
  } catch (error) {
    if (mutationError) throw mutationError;
    if ((error as { name?: string })?.name === 'QuotaExceededError') {
      throw new Error('浏览器可用空间不足，恢复事务已回滚；当前资料保持不变');
    }
    throw error;
  } finally {
    signal?.removeEventListener('abort', abortForCancel);
    db.close();
  }
}

/** Idempotent legacy migration may be retried after a reload when source entries were damaged. */
export async function retryPersonalDataMigration(): Promise<string[]> {
  migrationDeferred = false;
  migrationAttempt = null;
  await ensureLegacyMigrated();
  return getPersonalMigrationWarnings();
}
