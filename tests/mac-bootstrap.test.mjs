import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { mkdtemp, mkdir, rm, writeFile, access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { createMacBootstrap, createMacProcessRunner, MAC_BOOTSTRAP_HELP } from '../tools/lib/mac-bootstrap.mjs';

const temporaryRoots = [];

afterEach(async () => {
  await Promise.all(temporaryRoots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

const expectedCounts = { tabs: 16233, articles: 8, migrations: 4 };

async function createFixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'mimi-mac-bootstrap-'));
  temporaryRoots.push(root);
  const projectDir = path.join(root, 'project');
  const databaseDir = path.join(root, 'database');
  await mkdir(projectDir, { recursive: true });
  await mkdir(databaseDir, { recursive: true });
  await writeFile(path.join(projectDir, 'docker-compose.mac.yml'), 'services: {}\n');
  const dump = Buffer.from('PGDMP-test-archive');
  const sha256 = createHash('sha256').update(dump).digest('hex');
  await writeFile(path.join(databaseDir, 'catalog.dump'), dump);
  await writeFile(path.join(databaseDir, 'catalog-metadata.json'), JSON.stringify({
    postgresMajor: 16,
    sha256,
    counts: expectedCounts,
  }));
  return {
    root,
    projectDir,
    configFile: path.join(projectDir, '.env.mac.local'),
    catalogExpectation: { postgresMajor: 16, sha256, counts: expectedCounts },
  };
}

const safeArchiveListing = [
  '101; 0 0 TABLE DATA public Tab mimi_mac',
  '102; 0 0 TABLE DATA public Article mimi_mac',
  '103; 0 0 TABLE DATA public _prisma_migrations mimi_mac',
].join('\n');

function makeDockerRunner({ conflict = false, restoreCode = 0, archiveListing = safeArchiveListing, dockerEndpoint = 'unix:///var/run/docker.sock' } = {}) {
  const calls = [];
  const run = async (command, args, options = {}) => {
    calls.push({ command, args, options });
    if (command === 'npm' && args[0] === '--version') return { code: 0, stdout: '10.9.2' };
    if (command === 'docker' && args[0] === '--version') return { code: 0, stdout: 'Docker version test' };
    if (command === 'docker' && args[0] === 'compose' && args[1] === 'version') return { code: 0, stdout: 'Docker Compose version test' };
    if (command === 'docker' && args[0] === 'context' && args[1] === 'show') return { code: 0, stdout: 'desktop-linux' };
    if (command === 'docker' && args[0] === 'context' && args[1] === 'inspect') return { code: 0, stdout: dockerEndpoint };
    if (command === 'docker' && args[0] === 'info') return { code: 0, stdout: '29.0' };
    if (command === 'docker' && ['container', 'volume', 'network'].includes(args[0]) && args[1] === 'ls') {
      return { code: 0, stdout: conflict && args.includes('container') ? 'old-container-id' : '' };
    }
    if (command === 'docker' && args[0] === 'compose' && args.includes('up')) return { code: 0, stdout: '' };
    if (command === 'docker' && args[0] === 'inspect' && args.some((arg) => String(arg).includes('.State.Health.Status'))) return { code: 0, stdout: 'healthy' };
    if (command === 'docker' && args[0] === 'inspect' && args.some((arg) => String(arg).includes('com.docker.compose.project'))) return { code: 0, stdout: 'mimi-guitar-mac-dev' };
    if (command === 'docker' && args[0] === 'inspect' && args.some((arg) => String(arg).includes('com.docker.compose.service'))) return { code: 0, stdout: 'db' };
    if (command === 'docker' && args[0] === 'inspect' && args.includes('{{.Config.Image}}')) return { code: 0, stdout: 'postgres:16' };
    if (command === 'docker' && args[0] === 'inspect' && args.some((arg) => String(arg).includes('.Mounts'))) return { code: 0, stdout: 'mimi-guitar-mac-dev-data' };
    if (command === 'docker' && args[0] === 'volume' && args.some((arg) => String(arg).includes('com.docker.compose.project'))) return { code: 0, stdout: 'mimi-guitar-mac-dev' };
    if (command === 'docker' && args[0] === 'volume' && args.some((arg) => String(arg).includes('com.docker.compose.volume'))) return { code: 0, stdout: 'catalog-data' };
    if (command === 'docker' && args[0] === 'volume' && args.includes('{{.Driver}}')) return { code: 0, stdout: 'local' };
    if (command === 'docker' && args[0] === 'compose' && args.includes('pg_restore') && args.includes('--list')) return { code: 0, stdout: archiveListing };
    if (command === 'docker' && args[0] === 'compose' && args.includes('pg_restore')) return { code: restoreCode, stdout: '', stderr: 'private subprocess output is discarded' };
    if (command === 'docker' && args[0] === 'compose' && args.includes('psql')) {
      const query = args[args.indexOf('-c') + 1];
      if (query.includes('pg_catalog.pg_tables')) return { code: 0, stdout: '0' };
      return {
        code: 0,
        stdout: ['Tab|16233', 'Article|8', '_prisma_migrations|4', 'CompletedMigrationRows|4', 'IncompleteMigrationRows|0', 'User|0', 'Favorite|0', 'UploadRecord|0'].join('\n'),
      };
    }
    return { code: 0, stdout: '' };
  };
  return { calls, run };
}

function createBootstrap(fixture, overrides = {}) {
  const output = [];
  const defaults = {
    projectDir: fixture.projectDir,
    platform: 'darwin',
    arch: 'arm64',
    nodeVersion: 'v24.8.0',
    catalogExpectation: fixture.catalogExpectation,
    parentEnv: { DATABASE_URL: 'postgresql://do-not-use:parent-value@remote.invalid/old' },
    randomSecret: () => 'a'.repeat(43),
    portProbe: async () => true,
    output: (line) => output.push(line),
    wait: async () => {},
    now: (() => { let current = 1000; return () => current++; })(),
  };
  const result = { output, ...createMacBootstrap({ ...defaults, ...overrides }) };
  return result;
}

test('restore refuses an existing Compose target before config or database actions', async () => {
  const fixture = await createFixture();
  const { calls, run } = makeDockerRunner({ conflict: true });
  const app = createBootstrap(fixture, { run });

  await assert.rejects(app.restoreCatalog(), /target already exists/);
  await assert.rejects(access(fixture.configFile));
  assert.equal(calls.some(({ args }) => args[0] === 'compose' && args.includes('up')), false);
  assert.equal(calls.some(({ args }) => args.includes('pg_restore')), false);
});

test('restore imports only into a newly labeled empty target and verifies excluded rows', async (t) => {
  const fixture = await createFixture();
  const { calls, run } = makeDockerRunner();
  const app = createBootstrap(fixture, { run });

  const doctor = await app.doctor();
  assert.equal(doctor.ok, true);
  assert.match(app.output.join('\n'), /Docker context endpoint: local Unix socket/);

  const result = await app.restoreCatalog();

  assert.equal(result.ok, true);
  assert.equal(result.counts.get('Tab'), 16233);
  assert.equal(result.counts.get('Article'), 8);
  assert.equal(result.counts.get('_prisma_migrations'), 4);
  assert.equal(result.counts.get('CompletedMigrationRows'), 4);
  assert.equal(result.counts.get('IncompleteMigrationRows'), 0);
  assert.equal(result.counts.get('User'), 0);
  assert.equal(calls.some(({ args }) => args.includes('--clean') || args.includes('--drop')), false);
  const restoreCall = calls.find(({ args }) => args.includes('pg_restore') && !args.includes('--list'));
  assert.ok(restoreCall);
  assert.equal(restoreCall.options.stdinFile, path.join(fixture.root, 'database', 'catalog.dump'));
  for (const flag of ['--no-owner', '--no-privileges', '--exit-on-error', '--single-transaction']) {
    assert.equal(restoreCall.args.includes(flag), true);
  }
  assert.ok(calls.findIndex(({ args }) => args.some((arg) => String(arg).includes('pg_tables'))) < calls.findIndex(({ args }) => args.includes('pg_restore')));
  assert.ok(calls.findIndex(({ args }) => args.includes('pg_restore')) < calls.findIndex(({ args }) => args.some((arg) => String(arg).includes('public."Tab"'))));
  assert.equal(app.output.some((line) => line.includes('a'.repeat(43))), false);
});

test('restore failure preserves created resources and never runs cleanup commands', async (t) => {
  const fixture = await createFixture();
  const { calls, run } = makeDockerRunner({ restoreCode: 1 });
  const app = createBootstrap(fixture, { run });

  await assert.rejects(app.restoreCatalog(), /PostgreSQL catalog restore failed/);

  assert.ok(calls.some(({ args }) => args.includes('up')));
  assert.ok(calls.some(({ args }) => args.includes('pg_restore') && !args.includes('--list')));
  assert.equal(calls.some(({ args }) => args.includes('down') || args.includes('rm')), false);
  assert.ok(await access(fixture.configFile).then(() => true));
});

test('busy database port blocks restore before config or container creation', async () => {
  const fixture = await createFixture();
  const { calls, run } = makeDockerRunner();
  const app = createBootstrap(fixture, { run, portProbe: async () => false });

  await assert.rejects(app.restoreCatalog(), /127\.0\.0\.1:15433 is unavailable/);
  await assert.rejects(access(fixture.configFile));
  assert.equal(calls.some(({ args }) => args[0] === 'compose' && args.includes('up')), false);
});

test('restore rejects a remote DOCKER_HOST override before config or Compose actions', async () => {
  const fixture = await createFixture();
  const remoteEndpoint = 'ssh://review-user:private-value@remote.example';
  const { calls, run } = makeDockerRunner();
  const app = createBootstrap(fixture, {
    run,
    parentEnv: { DOCKER_HOST: remoteEndpoint },
  });

  await assert.rejects(app.restoreCatalog(), /local Docker Desktop context using a Unix socket/);

  await assert.rejects(access(fixture.configFile));
  assert.equal(calls.some(({ args }) => args[0] === 'compose' && args.includes('up')), false);
  assert.equal(app.output.join('\n').includes(remoteEndpoint), false);
  assert.equal(app.output.join('\n').includes('private-value'), false);
});

test('restore rejects a remote selected context and doctor reports it without switching contexts', async () => {
  const fixture = await createFixture();
  const remoteEndpoint = 'ssh://review-user:private-value@remote.example';
  const { calls, run } = makeDockerRunner({ dockerEndpoint: remoteEndpoint });
  const app = createBootstrap(fixture, { run });

  const doctor = await app.doctor();
  assert.equal(doctor.ok, false);
  assert.match(app.output.join('\n'), /Docker context endpoint: unavailable or remote/);
  assert.equal(app.output.join('\n').includes(remoteEndpoint), false);
  assert.equal(app.output.join('\n').includes('private-value'), false);

  await assert.rejects(app.restoreCatalog(), /local Docker Desktop context using a Unix socket/);

  await assert.rejects(access(fixture.configFile));
  assert.equal(calls.some(({ args }) => args[0] === 'compose' && args.includes('up')), false);
  assert.equal(calls.some(({ args }) => args[0] === 'context' && args[1] === 'use'), false);
});

test('archive inspection refuses excluded account rows before running pg_restore', async () => {
  const fixture = await createFixture();
  const { calls, run } = makeDockerRunner({ archiveListing: `${safeArchiveListing}\n104; 0 0 TABLE DATA public User mimi_mac` });
  const app = createBootstrap(fixture, { run });

  await assert.rejects(app.restoreCatalog(), /data outside the approved catalog tables/);

  assert.equal(calls.some(({ args }) => args.includes('pg_restore') && !args.includes('--list')), false);
  assert.equal(calls.some(({ args }) => args.includes('down') || args.includes('rm')), false);
  assert.ok(app.output.join('\n').includes('Creating the new isolated PostgreSQL 16 environment'));
  assert.equal(app.output.some((line) => line.startsWith('Restore verified:')), false);
});

test('dump checksum mismatch is rejected before Docker is queried', async () => {
  const fixture = await createFixture();
  await writeFile(path.join(fixture.root, 'database', 'catalog.dump'), Buffer.from('PGDMP-altered-archive'));
  const { calls, run } = makeDockerRunner();
  const app = createBootstrap(fixture, { run });

  await assert.rejects(app.restoreCatalog(), /SHA-256 does not match/);
  assert.equal(calls.length, 0);
});

test('dry run checks prerequisites without writing config or starting Compose', async (t) => {
  const fixture = await createFixture();
  const { calls, run } = makeDockerRunner();
  const app = createBootstrap(fixture, { run });

  const result = await app.restoreCatalog({ dryRun: true });

  assert.equal(result.dryRun, true);
  await assert.rejects(access(fixture.configFile));
  assert.equal(calls.some(({ args }) => args[0] === 'compose' && args.includes('up')), false);
  assert.match(app.output.join('\n'), /No config or container was created/);
});

test('install includes locked development tools even with production defaults and resets inherited DATABASE_URL', async () => {
  const calls = [];
  const app = createMacBootstrap({
    projectDir: path.resolve('mac-install-test-project'),
    platform: 'darwin',
    nodeVersion: 'v24.1.0',
    parentEnv: { DATABASE_URL: 'parent-test-value', NODE_ENV: 'production', npm_config_omit: 'dev' },
    run: async (command, args, options) => {
      calls.push({ command, args, options });
      return { code: 0, stdout: 'ok' };
    },
  });

  await app.install();

  assert.deepEqual(calls.map(({ command, args }) => `${command} ${args.join(' ')}`), [
    'npm --version',
    'npm ci --include=dev',
    'npm run prisma:generate',
  ]);
  assert.equal(calls[1].options.env.DATABASE_URL.includes('parent-test-value'), false);
  assert.equal(calls[2].options.env.DATABASE_URL, calls[1].options.env.DATABASE_URL);
});

test('process runner redacts secrets even when output splits the URL across chunks', async () => {
  const secret = 'postgresql://mimi_mac:private-password@127.0.0.1:15433/mimi_catalog?schema=public';
  const splitAt = Math.floor(secret.length / 2);
  const source = `process.stdout.write(${JSON.stringify(secret.slice(0, splitAt))});setTimeout(()=>process.stdout.write(${JSON.stringify(secret.slice(splitAt))}),10);`;
  const runner = createMacProcessRunner();

  const result = await runner(process.execPath, ['-e', source], { timeoutMs: 10_000, redact: [secret, 'private-password'] });

  assert.equal(result.code, 0);
  assert.equal(result.stdout.includes('private-password'), false);
  assert.match(result.stdout, /\[redacted\]/);
});

test('help states the non-destructive restore contract and manual failure review', () => {
  assert.match(MAC_BOOTSTRAP_HELP, /Existing targets or a busy port are refused/);
  assert.match(MAC_BOOTSTRAP_HELP, /never uses --clean or DROP/);
  assert.match(MAC_BOOTSTRAP_HELP, /resources are preserved for manual inspection/);
  assert.match(MAC_BOOTSTRAP_HELP, /local Docker Desktop context backed by a Unix socket/);
});
