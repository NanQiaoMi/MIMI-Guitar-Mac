import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { createReadStream, promises as fsPromises } from 'node:fs';
import { createServer } from 'node:net';
import path from 'node:path';

export const MAC_PROJECT_NAME = 'mimi-guitar-mac-dev';
export const MAC_CONTAINER_NAME = 'mimi-guitar-mac-dev-db';
export const MAC_VOLUME_NAME = 'mimi-guitar-mac-dev-data';
export const MAC_NETWORK_NAME = `${MAC_PROJECT_NAME}_default`;
export const MAC_CONFIG_NAME = '.env.mac.local';
export const MAC_DB_PORT = 15433;
export const MAC_DB_NAME = 'mimi_catalog';
export const MAC_DB_USER = 'mimi_mac';
export const MAC_CATALOG_EXPECTATION = Object.freeze({
  postgresMajor: 16,
  sha256: '7f709c83bf7d43d18d9a92ebf8b08a9dd1ddbbf6dc1cbe3173611f96168c71a1',
  counts: Object.freeze({ tabs: 16233, articles: 8, migrations: 4 }),
});

const INSTALL_DATABASE_URL = 'postgresql://bootstrap:bootstrap-only@127.0.0.1:1/bootstrap?schema=public';
const MAX_CAPTURE_BYTES = 256 * 1024;
const COMMAND_TIMEOUT_MS = 15_000;
const INSTALL_TIMEOUT_MS = 20 * 60_000;
const RESTORE_TIMEOUT_MS = 30 * 60_000;
const DATABASE_READY_TIMEOUT_MS = 90_000;
const LOCAL_DOCKER_CONTEXT_REQUIRED = 'A local Docker Desktop context using a Unix socket is required; select it manually and retry.';

export class MacBootstrapError extends Error {
  constructor(message) {
    super(message);
    this.name = 'MacBootstrapError';
  }
}

function trimCaptured(value) {
  if (value.length <= MAX_CAPTURE_BYTES) return value;
  return value.slice(-MAX_CAPTURE_BYTES);
}

function makeRedactor(secrets = []) {
  const candidates = [...new Set(secrets.filter((secret) => typeof secret === 'string' && secret.length > 0))];
  let pending = '';

  return (chunk, flush = false) => {
    pending += chunk;
    for (const secret of candidates) pending = pending.split(secret).join('[redacted]');
    if (flush) {
      const ready = pending;
      pending = '';
      return ready;
    }
    let partialSecretLength = 0;
    for (const secret of candidates) {
      const maxLength = Math.min(pending.length, secret.length - 1);
      for (let length = maxLength; length > partialSecretLength; length -= 1) {
        if (pending.endsWith(secret.slice(0, length))) {
          partialSecretLength = length;
          break;
        }
      }
    }
    const readyLength = pending.length - partialSecretLength;
    const ready = pending.slice(0, readyLength);
    pending = pending.slice(readyLength);
    return ready;
  };
}

export function createMacProcessRunner({ spawnProcess = spawn, streamFile = createReadStream } = {}) {
  return (command, args, options = {}) => new Promise((resolve) => {
    let child;
    let stdout = '';
    let stderr = '';
    let stdoutTruncated = false;
    let stderrTruncated = false;
    let timedOut = false;
    let inputFailed = false;
    const stdoutRedactor = makeRedactor(options.redact);
    const stderrRedactor = makeRedactor(options.redact);
    let timeoutHandle;
    let killHandle;

    try {
      child = spawnProcess(command, args, {
        cwd: options.cwd,
        env: options.env ?? process.env,
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch {
      resolve({ code: 127, stdout: '', stderr: '' });
      return;
    }

    const collect = (target, chunk, redactor, forward) => {
      const safeText = redactor(chunk.toString('utf8'));
      if (!safeText) return;
      if (target === 'stdout') {
        if (stdout.length + safeText.length > MAX_CAPTURE_BYTES) stdoutTruncated = true;
        stdout = trimCaptured(stdout + safeText);
      } else {
        if (stderr.length + safeText.length > MAX_CAPTURE_BYTES) stderrTruncated = true;
        stderr = trimCaptured(stderr + safeText);
      }
      if (forward) {
        const output = target === 'stdout' ? process.stdout : process.stderr;
        output.write(safeText);
      }
    };

    child.stdout?.on('data', (chunk) => collect('stdout', chunk, stdoutRedactor, options.forwardOutput));
    child.stderr?.on('data', (chunk) => collect('stderr', chunk, stderrRedactor, options.forwardOutput));
    child.stdin?.on('error', () => { inputFailed = true; });

    const timeoutMs = options.timeoutMs ?? COMMAND_TIMEOUT_MS;
    if (timeoutMs > 0) {
      timeoutHandle = setTimeout(() => {
        timedOut = true;
        child.kill('SIGTERM');
        killHandle = setTimeout(() => child.kill('SIGKILL'), 2_000);
      }, timeoutMs);
      timeoutHandle.unref?.();
    }

    child.once('error', () => {
      clearTimeout(timeoutHandle);
      clearTimeout(killHandle);
      resolve({ code: 127, stdout: '', stderr: '' });
    });
    child.once('close', (code) => {
      clearTimeout(timeoutHandle);
      clearTimeout(killHandle);
      const safeStdout = stdoutRedactor('', true);
      const safeStderr = stderrRedactor('', true);
      if (stdout.length + safeStdout.length > MAX_CAPTURE_BYTES) stdoutTruncated = true;
      if (stderr.length + safeStderr.length > MAX_CAPTURE_BYTES) stderrTruncated = true;
      stdout = trimCaptured(stdout + safeStdout);
      stderr = trimCaptured(stderr + safeStderr);
      if (options.forwardOutput) {
        if (safeStdout) process.stdout.write(safeStdout);
        if (safeStderr) process.stderr.write(safeStderr);
      }
      resolve({ code: inputFailed ? 1 : (timedOut ? 124 : (code ?? 1)), stdout, stderr, timedOut, stdoutTruncated, stderrTruncated });
    });

    if (options.stdinFile) {
      let input;
      try {
        input = streamFile(options.stdinFile);
      } catch {
        inputFailed = true;
        child.kill('SIGTERM');
      }
      input?.once('error', () => {
        inputFailed = true;
        child.kill('SIGTERM');
      });
      input?.pipe(child.stdin);
    } else {
      child.stdin?.end();
    }
  });
}

export function probeLoopbackPort(port, host = '127.0.0.1') {
  return new Promise((resolve) => {
    const server = createServer();
    server.once('error', () => resolve(false));
    server.listen(port, host, () => {
      server.close((error) => resolve(!error));
    });
  });
}

function readVersionMajor(version) {
  const match = /^v?(\d+)\./.exec(String(version));
  return match ? Number(match[1]) : Number.NaN;
}

async function sha256File(filePath) {
  const hash = createHash('sha256');
  const stream = createReadStream(filePath);
  for await (const chunk of stream) hash.update(chunk);
  return hash.digest('hex');
}

function requireSuccess(result, description) {
  if (!result || result.code !== 0) {
    const suffix = result?.timedOut ? ' timed out' : ' failed';
    throw new MacBootstrapError(`${description}${suffix}; inspect the local tool and retry after review.`);
  }
  return String(result.stdout ?? '').trim();
}

function isLocalUnixDockerEndpoint(endpoint) {
  return typeof endpoint === 'string' && /^unix:\/\/\/[^\s?#]+$/.test(endpoint);
}

function makeDatabaseUrl(password) {
  return `postgresql://${MAC_DB_USER}:${password}@127.0.0.1:${MAC_DB_PORT}/${MAC_DB_NAME}?schema=public`;
}

function parseConfig(contents) {
  const expectedKeys = new Set([
    'MIMI_MAC_CONFIG_VERSION',
    'MIMI_MAC_DB_NAME',
    'MIMI_MAC_DB_USER',
    'MIMI_MAC_DB_PASSWORD',
    'MIMI_MAC_DB_PORT',
  ]);
  const values = new Map();
  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator <= 0) throw new MacBootstrapError('The local Mac config is invalid; review it manually before continuing.');
    const key = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (!expectedKeys.has(key) || values.has(key) || value.length === 0) {
      throw new MacBootstrapError('The local Mac config is invalid; review it manually before continuing.');
    }
    values.set(key, value);
  }
  if (values.size !== expectedKeys.size
      || values.get('MIMI_MAC_CONFIG_VERSION') !== '1'
      || values.get('MIMI_MAC_DB_NAME') !== MAC_DB_NAME
      || values.get('MIMI_MAC_DB_USER') !== MAC_DB_USER
      || values.get('MIMI_MAC_DB_PORT') !== String(MAC_DB_PORT)
      || !/^[A-Za-z0-9_-]{40,}$/.test(values.get('MIMI_MAC_DB_PASSWORD') ?? '')) {
    throw new MacBootstrapError('The local Mac config is invalid; review it manually before continuing.');
  }
  const password = values.get('MIMI_MAC_DB_PASSWORD');
  return {
    password,
    databaseUrl: makeDatabaseUrl(password),
    composeEnv: {
      MIMI_MAC_DB_NAME: MAC_DB_NAME,
      MIMI_MAC_DB_USER: MAC_DB_USER,
      MIMI_MAC_DB_PASSWORD: password,
      MIMI_MAC_DB_PORT: String(MAC_DB_PORT),
    },
  };
}

function composeArgs(paths, suffix, { includeEnvFile = true } = {}) {
  const args = ['compose', '--file', paths.composeFile, '--project-name', MAC_PROJECT_NAME];
  if (includeEnvFile) args.push('--env-file', paths.configFile);
  args.push(...suffix);
  return args;
}

function safeComposeEnvironment(parentEnv) {
  const env = { ...parentEnv };
  for (const key of Object.keys(env)) {
    if (key.startsWith('MIMI_MAC_DB_') || key === 'MIMI_MAC_CONFIG_VERSION') delete env[key];
  }
  return env;
}

export function createMacBootstrap({
  projectDir,
  fs = fsPromises,
  run,
  portProbe = probeLoopbackPort,
  randomSecret = () => randomBytes(32).toString('base64url'),
  platform = process.platform,
  arch = process.arch,
  nodeVersion = process.version,
  catalogExpectation = MAC_CATALOG_EXPECTATION,
  parentEnv = process.env,
  output = () => {},
  wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
  now = () => Date.now(),
} = {}) {
  if (!projectDir || typeof run !== 'function') throw new TypeError('projectDir and run are required');

  const absoluteProjectDir = path.resolve(projectDir);
  const handoffRoot = path.resolve(absoluteProjectDir, '..');
  const paths = {
    projectDir: absoluteProjectDir,
    handoffRoot,
    composeFile: path.join(absoluteProjectDir, 'docker-compose.mac.yml'),
    configFile: path.join(absoluteProjectDir, MAC_CONFIG_NAME),
    dumpFile: path.join(handoffRoot, 'database', 'catalog.dump'),
    metadataFile: path.join(handoffRoot, 'database', 'catalog-metadata.json'),
    serverEntry: path.join(absoluteProjectDir, 'dist', 'server', 'entry.mjs'),
  };

  async function callResult(command, args, options = {}, description = `${command} command`) {
    let result;
    try {
      result = await run(command, args, { cwd: paths.projectDir, ...options });
    } catch {
      throw new MacBootstrapError(`${description} could not start; check the local installation and try again.`);
    }
    requireSuccess(result, description);
    return result;
  }

  async function call(command, args, options = {}, description = `${command} command`) {
    const result = await callResult(command, args, options, description);
    return String(result.stdout ?? '').trim();
  }

  function requireMacOS() {
    if (platform !== 'darwin') throw new MacBootstrapError('This Mac handoff command must run on macOS.');
  }

  function requireNode24() {
    if (readVersionMajor(nodeVersion) !== 24) {
      throw new MacBootstrapError('Node.js 24.x is required. Select or install it manually, then rerun this command.');
    }
  }

  async function requireLocalFile(filePath, label, { minimumSize = 0 } = {}) {
    let stat;
    try {
      stat = await fs.lstat(filePath);
    } catch {
      throw new MacBootstrapError(`${label} is missing; place the package file at its documented path and retry.`);
    }
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size < minimumSize) {
      throw new MacBootstrapError(`${label} is not a valid regular file; review the package before continuing.`);
    }
    return stat;
  }

  async function assertDumpIsCustomArchive() {
    await requireLocalFile(paths.dumpFile, 'database/catalog.dump', { minimumSize: 5 });
    await requireLocalFile(paths.metadataFile, 'database/catalog-metadata.json', { minimumSize: 2 });
    let metadata;
    try {
      metadata = JSON.parse(await fs.readFile(paths.metadataFile, 'utf8'));
    } catch {
      throw new MacBootstrapError('database/catalog-metadata.json is invalid; review the package before continuing.');
    }
    if (metadata?.postgresMajor !== catalogExpectation.postgresMajor
        || metadata?.sha256 !== catalogExpectation.sha256
        || metadata?.counts?.tabs !== catalogExpectation.counts.tabs
        || metadata?.counts?.articles !== catalogExpectation.counts.articles
        || metadata?.counts?.migrations !== catalogExpectation.counts.migrations) {
      throw new MacBootstrapError('database/catalog-metadata.json does not match the approved PostgreSQL 16 snapshot.');
    }
    let actualSha256;
    try {
      actualSha256 = await sha256File(paths.dumpFile);
    } catch {
      throw new MacBootstrapError('database/catalog.dump could not be hashed; review the package before continuing.');
    }
    if (actualSha256 !== metadata.sha256) {
      throw new MacBootstrapError('database/catalog.dump SHA-256 does not match its metadata; nothing was restored.');
    }
    let handle;
    try {
      handle = await fs.open(paths.dumpFile, 'r');
      const header = Buffer.alloc(5);
      const readResult = await handle.read(header, 0, header.length, 0);
      if (readResult.bytesRead !== 5 || header.toString('ascii') !== 'PGDMP') {
        throw new MacBootstrapError('database/catalog.dump is not a PostgreSQL custom-format archive.');
      }
    } catch (error) {
      if (error instanceof MacBootstrapError) throw error;
      throw new MacBootstrapError('database/catalog.dump could not be read; review the package before continuing.');
    } finally {
      await handle?.close().catch(() => {});
    }
    return metadata;
  }

  async function readOrCreateConfig({ create = false } = {}) {
    let stat;
    try {
      stat = await fs.lstat(paths.configFile);
    } catch (error) {
      if (error?.code !== 'ENOENT') throw new MacBootstrapError('The local Mac config could not be checked.');
      if (!create) throw new MacBootstrapError('Run restore-catalog first to create the isolated local database config.');
      const password = randomSecret();
      if (!/^[A-Za-z0-9_-]{40,}$/.test(password)) throw new MacBootstrapError('Could not create a valid local development secret.');
      const contents = [
        'MIMI_MAC_CONFIG_VERSION=1',
        `MIMI_MAC_DB_NAME=${MAC_DB_NAME}`,
        `MIMI_MAC_DB_USER=${MAC_DB_USER}`,
        `MIMI_MAC_DB_PASSWORD=${password}`,
        `MIMI_MAC_DB_PORT=${MAC_DB_PORT}`,
        '',
      ].join('\n');
      try {
        await fs.writeFile(paths.configFile, contents, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
        await fs.chmod(paths.configFile, 0o600);
      } catch {
        throw new MacBootstrapError('The local Mac config could not be created; inspect the target path and retry.');
      }
      return parseConfig(contents);
    }

    if (!stat.isFile() || stat.isSymbolicLink()) {
      throw new MacBootstrapError('The local Mac config must be a regular file created by this tool.');
    }
    try {
      await fs.chmod(paths.configFile, 0o600);
      const contents = await fs.readFile(paths.configFile, 'utf8');
      return parseConfig(contents);
    } catch (error) {
      if (error instanceof MacBootstrapError) throw error;
      throw new MacBootstrapError('The local Mac config could not be secured or read; review it manually.');
    }
  }

  async function checkDockerReady() {
    await call('docker', ['--version'], {}, 'Docker CLI check');
    await call('docker', ['compose', 'version'], {}, 'Docker Compose check');
    await assertLocalDockerEndpoint();
    await call('docker', ['info', '--format', '{{.ServerVersion}}'], {}, 'Docker Desktop engine check');
  }

  async function assertLocalDockerEndpoint() {
    const dockerHostOverride = typeof parentEnv?.DOCKER_HOST === 'string' ? parentEnv.DOCKER_HOST.trim() : '';
    if (dockerHostOverride && !isLocalUnixDockerEndpoint(dockerHostOverride)) {
      throw new MacBootstrapError(LOCAL_DOCKER_CONTEXT_REQUIRED);
    }
    const selectedContext = await call('docker', ['context', 'show'], {}, 'Docker context check');
    if (!selectedContext || /[\r\n]/.test(selectedContext)) {
      throw new MacBootstrapError(LOCAL_DOCKER_CONTEXT_REQUIRED);
    }
    const endpoint = await call('docker', [
      'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}', selectedContext,
    ], {}, 'Docker context endpoint check');
    if (!isLocalUnixDockerEndpoint(endpoint)) {
      throw new MacBootstrapError(LOCAL_DOCKER_CONTEXT_REQUIRED);
    }
  }

  async function checkPortAvailable(port, label) {
    let available;
    try {
      available = await portProbe(port, '127.0.0.1');
    } catch {
      available = false;
    }
    if (!available) throw new MacBootstrapError(`127.0.0.1:${port} is unavailable; free that port and retry ${label}.`);
  }

  async function assertNoTargetResources() {
    const resourceChecks = [
      ['container', ['ls', '-aq', '--filter', `label=com.docker.compose.project=${MAC_PROJECT_NAME}`]],
      ['volume', ['ls', '-q', '--filter', `label=com.docker.compose.project=${MAC_PROJECT_NAME}`]],
      ['network', ['ls', '-q', '--filter', `label=com.docker.compose.project=${MAC_PROJECT_NAME}`]],
      ['container', ['ls', '-aq', '--filter', `name=^/${MAC_CONTAINER_NAME}$`]],
      ['volume', ['ls', '-q', '--filter', `name=^${MAC_VOLUME_NAME}$`]],
      ['network', ['ls', '-q', '--filter', `name=^${MAC_NETWORK_NAME}$`]],
    ];
    for (const [kind, args] of resourceChecks) {
      const ids = await call('docker', [kind, ...args], {}, `Docker ${kind} conflict check`);
      if (ids.length > 0) {
        throw new MacBootstrapError(`The isolated Mac ${kind} target already exists. No database action was taken; review the existing resource manually.`);
      }
    }
  }

  async function assertFreshContainerAndVolume() {
    const checks = [
      [
        ['inspect', '--format', '{{ index .Config.Labels "com.docker.compose.project" }}', MAC_CONTAINER_NAME],
        MAC_PROJECT_NAME,
        'container project label',
      ],
      [
        ['inspect', '--format', '{{ index .Config.Labels "com.docker.compose.service" }}', MAC_CONTAINER_NAME],
        'db',
        'container service label',
      ],
      [
        ['inspect', '--format', '{{.Config.Image}}', MAC_CONTAINER_NAME],
        'postgres:16',
        'container image',
      ],
      [
        ['inspect', '--format', '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}', MAC_CONTAINER_NAME],
        MAC_VOLUME_NAME,
        'container data volume',
      ],
      [
        ['volume', 'inspect', '--format', '{{ index .Labels "com.docker.compose.project" }}', MAC_VOLUME_NAME],
        MAC_PROJECT_NAME,
        'volume project label',
      ],
      [
        ['volume', 'inspect', '--format', '{{ index .Labels "com.docker.compose.volume" }}', MAC_VOLUME_NAME],
        'catalog-data',
        'volume identity label',
      ],
      [
        ['volume', 'inspect', '--format', '{{.Driver}}', MAC_VOLUME_NAME],
        'local',
        'volume driver',
      ],
    ];
    for (const [args, expected, description] of checks) {
      const actual = await call('docker', args, {}, `Docker ${description} check`);
      if (actual !== expected) throw new MacBootstrapError(`The isolated Mac ${description} did not match; the database was not restored.`);
    }
  }

  async function waitForDatabase() {
    const deadline = now() + DATABASE_READY_TIMEOUT_MS;
    while (now() < deadline) {
      const status = await call('docker', ['inspect', '--format', '{{.State.Health.Status}}', MAC_CONTAINER_NAME], {}, 'PostgreSQL health check');
      if (status === 'healthy') return;
      if (status === 'unhealthy') throw new MacBootstrapError('The new PostgreSQL container is unhealthy; its resources were left in place for manual inspection.');
      await wait(1_000);
    }
    throw new MacBootstrapError('The new PostgreSQL container did not become healthy within 90 seconds; its resources were left in place for manual inspection.');
  }

  function psqlArgs(query) {
    return composeArgs(paths, [
      'exec', '-T', 'db', 'psql', '-X', '-q', '-A', '-t', '-F', '|',
      '-v', 'ON_ERROR_STOP=1', '--username', MAC_DB_USER, '--dbname', MAC_DB_NAME, '-c', query,
    ]);
  }

  async function assertEmptyDatabase() {
    const query = "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public';";
    const result = await call('docker', psqlArgs(query), {
      env: safeComposeEnvironment(parentEnv),
    }, 'New database emptiness check');
    if (result !== '0') throw new MacBootstrapError('The new database is not empty; no archive was restored and resources were left in place.');
  }

  function assertArchiveContainsOnlyCatalogData(listing) {
    const allowedDataTables = new Set(['Tab', 'Article', '_prisma_migrations']);
    const entries = String(listing).split(/\r?\n/).filter((line) => /^\s*\d+;/.test(line) && /\bTABLE DATA\b/.test(line));
    const found = new Set();
    for (const entry of entries) {
      const match = /\bTABLE DATA\s+"?public"?\s+("(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_$]*)/.exec(entry);
      const table = match?.[1]?.startsWith('"')
        ? match[1].slice(1, -1).replaceAll('""', '"')
        : match?.[1];
      if (!table || !allowedDataTables.has(table) || found.has(table)) {
        throw new MacBootstrapError('The archive contains data outside the approved catalog tables; nothing was restored and the new database was left empty.');
      }
      found.add(table);
    }
    if (found.size !== allowedDataTables.size) {
      throw new MacBootstrapError('The archive is missing Tab, Article, or migration data; nothing was restored and the new database was left empty.');
    }
  }

  async function verifyRestoredCatalog(metadata) {
    const query = [
      `SELECT 'Tab', count(*) FROM public."Tab"`,
      `UNION ALL SELECT 'Article', count(*) FROM public."Article"`,
      `UNION ALL SELECT '_prisma_migrations', count(*) FROM public."_prisma_migrations"`,
      `UNION ALL SELECT 'CompletedMigrationRows', count(*) FROM public."_prisma_migrations" WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL`,
      `UNION ALL SELECT 'IncompleteMigrationRows', count(*) FROM public."_prisma_migrations" WHERE finished_at IS NULL AND rolled_back_at IS NULL`,
      `UNION ALL SELECT 'User', count(*) FROM public."User"`,
      `UNION ALL SELECT 'Favorite', count(*) FROM public."Favorite"`,
      `UNION ALL SELECT 'UploadRecord', count(*) FROM public."UploadRecord";`,
    ].join('\n');
    const outputText = await call('docker', psqlArgs(query), {
      env: safeComposeEnvironment(parentEnv),
      timeoutMs: COMMAND_TIMEOUT_MS,
    }, 'Restored catalog verification');
    const counts = new Map();
    for (const line of outputText.split(/\r?\n/).filter(Boolean)) {
      const separator = line.indexOf('|');
      if (separator < 1) throw new MacBootstrapError('Restored catalog verification returned an invalid result; resources were left in place.');
      const name = line.slice(0, separator);
      const value = Number(line.slice(separator + 1));
      if (!Number.isSafeInteger(value) || value < 0) throw new MacBootstrapError('Restored catalog verification returned an invalid count; resources were left in place.');
      counts.set(name, value);
    }
    for (const name of ['Tab', 'Article', '_prisma_migrations', 'CompletedMigrationRows', 'IncompleteMigrationRows', 'User', 'Favorite', 'UploadRecord']) {
      if (!counts.has(name)) throw new MacBootstrapError('Restored catalog verification missed an expected table; resources were left in place.');
    }
    if (counts.get('Tab') < 1 || counts.get('Article') < 1 || counts.get('_prisma_migrations') < 1
        || counts.get('CompletedMigrationRows') !== metadata.counts.migrations
        || counts.get('IncompleteMigrationRows') !== 0) {
      throw new MacBootstrapError('The restored catalog is missing required Tab, Article, or migration data; resources were left in place.');
    }
    if (counts.get('User') !== 0 || counts.get('Favorite') !== 0 || counts.get('UploadRecord') !== 0) {
      throw new MacBootstrapError('The restored catalog contains excluded account or activity rows; resources were left in place for manual review.');
    }
    if (counts.get('Tab') !== metadata.counts.tabs
        || counts.get('Article') !== metadata.counts.articles
        || counts.get('_prisma_migrations') !== metadata.counts.migrations) {
      throw new MacBootstrapError('Restored catalog row counts did not match the verified snapshot metadata; resources were left in place.');
    }
    return counts;
  }

  async function doctor() {
    const nodeOkay = readVersionMajor(nodeVersion) === 24;
    output(`Node.js: ${nodeVersion} (${nodeOkay ? 'ready' : 'requires 24.x'})`);
    output(`macOS: ${platform === 'darwin' ? 'ready' : 'not macOS'}; architecture: ${arch}`);
    const checks = [
      ['npm', ['--version'], 'npm'],
      ['docker', ['--version'], 'Docker CLI'],
      ['docker', ['compose', 'version'], 'Docker Compose'],
    ];
    let allReady = nodeOkay && platform === 'darwin';
    for (const [command, args, label] of checks) {
      try {
        const result = await run(command, args, { cwd: paths.projectDir, timeoutMs: COMMAND_TIMEOUT_MS });
        if (result?.code === 0) output(`${label}: ready`);
        else {
          allReady = false;
          output(`${label}: unavailable; install/start it manually if the next step needs it`);
        }
      } catch {
        allReady = false;
        output(`${label}: unavailable; install/start it manually if the next step needs it`);
      }
    }
    let localDockerEndpointReady = false;
    try {
      await assertLocalDockerEndpoint();
      localDockerEndpointReady = true;
      output('Docker context endpoint: local Unix socket');
    } catch {
      allReady = false;
      output('Docker context endpoint: unavailable or remote; select the local Docker Desktop context manually.');
    }
    if (localDockerEndpointReady) {
      try {
        const result = await run('docker', ['info', '--format', '{{.ServerVersion}}'], { cwd: paths.projectDir, timeoutMs: COMMAND_TIMEOUT_MS });
        if (result?.code === 0) output('Docker Desktop engine: ready');
        else {
          allReady = false;
          output('Docker Desktop engine: unavailable; start it manually if the next step needs it');
        }
      } catch {
        allReady = false;
        output('Docker Desktop engine: unavailable; start it manually if the next step needs it');
      }
    } else {
      output('Docker Desktop engine: not checked because a local context is required');
    }
    if (!allReady) output('Doctor found missing prerequisites. No software or operating-system permissions were changed.');
    return { ok: allReady };
  }

  async function install({ dryRun = false } = {}) {
    requireMacOS();
    requireNode24();
    if (dryRun) {
      output('Dry run: would run npm ci --include=dev, then npm run prisma:generate with a non-routable placeholder DATABASE_URL.');
      return { ok: true, dryRun: true };
    }
    await call('npm', ['--version'], {}, 'npm check');
    output('Running npm ci...');
    await call('npm', ['ci', '--include=dev'], {
      env: { ...parentEnv, DATABASE_URL: INSTALL_DATABASE_URL },
      timeoutMs: INSTALL_TIMEOUT_MS,
    }, 'npm ci');
    output('Generating Prisma Client...');
    await call('npm', ['run', 'prisma:generate'], {
      env: { ...parentEnv, DATABASE_URL: INSTALL_DATABASE_URL },
      timeoutMs: INSTALL_TIMEOUT_MS,
    }, 'Prisma Client generation');
    output('Mac dependencies and Prisma Client are ready.');
    return { ok: true };
  }

  async function build({ dryRun = false } = {}) {
    requireMacOS();
    requireNode24();
    if (dryRun) {
      output('Dry run: would run npm run build with the isolated local DATABASE_URL in the child process only.');
      return { ok: true, dryRun: true };
    }
    const config = await readOrCreateConfig();
    output('Building the Mac project...');
    await call('npm', ['run', 'build'], {
      env: { ...parentEnv, DATABASE_URL: config.databaseUrl },
      timeoutMs: INSTALL_TIMEOUT_MS,
      forwardOutput: true,
      redact: [config.databaseUrl, config.password],
    }, 'Astro build');
    output('Build completed.');
    return { ok: true };
  }

  async function startApp(mode, { dryRun = false } = {}) {
    requireMacOS();
    requireNode24();
    const devMode = mode === 'dev';
    const port = devMode ? 4321 : 4336;
    if (dryRun) {
      output(`Dry run: would start ${devMode ? 'Astro dev' : 'the built Astro server'} on 127.0.0.1:${port}.`);
      return { ok: true, dryRun: true };
    }
    const config = await readOrCreateConfig();
    if (!devMode) await requireLocalFile(paths.serverEntry, 'dist/server/entry.mjs');
    await checkPortAvailable(port, mode);
    const env = {
      ...parentEnv,
      DATABASE_URL: config.databaseUrl,
      HOST: '127.0.0.1',
      PORT: String(port),
    };
    output(`${devMode ? 'Starting Astro dev' : 'Starting the built Astro server'} at http://127.0.0.1:${port} ...`);
    if (devMode) {
      await call('npm', ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(port)], {
        env,
        timeoutMs: 0,
        forwardOutput: true,
        redact: [config.databaseUrl, config.password],
      }, 'Astro dev server');
    } else {
      await call(process.execPath, [path.relative(paths.projectDir, paths.serverEntry)], {
        env,
        timeoutMs: 0,
        forwardOutput: true,
        redact: [config.databaseUrl, config.password],
      }, 'Astro production server');
    }
    return { ok: true };
  }

  async function restoreCatalog({ dryRun = false } = {}) {
    requireMacOS();
    requireNode24();
    await requireLocalFile(paths.composeFile, 'docker-compose.mac.yml');
    const catalogMetadata = await assertDumpIsCustomArchive();
    await checkDockerReady();
    await checkPortAvailable(MAC_DB_PORT, 'catalog restore');
    await assertNoTargetResources();

    if (dryRun) {
      output('Dry run passed: the PostgreSQL 16 archive, Docker engine, target names, and loopback port are ready. No config or container was created.');
      return { ok: true, dryRun: true };
    }

    const config = await readOrCreateConfig({ create: true });
    output('Creating the new isolated PostgreSQL 16 environment...');
    await call('docker', composeArgs(paths, ['up', '--detach', 'db']), {
      env: safeComposeEnvironment(parentEnv),
      timeoutMs: 5 * 60_000,
    }, 'Isolated PostgreSQL container creation');
    await assertFreshContainerAndVolume();
    await waitForDatabase();
    await assertEmptyDatabase();

    const archiveListingResult = await callResult('docker', composeArgs(paths, ['exec', '-T', 'db', 'pg_restore', '--list']), {
      env: safeComposeEnvironment(parentEnv),
      stdinFile: paths.dumpFile,
      timeoutMs: RESTORE_TIMEOUT_MS,
    }, 'PostgreSQL archive safety check');
    if (archiveListingResult.stdoutTruncated) {
      throw new MacBootstrapError('The archive TOC is too large to validate safely; nothing was restored and the new database remains empty.');
    }
    const archiveListing = String(archiveListingResult.stdout ?? '').trim();
    assertArchiveContainsOnlyCatalogData(archiveListing);
    let postListSha256;
    try {
      postListSha256 = await sha256File(paths.dumpFile);
    } catch {
      throw new MacBootstrapError('database/catalog.dump could not be rechecked; the new database remains empty for manual inspection.');
    }
    if (postListSha256 !== catalogMetadata.sha256) {
      throw new MacBootstrapError('database/catalog.dump changed during the archive safety check; the new database remains empty for manual inspection.');
    }

    output('Restoring the catalog archive into the verified empty database...');
    await call('docker', composeArgs(paths, [
      'exec', '-T', 'db', 'pg_restore', '--username', MAC_DB_USER, '--dbname', MAC_DB_NAME,
      '--no-owner', '--no-privileges', '--exit-on-error', '--single-transaction',
    ]), {
      env: safeComposeEnvironment(parentEnv),
      stdinFile: paths.dumpFile,
      timeoutMs: RESTORE_TIMEOUT_MS,
    }, 'PostgreSQL catalog restore');
    const counts = await verifyRestoredCatalog(catalogMetadata);
    output(`Restore verified: Tab=${counts.get('Tab')}, Article=${counts.get('Article')}, migrations=${counts.get('_prisma_migrations')}; User/Favorite/UploadRecord=0.`);
    output('The new local config is stored in .env.mac.local. Its credentials are passed to app processes without printing the connection URL.');
    return { ok: true, counts };
  }

  return {
    paths,
    doctor,
    install,
    build,
    dev: (options) => startApp('dev', options),
    start: (options) => startApp('start', options),
    restoreCatalog,
  };
}

export const MAC_BOOTSTRAP_HELP = `MIMI Guitar Mac bootstrap\n\nCommands (Node.js 24.x):\n  doctor                     Check Node, npm, Docker Compose, and the Docker Desktop engine\n  install [--dry-run]        Run npm ci --include=dev and npm run prisma:generate\n  restore-catalog [--dry-run]\n                             Restore root/database/catalog.dump into a new PostgreSQL 16 target\n  build [--dry-run]          Build with the local database URL passed only to the child process\n  dev [--dry-run]            Start Astro dev at 127.0.0.1:4321\n  start [--dry-run]          Start dist/server/entry.mjs at 127.0.0.1:4336\n  help                       Show this help\n\nStart with doctor and review its results before choosing the next step. Use a local Docker Desktop context backed by a Unix socket; remote, TCP, and SSH endpoints are refused, and the tool never changes contexts. The tool never installs Docker, Homebrew, Node, or OS permissions and never uses sudo.\nThe restore target is a dedicated Compose project, container, volume, network, and loopback port 15433. Existing targets or a busy port are refused.\nThe archive must be a PostgreSQL custom dump. Restore uses --no-owner, --no-privileges, --exit-on-error, and --single-transaction; it never uses --clean or DROP.\nLocal random development credentials are stored in gitignored .env.mac.local. Real Windows credentials and Windows node_modules/dist are not used.\nAfter any restore failure, created resources are preserved for manual inspection; the tool does not stop or delete containers, networks, volumes, or partial files. Review before retrying.`;

export const MAC_BOOTSTRAP_RESTORE_HELP = `\nSnapshot checks: the dump SHA-256 and PostgreSQL/count metadata must match the approved package. Before data is written, the archive TOC must contain data only for Tab, Article, and _prisma_migrations; restored counts and migration state are checked afterward.\nrestore-catalog --dry-run checks the dump checksum and local prerequisites without starting a container; it does not inspect the archive TOC.`;
