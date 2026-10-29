/** Backup diagnostics share the format and content checks used by restore. */
import type { PersonalDataSnapshot } from './types.ts';
import {
  PERSONAL_BACKUP_VOLUME_FORMAT,
  validateBackupVolumeManifest,
  verifyBackupVolumeFiles,
  verifyBackupVolumeManifest,
  type BackupVolumeManifest,
} from './backupVolumes.ts';
import { equalJson } from './backup.ts';

export interface IntegrityCheckResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
  details: {
    manifestChecksum: boolean;
    dataChecksum: boolean;
    assetChecksums: boolean;
    volumeCount: boolean;
    entityCounts: boolean;
    assetReferences: boolean;
  };
}

export interface BackupMetrics {
  totalSize: number;
  entityCount: number;
  assetCount: number;
  assetBytes: number;
  volumeCount: number;
  selectedVolumeCount: number;
  /** Compares counts and sizes only, without identifying or verifying files. */
  selectedSizesMatch: boolean;
}

/** Checks the signed data and every binary volume without staging or writing data. */
export async function verifyBackupIntegrity(
  manifest: BackupVolumeManifest,
  volumes: readonly Blob[],
  data: PersonalDataSnapshot,
): Promise<IntegrityCheckResult> {
  const result: IntegrityCheckResult = {
    isValid: false,
    errors: [],
    warnings: [],
    details: {
      manifestChecksum: false,
      dataChecksum: false,
      assetChecksums: false,
      volumeCount: false,
      entityCounts: false,
      assetReferences: false,
    },
  };
  try {
    const validated = validateBackupVolumeManifest(manifest);
    result.details.entityCounts = true;
    result.details.assetReferences = true;
    result.details.volumeCount = volumes.length === validated.volumes.length;
    await verifyBackupVolumeManifest(validated);
    result.details.manifestChecksum = true;
    // The manifest digest signs its data snapshot; it is not a separate data hash.
    result.details.dataChecksum = equalJson(data, validated.data);
    if (!result.details.dataChecksum) result.errors.push('数据快照与已签名清单不一致');
    await verifyBackupVolumeFiles(validated, volumes);
    result.details.assetChecksums = true;
    result.isValid = result.errors.length === 0;
  } catch (error) {
    result.errors.push(error instanceof Error ? error.message : '备份完整性检查失败');
  }
  return result;
}

/** Statistics describe file selection, without claiming that content is verified. */
export function calculateBackupMetrics(manifest: BackupVolumeManifest, volumes: readonly Blob[]): BackupMetrics {
  const validated = validateBackupVolumeManifest(manifest);
  const manifestBytes = new TextEncoder().encode(JSON.stringify({ format: PERSONAL_BACKUP_VOLUME_FORMAT, manifest: validated })).byteLength;
  const expectedSizes = validated.volumes.map((volume) => volume.byteLength).sort((a, b) => a - b);
  const selectedSizes = volumes.map((volume) => volume.size).sort((a, b) => a - b);
  return {
    totalSize: manifestBytes + volumes.reduce((sum, volume) => sum + volume.size, 0),
    entityCount: Object.entries(validated.counts).reduce((sum, [key, count]) => sum + (key === 'assets' ? 0 : count), 0),
    assetCount: validated.assets.length,
    assetBytes: validated.assetBytes,
    volumeCount: validated.volumes.length,
    selectedVolumeCount: volumes.length,
    selectedSizesMatch: equalJson(expectedSizes, selectedSizes),
  };
}

/** Structural preflight only; success does not imply a verified SHA-256 digest. */
export function quickValidateBackup(manifest: unknown): { valid: boolean; errors: string[] } {
  try {
    validateBackupVolumeManifest(manifest);
    return { valid: true, errors: [] };
  } catch (error) {
    return { valid: false, errors: [error instanceof Error ? error.message : '备份清单无效'] };
  }
}
