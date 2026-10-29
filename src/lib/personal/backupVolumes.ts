import type { PersonalAsset, PersonalData, PersonalDataSnapshot } from './types.ts';
import {
  BackupValidationError,
  canonicalJson,
  dataCounts,
  equalJson,
  mergePersonalBackupData,
  requiredAssetIds,
} from './backup.ts';
import {
  clearPersonalRestoreStage,
  commitPersonalRestoreStage,
  hashBytes,
  readAsset,
  readPersonalAssetMetadata,
  readPersonalAssetIds,
  readPersonalData,
  stagePersonalRestoreAsset,
} from './repository.ts';
import {
  countPackedPersonalBackupVolumes,
  isValidPersonalMimeType,
  MAX_PERSONAL_ASSET_BYTES,
  MAX_PERSONAL_BACKUP_ASSETS,
  MAX_PERSONAL_BACKUP_ASSET_BYTES,
  MAX_PERSONAL_BACKUP_ENTITIES,
  MAX_PERSONAL_BACKUP_MANIFEST_BYTES,
  MAX_PERSONAL_BACKUP_TOTAL_BYTES,
  MAX_PERSONAL_BACKUP_VOLUMES,
  PERSONAL_BACKUP_VOLUME_BYTES,
} from './limits.ts';
import { PersonalDataValidationError, validatePersonalData } from './validation.ts';
import { PERSONAL_SCHEMA_VERSION } from './validation.ts';

export const PERSONAL_BACKUP_VOLUME_FORMAT = 'mimi-personal-backup-volume';
export const PERSONAL_BACKUP_VOLUME_VERSION = 2;
export { MAX_PERSONAL_BACKUP_MANIFEST_BYTES, MAX_PERSONAL_BACKUP_TOTAL_BYTES, MAX_PERSONAL_BACKUP_VOLUMES, PERSONAL_BACKUP_VOLUME_BYTES };
const MAGIC = new TextEncoder().encode('MIMI2VOL');
const PREFIX_BYTES = MAGIC.byteLength + 4;
const MAX_HEADER_BYTES = 256 * 1024;
const MAX_VOLUME_FILE_BYTES = PREFIX_BYTES + MAX_HEADER_BYTES + PERSONAL_BACKUP_VOLUME_BYTES;

export interface BackupVolumeChunk {
  assetId: string;
  chunkIndex: number;
  byteLength: number;
  sha256: string;
}

export interface BackupVolumeAsset {
  id: string;
  mimeType: string;
  size: number;
  chunkCount: number;
}

export interface BackupVolumeDescriptor {
  sequence: number;
  payloadBytes: number;
  payloadSha256: string;
  byteLength: number;
  chunks: BackupVolumeChunk[];
}

export interface BackupVolumeManifest {
  formatVersion: number;
  snapshotId: string;
  schemaVersion: number;
  revision: number;
  generatedAt: string;
  counts: Record<string, number>;
  assetBytes: number;
  assets: BackupVolumeAsset[];
  volumes: BackupVolumeDescriptor[];
  data: PersonalDataSnapshot;
  snapshotSha256: string;
}

export interface PersonalBackupVolumePlan {
  manifest: Blob;
  manifestFileName: string;
  volumeCount: number;
  totalFileBytes: number;
  volumeFileName(sequence: number): string;
  createVolume(sequence: number, signal?: AbortSignal): Promise<Blob>;
  cancel(): void;
}

export interface BackupVolumePreview {
  format: typeof PERSONAL_BACKUP_VOLUME_FORMAT;
  manifest: BackupVolumeManifest;
  data: PersonalDataSnapshot;
  fileSize: number;
  volumeCount: number;
  assetBytes: number;
  assetCount: number;
  expectedRevision: number;
  stagingSessionId: string;
  assetIds: string[];
}

interface VolumeHeader {
  format: typeof PERSONAL_BACKUP_VOLUME_FORMAT;
  formatVersion: number;
  snapshotId: string;
  sequence: number;
  totalVolumes: number;
  payloadBytes: number;
  payloadSha256: string;
  chunks: BackupVolumeChunk[];
}

interface PendingChunk extends BackupVolumeChunk {
  offset: number;
}

function ensureNotAborted(signal?: AbortSignal): void {
  if (signal?.aborted) throw new BackupValidationError('备份操作已取消；当前资料保持不变');
}

function jsonCopy<T>(value: unknown, label: string): T {
  try {
    const serialized = JSON.stringify(value);
    if (serialized === undefined) throw new Error('not serializable');
    return JSON.parse(serialized) as T;
  } catch {
    throw new BackupValidationError(`${label} 不是有效的 JSON 资料`);
  }
}

function randomId(): string {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID().replaceAll('-', '_');
  return `restore_${Date.now().toString(36)}_${Math.random().toString(36).slice(2)}`;
}

function entityCount(data: PersonalData): number {
  return data.scores.length + data.favorites.length + data.practiceItems.length + data.practiceFragments.length + data.resumes.length + data.sessions.length + data.projects.length + data.originals.length + data.history.length;
}

function snapshotEntityCount(data: PersonalDataSnapshot): number {
  return data.scores.length + data.favorites.length + data.practiceItems.length +
    (data.schemaVersion === PERSONAL_SCHEMA_VERSION ? data.practiceFragments.length : 0) +
    data.resumes.length + data.sessions.length + data.projects.length + data.originals.length + data.history.length;
}

function snapshotDigestInput(manifest: Omit<BackupVolumeManifest, 'snapshotSha256'> | BackupVolumeManifest): string {
  const { snapshotSha256: _ignored, ...base } = manifest as BackupVolumeManifest;
  return canonicalJson(base);
}

function headerFor(manifest: BackupVolumeManifest, volume: BackupVolumeDescriptor): VolumeHeader {
  return {
    format: PERSONAL_BACKUP_VOLUME_FORMAT,
    formatVersion: PERSONAL_BACKUP_VOLUME_VERSION,
    snapshotId: manifest.snapshotId,
    sequence: volume.sequence,
    totalVolumes: manifest.volumes.length,
    payloadBytes: volume.payloadBytes,
    payloadSha256: volume.payloadSha256,
    chunks: volume.chunks,
  };
}

function encodeHeader(header: VolumeHeader): Uint8Array {
  const bytes = new TextEncoder().encode(JSON.stringify(header));
  if (bytes.byteLength > MAX_HEADER_BYTES) throw new BackupValidationError('分卷头信息超过安全上限');
  return bytes;
}

function writePrefix(headerBytes: Uint8Array): Uint8Array {
  const prefix = new Uint8Array(PREFIX_BYTES);
  prefix.set(MAGIC, 0);
  new DataView(prefix.buffer).setUint32(MAGIC.byteLength, headerBytes.byteLength, false);
  return prefix;
}

async function makeVolumeBody(
  volume: BackupVolumeDescriptor,
  signal?: AbortSignal,
): Promise<Uint8Array> {
  const body = new Uint8Array(volume.payloadBytes);
  let totalBytes = 0;
  let currentAssetId = '';
  let currentAsset: Uint8Array | null = null;
  for (const chunk of volume.chunks) {
    ensureNotAborted(signal);
    if (chunk.assetId !== currentAssetId) {
      const asset = await readAsset(chunk.assetId);
      if (!asset) throw new BackupValidationError(`导出期间附件缺失：${chunk.assetId}`);
      currentAssetId = chunk.assetId;
      currentAsset = new Uint8Array(asset.bytes);
    }
    if (!currentAsset) throw new BackupValidationError('附件读取状态无效');
    const offset = chunk.chunkIndex * PERSONAL_BACKUP_VOLUME_BYTES;
    const bytes = currentAsset.subarray(offset, offset + chunk.byteLength);
    if (bytes.byteLength !== chunk.byteLength || await hashBytes(bytes) !== chunk.sha256) {
      throw new BackupValidationError(`导出期间附件分块发生变化：${chunk.assetId}`);
    }
    body.set(bytes, totalBytes);
    totalBytes += bytes.byteLength;
  }
  if (totalBytes !== volume.payloadBytes || totalBytes > PERSONAL_BACKUP_VOLUME_BYTES) throw new BackupValidationError('分卷负载超过 8 MiB 或长度不一致');
  if (await hashBytes(body) !== volume.payloadSha256) throw new BackupValidationError(`分卷 ${volume.sequence} SHA-256 校验失败`);
  return body;
}

/** Creates a v2 manifest and one-volume-at-a-time download plan. */
export async function preparePersonalBackupVolumes(signal?: AbortSignal): Promise<PersonalBackupVolumePlan> {
  ensureNotAborted(signal);
  const originalData = await readPersonalData();
  if (!originalData.migrationCompleted) throw new BackupValidationError('旧个人数据尚未完整迁移；完整备份未生成');
  const data = jsonCopy<PersonalData>(originalData, '个人资料');
  try { validatePersonalData(data, { strictProjects: true }); } catch (error) {
    if (error instanceof PersonalDataValidationError) throw new BackupValidationError(error.message);
    throw error;
  }
  if (entityCount(data) > MAX_PERSONAL_BACKUP_ENTITIES) throw new BackupValidationError('个人资料实体总数超过 10,000 个上限');
  const ids = [...requiredAssetIds(data)].sort();
  if (ids.length > MAX_PERSONAL_BACKUP_ASSETS) throw new BackupValidationError('附件数量超过 500 个上限');

  const metadata = await readPersonalAssetMetadata(ids);
  const metadataById = new Map(metadata.map((asset) => [asset.id, asset]));
  const metadataBytes = metadata.reduce((total, asset) => total + asset.size, 0);
  if (metadata.some((asset) => !Number.isSafeInteger(asset.size) || asset.size < 0 || asset.size > MAX_PERSONAL_ASSET_BYTES || !isValidPersonalMimeType(asset.mimeType))) {
    throw new BackupValidationError('附件预算 metadata 无效；没有生成完整备份');
  }
  if (metadataBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES) throw new BackupValidationError(`被引用附件总量超过 ${MAX_PERSONAL_BACKUP_ASSET_BYTES / 1024 / 1024} MiB 上限；没有生成完整备份`);
  if (countPackedPersonalBackupVolumes(metadata) > MAX_PERSONAL_BACKUP_VOLUMES) throw new BackupValidationError(`附件按 8 MiB 分卷后超过 ${MAX_PERSONAL_BACKUP_VOLUMES} 卷上限；没有生成完整备份`);

  const pending: PendingChunk[] = [];
  const assets: BackupVolumeAsset[] = [];
  let assetBytes = 0;
  for (const id of ids) {
    ensureNotAborted(signal);
    const asset = await readAsset(id);
    if (!asset) throw new BackupValidationError(`个人资料引用的附件缺失，备份未生成：${id}`);
    if (!isValidPersonalMimeType(asset.mimeType)) throw new BackupValidationError(`附件 ${id} 的 MIME 类型无效，备份未生成`);
    const bytes = new Uint8Array(asset.bytes);
    if (bytes.byteLength > MAX_PERSONAL_ASSET_BYTES) throw new BackupValidationError(`附件 ${id} 超过 30 MiB 单附件上限`);
    const declared = metadataById.get(id);
    if (!declared || declared.size !== bytes.byteLength || declared.mimeType !== asset.mimeType) throw new BackupValidationError(`附件 ${id} 与预算 metadata 不一致，备份未生成`);
    if (await hashBytes(bytes) !== id) throw new BackupValidationError(`附件 ${id} 的内容摘要与 ID 不一致`);
    assetBytes += bytes.byteLength;
    const chunkCount = Math.ceil(bytes.byteLength / PERSONAL_BACKUP_VOLUME_BYTES);
    assets.push({ id, mimeType: asset.mimeType || 'application/octet-stream', size: bytes.byteLength, chunkCount });
    for (let chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
      const offset = chunkIndex * PERSONAL_BACKUP_VOLUME_BYTES;
      const part = bytes.subarray(offset, Math.min(offset + PERSONAL_BACKUP_VOLUME_BYTES, bytes.byteLength));
      pending.push({ assetId: id, chunkIndex, byteLength: part.byteLength, sha256: await hashBytes(part), offset });
    }
  }

  const packed: Array<{ chunks: BackupVolumeChunk[]; payloadBytes: number }> = [];
  let chunks: BackupVolumeChunk[] = [];
  let payloadBytes = 0;
  for (const chunk of pending) {
    if (payloadBytes > 0 && payloadBytes + chunk.byteLength > PERSONAL_BACKUP_VOLUME_BYTES) {
      packed.push({ chunks, payloadBytes });
      chunks = [];
      payloadBytes = 0;
    }
    chunks.push({ assetId: chunk.assetId, chunkIndex: chunk.chunkIndex, byteLength: chunk.byteLength, sha256: chunk.sha256 });
    payloadBytes += chunk.byteLength;
  }
  if (chunks.length) packed.push({ chunks, payloadBytes });
  if (packed.length > MAX_PERSONAL_BACKUP_VOLUMES) throw new BackupValidationError('附件超过 128 个分卷；没有生成不完整备份');

  const snapshotId = randomId();
  const generatedAt = new Date().toISOString();
  const volumes: BackupVolumeDescriptor[] = [];
  for (const [index, item] of packed.entries()) {
    ensureNotAborted(signal);
    const volume: BackupVolumeDescriptor = {
      sequence: index + 1,
      payloadBytes: item.payloadBytes,
      payloadSha256: '',
      byteLength: 0,
      chunks: item.chunks,
    };
    const pendingForVolume = pending.filter((chunk) => item.chunks.some((candidate) => candidate.assetId === chunk.assetId && candidate.chunkIndex === chunk.chunkIndex));
    const body = new Uint8Array(item.payloadBytes);
    let bodyOffset = 0;
    for (const assetId of [...new Set(item.chunks.map((chunk) => chunk.assetId))]) {
      const asset = await readAsset(assetId);
      if (!asset) throw new BackupValidationError(`生成分卷时附件缺失：${assetId}`);
      const bytes = new Uint8Array(asset.bytes);
      for (const chunk of pendingForVolume.filter((candidate) => candidate.assetId === assetId)) {
        const part = bytes.subarray(chunk.offset, chunk.offset + chunk.byteLength);
        if (part.byteLength !== chunk.byteLength || await hashBytes(part) !== chunk.sha256) throw new BackupValidationError(`生成分卷时附件已变化：${assetId}`);
        body.set(part, bodyOffset);
        bodyOffset += part.byteLength;
      }
    }
    if (bodyOffset !== item.payloadBytes) throw new BackupValidationError('生成分卷时负载长度不一致');
    volume.payloadSha256 = await hashBytes(body);
    const header = encodeHeader({
      format: PERSONAL_BACKUP_VOLUME_FORMAT,
      formatVersion: PERSONAL_BACKUP_VOLUME_VERSION,
      snapshotId,
      sequence: volume.sequence,
      totalVolumes: packed.length,
      payloadBytes: volume.payloadBytes,
      payloadSha256: volume.payloadSha256,
      chunks: volume.chunks,
    });
    volume.byteLength = PREFIX_BYTES + header.byteLength + body.byteLength;
    volumes.push(volume);
  }

  const base = {
    formatVersion: PERSONAL_BACKUP_VOLUME_VERSION,
    snapshotId,
    schemaVersion: data.schemaVersion,
    revision: data.revision,
    generatedAt,
    counts: dataCounts(data, assets.length),
    assetBytes,
    assets,
    volumes,
    data,
  };
  const snapshotSha256 = await hashBytes(new TextEncoder().encode(canonicalJson(base)));
  const manifest: BackupVolumeManifest = { ...base, snapshotSha256 };
  const manifestBytes = new TextEncoder().encode(JSON.stringify({ format: PERSONAL_BACKUP_VOLUME_FORMAT, manifest }));
  if (manifestBytes.byteLength > MAX_PERSONAL_BACKUP_MANIFEST_BYTES) throw new BackupValidationError('备份清单超过 64 MiB 上限；没有生成部分备份');
  const totalFileBytes = manifestBytes.byteLength + volumes.reduce((sum, volume) => sum + volume.byteLength, 0);
  if (totalFileBytes > MAX_PERSONAL_BACKUP_TOTAL_BYTES) throw new BackupValidationError('完整备份超过 1 GiB 总文件上限；没有生成部分备份');
  const after = await readPersonalData();
  if (after.revision !== data.revision) throw new BackupValidationError('备份生成期间个人资料发生变化，请重新开始');
  ensureNotAborted(signal);

  let cancelled = false;
  const ensurePlanValid = async (volumeSequence: number, volumeSignal?: AbortSignal) => {
    if (cancelled) throw new BackupValidationError('备份计划已取消，请重新生成');
    ensureNotAborted(volumeSignal);
    const current = await readPersonalData();
    if (current.revision !== data.revision) throw new BackupValidationError('备份生成期间个人资料发生变化，请重新开始');
    const volume = volumes[volumeSequence - 1];
    if (!volume || volume.sequence !== volumeSequence) throw new BackupValidationError('分卷序号超出备份清单');
    return volume;
  };

  return {
    manifest: new Blob([manifestBytes], { type: 'application/vnd.mimi.personal-backup-manifest+json' }),
    manifestFileName: `mimi-personal-v2-${generatedAt.slice(0, 10)}-${snapshotId}.json`,
    volumeCount: volumes.length,
    totalFileBytes,
    volumeFileName(sequence) {
      if (!Number.isSafeInteger(sequence) || sequence < 1 || sequence > volumes.length) throw new BackupValidationError('分卷序号超出备份清单');
      return `mimi-personal-v2-${snapshotId}-volume-${String(sequence).padStart(3, '0')}-of-${String(volumes.length).padStart(3, '0')}.mibak2`;
    },
    async createVolume(sequence, volumeSignal) {
      const volume = await ensurePlanValid(sequence, volumeSignal);
      const body = await makeVolumeBody(volume, volumeSignal);
      const headerBytes = encodeHeader(headerFor(manifest, volume));
      const current = await readPersonalData();
      if (current.revision !== data.revision) throw new BackupValidationError('分卷生成期间个人资料发生变化，请重新开始');
      const blob = new Blob([writePrefix(headerBytes), headerBytes, body], { type: 'application/vnd.mimi.personal-backup-volume' });
      if (blob.size !== volume.byteLength) throw new BackupValidationError('分卷长度与清单不一致');
      return blob;
    },
    cancel() { cancelled = true; },
  };
}

function assertObject(value: unknown, label: string): asserts value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new BackupValidationError(`${label} 必须是对象`);
}

/** Structural preflight only; SHA-256 and volume contents are checked separately. */
export function validateBackupVolumeManifest(value: unknown): BackupVolumeManifest {
  assertObject(value, 'v2 manifest');
  const manifest = value as unknown as BackupVolumeManifest;
  if (manifest.formatVersion !== PERSONAL_BACKUP_VOLUME_VERSION) throw new BackupValidationError(`不支持的分卷备份版本：${String(manifest.formatVersion)}`);
  if (typeof manifest.snapshotId !== 'string' || !/^[a-zA-Z0-9_-]{12,80}$/.test(manifest.snapshotId)) throw new BackupValidationError('snapshot ID 无效');
  if (!Number.isSafeInteger(manifest.schemaVersion) || (manifest.schemaVersion !== 1 && manifest.schemaVersion !== PERSONAL_SCHEMA_VERSION) || !Number.isSafeInteger(manifest.revision) || manifest.revision < 0) throw new BackupValidationError('备份资料版本或 revision 无效');
  if (typeof manifest.generatedAt !== 'string' || !Number.isFinite(Date.parse(manifest.generatedAt))) throw new BackupValidationError('备份时间无效');
  if (!/^[a-f0-9]{64}$/.test(manifest.snapshotSha256) || !Array.isArray(manifest.assets) || !Array.isArray(manifest.volumes) || !manifest.data) throw new BackupValidationError('v2 manifest 字段不完整');
  try { validatePersonalData(manifest.data, { strictProjects: true }); } catch (error) {
    if (error instanceof PersonalDataValidationError) throw new BackupValidationError(error.message);
    throw error;
  }
  if (manifest.data.schemaVersion !== manifest.schemaVersion || manifest.data.revision !== manifest.revision) throw new BackupValidationError('manifest 与个人资料版本不一致');
  if (snapshotEntityCount(manifest.data) > MAX_PERSONAL_BACKUP_ENTITIES) throw new BackupValidationError('个人资料实体总数超过 10,000 个上限');
  if (manifest.assets.length > MAX_PERSONAL_BACKUP_ASSETS || manifest.volumes.length > MAX_PERSONAL_BACKUP_VOLUMES) throw new BackupValidationError('附件或分卷数量超过备份上限');
  if (!Number.isSafeInteger(manifest.assetBytes) || manifest.assetBytes < 0 || manifest.assetBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES) throw new BackupValidationError(`附件总量超过 ${MAX_PERSONAL_BACKUP_ASSET_BYTES / 1024 / 1024} MiB 上限`);

  let totalAssetBytes = 0;
  const assetMap = new Map<string, BackupVolumeAsset>();
  let previousAssetId = '';
  for (const [index, asset] of manifest.assets.entries()) {
    if (!asset || !/^[a-f0-9]{64}$/.test(asset.id) || !isValidPersonalMimeType(asset.mimeType) || !Number.isSafeInteger(asset.size) || asset.size < 0 || asset.size > MAX_PERSONAL_ASSET_BYTES || !Number.isSafeInteger(asset.chunkCount) || asset.chunkCount < 0) throw new BackupValidationError(`assets[${index}] 字段无效`);
    if (assetMap.has(asset.id) || (previousAssetId && previousAssetId >= asset.id)) throw new BackupValidationError('附件清单重复或未按 ID 排序');
    const expectedChunkCount = Math.ceil(asset.size / PERSONAL_BACKUP_VOLUME_BYTES);
    if (asset.chunkCount !== expectedChunkCount) throw new BackupValidationError(`附件 ${asset.id} 分块数量无效`);
    totalAssetBytes += asset.size;
    assetMap.set(asset.id, asset);
    previousAssetId = asset.id;
  }
  if (totalAssetBytes !== manifest.assetBytes) throw new BackupValidationError('附件总大小与 manifest 不一致');
  if (countPackedPersonalBackupVolumes(manifest.assets) > MAX_PERSONAL_BACKUP_VOLUMES) throw new BackupValidationError(`附件按规则打包后超过 ${MAX_PERSONAL_BACKUP_VOLUMES} 卷上限`);
  const expectedAssetIds = [...requiredAssetIds(manifest.data)].sort();
  if (!equalJson(expectedAssetIds, manifest.assets.map((asset) => asset.id))) throw new BackupValidationError('备份没有完整包含个人资料引用的附件');
  if (!equalJson(manifest.counts, dataCounts(manifest.data, manifest.assets.length))) throw new BackupValidationError('manifest 实体计数不一致');

  if ((manifest.assets.some((asset) => asset.chunkCount > 0)) !== (manifest.volumes.length > 0)) throw new BackupValidationError('附件数据与分卷数量不一致');
  const allChunks: BackupVolumeChunk[] = [];
  let declaredFileBytes = 0;
  for (const [index, volume] of manifest.volumes.entries()) {
    if (!volume || volume.sequence !== index + 1 || !Number.isSafeInteger(volume.payloadBytes) || volume.payloadBytes <= 0 || volume.payloadBytes > PERSONAL_BACKUP_VOLUME_BYTES || !/^[a-f0-9]{64}$/.test(volume.payloadSha256) || !Number.isSafeInteger(volume.byteLength) || volume.byteLength < PREFIX_BYTES || volume.byteLength > MAX_VOLUME_FILE_BYTES || !Array.isArray(volume.chunks) || volume.chunks.length === 0) throw new BackupValidationError(`volumes[${index}] 字段无效`);
    let bodyBytes = 0;
    for (const chunk of volume.chunks) {
      const asset = assetMap.get(chunk.assetId);
      if (!asset || !Number.isSafeInteger(chunk.chunkIndex) || chunk.chunkIndex < 0 || chunk.chunkIndex >= asset.chunkCount || !Number.isSafeInteger(chunk.byteLength) || chunk.byteLength <= 0 || chunk.byteLength > PERSONAL_BACKUP_VOLUME_BYTES || !/^[a-f0-9]{64}$/.test(chunk.sha256)) throw new BackupValidationError(`分卷 ${volume.sequence} 含有无效附件分块`);
      const expectedLength = Math.min(PERSONAL_BACKUP_VOLUME_BYTES, asset.size - chunk.chunkIndex * PERSONAL_BACKUP_VOLUME_BYTES);
      if (chunk.byteLength !== expectedLength) throw new BackupValidationError(`附件 ${chunk.assetId} 分块长度无效`);
      bodyBytes += chunk.byteLength;
      allChunks.push(chunk);
    }
    if (bodyBytes !== volume.payloadBytes) throw new BackupValidationError(`分卷 ${volume.sequence} 负载长度不一致`);
    const header = encodeHeader({
      format: PERSONAL_BACKUP_VOLUME_FORMAT,
      formatVersion: PERSONAL_BACKUP_VOLUME_VERSION,
      snapshotId: manifest.snapshotId,
      sequence: volume.sequence,
      totalVolumes: manifest.volumes.length,
      payloadBytes: volume.payloadBytes,
      payloadSha256: volume.payloadSha256,
      chunks: volume.chunks,
    });
    if (volume.byteLength !== PREFIX_BYTES + header.byteLength + volume.payloadBytes) throw new BackupValidationError(`分卷 ${volume.sequence} 声明长度不一致`);
    declaredFileBytes += volume.byteLength;
  }
  let assetCursor = 0;
  let expectedIndex = 0;
  for (const chunk of allChunks) {
    while (manifest.assets[assetCursor]?.chunkCount === 0) assetCursor++;
    const expectedAsset = manifest.assets[assetCursor];
    if (!expectedAsset || chunk.assetId !== expectedAsset.id || chunk.chunkIndex !== expectedIndex) {
      throw new BackupValidationError(`附件 ${chunk.assetId} 分块重复、乱序或缺失`);
    }
    expectedIndex++;
    if (expectedIndex === expectedAsset.chunkCount) {
      assetCursor++;
      expectedIndex = 0;
    }
  }
  while (manifest.assets[assetCursor]?.chunkCount === 0) assetCursor++;
  if (assetCursor !== manifest.assets.length) throw new BackupValidationError(`附件 ${manifest.assets[assetCursor].id} 分块缺失`);
  const manifestBytes = new TextEncoder().encode(JSON.stringify({ format: PERSONAL_BACKUP_VOLUME_FORMAT, manifest })).byteLength;
  if (manifestBytes > MAX_PERSONAL_BACKUP_MANIFEST_BYTES) throw new BackupValidationError('备份清单超过 64 MiB 上限');
  if (manifestBytes + declaredFileBytes > MAX_PERSONAL_BACKUP_TOTAL_BYTES) throw new BackupValidationError('完整备份超过 1 GiB 总文件上限');
  return manifest;
}

async function parseHeader(file: Blob): Promise<{ header: VolumeHeader; headerLength: number }> {
  if (!(file instanceof Blob) || file.size < PREFIX_BYTES || file.size > MAX_VOLUME_FILE_BYTES) throw new BackupValidationError('分卷文件大小无效或超过 8 MiB 负载上限');
  const prefix = new Uint8Array(await file.slice(0, PREFIX_BYTES).arrayBuffer());
  if (!MAGIC.every((byte, index) => prefix[index] === byte)) throw new BackupValidationError('分卷文件标识不匹配');
  const headerLength = new DataView(prefix.buffer, prefix.byteOffset, prefix.byteLength).getUint32(MAGIC.byteLength, false);
  if (headerLength <= 0 || headerLength > MAX_HEADER_BYTES || PREFIX_BYTES + headerLength > file.size) throw new BackupValidationError('分卷头长度无效');
  const headerBytes = await file.slice(PREFIX_BYTES, PREFIX_BYTES + headerLength).arrayBuffer();
  let value: unknown;
  try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(headerBytes)); }
  catch { throw new BackupValidationError('分卷头不是有效 JSON'); }
  assertObject(value, '分卷头');
  return { header: value as unknown as VolumeHeader, headerLength };
}

function ensureHeaderMatches(header: VolumeHeader, manifest: BackupVolumeManifest, volume: BackupVolumeDescriptor): void {
  if (header.format !== PERSONAL_BACKUP_VOLUME_FORMAT || header.formatVersion !== PERSONAL_BACKUP_VOLUME_VERSION || header.snapshotId !== manifest.snapshotId || header.sequence !== volume.sequence || header.totalVolumes !== manifest.volumes.length || header.payloadBytes !== volume.payloadBytes || header.payloadSha256 !== volume.payloadSha256 || !equalJson(header.chunks, volume.chunks)) {
    throw new BackupValidationError(`分卷 ${volume.sequence} 与 manifest 快照不一致`);
  }
}

function abortError(signal?: AbortSignal): void {
  ensureNotAborted(signal);
}

/** Verifies the canonical manifest digest without reading or writing local data. */
export async function verifyBackupVolumeManifest(value: unknown): Promise<BackupVolumeManifest> {
  const manifest = validateBackupVolumeManifest(value);
  if (await hashBytes(new TextEncoder().encode(snapshotDigestInput(manifest))) !== manifest.snapshotSha256) {
    throw new BackupValidationError('manifest 快照 SHA-256 校验失败');
  }
  return manifest;
}

/** Checks the same signed manifest, headers, chunks and assets used by restore.
 * With no asset callback this is read-only and does not open IndexedDB. */
export async function verifyBackupVolumeFiles(
  manifestValue: unknown,
  volumeFiles: readonly Blob[],
  signal?: AbortSignal,
  onProgress?: (completed: number, total: number) => void,
  onAsset?: (asset: PersonalAsset) => Promise<void>,
): Promise<BackupVolumeManifest> {
  abortError(signal);
  const manifest = await verifyBackupVolumeManifest(manifestValue);
  const manifestBytes = new TextEncoder().encode(JSON.stringify({ format: PERSONAL_BACKUP_VOLUME_FORMAT, manifest })).byteLength;
  const totalBytes = manifestBytes + volumeFiles.reduce((sum, file) => sum + (file instanceof Blob ? file.size : 0), 0);
  if (totalBytes > MAX_PERSONAL_BACKUP_TOTAL_BYTES) throw new BackupValidationError('完整备份超过 1 GiB 总文件上限');
  if (volumeFiles.length !== manifest.volumes.length) throw new BackupValidationError(`此快照需要 ${manifest.volumes.length} 卷，当前选择了 ${volumeFiles.length} 卷`);
  const bySequence = new Map<number, Blob>();
  for (const file of volumeFiles) {
    abortError(signal);
    const { header } = await parseHeader(file);
    if (!Number.isSafeInteger(header.sequence) || header.sequence < 1 || header.sequence > manifest.volumes.length || bySequence.has(header.sequence)) throw new BackupValidationError('分卷重复、序号无效或混入了其他快照');
    bySequence.set(header.sequence, file);
  }
  for (let sequence = 1; sequence <= manifest.volumes.length; sequence++) if (!bySequence.has(sequence)) throw new BackupValidationError(`缺少分卷 ${sequence}`);

  let assetIndex = 0;
  let currentDescriptor: BackupVolumeAsset | null = null;
  let currentBytes: Uint8Array | null = null;
  let currentChunkIndex = 0;
  const finishAsset = async () => {
    if (!currentDescriptor || !currentBytes) return;
    if (currentChunkIndex !== currentDescriptor.chunkCount || await hashBytes(currentBytes) !== currentDescriptor.id) throw new BackupValidationError(`附件 ${currentDescriptor.id} 内容 SHA-256 校验失败`);
    abortError(signal);
    await onAsset?.({
      id: currentDescriptor.id,
      mimeType: currentDescriptor.mimeType,
      bytes: currentBytes.buffer.slice(currentBytes.byteOffset, currentBytes.byteOffset + currentBytes.byteLength) as ArrayBuffer,
    });
    assetIndex++;
    currentDescriptor = null;
    currentBytes = null;
    currentChunkIndex = 0;
  };
  const skipEmptyAssets = async (nextId?: string) => {
    while (assetIndex < manifest.assets.length) {
      const descriptor = manifest.assets[assetIndex];
      if (descriptor.size !== 0) break;
      if (nextId && descriptor.id >= nextId) break;
      abortError(signal);
      const empty = new Uint8Array(0);
      if (await hashBytes(empty) !== descriptor.id) throw new BackupValidationError(`空附件 ${descriptor.id} 的内容摘要无效`);
      await onAsset?.({ id: descriptor.id, mimeType: descriptor.mimeType, bytes: new ArrayBuffer(0) });
      assetIndex++;
    }
  };

  await skipEmptyAssets();
  for (const descriptor of manifest.volumes) {
    abortError(signal);
    const file = bySequence.get(descriptor.sequence);
    if (!file || file.size !== descriptor.byteLength) throw new BackupValidationError(`分卷 ${descriptor.sequence} 文件长度与 manifest 不一致`);
    const parsedHeader = await parseHeader(file);
    const header = parsedHeader.header;
    ensureHeaderMatches(header, manifest, descriptor);
    const bytes = new Uint8Array(await file.arrayBuffer());
    const bodyOffset = PREFIX_BYTES + parsedHeader.headerLength;
    const body = bytes.subarray(bodyOffset);
    if (body.byteLength !== descriptor.payloadBytes || await hashBytes(body) !== descriptor.payloadSha256) throw new BackupValidationError(`分卷 ${descriptor.sequence} SHA-256 校验失败`);
    let bodyCursor = 0;
    for (const chunk of descriptor.chunks) {
      abortError(signal);
      await skipEmptyAssets(chunk.assetId);
      if (currentDescriptor && currentDescriptor.id !== chunk.assetId) await finishAsset();
      if (!currentDescriptor) {
        const next = manifest.assets[assetIndex];
        if (!next || next.id !== chunk.assetId) throw new BackupValidationError('分卷附件顺序与 manifest 不一致');
        currentDescriptor = next;
        currentBytes = new Uint8Array(next.size);
        currentChunkIndex = 0;
      }
      if (currentDescriptor.id !== chunk.assetId || chunk.chunkIndex !== currentChunkIndex) throw new BackupValidationError(`附件 ${chunk.assetId} 分块重复、乱序或缺失`);
      const chunkBytes = body.subarray(bodyCursor, bodyCursor + chunk.byteLength);
      if (chunkBytes.byteLength !== chunk.byteLength || await hashBytes(chunkBytes) !== chunk.sha256) throw new BackupValidationError(`附件 ${chunk.assetId} 第 ${chunk.chunkIndex + 1} 块 SHA-256 校验失败`);
      currentBytes!.set(chunkBytes, chunk.chunkIndex * PERSONAL_BACKUP_VOLUME_BYTES);
      bodyCursor += chunk.byteLength;
      currentChunkIndex++;
      if (currentChunkIndex === currentDescriptor.chunkCount) await finishAsset();
    }
    if (bodyCursor !== body.byteLength) throw new BackupValidationError(`分卷 ${descriptor.sequence} 含未声明数据`);
    onProgress?.(descriptor.sequence, manifest.volumes.length);
  }
  if (currentDescriptor) await finishAsset();
  await skipEmptyAssets();
  if (assetIndex !== manifest.assets.length) throw new BackupValidationError('一个或多个备份附件未完整校验');
  abortError(signal);
  return manifest;
}

/** Verifies all files, staging only validated assets before showing a preview. */
export async function previewPersonalBackupVolumes(
  manifestFile: Blob,
  volumeFiles: readonly Blob[],
  signal?: AbortSignal,
  onProgress?: (completed: number, total: number) => void,
): Promise<BackupVolumePreview> {
  abortError(signal);
  if (!(manifestFile instanceof Blob) || manifestFile.size <= 0 || manifestFile.size > MAX_PERSONAL_BACKUP_MANIFEST_BYTES) throw new BackupValidationError('清单文件必须大于 0 且不超过 64 MiB');
  let root: unknown;
  try { root = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(await manifestFile.arrayBuffer())); }
  catch { throw new BackupValidationError('分卷备份清单不是有效 UTF-8 JSON'); }
  assertObject(root, '备份清单');
  if (root.format !== PERSONAL_BACKUP_VOLUME_FORMAT) throw new BackupValidationError('备份清单格式不匹配');
  const totalBytes = manifestFile.size + volumeFiles.reduce((sum, file) => sum + (file instanceof Blob ? file.size : 0), 0);
  if (totalBytes > MAX_PERSONAL_BACKUP_TOTAL_BYTES) throw new BackupValidationError('完整备份超过 1 GiB 总文件上限');
  const stagingSessionId = `restore_${randomId()}`;
  let currentIds: Set<string> | null = null;
  let stagingStarted = false;
  try {
    const manifest = await verifyBackupVolumeFiles(root.manifest, volumeFiles, signal, onProgress, async (asset) => {
      currentIds ??= await readPersonalAssetIds();
      if (currentIds.has(asset.id)) {
        const active = await readAsset(asset.id);
        if (!active || await hashBytes(new Uint8Array(active.bytes)) !== asset.id) throw new BackupValidationError(`本机已有附件 ${asset.id} 内容异常；没有覆盖任何资料`);
      } else {
        abortError(signal);
        stagingStarted = true;
        await stagePersonalRestoreAsset(stagingSessionId, asset);
      }
    });
    abortError(signal);
    const current = await readPersonalData();
    return {
      format: PERSONAL_BACKUP_VOLUME_FORMAT,
      manifest,
      data: manifest.data,
      fileSize: totalBytes,
      volumeCount: manifest.volumes.length,
      assetBytes: manifest.assetBytes,
      assetCount: manifest.assets.length,
      expectedRevision: current.revision,
      stagingSessionId,
      assetIds: manifest.assets.map((asset) => asset.id),
    };
  } catch (error) {
    if (!stagingStarted) throw error;
    try { await clearPersonalRestoreStage(stagingSessionId); }
    catch {
      const message = error instanceof Error ? error.message : '分卷备份校验失败';
      throw new BackupValidationError(`${message}；本次临时数据未能确认清理，请重新打开数据与备份页后重试`);
    }
    throw error;
  }
}

export async function cancelPersonalBackupVolumesPreview(preview: BackupVolumePreview): Promise<void> {
  if (preview?.format !== PERSONAL_BACKUP_VOLUME_FORMAT || typeof preview.stagingSessionId !== 'string') return;
  await clearPersonalRestoreStage(preview.stagingSessionId);
}

/** CAS-commits the preview after rechecking its JSON snapshot and preserves every existing asset. */
export async function restorePersonalBackupVolumes(
  preview: BackupVolumePreview,
  expectedRevision: number,
  signal?: AbortSignal,
): Promise<PersonalData> {
  if (!preview || preview.format !== PERSONAL_BACKUP_VOLUME_FORMAT) throw new BackupValidationError('v2 备份预览无效');
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision !== preview.expectedRevision) throw new BackupValidationError('备份预览 revision 已失效；请重新校验');
  let committed = false;
  let operationFailure: unknown = null;
  try {
    const manifest = jsonCopy<BackupVolumeManifest>(preview.manifest, 'v2 manifest');
    const data = jsonCopy<PersonalDataSnapshot>(preview.data, 'v2 预览资料');
    manifest.data = data;
    await verifyBackupVolumeManifest(manifest);
    if (!equalJson(preview.assetIds, manifest.assets.map((asset) => asset.id)) || !Number.isSafeInteger(preview.expectedRevision)) throw new BackupValidationError('预览附件清单无效');
    validatePersonalData(data, { strictProjects: true });
    const result = await commitPersonalRestoreStage(
      preview.stagingSessionId,
      expectedRevision,
      preview.assetIds,
      manifest.assets.map(({ id, size, mimeType }) => ({ id, size, mimeType })),
      (current) => mergePersonalBackupData(current, data),
      signal,
    );
    committed = true;
    return result;
  } catch (error) {
    operationFailure = signal?.aborted ? new BackupValidationError('恢复已取消；当前资料保持不变') : error;
    throw operationFailure;
  } finally {
    if (!committed) {
      try { await clearPersonalRestoreStage(preview.stagingSessionId); }
      catch {
        const message = operationFailure instanceof Error ? operationFailure.message : '恢复没有提交；当前资料保持不变';
        throw new BackupValidationError(`${message}；本次临时数据未能确认清理，请重新打开数据与备份页后重试`);
      }
    }
  }
}
