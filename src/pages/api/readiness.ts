import type { APIRoute } from 'astro';
import { join } from 'node:path';
import { db } from '../../lib/db';
import { evaluateCatalogReadiness } from '../../lib/server/readiness.ts';

/** Catalog readiness is separate from liveness and samples at most 20 local assets per type. */
export const GET: APIRoute = async () => {
  const result = await evaluateCatalogReadiness({
    database: db,
    storageRoot: join(process.cwd(), 'public', 'storage'),
    publicRoot: join(process.cwd(), 'public'),
    migrationsRoot: join(process.cwd(), 'prisma', 'migrations'),
  });
  return new Response(JSON.stringify(result), {
    status: result.status === 'ready' ? 200 : 503,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
};
