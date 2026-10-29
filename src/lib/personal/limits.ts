export const MAX_PERSONAL_ASSET_BYTES = 30 * 1024 * 1024;
export const MAX_PERSONAL_BACKUP_ASSETS = 500;
export const MAX_PERSONAL_BACKUP_ENTITIES = 10_000;
export const MAX_PERSONAL_BACKUP_MANIFEST_BYTES = 64 * 1024 * 1024;
export const PERSONAL_BACKUP_VOLUME_BYTES = 8 * 1024 * 1024;
export const MAX_PERSONAL_BACKUP_VOLUMES = 128;
export const MAX_PERSONAL_BACKUP_TOTAL_BYTES = 1024 * 1024 * 1024;
/** Leaves one MiB beyond the manifest and 128 maximum-size volume headers/prefixes. */
export const MAX_PERSONAL_BACKUP_ASSET_BYTES = 927 * 1024 * 1024;
/** Reserves 4 MiB inside the manifest budget for metadata and per-volume chunk descriptors. */
export const MAX_PERSONAL_DATA_JSON_BYTES = 60 * 1024 * 1024;

export interface PersonalBackupAssetMetadata {
  id: string;
  size: number;
}

export interface PersonalBackupWriteUsage {
  assetBytes: number;
  assetCount: number;
  volumeCount: number;
  entityCount: number;
  dataJsonBytes: number;
}

/** Mirrors v2's sorted asset chunks and next-fit 8 MiB volume packing without reading asset bodies. */
export function countPackedPersonalBackupVolumes(assets: readonly PersonalBackupAssetMetadata[]): number {
  const sorted = [...assets].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  let volumeCount = 0;
  let payloadBytes = 0;
  for (const asset of sorted) {
    if (!Number.isSafeInteger(asset.size) || asset.size < 0) throw new Error(`附件 ${asset.id} 的大小 metadata 无效`);
    let remaining = asset.size;
    while (remaining > 0) {
      const chunkBytes = Math.min(PERSONAL_BACKUP_VOLUME_BYTES, remaining);
      if (payloadBytes > 0 && payloadBytes + chunkBytes > PERSONAL_BACKUP_VOLUME_BYTES) {
        volumeCount++;
        payloadBytes = 0;
      }
      payloadBytes += chunkBytes;
      remaining -= chunkBytes;
      if (payloadBytes === PERSONAL_BACKUP_VOLUME_BYTES) {
        volumeCount++;
        payloadBytes = 0;
      }
    }
  }
  if (payloadBytes > 0) volumeCount++;
  return volumeCount;
}

/**
 * Keeps already-over-budget local data editable while preventing its referenced
 * attachment bytes/count from growing until every backup budget is back in range.
 */
export function enforcePersonalBackupAssetGrowthBudget(current: PersonalBackupWriteUsage, proposed: PersonalBackupWriteUsage): void {
  for (const [label, usage] of [['current', current], ['proposed', proposed]] as const) {
    if (Object.values(usage).some((value) => !Number.isSafeInteger(value) || value < 0)) {
      throw new Error(`个人资料 ${label} 的备份预算 metadata 无效`);
    }
  }

  const proposedOverBudget = proposed.assetBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES
    || proposed.assetCount > MAX_PERSONAL_BACKUP_ASSETS
    || proposed.volumeCount > MAX_PERSONAL_BACKUP_VOLUMES
    || proposed.entityCount > MAX_PERSONAL_BACKUP_ENTITIES
    || proposed.dataJsonBytes > MAX_PERSONAL_DATA_JSON_BYTES;

  if (proposed.assetBytes > MAX_PERSONAL_BACKUP_ASSET_BYTES && proposed.assetBytes > current.assetBytes) {
    throw new Error(`被引用附件总量超过完整备份的 ${MAX_PERSONAL_BACKUP_ASSET_BYTES / 1024 / 1024} MiB 预算；请先整理现有引用，本次新增未保存`);
  }
  if (proposed.assetCount > MAX_PERSONAL_BACKUP_ASSETS && proposed.assetCount > current.assetCount) {
    throw new Error(`个人资料超过完整备份的 ${MAX_PERSONAL_BACKUP_ASSETS} 份附件预算；请先整理引用，本次新增未保存`);
  }
  if (proposed.volumeCount > MAX_PERSONAL_BACKUP_VOLUMES && proposed.volumeCount > current.volumeCount) {
    throw new Error(`附件按 8 MiB 分卷后超过 ${MAX_PERSONAL_BACKUP_VOLUMES} 卷预算；请先整理现有引用，本次新增未保存`);
  }
  if (proposedOverBudget && proposed.assetBytes > current.assetBytes) {
    throw new Error('个人资料仍超过完整备份预算，不能增加被引用附件总量；请先减少超限资料');
  }
  if (proposedOverBudget && proposed.assetCount > current.assetCount) {
    throw new Error('个人资料仍超过完整备份预算，不能增加被引用附件数量；请先减少超限资料');
  }
}

export function isValidPersonalMimeType(value: unknown): value is string {
  const token = "[!#$%&'*+.^_`|~0-9A-Za-z-]+";
  const mimeTypePattern = new RegExp(`^${token}/${token}(?:\\s*;\\s*${token}(?:\\s*=\\s*(?:${token}|"[^"]*"))?)*$`);
  return typeof value === 'string'
    && value.length > 0
    && value.length <= 256
    && !/[\u0000-\u001f\u007f]/.test(value)
    && mimeTypePattern.test(value);
}
