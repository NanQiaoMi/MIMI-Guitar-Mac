import assert from 'node:assert/strict';
import test from 'node:test';
import { countPackedPersonalBackupVolumes, enforcePersonalBackupAssetGrowthBudget } from '../src/lib/personal/limits.ts';

const mib = 1024 * 1024;
const assets = Array.from({ length: 129 }, (_, index) => ({ id: String(index).padStart(4, '0'), size: 7 * mib }));
const existing = { assetBytes: 903 * mib, assetCount: 129, volumeCount: 129, entityCount: 129, dataJsonBytes: 1024 };

test('already-over-volume-budget data cannot grow by filling the final volume', () => {
  const proposed = [...assets, { id: 'last', size: mib / 2 }];
  assert.equal(countPackedPersonalBackupVolumes(assets), 129);
  assert.equal(countPackedPersonalBackupVolumes(proposed), 129);
  assert.throws(() => enforcePersonalBackupAssetGrowthBudget(existing, {
    ...existing, assetBytes: existing.assetBytes + mib / 2, assetCount: 130,
  }), /仍超过完整备份预算/);
});

test('over-budget data allows metadata edits, equal-size replacements and reducing assets', () => {
  assert.doesNotThrow(() => enforcePersonalBackupAssetGrowthBudget(existing, { ...existing, dataJsonBytes: 2048 }));
  assert.doesNotThrow(() => enforcePersonalBackupAssetGrowthBudget(existing, { ...existing }));
  assert.doesNotThrow(() => enforcePersonalBackupAssetGrowthBudget(existing, { ...existing, assetBytes: 902 * mib }));
  assert.doesNotThrow(() => enforcePersonalBackupAssetGrowthBudget(existing, {
    ...existing, assetBytes: 896 * mib, assetCount: 128, volumeCount: 128,
  }));
});

test('any remaining backup overage blocks attachment count or byte growth', () => {
  const base = { assetBytes: mib, assetCount: 1, volumeCount: 1, entityCount: 10001, dataJsonBytes: 1024 };
  assert.throws(() => enforcePersonalBackupAssetGrowthBudget(base, { ...base, assetCount: 2 }), /不能增加被引用附件数量/);
  assert.throws(() => enforcePersonalBackupAssetGrowthBudget(base, { ...base, assetBytes: mib + 1 }), /不能增加被引用附件总量/);
  assert.doesNotThrow(() => enforcePersonalBackupAssetGrowthBudget(base, { ...base, assetCount: 2, entityCount: 10000 }));
  const jsonOverage = { ...base, entityCount: 1, dataJsonBytes: 61 * mib };
  assert.throws(() => enforcePersonalBackupAssetGrowthBudget(jsonOverage, { ...jsonOverage, assetBytes: mib + 1 }), /仍超过完整备份预算/);
});
