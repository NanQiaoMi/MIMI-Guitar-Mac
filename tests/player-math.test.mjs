import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computePlaybackSpeed, clampTick, clampTargetBpm, formatTime, formatMilliseconds, resolvePlaybackTempo, resolvePracticeTempo } from '../src/lib/playbackSpeed.mjs';

test('computePlaybackSpeed: 仅倍率生效（target/base），不改谱面 tempo', () => {
  assert.equal(computePlaybackSpeed(160, 80), 2);
  assert.equal(computePlaybackSpeed(80, 80), 1);
  assert.equal(computePlaybackSpeed(40, 80), 0.5);
  assert.equal(computePlaybackSpeed(120, 0), 1);
  assert.equal(computePlaybackSpeed(120, -10), 1);
  assert.equal(computePlaybackSpeed(NaN, 80), 1);
});

test('clampTick: 限制在 [0, endTick] 并按 round 取整', () => {
  assert.equal(clampTick(-5, 1000), 0);
  assert.equal(clampTick(500, 1000), 500);
  assert.equal(clampTick(1500, 1000), 1000);
  assert.equal(clampTick(1000.9, 1000), 1000);
  assert.equal(clampTick(500.6, 1000), 501);
  assert.equal(clampTick(1000, 0), 0); // endTick=0 时上限为 0
  assert.equal(clampTick(NaN, 1000), 0);
  assert.equal(clampTick(Infinity, 1000), 0);
});

test('formatTime: mm:ss（分钟补零）', () => {
  assert.equal(formatTime(0), '00:00');
  assert.equal(formatTime(65), '01:05');
  assert.equal(formatTime(600), '10:00');
  assert.equal(formatTime(-3), '00:00');
  assert.equal(formatTime(NaN), '00:00');
  assert.equal(formatTime(3.9), '00:03');
});

test('resolvePlaybackTempo: 曲库 BPM 覆盖谱面原生速度，播放倍率以原生速度为基准', () => {
  assert.deepEqual(resolvePlaybackTempo(80, 69), {
    sourceTempo: 80,
    targetTempo: 69,
    playbackSpeed: 69 / 80,
  });
});

test('resolvePlaybackTempo: 缺失或非法曲库 BPM 时保留谱面原生速度', () => {
  assert.deepEqual(resolvePlaybackTempo(80, 0), {
    sourceTempo: 80,
    targetTempo: 80,
    playbackSpeed: 1,
  });
  assert.deepEqual(resolvePlaybackTempo(undefined, '69'), {
    sourceTempo: 69,
    targetTempo: 69,
    playbackSpeed: 1,
  });
  assert.deepEqual(resolvePlaybackTempo(0, 0), {
    sourceTempo: 80,
    targetTempo: 80,
    playbackSpeed: 1,
  });
});

test('resolvePracticeTempo: 400 BPM 原谱保持 1×，目标控件与实际速度分开保存', () => {
  const native = resolvePracticeTempo(400, 0);
  assert.equal(native.sourceTempo, 400);
  assert.equal(native.targetTempo, 300);
  assert.equal(native.playbackSpeed, 1);
  assert.equal(native.actualTempo, 400);
  assert.equal(native.targetMin, 50);
  assert.equal(native.targetMax, 300);
  assert.equal(native.targetClamped, true);

  const lowRequest = resolvePracticeTempo(400, 20);
  assert.equal(lowRequest.targetTempo, 50);
  assert.equal(lowRequest.playbackSpeed, 0.125);
  assert.equal(lowRequest.actualTempo, 50);
  assert.equal(lowRequest.targetClamped, true);

  const highNative = resolvePracticeTempo(1000, 20);
  assert.equal(highNative.targetTempo, 125);
  assert.equal(highNative.playbackSpeed, 0.125);
  assert.equal(highNative.actualTempo, 125);
});

test('clampTargetBpm: 断点目标不超过普通速度字段契约范围', () => {
  assert.equal(clampTargetBpm(400), 300);
  assert.equal(clampTargetBpm(10), 20);
  assert.equal(clampTargetBpm(Number.NaN), 80);
});

test('formatMilliseconds: AlphaTab 毫秒时间转 mm:ss', () => {
  assert.equal(formatMilliseconds(0), '00:00');
  assert.equal(formatMilliseconds(65_000), '01:05');
  assert.equal(formatMilliseconds(228_000), '03:48');
  assert.equal(formatMilliseconds(-3), '00:00');
  assert.equal(formatMilliseconds(NaN), '00:00');
});
