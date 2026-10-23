import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CAPO_OPTIONS,
  capoDelta,
  capoLabel,
  clampTranspose,
  totalTransposition,
  transposeKeyName,
} from '../src/lib/pitch.mjs';

test('CAPO_OPTIONS: 与参考站一致（降半调调弦/不夹/1~6品）', () => {
  assert.deepEqual(CAPO_OPTIONS.map((o) => o.value), [-1, 0, 1, 2, 3, 4, 5, 6]);
  assert.equal(CAPO_OPTIONS[0].label, '降半调调弦');
  assert.equal(CAPO_OPTIONS[1].label, '不夹');
  assert.equal(CAPO_OPTIONS[7].label, '6品');
  assert.equal(capoLabel(3), '3品');
  assert.equal(capoLabel(-1), '降半调调弦');
  assert.equal(capoLabel(99), '不夹');
});

test('capoDelta: 相对原始 Capo 的半音偏移', () => {
  assert.equal(capoDelta(0, 0), 0);
  assert.equal(capoDelta(3, 0), 3);
  assert.equal(capoDelta(-1, 0), -1); // 降半调调弦
  assert.equal(capoDelta(0, 2), -2); // 原谱 capo2，选不夹 = 回到原调
  assert.equal(capoDelta(3, 2), 1);
  assert.equal(capoDelta(0, undefined), 0);
});

test('totalTransposition: 变调夹 + 转调 半音相加', () => {
  assert.equal(totalTransposition(0, 0, 0), 0);
  assert.equal(totalTransposition(3, 0, 0), 3);
  assert.equal(totalTransposition(3, 0, 2), 5);
  assert.equal(totalTransposition(0, 0, -2), -2);
  assert.equal(totalTransposition(-1, 0, 4), 3); // 降半调 + 转调+4
  assert.equal(totalTransposition(0, 2, 3), 1); // 原 capo2，不夹 + 转调3
});

test('clampTranspose: 约束在 [-12, 12] 并取整', () => {
  assert.equal(clampTranspose(0), 0);
  assert.equal(clampTranspose(12), 12);
  assert.equal(clampTranspose(13), 12);
  assert.equal(clampTranspose(-13), -12);
  assert.equal(clampTranspose(2.6), 3);
  assert.equal(clampTranspose(NaN), 0);
  assert.equal(clampTranspose(Infinity), 0);
});

test('transposeKeyName: 转调后调名计算', () => {
  assert.equal(transposeKeyName('G', 0), 'G');
  assert.equal(transposeKeyName('G', 2), 'A');
  assert.equal(transposeKeyName('C', 2), 'D');
  assert.equal(transposeKeyName('C', -2), 'A#');
  assert.equal(transposeKeyName('G', 7), 'D');
  assert.equal(transposeKeyName('E', -1), 'D#');
  assert.equal(transposeKeyName('Bb', 1), 'B');
  assert.equal(transposeKeyName('', 2), null);
  assert.equal(transposeKeyName(null, 2), null);
});
