import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { canonicalJson, dataCounts, requiredAssetIds } from '../../../src/lib/personal/backup.ts';
import { validatePersonalData } from '../../../src/lib/personal/validation.ts';

const path = process.argv[2];
if (!path) throw new Error('Pass the actual file path returned by the browser download.');
const root = JSON.parse(await readFile(path, 'utf8'));
assert.equal(root.format, 'mimi-personal-backup');
assert.equal(root.manifest.formatVersion, 1);
const { data, assets } = root.payload;
validatePersonalData(data, { strictProjects: true });
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
assert.equal(sha(canonicalJson(root.payload)), root.manifest.payloadSha256);
assert.deepEqual(dataCounts(data, assets.length), root.manifest.counts);
assert.deepEqual([...requiredAssetIds(data)].sort(), assets.map((asset) => asset.id).sort());
let total = 0;
for (const asset of assets) {
  const bytes = Buffer.from(asset.base64, 'base64');
  assert.equal(bytes.length, asset.size);
  assert.equal(sha(bytes), asset.id);
  total += bytes.length;
}
assert.equal(total, root.manifest.assetBytes);
for (const session of data.sessions) {
  assert.equal(new Set(session.slices.map((slice) => slice.id)).size, session.slices.length);
  assert.ok(session.slices.every((slice) => Number.isFinite(slice.durationMs) && slice.durationMs >= 0));
}
const summary = {
  revision: data.revision, payloadSha256: root.manifest.payloadSha256, assetsVerified: assets.length,
  queue: data.practiceItems.map((item) => ({ ...item, title: data.scores.find((score) => score.id === item.scoreId)?.title })),
  scores: data.scores.map(({ id, source, revision, title, assetId }) => ({ id, source, revision, title, assetId })),
  resumes: data.resumes,
  sessions: data.sessions.map(({ slices, ...session }) => ({ ...session, sliceCount: slices.length,
    durationMs: slices.reduce((sum, slice) => sum + slice.durationMs, 0), slices })),
};
if (process.argv[3]) await writeFile(process.argv[3], JSON.stringify(summary, null, 2) + '\n');
console.log(JSON.stringify({ revision: summary.revision, assetsVerified: assets.length, sessions: summary.sessions.map(({ id, state, durationMs, sliceCount }) => ({ id, state, durationMs, sliceCount })) }, null, 2));
