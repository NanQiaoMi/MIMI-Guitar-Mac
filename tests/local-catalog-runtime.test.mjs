import assert from 'node:assert/strict';
import test from 'node:test';
import { Prisma } from '@prisma/client';
import {
  LOCAL_DATABASE_NAME,
  LOCAL_DATABASE_USER,
  LOCAL_POSTGRES_CONTAINER,
  LOCAL_POSTGRES_IMAGE,
  LocalCatalogRuntimeError,
  READ_ONLY_MIGRATIONS_SQL,
  READ_ONLY_SCHEMA_SQL,
  PRISMA_CONNECT_TIMEOUT_SECONDS,
  PRISMA_DISCONNECT_TIMEOUT_MS,
  PRISMA_POOL_TIMEOUT_SECONDS,
  PRISMA_PROBE_TIMEOUT_MS,
  PRISMA_TOTAL_TIMEOUT_MS,
  REQUIRED_PRISMA_SCHEMA_COLUMNS,
  REQUIRED_PRISMA_MIGRATIONS,
  REQUIRED_SCHEMA_COLUMN_COUNT,
  buildLocalDatabaseUrl,
  checkLocalCatalog,
  checkThenStart,
  classifyDockerFailure,
  inspectLocalPostgres,
  parseReadOnlyMigrationResult,
  parseReadOnlySchemaResult,
  probePrismaCatalog,
  resolveDatabaseUrl,
} from '../tools/lib/local-catalog-runtime.mjs';

const fakePassword = 'fake:p@ss/with%chars';

function containerSnapshot(overrides = {}) {
  return [{
    Name: `/${LOCAL_POSTGRES_CONTAINER}`,
    Config: {
      Image: LOCAL_POSTGRES_IMAGE,
      Env: [
        `POSTGRES_USER=${LOCAL_DATABASE_USER}`,
        `POSTGRES_DB=${LOCAL_DATABASE_NAME}`,
        `POSTGRES_PASSWORD=${fakePassword}`,
      ],
    },
    State: { Running: true },
    Mounts: [{
      Type: 'volume',
      Name: 'project_pgdata',
      Destination: '/var/lib/postgresql/data',
      RW: true,
    }],
    NetworkSettings: {
      Ports: {
        '5432/tcp': [
          { HostIp: '0.0.0.0', HostPort: '5433' },
          { HostIp: '::', HostPort: '5433' },
        ],
      },
    },
    ...overrides,
  }];
}

function inspectJson(overrides = {}) {
  return JSON.stringify(containerSnapshot(overrides));
}

function schemaOutput(missingColumns = [], { database = LOCAL_DATABASE_NAME, tab = 1, migrations = 1 } = {}) {
  return `database|${database}\ntables|${tab}|${migrations}\nmissing|${missingColumns.join(',')}\n`;
}

function assertCode(error, code) {
  assert.ok(error instanceof LocalCatalogRuntimeError);
  assert.equal(error.code, code);
}

test('accepts only the named PostgreSQL container, expected image, persistent volume, and loopback-capable port', () => {
  const target = inspectLocalPostgres(inspectJson());
  assert.equal(target.containerName, LOCAL_POSTGRES_CONTAINER);
  assert.equal(target.host, '127.0.0.1');
  assert.equal(target.hostPort, 5433);
  assert.equal(target.database, LOCAL_DATABASE_NAME);
  assert.equal(target.user, LOCAL_DATABASE_USER);
  assert.equal(target.password, fakePassword);

  assert.throws(() => inspectLocalPostgres(inspectJson({ Name: '/other-postgres' })), (error) => {
    assertCode(error, 'CONTAINER_IDENTITY');
    assert.equal(error.message.includes(fakePassword), false);
    return true;
  });
  assert.throws(() => inspectLocalPostgres(inspectJson({ Config: { Image: 'postgres:latest', Env: [] } })), (error) => {
    assertCode(error, 'CONTAINER_IDENTITY');
    return true;
  });
  assert.throws(() => inspectLocalPostgres(inspectJson({ State: { Running: false } })), (error) => {
    assertCode(error, 'CONTAINER_STOPPED');
    return true;
  });
  assert.throws(() => inspectLocalPostgres(inspectJson({ Mounts: [] })), (error) => {
    assertCode(error, 'CONTAINER_VOLUME');
    return true;
  });
  assert.throws(() => inspectLocalPostgres(inspectJson({
    NetworkSettings: { Ports: { '5432/tcp': [{ HostIp: '192.168.1.4', HostPort: '5433' }] } },
  })), (error) => {
    assertCode(error, 'CONTAINER_PORT');
    return true;
  });
  assert.throws(() => inspectLocalPostgres(inspectJson({
    NetworkSettings: { Ports: { '5432/tcp': [
      { HostIp: '0.0.0.0', HostPort: '5433' },
      { HostIp: '::', HostPort: '5434' },
    ] } },
  })), (error) => {
    assertCode(error, 'CONTAINER_PORT');
    return true;
  });
  for (const hostIp of ['::', 'not-an-ip', '127.0.0.2']) {
    assert.throws(() => inspectLocalPostgres(inspectJson({
      NetworkSettings: { Ports: { '5432/tcp': [{ HostIp: hostIp, HostPort: '5433' }] } },
    })), (error) => {
      assertCode(error, 'CONTAINER_PORT');
      return true;
    });
  }
});

test('builds an ephemeral loopback URL with encoded container credentials', () => {
  const target = inspectLocalPostgres(inspectJson());
  const url = new URL(buildLocalDatabaseUrl(target));
  assert.equal(url.protocol, 'postgresql:');
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.port, '5433');
  assert.equal(url.username, LOCAL_DATABASE_USER);
  assert.equal(decodeURIComponent(url.password), fakePassword);
  assert.equal(url.pathname, `/${LOCAL_DATABASE_NAME}`);
  assert.equal(url.searchParams.get('connect_timeout'), String(PRISMA_CONNECT_TIMEOUT_SECONDS));
  assert.equal(url.searchParams.get('pool_timeout'), String(PRISMA_POOL_TIMEOUT_SECONDS));
});

test('preserves matching URLs while deriving only missing safe timeout defaults', () => {
  const target = inspectLocalPostgres(inspectJson());
  const expected = buildLocalDatabaseUrl(target);
  assert.equal(resolveDatabaseUrl(expected, target), expected);
  const base = expected.slice(0, expected.indexOf('?'));
  const noQuery = base;
  assert.equal(resolveDatabaseUrl(noQuery, target), `${noQuery}?connect_timeout=3&pool_timeout=3`);
  assert.equal(noQuery, base);
  const schemaOnly = `${base}?schema=public`;
  assert.equal(resolveDatabaseUrl(schemaOnly, target), `${schemaOnly}&connect_timeout=3&pool_timeout=3`);
  const oneTimeout = `${base}?connect_timeout=2`;
  assert.equal(resolveDatabaseUrl(oneTimeout, target), `${oneTimeout}&pool_timeout=3`);
  const onlyPoolTimeout = `${base}?pool_timeout=4`;
  assert.equal(resolveDatabaseUrl(onlyPoolTimeout, target), `${onlyPoolTimeout}&connect_timeout=3`);
  const withSchema = `${expected}&schema=public`;
  assert.equal(resolveDatabaseUrl(withSchema, target), withSchema);
  const boundedAlternative = expected.replace('connect_timeout=3', 'connect_timeout=5').replace('pool_timeout=3', 'pool_timeout=1');
  assert.equal(resolveDatabaseUrl(boundedAlternative, target), boundedAlternative);

  for (const value of [
    'postgresql://tester:secret@127.0.0.1:5433/mimi_platform_test',
    'postgresql://mimi:secret@db.example.net:5432/mimi_guitar',
    'not-a-database-url',
    '',
    `postgresql://mimi:${encodeURIComponent(fakePassword)}@127.0.0.1:5432/mimi_guitar`,
    expected.replace('connect_timeout=3', 'connect_timeout=60'),
    `${expected}&connect_timeout=2`,
    `${base}?schema=public&schema=public`,
    `${base}?unknown=value`,
  ]) {
    assert.throws(() => resolveDatabaseUrl(value, target), (error) => {
      assertCode(error, 'DATABASE_URL_CONFLICT');
      assert.equal(error.message.includes(fakePassword), false);
      assert.equal(error.message.includes('secret'), false);
      return true;
    });
  }
});

function fakePrismaClient({ database = LOCAL_DATABASE_NAME, rowCount = 19, failAt, prismaCode, disconnectError, connectNeverSettles = false, disconnectNeverSettles = false, transactionNeverSettles = false } = {}) {
  const calls = [];
  const fail = () => { throw Object.assign(new Error(`fake Prisma failure ${fakePassword}`), { code: prismaCode }); };
  const tx = {
    $executeRawUnsafe: async (query) => {
      calls.push(['execute', query]);
      if (failAt === query) fail();
      return 0;
    },
    $queryRawUnsafe: async (query) => {
      calls.push(['query', query]);
      if (failAt === query) fail();
      if (query.startsWith('SELECT 1')) return [{ ok: 1 }];
      if (query.includes('current_database')) return [{ database }];
      return [];
    },
    tab: {
      count: async () => {
        calls.push(['count']);
        if (failAt === 'count') fail();
        return rowCount;
      },
    },
  };
  const client = {
    $connect: async () => {
      calls.push(['connect']);
      if (connectNeverSettles) return new Promise(() => {});
      if (failAt === 'connect') fail();
    },
    $transaction: async (callback, options) => {
      calls.push(['transaction', options]);
      if (transactionNeverSettles) return new Promise(() => {});
      return callback(tx);
    },
    $disconnect: async () => {
      calls.push(['disconnect']);
      if (disconnectNeverSettles) return new Promise(() => {});
      if (disconnectError) throw disconnectError;
    },
  };
  return { client, calls };
}

test('uses the same bounded Prisma URL for read-only identity and non-empty catalog checks', async () => {
  const databaseUrl = buildLocalDatabaseUrl(inspectLocalPostgres(inspectJson()));
  const fake = fakePrismaClient();
  let receivedUrl;
  const result = await probePrismaCatalog({
    databaseUrl,
    createClient: async (url) => {
      receivedUrl = url;
      return fake.client;
    },
  });
  assert.equal(receivedUrl, databaseUrl);
  assert.deepEqual(result, { database: LOCAL_DATABASE_NAME, rowCount: 19 });
  assert.deepEqual(fake.calls.map(([kind, value]) => [kind, value]), [
    ['connect', undefined],
    ['transaction', { maxWait: PRISMA_PROBE_TIMEOUT_MS, timeout: PRISMA_PROBE_TIMEOUT_MS }],
    ['execute', 'SET TRANSACTION READ ONLY'],
    ['query', 'SELECT 1 AS "ok"'],
    ['query', 'SELECT current_database() AS "database"'],
    ['count', undefined],
    ['disconnect', undefined],
  ]);
});

test('disconnects Prisma on failures and keeps network, auth, schema, identity, and empty-catalog states distinct', async () => {
  const databaseUrl = buildLocalDatabaseUrl(inspectLocalPostgres(inspectJson()));
  const cases = [
    [fakePrismaClient({ failAt: 'connect', prismaCode: 'P1001' }), 'DATABASE_UNAVAILABLE'],
    [fakePrismaClient({ failAt: 'connect', prismaCode: 'P1000' }), 'DATABASE_AUTH'],
    [fakePrismaClient({ failAt: 'count', prismaCode: 'P2022' }), 'SCHEMA_MISMATCH'],
    [fakePrismaClient({ database: 'mimi_platform_test' }), 'DATABASE_CONFIG'],
    [fakePrismaClient({ rowCount: 0 }), 'EMPTY_CATALOG'],
  ];
  for (const [fake, code] of cases) {
    await assert.rejects(probePrismaCatalog({ databaseUrl, createClient: () => fake.client }), (error) => {
      assertCode(error, code);
      assert.equal(error.message.includes(fakePassword), false);
      return true;
    });
    assert.deepEqual(fake.calls.at(-1), ['disconnect']);
  }
});

test('bounds Prisma total work and disconnect even when injected promises never settle', async () => {
  const databaseUrl = buildLocalDatabaseUrl(inspectLocalPostgres(inspectJson()));
  const fastTimeouts = { totalMs: 40, connectMs: 20, transactionMs: 20, disconnectMs: 20 };
  for (const fake of [
    fakePrismaClient({ connectNeverSettles: true }),
    fakePrismaClient({ transactionNeverSettles: true }),
    fakePrismaClient({ disconnectNeverSettles: true }),
  ]) {
    await assert.rejects(probePrismaCatalog({
      databaseUrl,
      createClient: () => fake.client,
      timeouts: fastTimeouts,
    }), (error) => {
      assertCode(error, 'DATABASE_PROBE_TIMEOUT');
      return true;
    });
    assert.deepEqual(fake.calls.at(-1), ['disconnect']);
  }
  assert.equal(PRISMA_TOTAL_TIMEOUT_MS > PRISMA_PROBE_TIMEOUT_MS, true);
  assert.ok(PRISMA_DISCONNECT_TIMEOUT_MS > 0);
});

test('requires the expected schema and every migration to have a successful, unrolled-back record', () => {
  assert.equal(REQUIRED_SCHEMA_COLUMN_COUNT, REQUIRED_PRISMA_SCHEMA_COLUMNS.length);
  assert.equal(REQUIRED_SCHEMA_COLUMN_COUNT, 52);
  assert.ok(READ_ONLY_SCHEMA_SQL.includes("('Tab', 'timeSig', 'text', 'YES')"));
  assert.ok(READ_ONLY_SCHEMA_SQL.includes("('User', 'passwordHash', 'text', 'NO')"));
  assert.ok(READ_ONLY_SCHEMA_SQL.includes("('Favorite', 'userId', 'text', 'NO')"));
  assert.deepEqual(parseReadOnlySchemaResult(schemaOutput()), {
    database: LOCAL_DATABASE_NAME,
    tabExists: true,
    migrationsTableExists: true,
    missingColumns: [],
  });
  assert.deepEqual(parseReadOnlyMigrationResult('migrations|4|0\n'), { applied: 4, failed: 0 });
  assert.throws(() => parseReadOnlySchemaResult(schemaOutput([], { database: 'mimi_platform_test' })), (error) => {
    assertCode(error, 'DATABASE_CONFIG');
    return true;
  });
  assert.deepEqual(parseReadOnlySchemaResult(schemaOutput(['Tab.timeSig'])).missingColumns, ['Tab.timeSig']);
  assert.throws(() => parseReadOnlyMigrationResult(`migrations|${REQUIRED_PRISMA_MIGRATIONS.length - 1}|0`), (error) => {
    assertCode(error, 'MIGRATIONS_PENDING');
    return true;
  });
  assert.throws(() => parseReadOnlyMigrationResult('migrations|4|1'), (error) => {
    assertCode(error, 'MIGRATIONS_PENDING');
    return true;
  });
});

test('keeps the read-only schema gate aligned with every generated Prisma scalar field', () => {
  const postgresTypeByPrismaType = {
    String: 'text',
    Int: 'integer',
    DateTime: 'timestamp without time zone',
  };
  const prismaColumns = Prisma.dmmf.datamodel.models.flatMap((model) =>
    model.fields
      .filter((field) => field.kind === 'scalar')
      .map((field) => {
        assert.ok(postgresTypeByPrismaType[field.type], `Add PostgreSQL mapping for Prisma ${field.type}`);
        return [model.name, field.name, postgresTypeByPrismaType[field.type], field.isRequired ? 'NO' : 'YES'].join('|');
      }),
  ).sort();
  const guardedColumns = REQUIRED_PRISMA_SCHEMA_COLUMNS.map((column) => column.join('|')).sort();
  assert.equal(prismaColumns.length, 52);
  assert.deepEqual(guardedColumns, prismaColumns);
});

test('classifies read-only probe network and schema failures without exposing stderr', () => {
  const network = classifyDockerFailure(['exec', LOCAL_POSTGRES_CONTAINER, 'psql'], {
    status: 2,
    stderr: `could not connect to server: ${fakePassword}`,
  });
  const schema = classifyDockerFailure(['exec', LOCAL_POSTGRES_CONTAINER, 'psql'], {
    status: 2,
    stderr: `relation "Tab" does not exist: ${fakePassword}`,
  });
  assertCode(network, 'DATABASE_UNAVAILABLE');
  assertCode(schema, 'SCHEMA_MISMATCH');
  assert.equal(network.message.includes(fakePassword), false);
  assert.equal(schema.message.includes(fakePassword), false);
  assert.equal(classifyDockerFailure(['inspect'], { error: { code: 'ETIMEDOUT' }, status: null }).code, 'DOCKER_TIMEOUT');
  assert.equal(classifyDockerFailure(['exec'], { error: { code: 'ETIMEDOUT' }, status: null }).code, 'DATABASE_UNAVAILABLE');
});

test('runs read-only schema and migration probes before Prisma verifies the app connection and catalog', async () => {
  const dockerCalls = [];
  const prismaCalls = [];
  const result = await checkLocalCatalog({
    existingDatabaseUrl: undefined,
    runDocker: async (args) => {
      dockerCalls.push(args);
      if (args[0] === 'inspect') return inspectJson();
      if (args.at(-1) === READ_ONLY_SCHEMA_SQL) return schemaOutput();
      if (args.at(-1) === READ_ONLY_MIGRATIONS_SQL) return 'migrations|4|0\n';
      throw new Error('unexpected command');
    },
    probePrisma: async (url) => {
      prismaCalls.push(url);
      return { database: LOCAL_DATABASE_NAME, rowCount: 19 };
    },
  });

  assert.equal(dockerCalls.length, 3);
  assert.deepEqual(dockerCalls[0], ['inspect', '--type', 'container', LOCAL_POSTGRES_CONTAINER]);
  const sql = dockerCalls.slice(1).map((args) => args.at(-1));
  assert.deepEqual(sql, [READ_ONLY_SCHEMA_SQL, READ_ONLY_MIGRATIONS_SQL]);
  assert.ok(sql.every((query) => query.startsWith('BEGIN READ ONLY;') && query.endsWith('ROLLBACK;')));
  assert.equal(dockerCalls.some((args) => args.includes(fakePassword)), false);
  assert.deepEqual(prismaCalls, [result.databaseUrl]);
  assert.equal(result.rowCount, 19);
  assert.equal(new URL(result.databaseUrl).hostname, '127.0.0.1');
});

function responseForValidCatalog() {
  return async (args) => {
    if (args[0] === 'inspect') return inspectJson();
    if (args.at(-1) === READ_ONLY_SCHEMA_SQL) return schemaOutput();
    if (args.at(-1) === READ_ONLY_MIGRATIONS_SQL) return 'migrations|4|0\n';
    throw new Error('unexpected command');
  };
}

test('keeps unavailable, pending migrations, missing Prisma columns, and empty catalog distinct', async () => {
  const responseWith = (migrationOutput = 'migrations|4|0\n', missingColumns = []) => async (args) => {
    if (args[0] === 'inspect') return inspectJson();
    if (args.at(-1) === READ_ONLY_SCHEMA_SQL) return schemaOutput(missingColumns);
    if (args.at(-1) === READ_ONLY_MIGRATIONS_SQL) return migrationOutput;
    throw new Error('unexpected command');
  };

  const cases = [
    [async (args) => {
      if (args[0] === 'inspect') return inspectJson();
      throw new LocalCatalogRuntimeError('DATABASE_UNAVAILABLE', 'safe fake failure');
    }, 'DATABASE_UNAVAILABLE'],
    [responseWith('migrations|3|0\n'), 'MIGRATIONS_PENDING'],
    [responseWith('migrations|4|0\n', ['Tab.timeSig']), 'SCHEMA_MISMATCH'],
  ];

  for (const [runDocker, expected] of cases) {
    let checkedPrisma = false;
    await assert.rejects(checkLocalCatalog({
      existingDatabaseUrl: undefined,
      runDocker,
      probePrisma: async () => { checkedPrisma = true; return { database: LOCAL_DATABASE_NAME, rowCount: 19 }; },
    }), (error) => {
      assertCode(error, expected);
      return true;
    });
    assert.equal(checkedPrisma, false);
  }

  await assert.rejects(checkLocalCatalog({
    existingDatabaseUrl: undefined,
    runDocker: responseWith(),
    probePrisma: async () => { throw new LocalCatalogRuntimeError('EMPTY_CATALOG', 'safe empty fake'); },
  }), (error) => {
    assertCode(error, 'EMPTY_CATALOG');
    return true;
  });

  let launches = 0;
  await assert.rejects(checkThenStart({
    check: async () => { throw new LocalCatalogRuntimeError('SCHEMA_MISMATCH', 'safe fake failure'); },
    launch: async () => { launches += 1; },
  }));
  assert.equal(launches, 0);
});

test('rejects an inherited remote or test URL before querying PostgreSQL', async () => {
  let calls = 0;
  await assert.rejects(checkLocalCatalog({
    existingDatabaseUrl: 'postgresql://tester:secret@remote.example/mimi_platform_test',
    runDocker: async (args) => {
      calls += 1;
      if (args[0] === 'inspect') return inspectJson();
      throw new Error('database query should not run');
    },
    probePrisma: async () => { throw new Error('database probe should not run'); },
  }), (error) => {
    assertCode(error, 'DATABASE_URL_CONFLICT');
    assert.equal(error.message.includes('secret'), false);
    return true;
  });
  assert.equal(calls, 1);
});

test('checks schema before the same-URL Prisma probe and refuses launch when app credentials fail', async () => {
  let probedUrl;
  const expectedUrl = buildLocalDatabaseUrl(inspectLocalPostgres(inspectJson()));
  const check = () => checkLocalCatalog({
    existingDatabaseUrl: undefined,
    runDocker: responseForValidCatalog(),
    probePrisma: async (databaseUrl) => {
      probedUrl = databaseUrl;
      throw Object.assign(new Error(`secret ${fakePassword}`), { code: 'P1001' });
    },
  });
  await assert.rejects(check(), (error) => {
    assertCode(error, 'DATABASE_UNAVAILABLE');
    assert.equal(error.message.includes(fakePassword), false);
    return true;
  });
  assert.equal(probedUrl, expectedUrl);

  let launches = 0;
  await assert.rejects(checkThenStart({
    check: async () => { throw new LocalCatalogRuntimeError('MIGRATIONS_PENDING', 'safe fake failure'); },
    launch: async () => { launches += 1; },
  }));
  assert.equal(launches, 0);
});

test('starts only once after the injected database check succeeds', async () => {
  const calls = [];
  const result = await checkThenStart({
    check: async () => ({ databaseUrl: 'postgresql://fake-local-target' }),
    launch: async (url) => calls.push(url),
  });
  assert.deepEqual(calls, ['postgresql://fake-local-target']);
  assert.equal(result.databaseUrl, calls[0]);
});
