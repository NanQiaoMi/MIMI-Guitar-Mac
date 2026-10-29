import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isApiFailureResponse,
  isDatabaseError,
  readApiErrorMessage,
} from '../src/lib/errorBoundary.ts';

const fallback = '旧版云端收藏未能取消，请稍后重试。';

test('reads legacy string and current structured API errors', () => {
  assert.equal(readApiErrorMessage({ error: '旧接口错误' }, fallback), '旧接口错误');
  assert.equal(readApiErrorMessage({ ok: false, error: { code: 'DATABASE_ERROR', message: '数据库暂不可用', recoverable: true } }, fallback), '数据库暂不可用');
});

test('uses the supplied fallback for null, malformed, and empty error messages', () => {
  assert.equal(readApiErrorMessage(null, fallback), fallback);
  assert.equal(readApiErrorMessage([], fallback), fallback);
  assert.equal(readApiErrorMessage({ error: { message: 503 } }, fallback), fallback);
  assert.equal(readApiErrorMessage({ error: { message: '  ' } }, fallback), fallback);
});

test('recognizes explicit API failures without rejecting legacy success bodies', () => {
  assert.equal(isApiFailureResponse({ ok: false, error: 'failed' }), true);
  assert.equal(isApiFailureResponse({ ok: true, data: {} }), false);
  assert.equal(isApiFailureResponse({ favorites: [] }), false);
  assert.equal(isApiFailureResponse(null), false);
});

test('classifies Prisma names, Prisma codes, and network connection codes', () => {
  const prismaError = new Error('database request failed');
  prismaError.name = 'PrismaClientKnownRequestError';
  assert.equal(isDatabaseError(prismaError), true);
  assert.equal(isDatabaseError({ code: 'P2002' }), true);
  assert.equal(isDatabaseError({ code: 'ECONNREFUSED' }), true);
  assert.equal(isDatabaseError({ code: 'ETIMEDOUT' }), true);
});

test('does not classify ordinary messages by broad English substrings', () => {
  assert.equal(isDatabaseError(null), false);
  assert.equal(isDatabaseError([]), false);
  assert.equal(isDatabaseError({ code: 503 }), false);
  assert.equal(isDatabaseError(new Error('relation constraint connect ECONNREFUSED PrismaClient')), false);
  assert.equal(isDatabaseError('PrismaClient relation constraint connect ECONNREFUSED'), false);
  assert.equal(isDatabaseError({ message: 'constraint failed', code: 'EACCES' }), false);
});
