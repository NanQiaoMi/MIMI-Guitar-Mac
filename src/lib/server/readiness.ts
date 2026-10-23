import { readdir, stat } from 'node:fs/promises';
import { isAbsolute, relative, resolve, sep } from 'node:path';

export const REQUIRED_PRISMA_MIGRATIONS = [
  '20260812171354_init',
  '20260813034945_upload_meta',
  '20260813054546_article_views',
  '20261015000000_tab_score_resources',
] as const;
export const RESOURCE_SAMPLE_LIMIT = 20;
const REQUIRED_SOUNDFONTS = [
  { key: 'generalMidi', file: 'soundfonts/sonivox.sf2', scope: 'public' },
  { key: 'ukulele', file: 'soundfonts/ukulele_fast.sf2', scope: 'storage' },
] as const;

interface MigrationRow {
  migration_name: string;
  finished_at: Date | string | null;
  rolled_back_at: Date | string | null;
}

export interface ReadinessDatabase {
  $queryRawUnsafe(query: string): Promise<unknown>;
  tab: {
    count(args?: unknown): Promise<number>;
    findMany(args: unknown): Promise<Array<{ id: string; scoreUrl: string | null; xheUrl: string | null }>>;
  };
}

export interface ReadinessResult {
  status: 'ready' | 'not_ready';
  process: 'alive';
  database: { status: 'ready' | 'unavailable'; code?: string };
  migrations: { status: 'ready' | 'pending' | 'failed' | 'source_mismatch' | 'unavailable'; required: number; applied: number; pending: number; failed: number };
  catalog: { status: 'ready' | 'empty' | 'unavailable'; tabs?: number; code?: string };
  resources: {
    status: 'sampled' | 'incomplete' | 'unverified' | 'unconfigured' | 'unavailable';
    sampleLimitPerType: number;
    score: { catalogReferences: number; checked: number; present: number; missing: number; unsupported: number; unsampled: number };
    xhe: { catalogReferences: number; checked: number; present: number; missing: number; unsupported: number; unsampled: number };
    soundfonts: { status: 'ready' | 'incomplete'; required: number; present: number; missing: string[] };
  };
}

function isInside(root: string, candidate: string): boolean {
  const rel = relative(root, candidate);
  return rel === '' || (!rel.startsWith(`..${sep}`) && rel !== '..' && !isAbsolute(rel));
}

function localStorageFile(value: string | null, storageRoot: string): string | null {
  if (!value || value.length > 2048 || !value.startsWith('/storage/') || value.startsWith('//') || /[\\\u0000-\u001f\u007f?#]/.test(value)) return null;
  let decoded: string;
  try { decoded = decodeURIComponent(value); } catch { return null; }
  if (!decoded.startsWith('/storage/') || /[\\\u0000-\u001f\u007f?#]/.test(decoded)) return null;
  const relativePath = decoded.slice('/storage/'.length);
  if (!relativePath || relativePath.split('/').some((part) => !part || part === '.' || part === '..')) return null;
  const root = resolve(storageRoot);
  const candidate = resolve(root, relativePath.replaceAll('/', sep));
  return isInside(root, candidate) ? candidate : null;
}

async function inspectSamples(
  rows: Array<{ id: string; scoreUrl: string | null; xheUrl: string | null }>,
  field: 'scoreUrl' | 'xheUrl',
  referenceCount: number,
  storageRoot: string,
  inspectFile: (filePath: string) => Promise<boolean>,
) {
  const sample = rows.slice(0, RESOURCE_SAMPLE_LIMIT);
  let present = 0;
  let missing = 0;
  let unsupported = 0;
  for (const row of sample) {
    const filePath = localStorageFile(row[field], storageRoot);
    if (!filePath) { unsupported++; continue; }
    if (await inspectFile(filePath)) present++;
    else missing++;
  }
  const checked = present + missing + unsupported;
  return { catalogReferences: referenceCount, checked, present, missing, unsupported, unsampled: Math.max(0, referenceCount - sample.length) };
}

export interface ReadinessDependencies {
  database: ReadinessDatabase;
  storageRoot: string;
  publicRoot?: string;
  migrationsRoot: string;
  inspectFile?: (filePath: string) => Promise<boolean>;
  listMigrationDirectories?: (path: string) => Promise<string[]>;
}

/** Read-only startup/catalog probe. It deliberately samples, rather than traverses, the media library. */
export async function evaluateCatalogReadiness(dependencies: ReadinessDependencies): Promise<ReadinessResult> {
  const inspectFile = dependencies.inspectFile ?? (async (filePath: string) => {
    try { const metadata = await stat(filePath); return metadata.isFile() && metadata.size > 0; }
    catch { return false; }
  });
  const result: ReadinessResult = {
    status: 'not_ready',
    process: 'alive',
    database: { status: 'unavailable', code: 'database_unavailable' },
    migrations: { status: 'unavailable', required: REQUIRED_PRISMA_MIGRATIONS.length, applied: 0, pending: REQUIRED_PRISMA_MIGRATIONS.length, failed: 0 },
    catalog: { status: 'unavailable', code: 'catalog_unavailable' },
    resources: {
      status: 'unavailable',
      sampleLimitPerType: RESOURCE_SAMPLE_LIMIT,
      score: { catalogReferences: 0, checked: 0, present: 0, missing: 0, unsupported: 0, unsampled: 0 },
      xhe: { catalogReferences: 0, checked: 0, present: 0, missing: 0, unsupported: 0, unsampled: 0 },
      soundfonts: { status: 'incomplete', required: REQUIRED_SOUNDFONTS.length, present: 0, missing: REQUIRED_SOUNDFONTS.map(({ key }) => key) },
    },
  };
  const publicRoot = dependencies.publicRoot ?? resolve(dependencies.storageRoot, '..');
  const soundfontResults = await Promise.all(REQUIRED_SOUNDFONTS.map(async ({ key, file, scope }) => {
    const root = scope === 'public' ? publicRoot : dependencies.storageRoot;
    try { return { key, present: await inspectFile(resolve(root, file)) }; }
    catch { return { key, present: false }; }
  }));
  const missingSoundfonts = soundfontResults.filter(({ present }) => !present).map(({ key }) => key);
  result.resources.soundfonts = {
    status: missingSoundfonts.length === 0 ? 'ready' : 'incomplete',
    required: REQUIRED_SOUNDFONTS.length,
    present: soundfontResults.length - missingSoundfonts.length,
    missing: missingSoundfonts,
  };
  let migrationRows: MigrationRow[] = [];
  let migrationQueryReady = true;
  try {
    await dependencies.database.$queryRawUnsafe('SELECT 1');
    result.database = { status: 'ready' };
  } catch {
    return result;
  }
  try {
    migrationRows = await dependencies.database.$queryRawUnsafe('SELECT migration_name, finished_at, rolled_back_at FROM "_prisma_migrations"') as MigrationRow[];
  } catch {
    result.migrations = { ...result.migrations, status: 'unavailable' };
    migrationQueryReady = false;
  }

  try {
    if (!migrationQueryReady) throw new Error('migration status unavailable');
    const listDirectories = dependencies.listMigrationDirectories ?? (async (path: string) =>
      (await readdir(path, { withFileTypes: true })).filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort());
    const diskMigrations = (await listDirectories(dependencies.migrationsRoot)).sort();
    const required = [...REQUIRED_PRISMA_MIGRATIONS].sort();
    const sourceMatches = diskMigrations.length === required.length && diskMigrations.every((name, index) => name === required[index]);
    const appliedRows = new Set(migrationRows.filter((row) => row.finished_at && !row.rolled_back_at).map((row) => row.migration_name));
    const failedRows = new Set(migrationRows.filter((row) => !row.finished_at && !row.rolled_back_at).map((row) => row.migration_name));
    const applied = required.filter((name) => appliedRows.has(name)).length;
    const failed = required.filter((name) => !appliedRows.has(name) && failedRows.has(name)).length;
    const pending = required.filter((name) => !appliedRows.has(name) && !failedRows.has(name)).length;
    result.migrations = {
      status: !sourceMatches ? 'source_mismatch' : failed ? 'failed' : pending ? 'pending' : 'ready',
      required: required.length,
      applied,
      pending,
      failed,
    };
  } catch {
    result.migrations = { ...result.migrations, status: 'unavailable' };
  }

  try {
    const catalogCount = await dependencies.database.tab.count();
    const [scoreReferences, xheReferences, scoreRows, xheRows] = await Promise.all([
      dependencies.database.tab.count({ where: { scoreUrl: { not: null } } }),
      dependencies.database.tab.count({ where: { xheUrl: { not: null } } }),
      dependencies.database.tab.findMany({ where: { scoreUrl: { not: null } }, select: { id: true, scoreUrl: true, xheUrl: true }, orderBy: { id: 'asc' }, take: RESOURCE_SAMPLE_LIMIT }),
      dependencies.database.tab.findMany({ where: { xheUrl: { not: null } }, select: { id: true, scoreUrl: true, xheUrl: true }, orderBy: { id: 'asc' }, take: RESOURCE_SAMPLE_LIMIT }),
    ]);
    result.catalog = catalogCount > 0 ? { status: 'ready', tabs: catalogCount } : { status: 'empty', tabs: 0 };
    const [score, xhe] = await Promise.all([
      inspectSamples(scoreRows, 'scoreUrl', scoreReferences, dependencies.storageRoot, inspectFile),
      inspectSamples(xheRows, 'xheUrl', xheReferences, dependencies.storageRoot, inspectFile),
    ]);
    const referenceCount = scoreReferences + xheReferences;
    result.resources = {
      status: referenceCount === 0 ? 'unconfigured' : score.checked + xhe.checked === 0 ? 'unverified' : score.missing + xhe.missing + score.unsupported + xhe.unsupported > 0 ? 'incomplete' : 'sampled',
      sampleLimitPerType: RESOURCE_SAMPLE_LIMIT,
      score,
      xhe,
      soundfonts: result.resources.soundfonts,
    };
  } catch {
    result.catalog = { status: 'unavailable', code: 'catalog_query_failed' };
  }

  const migrationsReady = result.migrations.status === 'ready';
  const resourcesReady = result.resources.status === 'sampled' && result.resources.soundfonts.status === 'ready';
  result.status = result.database.status === 'ready'
    && migrationsReady
    && result.catalog.status === 'ready'
    && resourcesReady
    ? 'ready'
    : 'not_ready';
  return result;
}
