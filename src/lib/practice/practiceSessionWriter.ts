import type { PersonalData, PracticeSession } from '../personal/types.ts';
import {
  assertPracticeSessionWriteContext,
  CompletedPracticeSessionError,
  makePracticeSlice,
  samePracticeSessionWriteContext,
  StalePracticeSessionWriteError,
  updatePracticeSessionIfOpen,
  type PracticeSessionWriteContext,
} from './practiceProgress.ts';

export interface PendingPracticeSlice {
  slice: PracticeSession['slices'][number];
  context: PracticeSessionWriteContext;
  generation: number;
  startedPerf: number;
  boundaryPerf: number;
  boundaryWall: number;
  closesTimer: boolean;
}

export interface PracticeSessionWriterOptions {
  mutatePersonalData: (mutator: (draft: PersonalData) => void) => Promise<PersonalData>;
  getCurrentContext: () => PracticeSessionWriteContext | null;
  getCurrentGeneration: () => number;
  getSession: () => PracticeSession | null;
  onSessionSaved?: (session: PracticeSession, context: PracticeSessionWriteContext, generation: number) => void;
  onSliceSaved?: (context: PracticeSessionWriteContext, generation: number) => void;
  onTimingFailure?: (error: unknown, context: PracticeSessionWriteContext, generation: number) => void;
  nowWall?: () => number;
  nowMonotonic?: () => number;
  createEpoch?: () => string;
}

export type FinishPracticeResult = 'completed' | 'stale' | 'pending-slice' | 'resume-failed';

export class PracticeNoteConflictError extends Error {
  constructor() {
    super('另一页面已修改本次练习备注，未覆盖新内容。');
    this.name = 'PracticeNoteConflictError';
  }
}

/** Compare inside the storage mutation, after reading the transaction's latest record. */
export function assertPracticeNoteUnchanged(actualNote: string, expectedNote: string): void {
  if (actualNote !== expectedNote) throw new PracticeNoteConflictError();
}

export interface FinishPracticeOptions {
  note: string;
  /** Baseline captured when editing began; absent only for legacy callers. */
  expectedNote?: string;
  saveResume: () => Promise<boolean>;
  onReadyToCommit?: () => void;
  onCommitted: () => void;
}

export interface PracticeSessionWriter {
  persist(
    update: (latest: PracticeSession) => PracticeSession,
    context?: PracticeSessionWriteContext | null,
    generation?: number,
  ): Promise<void>;
  /** Persist against the writer's current session/generation, avoiding unrelated player generations. */
  persistCurrent(update: (latest: PracticeSession) => PracticeSession): Promise<void>;
  startNewSession(epoch?: string): void;
  setSequence(sequence: number): void;
  resetForScore(): void;
  clearSessionTiming(context: PracticeSessionWriteContext, generation?: number): void;
  startTiming(context?: PracticeSessionWriteContext | null, generation?: number): void;
  getTimingState(): { context: PracticeSessionWriteContext; generation: number } | null;
  isTiming(): boolean;
  getPendingSlice(): PendingPracticeSlice | null;
  checkpoint(input: { playing: boolean; focused: boolean; visible: boolean }): Promise<void>;
  closeSlice(context?: PracticeSessionWriteContext | null, generation?: number): Promise<void>;
  flushPending(context?: PracticeSessionWriteContext | null, generation?: number): Promise<void>;
  finish(
    context: PracticeSessionWriteContext,
    generation: number,
    options: FinishPracticeOptions,
  ): Promise<FinishPracticeResult>;
}

/**
 * Owns durable practice-session writes and the timer slice lifecycle. Playback
 * and Svelte state stay in the caller; clocks and storage are injectable so
 * checkpoint, close and finish ordering can be tested without a browser.
 */
export function createPracticeSessionWriter(options: PracticeSessionWriterOptions): PracticeSessionWriter {
  const nowWall = options.nowWall ?? Date.now;
  const nowMonotonic = options.nowMonotonic ?? (() => performance.now());
  const createEpoch = options.createEpoch ?? (() => crypto.randomUUID());

  let sequence = 0;
  let epoch = '';
  let timerState: { context: PracticeSessionWriteContext; generation: number } | null = null;
  let lastCheckpointPerf: number | null = null;
  let lastCheckpointWall: number | null = null;
  let pending: PendingPracticeSlice | null = null;
  let sessionWriteQueue: Promise<void> = Promise.resolve();
  let closeSlicePromise: {
    generation: number;
    context: PracticeSessionWriteContext;
    boundaryPerf: number;
    boundaryWall: number;
    promise: Promise<void>;
  } | null = null;
  let checkpointInFlight: { generation: number; context: PracticeSessionWriteContext; promise: Promise<void> } | null = null;

  function isCurrent(context: PracticeSessionWriteContext, generation: number): boolean {
    return generation === options.getCurrentGeneration() &&
      samePracticeSessionWriteContext(context, options.getCurrentContext());
  }

  function assertCurrent(context: PracticeSessionWriteContext, generation: number): void {
    if (generation !== options.getCurrentGeneration()) throw new StalePracticeSessionWriteError();
    assertPracticeSessionWriteContext(context, options.getCurrentContext());
  }

  function sameTimingOwner(context: PracticeSessionWriteContext, generation: number): boolean {
    return !!timerState && timerState.generation === generation && samePracticeSessionWriteContext(context, timerState.context);
  }

  function stopTimer(context: PracticeSessionWriteContext, generation: number): void {
    if (sameTimingOwner(context, generation)) {
      timerState = null;
      lastCheckpointPerf = null;
      lastCheckpointWall = null;
    }
  }

  function clearTiming(context: PracticeSessionWriteContext, generation = options.getCurrentGeneration()): void {
    if (pending && pending.generation === generation && samePracticeSessionWriteContext(context, pending.context)) pending = null;
    stopTimer(context, generation);
  }

  function setPendingSlice(
    slice: PracticeSession['slices'][number],
    context: PracticeSessionWriteContext,
    generation: number,
    startedPerf: number,
    boundaryPerf: number,
    boundaryWall: number,
    closesTimer = false,
  ): void {
    pending = { slice, context: { ...context }, generation, startedPerf, boundaryPerf, boundaryWall, closesTimer };
  }

  function getPendingSlice(): PendingPracticeSlice | null {
    return pending ? { ...pending, slice: { ...pending.slice }, context: { ...pending.context } } : null;
  }

  async function persist(
    update: (latest: PracticeSession) => PracticeSession,
    context = options.getCurrentContext(),
    generation = options.getCurrentGeneration(),
  ): Promise<void> {
    if (!context) throw new Error('没有活动练习记录');
    const result = sessionWriteQueue.then(async () => {
      assertCurrent(context, generation);
      const saved = await options.mutatePersonalData((draft) => {
        assertCurrent(context, generation);
        updatePracticeSessionIfOpen(draft.sessions, context.sessionId, update);
      });
      const updated = saved.sessions.find((item) => item.id === context.sessionId);
      if (!updated) throw new Error('练习保存后未能重新读取记录');
      if (isCurrent(context, generation)) options.onSessionSaved?.(updated, context, generation);
    });
    sessionWriteQueue = result.then(() => undefined, () => undefined);
    return result;
  }

  function persistCurrent(update: (latest: PracticeSession) => PracticeSession): Promise<void> {
    return persist(update, options.getCurrentContext(), options.getCurrentGeneration());
  }

  function startNewSession(nextEpoch = createEpoch()): void {
    sequence = 0;
    epoch = nextEpoch;
    pending = null;
    timerState = null;
    lastCheckpointPerf = null;
    lastCheckpointWall = null;
  }

  function setSequence(nextSequence: number): void {
    sequence = Math.max(0, Number.isSafeInteger(nextSequence) ? nextSequence : 0);
  }

  function resetForScore(): void {
    sequence = 0;
    pending = null;
    timerState = null;
    lastCheckpointPerf = null;
    lastCheckpointWall = null;
  }

  function startTiming(context = options.getCurrentContext(), generation = options.getCurrentGeneration()): void {
    if (!context || !isCurrent(context, generation) || options.getSession()?.state !== 'active') return;
    if (sameTimingOwner(context, generation)) return;
    timerState = { context: { ...context }, generation };
    lastCheckpointPerf = nowMonotonic();
    lastCheckpointWall = nowWall();
  }

  function getTimingState(): { context: PracticeSessionWriteContext; generation: number } | null {
    return timerState ? { context: { ...timerState.context }, generation: timerState.generation } : null;
  }

  function isTiming(): boolean {
    return timerState !== null && lastCheckpointPerf !== null;
  }

  function reportTimingFailure(error: unknown, context: PracticeSessionWriteContext, generation: number): void {
    if (error instanceof StalePracticeSessionWriteError) {
      clearTiming(context, generation);
      return;
    }
    if (error instanceof CompletedPracticeSessionError) clearTiming(context, generation);
    else {
      if (pending && pending.generation === generation && samePracticeSessionWriteContext(context, pending.context) && !pending.closesTimer) {
        const closing = closeSlicePromise && closeSlicePromise.generation === generation &&
          samePracticeSessionWriteContext(closeSlicePromise.context, context)
          ? closeSlicePromise
          : null;
        const boundaryPerf = closing ? closing.boundaryPerf : nowMonotonic();
        const boundaryWall = closing ? closing.boundaryWall : nowWall();
        const durationMs = Math.max(1, Math.floor(boundaryPerf - pending.startedPerf));
        pending = {
          ...pending,
          slice: { ...pending.slice, durationMs, startedAt: closing ? boundaryWall - durationMs : pending.slice.startedAt },
          boundaryPerf,
          boundaryWall,
          closesTimer: true,
        };
      }
      stopTimer(context, generation);
    }
    // A storage error from a previous score must not stop or annotate the new one.
    if (isCurrent(context, generation)) options.onTimingFailure?.(error, context, generation);
  }

  async function checkpoint(input: { playing: boolean; focused: boolean; visible: boolean }): Promise<void> {
    const context = options.getCurrentContext();
    if (!context) return;
    const generation = options.getCurrentGeneration();
    const existing = checkpointInFlight;
    if (existing && existing.generation === generation && samePracticeSessionWriteContext(existing.context, context)) {
      await existing.promise;
      return;
    }
    const operation = { generation, context: { ...context }, promise: Promise.resolve() };
    operation.promise = performCheckpoint(context, generation, input);
    checkpointInFlight = operation;
    try { await operation.promise; }
    finally { if (checkpointInFlight === operation) checkpointInFlight = null; }
  }

  async function performCheckpoint(
    context: PracticeSessionWriteContext,
    generation: number,
    input: { playing: boolean; focused: boolean; visible: boolean },
  ): Promise<void> {
    const session = options.getSession();
    if (!session || session.state !== 'active' || !isCurrent(context, generation) || !input.playing || !input.focused || !input.visible) return;
    if (!sameTimingOwner(context, generation) || lastCheckpointPerf === null || lastCheckpointWall === null) return;
    const nowPerf = nowMonotonic();
    const boundaryWall = nowWall();
    const elapsed = nowPerf - lastCheckpointPerf;
    if (elapsed < 5000) return;
    if (pending && (pending.generation !== generation || !samePracticeSessionWriteContext(pending.context, context))) return;
    if (!pending) {
      setPendingSlice(makePracticeSlice(session, sequence + 1, lastCheckpointWall, Math.floor(elapsed), epoch || createEpoch()), context, generation, lastCheckpointPerf, nowPerf, boundaryWall);
    }
    try {
      const pendingAtStart = pending;
      if (!pendingAtStart) return;
      const { slice } = pendingAtStart;
      await persist((latest) => {
        if (!latest.slices.some((item) => item.id === slice.id)) {
          latest.slices.push(slice);
          latest.slices.sort((a, b) => a.sequence - b.sequence);
        }
        return { ...latest, updatedAt: nowWall() };
      }, context, generation);
      if (!isCurrent(context, generation)) return;
      sequence = Math.max(sequence, slice.sequence);
      if (pending === pendingAtStart) {
        const persistedBoundary = pending;
        pending = null;
        if (persistedBoundary.closesTimer) {
          stopTimer(context, generation);
        } else if (sameTimingOwner(context, generation)) {
          // Advance only to the boundary represented by the persisted slice.
          lastCheckpointPerf = persistedBoundary.boundaryPerf;
          lastCheckpointWall = persistedBoundary.boundaryWall;
        }
      }
      options.onSliceSaved?.(context, generation);
    } catch (error) {
      reportTimingFailure(error, context, generation);
    }
  }

  async function closeSlice(context = options.getCurrentContext(), generation = options.getCurrentGeneration()): Promise<void> {
    if (!context) return;
    const existing = closeSlicePromise;
    if (existing && existing.generation === generation && samePracticeSessionWriteContext(existing.context, context)) {
      await existing.promise;
      return;
    }
    const boundaryPerf = nowMonotonic();
    const boundaryWall = nowWall();
    const operation = { generation, context: { ...context }, boundaryPerf, boundaryWall, promise: Promise.resolve() };
    operation.promise = performCloseSlice(context, generation, boundaryPerf, boundaryWall);
    closeSlicePromise = operation;
    try { await operation.promise; }
    finally { if (closeSlicePromise === operation) closeSlicePromise = null; }
  }

  async function performCloseSlice(
    context: PracticeSessionWriteContext,
    generation: number,
    boundaryPerf: number,
    boundaryWall: number,
  ): Promise<void> {
    const checkpoint = checkpointInFlight;
    if (checkpoint && checkpoint.generation === generation && samePracticeSessionWriteContext(checkpoint.context, context)) await checkpoint.promise;
    await sessionWriteQueue;
    if (!isCurrent(context, generation)) return;
    const session = options.getSession();
    if (sameTimingOwner(context, generation) && lastCheckpointPerf !== null && lastCheckpointWall !== null && session) {
      const elapsed = boundaryPerf - lastCheckpointPerf;
      if (elapsed >= 1) {
        if (pending && (pending.generation !== generation || !samePracticeSessionWriteContext(pending.context, context))) return;
        if (!pending) {
          setPendingSlice(makePracticeSlice(session, sequence + 1, lastCheckpointWall, Math.floor(elapsed), epoch || createEpoch()), context, generation, lastCheckpointPerf, boundaryPerf, boundaryWall, true);
        }
        pending = {
          ...pending!,
          slice: {
            ...pending!.slice,
            durationMs: Math.floor(boundaryPerf - pending!.startedPerf),
            startedAt: boundaryWall - Math.floor(boundaryPerf - pending!.startedPerf),
          },
          boundaryPerf,
          boundaryWall,
          closesTimer: true,
        };
      }
    }
    if (pending && pending.generation === generation && samePracticeSessionWriteContext(pending.context, context)) {
      await flushPending(context, generation);
    }
    if (!isCurrent(context, generation)) return;
    stopTimer(context, generation);
  }

  async function flushPending(context = pending?.context, generation = pending?.generation ?? -1): Promise<void> {
    if (!options.getSession() || !pending || !context || generation < 0) return;
    if (pending.generation !== generation || !samePracticeSessionWriteContext(pending.context, context)) return;
    if (!isCurrent(context, generation)) {
      clearTiming(context, generation);
      return;
    }
    const pendingAtStart = pending;
    const { slice } = pendingAtStart;
    try {
      await persist((latest) => {
        if (!latest.slices.some((item) => item.id === slice.id)) latest.slices.push(slice);
        return { ...latest, updatedAt: nowWall() };
      }, context, generation);
      if (!isCurrent(context, generation)) return;
      sequence = Math.max(sequence, slice.sequence);
      if (pending === pendingAtStart) {
        pending = null;
        if (pendingAtStart.closesTimer) {
          stopTimer(context, generation);
        } else if (sameTimingOwner(context, generation)) {
          lastCheckpointPerf = pendingAtStart.boundaryPerf;
          lastCheckpointWall = pendingAtStart.boundaryWall;
        }
      }
      options.onSliceSaved?.(context, generation);
    } catch (error) {
      reportTimingFailure(error, context, generation);
    }
  }

  async function finish(
    context: PracticeSessionWriteContext,
    generation: number,
    finishOptions: FinishPracticeOptions,
  ): Promise<FinishPracticeResult> {
    await closeSlice(context, generation);
    if (!isCurrent(context, generation)) return 'stale';
    if (pending) return 'pending-slice';
    if (!await finishOptions.saveResume()) return isCurrent(context, generation) ? 'resume-failed' : 'stale';
    if (!isCurrent(context, generation)) return 'stale';
    finishOptions.onReadyToCommit?.();
    const endedAt = nowWall();
    await persist((latest) => {
      if (finishOptions.expectedNote !== undefined) {
        assertPracticeNoteUnchanged(latest.note, finishOptions.expectedNote);
      }
      return {
        ...latest,
        state: 'completed',
        endedAt,
        note: finishOptions.note,
        updatedAt: endedAt,
      };
    }, context, generation);
    if (!isCurrent(context, generation)) return 'stale';
    finishOptions.onCommitted();
    return 'completed';
  }

  return {
    persist,
    persistCurrent,
    startNewSession,
    setSequence,
    resetForScore,
    clearSessionTiming: clearTiming,
    startTiming,
    getTimingState,
    isTiming,
    getPendingSlice,
    checkpoint,
    closeSlice,
    flushPending,
    finish,
  };
}
