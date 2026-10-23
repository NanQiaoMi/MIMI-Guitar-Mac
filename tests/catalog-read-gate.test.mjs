import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CatalogReadUnavailableError,
  createCatalogReadGate,
  createCatalogReadRunner,
  isCatalogConnectivityFailure,
} from '../src/lib/catalogReadGate.ts';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('lazy runner shares first gate initialization and the cold SELECT probe', async () => {
  let loadCount = 0;
  let probeCount = 0;
  let readCount = 0;
  const runner = createCatalogReadRunner(async () => {
    loadCount += 1;
    await Promise.resolve();
    return createCatalogReadGate({
      probe: async () => { probeCount += 1; },
    });
  });

  const values = await Promise.all(Array.from({ length: 12 }, (_, index) =>
    runner(async () => { readCount += 1; return index; })
  ));

  assert.equal(loadCount, 1);
  assert.equal(probeCount, 1);
  assert.equal(readCount, 12);
  assert.deepEqual(values, Array.from({ length: 12 }, (_, index) => index));
});

test('cold and half-open probes are single-flight; known disconnects back off then recover', async () => {
  let now = 100;
  let probeCount = 0;
  let readCount = 0;
  const coldProbe = deferred();
  const recoveryProbe = deferred();
  const gate = createCatalogReadGate({
    now: () => now,
    cooldownMs: 10_000,
    probe: () => {
      probeCount += 1;
      if (probeCount === 1) return coldProbe.promise;
      if (probeCount === 2) return recoveryProbe.promise;
      return Promise.resolve();
    },
  });

  const coldReads = [1, 2, 3].map((index) => gate.run(async () => { readCount += 1; return index; }));
  await Promise.resolve();
  assert.equal(probeCount, 1);
  coldProbe.reject(Object.assign(new Error('database server unreachable'), { code: 'P1001' }));
  const coldResults = await Promise.allSettled(coldReads);
  assert.equal(coldResults.every((result) => result.status === 'rejected' && result.reason instanceof CatalogReadUnavailableError), true);
  assert.equal(readCount, 0);

  await assert.rejects(gate.run(async () => { readCount += 1; }), CatalogReadUnavailableError);
  assert.equal(probeCount, 1, 'calls inside the open interval must not issue more probes');

  now = 10_100;
  const recoveringReads = [gate.run(async () => { readCount += 1; return 'a'; }), gate.run(async () => { readCount += 1; return 'b'; })];
  await Promise.resolve();
  assert.equal(probeCount, 2);
  recoveryProbe.resolve('ok');
  assert.deepEqual(await Promise.all(recoveringReads), ['a', 'b']);
  assert.equal(readCount, 2);
  assert.equal(probeCount, 2);
});

test('unknown probe errors and non-connection read errors do not open the gate', async () => {
  const unknownProbeError = Object.assign(new Error('schema mismatch'), { code: 'P2022' });
  let probeCount = 0;
  const gate = createCatalogReadGate({
    probe: async () => {
      probeCount += 1;
      if (probeCount === 1) throw unknownProbeError;
    },
  });

  await assert.rejects(gate.run(async () => 'unused'), (error) => error === unknownProbeError);
  assert.equal(await gate.run(async () => 'recovered'), 'recovered');
  assert.equal(probeCount, 2, 'a non-connection probe error remains retryable');

  const queryError = Object.assign(new Error('invalid query'), { code: 'P2024' });
  await assert.rejects(gate.run(async () => { throw queryError; }), (error) => error === queryError);
  assert.equal(await gate.run(async () => 'healthy'), 'healthy');
  assert.equal(probeCount, 2, 'a healthy gate does not reprobe for non-connection query errors');
});

test('a connection failure in a healthy read opens cooldown, then each read still returns fresh data', async () => {
  let now = 0;
  let probeCount = 0;
  let readCount = 0;
  const gate = createCatalogReadGate({
    now: () => now,
    cooldownMs: 10_000,
    probe: async () => { probeCount += 1; },
  });

  assert.deepEqual(await Promise.all([
    gate.run(async () => ++readCount),
    gate.run(async () => ++readCount),
  ]), [1, 2], 'healthy reads return their own current values without result caching');
  assert.equal(probeCount, 1);

  const disconnect = Object.assign(new Error('socket closed'), { code: 'ECONNRESET' });
  await assert.rejects(gate.run(async () => { readCount += 1; throw disconnect; }), CatalogReadUnavailableError);
  const readsAtOpen = readCount;
  await assert.rejects(gate.run(async () => ++readCount), CatalogReadUnavailableError);
  assert.equal(readCount, readsAtOpen, 'an open gate does not start a database read');
  assert.equal(probeCount, 1);

  now = 10_000;
  assert.deepEqual(await Promise.all([
    gate.run(async () => ++readCount),
    gate.run(async () => ++readCount),
  ]), [4, 5]);
  assert.equal(probeCount, 2, 'one successful half-open probe is shared');
});

test('a failed lazy gate loader can be retried by the next caller', async () => {
  const loadError = new Error('temporary module loader failure');
  let loadCount = 0;
  let probeCount = 0;
  const runner = createCatalogReadRunner(async () => {
    loadCount += 1;
    if (loadCount === 1) throw loadError;
    return createCatalogReadGate({
      probe: async () => { probeCount += 1; },
    });
  });

  await assert.rejects(runner(async () => 'unused'), (error) => error === loadError);
  assert.equal(await runner(async () => 'loaded'), 'loaded');
  assert.equal(loadCount, 2);
  assert.equal(probeCount, 1);
});

test('connection-shaped nested causes open the gate while unrelated Prisma codes do not', () => {
  assert.equal(isCatalogConnectivityFailure({ cause: { code: 'ECONNRESET' } }), true);
  assert.equal(isCatalogConnectivityFailure({ code: 'P1017' }), true);
  assert.equal(isCatalogConnectivityFailure({ code: 'P2024' }), false);
  assert.equal(isCatalogConnectivityFailure(new Error('unknown database error')), false);
});

test('Prisma initialization pool timeouts without a code back off, while other failures remain retryable', async () => {
  const message = 'Timed out fetching a new connection from the connection pool. More info: connection limit reached.';
  const initializationError = Object.assign(new Error(message), { name: 'PrismaClientInitializationError' });
  assert.equal(isCatalogConnectivityFailure(initializationError), true);
  assert.equal(isCatalogConnectivityFailure(Object.assign(new Error(message), { code: 'P2024' })), false);
  assert.equal(isCatalogConnectivityFailure(Object.assign(new Error(message), { name: 'PrismaClientInitializationError', code: 'P2024' })), false);
  assert.equal(isCatalogConnectivityFailure(Object.assign(new Error('Authentication failed'), { name: 'PrismaClientInitializationError' })), false);
  assert.equal(isCatalogConnectivityFailure(Object.assign(new Error('Timed out during query execution'), { name: 'PrismaClientInitializationError' })), false);

  let probes = 0;
  const gate = createCatalogReadGate({ now: () => 100, probe: async () => { probes++; throw initializationError; } });
  await assert.rejects(gate.run(async () => assert.fail('unavailable reader must not run')), CatalogReadUnavailableError);
  await assert.rejects(gate.run(async () => assert.fail('cooldown reader must not run')), CatalogReadUnavailableError);
  assert.equal(probes, 1);
});
