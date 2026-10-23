// Read-only repeatable navigation probe. Run against an isolated local preview.
// node docs/evidence/fast-navigation-2026-10-19/measure-http.mjs http://127.0.0.1:4338
import { performance } from 'node:perf_hooks';

const base = new URL(process.argv[2] || 'http://127.0.0.1:4338');
if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) {
  throw new Error('This evidence probe is limited to a local preview.');
}

const rows = [];
async function observe(route, phase, headers) {
  const start = performance.now();
  const response = await fetch(new URL(route, base), { headers });
  const body = await response.text();
  const row = {
    route, phase, ms: Number((performance.now() - start).toFixed(2)),
    status: response.status, bytes: Buffer.byteLength(body),
    cacheControl: response.headers.get('cache-control'), vary: response.headers.get('vary'),
    demo: /演示|"source":"demo"/.test(body),
    unavailable: /暂时不可用|暂不可用|"source":"unavailable"/.test(body),
  };
  rows.push(row);
  return row;
}

const routes = ['/practice', '/library', '/motion', '/studio', '/', '/tabs', '/ukulele', '/article'];
for (let run = 1; run <= 2; run++) {
  for (const route of routes) await observe(route, `route-run-${run}`);
}
for (const route of [
  '/searchResults?searchValue=%E6%99%B4%E5%A4%A9&type=all',
  '/api/search?q=%E6%99%B4%E5%A4%A9', '/tabs/1sdc49P3eKm',
  '/article/nonexistent-navigation-probe', '/tabs/nonexistent-navigation-probe',
  '/ukulele/nonexistent-navigation-probe', '/tabs?no=9999', '/article?page=9999',
]) await observe(route, 'extra');

// A non-session sentinel cookie verifies the conservative any-cookie no-store path.
await observe('/tabs', 'cookie-cache-exclusion', { Cookie: 'mimi_navigation_probe=1' });
await observe('/api/health', 'liveness');
await observe('/api/readiness', 'readiness');
console.log(JSON.stringify({ capturedAt: new Date().toISOString(), base: base.origin, rows }, null, 2));
