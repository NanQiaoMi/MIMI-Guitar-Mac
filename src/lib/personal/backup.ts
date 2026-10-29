import type { PersonalAsset, PersonalData, PersonalDataSnapshot, PracticeFragment, PracticeSession } from './types.ts';
import { hashBytes, mutatePersonalData, readAsset, readPersonalAssetMetadata, readPersonalData } from './repository.ts';
import { normalizePersonalData, PERSONAL_SCHEMA_VERSION, PersonalDataValidationError, validatePersonalData } from './validation.ts';
import { isValidPersonalMimeType, MAX_PERSONAL_ASSET_BYTES, MAX_PERSONAL_BACKUP_ASSETS, MAX_PERSONAL_BACKUP_ASSET_BYTES, MAX_PERSONAL_BACKUP_ENTITIES } from './limits.ts';

export const PERSONAL_BACKUP_FORMAT = 'mimi-personal-backup';
export const PERSONAL_BACKUP_FORMAT_VERSION = 1;
export const MAX_PERSONAL_BACKUP_BYTES = 64 * 1024 * 1024;
export { MAX_PERSONAL_ASSET_BYTES, MAX_PERSONAL_BACKUP_ASSETS, MAX_PERSONAL_BACKUP_ENTITIES };

interface BackupAssetEntry {
  id: string;
  mimeType: string;
  size: number;
  base64: string;
}

interface BackupPayload {
  data: PersonalDataSnapshot;
  assets: BackupAssetEntry[];
}

interface BackupManifest {
  formatVersion: number;
  schemaVersion: number;
  revision: number;
  generatedAt: string;
  counts: Record<string, number>;
  assets: Array<{ id: string; mimeType: string; size: number }>;
  payloadSha256: string;
  assetBytes: number;
}

export interface BackupPreview {
  format: typeof PERSONAL_BACKUP_FORMAT;
  manifest: BackupManifest;
  data: PersonalDataSnapshot;
  assets: PersonalAsset[];
  fileSize: number;
  expectedRevision: number;
  payloadSha256: string;
}

export class BackupValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BackupValidationError';
  }
}

export function canonicalJson(value: unknown): string {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record).filter((key) => record[key] !== undefined).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(',')}}`;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new BackupValidationError('备份附件不是规范的 Base64 数据');
  }
  let binary: string;
  try { binary = atob(value); } catch { throw new BackupValidationError('备份附件无法解码'); }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  if (bytesToBase64(bytes) !== value) throw new BackupValidationError('备份附件 Base64 编码不规范');
  return bytes;
}

export function dataCounts(data: PersonalDataSnapshot, assetCount: number): Record<string, number> {
  const counts: Record<string, number> = {
    scores: data.scores.length,
    favorites: data.favorites.length,
    practiceItems: data.practiceItems.length,
    resumes: data.resumes.length,
    sessions: data.sessions.length,
    projects: data.projects.length,
    originals: data.originals.length,
    history: data.history.length,
    assets: assetCount,
  };
  // Schema-1 manifests are signed with this exact key set. Do not add a zero
  // count when reading them; schema-2 snapshots always emit the new field.
  if (data.schemaVersion === PERSONAL_SCHEMA_VERSION) counts.practiceFragments = data.practiceFragments.length;
  return counts;
}

export function requiredAssetIds(data: PersonalDataSnapshot): Set<string> {
  const ids = new Set<string>();
  for (const score of data.scores) {
    if (score.assetId) ids.add(score.assetId);
    if (score.originalAssetId) ids.add(score.originalAssetId);
  }
  for (const original of data.originals) ids.add(original.assetId);
  return ids;
}

export function equalJson(a: unknown, b: unknown): boolean {
  return canonicalJson(a) === canonicalJson(b);
}

function jsonCopy<T>(value: unknown, label: string): T {
  try {
    const serialized = JSON.stringify(value);
    if (serialized === undefined) throw new Error('not JSON serializable');
    return JSON.parse(serialized) as T;
  } catch {
    throw new BackupValidationError(`${label} 不是有效的 JSON 资料`);
  }
}

export async function exportPersonalBackup(): Promise<Blob> {
  const data = await readPersonalData();
  if (!data.migrationCompleted) throw new BackupValidationError('旧个人数据尚未完整迁移，请在数据设置中检查并重试；完整备份未生成');
  const entityCount = data.scores.length + data.favorites.length + data.practiceItems.length + data.practiceFragments.length + data.resumes.length + data.sessions.length + data.projects.length + data.originals.length + data.history.length;
  if (entityCount > MAX_PERSONAL_BACKUP_ENTITIES) throw new BackupValidationError('个人资料实体总数超过 10,000 个上限；没有生成部分备份');
  const ids = requiredAssetIds(data);
  if (ids.size > MAX_PERSONAL_BACKUP_ASSETS) throw new BackupValidationError('附件数量超过 500 个上限；没有生成部分备份');
  const metadata = await readPersonalAssetMetadata([...ids].sort());
  const metadataById = new Map(metadata.map((asset) => [asset.id, asset]));
  const metadataBytes = metadata.reduce((total, asset) => total + asset.size, 0);
  if (metadata.some((asset) => !Number.isSafeInteger(asset.size) || asset.size < 0 || asset.size > MAX_PERSONAL_ASSET_BYTES || !isValidPersonalMimeType(asset.mimeType))) {
    throw new BackupValidationError('附件预算 metadata 无效；没有生成完整备份');
  }
  if (metadataBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES) throw new BackupValidationError(`被引用附件总量超过 ${MAX_PERSONAL_BACKUP_ASSET_BYTES / 1024 / 1024} MiB 上限；没有生成完整备份`);
  const dataBytes = new TextEncoder().encode(JSON.stringify(data)).byteLength;
  const estimatedBytes = dataBytes + metadata.reduce((size, asset) => size + 4 * Math.ceil(asset.size / 3) + asset.id.length + asset.mimeType.length + 128, 0) + 4096;
  if (estimatedBytes > MAX_PERSONAL_BACKUP_BYTES) throw new BackupValidationError('JSON 备份超过当前 64 MiB 上限；没有生成部分备份');
  const loadedAssets: PersonalAsset[] = [];
  let assetBytes = 0;
  for (const id of [...ids].sort()) {
    const asset = await readAsset(id);
    if (!asset) throw new BackupValidationError(`个人资料引用的附件缺失，备份未生成：${id}`);
    if (!isValidPersonalMimeType(asset.mimeType)) throw new BackupValidationError(`附件 ${id} 的 MIME 类型无效，备份未生成`);
    if (asset.bytes.byteLength > MAX_PERSONAL_ASSET_BYTES) throw new BackupValidationError(`附件 ${id} 超过当前 30 MiB 单文件上限`);
    const declared = metadataById.get(id);
    if (!declared || declared.size !== asset.bytes.byteLength || declared.mimeType !== asset.mimeType) throw new BackupValidationError(`附件 ${id} 与预算 metadata 不一致，备份未生成`);
    assetBytes += asset.bytes.byteLength;
    loadedAssets.push(asset);
  }
  const assetEntries = loadedAssets.map((asset) => {
    const bytes = new Uint8Array(asset.bytes);
    return { id: asset.id, mimeType: asset.mimeType, size: bytes.byteLength, base64: bytesToBase64(bytes) };
  });
  const payload: BackupPayload = { data, assets: assetEntries };
  const payloadSha256 = await hashBytes(new TextEncoder().encode(canonicalJson(payload)));
  const manifest: BackupManifest = {
    formatVersion: PERSONAL_BACKUP_FORMAT_VERSION,
    schemaVersion: data.schemaVersion,
    revision: data.revision,
    generatedAt: new Date().toISOString(),
    counts: dataCounts(data, assetEntries.length),
    assets: assetEntries.map(({ id, mimeType, size }) => ({ id, mimeType, size })),
    payloadSha256,
    assetBytes,
  };
  const serialized = JSON.stringify({ format: PERSONAL_BACKUP_FORMAT, manifest, payload });
  const bytes = new TextEncoder().encode(serialized);
  if (bytes.byteLength > MAX_PERSONAL_BACKUP_BYTES) {
    throw new BackupValidationError('JSON 备份超过当前 64 MiB 上限；没有生成部分备份');
  }
  const after = await readPersonalData();
  if (after.revision !== data.revision) throw new BackupValidationError('备份期间个人资料发生变化，请重新导出');
  return new Blob([bytes], { type: 'application/vnd.mimi.personal-backup+json' });
}

function assertObject(value: unknown, label: string): asserts value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new BackupValidationError(`${label} 必须是对象`);
}

export async function previewBackup(file: Blob): Promise<BackupPreview> {
  if (!(file instanceof Blob)) throw new BackupValidationError('请选择有效的备份文件');
  if (file.size <= 0 || file.size > MAX_PERSONAL_BACKUP_BYTES) {
    throw new BackupValidationError('备份文件必须大于 0 且不超过当前 64 MiB 上限');
  }
  let root: unknown;
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(await file.arrayBuffer());
    root = JSON.parse(text);
  } catch {
    throw new BackupValidationError('备份不是有效的 UTF-8 JSON 文件');
  }
  assertObject(root, '备份内容');
  if (root.format !== PERSONAL_BACKUP_FORMAT) throw new BackupValidationError('备份格式不匹配');
  assertObject(root.manifest, 'manifest');
  assertObject(root.payload, 'payload');
  const manifest = root.manifest as unknown as BackupManifest;
  const payloadObject = root.payload as Record<string, unknown>;
  if (manifest.formatVersion !== PERSONAL_BACKUP_FORMAT_VERSION) throw new BackupValidationError(`不支持的备份格式版本：${String(manifest.formatVersion)}`);
  if (!Number.isSafeInteger(manifest.schemaVersion) || (manifest.schemaVersion !== 1 && manifest.schemaVersion !== PERSONAL_SCHEMA_VERSION)) throw new BackupValidationError(`不支持的个人资料版本：${String(manifest.schemaVersion)}`);
  if (!Number.isSafeInteger(manifest.revision) || manifest.revision < 0) throw new BackupValidationError('manifest revision 无效');
  if (typeof manifest.generatedAt !== 'string' || !Number.isFinite(Date.parse(manifest.generatedAt))) throw new BackupValidationError('manifest 时间无效');
  if (!/^[a-f0-9]{64}$/.test(manifest.payloadSha256)) throw new BackupValidationError('manifest payload SHA-256 无效');
  if (!Number.isSafeInteger(manifest.assetBytes) || manifest.assetBytes < 0 || manifest.assetBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES) throw new BackupValidationError('manifest 附件总量超过 927 MiB 上限');
  if (!payloadObject.data || !Array.isArray(payloadObject.assets)) throw new BackupValidationError('备份缺少资料或附件列表');

  const data = payloadObject.data as PersonalDataSnapshot;
  try { validatePersonalData(data, { strictProjects: true }); } catch (error) {
    if (error instanceof PersonalDataValidationError) throw new BackupValidationError(error.message);
    throw error;
  }
  if (data.revision !== manifest.revision || data.schemaVersion !== manifest.schemaVersion) throw new BackupValidationError('manifest 与资料版本不一致');
  const entityCount = data.scores.length + data.favorites.length + data.practiceItems.length + (data.schemaVersion === 2 ? data.practiceFragments.length : 0) + data.resumes.length + data.sessions.length + data.projects.length + data.originals.length + data.history.length;
  if (entityCount > MAX_PERSONAL_BACKUP_ENTITIES) throw new BackupValidationError('个人资料实体总数超过 10,000 个上限');
  const entries = payloadObject.assets as unknown[];
  if (entries.length > MAX_PERSONAL_BACKUP_ASSETS) throw new BackupValidationError('附件数量超过 500 个上限');
  const assets: PersonalAsset[] = [];
  const seen = new Set<string>();
  let totalBytes = 0;
  for (const [index, raw] of entries.entries()) {
    assertObject(raw, `assets[${index}]`);
    const entry = raw as unknown as BackupAssetEntry;
    if (!/^[a-f0-9]{64}$/.test(entry.id) || !isValidPersonalMimeType(entry.mimeType) || !Number.isSafeInteger(entry.size) || entry.size < 0 || typeof entry.base64 !== 'string') {
      throw new BackupValidationError(`assets[${index}] 字段无效`);
    }
    if (entry.size > MAX_PERSONAL_ASSET_BYTES) throw new BackupValidationError(`assets[${index}] 超过当前 30 MiB 单文件上限`);
    if (seen.has(entry.id)) throw new BackupValidationError(`附件重复：${entry.id}`);
    seen.add(entry.id);
    const bytes = base64ToBytes(entry.base64);
    totalBytes += bytes.byteLength;
    if (bytes.byteLength !== entry.size) throw new BackupValidationError(`附件长度不一致：${entry.id}`);
    if (await hashBytes(bytes) !== entry.id) throw new BackupValidationError(`附件 SHA-256 不匹配：${entry.id}`);
    assets.push({ id: entry.id, mimeType: entry.mimeType, bytes: bytes.slice().buffer as ArrayBuffer });
  }
  if (totalBytes !== manifest.assetBytes) throw new BackupValidationError('manifest 附件总大小不一致');
  if (totalBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES) throw new BackupValidationError('manifest 附件总量超过 927 MiB 上限');
  const expectedIds = [...requiredAssetIds(data)].sort();
  if (!equalJson(expectedIds, [...seen].sort())) throw new BackupValidationError('备份没有完整包含资料引用的附件，无法安全恢复');
  const actualMetadata = assets.map(({ id, mimeType, bytes }) => ({ id, mimeType, size: bytes.byteLength })).sort((a, b) => a.id.localeCompare(b.id));
  const expectedMetadata = Array.isArray(manifest.assets) ? [...manifest.assets].sort((a, b) => a.id.localeCompare(b.id)) : null;
  if (!expectedMetadata || !equalJson(actualMetadata, expectedMetadata)) throw new BackupValidationError('manifest 附件清单不一致');
  if (!equalJson(manifest.counts, dataCounts(data, assets.length))) throw new BackupValidationError('manifest 实体计数不一致');
  const payload: BackupPayload = { data, assets: entries as BackupAssetEntry[] };
  const payloadSha256 = await hashBytes(new TextEncoder().encode(canonicalJson(payload)));
  if (payloadSha256 !== manifest.payloadSha256) throw new BackupValidationError('备份 payload SHA-256 校验失败');

  const current = await readPersonalData();
  return {
    format: PERSONAL_BACKUP_FORMAT,
    manifest,
    data: structuredClone(data),
    assets,
    fileSize: file.size,
    expectedRevision: current.revision,
    payloadSha256,
  };
}

function conflictId(id: string, serialized: string, existing: Set<string>, marker: string): string {
  let hash = 2166136261;
  for (let index = 0; index < serialized.length; index++) {
    hash ^= serialized.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  const suffix = (hash >>> 0).toString(16).padStart(8, '0');
  let candidate = `${id}~${marker}-${suffix}`;
  let serial = 2;
  while (existing.has(candidate)) candidate = `${id}~${marker}-${suffix}-${serial++}`;
  return candidate;
}

function reusableConflictId<T extends { id: string }>(
  sourceId: string,
  candidate: T,
  existing: Iterable<T>,
  marker: string,
): string | null {
  const base = conflictId(sourceId, canonicalJson(candidate), new Set(), marker);
  for (const item of existing) {
    if (item.id !== base && !item.id.startsWith(`${base}-`)) continue;
    if (equalJson({ ...item, id: sourceId }, candidate)) return item.id;
  }
  return null;
}

function mergeSessions(current: PracticeSession[], incoming: PracticeSession[]): PracticeSession[] {
  const sessions = new Map(current.map((session) => [session.id, structuredClone(session)]));
  for (const candidate of incoming) {
    const old = sessions.get(candidate.id);
    if (!old) {
      sessions.set(candidate.id, structuredClone(candidate));
      continue;
    }
    if (old.scoreId !== candidate.scoreId || old.scoreRevision !== candidate.scoreRevision) {
      throw new BackupValidationError(`练习会话 ${candidate.id} 在同一稳定 ID 下关联了不同曲谱版本；为避免重复计时，本次恢复已取消`);
    }
    const byId = new Map<string, PracticeSession['slices'][number]>();
    for (const slice of [...old.slices, ...candidate.slices]) {
      const previous = byId.get(slice.id);
      if (!previous || slice.sequence > previous.sequence || (slice.sequence === previous.sequence && slice.durationMs > previous.durationMs)) byId.set(slice.id, slice);
    }
    const bySequence = new Map<string, PracticeSession['slices'][number]>();
    for (const slice of byId.values()) {
      const key = `${slice.epoch}\0${slice.sequence}`;
      const previous = bySequence.get(key);
      if (!previous || slice.durationMs > previous.durationMs) bySequence.set(key, slice);
    }
    const latest = candidate.updatedAt >= old.updatedAt ? candidate : old;
    sessions.set(candidate.id, { ...structuredClone(latest), slices: [...bySequence.values()].sort((a, b) => a.epoch.localeCompare(b.epoch) || a.sequence - b.sequence) });
  }
  return [...sessions.values()];
}

function practiceFragmentCandidateWins(old: PracticeFragment, candidate: PracticeFragment): boolean {
  if (candidate.updatedAt !== old.updatedAt) return candidate.updatedAt > old.updatedAt;
  const oldDeleted = old.deletedAt !== undefined;
  const candidateDeleted = candidate.deletedAt !== undefined;
  if (oldDeleted !== candidateDeleted) return candidateDeleted;
  const oldJson = canonicalJson(old);
  const candidateJson = canonicalJson(candidate);
  return candidateJson >= oldJson;
}

function choosePracticeFragmentVersion(old: PracticeFragment, candidate: PracticeFragment): PracticeFragment {
  return structuredClone(practiceFragmentCandidateWins(old, candidate) ? candidate : old);
}

function stableIdentityHash(value: string): string {
  const seeds = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35];
  return seeds.map((seed, slot) => {
    let hash = seed;
    for (let index = 0; index < value.length; index++) {
      hash = Math.imul(hash ^ (value.charCodeAt(index) + slot * 17), 0x01000193 + slot * 2);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }).join('');
}

function stablePracticeFragmentConflictId(
  sourceId: string,
  scoreId: string,
  scoreRevision: string,
  existing: Map<string, PracticeFragment>,
): string {
  const identity = canonicalJson({ scoreId, scoreRevision });
  const base = `${sourceId}~backup-${stableIdentityHash(identity)}`;
  let candidate = base;
  let serial = 2;
  while (existing.has(candidate)) {
    const present = existing.get(candidate)!;
    if (present.scoreId === scoreId && present.scoreRevision === scoreRevision && present.id === sourceId) return candidate;
    // The second test handles an already-created branch whose id is the candidate.
    if (present.scoreId === scoreId && present.scoreRevision === scoreRevision) return candidate;
    candidate = `${base}-${serial++}`;
  }
  return candidate;
}

function stableScoreConflictId(sourceId: string, scoreRevision: string, existing: Map<string, PersonalData['scores'][number]>): string {
  const identity = canonicalJson({ sourceId, scoreRevision });
  const base = `${sourceId}~backup-${stableIdentityHash(identity)}`;
  let candidate = base;
  let serial = 2;
  while (existing.has(candidate) && existing.get(candidate)!.revision !== scoreRevision) candidate = `${base}-${serial++}`;
  return candidate;
}

function mergePracticeFragments(
  current: PracticeFragment[],
  incoming: PracticeFragment[],
  scoreIdMap: Map<string, string>,
): PracticeFragment[] {
  const merged = new Map(current.map((fragment) => [fragment.id, structuredClone(fragment)]));
  for (const sourceCandidate of incoming) {
    // Match against the source identity before score IDs are remapped. This lets
    // an old backup encounter a tombstone whose score was later superseded.
    const originalScoreId = sourceCandidate.scoreId;
    const candidate = structuredClone(sourceCandidate);
    candidate.scoreId = scoreIdMap.get(originalScoreId) ?? originalScoreId;
    const sourceIdentity = merged.get(candidate.id);
    if (sourceIdentity && sourceIdentity.scoreId === originalScoreId && sourceIdentity.scoreRevision === candidate.scoreRevision) {
      if (!practiceFragmentCandidateWins(sourceIdentity, sourceCandidate)) continue;
      if (candidate.scoreId === originalScoreId) {
        merged.set(candidate.id, candidate);
      } else {
        // Keep the old source-side version (especially a tombstone) and place a
        // genuinely newer remapped version on a stable branch.
        const branchId = stablePracticeFragmentConflictId(candidate.id, candidate.scoreId, candidate.scoreRevision, merged);
        const branchCandidate = { ...candidate, id: branchId };
        const existingBranch = merged.get(branchId);
        merged.set(branchId, existingBranch && existingBranch.scoreId === branchCandidate.scoreId && existingBranch.scoreRevision === branchCandidate.scoreRevision
          ? choosePracticeFragmentVersion(existingBranch, branchCandidate)
          : branchCandidate);
      }
      continue;
    }

    const old = merged.get(candidate.id);
    if (old && old.scoreId === candidate.scoreId && old.scoreRevision === candidate.scoreRevision) {
      merged.set(candidate.id, choosePracticeFragmentVersion(old, candidate));
      continue;
    }

    if (!old) {
      merged.set(candidate.id, candidate);
      continue;
    }

    const branchId = stablePracticeFragmentConflictId(candidate.id, candidate.scoreId, candidate.scoreRevision, merged);
    const existingBranch = merged.get(branchId);
    const branchCandidate = { ...candidate, id: branchId };
    merged.set(branchId, existingBranch && existingBranch.scoreId === branchCandidate.scoreId && existingBranch.scoreRevision === branchCandidate.scoreRevision
      ? choosePracticeFragmentVersion(existingBranch, branchCandidate)
      : branchCandidate);
  }
  return [...merged.values()].sort((a, b) => a.id.localeCompare(b.id));
}

export function mergePersonalBackupData(current: PersonalData, incomingData: PersonalDataSnapshot): PersonalData {
  const incoming = structuredClone(normalizePersonalData(incomingData));
  const originals = new Map(current.originals.map((original) => [original.id, original]));
  const originalIdMap = new Map<string, string>();
  for (const original of incoming.originals) {
    const old = originals.get(original.id);
    if (!old) originals.set(original.id, original);
    else if (old.assetId !== original.assetId) {
      const reusableId = reusableConflictId(original.id, original, originals.values(), 'backup');
      const id = reusableId ?? conflictId(original.id, canonicalJson(original), new Set(originals.keys()), 'backup');
      originalIdMap.set(original.id, id);
      if (!reusableId) originals.set(id, { ...original, id });
    }
  }
  for (const project of incoming.projects) {
    const source = project.source as unknown as { id?: unknown };
    if (source && typeof source.id === 'string') source.id = originalIdMap.get(source.id) ?? source.id;
  }

  const projects = new Map(current.projects.map((project) => [project.id, project]));
  const projectIdMap = new Map<string, string>();
  for (const project of incoming.projects) {
    const old = projects.get(project.id);
    if (!old) projects.set(project.id, project);
    else if (!equalJson(old, project)) {
      const reusableId = reusableConflictId(project.id, project, projects.values(), 'backup');
      const id = reusableId ?? conflictId(project.id, canonicalJson(project), new Set(projects.keys()), 'backup');
      projectIdMap.set(project.id, id);
      project.id = id;
      if (!reusableId) projects.set(id, project);
    }
  }
  // Scores reference projects; resolve those references before deriving deterministic score conflict IDs.
  for (const score of incoming.scores) if (score.projectId) score.projectId = projectIdMap.get(score.projectId) ?? score.projectId;

  const scores = new Map(current.scores.map((score) => [score.id, score]));
  const scoreIdMap = new Map<string, string>();
  for (const score of incoming.scores) {
    const sourceId = score.id;
    const old = scores.get(sourceId);
    if (old && old.revision !== score.revision) {
      const id = stableScoreConflictId(sourceId, score.revision, scores);
      scoreIdMap.set(sourceId, id);
      score.id = id;
      const priorCopy = scores.get(id);
      if (!priorCopy || score.updatedAt >= priorCopy.updatedAt) scores.set(id, score);
    } else if (!old || score.updatedAt >= old.updatedAt) {
      scores.set(sourceId, score);
    }
  }
  const remapScoreId = (id: string) => scoreIdMap.get(id) ?? id;
  for (const item of incoming.practiceItems) item.scoreId = remapScoreId(item.scoreId);
  for (const resume of incoming.resumes) resume.scoreId = remapScoreId(resume.scoreId);
  for (const session of incoming.sessions) session.scoreId = remapScoreId(session.scoreId);
  incoming.favorites = incoming.favorites.map(remapScoreId);

  const favorites = [...new Set([...current.favorites, ...incoming.favorites])];
  const keyedMerge = <T extends { scoreId: string; updatedAt: number }>(a: T[], b: T[]) => {
    const result = new Map(a.map((entry) => [entry.scoreId, entry]));
    for (const entry of b) {
      const old = result.get(entry.scoreId);
      if (!old || entry.updatedAt >= old.updatedAt) result.set(entry.scoreId, entry);
    }
    return [...result.values()];
  };
  const history = new Map(current.history.map((entry) => [`${entry.id}\0${entry.url}\0${entry.time}`, entry]));
  for (const entry of incoming.history) history.set(`${entry.id}\0${entry.url}\0${entry.time}`, entry);
  return {
    schemaVersion: PERSONAL_SCHEMA_VERSION,
    revision: current.revision,
    scores: [...scores.values()],
    favorites,
    practiceItems: keyedMerge(current.practiceItems, incoming.practiceItems),
    practiceFragments: mergePracticeFragments(current.practiceFragments, incoming.practiceFragments, scoreIdMap),
    resumes: keyedMerge(current.resumes, incoming.resumes),
    sessions: mergeSessions(current.sessions, incoming.sessions),
    projects: [...projects.values()],
    originals: [...originals.values()],
    history: [...history.values()].sort((a, b) => b.time - a.time),
    settings: { ...current.settings, ...incoming.settings },
    migrationCompleted: current.migrationCompleted && incoming.migrationCompleted,
  };
}

export async function restoreBackup(preview: BackupPreview, expectedRevision: number): Promise<PersonalData> {
  if (!preview || preview.format !== PERSONAL_BACKUP_FORMAT) throw new BackupValidationError('备份预览无效');
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision !== preview.expectedRevision) throw new BackupValidationError('备份预览版本已失效，请重新预览后再恢复');
  // Svelte $state proxies cannot be structuredClone'd in browsers. Cross the public
  // restore boundary through JSON semantics before validation, hashing, and merging.
  const data = jsonCopy<PersonalDataSnapshot>(preview.data, '备份预览资料');
  const manifest = jsonCopy<BackupManifest>(preview.manifest, '备份预览 manifest');
  const payloadSha256 = preview.payloadSha256;
  if (manifest.formatVersion !== PERSONAL_BACKUP_FORMAT_VERSION || manifest.schemaVersion !== data.schemaVersion || !/^[a-f0-9]{64}$/.test(payloadSha256)) {
    throw new BackupValidationError('备份预览版本或摘要无效');
  }
  if (data.revision !== manifest.revision) throw new BackupValidationError('备份预览资料与 manifest 不一致');
  if (payloadSha256 !== manifest.payloadSha256) throw new BackupValidationError('备份预览摘要已改变，请重新预览');
  validatePersonalData(data, { strictProjects: true });
  const assets = Array.from(preview.assets, (asset) => {
    if (!asset || typeof asset.id !== 'string' || typeof asset.mimeType !== 'string' || !(asset.bytes instanceof ArrayBuffer)) {
      throw new BackupValidationError('备份预览附件字段无效');
    }
    return { id: asset.id, mimeType: asset.mimeType, bytes: new Uint8Array(asset.bytes).slice().buffer as ArrayBuffer };
  });
  if (assets.length > MAX_PERSONAL_BACKUP_ASSETS || assets.some((asset) => asset.bytes.byteLength > MAX_PERSONAL_ASSET_BYTES)) {
    throw new BackupValidationError('备份预览附件超过当前容量限制');
  }
  const payload: BackupPayload = {
    data,
    assets: assets.map((asset) => ({ id: asset.id, mimeType: asset.mimeType, size: asset.bytes.byteLength, base64: bytesToBase64(new Uint8Array(asset.bytes)) })),
  };
  const assetIds = assets.map((asset) => asset.id).sort();
  if (!equalJson(assetIds, [...requiredAssetIds(data)].sort())) throw new BackupValidationError('备份预览没有完整包含资料引用的附件');
  for (const asset of assets) if (await hashBytes(new Uint8Array(asset.bytes)) !== asset.id) throw new BackupValidationError(`备份预览附件校验失败：${asset.id}`);
  const assetMetadata = assets.map((asset) => ({ id: asset.id, mimeType: asset.mimeType, size: asset.bytes.byteLength })).sort((a, b) => a.id.localeCompare(b.id));
  const manifestAssets = Array.isArray(manifest.assets) ? [...manifest.assets].sort((a, b) => a.id.localeCompare(b.id)) : null;
  const assetBytes = assets.reduce((total, asset) => total + asset.bytes.byteLength, 0);
  if (!manifestAssets || !equalJson(assetMetadata, manifestAssets) || assetBytes !== manifest.assetBytes || !equalJson(manifest.counts, dataCounts(data, assets.length))) {
    throw new BackupValidationError('备份预览清单与资料不一致');
  }
  if (await hashBytes(new TextEncoder().encode(canonicalJson(payload))) !== payloadSha256) throw new BackupValidationError('备份预览内容已改变，请重新预览');

  return mutatePersonalData((current) => {
    const merged = mergePersonalBackupData(current, data);
    Object.assign(current, merged);
  }, { expectedRevision, assets });
}
