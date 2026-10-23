/**
 * A process-local guard for public catalog reads only. It is deliberately
 * separate from authentication, writes, and readiness checks.
 */
export class CatalogReadUnavailableError extends Error {
  readonly cause: unknown;

  constructor(cause?: unknown) {
    super('The public catalog is temporarily unavailable.');
    this.name = 'CatalogReadUnavailableError';
    this.cause = cause;
  }
}

export interface CatalogReadGateOptions {
  probe: () => Promise<unknown>;
  now?: () => number;
  cooldownMs?: number;
  isConnectivityFailure?: (error: unknown) => boolean;
}

export interface CatalogReadGate {
  run<T>(read: () => Promise<T>): Promise<T>;
}

export type CatalogReadGateLoader = () => Promise<CatalogReadGate>;

/** Share lazy gate creation as well as the gate's own probe flight. */
export function createCatalogReadRunner(loadGate: CatalogReadGateLoader): <T>(read: () => Promise<T>) => Promise<T> {
  let gateFlight: Promise<CatalogReadGate> | null = null;

  return async function run<T>(read: () => Promise<T>): Promise<T> {
    if (!gateFlight) {
      const flight = Promise.resolve().then(loadGate);
      gateFlight = flight;
      void flight.catch(() => {
        if (gateFlight === flight) gateFlight = null;
      });
    }

    const gate = await gateFlight;
    return gate.run(read);
  };
}

const PRISMA_CONNECTION_CODES = new Set(['P1001', 'P1002', 'P1017']);
const SOCKET_CONNECTION_CODES = new Set([
  'ECONNREFUSED',
  'ECONNRESET',
  'ETIMEDOUT',
  'EHOSTUNREACH',
  'ENETUNREACH',
  'EPIPE',
  'ENOTFOUND',
  'EAI_AGAIN',
]);

/** Only known transport/database reachability errors open the read gate. */
export function isCatalogConnectivityFailure(error: unknown): boolean {
  const pending: unknown[] = [error];
  const seen = new Set<object>();

  while (pending.length > 0) {
    const current = pending.pop();
    if (!current || typeof current !== 'object') continue;
    if (seen.has(current)) continue;
    seen.add(current);

    const record = current as { code?: unknown; errorCode?: unknown; cause?: unknown; name?: unknown; message?: unknown };
    const codes = [record.code, record.errorCode];
    if (codes.some((code) => typeof code === 'string' && (PRISMA_CONNECTION_CODES.has(code) || SOCKET_CONNECTION_CODES.has(code)))) {
      return true;
    }
    // Prisma 6 can omit errorCode when its initial connection pool times out.
    // Match only its initialization error and known connection messages; schema,
    // credentials, general query timeouts and coded P2024 errors remain outside.
    if (!codes.some((code) => typeof code === 'string' && code.length > 0)
      && record.name === 'PrismaClientInitializationError'
      && typeof record.message === 'string'
      && /can't reach database server at|timed out fetching a new connection from the connection pool\.|server has closed the connection\./i.test(record.message)) {
      return true;
    }
    if (record.cause !== undefined) pending.push(record.cause);
  }

  return false;
}

/**
 * Build an injectable gate for deterministic tests. A failed probe is shared
 * by all waiters; after a known connection failure, calls fail quickly until
 * the cooldown expires and one shared probe is allowed to try recovery.
 */
export function createCatalogReadGate(options: CatalogReadGateOptions): CatalogReadGate {
  const now = options.now ?? Date.now;
  const cooldownMs = Math.max(0, options.cooldownMs ?? 10_000);
  const isConnectivityFailure = options.isConnectivityFailure ?? isCatalogConnectivityFailure;

  let healthy = false;
  let openUntil: number | null = null;
  let lastConnectionFailure: unknown;
  let probeFlight: Promise<void> | null = null;

  const unavailable = () => new CatalogReadUnavailableError(lastConnectionFailure);

  function markUnavailable(error: unknown): CatalogReadUnavailableError {
    healthy = false;
    openUntil = now() + cooldownMs;
    lastConnectionFailure = error;
    return unavailable();
  }

  async function ensureAvailable(): Promise<void> {
    if (openUntil !== null && now() < openUntil) throw unavailable();
    if (healthy) return;
    if (probeFlight) return probeFlight;

    const flight = (async () => {
      try {
        await options.probe();
        healthy = true;
        openUntil = null;
        lastConnectionFailure = undefined;
      } catch (error) {
        if (isConnectivityFailure(error)) throw markUnavailable(error);
        // Unknown failures remain visible to callers and do not open the gate.
        healthy = false;
        throw error;
      }
    })();

    probeFlight = flight;
    try {
      await flight;
    } finally {
      if (probeFlight === flight) probeFlight = null;
    }
  }

  return {
    async run<T>(read: () => Promise<T>): Promise<T> {
      await ensureAvailable();
      try {
        return await read();
      } catch (error) {
        if (isConnectivityFailure(error)) throw markUnavailable(error);
        throw error;
      }
    },
  };
}

const runProcessCatalogRead = createCatalogReadRunner(async () => {
    const { db } = await import('./db');
    return createCatalogReadGate({
      probe: () => db.$queryRawUnsafe('SELECT 1'),
      cooldownMs: 10_000,
    });
});

/** Run one uncached public catalog read through the shared process gate. */
export function withCatalogRead<T>(read: () => Promise<T>): Promise<T> {
  return runProcessCatalogRead(read);
}
