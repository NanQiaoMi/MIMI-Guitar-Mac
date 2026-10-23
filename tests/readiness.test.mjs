import assert from 'node:assert/strict';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';
import { GET as healthGet } from '../src/pages/api/health.ts';
import { evaluateCatalogReadiness, REQUIRED_PRISMA_MIGRATIONS } from '../src/lib/server/readiness.ts';

function readyDatabase({ rows = [], total = 2, scores = [], xhe = [], scoreReferenceCount = scores.length } = {}) {
  return {
    async $queryRawUnsafe(query) {
      if (query === 'SELECT 1') return [{ '?column?': 1 }];
      if (query.includes('"_prisma_migrations"')) return rows;
      throw new Error('unexpected SQL');
    },
    tab: {
      async count(args) {
        if (!args) return total;
        if (args.where?.scoreUrl) return scoreReferenceCount;
        if (args.where?.xheUrl) return xhe.length;
        return total;
      },
      async findMany(args) { return args.where?.scoreUrl ? scores : xhe; },
    },
  };
}

const appliedRows = REQUIRED_PRISMA_MIGRATIONS.map((migration_name) => ({ migration_name, finished_at: new Date(), rolled_back_at: null }));

test('health endpoint reports process liveness without consulting dependent services', async () => {
  const response = healthGet();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'alive' });
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('readiness requires migrations, catalog rows, and reports read-only local resource samples', async () => {
  const probedPaths = [];
  const result = await evaluateCatalogReadiness({
    database: readyDatabase({
      rows: appliedRows,
      scores: [{ id: 'score-1', scoreUrl: '/storage/scores/one.ibe', xheUrl: null }],
      xhe: [{ id: 'xhe-1', scoreUrl: null, xheUrl: '/storage/xhe/one.xhe' }],
    }),
    storageRoot: 'C:\\private-storage-root',
    migrationsRoot: 'C:\\private-migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile(path) { probedPaths.push(path); return true; },
  });
  assert.equal(result.status, 'ready');
  assert.equal(result.database.status, 'ready');
  assert.equal(result.migrations.status, 'ready');
  assert.equal(result.catalog.tabs, 2);
  assert.equal(result.resources.status, 'sampled');
  assert.equal(result.resources.score.present, 1);
  assert.equal(result.resources.xhe.present, 1);
  assert.equal(probedPaths.length, 4);
  assert.equal(result.resources.soundfonts.status, 'ready');
  assert.equal(result.resources.soundfonts.present, 2);
  assert.equal(JSON.stringify(result).includes('private-storage-root'), false);
});

test('readiness remains not-ready for pending migrations or missing local files', async () => {
  const pending = await evaluateCatalogReadiness({
    database: readyDatabase({ rows: appliedRows.slice(1), scores: [{ id: 'score-1', scoreUrl: '/storage/scores/one.ibe', xheUrl: null }] }),
    storageRoot: 'C:\\storage',
    migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile() { return false; },
  });
  assert.equal(pending.status, 'not_ready');
  assert.equal(pending.migrations.status, 'pending');
  assert.equal(pending.resources.status, 'incomplete');

  const actualDirectories = (await readdir(join(process.cwd(), 'prisma', 'migrations'), { withFileTypes: true }))
    .filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
  assert.deepEqual(actualDirectories, [...REQUIRED_PRISMA_MIGRATIONS].sort());
});

test('database failure and unsafe resource paths fail closed without probing outside storage', async () => {
  let fileChecks = 0;
  const databaseDown = readyDatabase({ rows: appliedRows });
  databaseDown.$queryRawUnsafe = async () => { throw new Error('database password must not leak'); };
  const unavailable = await evaluateCatalogReadiness({
    database: databaseDown, storageRoot: 'C:\\storage', migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile() { fileChecks++; return true; },
  });
  assert.equal(unavailable.status, 'not_ready');
  assert.equal(unavailable.database.status, 'unavailable');
  assert.equal(fileChecks, 2);
  assert.equal(unavailable.catalog.status, 'unavailable');
  assert.equal(unavailable.resources.status, 'unavailable');
  assert.equal(unavailable.resources.soundfonts.status, 'ready');
  assert.equal(JSON.stringify(unavailable).includes('password'), false);

  fileChecks = 0;
  const unsafe = await evaluateCatalogReadiness({
    database: readyDatabase({ rows: appliedRows, scores: [{ id: 'score-1', scoreUrl: '/storage/../../outside.ibe', xheUrl: null }] }),
    storageRoot: 'C:\\storage', migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile() { fileChecks++; return true; },
  });
  assert.equal(unsafe.status, 'not_ready');
  assert.equal(unsafe.resources.status, 'incomplete');
  assert.equal(unsafe.resources.score.unsupported, 1);
  assert.equal(fileChecks, 2);
  assert.equal(JSON.stringify(unsafe).includes('outside.ibe'), false);
});

test('mixed valid and unsupported sampled catalog paths make resource readiness incomplete', async () => {
  const result = await evaluateCatalogReadiness({
    database: readyDatabase({
      rows: appliedRows,
      scores: [
        { id: 'score-1', scoreUrl: '/storage/scores/one.ibe', xheUrl: null },
        { id: 'score-2', scoreUrl: '/storage/../../outside.ibe', xheUrl: null },
      ],
    }),
    storageRoot: 'C:\\storage', migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile() { return true; },
  });
  assert.equal(result.status, 'not_ready');
  assert.equal(result.resources.status, 'incomplete');
  assert.equal(result.resources.score.present, 1);
  assert.equal(result.resources.score.unsupported, 1);
  assert.equal(result.resources.score.checked, 2);
  assert.equal(result.resources.score.unsampled, 0);
});

test('reports references outside the sample limit separately from unsupported samples', async () => {
  const scores = Array.from({ length: 20 }, (_, index) => ({
    id: `score-${index}`,
    scoreUrl: `/storage/scores/${index}.ibe`,
    xheUrl: null,
  }));
  const result = await evaluateCatalogReadiness({
    database: readyDatabase({ rows: appliedRows, scores, scoreReferenceCount: 27 }),
    storageRoot: 'C:\\storage', migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile() { return true; },
  });
  assert.equal(result.resources.status, 'sampled');
  assert.equal(result.resources.score.checked, 20);
  assert.equal(result.resources.score.unsupported, 0);
  assert.equal(result.resources.score.unsampled, 7);
});

test('missing required soundfont keeps readiness incomplete even when sampled scores exist', async () => {
  const probed = [];
  const result = await evaluateCatalogReadiness({
    database: readyDatabase({
      rows: appliedRows,
      scores: [{ id: 'score-1', scoreUrl: '/storage/scores/one.ibe', xheUrl: null }],
    }),
    storageRoot: 'C:\\storage', migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile(path) { probed.push(path); return !path.endsWith('ukulele_fast.sf2'); },
  });
  assert.equal(result.status, 'not_ready');
  assert.equal(result.resources.status, 'sampled');
  assert.equal(result.resources.soundfonts.status, 'incomplete');
  assert.deepEqual(result.resources.soundfonts.missing, ['ukulele']);
  assert.equal(probed.filter((path) => path.includes('soundfonts')).length, 2);
  assert.equal(JSON.stringify(result).includes('C:\\\\storage'), false);
});

test('readiness requires the actual GM SoundFont in public independently of legacy split banks', async () => {
  const probed = [];
  const result = await evaluateCatalogReadiness({
    database: readyDatabase({
      rows: appliedRows,
      scores: [{ id: 'score-1', scoreUrl: '/storage/scores/one.ibe', xheUrl: null }],
    }),
    publicRoot: join(process.cwd(), 'test-public'),
    storageRoot: join(process.cwd(), 'test-storage'),
    migrationsRoot: 'C:\\migrations',
    async listMigrationDirectories() { return [...REQUIRED_PRISMA_MIGRATIONS]; },
    async inspectFile(path) { probed.push(path); return !path.endsWith('sonivox.sf2'); },
  });
  assert.equal(result.status, 'not_ready');
  assert.equal(result.resources.soundfonts.required, 2);
  assert.deepEqual(result.resources.soundfonts.missing, ['generalMidi']);
  assert.ok(probed.includes(join(process.cwd(), 'test-public', 'soundfonts', 'sonivox.sf2')));
  assert.ok(probed.includes(join(process.cwd(), 'test-storage', 'soundfonts', 'ukulele_fast.sf2')));
  assert.equal(probed.some((path) => /acoustic_guitar_fast|[/\\]0\.sf2$/.test(path)), false);
});
