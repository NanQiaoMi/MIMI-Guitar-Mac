<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { PersonalScore, PlayerResume, PracticeSession, SpeedPlan, PracticeFragment } from '../../lib/personal/types.ts';
  import { hashBytes, mutatePersonalData, readAsset, readPersonalData, subscribePersonalData } from '../../lib/personal/repository.ts';
  import type { PracticeSessionWriteContext } from '../../lib/practice/practiceProgress.ts';
  import { advanceSpeedPlan, assertPracticeAssetConsistency, canCountLoopCompletion, canPersistResume, cloneSpeedPlan, CompletedPracticeSessionError, createLoopLapProgress, createPracticeSession, createResumeWriteQueue, createSpeedPlan, hasSpeedPlanAnchor, isResumeCheckpointDue, isSpeedPlanApplied, isValidPlaybackRatio, isValidPracticeLoopRange, normalizePracticeLoopSelection, observeLoopLapProgress, reconcilePracticeSession, samePracticeSessionWriteContext, sameResumeContent, speedMultiplierAtAnchor, speedPlanMatchesLoop, StalePracticeSessionWriteError } from '../../lib/practice/practiceProgress.ts';
  import { appendPracticeQueueItem, setPracticeQueueStatus } from '../../lib/personal/practiceQueue.ts';
  import { clearPracticeSaveIssue, practiceSaveIssueIsCurrent, samePracticeSaveIssueOwner, upsertPracticeSaveIssue, type PracticeSaveIssue, type PracticeSaveIssueOwner } from '../../lib/practice/practiceSaveIssues.ts';
  import { assertPracticeNoteUnchanged, createPracticeSessionWriter, PracticeNoteConflictError } from '../../lib/practice/practiceSessionWriter.ts';
  import { createPracticeFragment, deletePracticeFragment, listPracticeFragments, updatePracticeFragment, validatePracticeFragmentApply } from '../../lib/personal/practiceFragments.ts';
  import { applyPracticeFragmentSafely } from '../../lib/practice/applyPracticeFragment.ts';
  import type { RegisterPracticeLeaveGuard } from '../../lib/practice/practiceLeaveGuard.ts';
  import PracticeFragmentLibrary from './PracticeFragmentLibrary.svelte';

  let {
    score,
    currentTick = 0,
    currentTime = 0,
    currentBeatEndTick = 0,
    lapCompletion = null,
    loopGeneration = 0,
    lapInterruptionRevision = 0,
    resumeIntentRevision = 0,
    playbackRatio = 1,
    trackMix = [],
    display = { fontScale: 1, chordMode: 'diagram', scoreDisplayMode: 'mixed', numberTab: true, showFretboard: false },
    endTick = 0,
    currentBar = 0,
    currentBeat = 0,
    currentTickIsSeek = false,
    repeatAmbiguous = false,
    currentBpm = 80,
    getNativeTempoAtTick = () => null,
    capo = 0,
    useSourceCapo = false,
    transpose = 0,
    trackIndexes = [0],
    metronome = false,
    countIn = false,
    loop = null,
    playing = false,
    focusOwned = false,
    ready = false,
    onPlay,
    onPause,
    onStop,
    onSeek,
    onSetLoop,
    onClearLoop,
    onSpeedChange,
    onSpeedMultiplier,
    onContinue,
    getPositionSnapshot,
    onRegisterPracticeLeaveGuard,
  }: {
    score: PersonalScore | null;
    currentTick?: number;
    currentTime?: number;
    currentBeatEndTick?: number;
    lapCompletion?: { generation: number; sequence: number; startTick: number; endTick: number } | null;
    loopGeneration?: number;
    lapInterruptionRevision?: number;
    resumeIntentRevision?: number;
    playbackRatio?: number;
    trackMix?: NonNullable<PlayerResume['trackMix']>;
    display?: NonNullable<PlayerResume['display']>;
    endTick?: number;
    currentBar?: number;
    currentBeat?: number;
    currentTickIsSeek?: boolean;
    repeatAmbiguous?: boolean;
    currentBpm?: number;
    getNativeTempoAtTick?: (tick: number) => number | null;
    capo?: number;
    useSourceCapo?: boolean;
    transpose?: number;
    trackIndexes?: number[];
    metronome?: boolean;
    countIn?: boolean;
    loop?: { startTick: number; endTick: number } | null;
    playing?: boolean;
    focusOwned?: boolean;
    ready?: boolean;
    onPlay: () => Promise<boolean>;
    onPause: () => boolean;
    onStop: () => void;
    onSeek: (tick: number) => Promise<{ tick: number; timeMs: number }>;
    onSetLoop: (startTick: number, endTick: number) => void;
    onClearLoop: () => void;
    onSpeedChange: (bpm: number) => void;
    onSpeedMultiplier: (multiplier: number, bpm?: number) => number;
    onContinue: (resume: PlayerResume) => Promise<number>;
    getPositionSnapshot?: () => { tick: number; timeMs: number };
    onRegisterPracticeLeaveGuard?: RegisterPracticeLeaveGuard;
  } = $props();

  let dataReady = $state(false);
  let joined = $state(false);
  let loadError = $state('');
  let operationError = $state('');
  type SaveErrorKind = 'timing' | 'resume' | 'note' | 'queue' | 'session' | 'speed-plan';
  type SaveIssue = PracticeSaveIssue<SaveErrorKind>;
  let saveIssues = $state<SaveIssue[]>([]);
  let saveIssueSequence = 0;
  let retryingSaveId = $state<number | null>(null);
  let session = $state<PracticeSession | null>(null);
  let lastResume = $state<PlayerResume | null>(null);
  let outdatedResume = $state<PlayerResume | null>(null);
  const enqueueResumeWrite = createResumeWriteQueue(async (resume: PlayerResume) => {
    if (sameResumeContent(lastResume, resume)) return;
    await mutatePersonalData((draft) => {
      const index = draft.resumes.findIndex((item) => item.scoreId === resume.scoreId);
      if (index >= 0) draft.resumes[index] = resume;
      else draft.resumes.push(resume);
    });
    if (score?.id === resume.scoreId && score.revision === resume.scoreRevision) lastResume = resume;
  });
  let note = $state('');
  let persistedNote = $state('');
  let noteDirty = $state(false);
  let noteSaving = $state(false);
  let noteEditBaseline = $state<string | null>(null);
  let noteConflict = $state(false);
  let noteEditContext = $state<PracticeSessionWriteContext | null>(null);
  let noteContextConflict = $state(false);
  let noteSavePromise: Promise<boolean> | null = null;
  let pointA = $state<number | null>(null);
  let pointABeatEndTick = $state<number | null>(null);
  let pointB = $state<number | null>(null);
  let visible = $state(true);
  let speedStart = $state(60);
  let speedTarget = $state(90);
  let speedStep = $state(5);
  let lapsPerLevel = $state(3);
  let speedPlan = $state<SpeedPlan | null>(null);
  let speedPlanApplied = $derived(isSpeedPlanApplied(speedPlan, loop, playbackRatio));
  let nativeAnchorAtA = $state(0);
  let speedMessage = $state('');
  let speedPlanWarning = $state('');
  let localLapInterruptionRevision = $state(0);
  let lapProgress = createLoopLapProgress(loopGeneration, lapInterruptionRevision, loop);
  let lastLapEvent = '';
  let seenLapIds = new Set<string>();
  let storageUnsubscribe: (() => void) | null = null;
  let timer: ReturnType<typeof setInterval> | null = null;
  let lastResumeWritePerf: number | null = null;
  let resumeDirty = false;
  let resumeBaseline: string | null = null;
  let loadedScoreKey = '';
  let practiceGeneration = 0;
  let refreshSequence = 0;
  let restoringResume = $state(false);
  let resumeRestoreGeneration = 0;
  let endingPractice = $state(false);
  let startingPractice = $state(false);
  let fragments = $state<PracticeFragment[]>([]);
  let fragmentBusy = $state(false);
  let fragmentOperationSequence = 0;
  let observedLoopSignature: string | null = null;
  let expectedRestoredLoopSignature: string | null = null;

  function errorMessage(error: unknown, fallback: string): string {
    return error instanceof Error ? error.message : fallback;
  }

  function clearOperationError(): void {
    operationError = '';
  }

  function reportOperationError(message: string): void {
    operationError = message;
  }

  function currentSaveIssueOwner(): PracticeSaveIssueOwner {
    return { scoreKey: currentScoreKey(), generation: practiceGeneration, sessionContext: currentSessionWriteContext() };
  }

  function reportSaveFailure(
    kind: SaveErrorKind,
    message: string,
    retry?: () => Promise<unknown>,
    owner = currentSaveIssueOwner(),
  ): number {
    const id = ++saveIssueSequence;
    saveIssues = upsertPracticeSaveIssue(saveIssues, { ...owner, id, kind, message, retry });
    return id;
  }

  function clearSaveFailure(kind: SaveErrorKind, owner = currentSaveIssueOwner(), issueId?: number): void {
    saveIssues = clearPracticeSaveIssue(saveIssues, kind, owner, issueId);
  }

  function isCurrentSaveIssue(issue: SaveIssue): boolean {
    return practiceSaveIssueIsCurrent(issue, currentSaveIssueOwner(), saveIssues);
  }

  function retrySessionUpdate(
    kind: SaveErrorKind,
    update: (latest: PracticeSession) => PracticeSession,
    context: PracticeSessionWriteContext,
    generation: number,
  ): () => Promise<void> {
    return async () => {
      await persistSession(update, context, generation);
    };
  }

  function handleSessionPersistFailure(
    kind: SaveErrorKind,
    error: unknown,
    label: string,
    update: (latest: PracticeSession) => PracticeSession,
    context: PracticeSessionWriteContext,
    generation: number,
  ): void {
    const owner: PracticeSaveIssueOwner = {
      scoreKey: `${context.scoreId}:${context.scoreRevision}`,
      generation,
      sessionContext: context,
    };
    if (error instanceof CompletedPracticeSessionError) {
      clearSaveFailure(kind, owner);
      void refreshData();
      reportOperationError('练习会话已在其他标签页结束，资料已刷新。');
      return;
    }
    if (error instanceof StalePracticeSessionWriteError) {
      clearSaveFailure(kind, owner);
      if (generation === practiceGeneration) {
        void refreshData();
        reportOperationError('练习状态已在其他标签页改变；资料已刷新，请重试。');
      }
      return;
    }
    if (!isSessionOperationCurrent(generation, context)) return;
    if (error instanceof Error && error.message === '练习记录已被其他页面移除') {
      clearSaveFailure(kind, owner);
      void refreshData();
      reportOperationError('练习记录已被其他页面移除；资料已刷新，请重新开始。');
      return;
    }
    reportSaveFailure(kind, `${label}未保存：${errorMessage(error, '本地写入失败')}`, retrySessionUpdate(kind, update, context, generation));
  }

  const sessionWriter = createPracticeSessionWriter({
    mutatePersonalData,
    getCurrentContext: currentSessionWriteContext,
    getCurrentGeneration: () => practiceGeneration,
    getSession: () => session,
    onSessionSaved: (updated, context, generation) => {
      if (generation === practiceGeneration && samePracticeSessionWriteContext(context, currentSessionWriteContext())) session = updated;
    },
    onSliceSaved: (context, generation) => clearSaveFailure('timing', {
      scoreKey: currentScoreKey(), generation, sessionContext: context,
    }),
    onTimingFailure: (error, context, generation) => {
      onPause();
      if (error instanceof CompletedPracticeSessionError) {
        reportOperationError('练习会话已在其他标签页结束，计时已停止。');
        void refreshData();
      } else {
        reportSaveFailure('timing', `练习计时尚未保存：${errorMessage(error, '本地写入失败')}`, async () => {
          await sessionWriter.flushPending(context, generation);
          return !sessionWriter.getPendingSlice();
        }, { scoreKey: currentScoreKey(), generation, sessionContext: context });
      }
    },
  });

  function loopSignature(value: { startTick: number; endTick: number } | null): string {
    return value ? `${value.startTick}:${value.endTick}` : 'none';
  }

  function currentScoreKey(): string {
    return score ? `${score.id}:${score.revision}` : '';
  }

  function currentSessionWriteContext(): PracticeSessionWriteContext | null {
    return score && session ? { scoreId: score.id, scoreRevision: score.revision, sessionId: session.id } : null;
  }

  function populateSpeedPlanInputs(plan: SpeedPlan | null): void {
    if (!score || !plan || plan.revision !== score.revision || !hasSpeedPlanAnchor(plan) || !plan.loopRange) return;
    try {
      createSpeedPlan(plan.revision, plan.startBpm, plan.targetBpm, plan.stepBpm, plan.lapsPerLevel, plan.nativeAnchorBpm, plan.loopRange);
      if (!Number.isFinite(plan.currentBpm) || plan.currentBpm < plan.startBpm || plan.currentBpm > plan.targetBpm) return;
      speedMultiplierAtAnchor(plan.currentBpm, plan.nativeAnchorBpm);
    } catch {
      return;
    }
    speedStart = plan.startBpm;
    speedTarget = plan.targetBpm;
    speedStep = plan.stepBpm;
    lapsPerLevel = plan.lapsPerLevel;
  }

  function syncSessionFromSnapshot(sessions: readonly PracticeSession[], scoreId: string, scoreRevision: string) {
    const previous = session;
    const previousId = previous?.id ?? null;
    const next = reconcilePracticeSession(session, sessions, scoreId, scoreRevision);
    if (previous && previous.id !== next?.id) {
      const previousContext = { scoreId, scoreRevision, sessionId: previous.id };
      const timingState = sessionWriter.getTimingState();
      const wasCounting = previous.state === 'active' || (timingState !== null && samePracticeSessionWriteContext(previousContext, timingState.context));
      sessionWriter.clearSessionTiming(previousContext, timingState?.generation ?? practiceGeneration);
      if (wasCounting) onPause();
      lapProgress = createLoopLapProgress(loopGeneration, currentLapInterruptionRevision(), loop);
    }
    session = next;
    if (!next) {
      speedPlan = null;
      nativeAnchorAtA = 0;
      speedPlanWarning = '';
      sessionWriter.setSequence(0);
      const savedNoteSession = (previousId ? sessions.find((item) => item.id === previousId) : null) ??
        [...sessions].reverse().find((item) => item.scoreId === scoreId && item.scoreRevision === scoreRevision);
      if (savedNoteSession) persistedNote = savedNoteSession.note;
      else if (!noteDirty) {
        note = '';
        persistedNote = '';
        noteEditBaseline = null;
        noteConflict = false;
        noteEditContext = null;
        noteContextConflict = false;
      }
      if (!noteDirty) {
        note = persistedNote;
        noteEditBaseline = null;
        noteConflict = false;
        noteEditContext = null;
        noteContextConflict = false;
      }
      if (noteDirty && (!noteEditContext || !samePracticeSessionWriteContext(noteEditContext, currentSessionWriteContext()))) {
        noteContextConflict = true;
      }
      return;
    }
    const persisted = sessions.find((item) => item.id === next.id);
    persistedNote = persisted?.note ?? next.note;
    if (noteDirty && (!noteEditContext || !samePracticeSessionWriteContext(noteEditContext, currentSessionWriteContext()))) {
      noteContextConflict = true;
    }
    if (next.id !== previousId) {
      speedPlan = next.speedPlan ?? null;
      populateSpeedPlanInputs(speedPlan);
      nativeAnchorAtA = hasSpeedPlanAnchor(speedPlan) ? speedPlan.nativeAnchorBpm : 0;
      speedPlanWarning = speedPlan && !hasSpeedPlanAnchor(speedPlan)
        ? '旧提速计划没有 A 点原生速度锚点，请重设 A/B 与提速计划。'
        : speedPlan && !speedPlan.loopRange
          ? '提速计划没有绑定 A/B 区间，请重设 A/B 与提速计划。'
          : '';
      sessionWriter.setSequence(Math.max(0, ...next.slices.map((slice) => slice.sequence)));
      if (!noteDirty) {
        note = persistedNote;
        noteEditBaseline = null;
        noteConflict = false;
        noteEditContext = null;
        noteContextConflict = false;
      }
    } else if (!noteDirty) {
      note = persistedNote;
      noteEditBaseline = null;
      noteConflict = false;
      noteEditContext = null;
      noteContextConflict = false;
    }
  }

  function setNoteDraft(value: string): void {
    if (!noteDirty) {
      noteEditBaseline = persistedNote;
      noteConflict = false;
      noteEditContext = currentSessionWriteContext();
      noteContextConflict = false;
    }
    note = value;
    noteDirty = true;
  }

  function isScoreOperationCurrent(generation: number, key: string): boolean {
    return generation === practiceGeneration && key === currentScoreKey();
  }

  function isSessionOperationCurrent(generation: number, context: PracticeSessionWriteContext | null): boolean {
    if (generation !== practiceGeneration) return false;
    const current = currentSessionWriteContext();
    return context ? samePracticeSessionWriteContext(context, current) : current === null;
  }

  function persistSession(
    update: (latest: PracticeSession) => PracticeSession,
    context = currentSessionWriteContext(),
    generation = practiceGeneration,
  ): Promise<void> {
    return sessionWriter.persist(update, context, generation);
  }

  function currentLapInterruptionRevision(): number {
    return lapInterruptionRevision + localLapInterruptionRevision;
  }

  function invalidateSpeedPlan(message = '') {
    if (!speedPlan) return;
    speedPlan = null;
    speedPlanWarning = message;
    const context = currentSessionWriteContext();
    const generation = practiceGeneration;
    const owner = currentSaveIssueOwner();
    if (context) {
      const removePlan = (latest: PracticeSession) => {
        const { speedPlan: _discarded, ...withoutPlan } = latest;
        return { ...withoutPlan, updatedAt: Date.now() };
      };
      void persistSession(removePlan, context, generation).then(() => {
        if (isSessionOperationCurrent(generation, context)) clearSaveFailure('speed-plan', owner);
      }).catch((error) => {
        if (!isSessionOperationCurrent(generation, context) || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return;
        reportSaveFailure('speed-plan', `区间已变更，但旧提速计划未能清除：${errorMessage(error, '本地写入失败')}`, retrySessionUpdate('speed-plan', removePlan, context, generation), owner);
      });
    }
  }

  async function refreshData() {
    const requestedSequence = ++refreshSequence;
    const requestedScore = score;
    const requestedKey = requestedScore ? `${requestedScore.id}:${requestedScore.revision}` : '';
    const requestedGeneration = practiceGeneration;
    try {
      const latest = await readPersonalData();
      if (requestedSequence !== refreshSequence || requestedGeneration !== practiceGeneration || requestedKey !== currentScoreKey()) return;
      if (!requestedScore) { dataReady = true; joined = false; lastResume = null; outdatedResume = null; session = null; return; }
      joined = latest.practiceItems.some((item) => item.scoreId === requestedScore.id && item.status !== 'archived');
      fragments = listPracticeFragments(latest, requestedScore.id);
      const resume = latest.resumes.find((item) => item.scoreId === requestedScore.id);
      lastResume = resume?.scoreRevision === requestedScore.revision ? resume : null;
      outdatedResume = resume && resume.scoreRevision !== requestedScore.revision ? resume : null;
      syncSessionFromSnapshot(latest.sessions, requestedScore.id, requestedScore.revision);
      dataReady = true;
      loadError = '';
    } catch (error) {
      if (requestedSequence !== refreshSequence || requestedGeneration !== practiceGeneration || requestedKey !== currentScoreKey()) return;
      loadError = error instanceof Error ? error.message : '无法读取本地练习资料';
      dataReady = false;
    }
  }

  async function saveNote(expectedOwner?: PracticeSaveIssueOwner, retryValue?: string, expectedIssueId?: number): Promise<boolean> {
    if (expectedOwner && !samePracticeSaveIssueOwner(expectedOwner, currentSaveIssueOwner())) return false;
    if (!noteDirty) return true;
    if (noteConflict) return false;
    if (noteContextConflict) return false;
    if (noteSavePromise) {
      const saved = await noteSavePromise;
      if (!saved) return false;
      return noteDirty ? saveNote(expectedOwner) : true;
    }
    if (!session) return false;
    clearOperationError();
    const context = currentSessionWriteContext();
    const generation = practiceGeneration;
    const owner = currentSaveIssueOwner();
    const value = retryValue ?? note;
    const expectedNote = noteEditBaseline ?? persistedNote;
    if (!context || !noteEditContext || !samePracticeSessionWriteContext(noteEditContext, context)) {
      noteContextConflict = true;
      reportOperationError('练习会话已变化；草稿仍保留，取消编辑后才能继续，草稿不会写入其他会话。');
      return false;
    }
    noteSaving = true;
    const operation = (async (): Promise<boolean> => {
      try {
        await persistSession((latest) => {
          assertPracticeNoteUnchanged(latest.note, expectedNote);
          return { ...latest, note: value, updatedAt: Date.now() };
        }, context, generation);
        if (!samePracticeSaveIssueOwner(owner, currentSaveIssueOwner()) || !isSessionOperationCurrent(generation, context)) return false;
        clearSaveFailure('note', owner);
        persistedNote = value;
        noteEditBaseline = value;
        noteConflict = false;
        noteContextConflict = false;
        if (note === value) {
          noteDirty = false;
          noteEditBaseline = null;
          noteEditContext = null;
        }
        return true;
      } catch (error) {
        if (!samePracticeSaveIssueOwner(owner, currentSaveIssueOwner()) || !isSessionOperationCurrent(generation, context)) return false;
        if (error instanceof PracticeNoteConflictError) {
          clearSaveFailure('note', owner, expectedIssueId);
          noteConflict = true;
          await refreshData();
          if (samePracticeSaveIssueOwner(owner, currentSaveIssueOwner()) && isSessionOperationCurrent(generation, context)) {
            reportOperationError('备注已在其他标签页更新；本页草稿已保留。请取消编辑载入最新备注，再继续修改。');
          }
          return false;
        }
        if (error instanceof CompletedPracticeSessionError || error instanceof StalePracticeSessionWriteError ||
            (error instanceof Error && error.message === '练习记录已被其他页面移除')) {
          clearSaveFailure('note', owner, expectedIssueId);
          void refreshData();
          reportOperationError(error instanceof CompletedPracticeSessionError
            ? '练习会话已结束；资料已刷新，备注草稿仍保留。'
            : '练习状态已改变；资料已刷新，备注草稿仍保留。');
          return false;
        }
        let issueId = 0;
        issueId = reportSaveFailure('note', `备注未保存：${errorMessage(error, '本地写入失败')}`, () => saveNote(owner, undefined, issueId), owner);
        return false;
      }
    })();
    let tracked: Promise<boolean>;
    tracked = operation.finally(() => {
      if (noteSavePromise === tracked) {
        noteSavePromise = null;
        noteSaving = false;
      }
    });
    noteSavePromise = tracked;
    return tracked;
  }

  function cancelNoteEdit(): void {
    if (noteSaving) return;
    note = persistedNote;
    noteDirty = false;
    noteEditBaseline = null;
    noteConflict = false;
    noteEditContext = null;
    noteContextConflict = false;
    clearOperationError();
  }

  async function preparePracticeLeave(): Promise<boolean> {
    const generation = practiceGeneration;
    const scoreKey = currentScoreKey();
    const context = currentSessionWriteContext();
    const isOriginalContextCurrent = () => generation === practiceGeneration && scoreKey === currentScoreKey() &&
      (context
        ? samePracticeSessionWriteContext(context, currentSessionWriteContext())
        : currentSessionWriteContext() === null);
    while (true) {
      if (noteSavePromise) {
        const saved = await noteSavePromise;
        if (!saved && noteDirty) return false;
      }
      if (!isOriginalContextCurrent()) return false;
      if (!noteDirty) return true;
      if (noteConflict) {
        reportOperationError('备注草稿与其他标签页的版本冲突；请取消编辑载入最新备注后再离开。');
        return false;
      }
      if (noteContextConflict || !noteEditContext ||
          !samePracticeSessionWriteContext(noteEditContext, currentSessionWriteContext())) {
        noteContextConflict = true;
        reportOperationError('备注所属练习会话已变化；草稿仍保留且不会写入其他会话，请取消编辑后再离开。');
        return false;
      }
      if (!context || !session) {
        reportOperationError('备注草稿尚未关联到可保存的练习会话；请取消编辑。');
        return false;
      }
      if (!(await saveNote())) return false;
      if (!isOriginalContextCurrent()) return false;
    }
  }

  async function joinPractice(expectedOwner?: PracticeSaveIssueOwner, expectedScore?: PersonalScore): Promise<boolean> {
    const selectedScore = expectedScore ?? score;
    if (!selectedScore) return false;
    const owner = expectedOwner ?? currentSaveIssueOwner();
    if (!samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
    clearOperationError();
    try {
      const now = Date.now();
      await mutatePersonalData((draft) => {
        const existing = draft.scores.findIndex((item) => item.id === selectedScore.id);
        if (existing >= 0) draft.scores[existing] = { ...draft.scores[existing], ...selectedScore, updatedAt: now };
        else draft.scores.push({ ...selectedScore, createdAt: selectedScore.createdAt || now, updatedAt: now });
        const item = draft.practiceItems.find((entry) => entry.scoreId === selectedScore.id);
        if (item) {
          if (item.status === 'archived') {
            draft.practiceItems = setPracticeQueueStatus(draft.practiceItems, selectedScore.id, 'todo');
          }
          const restored = draft.practiceItems.find((entry) => entry.scoreId === selectedScore.id);
          if (restored) restored.updatedAt = now;
        } else {
          draft.practiceItems = appendPracticeQueueItem(draft.practiceItems, {
            scoreId: selectedScore.id, status: 'todo', note: '', order: 0, updatedAt: now,
          });
        }
      });
      if (!samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
      joined = true;
      clearSaveFailure('queue', owner);
      await refreshData();
      return samePracticeSaveIssueOwner(owner, currentSaveIssueOwner());
    } catch (error) {
      if (!samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
      reportSaveFailure('queue', `待练项目保存失败：${errorMessage(error, '本地写入失败')}`, () => joinPractice(owner, selectedScore), owner);
      return false;
    }
  }

  async function beginPractice() {
    if (startingPractice || endingPractice || fragmentBusy) return;
    const selectedScore = score;
    const operationGeneration = practiceGeneration;
    const operationKey = currentScoreKey();
    let operationSessionContext: PracticeSessionWriteContext | null = null;
    let playAttempted = false;
    const assertCurrentScore = () => {
      if (!isScoreOperationCurrent(operationGeneration, operationKey)) throw new StalePracticeSessionWriteError();
    };
    if (!selectedScore || !joined || !dataReady || !ready || selectedScore.revision === 'unverified') {
      reportOperationError('请先加载并核对谱面版本，再开始练习。');
      return;
    }
    clearOperationError();
    startingPractice = true;
    try {
      const pending = sessionWriter.getPendingSlice();
      if (pending) {
        if (pending.generation !== operationGeneration || !samePracticeSessionWriteContext(pending.context, currentSessionWriteContext())) {
          throw new StalePracticeSessionWriteError();
        }
        await sessionWriter.flushPending(pending.context, pending.generation);
        if (sessionWriter.getPendingSlice()) throw new Error('上次练习计时尚未保存，请先重试保存。');
      }
      assertCurrentScore();
      const snapshot = await readPersonalData();
      assertCurrentScore();
      syncSessionFromSnapshot(snapshot.sessions, selectedScore.id, selectedScore.revision);
      const storedBeforeStart = snapshot.scores.find((item) => item.id === selectedScore.id);
      if (!storedBeforeStart) throw new Error('个人谱引用已被移除，请重新加入待练');
      if (storedBeforeStart.source !== selectedScore.source) throw new Error('练习谱来源与本地引用不一致，请重新打开曲谱');
      if (selectedScore.source === 'catalog') {
        assertPracticeAssetConsistency({
          source: selectedScore.source,
          storedSource: storedBeforeStart.source,
          scoreRevision: selectedScore.revision,
          storedRevision: storedBeforeStart.revision,
        });
      } else {
        if (!selectedScore.assetId) throw new Error('个人谱缺少可播放附件，无法开始练习');
        const asset = await readAsset(selectedScore.assetId);
        assertCurrentScore();
        if (!asset) throw new Error('个人谱可播放附件缺失，请先修复个人谱资料');
        const assetHash = await hashBytes(new Uint8Array(asset.bytes));
        assertCurrentScore();
        assertPracticeAssetConsistency({
          source: selectedScore.source,
          storedSource: storedBeforeStart.source,
          scoreRevision: selectedScore.revision,
          storedRevision: storedBeforeStart.revision,
          scoreAssetId: selectedScore.assetId,
          storedAssetId: storedBeforeStart.assetId,
          actualAssetId: asset.id,
          actualAssetHash: assetHash,
        });
      }
      await mutatePersonalData((draft) => {
        assertCurrentScore();
        const stored = draft.scores.find((item) => item.id === selectedScore.id);
        if (!stored) throw new Error('个人谱引用已被移除，请重新加入待练');
        if (stored.source !== storedBeforeStart.source || stored.revision !== storedBeforeStart.revision || stored.assetId !== storedBeforeStart.assetId) {
          throw new Error('个人谱在校验期间已更新，请重新打开后再练习');
        }
        stored.revision = selectedScore.revision;
        stored.updatedAt = Date.now();
      });
      assertCurrentScore();
      let created: PracticeSession | null = null;
      if (!session || session.state === 'completed' || session.scoreRevision !== selectedScore.revision) {
        created = createPracticeSession(selectedScore.id, selectedScore.revision);
        const saved = await mutatePersonalData((draft) => {
          assertCurrentScore();
          const existingOpen = [...draft.sessions].reverse().find((item) => item.scoreId === selectedScore.id && item.scoreRevision === selectedScore.revision && item.state !== 'completed');
          if (existingOpen) throw new Error('另一标签页已开始这首曲谱的练习，请刷新后继续');
          const item = draft.practiceItems.find((entry) => entry.scoreId === selectedScore.id);
          if (item) { item.status = 'practicing'; item.updatedAt = Date.now(); }
          draft.sessions.push(created!);
        });
        assertCurrentScore();
        session = saved.sessions.find((item) => item.id === created!.id) ?? created;
        operationSessionContext = currentSessionWriteContext();
        sessionWriter.startNewSession(crypto.randomUUID());
      } else {
        operationSessionContext = currentSessionWriteContext();
        await persistSession((latest) => ({ ...latest, state: 'active', updatedAt: Date.now() }), operationSessionContext, operationGeneration);
      }
      assertCurrentScore();
      if (!operationSessionContext || !isSessionOperationCurrent(operationGeneration, operationSessionContext)) throw new StalePracticeSessionWriteError();
      playAttempted = true;
      const started = await onPlay();
      if (!isSessionOperationCurrent(operationGeneration, operationSessionContext)) throw new StalePracticeSessionWriteError();
      if (!started) {
        await persistSession((latest) => ({ ...latest, state: 'paused', updatedAt: Date.now() }), operationSessionContext, operationGeneration);
        throw new Error('音频焦点或播放引擎未就绪，练习已保存为暂停状态');
      }
      resumeDirty = true;
      await storeResume(true);
      if (!isSessionOperationCurrent(operationGeneration, operationSessionContext)) throw new StalePracticeSessionWriteError();
    } catch (error) {
      if (error instanceof StalePracticeSessionWriteError && !isScoreOperationCurrent(operationGeneration, operationKey)) return;
      if (error instanceof CompletedPracticeSessionError) {
        await refreshData();
        reportOperationError('这段练习已在其他标签页结束；资料已刷新，再次点击可开始新练习。');
      } else if (error instanceof StalePracticeSessionWriteError) {
        if (playAttempted && isScoreOperationCurrent(operationGeneration, operationKey)) onPause();
        await refreshData();
        reportOperationError('练习状态已在其他标签页改变；资料已刷新，请重试。');
      } else {
        reportOperationError(errorMessage(error, '练习开始失败'));
      }
      if (operationSessionContext && isSessionOperationCurrent(operationGeneration, operationSessionContext) && session?.state === 'active' && !playing) {
        const pauseUpdate = (latest: PracticeSession) => ({ ...latest, state: 'paused' as const, updatedAt: Date.now() });
        try { await persistSession(pauseUpdate, operationSessionContext, operationGeneration); }
        catch (persistError) { handleSessionPersistFailure('session', persistError, '暂停状态', pauseUpdate, operationSessionContext, operationGeneration); }
      }
    } finally { if (operationGeneration === practiceGeneration) startingPractice = false; }
  }

  async function checkpoint(): Promise<void> {
    await sessionWriter.checkpoint({ playing, focused: focusOwned, visible });
  }

  function closeSlice(context = currentSessionWriteContext(), generation = practiceGeneration): Promise<void> {
    return sessionWriter.closeSlice(context, generation);
  }

  async function pausePractice(): Promise<boolean> {
    clearOperationError();
    const operationGeneration = practiceGeneration;
    const operationKey = currentScoreKey();
    const operationContext = currentSessionWriteContext();
    const operationOwner = currentSaveIssueOwner();
    const isCurrentOperation = () => isScoreOperationCurrent(operationGeneration, operationKey) &&
      (operationContext ? samePracticeSessionWriteContext(operationContext, currentSessionWriteContext()) : currentSessionWriteContext() === null);
    const pausedResume = captureResumeSnapshot();
    if (!onPause()) { reportOperationError('播放器未能暂停，请等待谱面就绪。'); return false; }
    if (session) session = { ...session, state: 'paused', updatedAt: Date.now() };
    await closeSlice(operationContext, operationGeneration);
    if (!isCurrentOperation()) return false;
    const slicePending = !!sessionWriter.getPendingSlice();
    const resumeSaved = !!pausedResume && await storeResume(true, playbackRatio, pausedResume, operationOwner);
    if (!isCurrentOperation()) return false;
    let sessionSaved = true;
    if (session) {
      const pauseUpdate = (latest: PracticeSession) => ({ ...latest, state: 'paused' as const, updatedAt: Date.now() });
      try { await persistSession(pauseUpdate, operationContext, operationGeneration); }
      catch (error) {
        sessionSaved = false;
        if (operationContext) handleSessionPersistFailure('session', error, '暂停状态', pauseUpdate, operationContext, operationGeneration);
      }
      if (sessionSaved && isCurrentOperation()) clearSaveFailure('session', operationOwner);
    }
    return isCurrentOperation() && resumeSaved && sessionSaved && !slicePending;
  }

  async function endPractice(expectedOwner?: PracticeSaveIssueOwner): Promise<boolean> {
    if (!session || endingPractice || fragmentBusy) return false;
    if (noteDirty && (noteConflict || noteContextConflict)) return false;
    if (noteDirty && (!noteEditContext || !samePracticeSessionWriteContext(noteEditContext, currentSessionWriteContext()))) {
      noteContextConflict = true;
      reportOperationError('备注所属练习会话已变化；草稿仍保留且不会写入其他会话，请取消编辑后再结束。');
      return false;
    }
    const owner = expectedOwner ?? currentSaveIssueOwner();
    if (!samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
    if (noteSavePromise && !(await noteSavePromise)) return false;
    if (!session || endingPractice || fragmentBusy || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
    clearOperationError();
    const operationGeneration = practiceGeneration;
    const operationKey = currentScoreKey();
    const operationContext = currentSessionWriteContext();
    if (!operationContext) return false;
    const endingNote = note;
    const expectedNote = noteEditBaseline ?? persistedNote;
    const isCurrentOperation = () => isScoreOperationCurrent(operationGeneration, operationKey) &&
      samePracticeSessionWriteContext(operationContext, currentSessionWriteContext());
    const endingResume = captureResumeSnapshot();
    endingPractice = true;
    onPause();
    try {
      const result = await sessionWriter.finish(operationContext, operationGeneration, {
        note: endingNote,
        expectedNote,
        saveResume: async () => !!endingResume && await storeResume(true, playbackRatio, endingResume, owner),
        onReadyToCommit: () => {
          if (session) session = { ...session, state: 'paused', updatedAt: Date.now() };
        },
        onCommitted: () => {
          session = null;
          persistedNote = endingNote;
          if (note === endingNote) {
            noteDirty = false;
            noteEditBaseline = null;
            noteConflict = false;
            noteEditContext = null;
            noteContextConflict = false;
          }
          resumeDirty = false;
          onStop();
          resumeBaseline = resumeSignature();
          clearSaveFailure('session', owner);
        },
      });
      if (result === 'stale') return false;
      if (result === 'pending-slice') return false;
      if (result === 'resume-failed') {
        if (!isCurrentOperation() || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
        session = { ...session, state: 'paused', updatedAt: Date.now() };
        const pauseUpdate = (latest: PracticeSession) => ({ ...latest, state: 'paused' as const, updatedAt: Date.now() });
        try {
          await persistSession(pauseUpdate, operationContext, operationGeneration);
          if (isCurrentOperation()) clearSaveFailure('session', owner);
        }
        catch (error) { handleSessionPersistFailure('session', error, '暂停状态', pauseUpdate, operationContext, operationGeneration); }
        return false;
      }
      return result === 'completed';
    } catch (error) {
      if (error instanceof PracticeNoteConflictError && isCurrentOperation()) {
        await refreshData();
        if (isCurrentOperation() && samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) {
          if (noteDirty) {
            noteConflict = true;
            reportOperationError('备注已在其他标签页更新；练习未结束，本页草稿已保留。请取消编辑载入最新备注后再试。');
          } else {
            noteConflict = false;
            reportOperationError('备注已在其他标签页更新；练习未结束，资料已刷新，请再次结束。');
          }
        }
      } else if (error instanceof CompletedPracticeSessionError) {
        await refreshData();
        if (samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) reportOperationError('练习会话已在其他标签页结束，资料已刷新。');
      } else if (!(error instanceof StalePracticeSessionWriteError) && isCurrentOperation()) {
        reportSaveFailure('session', `结束记录未保存：${errorMessage(error, '本地写入失败')}`, () => endPractice(owner), owner);
      }
      return false;
    } finally {
      if (operationGeneration === practiceGeneration) endingPractice = false;
    }
  }

  async function retrySave(issueId: number) {
    const issue = saveIssues.find((candidate) => candidate.id === issueId);
    if (!issue?.retry || retryingSaveId === issueId) return;
    if (!isCurrentSaveIssue(issue)) {
      clearSaveFailure(issue.kind, issue, issue.id);
      return;
    }
    retryingSaveId = issueId;
    try {
      const result = await issue.retry();
      if (!samePracticeSaveIssueOwner(issue, currentSaveIssueOwner())) clearSaveFailure(issue.kind, issue, issue.id);
      else if (result !== false && isCurrentSaveIssue(issue)) clearSaveFailure(issue.kind, issue, issue.id);
    }
    catch (error) {
      if (!samePracticeSaveIssueOwner(issue, currentSaveIssueOwner())) {
        clearSaveFailure(issue.kind, issue, issue.id);
      } else if (error instanceof StalePracticeSessionWriteError || error instanceof CompletedPracticeSessionError) {
        clearSaveFailure(issue.kind, issue, issue.id);
        reportOperationError('练习状态已改变；资料已刷新，请重试。');
        void refreshData();
      } else if (isCurrentSaveIssue(issue)) {
        reportSaveFailure(issue.kind, `${issue.message}（重试仍未成功：${errorMessage(error, '本地写入失败')}）`, issue.retry, issue);
      }
    } finally { if (retryingSaveId === issueId) retryingSaveId = null; }
  }

  function captureResumeSnapshot(): PlayerResume | null {
    if (!score) return null;
    const position = getPositionSnapshot?.();
    const tick = position?.tick ?? currentTick;
    const timeMs = position?.timeMs ?? currentTime;
    return {
      scoreId: score.id,
      scoreRevision: score.revision,
      tick: Math.max(0, Math.min(endTick || Number.MAX_SAFE_INTEGER, Number.isFinite(tick) ? tick : currentTick)),
      timeMs: Math.max(0, Number.isFinite(timeMs) ? timeMs : currentTime),
      speed: speedPlanApplied && speedPlan ? speedPlan.currentBpm : currentBpm,
      capo,
      useSourceCapo,
      transpose,
      loop: loop ? { startTick: loop.startTick, endTick: loop.endTick } : null,
      trackIndexes: [...trackIndexes],
      trackMix: trackMix.map((mix) => ({ ...mix })),
      display: { ...display },
      metronome,
      countIn,
      playbackRatio,
      updatedAt: Date.now(),
    };
  }

  async function storeResume(
    force = false,
    ratioOverride?: number,
    baseResume?: PlayerResume,
    expectedOwner?: PracticeSaveIssueOwner,
  ): Promise<boolean> {
    if (expectedOwner && !samePracticeSaveIssueOwner(expectedOwner, currentSaveIssueOwner())) return false;
    const owner = currentSaveIssueOwner();
    const operationGeneration = practiceGeneration;
    const operationKey = currentScoreKey();
    const nowPerf = performance.now();
    if (!score || (endingPractice && !baseResume) || !canPersistResume({ dirty: resumeDirty, joined, dataReady, playerReady: ready, hasPosition: endTick > 0, restoring: restoringResume, explicitSnapshot: !!baseResume }) || (!force && !isResumeCheckpointDue(nowPerf, lastResumeWritePerf))) return false;
    const savedRatio = ratioOverride ?? playbackRatio;
    if (!isValidPlaybackRatio(savedRatio)) { reportOperationError('当前播放倍率超出 AlphaTab 支持范围，断点尚未保存。'); return false; }
    const resume: PlayerResume = baseResume
      ? { ...baseResume, playbackRatio: savedRatio, updatedAt: Date.now() }
      : { ...captureResumeSnapshot()!, playbackRatio: savedRatio, updatedAt: Date.now() };
    lastResumeWritePerf = nowPerf;
    try {
      await enqueueResumeWrite(resume);
      if (!isScoreOperationCurrent(operationGeneration, operationKey) || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
      clearSaveFailure('resume', owner);
      return true;
    } catch (error) {
      if (!isScoreOperationCurrent(operationGeneration, operationKey) || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return false;
      lastResumeWritePerf = null;
      reportSaveFailure('resume', `断点尚未保存：${errorMessage(error, '本地写入失败')}`, () => storeResume(true, savedRatio, resume, owner), owner);
      return false;
    }
  }

  function setPointA() {
    if (fragmentBusy) return;
    clearOperationError();
    if (!Number.isSafeInteger(endTick) || endTick <= 0 || !Number.isSafeInteger(currentTick) || currentTick < 0 || currentTick >= endTick) {
      reportOperationError('当前位置不在当前谱面范围内，无法设置 A。');
      return;
    }
    const nativeTempo = getNativeTempoAtTick(currentTick);
    if (nativeTempo === null || !Number.isFinite(nativeTempo) || nativeTempo < 1 || nativeTempo > 1000) {
      reportOperationError('A 点原生速度不可用，请等待谱面就绪或选择谱面内的位置。');
      return;
    }
    pointA = currentTick;
    pointABeatEndTick = Number.isSafeInteger(currentBeatEndTick) && currentBeatEndTick > currentTick && currentBeatEndTick <= endTick
      ? currentBeatEndTick
      : null;
    nativeAnchorAtA = nativeTempo;
    pointB = null;
    invalidateSpeedPlan('A/B 区间已改变，请重新创建提速计划。');
    onClearLoop();
  }

  function setPointB() {
    if (fragmentBusy) return;
    clearOperationError();
    try {
      const range = normalizePracticeLoopSelection({
        pointATick: pointA,
        pointABeatEndTick,
        currentTick,
        currentBeatEndTick,
        scoreEndTick: endTick,
      });
      const nativeTempo = getNativeTempoAtTick(range.startTick);
      if (nativeTempo === null || !Number.isFinite(nativeTempo) || nativeTempo < 1 || nativeTempo > 1000) {
        throw new Error('无法确认最终 A 点的原生速度，区间未改变。');
      }
      const reverseSelection = pointA !== null && currentTick < pointA;
      pointA = range.startTick;
      if (reverseSelection) pointABeatEndTick = currentBeatEndTick;
      pointB = range.endTick;
      nativeAnchorAtA = nativeTempo;
      onSetLoop(range.startTick, range.endTick);
      invalidateSpeedPlan('A/B 区间已改变，请重新创建提速计划。');
    } catch (error) {
      reportOperationError(errorMessage(error, '无法设置 A-B 区间。'));
    }
  }

  function startSpeedPlan() {
    if (fragmentBusy) return;
    clearOperationError();
    if (!score || !loop || !session || session.scoreRevision !== score.revision) { reportOperationError('请先开始当前版本的练习并设置有效 A-B 区间。'); return; }
    const parameterIssue = fragmentSaveReason();
    if (parameterIssue) { reportOperationError(parameterIssue); return; }
    nativeAnchorAtA = getNativeTempoAtTick(loop.startTick) ?? 0;
    if (!Number.isFinite(nativeAnchorAtA) || nativeAnchorAtA < 1 || nativeAnchorAtA > 1000) {
      reportOperationError('A 点原生速度不可用，请在有效 A 点重新设置后创建计划。');
      return;
    }
    try {
      const plan = createSpeedPlan(score.revision, speedStart, speedTarget, speedStep, lapsPerLevel, nativeAnchorAtA, { startTick: loop.startTick, endTick: loop.endTick });
      const requestedRatio = speedMultiplierAtAnchor(speedStart, nativeAnchorAtA);
      const actualRatio = onSpeedMultiplier(requestedRatio, speedStart);
      if (!isValidPlaybackRatio(actualRatio) || Math.abs(actualRatio - requestedRatio) > 0.0001) {
        throw new Error('播放器未能应用计划起始倍率，请确认当前谱面速度后重试。');
      }
      speedPlan = plan;
      speedPlanWarning = '';
      seenLapIds = new Set();
      lapProgress = createLoopLapProgress(loopGeneration, currentLapInterruptionRevision(), loop);
      speedMessage = `A 点目标 ${speedStart} BPM · 倍率 ${actualRatio.toFixed(2)}×`;
      const persistedPlan = cloneSpeedPlan(plan);
      const context = currentSessionWriteContext();
      const generation = practiceGeneration;
      const owner = currentSaveIssueOwner();
      const savePlan = (latest: PracticeSession) => ({ ...latest, speedPlan: persistedPlan, updatedAt: Date.now() });
      if (context) {
        void persistSession(savePlan, context, generation).then(() => {
          if (isSessionOperationCurrent(generation, context)) clearSaveFailure('speed-plan', owner);
        }).catch((error) => {
          if (!isSessionOperationCurrent(generation, context) || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return;
          handleSessionPersistFailure('speed-plan', error, '提速计划', savePlan, context, generation);
        });
      }
    } catch (error) {
      reportOperationError(errorMessage(error, '提速参数无效'));
    }
  }

  function fragmentSaveReason(): string | null {
    if (!dataReady || !score) return '请等待本地资料加载。';
    if (!joined) return '请先加入待练。';
    if (!ready) return '请等待谱面和音源准备就绪。';
    if (!/^[a-f0-9]{64}$/.test(score.revision)) return '当前谱面内容尚未核验，请重新加载。';
    if (!isValidPracticeLoopRange(loop, endTick)) return '请先设置谱面内的有效 A-B 区间。';
    const nativeTempo = getNativeTempoAtTick(loop.startTick);
    if (nativeTempo === null) return '无法确认 A 点原生速度，请重新选区。';
    if (![speedStart, speedTarget, speedStep, lapsPerLevel].every(Number.isFinite)) return '请填写完整的起始、目标、步长和圈数。';
    if (speedStart < 20 || speedStart > 300 || speedTarget < 20 || speedTarget > 300) return '起始与目标速度须在 20–300 BPM 内。';
    if (speedTarget < speedStart) return '目标速度不能低于起始速度。';
    if (speedStep <= 0 || !Number.isSafeInteger(lapsPerLevel) || lapsPerLevel < 1) return '步长须大于零，每级圈数须为正整数。';
    try {
      createSpeedPlan(score.revision, speedStart, speedTarget, speedStep, lapsPerLevel, nativeTempo, loop);
      speedMultiplierAtAnchor(speedTarget, nativeTempo);
      return null;
    } catch { return '这些速度超出当前曲谱可用倍率，请调整起始或目标 BPM。'; }
  }

  function fragmentApplyReason(fragment: PracticeFragment): string | null {
    if (!dataReady || !ready || !score) return '请等待本地资料、谱面和音源准备就绪。';
    try {
      validatePracticeFragmentApply(fragment, score.id, score.revision, endTick);
      const nativeTempo = getNativeTempoAtTick(fragment.range.startTick);
      if (nativeTempo === null) return '无法确认 A 点原生速度，请重新选区。';
      speedMultiplierAtAnchor(fragment.speed.startBpm, nativeTempo);
      speedMultiplierAtAnchor(fragment.speed.targetBpm, nativeTempo);
      return null;
    } catch (error) { return error instanceof Error ? error.message : '该片段暂不能应用。'; }
  }

  async function runFragmentOperation(action: (assertCurrent: () => void) => Promise<void>): Promise<void> {
    if (fragmentBusy || startingPractice || endingPractice || restoringResume) throw new Error('请等待当前练习操作完成。');
    const generation = practiceGeneration;
    const key = currentScoreKey();
    const operation = ++fragmentOperationSequence;
    const assertCurrent = () => {
      if (operation !== fragmentOperationSequence || !isScoreOperationCurrent(generation, key)) throw new Error('曲谱已切换，请在当前曲谱重试。');
    };
    fragmentBusy = true;
    try { assertCurrent(); await action(assertCurrent); }
    finally { if (operation === fragmentOperationSequence) fragmentBusy = false; }
  }

  async function saveFragment(draft: { name: string; note: string }): Promise<void> {
    await runFragmentOperation(async (assertCurrent) => {
      const reason = fragmentSaveReason();
      if (reason) throw new Error(reason);
      if (!score || !loop) throw new Error('请先设置 A-B 区间。');
      const nativeTempo = getNativeTempoAtTick(loop.startTick);
      if (nativeTempo === null) throw new Error('无法确认 A 点原生速度。');
      await createPracticeFragment({
        scoreId: score.id, scoreRevision: score.revision, ...draft,
        range: { startTick: loop.startTick, endTick: loop.endTick },
        speed: { nativeAnchorBpm: nativeTempo, startBpm: speedStart, targetBpm: speedTarget, stepBpm: speedStep, lapsPerLevel },
      });
      assertCurrent();
      await refreshData();
    });
  }

  async function editFragment(id: string, expectedUpdatedAt: number, patch: { name?: string; note?: string }): Promise<void> {
    await runFragmentOperation(async (assertCurrent) => {
      if (!fragments.some((fragment) => fragment.id === id)) throw new Error('该片段不在当前曲谱中。');
      await updatePracticeFragment(id, expectedUpdatedAt, patch);
      assertCurrent();
      await refreshData();
    });
  }

  async function removeFragment(id: string, expectedUpdatedAt: number): Promise<void> {
    await runFragmentOperation(async (assertCurrent) => {
      if (!fragments.some((fragment) => fragment.id === id)) throw new Error('该片段不在当前曲谱中。');
      await deletePracticeFragment(id, expectedUpdatedAt);
      assertCurrent();
      await refreshData();
    });
  }

  async function applyFragment(id: string, expectedUpdatedAt: number): Promise<void> {
    await runFragmentOperation(async (assertCurrent) => {
      const selectedScore = score;
      const context = currentSessionWriteContext();
      const generation = practiceGeneration;
      const pendingSeek: { request?: Promise<{ tick: number; timeMs: number }> } = {};
      if (!selectedScore || !ready) throw new Error('请等待谱面准备就绪。');
      const isCurrent = () => {
        try { assertCurrent(); } catch { return false; }
        return ready && isSessionOperationCurrent(generation, context);
      };
      try {
        await applyPracticeFragmentSafely({
        scoreId: selectedScore.id, scoreRevision: selectedScore.revision, expectedUpdatedAt,
        isCurrent, endTick: () => endTick, nativeTempoAtTick: getNativeTempoAtTick,
        load: async () => (await readPersonalData()).practiceFragments.find((fragment) => fragment.id === id) ?? null,
        pauseAndSave: pausePractice,
        clearPlan: async () => {
          if (context) await persistSession((latest) => {
            const { speedPlan: _removed, ...withoutPlan } = latest;
            return { ...withoutPlan, updatedAt: Date.now() };
          }, context, generation);
        },
        apply: ({ fragment, nativeAnchorBpm: nativeTempo, playbackRatio: requestedRatio }) => {
          assertCurrent();
          if (!onPause()) throw new Error('播放器未能保持暂停，片段未应用。');
          const actualRatio = onSpeedMultiplier(requestedRatio, fragment.speed.startBpm);
          if (!isValidPlaybackRatio(actualRatio) || Math.abs(actualRatio - requestedRatio) > 0.0001) throw new Error('播放器未能应用起始速度，请重试。');
          speedPlan = null;
          const signature = loopSignature(fragment.range);
          expectedRestoredLoopSignature = signature === observedLoopSignature ? null : signature;
          pointA = fragment.range.startTick; pointABeatEndTick = null; pointB = fragment.range.endTick;
          nativeAnchorAtA = nativeTempo;
          speedStart = fragment.speed.startBpm; speedTarget = fragment.speed.targetBpm;
          speedStep = fragment.speed.stepBpm; lapsPerLevel = fragment.speed.lapsPerLevel;
          seenLapIds = new Set();
          onSetLoop(pointA, pointB);
          restoringResume = true;
          pendingSeek.request = onSeek(pointA);
          lapProgress = createLoopLapProgress(loopGeneration, currentLapInterruptionRevision(), fragment.range);
          speedPlanWarning = '';
          speedMessage = `片段已应用 · A 点原速 ${nativeTempo} BPM · 请明确开始练习与提速。`;
        },
        });
        const receipt = await pendingSeek.request;
        await tick();
        assertCurrent();
        const snapshot = captureResumeSnapshot();
        if (!receipt || !snapshot) throw new Error('位置跳转尚未确认，请重试。');
        resumeBaseline = resumeSignature();
        restoringResume = false;
        resumeDirty = true;
        if (!await storeResume(true, playbackRatio, { ...snapshot, ...receipt })) throw new Error('片段已应用并保持暂停，但新断点尚未保存；请重试保存。');
      } finally { if (generation === practiceGeneration) restoringResume = false; }
    });
  }

  function recordPosition(
    tick: number,
    isSeek: boolean,
    generation: number,
    interruptionRevision: number,
    range: { startTick: number; endTick: number } | null,
    isPlaying: boolean,
    focused: boolean,
    isVisible: boolean,
  ) {
    lapProgress = observeLoopLapProgress(lapProgress, {
      tick,
      isSeek,
      generation,
      interruptionRevision,
      range,
      playing: isPlaying,
      focused,
      visible: isVisible,
    });
  }

  function applyCompletedLap(
    event: typeof lapCompletion,
    generation: number,
    range: { startTick: number; endTick: number } | null,
    isPlaying: boolean,
    focused: boolean,
    isVisible: boolean,
    interruptionRevision: number,
  ) {
    if (!event || event.generation !== generation || !range || event.startTick !== range.startTick || event.endTick !== range.endTick) return;
    const eventId = `${event.generation}:${event.sequence}`;
    if (eventId === lastLapEvent) return;
    lastLapEvent = eventId;
    const completedWholeLap = canCountLoopCompletion({
      playing: isPlaying,
      focused,
      visible: isVisible,
      observedFromA: lapProgress.observedFromA,
      event,
      range,
    });
    // playerFinished means AlphaTab has wrapped this exact playbackRange to A.
    // Discard this partial/interrupted pass, then allow the next full pass to arm.
    lapProgress = {
      ...createLoopLapProgress(generation, interruptionRevision, range),
      observedFromA: isPlaying && focused && isVisible,
    };
    if (!completedWholeLap || !session || !speedPlan || !isSpeedPlanApplied(speedPlan, range, playbackRatio)) {
      if (speedPlan && !isSpeedPlanApplied(speedPlan, range, playbackRatio)) speedPlanWarning = '当前 A/B 区间或播放器倍率与提速计划不匹配；恢复匹配后才会推进。';
      return;
    }
    const lapId = `${session.id}:${score?.revision}:${eventId}`;
    const advanced = advanceSpeedPlan(speedPlan, lapId, seenLapIds);
    if (advanced.changed) {
      const requestedRatio = speedMultiplierAtAnchor(advanced.plan.currentBpm, nativeAnchorAtA);
      try {
        const actualRatio = onSpeedMultiplier(requestedRatio, advanced.plan.currentBpm);
        if (!isValidPlaybackRatio(actualRatio) || Math.abs(actualRatio - requestedRatio) > 0.0001) {
          throw new Error('播放器实际倍率与提速计划不一致');
        }
      } catch (error) {
        reportOperationError(`提速未能应用：${errorMessage(error, '播放器倍率设置失败')}`);
        lapProgress = createLoopLapProgress(generation, interruptionRevision, range);
        return;
      }
      speedPlan = advanced.plan;
      speedMessage = speedPlan.currentBpm >= speedPlan.targetBpm
        ? `已达到目标：${speedPlan.targetBpm} BPM · 保持目标速度`
        : `完整区间完成：${speedPlan.currentBpm} BPM · ${speedPlan.completedLaps}/${speedPlan.lapsPerLevel} 圈`;
      const persistedPlan = cloneSpeedPlan(advanced.plan);
      const context = currentSessionWriteContext();
      const owner = currentSaveIssueOwner();
      const practiceWriteGeneration = practiceGeneration;
      const savePlan = (latest: PracticeSession) => ({ ...latest, speedPlan: persistedPlan, updatedAt: Date.now() });
      if (context) {
        void sessionWriter.persistCurrent(savePlan).then(() => {
          if (isSessionOperationCurrent(practiceWriteGeneration, context)) clearSaveFailure('speed-plan', owner);
        }).catch((error) => {
          if (!isSessionOperationCurrent(practiceWriteGeneration, context) || !samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) return;
          handleSessionPersistFailure('speed-plan', error, '提速进度', savePlan, context, practiceWriteGeneration);
        });
      }
    }
  }

  async function continuePractice() {
    if (fragmentBusy || startingPractice || endingPractice || restoringResume) return;
    clearOperationError();
    const resume = lastResume;
    if (!resume || !score || resume.scoreRevision !== score.revision) return;
    const operationGeneration = practiceGeneration;
    const operationKey = currentScoreKey();
    const operationSessionContext = currentSessionWriteContext();
    const operationOwner = currentSaveIssueOwner();
    let restoredRatio: number;
    let restoredFromPlan = false;
    const needsLegacySpeedWarning = resume.playbackRatio === undefined;
    const restoreGeneration = ++resumeRestoreGeneration;
    restoringResume = true;
    expectedRestoredLoopSignature = loopSignature(resume.loop ?? null);
    try {
      restoredRatio = await onContinue(resume);
      if (!isValidPlaybackRatio(restoredRatio)) throw new Error('播放器未能确认断点实际倍率，已保持暂停。');
    }
    catch (error) {
      if (!isScoreOperationCurrent(operationGeneration, operationKey)) return;
      expectedRestoredLoopSignature = null;
      reportOperationError(`续练参数未能恢复：${errorMessage(error, '播放器恢复失败')}`);
      return;
    }
    finally { if (restoreGeneration === resumeRestoreGeneration) restoringResume = false; }
    if (!isScoreOperationCurrent(operationGeneration, operationKey)) return;
    if (operationSessionContext && !isSessionOperationCurrent(operationGeneration, operationSessionContext)) {
      onPause();
      await refreshData();
      reportOperationError('练习会话已在其他标签页改变；资料已刷新，请重试。');
      return;
    }
    resumeDirty = true;
    resumeBaseline = resumeSignature();
    if (speedPlan) {
      if (hasSpeedPlanAnchor(speedPlan) && speedPlanMatchesLoop(speedPlan, resume.loop)) {
        nativeAnchorAtA = speedPlan.nativeAnchorBpm;
        const plannedRatio = speedMultiplierAtAnchor(speedPlan.currentBpm, speedPlan.nativeAnchorBpm);
        if (resume.playbackRatio !== undefined && Math.abs(resume.playbackRatio - plannedRatio) > 0.0001) {
          invalidateSpeedPlan('断点实际倍率与已保存提速计划不一致；已保留实际倍率，请重设计划。');
        } else {
          // Re-apply even when the ratio already matches so the player also restores
          // the plan's target-BPM display independently of the song-wide native tempo.
          const actualRatio = onSpeedMultiplier(plannedRatio, speedPlan.currentBpm);
          if (!isValidPlaybackRatio(actualRatio) || Math.abs(actualRatio - plannedRatio) > 0.0001) {
            reportOperationError('续练位置已恢复，但当前播放器无法应用已保存的提速计划。');
            return;
          }
          restoredRatio = actualRatio;
          restoredFromPlan = true;
          speedPlanWarning = '';
          populateSpeedPlanInputs(speedPlan);
        }
      } else {
        invalidateSpeedPlan('已恢复播放断点；旧提速计划缺少有效速度锚点或 A/B 区间已变，请重设 A/B 与提速计划。');
      }
    }
    const resumedSnapshot = {
      ...resume,
      speed: restoredFromPlan && speedPlan ? speedPlan.currentBpm : resume.speed,
    };
    const resumeSaved = await storeResume(true, restoredRatio, resumedSnapshot, operationOwner);
    if (operationSessionContext && !isSessionOperationCurrent(operationGeneration, operationSessionContext)) {
      onPause();
      await refreshData();
      reportOperationError('练习会话已在其他标签页改变；资料已刷新，请重试。');
      return;
    }
    if (needsLegacySpeedWarning && !restoredFromPlan) reportOperationError('旧断点未含实际倍率，位置已恢复并保持暂停，请确认速度。');
    if (operationSessionContext) {
      const pauseUpdate = (latest: PracticeSession) => ({ ...latest, state: 'paused' as const, updatedAt: Date.now() });
      try {
        await persistSession(pauseUpdate, operationSessionContext, operationGeneration);
        if (isSessionOperationCurrent(operationGeneration, operationSessionContext) && samePracticeSaveIssueOwner(operationOwner, currentSaveIssueOwner())) {
          clearSaveFailure('session', operationOwner);
        }
      }
      catch (error) {
        handleSessionPersistFailure('session', error, '续练暂停状态', pauseUpdate, operationSessionContext, operationGeneration);
      }
    }
    if (!resumeSaved) return;
  }

  $effect(() => {
    const signature = loopSignature(loop);
    if (observedLoopSignature === null) { observedLoopSignature = signature; return; }
    if (signature === observedLoopSignature) return;
    observedLoopSignature = signature;
    if (expectedRestoredLoopSignature === signature) { expectedRestoredLoopSignature = null; return; }
    invalidateSpeedPlan('A/B 区间已改变，旧提速计划已失效。');
  });

  $effect(() => {
    if (endingPractice) return;
    if (playing && focusOwned && visible && session?.state === 'active') {
      sessionWriter.startTiming(currentSessionWriteContext(), practiceGeneration);
    } else if (sessionWriter.isTiming()) {
      const timingState = sessionWriter.getTimingState();
      const context = timingState?.context ?? null;
      const generation = timingState?.generation ?? practiceGeneration;
      const owner = { scoreKey: currentScoreKey(), generation, sessionContext: context };
      const shouldPersistPause = !!context && session?.state === 'active' && isSessionOperationCurrent(generation, context);
      void closeSlice(context, generation).then(async () => {
        if (shouldPersistPause && context && isSessionOperationCurrent(generation, context) && session?.state === 'active') {
          const pauseUpdate = (latest: PracticeSession) => ({ ...latest, state: 'paused' as const, updatedAt: Date.now() });
          try {
            await persistSession(pauseUpdate, context, generation);
            if (isSessionOperationCurrent(generation, context) && samePracticeSaveIssueOwner(owner, currentSaveIssueOwner())) {
              clearSaveFailure('session', owner);
            }
          }
          catch (error) {
            if (error instanceof StalePracticeSessionWriteError) {
              sessionWriter.clearSessionTiming(context, generation);
            } else if (isSessionOperationCurrent(generation, context)) {
              handleSessionPersistFailure('session', error, '暂停状态', pauseUpdate, context, generation);
            }
          }
        }
      });
    }
  });

  $effect(() => {
    const signature = resumeSignature();
    if (endingPractice || !score || !joined || !dataReady || !ready || restoringResume) return;
    if (resumeBaseline === null) {
      resumeBaseline = signature;
      return;
    }
    if (signature !== resumeBaseline) {
      resumeBaseline = signature;
      resumeDirty = true;
      void storeResume();
    }
  });

  $effect(() => {
    const key = score ? `${score.id}:${score.revision}` : '';
    if (key === loadedScoreKey) return;
    loadedScoreKey = key;
    practiceGeneration++;
    fragmentOperationSequence++;
    fragmentBusy = false;
    fragments = [];
    session = null;
    lastResume = null;
    outdatedResume = null;
    resumeDirty = false;
    resumeBaseline = null;
    lastResumeWritePerf = null;
    refreshSequence++;
    joined = false;
    speedPlan = null;
    nativeAnchorAtA = 0;
    speedPlanWarning = '';
    note = '';
    persistedNote = '';
    noteDirty = false;
    noteEditBaseline = null;
    noteConflict = false;
    noteEditContext = null;
    noteContextConflict = false;
    pointA = null;
    pointABeatEndTick = null;
    pointB = null;
    clearOperationError();
    saveIssues = [];
    retryingSaveId = null;
    expectedRestoredLoopSignature = null;
    sessionWriter.resetForScore();
    startingPractice = false;
    endingPractice = false;
    resumeRestoreGeneration++;
    restoringResume = false;
    void refreshData();
  });

  $effect(() => {
    if ((!noteDirty && !noteSaving) || typeof window === 'undefined') return;
    const warnBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', warnBeforeUnload);
    return () => window.removeEventListener('beforeunload', warnBeforeUnload);
  });

  $effect(() => {
    recordPosition(currentTick, currentTickIsSeek, loopGeneration, currentLapInterruptionRevision(), loop, playing, focusOwned, visible);
  });

  $effect(() => {
    applyCompletedLap(lapCompletion, loopGeneration, loop, playing, focusOwned, visible, currentLapInterruptionRevision());
  });

  $effect(() => {
    loopGeneration;
    lastLapEvent = '';
  });

  onMount(() => {
    storageUnsubscribe = subscribePersonalData(() => { void refreshData(); });
    const unregisterLeaveGuard = onRegisterPracticeLeaveGuard?.(preparePracticeLeave);
    const visibility = () => {
      const isVisible = document.visibilityState === 'visible';
      if (!isVisible && visible) {
        localLapInterruptionRevision++;
        onPause();
      }
      visible = isVisible;
    };
    document.addEventListener('visibilitychange', visibility);
    visible = document.visibilityState === 'visible';
    if (!visible) { localLapInterruptionRevision++; onPause(); }
    timer = setInterval(() => { void checkpoint(); void storeResume(); }, 1000);
    return () => {
      unregisterLeaveGuard?.();
      document.removeEventListener('visibilitychange', visibility);
      storageUnsubscribe?.();
      if (timer) clearInterval(timer);
      void storeResume(true);
      const timingState = sessionWriter.getTimingState();
      if (timingState) void closeSlice(timingState.context, timingState.generation);
    };
  });

  function resumeSignature(): string {
    return JSON.stringify({
      key: score ? `${score.id}:${score.revision}` : '', speed: currentBpm, playbackRatio,
      capo, useSourceCapo, transpose, trackIndexes, trackMix, display, metronome, countIn, loop, resumeIntentRevision,
    });
  }

  function resumeTimeLabel(timeMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(timeMs / 1000));
    return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, '0')}`;
  }

  function resumeDateLabel(updatedAt: number): string {
    if (!Number.isFinite(updatedAt) || updatedAt < 0) return '时间未知';
    const date = new Date(updatedAt);
    if (!Number.isFinite(date.getTime())) return '时间未知';
    return new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
  }

  function resumeRevisionLabel(revision: string): string {
    return /^[a-f0-9]{64}$/.test(revision) ? `${revision.slice(0, 8)}…` : revision;
  }
</script>

<section class="border-t border-[#e8dfd2] bg-[#fbf9f4] px-4 pt-4 pb-24 sm:px-5 sm:py-4" aria-label="个人练习控制">
  <div class="flex flex-wrap items-center justify-between gap-2">
    <div>
      <h2 class="text-sm font-semibold text-ink">本地练习</h2>
      <p class="text-xs text-mid-gray">有效时长只统计前台、持有音频焦点且引擎实际播放的时间。</p>
    </div>
    <span class="text-xs {dataReady ? 'text-emerald-700' : 'text-amber-800'}">{dataReady ? '本地资料可用' : '正在检查本地资料'}</span>
  </div>

  {#if loadError}<p class="mt-2 max-w-full break-words text-sm text-danger" role="alert">本地资料加载失败：{loadError}</p>{/if}
  {#if operationError}<p class="mt-2 max-w-full break-words text-sm text-danger" role="alert">{operationError}</p>{/if}
  {#each saveIssues as issue (issue.id)}
    <div class="mt-2 flex min-w-0 max-w-full flex-wrap items-center gap-2 text-sm text-danger" role="alert">
      <span class="min-w-0 break-words">{issue.message}</span>
      {#if issue.retry}
        <button type="button" class="min-h-[44px] rounded px-2 underline" onclick={() => retrySave(issue.id)} disabled={retryingSaveId === issue.id}>
          {retryingSaveId === issue.id ? '正在重试' : '重试保存'}
        </button>
      {/if}
    </div>
  {/each}

  <div class="mt-3 flex flex-wrap items-center gap-2">
    {#if !joined}
      <button type="button" class="btn btn-primary min-h-[44px] !px-3 !py-1.5 text-xs" onclick={() => joinPractice()} disabled={!score || !dataReady}>加入待练</button>
    {:else}
      <span class="rounded-full bg-signal/10 px-3 py-1 text-xs text-signal">已加入待练</span>
      {#if session}
        {#if playing}
          <button type="button" class="btn btn-primary min-h-[44px] !px-3 !py-1.5 text-xs" onclick={pausePractice} disabled={fragmentBusy || endingPractice}>暂停练习</button>
        {:else}
          <button type="button" class="btn btn-primary min-h-[44px] !px-3 !py-1.5 text-xs" onclick={beginPractice} disabled={!ready || !dataReady || startingPractice || endingPractice || fragmentBusy}>继续练习</button>
        {/if}
        <button type="button" class="btn btn-ghost min-h-[44px] !px-3 !py-1.5 text-xs" onclick={() => endPractice()} disabled={endingPractice || fragmentBusy || noteSaving || (noteDirty && (noteConflict || noteContextConflict))}>结束并保存</button>
      {:else}
        <button type="button" class="btn btn-primary min-h-[44px] !px-3 !py-1.5 text-xs" onclick={beginPractice} disabled={!ready || !dataReady || startingPractice || fragmentBusy || noteDirty}>开始练习</button>
      {/if}
      {#if lastResume && ready && !playing}
        <button type="button" class="btn btn-ghost min-h-[44px] min-w-0 max-w-full !whitespace-normal break-words text-left leading-5 !px-3 !py-1.5 text-xs" onclick={continuePractice} disabled={fragmentBusy || endingPractice || restoringResume}>继续上次并保持暂停（{resumeTimeLabel(lastResume.timeMs)} · tick {Math.round(lastResume.tick)} · {Math.round(lastResume.speed)} BPM · {resumeDateLabel(lastResume.updatedAt)}）</button>
      {/if}
    {/if}
    <span class="text-xs text-mid-gray">小节 {currentBar || '—'} · 拍 {currentBeat || '—'} · tick {Math.round(currentTick)}</span>
  </div>
  {#if outdatedResume}
    <p class="mt-2 max-w-full break-words text-xs text-warning" role="status">最近断点来自旧谱面版本 {resumeRevisionLabel(outdatedResume.scoreRevision)}，保存于 {resumeDateLabel(outdatedResume.updatedAt)}；已停用直接续练，请重新打开当前谱面。</p>
  {/if}

  {#if joined}
    <details class="mt-3 min-w-0 rounded-xl border border-[#e8dfd2] bg-white/55">
      <summary class="relative flex min-h-[44px] cursor-pointer list-none flex-col justify-center gap-1 px-3 py-2 pr-10 text-left text-sm font-medium text-ink focus-visible:outline focus-visible:outline-2 focus-visible:outline-signal sm:flex-row sm:items-center sm:justify-between">
        <span>区间、提速与练习片段</span>
        <span class="text-xs font-normal text-mid-gray">A {pointA ?? loop?.startTick ?? '—'} · B {pointB ?? loop?.endTick ?? '—'} · {speedPlan ? '已设提速计划' : '未设提速计划'}</span>
        <span aria-hidden="true" class="absolute right-3 top-1/2 -translate-y-1/2 text-lg leading-none">⌄</span>
      </summary>
      <div class="min-w-0 px-3 pb-3">
    <fieldset class="grid min-w-0 gap-3 lg:grid-cols-2" disabled={!ready || fragmentBusy || endingPractice || startingPractice || restoringResume}>
      <div class="rounded-xl border border-[#e8dfd2] bg-white/70 p-3">
        <h3 class="text-xs font-semibold text-ink">A-B 区间</h3>
        <p class="mt-1 text-xs text-mid-gray">先定位并设置 A，再播放到 B 点并设置 B，即可循环练习这段。可以倒着选；反复段请在目标演奏次序播放时设点。{#if repeatAmbiguous}当前小节有反复次序，请按正在播放的顺序设置。{/if}</p>
        <div class="mt-2 flex flex-wrap items-center gap-2">
          <button type="button" class="btn btn-ghost min-h-[44px] !px-3 !py-1 text-xs" onclick={setPointA} aria-label="将当前位置设为循环 A 点">设 A</button>
          <span class="font-mono text-xs">{pointA ?? loop?.startTick ?? '—'}</span>
          <button type="button" class="btn btn-ghost min-h-[44px] !px-3 !py-1 text-xs" onclick={setPointB} disabled={pointA === null} aria-label="将当前拍末设为循环 B 点">设 B</button>
          <span class="font-mono text-xs">{pointB ?? loop?.endTick ?? '—'}</span>
          <button type="button" class="btn btn-ghost min-h-[44px] !px-3 !py-1 text-xs" onclick={() => { onClearLoop(); pointA = null; pointABeatEndTick = null; pointB = null; invalidateSpeedPlan('A/B 区间已清除，旧提速计划已失效。'); }}>清除</button>
          {#if loop}<span class="text-xs text-signal">循环中 [{loop.startTick}, {loop.endTick})</span>{/if}
        </div>
      </div>
      <div class="rounded-xl border border-[#e8dfd2] bg-white/70 p-3">
        <h3 class="text-xs font-semibold text-ink">渐进提速</h3>
        <p class="mt-1 text-xs text-mid-gray">完成设定圈数后提速；跳转、暂停或切出页面会重新计算当前圈。</p>
        <div class="mt-2 flex flex-wrap items-center gap-2 text-xs">
          <label>起始 <input class="min-h-[44px] w-16 rounded border px-1" type="number" min="20" max="300" bind:value={speedStart} aria-label="提速计划起始 BPM" /></label>
          <label>目标 <input class="min-h-[44px] w-16 rounded border px-1" type="number" min="20" max="300" bind:value={speedTarget} aria-label="提速计划目标 BPM" /></label>
          <label>步长 <input class="min-h-[44px] w-14 rounded border px-1" type="number" min="1" max="50" bind:value={speedStep} aria-label="每级增加 BPM" /></label>
          <label>每级圈数 <input class="min-h-[44px] w-14 rounded border px-1" type="number" min="1" max="20" bind:value={lapsPerLevel} aria-label="每级完整循环圈数" /></label>
          <button type="button" class="btn btn-primary min-h-[44px] !px-3 !py-1 text-xs" onclick={startSpeedPlan} disabled={!session || !loop}>开始提速</button>
        </div>
        {#if speedPlan}<p class="mt-2 text-xs text-signal">{#if speedPlanApplied}{#if speedPlan.currentBpm >= speedPlan.targetBpm}目标已达 · 保持 {speedPlan.targetBpm} BPM{:else}当前 {speedPlan.currentBpm} BPM · {speedPlan.completedLaps}/{speedPlan.lapsPerLevel} 圈 · 上限 {speedPlan.targetBpm}{/if}{:else if hasSpeedPlanAnchor(speedPlan) && speedPlan.loopRange}上次计划 {speedPlan.currentBpm} BPM，恢复后生效{:else}已保存提速计划未应用{/if}</p>{/if}
        {#if speedPlanWarning}<p class="mt-2 text-xs text-warning" role="status">{speedPlanWarning}</p>{/if}
        {#if speedMessage}<p class="mt-1 text-xs text-mid-gray">{speedMessage}</p>{/if}
      </div>
    </fieldset>
    <PracticeFragmentLibrary
      {fragments}
      currentScoreId={score?.id ?? null}
      currentScoreRevision={score?.revision ?? null}
      currentRevisionTrusted={/^[a-f0-9]{64}$/.test(score?.revision ?? '')}
      canSaveReason={fragmentSaveReason()}
      applyBlockedReason={fragmentApplyReason}
      busy={fragmentBusy || startingPractice || endingPractice || !dataReady || restoringResume}
      onSave={saveFragment}
      onUpdate={editFragment}
      onDelete={removeFragment}
      onApply={applyFragment}
    />
      </div>
    </details>
  {/if}

  {#if session || noteDirty}
    <div class="mt-3">
      <label class="block text-xs text-mid-gray" for="practice-session-note">本次练习备注</label>
      <textarea
        id="practice-session-note"
        class="mt-1 min-h-[72px] w-full rounded-lg border border-[#e8dfd2] bg-white p-2 text-sm text-ink focus-visible:outline focus-visible:outline-2 focus-visible:outline-signal disabled:bg-surface-alt"
        rows="2"
        value={note}
        oninput={(event) => setNoteDraft((event.currentTarget as HTMLTextAreaElement).value)}
        disabled={endingPractice}
      ></textarea>
      <div class="mt-2 flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-primary min-h-[44px] !px-3 !py-1.5 text-xs" onclick={() => { void saveNote(); }} disabled={!session || !noteDirty || noteSaving || noteConflict || noteContextConflict || endingPractice}>
          {noteSaving ? '正在保存备注…' : '保存备注'}
        </button>
        <button type="button" class="btn btn-ghost min-h-[44px] !px-3 !py-1.5 text-xs" onclick={cancelNoteEdit} disabled={!noteDirty || noteSaving}>
          取消编辑
        </button>
        <span class="text-xs text-mid-gray" role="status">{noteSaving ? '正在保存' : noteDirty ? '有未保存修改' : '已保存'}</span>
      </div>
      {#if noteConflict}<p class="mt-1 text-xs text-danger" role="alert">备注已在其他标签页更新；草稿仍保留。取消编辑可载入最新备注，再继续修改。</p>{/if}
      {#if noteContextConflict}<p class="mt-1 text-xs text-danger" role="alert">备注所属练习会话已变化；草稿仍保留且不会写入其他会话。取消编辑可载入当前会话备注。</p>{/if}
      {#if !session && noteDirty}<p class="mt-1 text-xs text-mid-gray">这份草稿来自已结束的练习，无法写入新会话；取消编辑后可继续。</p>{/if}
    </div>
  {/if}
  {#if session}
    <p class="mt-1 text-xs text-mid-gray">已确认伴奏时长：{Math.round(session.slices.reduce((sum, slice) => sum + slice.durationMs, 0) / 1000)} 秒</p>
  {/if}
</section>
