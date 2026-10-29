import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { checkScoreResources, prepareScoreResources, ScoreResourceSafetyError } from '../tools/lib/score-resource-files.mjs';

const categories = {
  scores: ['1sdc49P3eKm.ibe', 'second.ibe'],
  xhe: ['text-score.json'],
  screenshots: ['cover.jpg'],
  soundfonts: ['0.sf2'],
};

async function makeProject(root) {
  const publicRoot = path.join(root, 'public');
  const storageRoot = path.join(publicRoot, 'storage');
  for (const category of Object.keys(categories)) await mkdir(path.join(storageRoot, category), { recursive: true });
  return { root, publicRoot, storageRoot };
}

async function makeFixture() {
  const temporaryDirectory = await realpath(tmpdir());
  const temporaryRoot = await mkdtemp(path.join(temporaryDirectory, 'score-resource-files-'));
  const source = await makeProject(path.join(temporaryRoot, 'source-project'));
  const target = await makeProject(path.join(temporaryRoot, 'target-project'));
  const values = new Map();
  for (const [category, names] of Object.entries(categories)) {
    for (const name of names) {
      const relative = `${category}/${name}`;
      const bytes = Buffer.from(`fixture:${relative}:original`);
      values.set(relative, bytes);
      await writeFile(path.join(source.storageRoot, category, name), bytes);
    }
  }
  return { temporaryRoot, source, target, values };
}

async function cleanup(fixture) {
  const temporaryDirectory = await realpath(tmpdir());
  assert.ok(path.resolve(fixture.temporaryRoot).startsWith(path.join(temporaryDirectory, 'score-resource-files-')));
  await rm(fixture.temporaryRoot, { recursive: true, force: true });
}

test('preflight finds a differing target file before copying any missing resource', async () => {
  const fixture = await makeFixture();
  try {
    const existing = path.join(fixture.target.storageRoot, 'scores', '1sdc49P3eKm.ibe');
    const previousBytes = Buffer.from('keep-existing-target-bytes');
    await writeFile(existing, previousBytes);

    const report = await prepareScoreResources({
      sourceRoot: fixture.source.storageRoot,
      targetRoot: fixture.target.storageRoot,
      apply: true,
    });

    assert.equal(report.ok, false);
    assert.equal(report.status, 'conflict');
    assert.deepEqual(report.copied, []);
    assert.equal(report.conflicts.some((entry) => entry.path === 'scores/1sdc49P3eKm.ibe'), true);
    await assert.rejects(readFile(path.join(fixture.target.storageRoot, 'scores', 'second.ibe')), { code: 'ENOENT' });
    assert.deepEqual(await readFile(existing), previousBytes);
  } finally {
    await cleanup(fixture);
  }
});

test('apply adds only missing files, leaves source bytes unchanged, and reruns idempotently', async () => {
  const fixture = await makeFixture();
  try {
    const unchangedPath = path.join(fixture.target.storageRoot, 'soundfonts', '0.sf2');
    await writeFile(unchangedPath, fixture.values.get('soundfonts/0.sf2'));
    const sourceBefore = await readFile(path.join(fixture.source.storageRoot, 'scores', '1sdc49P3eKm.ibe'));

    const first = await prepareScoreResources({
      sourceRoot: fixture.source.storageRoot,
      targetRoot: fixture.target.storageRoot,
      apply: true,
      concurrency: 2,
    });
    assert.equal(first.ok, true);
    assert.equal(first.status, 'prepared');
    assert.equal(first.copied.length, fixture.values.size - 1);
    assert.equal(first.summary.missing, 0);
    assert.deepEqual(await readFile(path.join(fixture.source.storageRoot, 'scores', '1sdc49P3eKm.ibe')), sourceBefore);

    const second = await prepareScoreResources({
      sourceRoot: fixture.source.storageRoot,
      targetRoot: fixture.target.storageRoot,
      apply: true,
    });
    assert.equal(second.ok, true);
    assert.equal(second.copied.length, 0);
    assert.equal(second.summary.missing, 0);

    const verified = await checkScoreResources({
      sourceRoot: fixture.source.storageRoot,
      publicRoot: fixture.target.storageRoot,
    });
    assert.equal(verified.ok, true);
    assert.equal(verified.status, 'verified');
  } finally {
    await cleanup(fixture);
  }
});

test('built-output check detects a resource that Astro did not copy and then verifies exact contents', async () => {
  const fixture = await makeFixture();
  try {
    const prepared = await prepareScoreResources({
      sourceRoot: fixture.source.storageRoot,
      targetRoot: fixture.target.storageRoot,
      apply: true,
    });
    assert.equal(prepared.ok, true);

    const distStorage = path.join(fixture.target.root, 'dist', 'client', 'storage');
    await mkdir(path.join(distStorage, 'scores'), { recursive: true });
    await writeFile(path.join(distStorage, 'scores', '1sdc49P3eKm.ibe'), fixture.values.get('scores/1sdc49P3eKm.ibe'));
    const incomplete = await checkScoreResources({
      sourceRoot: fixture.source.storageRoot,
      publicRoot: fixture.target.storageRoot,
      distRoot: distStorage,
    });
    assert.equal(incomplete.ok, false);
    assert.equal(incomplete.dist.missing.length, fixture.values.size - 1);

    assert.equal(distStorage, path.join(fixture.target.root, 'dist', 'client', 'storage'));
    await rm(distStorage, { recursive: true, force: true });
    await mkdir(path.dirname(distStorage), { recursive: true });
    await import('node:fs/promises').then(({ cp }) => cp(fixture.target.storageRoot, distStorage, { recursive: true }));
    const complete = await checkScoreResources({
      sourceRoot: fixture.source.storageRoot,
      publicRoot: fixture.target.storageRoot,
      distRoot: distStorage,
    });
    assert.equal(complete.ok, true);
    assert.equal(complete.operation, 'check-built');

    await writeFile(path.join(distStorage, 'scores', '1sdc49P3eKm.ibe'), 'changed-after-build');
    const changed = await checkScoreResources({
      sourceRoot: fixture.source.storageRoot,
      publicRoot: fixture.target.storageRoot,
      distRoot: distStorage,
    });
    assert.equal(changed.ok, false);
    assert.equal(changed.dist.different.some((entry) => entry.path === 'scores/1sdc49P3eKm.ibe'), true);
  } finally {
    await cleanup(fixture);
  }
});

test('refuses writes into the source project tree or through a junction/symlink target', async (t) => {
  const fixture = await makeFixture();
  try {
    const nestedProject = path.join(fixture.source.root, 'nested-target');
    const nestedStorage = path.join(nestedProject, 'public', 'storage');
    await mkdir(path.dirname(nestedStorage), { recursive: true });
    await assert.rejects(
      prepareScoreResources({ sourceRoot: fixture.source.storageRoot, targetRoot: nestedStorage, apply: true }),
      ScoreResourceSafetyError,
    );

    const linkedProject = path.join(fixture.temporaryRoot, 'linked-project');
    const linkedPublic = path.join(linkedProject, 'public');
    await mkdir(linkedPublic, { recursive: true });
    const physicalTarget = path.join(fixture.temporaryRoot, 'physical-storage');
    await mkdir(physicalTarget, { recursive: true });
    const linkedStorage = path.join(linkedPublic, 'storage');
    try {
      await symlink(physicalTarget, linkedStorage, process.platform === 'win32' ? 'junction' : 'dir');
    } catch (error) {
      if (['EPERM', 'EACCES', 'ENOSYS', 'EINVAL'].includes(error?.code)) {
        t.skip(`platform cannot create a test junction/symlink: ${error.code}`);
        return;
      }
      throw error;
    }
    await assert.rejects(
      prepareScoreResources({ sourceRoot: fixture.source.storageRoot, targetRoot: linkedStorage, apply: true }),
      ScoreResourceSafetyError,
    );
    await assert.rejects(readFile(path.join(physicalTarget, 'scores', '1sdc49P3eKm.ibe')), { code: 'ENOENT' });
  } finally {
    await cleanup(fixture);
  }
});

test('rejects unsupported source files instead of silently omitting them', async () => {
  const fixture = await makeFixture();
  try {
    await writeFile(path.join(fixture.source.storageRoot, 'scores', 'notes.txt'), 'not a score resource');
    await assert.rejects(
      prepareScoreResources({ sourceRoot: fixture.source.storageRoot, targetRoot: fixture.target.storageRoot }),
      /unsupported file type/,
    );
  } finally {
    await cleanup(fixture);
  }
});

test('an incomplete source cannot pass merely because the destination matches it', async () => {
  const fixture = await makeFixture();
  try {
    const requiredPaths = ['scores/catalog-reference-not-in-source.ibe'];
    await assert.rejects(prepareScoreResources({ sourceRoot: fixture.source.storageRoot, targetRoot: fixture.target.storageRoot, requiredPaths, apply: true }), /missing required catalog/);
    await assert.rejects(checkScoreResources({ sourceRoot: fixture.source.storageRoot, publicRoot: fixture.target.storageRoot, requiredPaths }), /missing required catalog/);
    await assert.rejects(readFile(path.join(fixture.target.storageRoot, 'scores', '1sdc49P3eKm.ibe')), { code: 'ENOENT' });
  } finally { await cleanup(fixture); }
});
