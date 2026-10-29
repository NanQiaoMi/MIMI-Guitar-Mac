import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertRenderableScore,
  hasRenderableScore,
  runWithRollbackTransaction,
  safeScoreDownloadHref,
  scoreLoadFailurePresentation,
} from '../src/lib/scoreLoadGuard.mjs';

test('accepts a score with at least one renderable track, staff, and bar', () => {
  const jsonScore = {
    tracks: [{ staves: [{ bars: [{}] }] }],
  };
  const alphaTabScore = {
    tracks: [{ staves: [{ bars: [{ voices: [] }] }] }],
  };

  assert.equal(hasRenderableScore(jsonScore), true);
  assert.equal(assertRenderableScore(jsonScore), jsonScore);
  assert.equal(hasRenderableScore(alphaTabScore), true);
  assert.equal(assertRenderableScore(alphaTabScore), alphaTabScore);
});

test('rejects empty or structurally incomplete scores before rendering', () => {
  for (const score of [
    null,
    {},
    { tracks: [] },
    { tracks: [{ staves: [] }] },
    { tracks: [{ staves: [{ bars: [] }] }] },
    { tracks: [{ staves: [{ bars: [null] }] }] },
    { tracks: [{ staves: [{ bars: null }] }] },
  ]) {
    assert.equal(hasRenderableScore(score), false);
    assert.throws(() => assertRenderableScore(score), /谱表或小节/);
  }
});

test('missing score URL shows an unavailable-file state without retry or download', () => {
  const state = scoreLoadFailurePresentation('', 'fetch');

  assert.equal(state.kind, 'missing');
  assert.equal(state.canRetry, false);
  assert.equal(state.canDownload, false);
  assert.match(state.message, /没有可用的乐谱文件/);
  assert.equal(safeScoreDownloadHref(''), '');
});

test('failed transpose keeps the old UI selection and invokes old-state render rollback', async () => {
  let displayedTranspose = 0;
  let attemptedTranspose = null;
  let restoredTranspose = null;
  const failure = new Error('AlphaTab async layout error');

  const outcome = await runWithRollbackTransaction({
    previousValue: displayedTranspose,
    nextValue: 1,
    commit(value) { displayedTranspose = value; },
    async apply(value) {
      attemptedTranspose = value;
      throw failure;
    },
    async rollback(value) {
      restoredTranspose = value;
    },
  });

  assert.equal(outcome.ok, false);
  assert.equal(outcome.error, failure);
  assert.equal(outcome.rollbackError, null);
  assert.equal(attemptedTranspose, 1);
  assert.equal(restoredTranspose, 0);
  assert.equal(displayedTranspose, 0);
});

test('source download link allows same-origin files only', () => {
  assert.equal(safeScoreDownloadHref('/storage/scores/demo.gp5'), '/storage/scores/demo.gp5');
  assert.equal(safeScoreDownloadHref('https://mimi.example/storage/demo.gp5', 'https://mimi.example'), 'https://mimi.example/storage/demo.gp5');
  assert.equal(safeScoreDownloadHref('https://other.example/demo.gp5', 'https://mimi.example'), '');
  assert.equal(safeScoreDownloadHref('//other.example/demo.gp5', 'https://mimi.example'), '');
});

test('decode errors and structurally empty scores have distinct recovery guidance', () => {
  const decode = scoreLoadFailurePresentation('/score.ibe', 'decode');
  const structure = scoreLoadFailurePresentation('/score.ibe', 'convert');
  assert.match(decode.message, /解码失败/);
  assert.match(structure.message, /没有找到可显示的谱轨或小节/);
  assert.equal(decode.canDownload, true);
  assert.equal(structure.canDownload, true);
});

test('download paths reject normalized cross-origin and non-web URLs', () => {
  const origin = 'https://mimi.example';
  assert.equal(safeScoreDownloadHref('/\\\\evil.example/file.ibe', origin), '');
  assert.equal(safeScoreDownloadHref('javascript:alert(1)', origin), '');
  assert.equal(safeScoreDownloadHref('/storage/scores/demo.ibe', origin), 'https://mimi.example/storage/scores/demo.ibe');
});
