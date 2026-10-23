export function publicSubmissionDisabledResponse() {
  return new Response(JSON.stringify({
    ok: false,
    code: 'public_submission_disabled',
    error: '公开投稿和审核功能首期暂未开放。请使用“我的谱”在本设备本地导入。',
  }), {
    status: 503,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}
