import type { APIRoute } from 'astro';

/** Process liveness only; this route never queries PostgreSQL or catalog resources. */
export const GET: APIRoute = () => new Response(JSON.stringify({ status: 'alive' }), {
  status: 200,
  headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
});
