import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summarizePractice } from '../src/lib/practice/practiceSummary.ts';

function session(id, state, slices, overrides = {}) {
  return { id, scoreId: 'score-1', scoreRevision: 'r1', state, startedAt: 1, updatedAt: 100, timezone: 'UTC', slices, note: '', ...overrides };
}
function slice(id, startedAt, durationMs) { return { id, epoch: 'e1', sequence: 1, startedAt, durationMs }; }

test('splits a slice across UTC+8 local midnight into two calendar days', () => {
  const startedAt = Date.UTC(2024, 5, 1, 15, 30); // June 1, 23:30 in Shanghai
  const data = { sessions: [session('s1', 'completed', [slice('a', startedAt, 2 * 60 * 60 * 1000)])], scores: [{ id: 'score-1', title: '测试曲', artist: '艺人' }] };
  const summary = summarizePractice(data, { now: Date.UTC(2024, 5, 2, 4), timeZone: 'Asia/Shanghai' });
  assert.equal(summary.today.date, '2024-06-02');
  assert.equal(summary.today.durationMs, 90 * 60 * 1000);
  assert.deepEqual(summary.last7Days.find((day) => day.date === '2024-06-01'), { date: '2024-06-01', durationMs: 30 * 60 * 1000 });
  assert.equal(summary.timeZone, 'Asia/Shanghai');
});

test('splits at midnight correctly across a DST date change without losing elapsed time', () => {
  const startedAt = Date.UTC(2024, 2, 10, 4, 30); // March 9, 23:30 in New York (EST)
  const data = { sessions: [session('dst', 'paused', [slice('cross', startedAt, 2 * 60 * 60 * 1000)])], scores: [] };
  const summary = summarizePractice(data, { now: Date.UTC(2024, 2, 10, 12), timeZone: 'America/New_York' });
  assert.equal(summary.today.date, '2024-03-10');
  assert.equal(summary.today.durationMs, 90 * 60 * 1000);
  assert.equal(summary.last7Days.find((day) => day.date === '2024-03-09').durationMs, 30 * 60 * 1000);
  assert.equal(summary.last7Days.reduce((sum, day) => sum + day.durationMs, 0), 2 * 60 * 60 * 1000);
});

test('deduplicates slice IDs only within the same session and reports recent status, title, note, and duration', () => {
  const start = Date.UTC(2024, 0, 2, 10);
  const data = {
    sessions: [
      session('s1', 'completed', [slice('repeat', start, 60_000), slice('repeat', start + 60_000, 60_000)], { note: 'A-B 慢练', updatedAt: 300 }),
      session('s2', 'mystery', [slice('repeat', start, 30_000)], { updatedAt: 200 }),
    ],
    scores: [{ id: 'score-1', title: '晴天', artist: '周杰伦' }],
  };
  const summary = summarizePractice(data, { now: start + 86_400_000, timeZone: 'UTC' });
  assert.equal(summary.today.durationMs, 0);
  assert.equal(summary.recent[0].title, '晴天');
  assert.equal(summary.recent[0].state, '已完成');
  assert.equal(summary.recent[0].note, 'A-B 慢练');
  assert.equal(summary.recent[0].durationMs, 60_000);
  assert.equal(summary.recent[1].durationMs, 30_000);
  assert.equal(summary.recent[1].state, '未知状态');
});

test('recent records carry their score and current queue recovery state without changing duration', () => {
  const start = Date.UTC(2024, 0, 2, 10);
  const data = {
    sessions: [
      session('active-session', 'paused', [slice('a', start, 60_000)], { scoreId: 'active', updatedAt: 400 }),
      session('archived-session', 'completed', [slice('b', start, 90_000)], { scoreId: 'archived', updatedAt: 300 }),
      session('removed-session', 'completed', [slice('c', start, 120_000)], { scoreId: 'removed', updatedAt: 200 }),
      session('missing-session', 'completed', [slice('d', start, 150_000)], { scoreId: 'missing', updatedAt: 100 }),
    ],
    scores: ['active', 'archived', 'removed'].map((id) => ({ id, title: id, artist: '' })),
    practiceItems: [
      { scoreId: 'active', status: 'practicing' },
      { scoreId: 'archived', status: 'archived' },
    ],
  };
  const summary = summarizePractice(data, { now: start + 86_400_000, timeZone: 'UTC' });

  assert.deepEqual(summary.recent.map(({ scoreId, scoreStatus }) => [scoreId, scoreStatus]), [
    ['active', 'active'],
    ['archived', 'archived'],
    ['removed', 'not-in-queue'],
    ['missing', 'missing'],
  ]);
  assert.deepEqual(summary.recent.map(({ durationMs }) => durationMs), [60_000, 90_000, 120_000, 150_000]);
});

test('empty data is a valid zero summary', () => {
  const summary = summarizePractice({ sessions: [], scores: [] }, { now: Date.UTC(2024, 0, 1), timeZone: 'UTC' });
  assert.equal(summary.today.durationMs, 0);
  assert.ok(summary.last7Days.every((day) => day.durationMs === 0));
  assert.deepEqual(summary.recent, []);
  assert.deepEqual(summary.warnings, []);
});

test('malformed slices and missing score references are reported without aborting the review', () => {
  const data = { sessions: [session('broken', 'active', [slice('', 0, -1)], { scoreId: 'missing' })], scores: [] };
  const summary = summarizePractice(data, { now: Date.UTC(2024, 0, 1), timeZone: 'UTC' });
  assert.equal(summary.today.durationMs, 0);
  assert.equal(summary.recent[0].title, '曲谱已不可用');
  assert.equal(summary.recent[0].state, '进行中');
  assert.ok(summary.warnings.some((warning) => warning.includes('无效时段')));
  assert.ok(summary.warnings.some((warning) => warning.includes('曲谱缺失')));
});

test('thousands of repeated midnight slices reuse one formatter and cached day boundaries', () => {
  const count = 3000;
  const startedAt = Date.UTC(2024, 5, 1, 15, 59, 58); // June 1, 23:59:58 in Shanghai
  const slices = Array.from({ length: count }, (_, index) => slice(`slice-${index}`, startedAt, 5000));
  const data = { sessions: [session('large', 'active', slices)], scores: [] };
  let diagnostics;
  const summary = summarizePractice(data, {
    now: Date.UTC(2024, 5, 2, 4),
    timeZone: 'Asia/Shanghai',
    onDiagnostics: (value) => { diagnostics = value; },
  });
  assert.equal(summary.today.durationMs, count * 3000);
  assert.equal(summary.last7Days.find((day) => day.date === '2024-06-01').durationMs, count * 2000);
  assert.equal(summary.recent[0].durationMs, count * 5000);
  assert.equal(diagnostics.formatterCount, 1);
  assert.equal(diagnostics.boundarySearches, 2);
  assert.ok(diagnostics.boundaryCacheHits >= count * 2 - 2);
  assert.ok(diagnostics.dateKeyCalls <= count * 4 + 100);
});
