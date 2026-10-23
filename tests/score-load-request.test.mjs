import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { fetchScoreBytes, ScoreRequestError } from '../src/lib/scoreLoadRequest.mjs';
import { scoreLoadFailurePresentation } from '../src/lib/scoreLoadGuard.mjs';

async function localServer(t, handle) {
  const server = createServer(handle);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }));
  return `http://127.0.0.1:${server.address().port}/score.ibe`;
}

test('a real missing-file HTTP response does not offer the same broken download', async (t) => {
  const url = await localServer(t, (_request, response) => { response.writeHead(404); response.end('missing'); });
  await assert.rejects(fetchScoreBytes(url), (error) => {
    assert.ok(error instanceof ScoreRequestError);
    assert.equal(error.status, 404);
    const recovery = scoreLoadFailurePresentation(url, 'fetch', error);
    assert.match(recovery.message, /没有找到.*乐谱文件/);
    assert.equal(recovery.canDownload, false);
    assert.equal(recovery.canRetry, true);
    return true;
  });
});

test('HTTP access, server, HTML and empty responses have distinct file failure reasons', async (t) => {
  let selected;
  const url = await localServer(t, (_request, response) => {
    response.writeHead(selected.status, selected.headers ?? {});
    response.end(selected.body);
  });
  for (const entry of [
    { status: 410, body: '', kind: 'missing' },
    { status: 403, body: 'denied', kind: 'forbidden' },
    { status: 503, body: 'unavailable', kind: 'server' },
    { status: 200, headers: { 'Content-Type': 'text/html' }, body: '<p>login</p>', kind: 'html' },
    { status: 200, body: '<!DOCTYPE html><html>error page</html>', kind: 'html' },
    { status: 200, body: '', kind: 'empty' },
  ]) {
    selected = entry;
    await assert.rejects(fetchScoreBytes(url), (error) => {
      assert.equal(error.kind, entry.kind);
      assert.equal(scoreLoadFailurePresentation(url, 'fetch', error).canDownload, false);
      return true;
    });
  }
});

test('explicit retry revalidates an earlier failure and returns the recovered file bytes', async (t) => {
  const bytes = Buffer.from([77, 73, 77, 73, 1, 3, 5, 7]);
  let count = 0;
  const url = await localServer(t, (_request, response) => {
    if (++count === 1) { response.writeHead(404); response.end(); }
    else { response.writeHead(200, { 'Content-Type': 'application/octet-stream' }); response.end(bytes); }
  });
  await assert.rejects(fetchScoreBytes(url), { status: 404 });
  assert.deepEqual(await fetchScoreBytes(url, { retry: true }), new Uint8Array(bytes));
  const policies = [];
  const fetchImpl = async (_url, options) => { policies.push(options.cache); return new Response(bytes); };
  await fetchScoreBytes(url, { fetchImpl });
  await fetchScoreBytes(url, { fetchImpl, retry: true });
  assert.deepEqual(policies, ['default', 'reload']);
});

test('a cancelled delayed response remains cancellation rather than a visible loading error', async () => {
  const controller = new AbortController();
  let finish;
  const pending = fetchScoreBytes('/score.ibe', {
    signal: controller.signal,
    fetchImpl: () => new Promise((resolve) => { finish = resolve; }),
  });
  controller.abort();
  finish(new Response(new Uint8Array([1, 2, 3])));
  await assert.rejects(pending, (error) => error.name === 'AbortError');
});

test('transport failures retain a separate network or timeout reason', async () => {
  await assert.rejects(fetchScoreBytes('/score.ibe', { fetchImpl: async () => { throw new TypeError('fetch failed'); } }), { kind: 'network' });
  await assert.rejects(fetchScoreBytes('/score.ibe', { fetchImpl: async () => { throw new DOMException('deadline', 'TimeoutError'); } }), { kind: 'timeout' });
});
