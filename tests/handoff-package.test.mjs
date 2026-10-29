import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { verifyHandoff, parseVerifyArgs } from '../tools/verify-handoff.mjs';

async function fixture(t) {
  const root = await mkdtemp(path.join(tmpdir(), 'mimi-handoff-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'project'));
  const bytes = Buffer.from('a portable score package\n');
  await writeFile(path.join(root, 'project', 'README.md'), bytes);
  const manifest = { schemaVersion: 1, sourceRevision: 'fixture', fileCount: 1, totalBytes: bytes.length,
    files: [{ path: 'project/README.md', bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') }] };
  await writeFile(path.join(root, 'PACKAGE-MANIFEST.json'), JSON.stringify(manifest));
  return { root, manifest };
}

test('handoff verifier checks actual bytes and fails if same-size content was changed', async (t) => {
  const { root, manifest } = await fixture(t);
  assert.equal((await verifyHandoff(root)).status, 'verified');
  const file = path.join(root, 'project', 'README.md');
  const content = await readFile(file);
  content[0] ^= 1;
  await writeFile(file, content);
  await assert.rejects(verifyHandoff(root), /Checksum mismatch/);
  assert.equal(manifest.fileCount, 1);
});

test('handoff verifier rejects escaping and case-colliding paths before reading them', async (t) => {
  const { root, manifest } = await fixture(t);
  manifest.files[0].path = '../outside';
  await writeFile(path.join(root, 'PACKAGE-MANIFEST.json'), JSON.stringify(manifest));
  await assert.rejects(verifyHandoff(root), /Invalid manifest file entry/);
  manifest.files[0].path = 'project/README.md';
  manifest.files.push({ ...manifest.files[0], path: 'Project/readme.MD' });
  manifest.fileCount = 2; manifest.totalBytes *= 2;
  await writeFile(path.join(root, 'PACKAGE-MANIFEST.json'), JSON.stringify(manifest));
  await assert.rejects(verifyHandoff(root), /case-colliding/);
});

test('handoff verifier rejects a missing file and inconsistent manifest totals', async (t) => {
  const { root, manifest } = await fixture(t);
  await rm(path.join(root, 'project', 'README.md'));
  await assert.rejects(verifyHandoff(root), /ENOENT/);
  manifest.totalBytes++;
  await writeFile(path.join(root, 'PACKAGE-MANIFEST.json'), JSON.stringify(manifest));
  await assert.rejects(verifyHandoff(root), /byte count/);
});

test('handoff verifier rejects linked payload files where supported', async (t) => {
  const { root } = await fixture(t);
  const file = path.join(root, 'project', 'README.md');
  const target = path.join(root, 'target.md');
  await writeFile(target, await readFile(file));
  await rm(file);
  try { await symlink(target, file); }
  catch (error) { if (['EPERM', 'EACCES'].includes(error.code)) { t.skip('symlink creation is not permitted on this host'); return; } throw error; }
  await assert.rejects(verifyHandoff(root), /unsafe file/);
});

test('handoff verifier CLI rejects incomplete or unknown options', () => {
  assert.deepEqual(parseVerifyArgs(['--root', '/tmp/package']), { root: '/tmp/package' });
  assert.equal(parseVerifyArgs(['--help']).help, true);
  assert.throws(() => parseVerifyArgs(['--root']), /Usage/);
  assert.throws(() => parseVerifyArgs(['--skip-checks']), /Usage/);
});
