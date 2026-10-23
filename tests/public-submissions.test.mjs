import assert from 'node:assert/strict';
import test from 'node:test';
import { POST as submitUpload } from '../src/pages/api/upload.ts';
import { POST as reviewUpload } from '../src/pages/api/upload/[id]/review.ts';

const ioForbiddenContext = new Proxy({}, {
  get(_target, property) { throw new Error(`route accessed request context ${String(property)}`); },
});

test('public upload and self-review return 503 without reading request context', async () => {
  for (const handler of [submitUpload, reviewUpload]) {
    const response = await handler(ioForbiddenContext);
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), {
      ok: false,
      code: 'public_submission_disabled',
      error: '公开投稿和审核功能首期暂未开放。请使用“我的谱”在本设备本地导入。',
    });
  }
});
