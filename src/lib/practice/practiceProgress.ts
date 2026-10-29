import type { PlayerResume, PracticeSession, SpeedPlan } from '../personal/types.ts';

export const MIN_ALPHA_TAB_PLAYBACK_RATIO = 0.125;
export const MAX_ALPHA_TAB_PLAYBACK_RATIO = 8;

export function isValidPlaybackRatio(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) &&
    value >= MIN_ALPHA_TAB_PLAYBACK_RATIO && value <= MAX_ALPHA_TAB_PLAYBACK_RATIO;
}

export interface PracticeLoopRange {
  startTick: number;
  endTick: number;
}

/** Validate an expanded playback range against the exact current score end. */
export function isValidPracticeLoopRange(
  range: PracticeLoopRange | null | undefined,
  scoreEndTick: number,
): range is PracticeLoopRange {
  return Number.isSafeInteger(scoreEndTick) && scoreEndTick > 0 && !!range &&
    Number.isSafeInteger(range.startTick) && Number.isSafeInteger(range.endTick) &&
    range.startTick >= 0 && range.endTick > range.startTick && range.endTick <= scoreEndTick;
}

/**
 * Normalize an A/current-position selection into [startTick, endTick).
 * The selected B beat is included through its known exclusive beat end. For a
 * reverse selection, the beat end captured when A was set supplies the other
 * boundary. Missing or corrupt timing metadata is never guessed or clamped.
 */
export function normalizePracticeLoopSelection(input: {
  pointATick: number | null;
  pointABeatEndTick: number | null;
  currentTick: number;
  currentBeatEndTick: number;
  scoreEndTick: number;
}): PracticeLoopRange {
  const { pointATick, pointABeatEndTick, currentTick, currentBeatEndTick, scoreEndTick } = input;
  if (!Number.isSafeInteger(scoreEndTick) || scoreEndTick <= 0) {
    throw new RangeError('当前谱面曲末无效，无法设置 A-B 区间。');
  }
  if (!Number.isSafeInteger(pointATick) || pointATick! < 0 || pointATick! >= scoreEndTick) {
    throw new RangeError('A 点已超出当前谱面范围，请重新设置 A。');
  }
  if (!Number.isSafeInteger(currentTick) || currentTick < 0 || currentTick > scoreEndTick) {
    throw new RangeError('当前位置已超出当前谱面范围，请等待播放器同步后重试。');
  }
  const isExactScoreEndSelection = currentTick === scoreEndTick && currentBeatEndTick === scoreEndTick;
  if (!Number.isSafeInteger(currentBeatEndTick) ||
    (!isExactScoreEndSelection && currentBeatEndTick <= currentTick) ||
    currentBeatEndTick > scoreEndTick) {
    throw new RangeError('无法确认当前拍末，请等待拍点信息更新后重试。');
  }

  let startTick: number;
  let endTick: number;
  if (currentTick >= pointATick!) {
    startTick = pointATick!;
    endTick = currentBeatEndTick;
  } else {
    if (!Number.isSafeInteger(pointABeatEndTick) || pointABeatEndTick! <= pointATick! || pointABeatEndTick! > scoreEndTick) {
      throw new RangeError('倒选时无法确认 A 点当时的拍末，请重新设置 A。');
    }
    startTick = currentTick;
    endTick = pointABeatEndTick!;
  }

  const range = { startTick, endTick };
  if (!isValidPracticeLoopRange(range, scoreEndTick)) {
    throw new RangeError('A-B 区间为空或超出当前谱面范围，请重新选择。');
  }
  return range;
}

/** Return a plain snapshot so Svelte's nested $state proxies never reach IndexedDB. */
export function cloneSpeedPlan(plan: SpeedPlan): SpeedPlan {
  const snapshot = { ...plan };
  if (plan.loopRange) snapshot.loopRange = { startTick: plan.loopRange.startTick, endTick: plan.loopRange.endTick };
  else delete snapshot.loopRange;
  return snapshot;
}

/** Serialize resume snapshots in order so an older in-flight checkpoint cannot
 * overwrite a newer pause/end boundary after the player stops. */
export function createResumeWriteQueue<T>(write: (snapshot: T) => Promise<void>): (snapshot: T) => Promise<void> {
  let tail: Promise<void> = Promise.resolve();
  return (snapshot: T) => {
    const current = tail.then(() => write(snapshot));
    tail = current.then(() => undefined, () => undefined);
    return current;
  };
}

export interface PracticeSessionWriteContext {
  scoreId: string;
  scoreRevision: string;
  sessionId: string;
}

export class StalePracticeSessionWriteError extends Error {
  constructor() {
    super('曲谱或练习会话已切换，旧写入已取消');
    this.name = 'StalePracticeSessionWriteError';
  }
}

export class CompletedPracticeSessionError extends Error {
  constructor() {
    super('练习会话已结束，不能从其他标签页恢复；请重新开始练习');
    this.name = 'CompletedPracticeSessionError';
  }
}

export function samePracticeSessionWriteContext(
  expected: PracticeSessionWriteContext,
  current: PracticeSessionWriteContext | null,
): boolean {
  return !!current && expected.scoreId === current.scoreId &&
    expected.scoreRevision === current.scoreRevision && expected.sessionId === current.sessionId;
}

export function assertPracticeSessionWriteContext(
  expected: PracticeSessionWriteContext,
  current: PracticeSessionWriteContext | null,
): void {
  if (!samePracticeSessionWriteContext(expected, current)) throw new StalePracticeSessionWriteError();
}

/** Keep a panel aligned with the database while preserving its local active state.
 * A removed or completed session is terminal; stale local copies cannot be reused. */
export function reconcilePracticeSession(
  local: PracticeSession | null,
  sessions: readonly PracticeSession[],
  scoreId: string,
  scoreRevision: string,
): PracticeSession | null {
  if (local?.scoreId === scoreId && local.scoreRevision === scoreRevision) {
    const persisted = sessions.find((item) => item.id === local.id);
    if (persisted && persisted.scoreId === scoreId && persisted.scoreRevision === scoreRevision && persisted.state !== 'completed') {
      return local;
    }
  }

  const active = [...sessions].reverse().find((item) => item.scoreId === scoreId && item.scoreRevision === scoreRevision &&
    ['active', 'paused', 'interrupted'].includes(item.state));
  if (!active) return null;
  return active.state === 'active' ? { ...active, state: 'interrupted' } : active;
}

export interface PreparedPracticeResumeSettings {
  visibleTrackIndexes: number[];
  trackMix: NonNullable<PlayerResume['trackMix']>;
  display?: PlayerResume['display'];
}

/** Only apply indices from the exact score revision and within its track list. */
export function preparePracticeResumeSettings(
  resume: PlayerResume,
  currentRevision: string,
  trackCount: number,
): PreparedPracticeResumeSettings {
  if (resume.scoreRevision !== currentRevision) throw new Error('练习断点与当前谱面版本不一致，请重新打开曲谱');
  if (!Number.isSafeInteger(trackCount) || trackCount < 0) throw new RangeError('当前谱面音轨数量无效');
  const validIndex = (index: number) => Number.isSafeInteger(index) && index >= 0 && index < trackCount;
  const visibleTrackIndexes = [...new Set((resume.trackIndexes ?? []).filter(validIndex))].sort((a, b) => a - b);
  const trackMix = (resume.trackMix ?? []).filter((mix) => validIndex(mix.index)).map((mix) => {
    if (mix.instrumentOverride !== undefined && typeof mix.instrumentOverride !== 'boolean') {
      throw new Error('练习断点的音色覆盖标记无效，请重新保存后续练');
    }
    // Preserve the optional flag while keeping older records without it readable.
    return { ...mix };
  });
  const display = resume.display;
  if (display && (!Number.isFinite(display.fontScale) || display.fontScale < 0.6 || display.fontScale > 1.6 ||
    !['name', 'diagram'].includes(display.chordMode) || !['mixed', 'tab'].includes(display.scoreDisplayMode) ||
    typeof display.numberTab !== 'boolean' || typeof display.showFretboard !== 'boolean')) {
    throw new Error('练习断点的谱面显示设置无效，请重新保存后续练');
  }
  return {
    visibleTrackIndexes: visibleTrackIndexes.length ? visibleTrackIndexes : Array.from({ length: trackCount }, (_unused, index) => index),
    trackMix,
    display: display ? { ...display } : undefined,
  };
}

export function assertPracticeAssetConsistency(input: {
  source: 'catalog' | 'private' | 'project';
  storedSource: 'catalog' | 'private' | 'project';
  scoreRevision: string;
  storedRevision: string;
  scoreAssetId?: string;
  storedAssetId?: string;
  actualAssetId?: string;
  actualAssetHash?: string;
}): void {
  if (input.source !== input.storedSource) throw new Error('练习谱来源与本地引用不一致，请重新打开曲谱');
  if (input.source === 'catalog') return;
  const assetId = input.scoreAssetId;
  if (!assetId || input.storedAssetId !== assetId || input.scoreRevision !== assetId || input.storedRevision !== assetId) {
    throw new Error('个人谱版本与可播放附件不一致，请重新打开或重新保存个人谱');
  }
  if (input.actualAssetId !== assetId || input.actualAssetHash !== assetId) {
    throw new Error('个人谱可播放附件缺失或摘要校验失败，请先修复个人谱资料');
  }
}

export interface LoopLapProgress {
  generation: number;
  interruptionRevision: number;
  rangeKey: string;
  previousTick: number | null;
  observedFromA: boolean;
}

export function createLoopLapProgress(
  generation: number,
  interruptionRevision: number,
  range: { startTick: number; endTick: number } | null,
): LoopLapProgress {
  return {
    generation,
    interruptionRevision,
    rangeKey: range ? `${range.startTick}:${range.endTick}` : 'none',
    previousTick: null,
    observedFromA: false,
  };
}

/** Track one uninterrupted pass from A; interruptions and range changes discard the partial lap. */
export function observeLoopLapProgress(
  previous: LoopLapProgress,
  input: {
    tick: number;
    isSeek: boolean;
    generation: number;
    interruptionRevision: number;
    range: { startTick: number; endTick: number } | null;
    playing: boolean;
    focused: boolean;
    visible: boolean;
  },
): LoopLapProgress {
  const next = createLoopLapProgress(input.generation, input.interruptionRevision, input.range);
  const identityMatches = previous.generation === next.generation &&
    previous.interruptionRevision === next.interruptionRevision && previous.rangeKey === next.rangeKey;
  if (!input.range || !input.playing || !input.focused || !input.visible) return next;

  const current = identityMatches ? previous : next;
  if (input.isSeek) {
    return {
      ...current,
      previousTick: null,
      observedFromA: startsCompleteLoopLap(null, input.tick, input.range, true),
    };
  }
  return {
    ...current,
    previousTick: input.tick,
    observedFromA: current.observedFromA || startsCompleteLoopLap(current.previousTick, input.tick, input.range, false),
  };
}

export function sameResumeContent(left: PlayerResume | null | undefined, right: PlayerResume): boolean {
  if (!left) return false;
  return left.scoreId === right.scoreId && left.scoreRevision === right.scoreRevision &&
    left.tick === right.tick && left.timeMs === right.timeMs && left.speed === right.speed &&
    left.playbackRatio === right.playbackRatio &&
    left.capo === right.capo && left.transpose === right.transpose &&
    (left.useSourceCapo === true) === (right.useSourceCapo === true) &&
    JSON.stringify(left.loop ?? null) === JSON.stringify(right.loop ?? null) &&
    left.trackIndexes.length === right.trackIndexes.length &&
    left.trackIndexes.every((track, index) => track === right.trackIndexes[index]) &&
    JSON.stringify(left.trackMix ?? null) === JSON.stringify(right.trackMix ?? null) &&
    JSON.stringify(left.display ?? null) === JSON.stringify(right.display ?? null) &&
    left.metronome === right.metronome && left.countIn === right.countIn;
}

export function createPracticeSession(scoreId: string, scoreRevision: string, now = Date.now()): PracticeSession {
  return {
    id: crypto.randomUUID(),
    scoreId,
    scoreRevision,
    state: 'active',
    startedAt: now,
    updatedAt: now,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
    slices: [],
    note: '',
  };
}

/** Keep timestamp-merged session writes monotonic even if the wall clock moves backward. */
export function normalizePracticeSessionUpdate(
  latest: PracticeSession,
  proposed: PracticeSession,
  now = Date.now(),
): PracticeSession {
  const normalized = {
    ...proposed,
    updatedAt: Math.max(now, latest.updatedAt + 1, proposed.updatedAt),
  };
  if (proposed.endedAt !== undefined) {
    normalized.endedAt = Math.max(proposed.endedAt, proposed.startedAt);
  }
  return normalized;
}

/** Apply a session update against the record read in the transaction. Completed
 * records are immutable, so delayed cross-tab writes cannot reopen them. */
export function updatePracticeSessionIfOpen(
  sessions: PracticeSession[],
  sessionId: string,
  update: (latest: PracticeSession) => PracticeSession,
  now = Date.now(),
): PracticeSession {
  const index = sessions.findIndex((item) => item.id === sessionId);
  if (index < 0) throw new Error('练习记录已被其他页面移除');
  const latest = sessions[index];
  if (latest.state === 'completed') throw new CompletedPracticeSessionError();
  const normalized = normalizePracticeSessionUpdate(latest, update(latest), now);
  sessions[index] = normalized;
  return normalized;
}

/** Resume checkpoint cadence uses a monotonic clock, independent of wall-clock
 * corrections. A null baseline means the first checkpoint is due immediately. */
export function isResumeCheckpointDue(now: number, lastWrite: number | null, intervalMs = 5000): boolean {
  if (lastWrite === null || !Number.isFinite(lastWrite) || !Number.isFinite(now)) return true;
  return now < lastWrite || now - lastWrite >= intervalMs;
}

export function makePracticeSlice(session: PracticeSession, sequence: number, startedAt: number, durationMs: number, epoch: string): PracticeSession['slices'][number] {
  if (!Number.isInteger(sequence) || sequence < 1 || !Number.isFinite(durationMs) || durationMs <= 0) {
    throw new RangeError('Practice slice sequence and duration must be positive');
  }
  return { id: `${session.id}:${epoch}:${sequence}`, sequence, epoch, startedAt, durationMs };
}

export function createSpeedPlan(revision: string, startBpm: number, targetBpm: number, stepBpm: number, lapsPerLevel: number, nativeAnchorBpm?: number, loopRange?: { startTick: number; endTick: number }): SpeedPlan {
  if (![startBpm, targetBpm, stepBpm].every(Number.isFinite) || startBpm < 20 || targetBpm > 300 || targetBpm < startBpm || stepBpm <= 0 || !Number.isInteger(lapsPerLevel) || lapsPerLevel < 1) {
    throw new RangeError('Speed plan requires BPM values from 20 to 300, target >= start, and positive whole laps');
  }
  if (nativeAnchorBpm !== undefined && (!Number.isFinite(nativeAnchorBpm) || nativeAnchorBpm < 1 || nativeAnchorBpm > 1000)) {
    throw new RangeError('Native anchor BPM must be between 1 and 1000');
  }
  if (loopRange && (!Number.isInteger(loopRange.startTick) || !Number.isInteger(loopRange.endTick) || loopRange.startTick < 0 || loopRange.endTick <= loopRange.startTick)) {
    throw new RangeError('Speed plan loop range must have non-negative start and a later end');
  }
  if (nativeAnchorBpm !== undefined &&
    (!isValidPlaybackRatio(startBpm / nativeAnchorBpm) || !isValidPlaybackRatio(targetBpm / nativeAnchorBpm))) {
    throw new RangeError('Speed plan BPM range exceeds AlphaTab playback limits (0.125–8×)');
  }
  return { revision, nativeAnchorBpm, loopRange, startBpm, targetBpm, stepBpm, lapsPerLevel, currentBpm: startBpm, completedLaps: 0 };
}

export function hasSpeedPlanAnchor(plan: SpeedPlan | null | undefined): plan is SpeedPlan & { nativeAnchorBpm: number } {
  return !!plan && Number.isFinite(plan.nativeAnchorBpm) && (plan.nativeAnchorBpm ?? 0) >= 1 && (plan.nativeAnchorBpm ?? 0) <= 1000;
}

export function speedPlanMatchesLoop(plan: SpeedPlan | null | undefined, range: { startTick: number; endTick: number } | null | undefined): boolean {
  return !!plan && !!range && !!plan.loopRange && plan.loopRange.startTick === range.startTick && plan.loopRange.endTick === range.endTick;
}

/** A persisted plan is applied only when both its loop and requested playback ratio are active. */
export function isSpeedPlanApplied(
  plan: SpeedPlan | null | undefined,
  range: { startTick: number; endTick: number } | null | undefined,
  actualPlaybackRatio: number,
): boolean {
  if (!plan || !hasSpeedPlanAnchor(plan) || !speedPlanMatchesLoop(plan, range) || !isValidPlaybackRatio(actualPlaybackRatio)) return false;
  const plannedRatio = plan.currentBpm / plan.nativeAnchorBpm;
  return isValidPlaybackRatio(plannedRatio) && Math.abs(actualPlaybackRatio - plannedRatio) <= 0.0001;
}

/** A complete lap is only the non-seek engine event crossing the loop end boundary. */
export function isCompletedLoopLap(previousTick: number | null, currentTick: number, range: { startTick: number; endTick: number }, isSeek: boolean): boolean {
  if (isSeek || previousTick === null || range.endTick <= range.startTick) return false;
  return previousTick < range.endTick && currentTick >= range.endTick;
}

export function canCountLoopCompletion(input: {
  playing: boolean;
  focused: boolean;
  visible: boolean;
  observedFromA: boolean;
  event: { startTick: number; endTick: number } | null;
  range: { startTick: number; endTick: number } | null;
}): boolean {
  const { event, range } = input;
  return input.playing && input.focused && input.visible && input.observedFromA && !!event && !!range &&
    event.startTick === range.startTick && event.endTick === range.endTick;
}

export function startsCompleteLoopLap(
  previousTick: number | null,
  currentTick: number,
  range: { startTick: number; endTick: number },
  isSeek: boolean,
): boolean {
  if (range.endTick <= range.startTick || currentTick < range.startTick || currentTick >= range.endTick) return false;
  // AlphaTab may quantize a seek at the loop start to the next unfolded tick.
  // Keep this tolerance seek-only and bounded to one tick so seeking into the
  // middle of the loop can never arm a partial lap.
  if (isSeek) return Math.abs(currentTick - range.startTick) <= 1;
  if (previousTick === null) return currentTick === range.startTick;
  return previousTick <= range.startTick;
}

export function canPersistResume(state: {
  dirty: boolean;
  joined: boolean;
  dataReady: boolean;
  playerReady: boolean;
  hasPosition: boolean;
  restoring: boolean;
  explicitSnapshot?: boolean;
}): boolean {
  return (state.dirty || state.explicitSnapshot === true) && state.joined && state.dataReady && state.playerReady && state.hasPosition && !state.restoring;
}

export function advanceSpeedPlan(plan: SpeedPlan, lapId: string, seenLapIds: Set<string>): { plan: SpeedPlan; changed: boolean } {
  if (!lapId || seenLapIds.has(lapId)) return { plan, changed: false };
  if (plan.currentBpm >= plan.targetBpm) {
    return plan.completedLaps === 0 ? { plan, changed: false } : { plan: { ...plan, completedLaps: 0 }, changed: true };
  }
  seenLapIds.add(lapId);
  const completedLaps = plan.completedLaps + 1;
  if (completedLaps < plan.lapsPerLevel) {
    return { plan: { ...plan, completedLaps }, changed: true };
  }
  return {
    plan: {
      ...plan,
      currentBpm: Math.min(plan.targetBpm, plan.currentBpm + plan.stepBpm),
      completedLaps: 0,
    },
    changed: true,
  };
}

export function speedMultiplierAtAnchor(targetAnchorBpm: number, nativeAnchorBpm: number): number {
  if (!Number.isFinite(targetAnchorBpm) || !Number.isFinite(nativeAnchorBpm) || targetAnchorBpm <= 0 || nativeAnchorBpm <= 0) {
    throw new RangeError('Anchor BPM values must be positive');
  }
  const ratio = targetAnchorBpm / nativeAnchorBpm;
  if (!isValidPlaybackRatio(ratio)) throw new RangeError('Anchor BPM ratio exceeds AlphaTab playback limits (0.125–8×)');
  return ratio;
}
