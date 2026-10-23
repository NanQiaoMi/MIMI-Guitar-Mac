// 播放器纯函数工具（供 ScorePlayer 组件与 node --test 单测共用，纯 JS 以便 .mjs 直接导入）
/** 将 tick 约束到 [0, endTick] 并取整 */
export function clampTick(tick, endTick) {
  if (!Number.isFinite(tick) || tick < 0) return 0;
  let v = Math.round(tick);
  if (Number.isFinite(endTick) && v > endTick) v = Math.round(endTick);
  return v;
}

/** 变速语义：仅用 playbackSpeed = 目标BPM / 基准BPM，不再修改 tempo 自动化 */
export function computePlaybackSpeed(targetBpm, baseTempo) {
  if (!baseTempo || baseTempo <= 0 || !Number.isFinite(targetBpm)) return 1;
  return targetBpm / baseTempo;
}

/**
 * 统一播放器的速度来源：谱面内置速度是 AlphaTab 的原生基准，
 * 页面曲库的 BPM（如有）才是首次打开时应播放的目标速度。
 */
export function resolvePlaybackTempo(sourceTempo, requestedBpm, fallbackTempo = 80) {
  const toPositiveFinite = (value) => {
    const n = Number(value);
    return Number.isFinite(n) && n > 0 ? n : 0;
  };

  const fallback = toPositiveFinite(fallbackTempo) || 80;
  const requested = toPositiveFinite(requestedBpm);
  const source = toPositiveFinite(sourceTempo) || requested || fallback;
  const target = requested || source;

  return {
    sourceTempo: source,
    targetTempo: target,
    playbackSpeed: computePlaybackSpeed(target, source),
  };
}

export const MIN_TARGET_BPM = 20;
export const MAX_TARGET_BPM = 300;

/** Keep the user-facing target in its supported range, independently of native tempo. */
export function clampTargetBpm(value, fallback = 80) {
  const target = Number(value);
  const safeFallback = Number(fallback);
  const normalized = Number.isFinite(target) && target > 0
    ? target
    : Number.isFinite(safeFallback) && safeFallback > 0 ? safeFallback : 80;
  return Math.min(MAX_TARGET_BPM, Math.max(MIN_TARGET_BPM, normalized));
}

/**
 * Resolve a practice target without falsifying AlphaTab's actual playback ratio.
 * With no explicit catalog BPM, preserve the native rate even when its tempo is
 * outside the target slider's 20–300 BPM range. Explicit requests are limited to
 * both the target range and AlphaTab's [0.125, 8] playback ratio.
 */
export function resolvePracticeTempo(sourceTempo, requestedBpm, fallbackTempo = 80) {
  const resolved = resolvePlaybackTempo(sourceTempo, requestedBpm, fallbackTempo);
  const source = resolved.sourceTempo;
  const requested = Number(requestedBpm);
  const hasRequested = Number.isFinite(requested) && requested > 0;
  const targetMin = Math.max(MIN_TARGET_BPM, source * 0.125);
  const targetMax = Math.min(MAX_TARGET_BPM, source * 8);

  if (!hasRequested) {
    return {
      sourceTempo: source,
      targetTempo: clampTargetBpm(source),
      playbackSpeed: 1,
      actualTempo: source,
      targetMin: targetMin <= targetMax ? targetMin : MIN_TARGET_BPM,
      targetMax: targetMin <= targetMax ? targetMax : MAX_TARGET_BPM,
      targetClamped: source < MIN_TARGET_BPM || source > MAX_TARGET_BPM,
      targetUnavailable: false,
      hasRequested: false,
    };
  }

  if (targetMin > targetMax) {
    return {
      sourceTempo: source,
      targetTempo: clampTargetBpm(source),
      playbackSpeed: 1,
      actualTempo: source,
      targetMin: MIN_TARGET_BPM,
      targetMax: MAX_TARGET_BPM,
      targetClamped: true,
      targetUnavailable: true,
      hasRequested: true,
    };
  }

  const targetTempo = Math.min(targetMax, Math.max(targetMin, resolved.targetTempo));
  const playbackSpeed = computePlaybackSpeed(targetTempo, source);
  return {
    sourceTempo: source,
    targetTempo,
    playbackSpeed,
    actualTempo: source * playbackSpeed,
    targetMin,
    targetMax,
    targetClamped: Math.abs(targetTempo - resolved.targetTempo) > 0.0001,
    targetUnavailable: false,
    hasRequested: true,
  };
}

/** 秒 → mm:ss */
export function formatTime(seconds) {
  const s = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
}

/** AlphaTab 的 playerPositionChanged 时间值为毫秒；显示前统一转换为 mm:ss。 */
export function formatMilliseconds(milliseconds) {
  const ms = Number.isFinite(milliseconds) && milliseconds > 0 ? milliseconds : 0;
  return formatTime(ms / 1000);
}
