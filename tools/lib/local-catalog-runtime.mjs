import { isIP } from 'node:net';

export const LOCAL_POSTGRES_CONTAINER = 'mimi-guitar-pg';
export const LOCAL_POSTGRES_IMAGE = 'postgres:16-alpine';
export const LOCAL_DATABASE_NAME = 'mimi_guitar';
export const LOCAL_DATABASE_USER = 'mimi';
export const POSTGRES_PORT = 5432;
export const POSTGRES_DATA_DIRECTORY = '/var/lib/postgresql/data';
export const DOCKER_TIMEOUT_MS = 8_000;
export const PRISMA_CONNECT_TIMEOUT_SECONDS = 3;
export const PRISMA_POOL_TIMEOUT_SECONDS = 3;
export const PRISMA_PROBE_TIMEOUT_MS = 5_000;
export const PRISMA_TOTAL_TIMEOUT_MS = 10_000;
export const PRISMA_DISCONNECT_TIMEOUT_MS = 1_500;

export const REQUIRED_PRISMA_MIGRATIONS = Object.freeze([
  '20260812171354_init',
  '20260813034945_upload_meta',
  '20260813054546_article_views',
  '20261015000000_tab_score_resources',
]);

export const REQUIRED_PRISMA_SCHEMA_COLUMNS = Object.freeze([
  ['User', 'id', 'text', 'NO'],
  ['User', 'email', 'text', 'YES'],
  ['User', 'phone', 'text', 'YES'],
  ['User', 'passwordHash', 'text', 'NO'],
  ['User', 'nickname', 'text', 'YES'],
  ['User', 'avatarUrl', 'text', 'YES'],
  ['User', 'createdAt', 'timestamp without time zone', 'NO'],
  ['Tab', 'id', 'text', 'NO'],
  ['Tab', 'title', 'text', 'NO'],
  ['Tab', 'artist', 'text', 'YES'],
  ['Tab', 'category', 'text', 'NO'],
  ['Tab', 'difficulty', 'integer', 'NO'],
  ['Tab', 'style', 'integer', 'YES'],
  ['Tab', 'key', 'text', 'YES'],
  ['Tab', 'tuning', 'text', 'YES'],
  ['Tab', 'sheetForm', 'integer', 'NO'],
  ['Tab', 'bpm', 'integer', 'YES'],
  ['Tab', 'timeSig', 'text', 'YES'],
  ['Tab', 'capo', 'integer', 'NO'],
  ['Tab', 'tuningText', 'text', 'YES'],
  ['Tab', 'heat', 'integer', 'NO'],
  ['Tab', 'uploader', 'text', 'YES'],
  ['Tab', 'publishDate', 'timestamp without time zone', 'YES'],
  ['Tab', 'format', 'text', 'NO'],
  ['Tab', 'scoreUrl', 'text', 'YES'],
  ['Tab', 'xheUrl', 'text', 'YES'],
  ['Tab', 'screenshotUrl', 'text', 'YES'],
  ['Tab', 'description', 'text', 'YES'],
  ['Tab', 'tags', 'text', 'NO'],
  ['Tab', 'createdAt', 'timestamp without time zone', 'NO'],
  ['Tab', 'updatedAt', 'timestamp without time zone', 'NO'],
  ['Favorite', 'id', 'text', 'NO'],
  ['Favorite', 'userId', 'text', 'NO'],
  ['Favorite', 'tabId', 'text', 'NO'],
  ['Favorite', 'createdAt', 'timestamp without time zone', 'NO'],
  ['UploadRecord', 'id', 'text', 'NO'],
  ['UploadRecord', 'userId', 'text', 'YES'],
  ['UploadRecord', 'title', 'text', 'NO'],
  ['UploadRecord', 'artist', 'text', 'YES'],
  ['UploadRecord', 'fileName', 'text', 'NO'],
  ['UploadRecord', 'scoreUrl', 'text', 'NO'],
  ['UploadRecord', 'screenshotUrl', 'text', 'YES'],
  ['UploadRecord', 'metaJson', 'text', 'YES'],
  ['UploadRecord', 'tabId', 'text', 'YES'],
  ['UploadRecord', 'status', 'text', 'NO'],
  ['UploadRecord', 'createdAt', 'timestamp without time zone', 'NO'],
  ['Article', 'id', 'text', 'NO'],
  ['Article', 'title', 'text', 'NO'],
  ['Article', 'content', 'text', 'NO'],
  ['Article', 'category', 'text', 'YES'],
  ['Article', 'views', 'integer', 'NO'],
  ['Article', 'createdAt', 'timestamp without time zone', 'NO'],
].map((column) => Object.freeze(column)));
export const REQUIRED_SCHEMA_COLUMN_COUNT = REQUIRED_PRISMA_SCHEMA_COLUMNS.length;

export const READ_ONLY_SCHEMA_SQL = `BEGIN READ ONLY;
SELECT 'database|' || current_database();
SELECT 'tables|' || CASE WHEN to_regclass('"Tab"') IS NULL THEN '0' ELSE '1' END || '|' || CASE WHEN to_regclass('_prisma_migrations') IS NULL THEN '0' ELSE '1' END;
WITH expected(table_name, column_name, data_type, is_nullable) AS (VALUES
${REQUIRED_PRISMA_SCHEMA_COLUMNS.map(([table, column, type, nullable]) =>
  `  ('${table}', '${column}', '${type}', '${nullable}')`).join(',\n')}
)
SELECT 'missing|' || COALESCE((
  SELECT string_agg(e.table_name || '.' || e.column_name, ',' ORDER BY e.table_name, e.column_name)
  FROM expected e
  LEFT JOIN information_schema.columns c
    ON c.table_schema = current_schema()
   AND c.table_name = e.table_name
   AND c.column_name = e.column_name
   AND c.data_type = e.data_type
   AND c.is_nullable = e.is_nullable
  WHERE c.column_name IS NULL
), '');
ROLLBACK;`;

export const READ_ONLY_MIGRATIONS_SQL = `BEGIN READ ONLY;
WITH expected(migration_name) AS (VALUES
${REQUIRED_PRISMA_MIGRATIONS.map((name) => `  ('${name}')`).join(',\n')}
)
SELECT 'migrations|' ||
  COUNT(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM "_prisma_migrations" m
    WHERE m.migration_name = e.migration_name
      AND m.finished_at IS NOT NULL
      AND m.rolled_back_at IS NULL
  ))::text || '|' ||
  COUNT(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM "_prisma_migrations" failed
    WHERE failed.migration_name = e.migration_name
      AND failed.finished_at IS NULL
      AND failed.rolled_back_at IS NULL
  ) AND NOT EXISTS (
    SELECT 1 FROM "_prisma_migrations" applied
    WHERE applied.migration_name = e.migration_name
      AND applied.finished_at IS NOT NULL
      AND applied.rolled_back_at IS NULL
  ))::text
FROM expected e;
ROLLBACK;`;

export class LocalCatalogRuntimeError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'LocalCatalogRuntimeError';
    this.code = code;
  }
}

export function classifyDockerFailure(args, result) {
  if (result.error?.code === 'ENOENT') {
    return new LocalCatalogRuntimeError('DOCKER_UNAVAILABLE', '未找到 Docker Desktop 命令。');
  }
  if (result.error?.code === 'ETIMEDOUT') {
    return new LocalCatalogRuntimeError(
      args[0] === 'exec' ? 'DATABASE_UNAVAILABLE' : 'DOCKER_TIMEOUT',
      'Docker 命令超时。',
    );
  }
  if (result.status === null) {
    return new LocalCatalogRuntimeError('DOCKER_UNAVAILABLE', 'Docker Desktop 暂不可用。');
  }

  const stderr = String(result.stderr ?? '').toLowerCase();
  if (/error during connect|cannot connect to the docker daemon|docker engine.*not running|pipe.*not found|failed to connect to docker/.test(stderr)) {
    return new LocalCatalogRuntimeError('DOCKER_UNAVAILABLE', 'Docker Desktop 暂不可用。');
  }
  if (args[0] === 'exec') {
    if (/container .* is not running|is not running|no such container/.test(stderr)) {
      return new LocalCatalogRuntimeError('CONTAINER_STOPPED', '本地曲库容器未运行。');
    }
    if (/password authentication failed|role .* does not exist|permission denied/.test(stderr)) {
      return new LocalCatalogRuntimeError('DATABASE_AUTH', 'PostgreSQL 拒绝了只读检查。');
    }
    if (/relation .* does not exist|column .* does not exist|schema .* does not exist|no such table/.test(stderr)) {
      return new LocalCatalogRuntimeError('SCHEMA_MISMATCH', 'PostgreSQL 曲谱表结构不匹配。');
    }
    if (/database .* does not exist|invalid catalog name/.test(stderr)) {
      return new LocalCatalogRuntimeError('DATABASE_CONFIG', 'PostgreSQL 目标数据库不匹配。');
    }
    if (/could not connect to server|connection refused|connection timed out|connection reset|server closed the connection|socket.*no such file or directory|could not translate host name/.test(stderr)) {
      return new LocalCatalogRuntimeError('DATABASE_UNAVAILABLE', 'PostgreSQL 连接失败。');
    }
  }
  return new LocalCatalogRuntimeError('DOCKER_COMMAND_FAILED', 'Docker 检查命令未成功。');
}

function fail(code, message) {
  throw new LocalCatalogRuntimeError(code, message);
}

function parseContainerEnvironment(entries) {
  if (!Array.isArray(entries)) fail('CONTAINER_CONFIG', '容器环境配置无法验证。');

  const environment = new Map();
  for (const entry of entries) {
    if (typeof entry !== 'string') continue;
    const separator = entry.indexOf('=');
    if (separator < 1) continue;
    const key = entry.slice(0, separator);
    if (!['POSTGRES_USER', 'POSTGRES_DB', 'POSTGRES_PASSWORD'].includes(key)) continue;
    if (environment.has(key)) fail('CONTAINER_CONFIG', '容器数据库配置不唯一。');
    environment.set(key, entry.slice(separator + 1));
  }

  const user = environment.get('POSTGRES_USER');
  const database = environment.get('POSTGRES_DB');
  const password = environment.get('POSTGRES_PASSWORD');
  if (user !== LOCAL_DATABASE_USER || database !== LOCAL_DATABASE_NAME || !password) {
    fail('CONTAINER_CONFIG', '容器数据库身份不符合本地曲库预期。');
  }
  return { user, database, password };
}

export function inspectLocalPostgres(rawInspection) {
  let inspected;
  try {
    inspected = JSON.parse(rawInspection);
  } catch {
    fail('CONTAINER_INSPECT', 'Docker 返回了无法验证的容器信息。');
  }

  if (!Array.isArray(inspected) || inspected.length !== 1) {
    fail('CONTAINER_IDENTITY', '未找到唯一的本地曲库容器。');
  }

  const container = inspected[0];
  if (container?.Name !== `/${LOCAL_POSTGRES_CONTAINER}` ||
      container?.Config?.Image !== LOCAL_POSTGRES_IMAGE) {
    fail('CONTAINER_IDENTITY', '容器名称或 PostgreSQL 镜像与本地曲库不符。');
  }
  if (container?.State?.Running !== true) {
    fail('CONTAINER_STOPPED', '本地曲库容器未运行；请先在 Docker Desktop 中启动现有容器。');
  }

  const hasPersistentDataVolume = Array.isArray(container.Mounts) && container.Mounts.some((mount) =>
    mount?.Type === 'volume' &&
    mount?.Destination === POSTGRES_DATA_DIRECTORY &&
    typeof mount?.Name === 'string' && mount.Name.length > 0 &&
    mount?.RW === true,
  );
  if (!hasPersistentDataVolume) {
    fail('CONTAINER_VOLUME', '容器没有挂载预期的 PostgreSQL 持久卷。');
  }

  const bindings = container?.NetworkSettings?.Ports?.[`${POSTGRES_PORT}/tcp`];
  if (!Array.isArray(bindings) || bindings.length === 0) {
    fail('CONTAINER_PORT', 'PostgreSQL 容器没有本机端口映射。');
  }
  const hostPorts = new Set();
  let hasIpv4LoopbackRoute = false;
  for (const binding of bindings) {
    const hostPort = Number(binding?.HostPort);
    const hostIp = binding?.HostIp;
    if (!Number.isInteger(hostPort) || hostPort < 1 || hostPort > 65_535 || typeof hostIp !== 'string') {
      fail('CONTAINER_PORT', 'PostgreSQL 端口映射包含无效地址或端口。');
    }
    const addressFamily = hostIp === '' ? 4 : isIP(hostIp);
    if (addressFamily === 4 && ['', '0.0.0.0', '127.0.0.1'].includes(hostIp)) {
      hasIpv4LoopbackRoute = true;
    } else if (addressFamily === 6 && ['::', '::1'].includes(hostIp)) {
      // Docker may report the IPv6 wildcard/loopback alongside the IPv4 binding.
    } else {
      fail('CONTAINER_PORT', 'PostgreSQL 端口映射包含不受支持的地址。');
    }
    hostPorts.add(hostPort);
  }
  if (!hasIpv4LoopbackRoute || hostPorts.size !== 1) {
    fail('CONTAINER_PORT', 'PostgreSQL 端口映射必须指向唯一可由 IPv4 loopback 访问的端口。');
  }
  const [hostPort] = hostPorts;

  const credentials = parseContainerEnvironment(container?.Config?.Env);
  return {
    containerName: LOCAL_POSTGRES_CONTAINER,
    host: '127.0.0.1',
    hostPort,
    database: credentials.database,
    user: credentials.user,
    password: credentials.password,
  };
}

export function buildLocalDatabaseUrl(target) {
  const user = encodeURIComponent(target.user);
  const password = encodeURIComponent(target.password);
  const database = encodeURIComponent(target.database);
  return `postgresql://${user}:${password}@127.0.0.1:${target.hostPort}/${database}?connect_timeout=${PRISMA_CONNECT_TIMEOUT_SECONDS}&pool_timeout=${PRISMA_POOL_TIMEOUT_SECONDS}`;
}

function matchingLocalTargetParams(value, target) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }

  try {
    if (!['postgres:', 'postgresql:'].includes(url.protocol) || url.hash !== '' ||
        !['127.0.0.1', 'localhost'].includes(url.hostname) ||
        Number(url.port || 5432) !== target.hostPort ||
        decodeURIComponent(url.username) !== target.user ||
        decodeURIComponent(url.password) !== target.password ||
        decodeURIComponent(url.pathname.slice(1)) !== target.database) {
      return null;
    }

    const params = [...url.searchParams];
    if (new Set(params.map(([key]) => key)).size !== params.length) return null;
    const values = new Map(params);
    for (const [key, value] of params) {
      if (key === 'schema' && value === 'public') continue;
      if (key === 'connect_timeout' && /^[1-5]$/.test(value)) continue;
      if (key === 'pool_timeout' && /^[1-5]$/.test(value)) continue;
      return null;
    }
    return values;
  } catch {
    return null;
  }
}

export function resolveDatabaseUrl(existingValue, target) {
  const generatedUrl = buildLocalDatabaseUrl(target);
  if (existingValue === undefined) return generatedUrl;
  const params = matchingLocalTargetParams(existingValue, target);
  if (!params) {
    fail(
      'DATABASE_URL_CONFLICT',
      '当前进程已设置不同的 DATABASE_URL。为避免连接测试库或远端库，请先显式清除该变量后再启动本地曲库。',
    );
  }
  const defaults = [];
  if (!params.has('connect_timeout')) defaults.push(`connect_timeout=${PRISMA_CONNECT_TIMEOUT_SECONDS}`);
  if (!params.has('pool_timeout')) defaults.push(`pool_timeout=${PRISMA_POOL_TIMEOUT_SECONDS}`);
  if (defaults.length === 0) return existingValue;
  const separator = existingValue.includes('?') ? (existingValue.endsWith('?') ? '' : '&') : '?';
  return `${existingValue}${separator}${defaults.join('&')}`;
}

export function parseReadOnlySchemaResult(output) {
  const lines = String(output).split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (lines.length !== 3 || !/^database\|[^|]+$/.test(lines[0]) ||
      !/^tables\|[01]\|[01]$/.test(lines[1]) || !/^missing\|[^\r\n]*$/.test(lines[2])) {
    fail('DATABASE_PROBE', '只读 schema 检查未返回预期结果。');
  }
  const [, database] = lines[0].split('|');
  const [, tab, migrations] = lines[1].split('|').map(Number);
  const missingColumns = lines[2].slice('missing|'.length).split(',').filter(Boolean);
  if (database !== LOCAL_DATABASE_NAME) fail('DATABASE_CONFIG', '本地容器连接到了非预期数据库。');
  return { database, tabExists: tab === 1, migrationsTableExists: migrations === 1, missingColumns };
}

export function parseReadOnlyMigrationResult(output) {
  const lines = String(output).split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const match = lines.length === 1 ? /^migrations\|(\d+)\|(\d+)$/.exec(lines[0]) : null;
  if (!match) fail('DATABASE_PROBE', '迁移状态只读检查未返回预期结果。');
  const applied = Number(match[1]);
  const failed = Number(match[2]);
  if (applied !== REQUIRED_PRISMA_MIGRATIONS.length || failed > 0) {
    fail('MIGRATIONS_PENDING', '本地曲库尚未完成全部必要迁移；未启动站点。');
  }
  return { applied, failed };
}

function reportProbeFailure(error) {
  const knownFailures = {
    DATABASE_UNAVAILABLE: 'PostgreSQL 不可连接；未启动站点。',
    SCHEMA_MISMATCH: '数据库已连接，但当前曲库 schema 不匹配；未启动站点。',
    MIGRATIONS_PENDING: '本地曲库尚未完成全部必要迁移；未启动站点。',
    DATABASE_AUTH: '数据库拒绝了只读检查；请核对容器的本地数据库身份配置。',
    DATABASE_CONFIG: '容器中的目标数据库不存在或配置不匹配；未启动站点。',
    EMPTY_CATALOG: '本地曲库连接正常，但曲谱表为空；为避免显示演示数据，暂不启动站点。',
    DATABASE_PROBE_TIMEOUT: 'PostgreSQL 只读检查或客户端清理超时；未启动站点。',
  };
  if (error instanceof LocalCatalogRuntimeError && knownFailures[error.code]) {
    fail(error.code, knownFailures[error.code]);
  }
  fail('DATABASE_PROBE', '本地 PostgreSQL 只读检查失败；未启动站点。');
}

function classifyPrismaFailure(error) {
  if (error instanceof LocalCatalogRuntimeError) return error;
  const code = typeof error?.code === 'string' ? error.code : '';
  if (['P1000', 'P1010'].includes(code)) {
    return new LocalCatalogRuntimeError('DATABASE_AUTH', 'PostgreSQL 拒绝了只读连接。');
  }
  if (['P1001', 'P1002', 'P1008', 'P1017', 'P2024'].includes(code)) {
    return new LocalCatalogRuntimeError('DATABASE_UNAVAILABLE', 'PostgreSQL 连接或只读查询超时。');
  }
  if (['P2021', 'P2022'].includes(code)) {
    return new LocalCatalogRuntimeError('SCHEMA_MISMATCH', '数据库中的曲谱表结构与当前应用不匹配。');
  }
  if (code === 'P1003') {
    return new LocalCatalogRuntimeError('DATABASE_CONFIG', '本地 PostgreSQL 目标数据库不存在。');
  }
  return new LocalCatalogRuntimeError('DATABASE_PROBE', '本地 PostgreSQL 只读连接检查失败。');
}

function withTimeout(operation, timeoutMs, code, message) {
  let timer;
  const operationPromise = Promise.resolve().then(() => operation);
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new LocalCatalogRuntimeError(code, message)), timeoutMs);
  });
  return Promise.race([operationPromise, timeoutPromise]).finally(() => clearTimeout(timer));
}

export async function probePrismaCatalog({ databaseUrl, createClient, timeouts = {} }) {
  let client;
  let probeResult;
  let probeError;
  let cleanupTimedOut = false;
  const totalTimeoutMs = timeouts.totalMs ?? PRISMA_TOTAL_TIMEOUT_MS;
  const connectTimeoutMs = timeouts.connectMs ?? (PRISMA_CONNECT_TIMEOUT_SECONDS + 1) * 1_000;
  const transactionTimeoutMs = timeouts.transactionMs ?? PRISMA_PROBE_TIMEOUT_MS;
  const disconnectTimeoutMs = timeouts.disconnectMs ?? PRISMA_DISCONNECT_TIMEOUT_MS;
  const deadline = Date.now() + totalTimeoutMs;
  const remaining = () => Math.max(1, deadline - Date.now());
  try {
    client = await withTimeout(
      createClient(databaseUrl), remaining(), 'DATABASE_PROBE_TIMEOUT',
      'Prisma 只读检查超过总时限。',
    );
    if (!client || typeof client.$connect !== 'function' || typeof client.$transaction !== 'function' ||
        typeof client.$disconnect !== 'function') {
      fail('DATABASE_PROBE', 'Prisma 只读检查客户端无法使用。');
    }
    await withTimeout(
      client.$connect(), Math.min(remaining(), connectTimeoutMs),
      'DATABASE_PROBE_TIMEOUT', 'Prisma 连接检查超过时限。',
    );
    probeResult = await withTimeout(client.$transaction(async (tx) => {
        await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');
        const ping = await tx.$queryRawUnsafe('SELECT 1 AS "ok"');
        if (!Array.isArray(ping) || ping.length !== 1 || Number(ping[0]?.ok) !== 1) {
          fail('DATABASE_PROBE', 'PostgreSQL 连通性检查未返回预期结果。');
        }
        const databaseRows = await tx.$queryRawUnsafe('SELECT current_database() AS "database"');
        if (!Array.isArray(databaseRows) || databaseRows.length !== 1 || typeof databaseRows[0]?.database !== 'string') {
          fail('DATABASE_PROBE', 'PostgreSQL 数据库身份检查未返回预期结果。');
        }
        const database = databaseRows[0].database;
        if (database !== LOCAL_DATABASE_NAME) {
          fail('DATABASE_CONFIG', '本地曲库连接到了非预期数据库。');
        }
        if (typeof tx.tab?.count !== 'function') {
          fail('SCHEMA_MISMATCH', '当前 Prisma 客户端没有曲谱只读计数接口。');
        }
        const rowCount = await tx.tab.count();
        if (!Number.isSafeInteger(rowCount) || rowCount <= 0) {
          fail('EMPTY_CATALOG', '本地曲库连接正常，但曲谱表为空；为避免显示演示数据，暂不启动站点。');
        }
        return { database, rowCount };
      }, { maxWait: transactionTimeoutMs, timeout: transactionTimeoutMs }),
      Math.min(remaining(), transactionTimeoutMs + 100),
      'DATABASE_PROBE_TIMEOUT', 'Prisma 只读事务超过时限。',
    );
  } catch (error) {
    probeError = error;
  } finally {
    if (client) {
      try {
        await withTimeout(
          client.$disconnect(), disconnectTimeoutMs,
          'DATABASE_PROBE_TIMEOUT', 'Prisma 客户端清理超过时限。',
        );
      } catch (error) {
        if (error instanceof LocalCatalogRuntimeError && error.code === 'DATABASE_PROBE_TIMEOUT') cleanupTimedOut = true;
        if (!probeError || cleanupTimedOut) probeError = error;
      }
    }
  }
  if (cleanupTimedOut) {
    fail('DATABASE_PROBE_TIMEOUT', 'Prisma 客户端清理超时；未启动站点。');
  }
  if (probeError) reportProbeFailure(classifyPrismaFailure(probeError));
  return probeResult;
}

export async function checkLocalCatalog({ runDocker, probePrisma, existingDatabaseUrl }) {
  let inspectionOutput;
  try {
    inspectionOutput = await runDocker(['inspect', '--type', 'container', LOCAL_POSTGRES_CONTAINER]);
  } catch (error) {
    if (error instanceof LocalCatalogRuntimeError && error.code === 'DOCKER_TIMEOUT') {
      fail('DOCKER_TIMEOUT', 'Docker 检查超时；请确认 Docker Desktop 已就绪。');
    }
    fail('DOCKER_UNAVAILABLE', '无法读取本地曲库容器信息；请确认 Docker Desktop 已运行。');
  }

  const target = inspectLocalPostgres(inspectionOutput);
  const databaseUrl = resolveDatabaseUrl(existingDatabaseUrl, target);

  let probeOutput;
  try {
    probeOutput = await runDocker([
      'exec',
      '--user=postgres',
      target.containerName,
      'psql',
      '--no-psqlrc',
      '--quiet',
      '--tuples-only',
      '--no-align',
      '--set=ON_ERROR_STOP=1',
      '--username',
      target.user,
      '--dbname',
      target.database,
      '--command',
      READ_ONLY_SCHEMA_SQL,
    ]);
  } catch (error) {
    reportProbeFailure(error);
  }

  const schema = parseReadOnlySchemaResult(probeOutput);
  if (!schema.migrationsTableExists) {
    fail('MIGRATIONS_PENDING', '本地曲库尚未完成全部必要迁移；未启动站点。');
  }

  let migrationOutput;
  try {
    migrationOutput = await runDocker([
      'exec', '--user=postgres', target.containerName, 'psql',
      '--no-psqlrc', '--quiet', '--tuples-only', '--no-align', '--set=ON_ERROR_STOP=1',
      '--username', target.user, '--dbname', target.database, '--command', READ_ONLY_MIGRATIONS_SQL,
    ]);
  } catch (error) {
    reportProbeFailure(error);
  }
  parseReadOnlyMigrationResult(migrationOutput);

  if (!schema.tabExists || schema.missingColumns.length > 0) {
    fail('SCHEMA_MISMATCH', '数据库迁移记录齐全，但当前 Prisma 模型列与应用不匹配；未启动站点。');
  }

  let catalog;
  try {
    catalog = await probePrisma(databaseUrl);
  } catch (error) {
    reportProbeFailure(classifyPrismaFailure(error));
  }

  return {
    containerName: target.containerName,
    host: target.host,
    hostPort: target.hostPort,
    database: catalog.database,
    rowCount: catalog.rowCount,
    databaseUrl,
  };
}

export async function checkThenStart({ check, launch }) {
  const result = await check();
  await launch(result.databaseUrl);
  return result;
}
