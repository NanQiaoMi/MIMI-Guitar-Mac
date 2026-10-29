import assert from 'node:assert/strict';
import test from 'node:test';
import { CatalogSearchClient } from '../src/lib/catalogSearch.ts';

const response = (payload, status = 200) => new Response(JSON.stringify(payload), { status });

test('palette search preserves demo provenance and distinguishes unavailable from empty', async () => {
  let next = response({ ok: true, source: 'demo', tabs: [{ id: 'demo' }] });
  const client = new CatalogSearchClient(async () => next);
  assert.deepEqual(await client.search('吉他', 'all'), { source: 'demo', tabs: [{ id: 'demo' }] });
  next = response({ ok: true, source: 'catalog', tabs: [] });
  assert.deepEqual(await client.search('空结果', 'guitar'), { source: 'catalog', tabs: [] });
  next = response({ ok: false, source: 'unavailable', error: 'catalog_unavailable' }, 503);
  const failed = await client.search('无法搜索', 'all');
  assert.equal(failed.source, 'unavailable');
  assert.match(failed.error, /暂不可用/);
});

test('a newer query aborts and suppresses an older response even when transport ignores abort', async () => {
  const requests = [];
  const client = new CatalogSearchClient((url, options) => new Promise((resolve) => requests.push({ url, options, resolve })));
  const old = client.search('first', 'guitar');
  const latest = client.search('second', 'ukulele');
  assert.equal(requests[0].options.signal.aborted, true);
  assert.match(requests[1].url, /q=second&category=ukulele/);
  requests[1].resolve(response({ ok: true, source: 'catalog', tabs: [{ id: 'new' }] }));
  assert.deepEqual(await latest, { source: 'catalog', tabs: [{ id: 'new' }] });
  requests[0].resolve(response({ ok: true, source: 'catalog', tabs: [{ id: 'old' }] }));
  assert.equal(await old, null);
});

test('closing a palette cancels its pending response and connection failures stay visible', async () => {
  let resolve;
  const pendingClient = new CatalogSearchClient(() => new Promise((done) => { resolve = done; }));
  const pending = pendingClient.search('unfinished', 'all');
  pendingClient.cancel();
  resolve(response({ ok: true, source: 'catalog', tabs: [{ id: 'stale' }] }));
  assert.equal(await pending, null);
  const failedClient = new CatalogSearchClient(async () => { throw new Error('network failed'); });
  const failed = await failedClient.search('query', 'all');
  assert.equal(failed.source, 'unavailable');
  assert.match(failed.error, /网络/);
});

test('default transport calls global fetch with the correct receiver', async () => {
  const originalFetch = globalThis.fetch;
  let requestUrl = '';
  globalThis.fetch = function (input) {
    assert.equal(this, globalThis);
    requestUrl = String(input);
    return Promise.resolve(response({ ok: true, source: 'catalog', tabs: [] }));
  };
  try {
    const client = new CatalogSearchClient();
    assert.deepEqual(await client.search('晴天', 'all'), { source: 'catalog', tabs: [] });
    assert.match(requestUrl, /q=%E6%99%B4%E5%A4%A9/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('malformed UTF-16 in a query is encoded instead of being reported as a connection failure', async () => {
  let requestUrl = '';
  const client = new CatalogSearchClient(async (url) => {
    requestUrl = url;
    return response({ ok: true, source: 'catalog', tabs: [] });
  });
  assert.deepEqual(await client.search('\uD800', 'guitar'), { source: 'catalog', tabs: [] });
  assert.match(requestUrl, /q=%EF%BF%BD/);
});
