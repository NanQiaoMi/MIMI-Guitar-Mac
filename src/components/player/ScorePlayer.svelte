<script lang="ts">
  import { untrack, onMount, onDestroy, tick } from 'svelte';
  import { AlphaTabApi, model, Environment, PlayerMode } from '@coderline/alphatab';
  import { installBrowserAr } from '../../lib/ar.browser';
  import { decodeIbeToJsonBrowser, extractScoreMeta } from '../../lib/ibe.browser';
  import { keySignatureName } from '../../lib/keyName.mjs';
  import { createScoreSettings } from '../../lib/playerSettings';
  import { GM_INSTRUMENTS } from '../../lib/gmInstruments';
  import { clampTargetBpm, clampTick, computePlaybackSpeed, formatMilliseconds, resolvePracticeTempo } from '../../lib/playbackSpeed.mjs';
  import { CAPO_OPTIONS, clampTranspose, totalTransposition, transposeKeyName } from '../../lib/pitch.mjs';
  import { DEFAULT_SCORE_DISPLAY_MODE, SCORE_DISPLAY_MODES, applyScoreDisplayMode, countTabTracks, replaceWholeRestsInSecondaryTracks } from '../../lib/scoreDisplayMode.mjs';
  import { preparePracticeResumeSettings } from '../../lib/practice/practiceProgress.ts';
  import { addLyricsTopSpacer } from '../../lib/scoreLyricsLayout.mjs';
  import { bassArticulationBoost, applyVelocityBoostToMidi } from '../../lib/bassArticulation.mjs';
  import { assertRenderableScore, runWithRollbackTransaction, safeScoreDownloadHref, scoreLoadFailurePresentation } from '../../lib/scoreLoadGuard.mjs';
  import { fetchScoreBytes } from '../../lib/scoreLoadRequest.mjs';
  import { acquireGuitarAudioSession, playProgramNote, getNoteMidi, setGlobalProgram, type GuitarAudioSession } from '../../lib/guitarSound.ts';
  import FloatingPlayerHUD from './FloatingPlayerHUD.svelte';
  import VirtualFretboard, { type ActiveNote } from './VirtualFretboard.svelte';
  import ScoreNoteSparkTrails from './ScoreNoteSparkTrails.svelte';
  import { unlockAudioContextImmediately, registerAudioContext, isIosDevice } from '../../lib/audioUnlocker';
  import { claimAudioFocus } from '../../lib/player/audioFocus.ts';
  import { isUkuleleScore, primaryStringTrackIndex } from '../../lib/player/scoreInstrument.ts';
  import { resolveResumeInstrument, sourceInstrumentFlavor, type ScoreInstrumentFlavor } from '../../lib/player/scoreInstrumentOverrides.ts';
  import { createFretboardAuditionLifecycle } from '../../lib/player/fretboardAuditionLifecycle.ts';
  import { planScoreAuditionSoundfonts } from '../../lib/player/scoreAuditionResources.ts';
  import { loadVerifiedScoreSoundfont, loadVerifiedScoreSoundfontPlan } from '../../lib/player/verifiedScoreSoundfont.ts';
  import { isSoundfontReceiptPoisoned, loadSoundfontWithReceipt } from '../../lib/player/soundfontLoadReceipt.ts';
  import { registerMotionSurface, surfaceMotion } from '../../lib/ui/motion';
  import type { PersonalScore, PlayerResume } from '../../lib/personal/types.ts';
  import PracticePanel from '../practice/PracticePanel.svelte';
  import { hashBytes } from '../../lib/personal/repository.ts';
  import { isValidPlaybackRatio } from '../../lib/practice/practiceProgress.ts';
  import { nativeTempoAtTick } from '../../lib/practice/nativeTempo.ts';
  import { seekWithReceipt } from '../../lib/practice/seekReceipt.ts';
  import { beginSeekPreview, observeSeekPreviewPosition, settleSeekPreview, updateSeekPreview, type SeekPreviewState } from '../../lib/player/seekPreview.ts';
  import { resolveManuscriptBarSeekTarget } from '../../lib/player/manuscriptSeek.mjs';
  import type { RegisterPracticeLeaveGuard } from '../../lib/practice/practiceLeaveGuard.ts';
  import {
    applyCapoSelection,
    beatLookupTick,
    captureSourceCapos,
    formatCapoValue,
    pausePositionRestoreTarget,
    practicePositionSnapshot,
    positionBeatMetadata,
    primarySourceCapo,
    resolvedCatalogScoreUrl,
    shouldIgnorePositionDuringSeek,
    shouldKeepVerifiedPracticeScore,
    sourceCapoSummary,
    trackVolumePercent,
  } from '../../lib/player/scorePlayerCorrectness.mjs';

  let {
    scoreUrl = '',
    title = '',
    artist = '',
    bpm = 0,
    capo,
    defaultTrack = 0,
    scoreKey = '',
    timeSig = '',
    category = '',
    practiceScore,
    onPracticeScoreVerified,
    onRegisterPracticeLeaveGuard,
  }: {
    scoreUrl?: string;
    title?: string;
    artist?: string;
    bpm?: number;
    capo?: number;
    defaultTrack?: number;
    scoreKey?: string;
    timeSig?: string;
    category?: string;
    practiceScore?: PersonalScore;
    onPracticeScoreVerified?: (verified: PersonalScore) => void;
    onRegisterPracticeLeaveGuard?: RegisterPracticeLeaveGuard;
  } = $props();

  let score: any = $state(null);
  let scoreJsonRaw: any = $state(null);
  function primaryTrackIndex(): number {
    return primaryStringTrackIndex(score?.tracks?.length ?? 0, defaultTrack, visibleTracks);
  }

  function primaryTrackTuning(): number[] | undefined {
    const staff = score?.tracks?.[primaryTrackIndex()]?.staves?.[0];
    const tuning = staff?.tuning ?? staff?.stringTuning?.tunings;
    return Array.isArray(tuning) ? tuning : undefined;
  }

  const isUkulele = $derived.by(() => isUkuleleScore(category, primaryTrackTuning()));

  const fretboardTuning = $derived.by(() => {
    if (isUkulele) {
      const tuning = primaryTrackTuning();
      if (tuning?.length === 4) {
        const CHROMATIC = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
        return tuning.map((midi: number) => {
          const note = CHROMATIC[midi % 12];
          const oct = Math.floor(midi / 12) - 1;
          return `${note}${oct}`;
        });
      }
      return ['A4', 'E4', 'C4', 'G4'];
    }
    return ['E4', 'B3', 'G3', 'D3', 'A2', 'E2'];
  });

  let container: HTMLDivElement | null = $state(null);
  let api: AlphaTabApi | null = $state(null);
  let loading = $state(true);
  let error = $state('');
  let exportBusy = $state(false);
  let exportMessage = $state('');
  let exportFailed = $state(false);
  let errorCanRetry = $state(true);
  let errorCanDownload = $state(false);
  let renderNotice = $state('');
  let transposePending = $state(false);
  let activeRenderWait: { api: AlphaTabApi; fail: (reason: unknown) => void } | null = null;
  const sourceDownloadHref = $derived(safeScoreDownloadHref(
    scoreUrl,
    typeof window !== 'undefined' ? window.location.origin : ''
  ));
  let loadTimeout: ReturnType<typeof setTimeout> | null = null;
  let scoreLoadedOnce = $state(false);
  // AlphaTab owns a Web Worker and a ScriptProcessor output. A retry must
  // invalidate every pending async continuation before a new instance exists,
  // otherwise an old worker can keep feeding audio into the same page.
  let loadGeneration = 0;
  let seekUiGeneration = $state(0);
  let playerAbort: AbortController | null = null;
  let disposePlayerEvents: (() => void) | null = null;

  // 控制状态
  let playing = $state(false);
  let audioFocusRelease: (() => void) | null = null;
  let audioFocusHeld = $state(false);
  let playbackRatio = $state(1);
  let lapInterruptionRevision = $state(0);
  let audioFocusRetainedForRender = false;
  let intentionalRestartPending = false;
  let pendingNaturalRestartTick: number | null = null;
  function interruptLoopLap(): void { lapInterruptionRevision++; }
  function setPlaybackRatio(target: number, targetBpm?: number): number {
    const currentApi = api;
    if (!currentApi) throw new Error('播放器尚未加载');
    if (!isValidPlaybackRatio(target)) throw new RangeError('播放倍率必须在 0.125× 到 8× 之间');
    const previous = currentApi.playbackSpeed;
    currentApi.playbackSpeed = target;
    const actual = currentApi.playbackSpeed;
    if (!isValidPlaybackRatio(actual) || Math.abs(actual - target) > 0.0001) {
      currentApi.playbackSpeed = previous;
      playbackRatio = currentApi.playbackSpeed;
      throw new Error('播放器未能应用请求倍率');
    }
    playbackRatio = actual;
    if (targetBpm !== undefined) {
      speed = clampTargetBpm(targetBpm);
      displayTempo = targetBpm;
    }
    return actual;
  }
  let resumeIntentRevision = $state(0);
  let playbackIntentGeneration = 0;
  function markResumeIntent(): void { resumeIntentRevision++; }
  let practiceScoreRef: PersonalScore | null = $state(practiceScore ?? null);
  $effect(() => {
    if (!practiceScore || shouldKeepVerifiedPracticeScore(practiceScoreRef, practiceScore)) return;
    practiceScoreRef = practiceScore;
  });

  function inferCatalogSourceId(url: string): string {
    if (typeof window !== 'undefined') {
      const routeId = window.location.pathname.match(/^\/(?:tabs|ukulele)\/([^/]+)/)?.[1];
      if (routeId) return decodeURIComponent(routeId);
    }
    return url.match(/\/storage\/scores\/([^/.]+)/)?.[1] ?? url.split('/').pop()?.replace(/\.[^.]+$/, '') ?? 'unknown-score';
  }
  let speed = $state(clampTargetBpm(bpm || 80));
  // 谱面内置速度只用于换算 AlphaTab 的播放倍率；speed 是用户所见的目标 BPM。
  let sourceTempo = $state(80);
  let metronome = $state(false);
  let countIn = $state(false);
  let loopArmed = $state(false);
  let loopStartSet = $state(false);
  let loopEndSet = $state(false);
  let loopStartTick = $state(1);
  let loopEndTick = $state(1);
  let loopActive = $state(false);
  let loopGeneration = $state(0);
  let completedLoopLap = $state<{ generation: number; sequence: number; startTick: number; endTick: number } | null>(null);
  let fontScale = $state(1);
  let numberTab = $state(true); // 数字谱默认开启：六线谱+简谱都显示；关闭时仅保留六线谱
  // 谱面显示模式：'mixed'=主音轨六线谱+其余音轨简谱（参考站默认）；'tab'=全部六线谱（可切换）
  let scoreDisplayMode = $state(DEFAULT_SCORE_DISPLAY_MODE);
  // 和弦显示模式：'name'=仅字母（参考站默认）；'diagram'=字母+完整指法图逐位内联（增强）
  let chordMode = $state<'name' | 'diagram'>('diagram');
  // 变调夹（-1=降半调调弦, 0=不夹；无显式覆盖时使用每轨原谱值）与整曲转调（±12 半音）
  let sourceStaffCapos = $state<number[][]>([]);
  let useSourceCapo = $state(untrack(() => capo === undefined));
  let capoMode = $state(untrack(() => capo ?? 0));
  let transpose = $state(0);
  let capoMenuOpen = $state(false);
  let capoMenuRoot: HTMLDivElement | undefined;
  let capoTrigger: HTMLButtonElement | undefined;
  // key header info
  let displayKey = $state('');
  let displayTimeSig = $state('');
  let displayTempo = $state(0);

  // 实时位置指示
  let curTick = $state(0);
  let curTime = $state(0);
  let naturalEndPosition = $state<{ tick: number; timeMs: number } | null>(null);
  let lastConfirmedPosition = $state<{ tick: number; timeMs: number } | null>(null);
  let endTick = $state(0);
  let endTime = $state(0);
  let curBar = $state(0);
  let curBeat = $state(0);
  let currentBeatEndTick = $state(0);
  let currentTickIsSeek = $state(false);
  let currentRepeatAmbiguous = $state(false);
  let dragging = $state(false);
  let dragTick = $state(0);
  let seekPreviewState = $state<SeekPreviewState | null>(null);
  let pendingSeek = $state<{ id: number; tick: number } | null>(null);
  type PausePositionCapture = {
    api: AlphaTabApi;
    loadGeneration: number;
    intentGeneration: number;
    tick: number;
    timeMs: number;
    unfoldedBeatStartTick: number | null;
    sourceBeatStartTick: number | null;
    rangeStartTick: number | null;
    rangeEndTick: number | null;
  };
  let pendingPausePositionRestore = $state<PausePositionCapture | null>(null);
  let seekSequence = 0;
  let seekAbort: AbortController | null = null;
  let lastPosUpdate = $state(0);

  // 音源加载
  let loadingSounds = $state(false);
  let soundReady = $state(false);
  let soundError = $state('');
  let playRequested = $state(false);

  // iOS 设备静音拨片与音量提示：播放时提示，4 秒后淡出消失
  let showIosSilentHint = $state(false);
  let iosHintTimer: ReturnType<typeof setTimeout> | null = null;

  $effect(() => {
    if (playing) {
      if (isIosDevice()) {
        showIosSilentHint = true;
        if (iosHintTimer) clearTimeout(iosHintTimer);
        iosHintTimer = setTimeout(() => {
          showIosSilentHint = false;
          iosHintTimer = null;
        }, 4000);
      }
    } else {
      if (iosHintTimer) {
        clearTimeout(iosHintTimer);
        iosHintTimer = null;
      }
      showIosSilentHint = false;
    }
  });

  // 音轨
  type PlayerTrackState = {
    index: number;
    name: string;
    sourceName: string;
    program: number;
    sourceProgram: number;
    sourceFlavor: ScoreInstrumentFlavor;
    instrumentFlavor: ScoreInstrumentFlavor;
    instrumentOverride: boolean;
    percussion: boolean;
    show: boolean;
    muted: boolean;
    soloed: boolean;
    volume: number;
  };
  type PlayerReloadSnapshot = {
    scoreId?: string;
    tracks: PlayerTrackState[];
    position: { tick: number; timeMs: number };
  };
  let tracks = $state<PlayerTrackState[]>([]);
  let pendingPlayerReloadSnapshot: PlayerReloadSnapshot | null = null;
  let restoringPlayerReloadSnapshot = false;
  const primaryInstrumentTrack = $derived(tracks.find((track) => track.index === primaryTrackIndex()) ?? tracks[0] ?? null);
  let pendingExternalInstrumentSelection: { program: number; scoreId?: string } | null = null;
  const fretboardAudition = createFretboardAuditionLifecycle<GuitarAudioSession>();
  let practiceTrackMix = $derived(tracks.map((track) => {
    return {
      index: track.index,
      muted: track.muted,
      soloed: track.soloed,
      volume: track.volume,
      // Persist the source program unless the user deliberately selected a GM override.
      program: Math.max(0, Math.min(127, track.instrumentOverride ? track.program : track.sourceProgram)),
      instrumentOverride: track.instrumentOverride,
    };
  }));
  let visibleTracks = $state<number[]>([]);
  let showTracksPanel = $state(false);
  let showInstrumentsPanel = $state(false);
  const tracksPanelId = 'score-player-tracks-panel';
  const instrumentsPanelId = 'score-player-instruments-panel';
  let lastTracksPanelTrigger: HTMLButtonElement | null = null;
  let lastInstrumentsPanelTrigger: HTMLButtonElement | null = null;
  let desktopTracksPanelTrigger: HTMLButtonElement | null = null;
  let desktopInstrumentsPanelTrigger: HTMLButtonElement | null = null;
  let showFretboard = $state(false);
  let practiceDisplay = $derived({ fontScale, chordMode, scoreDisplayMode: (scoreDisplayMode === SCORE_DISPLAY_MODES.ALL_TAB ? 'tab' : 'mixed') as 'tab' | 'mixed', numberTab, showFretboard });
  let liveActiveNotes = $state<ActiveNote[]>([]);
  let liveCurrentChord = $state('');
  let scorePlayerCard: HTMLDivElement | null = $state(null);
  // 全屏乐谱显示：隐藏页面所有元素，乐谱充满整个视口
  let isFullscreen = $state(false);
  let fullscreenSettingsOpen = $state(false);
  let fullscreenEntryTrigger: HTMLButtonElement | null = null;
  let fullscreenExitTrigger = $state<HTMLButtonElement | null>(null);
  let fullscreenFocusSequence = 0;
  let fullscreenComponentDestroyed = false;
  // 移动端滚动吸顶：当卡片顶部接近视口时，切换为 fixed 定位
  let isScoreFixed = $state(false);

  function toggleTracksPanel(event: MouseEvent) {
    if (event.currentTarget instanceof HTMLButtonElement) {
      lastTracksPanelTrigger = event.currentTarget;
    }
    const next = !showTracksPanel;
    showTracksPanel = next;
    if (next) showInstrumentsPanel = false;
  }

  function toggleInstrumentsPanel(event: MouseEvent) {
    if (event.currentTarget instanceof HTMLButtonElement) {
      lastInstrumentsPanelTrigger = event.currentTarget;
    }
    const next = !showInstrumentsPanel;
    showInstrumentsPanel = next;
    if (next) showTracksPanel = false;
  }

  function focusAvailableTrigger(...candidates: Array<HTMLButtonElement | null>) {
    const trigger = candidates.find((candidate) =>
      candidate?.isConnected && !candidate.disabled && candidate.getClientRects().length > 0
    );
    trigger?.focus();
  }

  function closeTracksPanelOnEscape(event: KeyboardEvent) {
    if (event.key !== 'Escape') return;
    event.preventDefault();
    event.stopPropagation();
    showTracksPanel = false;
    focusAvailableTrigger(lastTracksPanelTrigger, desktopTracksPanelTrigger);
  }

  function closeInstrumentsPanelOnEscape(event: KeyboardEvent) {
    if (event.key !== 'Escape') return;
    event.preventDefault();
    event.stopPropagation();
    showInstrumentsPanel = false;
    focusAvailableTrigger(lastInstrumentsPanelTrigger, desktopInstrumentsPanelTrigger);
  }

  function canFocusFullscreenTrigger(trigger: HTMLButtonElement | null): trigger is HTMLButtonElement {
    return !!trigger && trigger.isConnected && !trigger.disabled &&
      trigger.getClientRects().length > 0 &&
      !trigger.closest('[hidden], [inert], [aria-hidden="true"]') &&
      getComputedStyle(trigger).visibility !== 'hidden';
  }

  function focusAfterFullscreenRender(
    target: () => HTMLButtonElement | null,
    expectedFullscreen: boolean,
  ) {
    const sequence = ++fullscreenFocusSequence;
    void tick().then(() => {
      if (fullscreenComponentDestroyed || sequence !== fullscreenFocusSequence || isFullscreen !== expectedFullscreen) return;
      const trigger = target();
      if (canFocusFullscreenTrigger(trigger)) trigger.focus({ preventScroll: true });
    });
  }

  function exitFullscreen(nativeAlreadyExited = false) {
    if (!isFullscreen) return;
    const entryTrigger = fullscreenEntryTrigger;
    isFullscreen = false;
    fullscreenSettingsOpen = false;
    if (typeof document !== 'undefined') {
      document.body.classList.remove('score-fullscreen-lock');
      if (!nativeAlreadyExited && document.fullscreenElement === scorePlayerCard) {
        try {
          void document.exitFullscreen().catch(() => {});
        } catch {
          // CSS fullscreen has already ended; keep the control usable if the
          // browser rejects the native exit synchronously.
        }
      }
    }
    focusAfterFullscreenRender(() => entryTrigger, false);
  }

  function toggleFullscreen(event: MouseEvent) {
    if (isFullscreen) {
      exitFullscreen();
      return;
    }

    if (event.currentTarget instanceof HTMLButtonElement) {
      fullscreenEntryTrigger = event.currentTarget;
    }
    isFullscreen = true;
    if (typeof document !== 'undefined') {
      document.body.classList.add('score-fullscreen-lock');
    }
    focusAfterFullscreenRender(() => fullscreenExitTrigger, true);

    // Put the player in the browser top layer when supported, so sticky site
    // navigation and transformed layout ancestors cannot cover it.
    const card = scorePlayerCard;
    if (card && typeof card.requestFullscreen === 'function') {
      try {
        void card.requestFullscreen().then(() => {
          // A very fast Escape/unmount can race the browser's fullscreen promise.
          // Do not leave a detached or already-closed card in the top layer.
          if ((fullscreenComponentDestroyed || !isFullscreen) && document.fullscreenElement === card) {
            return document.exitFullscreen().catch(() => {});
          }
        }).catch(() => {}); // iOS Safari 等不支持时静默降级为 CSS 全屏
      } catch {
        // Browsers may reject fullscreen before returning a promise; CSS mode
        // remains available and its exit control still receives focus.
      }
    }
  }

  $effect(() => {
    if (typeof window === 'undefined') return;
    const onFsChange = () => {
      if (document.fullscreenElement === scorePlayerCard) {
        // A pending request may complete after the user has already exited.
        if (!isFullscreen && scorePlayerCard) {
          try {
            void document.exitFullscreen().catch(() => {});
          } catch {
            // The state transition already restored the regular layout.
          }
        }
        return;
      }
      // 用户通过系统手势/按键退出原生全屏时，同步退出 CSS 全屏并归还焦点。
      if (isFullscreen) exitFullscreen(true);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isFullscreen) exitFullscreen();
    };
    document.addEventListener('fullscreenchange', onFsChange);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('fullscreenchange', onFsChange);
      document.removeEventListener('keydown', onKey);
      if (typeof document !== 'undefined') document.body.classList.remove('score-fullscreen-lock');
    };
  });

  onDestroy(() => {
    fretboardAudition.dispose();
    fullscreenComponentDestroyed = true;
    fullscreenFocusSequence++;
    if (typeof document !== 'undefined') {
      document.body.classList.remove('score-fullscreen-lock');
      if (scorePlayerCard && document.fullscreenElement === scorePlayerCard) {
        try {
          void document.exitFullscreen().catch(() => {});
        } catch {
          // Component teardown must not fail because a browser cannot exit.
        }
      }
    }
    fullscreenEntryTrigger = null;
    fullscreenExitTrigger = null;
  });

  // 短视口（横屏手机）滚动吸顶：当卡片接近视口顶部时切换 fixed 定位
  onMount(() => {
    if (typeof window === 'undefined' || window.innerHeight >= 600) return;
    // 使用 scroll 事件监听，比 IntersectionObserver 更可靠
    const checkScroll = () => {
      const el = document.querySelector('.score-player-card');
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const shouldFix = rect.top < 0;
      if (shouldFix !== isScoreFixed) {
        isScoreFixed = shouldFix;
        document.body.classList.toggle('score-fixed-active', shouldFix);
      }
    };
    // 初始化检查一次
    checkScroll();
    window.addEventListener('scroll', checkScroll, { passive: true });
    return () => window.removeEventListener('scroll', checkScroll);
  });

  const baseScale = typeof window !== 'undefined' && window.innerWidth < 640 ? 1.0 : 0.84;

  function instrumentName(program: number): string {
    return GM_INSTRUMENTS[program]?.[1] ?? '乐器';
  }

  function isPercussionTrack(track: any): boolean {
    return track?.isPercussion === true || (track?.staves ?? []).some((staff: any) => staff?.isPercussion === true);
  }

  function trackTuning(track: any): number[] | undefined {
    for (const staff of track?.staves ?? []) {
      const tuning = staff?.tuning ?? staff?.stringTuning?.tunings;
      if (Array.isArray(tuning)) return tuning;
    }
    return undefined;
  }

  function sourceNameFor(program: number, flavor: ScoreInstrumentFlavor): string {
    if (flavor === 'ukulele') {
      const preset = program === 0 ? '原声' : program === 24 ? '尼龙弦' : '钢弦';
      return `原谱 · 尤克里里（${preset}）`;
    }
    return `原谱 · ${instrumentName(program)}`;
  }

  function scoreIdentity(): string | undefined {
    return practiceScoreRef?.sourceId || practiceScoreRef?.id || inferCatalogSourceId(scoreUrl) || undefined;
  }

  function publishPrimaryInstrumentSelection(): void {
    const primary = primaryInstrumentTrack;
    if (!primary || primary.percussion) return;
    setGlobalProgram(primary.program, {
      source: 'player',
      broadcast: true,
      flavor: primary.instrumentFlavor,
      instrumentOverride: primary.instrumentOverride,
      scoreId: scoreIdentity(),
    });
  }

  function pendingSelectionMatchesCurrentScore(): boolean {
    const pending = pendingExternalInstrumentSelection;
    if (!pending) return false;
    if (!pending.scoreId) return true;
    const identity = scoreIdentity();
    return !identity || identity === pending.scoreId || identity === `catalog:${pending.scoreId}`;
  }

  function applyPendingExternalInstrumentSelection(beforeInitialRender = false): void {
    if (!pendingSelectionMatchesCurrentScore() || !tracks.length) return;
    if (loading && !beforeInitialRender) return;
    const index = tracks.findIndex((track) => track.index === primaryTrackIndex());
    if (index < 0 || tracks[index].percussion) return;
    const target = pendingExternalInstrumentSelection!.program;
    pendingExternalInstrumentSelection = null;
    if (beforeInitialRender) {
      const selected = tracks[index];
      const scoreTrack = score?.tracks?.[selected.index];
      if (!scoreTrack) return;
      const name = applyTrackInstrument(scoreTrack, target);
      tracks = tracks.map((track, trackIndex) => trackIndex === index
        ? { ...track, program: target, name, instrumentOverride: true, instrumentFlavor: 'gm' }
        : track);
      return;
    }
    void changeInstrument(index, target);
  }

  function confirmPracticePosition(tick: number, timeMs: number, scoreEndTick = api?.endTick ?? endTick): void {
    lastConfirmedPosition = {
      tick: clampTick(tick, scoreEndTick),
      timeMs: Number.isFinite(timeMs) && timeMs >= 0 ? timeMs : lastConfirmedPosition?.timeMs ?? 0,
    };
  }

  function getPracticePositionSnapshot(): { tick: number; timeMs: number } {
    return practicePositionSnapshot(lastConfirmedPosition, { tick: curTick, timeMs: curTime }, naturalEndPosition);
  }

  function clearSeekPreview(): void {
    seekPreviewState = null;
    dragging = false;
    dragTick = clampTick(curTick, endTick);
  }

  function cancelSeekPreview(): void {
    const state = seekPreviewState;
    if (!state) {
      dragging = false;
      return;
    }
    const outcome = settleSeekPreview(state, loadGeneration, 'cancel');
    seekPreviewState = null;
    dragging = false;
    if (outcome?.kind !== 'cancel') return;

    curTick = clampTick(outcome.position.tick, api?.endTick ?? endTick);
    curTime = outcome.position.timeMs;
    confirmPracticePosition(curTick, curTime, api?.endTick ?? endTick);
    currentTickIsSeek = false;
    if (api) updatePositionBeatMetadata(api, curTick, api.endTick);
  }

  function clearPendingPausePositionRestore(): void {
    pendingPausePositionRestore = null;
  }

  function capturePausePosition(currentApi: AlphaTabApi, intentGeneration: number): PausePositionCapture {
    const position = getPracticePositionSnapshot();
    const tick = clampTick(position.tick, currentApi.endTick);
    let unfoldedBeatStartTick: number | null = null;
    let sourceBeatStartTick: number | null = null;
    try {
      const lookup = currentApi.tickCache?.findBeat(new Set(visibleTracks), beatLookupTick(tick, currentApi.endTick));
      if (lookup && typeof lookup.start === 'number' && Number.isSafeInteger(lookup.start)) {
        unfoldedBeatStartTick = lookup.start;
      }
      const sourceStart = lookup?.beat ? currentApi.tickCache?.getBeatStart(lookup.beat) : null;
      if (typeof sourceStart === 'number' && Number.isSafeInteger(sourceStart)) sourceBeatStartTick = sourceStart;
    } catch {
      // Without a trustworthy unfolded/source pair, keep the saved tick and do not infer a repeat remap.
    }
    return {
      api: currentApi,
      loadGeneration,
      intentGeneration,
      tick,
      timeMs: position.timeMs,
      unfoldedBeatStartTick,
      sourceBeatStartTick,
      rangeStartTick: loopActive ? loopStartTick : null,
      rangeEndTick: loopActive ? loopEndTick : null,
    };
  }

  function resumeAfterPauseIfRemapped(currentApi: AlphaTabApi, reportedTick: number): boolean {
    const captured = pendingPausePositionRestore;
    if (!captured) return false;
    if (captured.api !== currentApi || captured.loadGeneration !== loadGeneration
      || captured.intentGeneration !== playbackIntentGeneration) {
      clearPendingPausePositionRestore();
      return false;
    }
    const target = pausePositionRestoreTarget(captured, reportedTick);
    if (target === null) return false;
    clearPendingPausePositionRestore();
    // The receipt is the boundary that prevents the stale SDK pause seek from becoming durable progress.
    void seekPracticePosition(target).catch(() => {});
    return true;
  }

  function cancelPendingSeek(): void {
    seekSequence++;
    seekAbort?.abort();
    seekAbort = null;
    pendingSeek = null;
  }

  async function seekPracticePosition(tick: number): Promise<{ tick: number; timeMs: number }> {
    const currentApi = api;
    const generation = loadGeneration;
    if (!currentApi || !score || loading) return Promise.reject(new Error('播放器尚未就绪。'));
    const previousPosition = getPracticePositionSnapshot();
    clearPendingPausePositionRestore();
    naturalEndPosition = null;
    markResumeIntent();
    cancelPendingSeek();
    const id = ++seekSequence;
    const controller = new AbortController();
    seekAbort = controller;
    pendingSeek = { id, tick };
    renderNotice = '';
    try {
      const receipt = await seekWithReceipt({
        tick,
        isCurrent: () => isCurrentApi(currentApi, generation) && pendingSeek?.id === id,
        signal: controller.signal,
        subscribe: (listener) => currentApi.playerPositionChanged.on(listener),
        seek: () => { currentApi.tickPosition = tick; },
      });
      if (!isCurrentApi(currentApi, generation) || pendingSeek?.id !== id) {
        throw new Error('播放器已更新，位置跳转已取消。');
      }
      curTick = clampTick(receipt.tick, currentApi.endTick);
      curTime = receipt.timeMs;
      confirmPracticePosition(curTick, curTime, currentApi.endTick);
      currentTickIsSeek = true;
      updatePositionBeatMetadata(currentApi, curTick, currentApi.endTick);
      return receipt;
    } catch (reason) {
      if (isCurrentApi(currentApi, generation) && pendingSeek?.id === id) {
        curTick = clampTick(previousPosition.tick, currentApi.endTick);
        if (Number.isFinite(previousPosition.timeMs) && previousPosition.timeMs >= 0) curTime = previousPosition.timeMs;
        confirmPracticePosition(curTick, curTime, currentApi.endTick);
        currentTickIsSeek = false;
        updatePositionBeatMetadata(currentApi, curTick, currentApi.endTick);
        if (!controller.signal.aborted) {
          renderNotice = reason instanceof Error ? reason.message : '位置跳转未能确认，请重试。';
        }
      }
      throw reason;
    } finally {
      if (pendingSeek?.id === id) pendingSeek = null;
      if (seekAbort === controller) seekAbort = null;
    }
  }

  type ManuscriptBarSeekResult =
    | { ok: true; occurrence: number; occurrenceCount: number }
    | { ok: false; message: string };

  type ManuscriptBarSeekRequest = {
    barIndex: number;
    onResult?: (result: ManuscriptBarSeekResult) => void;
  };

  function handleManuscriptBarSeek(event: Event): void {
    const requestEvent = event as CustomEvent<ManuscriptBarSeekRequest>;
    const request = requestEvent.detail;
    if (!request || !Number.isSafeInteger(request.barIndex) || request.barIndex < 0) return;

    // Claim the request synchronously so the manuscript can report an
    // unavailable player instead of claiming a seek happened when none did.
    event.preventDefault();
    const currentApi = api;
    if (!currentApi || !score || loading) {
      request.onResult?.({ ok: false, message: '播放器尚未就绪，暂未同步该小节。' });
      return;
    }

    const currentPosition = getPracticePositionSnapshot();
    const target = resolveManuscriptBarSeekTarget(
      currentApi.tickCache,
      request.barIndex,
      clampTick(currentPosition.tick, currentApi.endTick),
    );
    if (!target) {
      const message = `第 ${request.barIndex + 1} 小节不在当前可定位的播放序列中。`;
      renderNotice = message;
      request.onResult?.({ ok: false, message });
      return;
    }

    void seekPracticePosition(target.tick).then(() => {
      request.onResult?.({
        ok: true,
        occurrence: target.occurrence,
        occurrenceCount: target.occurrenceCount,
      });
    }).catch((reason) => {
      request.onResult?.({
        ok: false,
        message: reason instanceof Error ? reason.message : '位置跳转未能确认，请重试。',
      });
    });
  }

  function buildTracks(sourceScore: any = score) {
    const list: PlayerTrackState[] = [];
    visibleTracks = [];
    for (let i = 0; i < (sourceScore?.tracks?.length ?? 0); i++) {
      const t = sourceScore.tracks[i];
      const originalName = String(t.name ?? '');
      const name = originalName;
      if (name === '@$Strumming$@' || name === '@$Chords$@') continue;
      const rawProgram = Number(t.playbackInfo?.program);
      const sourceProgram = Number.isInteger(rawProgram) && rawProgram >= 0 && rawProgram <= 127 ? rawProgram : 0;
      const percussion = isPercussionTrack(t);
      const program = percussion ? 128 : sourceProgram;
      const sourceFlavor = sourceInstrumentFlavor(category || practiceScoreRef?.category || '', trackTuning(t), sourceProgram);
      const sourceName = percussion ? '打击乐' : sourceNameFor(sourceProgram, sourceFlavor);
      const show = true;
      visibleTracks.push(i);
      const vol = trackVolumePercent(t.playbackInfo?.volume);
      const displayName = percussion ? sourceName : sourceName || name || `音轨 ${i + 1}`;
      t.mimiInstrumentOverride = false;
      t.mimiSoundfontFlavor = sourceFlavor;
      t.name = displayName;
      t.shortName = displayName;
      list.push({
        index: i,
        name: displayName,
        sourceName: displayName,
        program,
        sourceProgram,
        sourceFlavor,
        instrumentFlavor: sourceFlavor,
        instrumentOverride: false,
        percussion,
        show,
        muted: false,
        soloed: false,
        volume: vol,
      });
    }
    if (visibleTracks.length === 0) visibleTracks = [0];
    tracks = list;
  }

  function updatePositionBeatMetadata(currentApi: AlphaTabApi, tick: number, scoreEndTick: number): void {
    const lookupTick = beatLookupTick(tick, scoreEndTick);
    const lookup = currentApi.tickCache?.findBeat(new Set(visibleTracks), lookupTick);
    const metadata = positionBeatMetadata(lookup, tick, scoreEndTick);
    curBar = metadata.bar;
    curBeat = metadata.beat;
    currentBeatEndTick = metadata.beatEndTick;
    currentRepeatAmbiguous = metadata.repeatAmbiguous;
  }

  /** Warm the verified shared GM bank and isolated Uke preset used by this player. */
  async function prewarmSoundFontCache() {
    if (typeof window === 'undefined') return;
    const prewarm = async () => {
      try {
        await Promise.all([
          loadVerifiedScoreSoundfont({ bank: 0, program: 25, flavor: 'gm' }),
          loadVerifiedScoreSoundfont({ bank: 0, program: 25, flavor: 'ukulele' }),
        ]);
      } catch {
        // Best-effort warmup; the verified loader reports a useful error when playback is requested.
      }
    };
    if ('requestIdleCallback' in window) {
      (window as any).requestIdleCallback(() => void prewarm(), { timeout: 3000 });
    } else {
      setTimeout(() => void prewarm(), 1200);
    }
  }

  /** Use a per-request AlphaTab receipt; generic events cannot safely be reused after timeout. */
  async function loadSoundFontAwait(
    currentApi: AlphaTabApi,
    generation: number,
    signal: AbortSignal,
    data: Uint8Array,
    append: boolean = false
  ): Promise<'ok' | 'error' | 'timeout' | 'cancelled'> {
    if (!isCurrentApi(currentApi, generation) || signal.aborted || !data?.length) return 'cancelled';
    const receipt = await loadSoundfontWithReceipt(currentApi as any, data, append, { signal, timeoutMs: 15000 });
    if (!isCurrentApi(currentApi, generation) || signal.aborted || receipt.status === 'cancelled') return 'cancelled';
    if (receipt.status === 'loaded') return 'ok';
    if (receipt.status === 'timeout') return 'timeout';
    if (receipt.error) console.error('[ScorePlayer] loadSoundFont error:', receipt.error);
    return 'error';
  }

  async function placeNaturalRestartPosition(
    currentApi: AlphaTabApi,
    generation: number,
    intentGeneration: number,
  ): Promise<{ tick: number; loopRestart: boolean } | null> {
    if (pendingNaturalRestartTick === null) return null;
    const hasActiveLoop = loopActive && Number.isSafeInteger(loopStartTick)
      && Number.isSafeInteger(loopEndTick) && loopStartTick >= 0
      && loopEndTick > loopStartTick && loopEndTick <= currentApi.endTick;
    if (hasActiveLoop) {
      currentApi.isLooping = true;
      const range = currentApi.playbackRange;
      if (!range || range.startTick !== loopStartTick || range.endTick !== loopEndTick) {
        // AlphaTab's range setter itself seeks to A; only assign it when the range is stale.
        currentApi.playbackRange = { startTick: loopStartTick, endTick: loopEndTick };
      }
      await seekPracticePosition(loopStartTick);
      if (!isCurrentApi(currentApi, generation) || intentGeneration !== playbackIntentGeneration) {
        throw new Error('播放器已更新，循环起点恢复已取消。');
      }
      return { tick: loopStartTick, loopRestart: true };
    }

    currentApi.tickPosition = 0;
    curTick = 0;
    curTime = 0;
    confirmPracticePosition(0, 0, currentApi.endTick);
    curBar = 0;
    curBeat = 0;
    return { tick: 0, loopRestart: false };
  }

  // 记录当前完整有序银行计划。计划变化时必须从头重载，避免 AlphaTab 的 last-match 预设覆盖关系被破坏。
  let loadedPrograms = new Set<number>();
  let loadedSoundfontPlanKey: string | null = null;
  // 音源加载串行化：快速连续切换乐器时排队执行，绝不因 loadingSounds 守卫静默跳过
  let soundLoadChain: Promise<void> = Promise.resolve();

  function isCurrentApi(currentApi: AlphaTabApi | null, generation: number): currentApi is AlphaTabApi {
    return !!currentApi && api === currentApi && loadGeneration === generation;
  }

  function disposeActivePlayer() {
    fretboardAudition.invalidate();
    clearSeekPreview();
    clearPendingPausePositionRestore();
    cancelPendingSeek();
    playbackIntentGeneration++;
    playRequested = false;
    audioFocusRelease?.();
    audioFocusRelease = null;
    audioFocusHeld = false;
    audioFocusRetainedForRender = false;
    intentionalRestartPending = false;
    playerAbort?.abort();
    playerAbort = null;
    disposePlayerEvents?.();
    disposePlayerEvents = null;

    const previousApi = api;
    if (previousApi && activeRenderWait?.api === previousApi) {
      activeRenderWait.fail(new Error('乐谱渲染已取消'));
    }
    api = null;
    if (typeof window !== 'undefined' && (window as any).__api === previousApi) {
      (window as any).__api = null;
    }
    try {
      previousApi?.destroy();
    } catch (e) {
      console.warn('[ScorePlayer] player cleanup failed:', e);
    }

    loadedPrograms = new Set<number>();
    loadedSoundfontPlanKey = null;
    soundLoadChain = Promise.resolve();
    playing = false;
    loadingSounds = false;
    soundReady = false;
    playRequested = false;
  }

  function scoreSoundfontPlanKey(plan: ReturnType<typeof planScoreAuditionSoundfonts>): string | null {
    return plan.ok
      ? plan.presets.map(({ bank, program, flavor }) => `${bank}:${program}:${flavor}`).join('|')
      : null;
  }

  function scoreSoundfontConflictMessage(plan: Extract<ReturnType<typeof planScoreAuditionSoundfonts>, { ok: false }>): string {
    return `bank ${plan.bank} program ${plan.program} 同时需要 GM 与原谱尤克里里音源，当前音轨组合无法安全播放。播放已暂停；请恢复冲突音轨的原谱音色，或调整另一条音轨。`;
  }

  function failClosedForSoundfontConflict(
    plan: Extract<ReturnType<typeof planScoreAuditionSoundfonts>, { ok: false }>,
  ): void {
    const message = scoreSoundfontConflictMessage(plan);
    playbackIntentGeneration++;
    playRequested = false;
    pendingNaturalRestartTick = null;
    interruptLoopLap();
    api?.pause();
    playing = false;
    audioFocusRetainedForRender = false;
    audioFocusRelease?.();
    audioFocusRelease = null;
    audioFocusHeld = false;
    soundReady = false;
    soundError = message;
    renderNotice = message;
  }

  async function doLoadSoundfonts(currentApi: AlphaTabApi, generation: number, signal: AbortSignal) {
    if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
    const wasPlaying = playing;
    loadingSounds = true;
    soundError = '';
    let requestedPlanKey: string | null = null;
    let loadFailure: unknown = null;
    try {
      const plan = planScoreAuditionSoundfonts(score?.tracks, category);
      if (!plan.ok) {
        throw new Error(`音轨的 MIDI 音色 ${plan.bank}:${plan.program} 需要互相冲突的音源，无法安全播放。`);
      }
      requestedPlanKey = scoreSoundfontPlanKey(plan);
      if (plan.presets.length === 0 || !requestedPlanKey) throw new Error('当前乐谱没有可用的音色库计划。');

      if (loadedSoundfontPlanKey !== requestedPlanKey) {
        // A previous attempt may have partially replaced AlphaTab's banks.
        // Never treat those banks as ready; start the next complete plan with append=false.
        loadedSoundfontPlanKey = null;
        loadedPrograms = new Set<number>();
        soundReady = false;

        const soundfonts = await loadVerifiedScoreSoundfontPlan(plan.presets, signal);
        if (soundfonts.length === 0) throw new Error('已验证的音色库计划为空。');
        if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
        const fetchedPlan = planScoreAuditionSoundfonts(score?.tracks, category);
        if (!fetchedPlan.ok || scoreSoundfontPlanKey(fetchedPlan) !== requestedPlanKey) return;

        for (let index = 0; index < soundfonts.length; index++) {
          const currentPlan = planScoreAuditionSoundfonts(score?.tracks, category);
          if (!currentPlan.ok || scoreSoundfontPlanKey(currentPlan) !== requestedPlanKey) return;
          if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
          if (!soundfonts[index]?.bytes?.length) {
            throw new Error(`音色库 ${soundfonts[index]?.url ?? 'unknown'} 内容为空。`);
          }
          await new Promise((resolve) => setTimeout(resolve, 0));
          const result = await loadSoundFontAwait(
            currentApi,
            generation,
            signal,
            soundfonts[index].bytes,
            index > 0,
          );
          if (result === 'cancelled') return;
          if (result !== 'ok') {
            throw new Error(`音色库 ${soundfonts[index].url} 加载${result === 'timeout' ? '超时' : '失败'}。`);
          }
        }

        const loadedPlan = planScoreAuditionSoundfonts(score?.tracks, category);
        if (!loadedPlan.ok || scoreSoundfontPlanKey(loadedPlan) !== requestedPlanKey) return;
        loadedSoundfontPlanKey = requestedPlanKey;
      }

      const currentPlan = planScoreAuditionSoundfonts(score?.tracks, category);
      if (!currentPlan.ok || scoreSoundfontPlanKey(currentPlan) !== requestedPlanKey) return;
      // The complete plan also covers instrument automations and percussion.
      // Rebuild this current-track set even when 24/25 share the same fast bank.
      loadedPrograms = new Set(tracks.map((track) => track.program));
    } catch (error) {
      loadFailure = error;
      loadedSoundfontPlanKey = null;
      loadedPrograms = new Set<number>();
      soundReady = false;
    } finally {
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
      loadingSounds = false;
      const latestPlan = planScoreAuditionSoundfonts(score?.tracks, category);
      const latestPlanKey = scoreSoundfontPlanKey(latestPlan);
      // A newer instrument selection queued a different plan. Its queued load owns readiness/error state.
      if (latestPlanKey !== requestedPlanKey) {
        soundReady = false;
        return;
      }

      if (loadFailure) {
        soundError = loadFailure instanceof Error
          ? loadFailure.message
          : `音色库加载失败：${String(loadFailure)}`;
        soundReady = false;
      } else {
        const requiredPrograms = [...new Set(tracks.map((track) => track.program))];
        soundReady = requiredPrograms.length > 0
          && loadedSoundfontPlanKey === latestPlanKey
          && requiredPrograms.every((program) => loadedPrograms.has(program));
      }

      if (!soundReady) {
        if (!soundError) soundError = '音源加载失败或超时，播放器尚未就绪。请重试。';
        audioFocusRelease?.();
        audioFocusRelease = null;
        audioFocusHeld = false;
        playRequested = false;
      } else if ((wasPlaying || playRequested) && audioFocusHeld) {
        const restartIntent = playbackIntentGeneration;
        playRequested = false;
        const restartTick = pendingNaturalRestartTick;
        let restartPosition: { tick: number; loopRestart: boolean } | null = null;
        try {
          restartPosition = await placeNaturalRestartPosition(currentApi, generation, restartIntent);
        } catch (reason) {
          if (!isCurrentApi(currentApi, generation) || signal.aborted || restartIntent !== playbackIntentGeneration) return;
          pendingNaturalRestartTick = null;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          renderNotice = reason instanceof Error ? reason.message : '循环起点位置未能确认，请手动继续。';
          return;
        }
        if (!isCurrentApi(currentApi, generation) || signal.aborted
          || restartIntent !== playbackIntentGeneration || !audioFocusHeld) return;
        const started = currentApi.play();
        if (started === false) {
          if (restartTick !== null && restartPosition && !restartPosition.loopRestart) {
            currentApi.tickPosition = restartTick;
            curTick = restartTick;
            curTime = endTime;
            confirmPracticePosition(restartTick, endTime, currentApi.endTick);
          }
          pendingNaturalRestartTick = null;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          playing = false;
          renderNotice = '音源已准备好，但播放器未能开始；请手动继续。';
        } else if (restartTick !== null) {
          pendingNaturalRestartTick = null;
          markResumeIntent();
        }
      }
    }
  }

  $effect(() => {
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('mimi:playback-state', { detail: { isPlaying: playing } }));
    }
  });

  function loadSoundfonts(
    currentApi: AlphaTabApi | null = api,
    generation: number = loadGeneration,
    signal: AbortSignal | null = playerAbort?.signal ?? null
  ): Promise<void> {
    if (!currentApi || !signal || !isCurrentApi(currentApi, generation) || signal.aborted) return Promise.resolve();
    const next = soundLoadChain.then(async () => {
      await doLoadSoundfonts(currentApi, generation, signal);
      await restorePendingPlayerReloadSnapshot(currentApi, generation);
    });
    soundLoadChain = next.catch(() => {});
    return next;
  }

  function waitForAlphaTabRender(currentApi: AlphaTabApi, render: () => void | Promise<void>): Promise<void> {
    return new Promise((resolve, reject) => {
      let settled = false;
      let unsubscribe = () => {};
      let timeout: ReturnType<typeof setTimeout> | null = null;
      const finish = (reason?: unknown) => {
        if (settled) return;
        settled = true;
        if (timeout) clearTimeout(timeout);
        unsubscribe();
        if (activeRenderWait?.api === currentApi) activeRenderWait = null;
        if (reason != null) reject(reason);
        else resolve();
      };

      unsubscribe = currentApi.postRenderFinished.on(() => finish());
      activeRenderWait = { api: currentApi, fail: (reason) => finish(reason) };
      timeout = setTimeout(() => finish(new Error('乐谱排版超时')), 23000);
      try {
        const result = render();
        if (result && typeof (result as any).then === 'function') {
          void (result as Promise<void>).catch((reason) => finish(reason));
        }
      } catch (reason) {
        finish(reason);
      }
    });
  }

  function wireEvents(currentApi: AlphaTabApi, generation: number): () => void {
    const unregister: Array<() => void> = [];
    const current = () => isCurrentApi(currentApi, generation);

    unregister.push(currentApi.playerStateChanged.on((args: any) => {
      if (!current()) return;
      const wasPlaying = playing;
      playing = args.state === 1; // PlayerState.Playing
      if (args.state === 1) {
        naturalEndPosition = null;
        markResumeIntent();
        audioFocusRetainedForRender = false;
        intentionalRestartPending = false;
      }
      if (args.state === 0 && pendingPausePositionRestore) {
        // AlphaTab's pause handler maps a repeated beat back to its first source occurrence.
        // Its position receipt may arrive after this state event, so retain the capture until then.
        resumeAfterPauseIfRemapped(currentApi, currentApi.tickPosition);
      }
      if (args.state !== 1) {
        if (wasPlaying) interruptLoopLap();
        if (!audioFocusRetainedForRender) {
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
        }
      }
      if (args.state === 2) { // Stopped
        if (intentionalRestartPending) {
          curTick = 0;
          curTime = 0;
          confirmPracticePosition(0, 0, currentApi.endTick);
          curBar = 0;
          curBeat = 0;
          intentionalRestartPending = false;
        }
        liveActiveNotes = [];
        liveCurrentChord = '';
      }
    }));
    unregister.push(currentApi.scoreLoaded.on((loadedScore: any) => {
      if (!current()) return;
      const currentScore = loadedScore ?? score;
      if (!currentScore) return;
      if (title) currentScore.title = title;
      if (artist) currentScore.artist = artist;
      applyCapoSelection(currentScore, sourceStaffCapos, { useSourceCapo, capo: capoMode });
      if (!scoreLoadedOnce) {
        scoreLoadedOnce = true;
        const tempo = resolvePracticeTempo(currentScore.tempo, bpm);
        sourceTempo = tempo.sourceTempo;
        speed = tempo.targetTempo;
        displayTempo = tempo.actualTempo;
        // 不能改写 score 的 tempo automation，否则 AlphaTab 会叠加一次速度变化；
        // 仅按「目标 BPM / 谱面原生 BPM」设置播放倍率。
        const requestedRatio = tempo.playbackSpeed;
        currentApi.playbackSpeed = requestedRatio;
        playbackRatio = currentApi.playbackSpeed;
        if (!isValidPlaybackRatio(playbackRatio) || Math.abs(playbackRatio - requestedRatio) > 0.0001) {
          renderNotice = '播放器未能应用计算出的实际倍率，请手动确认速度后继续。';
        } else if (tempo.targetUnavailable) {
          renderNotice = `原谱 ${Math.round(sourceTempo)} BPM 与播放器倍率范围无法提供 20–300 BPM 目标；当前保持原谱 ${playbackRatio.toFixed(2)}×。`;
        } else if (tempo.targetClamped && !tempo.hasRequested) {
          renderNotice = `原谱 ${Math.round(sourceTempo)} BPM 超出速度目标控件的 20–300 BPM 范围；当前仍按原谱 ${playbackRatio.toFixed(2)}× 播放。`;
        } else if (tempo.targetClamped) {
          renderNotice = `请求目标速度无法按原谱与播放器范围实现，已调整为可达的 ${Math.round(tempo.targetTempo)} BPM。`;
        } else {
          renderNotice = '';
        }
      }
    }));
    // 贝斯击勾（tap/slap/pop）MIDI 力度增强：AlphaTab 1.8.4 不生成该效果，经官方 midiLoad 事件后处理
    unregister.push(currentApi.midiLoad.on((midiFile: any) => {
      if (!current() || !score) return;
      const map = buildBassBoostMap(currentApi, score);
      if (map.size > 0 && !(window as any).__disableBassBoost) applyVelocityBoostToMidi(midiFile, map);
    }));
    // AlphaTab 1.8.4 的 currentApi.midiLoaded.on() 会在注册时求值 loadedMidiInfo 并递归；只订阅无初始 getter 的 worker emitter。
    const workerMidiLoaded = (currentApi as any)._player?._instance?.midiLoaded;
    if (workerMidiLoaded?.on && workerMidiLoaded?.off) {
      const onMidiLoaded = (args: any) => {
        if (!current() || !args) return;
        const midiEndTime = args.endTime;
        if (Number.isFinite(midiEndTime) && midiEndTime > 0) endTime = midiEndTime;

        let apiPosition: any = null;
        try {
          apiPosition = { endTick: currentApi.endTick, endTime: currentApi.endTime };
        } catch {
          // 保持 fail-closed；不要在 MIDI 就绪回调之外触碰可能未就绪的 API 边界。
        }
        const apiEndTick = apiPosition?.endTick;
        if (Number.isFinite(apiEndTick) && Number.isSafeInteger(apiEndTick) && apiEndTick > 0) {
          endTick = apiEndTick;
        } else {
          try {
            // Worker payload 处于播放器 tick 原点；用 AlphaTab wrapper 的既有转换再作为兜底。
            const shiftedArgs = (currentApi as any)._player?._shiftPositionChangedEventArgsToApi?.(args);
            const shiftedEndTick = shiftedArgs?.endTick;
            if (Number.isFinite(shiftedEndTick) && Number.isSafeInteger(shiftedEndTick) && shiftedEndTick > 0) {
              endTick = shiftedEndTick;
            }
            const shiftedEndTime = shiftedArgs?.endTime;
            if (Number.isFinite(shiftedEndTime) && shiftedEndTime > 0) endTime = shiftedEndTime;
          } catch {
            // 无法安全转换时不使用原始 worker tick，也不放宽边界校验。
          }
        }
        const apiEndTime = apiPosition?.endTime;
        if (Number.isFinite(apiEndTime) && apiEndTime > 0) endTime = apiEndTime;
      };
      workerMidiLoaded.on(onMidiLoaded);
      unregister.push(() => workerMidiLoaded.off(onMidiLoaded));
    }
    // 实时位置：驱动进度条/时间；throttle 避免高频重渲染
    unregister.push(currentApi.playerPositionChanged.on((args: any) => {
      if (!current()) return;
      if (args) {
        const observedEndTick = args.endTick;
        if (Number.isFinite(observedEndTick) && Number.isSafeInteger(observedEndTick) && observedEndTick > 0) {
          endTick = observedEndTick;
        }
        const observedEndTime = args.endTime;
        if (Number.isFinite(observedEndTime) && observedEndTime > 0) endTime = observedEndTime;
        const positionEndTick = Number.isSafeInteger(observedEndTick) && observedEndTick > 0
          ? observedEndTick : currentApi.endTick;
        const observedTick = Number.isFinite(args.currentTick) ? args.currentTick : currentApi.tickPosition;
        const positionTick = clampTick(observedTick, positionEndTick);
        if (pendingPausePositionRestore) {
          if (resumeAfterPauseIfRemapped(currentApi, positionTick)) return;
          if (args.isSeek === true) clearPendingPausePositionRestore();
          else return;
        }
        if (shouldIgnorePositionDuringSeek(pendingSeek?.tick ?? null, args)) return;
        const actualTimeMs = Number.isFinite(args.currentTime) && args.currentTime >= 0
          ? args.currentTime
          : lastConfirmedPosition?.timeMs ?? curTime;
        if (dragging) {
          seekPreviewState = observeSeekPreviewPosition(seekPreviewState, generation, {
            tick: positionTick,
            timeMs: actualTimeMs,
          });
          confirmPracticePosition(positionTick, actualTimeMs, positionEndTick);
          const now = Date.now();
          if (!args.isSeek && now - lastPosUpdate < 80) return;
          lastPosUpdate = now;
          curTime = actualTimeMs;
          curTick = clampTick(positionTick, currentApi.endTick);
          currentTickIsSeek = args.isSeek === true;
          updatePositionBeatMetadata(currentApi, curTick, positionEndTick);
          return;
        }
        if (naturalEndPosition && !playing) {
          curTick = naturalEndPosition.tick;
          curTime = naturalEndPosition.timeMs;
          confirmPracticePosition(curTick, curTime, positionEndTick);
          updatePositionBeatMetadata(currentApi, curTick, positionEndTick);
          return;
        }
        currentTickIsSeek = args.isSeek === true;
        const now = Date.now();
        if (!args.isSeek && now - lastPosUpdate < 80) return;
        lastPosUpdate = now;
        curTime = Number.isFinite(args.currentTime) && args.currentTime >= 0 ? args.currentTime : curTime;
        curTick = clampTick(positionTick, currentApi.endTick);
        confirmPracticePosition(curTick, curTime, currentApi.endTick);
        updatePositionBeatMetadata(currentApi, curTick, positionEndTick);
      }
    }));
    unregister.push(currentApi.playedBeatChanged.on((beat: any) => {
      if (!current() || dragging || pendingSeek) return;
      updatePositionBeatMetadata(currentApi, currentApi.tickPosition, currentApi.endTick);

      if (beat && Array.isArray(beat.notes)) {
        liveActiveNotes = beat.notes.map((n: any) => ({
          string: n.string,
          fret: n.fret,
          finger: n.leftHandFinger || undefined,
        }));
        if (typeof window !== 'undefined') {
          window.dispatchEvent(new CustomEvent('mimi:beat-pulse'));
        }
      } else {
        liveActiveNotes = [];
      }

      if (beat?.hasChord && beat?.chord?.name) {
        liveCurrentChord = beat.chord.name;
      } else if (beat?.chord?.name) {
        liveCurrentChord = beat.chord.name;
      }
    }));
    unregister.push(currentApi.playerFinished.on(() => {
      if (!current()) return;
      if (loopActive && loopEndTick > loopStartTick) {
        const previous = completedLoopLap;
        completedLoopLap = {
          generation: loopGeneration,
          sequence: (previous?.generation === loopGeneration ? previous.sequence : 0) + 1,
          startTick: loopStartTick,
          endTick: loopEndTick,
        };
        curTick = loopStartTick;
        curTime = currentApi.timePosition;
        seekPreviewState = observeSeekPreviewPosition(seekPreviewState, generation, {
          tick: curTick,
          timeMs: curTime,
        });
        confirmPracticePosition(curTick, curTime, currentApi.endTick);
        return;
      }
      if (playing) interruptLoopLap();
      pendingNaturalRestartTick = null;
      const el = container?.closest('#score-scroll');
      el?.scrollTo({ top: 0 });
      playing = false;
      curTick = currentApi.endTick ?? endTick;
      curTime = Math.max(currentApi.timePosition || 0, curTime, endTime);
      naturalEndPosition = { tick: curTick, timeMs: curTime };
      seekPreviewState = observeSeekPreviewPosition(seekPreviewState, generation, naturalEndPosition);
      confirmPracticePosition(curTick, curTime, currentApi.endTick);
      audioFocusRelease?.();
      audioFocusRelease = null;
      audioFocusHeld = false;
      markResumeIntent();
      curBar = 0;
      curBeat = 0;
      liveActiveNotes = [];
      liveCurrentChord = '';
    }));
    unregister.push(currentApi.playbackRangeChanged.on((args: any) => {
      if (!current()) return;
      // alphaTab 点击音符时会重算/清空 playbackRange；循环激活时保持粘连
      if (!loopActive) return;
      const r = args?.playbackRange;
      if (!r || r.startTick !== loopStartTick || r.endTick !== loopEndTick) {
        currentApi.playbackRange = { startTick: loopStartTick, endTick: loopEndTick };
      }
    }));
    unregister.push(currentApi.beatMouseDown.on(() => {
      if (!current()) return;
      clearPendingPausePositionRestore();
      if (!naturalEndPosition) return;
      naturalEndPosition = null;
      markResumeIntent();
    }));
    unregister.push(currentApi.beatMouseUp.on((beat: any) => {
      if (!current()) return;
      if (!loopArmed) return;
      const startTick = currentApi.tickCache?.getBeatStart(beat) ?? 0;
      if (!loopStartSet) {
        loopStartTick = startTick;
        loopStartSet = true;
      } else if (!loopEndSet) {
        const masterBar = beat?.voice?.bar?.masterBar;
        if (masterBar?.repeatGroup?.isOpened && masterBar.repeatGroup.masterBars.length > 1) {
          renderNotice = '该谱面小节有多个反复演奏次序，无法仅凭谱面位置确定 B 点。请在“本地练习”面板按当前播放 tick 设置。';
          return;
        }
        if (startTick <= loopStartTick) return;
        loopEndTick = Math.min(endTick || currentApi.endTick, startTick + (beat?.playbackDuration ?? 0));
        loopEndSet = true;
        loopActive = true;
        currentApi.playbackRange = { startTick: loopStartTick, endTick: loopEndTick };
        currentApi.isLooping = true;
      }
    }));
    // 异常兜底：不再静默
    unregister.push(currentApi.error.on((e: any) => {
      if (!current()) return;
      console.error('[ScorePlayer] alphaTab error', e);
      if (activeRenderWait?.api === currentApi) {
        activeRenderWait.fail(e ?? new Error('AlphaTab 渲染失败'));
      } else if (loading) {
        const failure = scoreLoadFailurePresentation(scoreUrl, 'render');
        error = failure.message;
        errorCanRetry = failure.canRetry;
        errorCanDownload = failure.canDownload && scoreJsonRaw !== null;
        loading = false;
        clearLoadWatchdog(generation);
      } else {
        renderNotice = '播放器遇到问题，当前谱面设置已保留；可以稍后重试或下载原谱。';
      }
    }));

    return () => {
      for (const off of unregister.splice(0)) {
        try { off(); } catch { /* already disposed */ }
      }
    };
  }

  // Build a fresh score from the stored raw JSON. In MIXED mode the secondary
  // tuned tracks' whole-note rests are replaced by 4 quarter rests at the JSON
  // level (before JsonConverter) to avoid the AlphaTab 1.8.4 numbered-renderer
  // crash; ALL_TAB mode keeps the raw JSON (tab renderer handles whole rests).
  // 数字谱开关：控制 numbered（简谱）谱表的显隐。六线谱品数始终完整显示（不再用 CSS 隐藏和弦品数）。
  // numberTab=true → 按当前显示模式恢复 showNumbered；false → 全部置 false，仅保留六线谱谱表。
  function applyNumberTab(sc: any) {
    if (numberTab) {
      applyScoreDisplayMode(sc, scoreDisplayMode);
    } else {
      for (const t of sc.tracks) for (const st of t.staves) st.showNumbered = false;
    }
  }

  function buildScoreFromJson(mode: string) {
    // Rendering may add layout-only lyric spacer rows. Always start from a
    // fresh clone so mode toggles, downloads and subsequent renders never
    // accumulate synthetic rows into the decoded score source.
    const src = assertRenderableScore(JSON.parse(JSON.stringify(scoreJsonRaw)));
    if (mode === SCORE_DISPLAY_MODES.MIXED) {
      replaceWholeRestsInSecondaryTracks(src);
    }
    addLyricsTopSpacer(src);
    const sc = model.JsonConverter.jsonToScore(JSON.stringify(src), createScoreSettings());
    assertRenderableScore(sc);
    sourceStaffCapos = captureSourceCapos(sc);
    if (useSourceCapo) {
      const primaryIndex = primaryStringTrackIndex(sc.tracks.length, defaultTrack, visibleTracks);
      capoMode = primarySourceCapo(sourceStaffCapos, primaryIndex);
    }
    for (const t of sc.tracks) for (const st of t.staves) st.showStandardNotation = false;
    applyScoreDisplayMode(sc, mode);
    if (!numberTab) for (const t of sc.tracks) for (const st of t.staves) st.showNumbered = false;
    applyCapoSelection(sc, sourceStaffCapos, { useSourceCapo, capo: capoMode });
    for (const t of sc.tracks) for (const st of t.staves) st.transpositionPitch = -transpose;
    sc.stylesheet.globalDisplayChordDiagramsInScore = chordMode === 'diagram';
    return sc;
  }

  // Rebuild the tracks list for a fresh score object and preserve the user's
  // track adjustments (instrument / visibility / mute / solo / volume).
  function rebuildTrackState(sc: any) {
    const prev = tracks.map((t) => ({ ...t }));
    buildTracks(sc);
    visibleTracks = [];
    for (const tr of prev) {
      const t = sc.tracks[tr.index];
      if (!t) continue;
      const live = tracks.find((x) => x.index === tr.index);
      if (tr.instrumentOverride && !tr.percussion) {
        applyTrackInstrument(t, tr.program);
      }
      if (live) {
        live.program = tr.instrumentOverride && !tr.percussion ? tr.program : (live.percussion ? 128 : live.sourceProgram);
        live.name = tr.instrumentOverride && !tr.percussion ? instrumentName(tr.program) : live.sourceName;
        live.instrumentOverride = tr.instrumentOverride && !tr.percussion;
        live.instrumentFlavor = live.instrumentOverride ? 'gm' : live.sourceFlavor;
        live.volume = tr.volume;
        live.muted = tr.muted;
        live.soloed = tr.soloed;
      }
      if (tr.show) visibleTracks.push(tr.index);
    }
    if (visibleTracks.length === 0) visibleTracks = [0];
  }

  // Re-apply the mix on the player's tracks after a fresh score object is
  // rendered (renderScore with a new object resets the player track state).
  function applyTrackMix(sc: any, strict = false) {
    for (const tr of tracks) {
      const t = sc.tracks[tr.index];
      if (!t) continue;
      try {
        api?.changeTrackMute([t], !tr.show || tr.muted);
        if (tr.soloed) api?.changeTrackSolo([t], true);
        api?.changeTrackVolume([t], tr.volume / 100);
      } catch (error) {
        if (strict) throw new Error(`音轨 ${tr.index + 1} 的混音设置未能恢复`, { cause: error });
      }
    }
  }

  /** 从 score + tickCache 构建 tap/slap/pop 力度增强映射：Map<trackIndex, Map<tick, boost>> */
  function buildBassBoostMap(
    currentApi: AlphaTabApi | null = api,
    currentScore: any = score
  ): Map<number, Map<number, number>> {
    const map = new Map<number, Map<number, number>>();
    if (!currentApi || !currentScore) return map;
    for (const t of currentScore.tracks) {
      for (const st of t.staves ?? []) {
        for (const bar of st.bars ?? []) {
          for (const v of bar.voices ?? []) {
            for (const beat of v.beats ?? []) {
              const boost = bassArticulationBoost(beat);
              if (!boost) continue;
              const tick = currentApi.tickCache?.getBeatStart(beat) ?? 0;
              if (tick <= 0) continue;
              if (!map.has(t.index)) map.set(t.index, new Map<number, number>());
              const m = map.get(t.index)!;
              m.set(tick, Math.max(m.get(tick) ?? 0, boost));
            }
          }
        }
      }
    }
    return map;
  }

  function armLoadWatchdog(generation: number) {
    clearLoadWatchdog();
    loadTimeout = setTimeout(() => {
      if (generation === loadGeneration && loading) {
        ++loadGeneration;
        disposeActivePlayer();
        loading = false;
        const failure = scoreLoadFailurePresentation(scoreUrl, 'fetch', { kind: 'timeout' });
        error = failure.message;
        errorCanRetry = failure.canRetry;
        errorCanDownload = failure.canDownload;
        loadTimeout = null;
      }
    }, 25000);
  }
  function clearLoadWatchdog(generation?: number) {
    if (generation != null && generation !== loadGeneration) return;
    if (loadTimeout) { clearTimeout(loadTimeout); loadTimeout = null; }
  }

  function capturePlayerReloadSnapshot(): PlayerReloadSnapshot | null {
    if (!score || !api) return null;
    return {
      scoreId: scoreIdentity(),
      tracks: tracks.map((track) => ({ ...track })),
      position: getPracticePositionSnapshot(),
    };
  }

  function applyPendingPlayerReloadSnapshot(sc: any): void {
    const snapshot = pendingPlayerReloadSnapshot;
    if (!snapshot) return;
    const currentId = scoreIdentity();
    const identityMatches = !snapshot.scoreId || !currentId
      || snapshot.scoreId === currentId
      || snapshot.scoreId === `catalog:${currentId}`
      || currentId === `catalog:${snapshot.scoreId}`;
    if (!identityMatches) {
      pendingPlayerReloadSnapshot = null;
      return;
    }

    const previousByIndex = new Map(snapshot.tracks.map((track) => [track.index, track]));
    tracks = tracks.map((track) => {
      const previous = previousByIndex.get(track.index);
      const scoreTrack = sc?.tracks?.[track.index];
      if (!previous || !scoreTrack) return track;
      const instrumentOverride = previous.instrumentOverride && !track.percussion;
      const program = track.percussion ? 128 : instrumentOverride ? previous.program : track.sourceProgram;
      const name = instrumentOverride
        ? applyTrackInstrument(scoreTrack, program)
        : track.sourceName;
      return {
        ...track,
        program,
        name,
        instrumentOverride,
        instrumentFlavor: instrumentOverride ? 'gm' : track.sourceFlavor,
        show: previous.show,
        muted: previous.muted,
        soloed: previous.soloed,
        volume: previous.volume,
      };
    });
    visibleTracks = tracks.filter((track) => track.show).map((track) => track.index);
    if (visibleTracks.length === 0) visibleTracks = [tracks[0]?.index ?? 0];
  }

  async function restorePendingPlayerReloadSnapshot(currentApi: AlphaTabApi, generation: number): Promise<void> {
    const snapshot = pendingPlayerReloadSnapshot;
    if (!snapshot || restoringPlayerReloadSnapshot || !isCurrentApi(currentApi, generation) || !soundReady || !score) return;
    const currentId = scoreIdentity();
    const identityMatches = !snapshot.scoreId || !currentId
      || snapshot.scoreId === currentId
      || snapshot.scoreId === `catalog:${currentId}`
      || currentId === `catalog:${snapshot.scoreId}`;
    if (!identityMatches) {
      pendingPlayerReloadSnapshot = null;
      return;
    }

    restoringPlayerReloadSnapshot = true;
    try {
      applyTrackMix(score, true);
      const targetTick = clampTick(snapshot.position.tick, currentApi.endTick);
      try {
        await seekPracticePosition(targetTick);
      } catch (reason) {
        if (!isCurrentApi(currentApi, generation)) return;
        // Keep the user's last confirmed position when AlphaTab cannot issue a
        // position receipt during a fresh API's first MIDI tick.
        currentApi.tickPosition = targetTick;
        curTick = targetTick;
        curTime = snapshot.position.timeMs;
        confirmPracticePosition(targetTick, curTime, currentApi.endTick);
        updatePositionBeatMetadata(currentApi, targetTick, currentApi.endTick);
        renderNotice = reason instanceof Error ? reason.message : '已保留练习位置，但位置确认回执未到达。';
      }
      if (isCurrentApi(currentApi, generation) && pendingPlayerReloadSnapshot === snapshot) {
        pendingPlayerReloadSnapshot = null;
      }
    } catch (reason) {
      if (isCurrentApi(currentApi, generation)) {
        renderNotice = reason instanceof Error ? reason.message : '音源重建后混音状态未能恢复。';
      }
    } finally {
      restoringPlayerReloadSnapshot = false;
    }
  }

  function retrySoundfonts(): void {
    playRequested = false;
    const currentApi = api;
    if (currentApi && isSoundfontReceiptPoisoned(currentApi)) {
      pendingPlayerReloadSnapshot = capturePlayerReloadSnapshot() ?? pendingPlayerReloadSnapshot;
      retryLoad();
      return;
    }
    void loadSoundfonts(currentApi, loadGeneration, playerAbort?.signal ?? null);
  }

  function retryLoad() {
    if (!scoreUrl) return;
    error = '';
    errorCanRetry = true;
    errorCanDownload = false;
    renderNotice = '';
    loading = true;
    void loadScore(true);
  }

  async function loadScore(retry = false) {
    if (!scoreUrl) {
      const failure = scoreLoadFailurePresentation(scoreUrl);
      error = failure.message;
      errorCanRetry = failure.canRetry;
      errorCanDownload = failure.canDownload;
      loading = false;
      return;
    }
    if (!container) {
      console.warn('[ScorePlayer] container not ready, effect will retry');
      return;
    }

    const generation = ++loadGeneration;
    seekUiGeneration++;
    disposeActivePlayer();
    const currentAbort = new AbortController();
    playerAbort = currentAbort;
    const signal = currentAbort.signal;
    scoreLoadedOnce = false;
    score = null;
    scoreJsonRaw = null;
    sourceStaffCapos = [];
    tracks = [];
    visibleTracks = [];
    endTick = 0;
    endTime = 0;
    naturalEndPosition = null;
    curTick = 0;
    curTime = 0;
    lastConfirmedPosition = { tick: 0, timeMs: 0 };
    curBar = 0;
    curBeat = 0;
    loading = true;
    error = '';
    errorCanRetry = true;
    errorCanDownload = false;
    renderNotice = '';
    armLoadWatchdog(generation);

    let currentApi: AlphaTabApi | null = null;
    let loadStage: 'fetch' | 'decode' | 'convert' | 'render' = 'fetch';
    try {
      console.log('[ScorePlayer] starting loadScore for', scoreUrl);
      installBrowserAr();
      const settings = createScoreSettings();
      // 移动端（< 640px）加大初始缩放，让谱面更清晰；桌面保持 0.84
      if (baseScale !== 0.84) settings.display.scale = baseScale;
       // 先阻止 AlphaTab 构造函数创建默认播放器，确保 Worker 工厂注入后只创建一个实例。
       // AlphaTab 的兼容逻辑会在 enablePlayer=true 时把 Disabled 自动改回
       // EnabledAutomatic；因此两个开关必须同时关闭，否则构造函数会先创建
       // 一个默认 Worker，后续再注入工厂时就会留下第二条 ScriptProcessor 输出链路。
       const configuredPlayerMode = settings.player.playerMode;
       const configuredEnablePlayer = settings.player.enablePlayer;
       settings.player.enablePlayer = false;
       settings.player.playerMode = PlayerMode.Disabled;
       currentApi = new AlphaTabApi(container, settings);
      api = currentApi;
      (window as any).__api = currentApi;

      // 覆盖底层 Web Worker 工厂：使用绝对路径运行时，避免相对路径/模块解析造成音源初始化失败。
      const facade = (currentApi as any).uiFacade;
      if (facade?.constructor) {
        facade.constructor.createAlphaSynthWebWorker = function() {
          const code = `
            importScripts(location.origin + '/alphaTab.js');
          `;
          const blob = new Blob([code], { type: 'application/javascript' });
          return new Worker(URL.createObjectURL(blob));
        };
      }

       settings.player.enablePlayer = configuredEnablePlayer;
       settings.player.playerMode = configuredPlayerMode;
      (currentApi as any)._setupOrDestroyPlayer();

      // 关键优化：跟踪并注册 AlphaTab 底层 Web Audio 上下文，以便在移动端与切屏时保持自动唤醒
      try {
        const p = (currentApi as any)?._player;
        if (p?.output) {
          const syncAudioContext = () => {
            const ctx = p.output.audioContext || p.output.context;
            if (ctx) {
              p.output.audioContext = ctx;
              registerAudioContext(ctx);
            }
          };
          syncAudioContext();
          const origOpen = p.output.open?.bind(p.output);
          if (origOpen) {
            p.output.open = function (...args: any[]) {
              const res = origOpen(...args);
              syncAudioContext();
              return res;
            };
          }
        }
      } catch {}

      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
      disposePlayerEvents = wireEvents(currentApi, generation);

      console.log('[ScorePlayer] fetching scoreUrl...');
      const buf = await fetchScoreBytes(scoreUrl, { signal, retry });
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
      const sourceId = practiceScore?.sourceId ?? inferCatalogSourceId(scoreUrl);
      const revision = await hashBytes(buf);
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
      const loadedScoreSource = practiceScore?.source ?? 'catalog';
      const loadedScoreUrl = loadedScoreSource === 'catalog' ? (practiceScore ? practiceScore.scoreUrl : scoreUrl) : undefined;
      const verifiedPracticeScore: PersonalScore = {
        ...practiceScore,
        id: practiceScore?.id ?? `catalog:${sourceId}`,
        source: loadedScoreSource,
        sourceId,
        revision,
        title: practiceScore?.title ?? title,
        artist: practiceScore?.artist ?? artist,
        category: practiceScore?.category ?? (category === 'ukulele' || category === 'bass' ? category : 'guitar'),
        format: practiceScore?.format ?? (scoreUrl.toLowerCase().endsWith('.gp') ? 'gp' : 'ibe'),
        scoreUrl: loadedScoreUrl,
        createdAt: practiceScore?.createdAt ?? Date.now(),
        updatedAt: Date.now(),
      };
      practiceScoreRef = verifiedPracticeScore;

      // Yield 让出主线程，允许浏览器绘制加载过渡与响应手势
      await new Promise((r) => setTimeout(r, 0));
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;

      console.log('[ScorePlayer] decoding score...');
      loadStage = 'decode';
      const json = await decodeIbeToJsonBrowser(buf);
      assertRenderableScore(json);
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
      scoreJsonRaw = json;
      const meta = extractScoreMeta(json);
      displayKey = scoreKey || keySignatureName(meta.keySignature, meta.keySignatureType) || '';
      displayTimeSig = timeSig || String(meta.timeSigNum) + '/' + String(meta.timeSigDen);
      scoreDisplayMode = DEFAULT_SCORE_DISPLAY_MODE;

      // Yield 让出主线程，分割 JSON 解析与对象模型构建
      await new Promise((r) => setTimeout(r, 0));
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;

      loadStage = 'convert';
      score = buildScoreFromJson(scoreDisplayMode);
      buildTracks();
      applyPendingPlayerReloadSnapshot(score);
      applyPendingExternalInstrumentSelection(true);
      publishPrimaryInstrumentSelection();

      // Yield 让出主线程，准备进行谱面排版与光栅化渲染
      await new Promise((r) => setTimeout(r, 0));
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;

      console.log('[ScorePlayer] rendering score...');
      loadStage = 'render';
      // renderScore 内部会触发 AlphaTab 的 scoreLoaded 生命周期；不要手动调用
      // 私有 _onScoreLoaded，否则会提前/重复生成 MIDI，放大 worker 的状态竞态。
      await enqueueRender(() => currentApi!.renderScore(score, visibleTracks));
      if (!isCurrentApi(currentApi, generation) || signal.aborted) return;
      const currentPracticeScore = practiceScoreRef;
      const expectedFetchUrl = resolvedCatalogScoreUrl(practiceScore, scoreUrl);
      const sourceMatches = practiceScore?.source === 'catalog'
        && sourceId === (practiceScore.sourceId ?? inferCatalogSourceId(scoreUrl))
        && scoreUrl === expectedFetchUrl
        && currentPracticeScore?.source === 'catalog'
        && currentPracticeScore.id === verifiedPracticeScore.id
        && currentPracticeScore.sourceId === verifiedPracticeScore.sourceId
        && currentPracticeScore.scoreUrl === verifiedPracticeScore.scoreUrl
        && currentPracticeScore.assetId === verifiedPracticeScore.assetId
        && currentPracticeScore.revision === verifiedPracticeScore.revision;
      if (onPracticeScoreVerified && sourceMatches) {
        try { onPracticeScoreVerified(verifiedPracticeScore); }
        catch (callbackError) { console.warn('[ScorePlayer] practice score verification callback failed:', callbackError); }
      }
      currentApi.masterVolume = 1.0;
      loading = false;
      clearLoadWatchdog(generation);
      if (pendingExternalInstrumentSelection) applyPendingExternalInstrumentSelection();
      else publishPrimaryInstrumentSelection();
      console.log('[ScorePlayer] score rendered successfully');
      void loadSoundfonts(currentApi, generation, signal).catch((reason) => {
        if (isCurrentApi(currentApi, generation) && !signal.aborted) {
          renderNotice = reason instanceof Error ? reason.message : '音源加载失败。';
        }
      });
    } catch (e: any) {
      if (signal.aborted || loadGeneration !== generation || (currentApi && api !== currentApi)) return;
      console.error('[ScorePlayer] loadScore failed:', e);
      clearLoadWatchdog(generation);
      const message = e?.message ?? String(e);
      if (currentApi && api === currentApi) {
        disposeActivePlayer();
      } else if (playerAbort === currentAbort) {
        currentAbort.abort();
        playerAbort = null;
      }
      console.error('[ScorePlayer] load failure detail:', message);
      const failure = scoreLoadFailurePresentation(scoreUrl, loadStage, e);
      error = failure.message;
      errorCanRetry = failure.canRetry;
      errorCanDownload = failure.canDownload;
      score = null;
      tracks = [];
      visibleTracks = [];
      loading = false;
    }
  }

  onMount(() => {
    void prewarmSoundFontCache();
    const onVisibilityChange = () => {
      if (document.visibilityState === 'hidden') cancelSeekPreview();
    };
    const onPageHide = () => {
      cancelSeekPreview();
      // A pagehide can enter BFCache, where onDestroy does not run. Pause and
      // invalidate pending focus/soundfont starts without resuming on pageshow.
      fretboardAudition.invalidate();
      pausePlayback();
    };
    document.addEventListener('visibilitychange', onVisibilityChange);
    window.addEventListener('pagehide', onPageHide);
    window.addEventListener('mimi:seek-bar', handleManuscriptBarSeek);
    return () => {
      document.removeEventListener('visibilitychange', onVisibilityChange);
      window.removeEventListener('pagehide', onPageHide);
      window.removeEventListener('mimi:seek-bar', handleManuscriptBarSeek);
      clearSeekPreview();
    };
  });

  let isMounted = false;
  $effect(() => {
    if (isMounted) return;
    if (!container) return; // bind:this 未就绪时保持等待，容器就绪后 $effect 会重跑
    isMounted = true;
    // loadScore mutates api/score/loading while it initializes. Keep those
    // mutations out of this effect's dependency graph; otherwise assigning the
    // freshly-created api reruns the effect and aborts its own fetch.
    untrack(() => { void loadScore(); });
    const onExternalInstrChange = (e: any) => {
      if (e.detail?.source === 'player') return;
      const program = e.detail?.program;
      if (!Number.isSafeInteger(program) || program < 0 || program > 127) return;
      if (typeof e.detail?.scoreId === 'string') {
        const currentId = scoreIdentity();
        if (currentId && currentId !== e.detail.scoreId && currentId !== `catalog:${e.detail.scoreId}`) return;
      }
      pendingExternalInstrumentSelection = {
        program,
        scoreId: typeof e.detail?.scoreId === 'string' ? e.detail.scoreId : undefined,
      };
      if (!loading && tracks.length > 0) applyPendingExternalInstrumentSelection();
    };
    if (typeof window !== 'undefined') {
      window.addEventListener('mimi:instrument-change', onExternalInstrChange);
    }
    return () => {
      if (typeof window !== 'undefined') {
        window.removeEventListener('mimi:instrument-change', onExternalInstrChange);
      }
      clearLoadWatchdog();
      ++loadGeneration;
      seekUiGeneration++;
      disposeActivePlayer();
    };
  });

  /** Pause is an idempotent command, including while a focus claim is pending. */
  function pausePlayback(): boolean {
    const currentApi = api;
    const wasPlaying = playing;
    playbackIntentGeneration++;
    if (pendingPausePositionRestore) {
      // Visibility/focus/panel may send a second pause before the worker reports the first one.
      // Keep the original boundary and only advance its cancellation guard.
      pendingPausePositionRestore = {
        ...pendingPausePositionRestore,
        intentGeneration: playbackIntentGeneration,
      };
    } else if (wasPlaying && currentApi && !dragging && !pendingSeek) {
      pendingPausePositionRestore = capturePausePosition(currentApi, playbackIntentGeneration);
    }
    playRequested = false;
    pendingNaturalRestartTick = null;
    markResumeIntent();
    interruptLoopLap();
    currentApi?.pause();
    playing = false;
    audioFocusRelease?.();
    audioFocusRelease = null;
    audioFocusHeld = false;
    return !!api && !!score;
  }

  async function playPause(): Promise<boolean> {
    // 关键优化：在用户手势事件第一行同步调用栈立即解锁 Web Audio，绝不等待任何异步 Promise
    try {
      const p = (api as any)?._player;
      if (p?.output) {
        if (!p.output.audioContext && p.output.context) {
          p.output.audioContext = p.output.context;
        }
        if (p.output.audioContext) {
          registerAudioContext(p.output.audioContext);
          unlockAudioContextImmediately(p.output.audioContext);
        }
      }
    } catch {}

    if (!api || !score) return false;
    if (playing) {
      return pausePlayback();
    }
    const soundfontPlan = planScoreAuditionSoundfonts(score.tracks, category);
    if (!soundfontPlan.ok) {
      failClosedForSoundfontConflict(soundfontPlan);
      return false;
    }
    if (dragging || pendingSeek) {
      renderNotice = '请等待位置跳转确认后再开始播放。';
      return false;
    }

    const currentApi = api;
    const requestedIntent = ++playbackIntentGeneration;
    // A pause boundary belongs to one stopped run. Any remap correction is queued by the pause event itself;
    // do not carry an unconfirmed capture into a later playback run.
    clearPendingPausePositionRestore();
    const restartingAfterNaturalEnd = currentApi.endTick > 0 &&
      (currentApi.tickPosition >= currentApi.endTick || curTick >= currentApi.endTick);
    if (restartingAfterNaturalEnd) pendingNaturalRestartTick = currentApi.endTick;
    try {
      const release = await claimAudioFocus('score-player', () => {
        if (api === currentApi && requestedIntent === playbackIntentGeneration) pausePlayback();
      });
      if (api !== currentApi || requestedIntent !== playbackIntentGeneration) { release(); return false; }
      audioFocusRelease?.();
      audioFocusRelease = release;
      audioFocusHeld = true;
      if (loadingSounds || !soundReady) {
        playRequested = true;
        void loadSoundfonts(currentApi);
      } else {
        const restartTick = pendingNaturalRestartTick;
        const restartPosition = await placeNaturalRestartPosition(currentApi, loadGeneration, requestedIntent);
        if (api !== currentApi || requestedIntent !== playbackIntentGeneration) return false;
        const started = currentApi.play();
        if (started === false) {
          if (restartTick !== null && restartPosition && !restartPosition.loopRestart) {
            currentApi.tickPosition = restartTick;
            curTick = restartTick;
            curTime = endTime;
            confirmPracticePosition(restartTick, endTime, currentApi.endTick);
          }
          pendingNaturalRestartTick = null;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          return false;
        } else if (restartTick !== null) {
          pendingNaturalRestartTick = null;
          markResumeIntent();
        }
      }
      return true;
    } catch (reason) {
      if (api !== currentApi || requestedIntent !== playbackIntentGeneration) return false;
      pendingNaturalRestartTick = null;
      playRequested = false;
      audioFocusRelease?.();
      audioFocusRelease = null;
      audioFocusHeld = false;
      renderNotice = reason instanceof Error ? reason.message : '无法取得音频焦点，播放已停止。';
      return false;
    }
  }
  function stop() {
    playbackIntentGeneration++;
    playRequested = false;
    clearSeekPreview();
    clearPendingPausePositionRestore();
    cancelPendingSeek();
    dragging = false;
    naturalEndPosition = null;
    markResumeIntent();
    interruptLoopLap();
    intentionalRestartPending = true;
    pendingNaturalRestartTick = null;
    playing = false;
    curTick = 0;
    curTime = 0;
    confirmPracticePosition(0, 0, api?.endTick ?? endTick);
    api?.stop();
    audioFocusRelease?.();
    audioFocusRelease = null;
    audioFocusHeld = false;
  }
  function applyPracticeLoop(startTick: number, endExclusiveTick: number) {
    if (!api || startTick < 0 || endExclusiveTick <= startTick || endExclusiveTick > api.endTick) return;
    clearPendingPausePositionRestore();
    loopGeneration++;
    completedLoopLap = null;
    loopStartTick = startTick;
    loopEndTick = endExclusiveTick;
    loopStartSet = true;
    loopEndSet = true;
    loopActive = true;
    loopArmed = false;
    api.isLooping = true;
    api.playbackRange = { startTick, endTick: endExclusiveTick };
  }
  async function restorePracticeResume(resume: PlayerResume): Promise<number> {
    if (!api || !score || !practiceScoreRef) throw new Error('播放器尚未加载，无法恢复练习断点');
    fretboardAudition.invalidate();
    clearPendingPausePositionRestore();
    const currentApi = api;
    const initialScore = score;
    const settings = preparePracticeResumeSettings(resume, practiceScoreRef.revision, initialScore.tracks.length);
    const requestedRatio = resume.playbackRatio ?? computePlaybackSpeed(resume.speed, sourceTempo);
    if (!isValidPlaybackRatio(requestedRatio)) throw new Error('断点倍率超出播放器范围，请手动调整速度后继续');

    if (playing) {
      interruptLoopLap();
      audioFocusRetainedForRender = false;
      currentApi.pause();
      playing = false;
      audioFocusRelease?.();
      audioFocusRelease = null;
      audioFocusHeld = false;
    }

    if (settings.display) {
      fontScale = settings.display.fontScale;
      chordMode = settings.display.chordMode;
      scoreDisplayMode = settings.display.scoreDisplayMode === 'tab' ? SCORE_DISPLAY_MODES.ALL_TAB : SCORE_DISPLAY_MODES.MIXED;
      numberTab = settings.display.numberTab;
      showFretboard = settings.display.showFretboard;
      currentApi.settings.display.scale = baseScale * fontScale;
      currentApi.updateSettings();
    }
    speed = clampTargetBpm(resume.speed);
    capoMode = resume.capo;
    useSourceCapo = resume.useSourceCapo === true;
    transpose = resume.transpose;
    metronome = resume.metronome;
    countIn = resume.countIn;
    currentApi.metronomeVolume = metronome ? 1 : 0;
    currentApi.countInVolume = countIn ? 1 : 0;

    tracks = tracks.map((track) => ({
      ...track,
      program: track.percussion ? 128 : track.sourceProgram,
      name: track.sourceName,
      instrumentOverride: false,
      instrumentFlavor: track.sourceFlavor,
    }));
    const restoredScore = buildScoreFromJson(scoreDisplayMode);
    score = restoredScore;
    rebuildTrackState(restoredScore);
    visibleTracks = [...settings.visibleTrackIndexes];
    const visibleSet = new Set(visibleTracks);
    tracks = tracks.map((track) => ({ ...track, show: visibleSet.has(track.index) }));
    for (const saved of settings.trackMix) {
      const track = restoredScore.tracks[saved.index];
      const sourceState = tracks.find((item) => item.index === saved.index);
      if (!sourceState) continue;
      const resolved = resolveResumeInstrument(sourceState.sourceProgram, saved.program, saved.instrumentOverride);
      const percussion = sourceState.percussion || isPercussionTrack(track);
      let name = sourceState.sourceName;
      if (track && !percussion && resolved.instrumentOverride) name = applyTrackInstrument(track, resolved.program);
      tracks = tracks.map((item) => item.index === saved.index
        ? {
          ...item,
          ...(percussion
            ? {}
            : resolved.instrumentOverride
              ? { program: resolved.program, name, instrumentOverride: true, instrumentFlavor: 'gm' as const }
              : { program: sourceState.sourceProgram, name: sourceState.sourceName, instrumentOverride: false, instrumentFlavor: sourceState.sourceFlavor }),
          muted: saved.muted,
          soloed: saved.soloed,
          volume: saved.volume,
        }
        : item);
    }
    publishPrimaryInstrumentSelection();
    await loadSoundfonts(currentApi, loadGeneration, playerAbort?.signal ?? null);
    if (api !== currentApi) throw new Error('播放器已更新，断点恢复已取消');
    const midiLoaded = waitForMidiLoaded();
    await Promise.all([enqueueRender(() => currentApi.renderScore(restoredScore, visibleTracks)), midiLoaded]);
    endTick = currentApi.endTick ?? 0;
    if (api !== currentApi) throw new Error('播放器已更新，断点恢复已取消');
    applyTrackMix(restoredScore, true);

    const validLoop = resume.loop && Number.isInteger(resume.loop.startTick) && Number.isInteger(resume.loop.endTick) &&
      resume.loop.startTick >= 0 && resume.loop.endTick > resume.loop.startTick && resume.loop.endTick <= currentApi.endTick
      ? resume.loop
      : null;
    currentApi.playbackSpeed = requestedRatio;
    playbackRatio = currentApi.playbackSpeed;
    if (!isValidPlaybackRatio(playbackRatio) || Math.abs(playbackRatio - requestedRatio) > 0.0001) {
      throw new Error('播放器未能恢复保存的实际倍率，请手动确认速度');
    }
    const legacyTargetRatio = computePlaybackSpeed(resume.speed, sourceTempo);
    displayTempo = Math.abs(requestedRatio - legacyTargetRatio) <= 0.0001
      ? resume.speed
      : sourceTempo * playbackRatio;
    if (validLoop) applyPracticeLoop(validLoop.startTick, validLoop.endTick);
    else endLoop();
    const clampedTick = clampTick(resume.tick, currentApi.endTick);
    const restoredTick = validLoop
      ? Math.min(Math.max(clampedTick, validLoop.startTick), validLoop.endTick - 1)
      : clampedTick;
    naturalEndPosition = null;
    await seekPracticePosition(restoredTick);
    return playbackRatio;
  }
  function changeSpeed(v: number) {
    if (api && score) {
      if (!Number.isFinite(v) || v < 20 || v > 300) {
        renderNotice = '目标速度必须在 20–300 BPM 范围内。';
        return;
      }
      markResumeIntent();
      // 只改 playbackSpeed，不再改 tempo 自动化（避免双重生效）
      const requestedRatio = computePlaybackSpeed(v, sourceTempo);
      if (!isValidPlaybackRatio(requestedRatio)) {
        renderNotice = `该速度无法由当前曲谱原生速度实现（支持 ${Math.round(sourceTempo * 0.125)}–${Math.round(sourceTempo * 8)} BPM）。`;
        return;
      }
      try { setPlaybackRatio(requestedRatio, v); }
      catch {
        renderNotice = '播放器未能应用请求速度，请确认当前速度后重试。';
        return;
      }
    }
  }
  function toggleMetronome() {
    markResumeIntent();
    if (api) api.metronomeVolume = metronome ? 1 : 0;
  }
  function toggleCountIn() {
    markResumeIntent();
    if (api) api.countInVolume = countIn ? 1 : 0;
  }
  function toggleLoop() {
    if (loopArmed) { endLoop(); return; }
    loopArmed = true;
    loopStartSet = false;
    loopEndSet = false;
    loopActive = false;
    if (api) api.isLooping = true;
  }
  function endLoop() {
    clearPendingPausePositionRestore();
    loopArmed = false;
    loopStartSet = false;
    loopEndSet = false;
    loopStartTick = 1;
    loopEndTick = 1;
    loopActive = false;
    loopGeneration++;
    completedLoopLap = null;
    if (api) {
      api.isLooping = false;
      api.playbackRange = null;
    }
  }

  /**
   * 等待 worker 真正完成新一轮 MIDI 加载（loadMidiForScore 之后、恢复位置/续播之前）。
   * 必须监听 _player._instance.midiLoaded（worker API 层）：
   * - currentApi.midiLoaded / _player.midiLoaded 的 on() 会调用 loadedMidiInfo 初始 getter；1.8.4 Worker 的 loadedMidiInfo getter 自递归；
   * - _instance.midiLoaded 没有初始 getter，是安全 emitter，每次 worker 完成 MIDI 加载精确触发一次。
   * 超时兜底 resolve，不阻塞 UI。
   */
  function waitForMidiLoaded(timeoutMs = 8000): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!api) { reject(new Error('播放器已关闭，无法确认 MIDI 已加载')); return; }
      const player = (api as any)._player as any;
      const inst = player?._instance as any;
      if (!inst || !inst.midiLoaded) { reject(new Error('播放器没有可用的 MIDI 加载状态')); return; }
      let settled = false;
      const onLoaded = () => done();
      const timer = setTimeout(() => done(new Error('等待 MIDI 加载超时')), timeoutMs);
      function cleanup() {
        clearTimeout(timer);
        inst.midiLoaded.off(onLoaded);
      }
      function done(error?: Error) {
        if (settled) return;
        settled = true;
        cleanup();
        if (error) reject(error);
        else resolve();
      }
      inst.midiLoaded.on(onLoaded);
    });
  }

  /**
   * 播放中修改谱面：记录位置 → 暂停 → 应用/重渲染 →（可选）重生成播放 MIDI → 等 MIDI 加载完成 → 恢复位置 → 续播。
   * opts.reloadMidi=true 用于音频类变更（变调夹/降半调/转调/乐器切换）：AlphaTab 1.8.4 同一 score 对象重渲染不会重生成播放 MIDI，
   * 必须显式 loadMidiForScore() 并等待 waitForMidiLoaded 后再恢复位置/续播，避免时序竞态。
   */
  async function withRenderPreservingPosition(fn: () => Promise<void> | void, opts: { reloadMidi?: boolean } = {}): Promise<boolean> {
    if (!api || !score) {
      try { await fn(); return true; }
      catch (e) { console.error('[ScorePlayer] render error', e); return false; }
    }
    const currentApi = api;
    const currentScore = score;
    const wasPlaying = playing;
    const pos = currentApi.tickPosition;
    if (wasPlaying) {
      interruptLoopLap();
      audioFocusRetainedForRender = audioFocusHeld;
      currentApi.pause();
    }
    try {
      await fn();
      if (opts.reloadMidi) {
        const loaded = waitForMidiLoaded();
        await Promise.resolve().then(() => currentApi.loadMidiForScore()).then(() => loaded);
      }
      if (api !== currentApi) return false;
      currentApi.tickPosition = clampTick(pos, endTick);
      if (wasPlaying) {
        if (!soundReady) {
          currentApi.pause();
          playing = false;
          playRequested = false;
          audioFocusRetainedForRender = false;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          if (!soundError) soundError = '音源尚未就绪，播放器已暂停；请恢复原谱音色或重试音源。';
          renderNotice = soundError;
          return false;
        }
        const started = currentApi.play();
        if (started === false) {
          audioFocusRetainedForRender = false;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          playing = false;
        }
      }
      return true;
    } catch (e: any) {
      console.error('[ScorePlayer] render error', e);
      if (api === currentApi && !loading) {
        renderNotice = '谱面更新没有完成，当前调性与原谱仍可恢复；请稍后重试或下载原谱。';
        if (wasPlaying && soundReady) {
          try {
            const started = currentApi.play();
            if (started === false) {
              audioFocusRetainedForRender = false;
              audioFocusRelease?.();
              audioFocusRelease = null;
              audioFocusHeld = false;
              playing = false;
            }
          } catch {
            audioFocusRetainedForRender = false;
            audioFocusRelease?.();
            audioFocusRelease = null;
            audioFocusHeld = false;
            playing = false;
          }
        } else if (wasPlaying) {
          currentApi.pause();
          playing = false;
          playRequested = false;
          audioFocusRetainedForRender = false;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
        }
      }
      return false;
    }
  }

  /**
   * 变调夹(含降半调调弦) + 整曲转调：
   * - 变调夹/降半调调弦 → staff.capo（只改变发声音高，谱面显示不变，与参考站实测一致）
   * - 整曲转调 → staff.transpositionPitch（显示 + 播放整体移调，参考站无此控件，有意差异）
   */
  async function applyTransposition(transposeValue = transpose) {
    const currentApi = api;
    const currentScore = score;
    if (!currentApi || !currentScore) return;
    applyCapoSelection(currentScore, sourceStaffCapos, { useSourceCapo, capo: capoMode });
    for (const t of currentScore.tracks) for (const st of t.staves) st.transpositionPitch = -transposeValue;
    await enqueueRender(() => currentApi.renderScore(currentScore, visibleTracks));
  }

  /** 串行化 renderScore：AlphaTab 并发重渲染会崩溃，快速连续操作（连点变调夹/转调）时排队执行 */
  let renderChain: Promise<void> = Promise.resolve();
  function enqueueRender(fn: () => void | Promise<void>): Promise<void> {
    const targetApi = api;
    if (!targetApi) return Promise.resolve();
    const next = renderChain.then(async () => {
      if (api !== targetApi) return;
      await waitForAlphaTabRender(targetApi, fn);
    });
    renderChain = next.catch((e) => console.error('[ScorePlayer] render failed', e));
    return next;
  }

  async function closeCapoMenu(returnFocus = false): Promise<void> {
    if (!capoMenuOpen) return;
    capoMenuOpen = false;
    if (returnFocus) {
      await tick();
      capoTrigger?.focus();
    }
  }

  function handleCapoMenuKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Escape' || !capoMenuOpen ||
        !(event.target instanceof Node) || !capoMenuRoot?.contains(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
    void closeCapoMenu(true);
  }

  $effect(() => {
    if (!capoMenuOpen || typeof document === 'undefined') return;
    const closeOnOutsidePointer = (event: PointerEvent) => {
      const target = event.target;
      if (target instanceof Node && !capoMenuRoot?.contains(target)) {
        // Keep the pointer's normal focus behavior; only Escape and selection
        // explicitly return focus to the disclosure trigger.
        capoMenuOpen = false;
      }
    };
    document.addEventListener('keydown', handleCapoMenuKeydown);
    document.addEventListener('pointerdown', closeOnOutsidePointer, true);
    return () => {
      document.removeEventListener('keydown', handleCapoMenuKeydown);
      document.removeEventListener('pointerdown', closeOnOutsidePointer, true);
    };
  });

  function selectCapo(v: number) {
    markResumeIntent();
    useSourceCapo = false;
    capoMode = v;
    void closeCapoMenu(true);
    if (api && score) withRenderPreservingPosition(() => applyTransposition(), { reloadMidi: true });
  }

  function selectSourceCapo() {
    markResumeIntent();
    useSourceCapo = true;
    capoMode = primarySourceCapo(sourceStaffCapos, primaryTrackIndex());
    void closeCapoMenu(true);
    if (api && score) withRenderPreservingPosition(() => applyTransposition(), { reloadMidi: true });
  }

  async function changeTranspose(d: number) {
    const next = clampTranspose(transpose + d);
    if (next === transpose || transposePending) return;
    markResumeIntent();
    if (!api || !score) { transpose = next; return; }

    const previous = transpose;
    transposePending = true;
    renderNotice = '';
    try {
      const outcome = await runWithRollbackTransaction({
        previousValue: previous,
        nextValue: next,
        commit: (value: number) => { transpose = value; },
        apply: async (value: number) => {
          const rendered = await withRenderPreservingPosition(() => applyTransposition(value), { reloadMidi: true });
          if (!rendered) throw new Error('AlphaTab 未能完成新转调的渲染');
        },
        rollback: async (value: number) => {
          const rendered = await withRenderPreservingPosition(() => applyTransposition(value), { reloadMidi: true });
          if (!rendered) throw new Error('AlphaTab 未能恢复原调的渲染');
        },
      });
      renderNotice = outcome.ok
        ? ''
        : outcome.rollbackError
          ? '转调失败，原调参数已恢复，但谱面恢复排版未完成；请重试或下载原谱。'
          : '转调失败，已恢复原调和上一张有效谱面。';
    } catch (e) {
      console.error('[ScorePlayer] transpose transaction failed', e);
      renderNotice = '转调失败，当前调性已恢复；请重试或下载原谱。';
    } finally {
      transposePending = false;
    }
  }
  function changeFontScale(v: number) {
    markResumeIntent();
    fontScale = v;
    const currentApi = api;
    if (currentApi && score) {
      withRenderPreservingPosition(async () => {
        currentApi.settings.display.scale = baseScale * v;
        currentApi.updateSettings();
        await enqueueRender(() => currentApi.renderScore(score, visibleTracks));
      });
    }
  }

  /** 一键恢复原曲默认速度、原调变调夹与 0 转调 */
  function resetToDefaults() {
    if (!api || !score) return;
    const currentApi = api;
    const defaultCapoVal = primarySourceCapo(sourceStaffCapos, primaryTrackIndex());
    const defaultTargetBpm = clampTargetBpm(sourceTempo);
    const speedChanged = speed !== defaultTargetBpm || Math.abs(playbackRatio - 1) > 0.0001;
    const capoChanged = !useSourceCapo;
    const transposeChanged = transpose !== 0;
    const fontScaleChanged = fontScale !== 1;

    if (!speedChanged && !capoChanged && !transposeChanged && !fontScaleChanged) return;
    markResumeIntent();

    if (speedChanged) {
      speed = defaultTargetBpm;
      try {
        setPlaybackRatio(1);
        displayTempo = sourceTempo;
      } catch {
        renderNotice = '播放器未能恢复原谱实际速度，请手动确认速度后重试。';
      }
    }
    if (fontScaleChanged) {
      fontScale = 1;
      currentApi.settings.display.scale = baseScale;
      currentApi.updateSettings();
    }
    if (capoChanged || transposeChanged) {
      useSourceCapo = true;
      capoMode = defaultCapoVal;
      transpose = 0;
      withRenderPreservingPosition(() => applyTransposition(), { reloadMidi: true });
    } else if (fontScaleChanged) {
      withRenderPreservingPosition(async () => {
        await enqueueRender(() => currentApi.renderScore(score, visibleTracks));
      });
    }
  }
  /** 切换和弦显示模式：仅字母 vs 字母+完整指法图（原生逐拍渲染，保留播放位置） */
  function setChordMode(mode: 'name' | 'diagram') {
    if (mode === chordMode) return;
    markResumeIntent();
    chordMode = mode;
    const currentApi = api;
    if (currentApi && score) {
      score.stylesheet.globalDisplayChordDiagramsInScore = mode === 'diagram';
      withRenderPreservingPosition(async () => {
        await enqueueRender(() => currentApi.renderScore(score, visibleTracks));
      });
    }
  }

  // Switch score display mode. MIXED rebuilds from JSON (whole-rest safe),
  // ALL_TAB rebuilds from the raw JSON. A fresh score object auto-regenerates
  // the playback MIDI inside renderScore, so we only wait for it to be ready
  // before restoring the position and re-applying the mix.
  async function setScoreDisplayMode(mode: string) {
    if (mode === scoreDisplayMode) return;
    if (mode !== SCORE_DISPLAY_MODES.MIXED && mode !== SCORE_DISPLAY_MODES.ALL_TAB) return;
    markResumeIntent();
    scoreDisplayMode = mode;
    if (!api || !score || !scoreJsonRaw) return;
    const currentApi = api;
    const wasPlaying = playing;
    const pos = currentApi.tickPosition;
    if (wasPlaying) {
      interruptLoopLap();
      audioFocusRetainedForRender = audioFocusHeld;
      currentApi.pause();
    }
    try {
      const sc = buildScoreFromJson(mode);
      score = sc;
      rebuildTrackState(sc);
      const loaded = waitForMidiLoaded();
      await Promise.all([enqueueRender(() => currentApi.renderScore(sc, visibleTracks)), loaded]);
      endTick = currentApi.endTick;
      applyTrackMix(sc);
      currentApi.tickPosition = clampTick(pos, currentApi.endTick);
      if (wasPlaying) {
        const started = currentApi.play();
        if (started === false) {
          audioFocusRetainedForRender = false;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          renderNotice = '显示模式已切换，但播放器无法恢复播放；请手动继续。';
        }
      }
    } catch (e: any) {
      console.error('[ScorePlayer] mode switch error', e);
      renderNotice = '显示模式切换未完成；当前曲谱仍可继续使用，请重试。';
      if (wasPlaying && api === currentApi) {
        try {
          const started = currentApi.play();
          if (started === false) throw new Error('播放器拒绝继续播放');
        } catch {
          audioFocusRetainedForRender = false;
          audioFocusRelease?.();
          audioFocusRelease = null;
          audioFocusHeld = false;
          playing = false;
        }
      }
    }
  }

  function toggleNumberTab() {
    markResumeIntent();
    numberTab = !numberTab;
    // 数字谱开关：控制简谱（numbered）谱表显隐，重渲染保留播放位置；六线谱品数始终完整。
    const currentApi = api;
    if (currentApi && score) {
      withRenderPreservingPosition(async () => {
        applyNumberTab(score);
        await enqueueRender(() => currentApi.renderScore(score, visibleTracks));
      });
    }
  }

  function toggleFretboard() {
    markResumeIntent();
    showFretboard = !showFretboard;
    if (!showFretboard) fretboardAudition.invalidate();
  }

  function toggleTrack(i: number) {
    markResumeIntent();
    const tr = tracks[i];
    const show = !tr.show;
    tracks = tracks.map((x, idx) => (idx === i ? { ...x, show } : x));
    if (show) visibleTracks = [...visibleTracks, tr.index].sort((a, b) => a - b);
    else visibleTracks = visibleTracks.filter((x) => x !== tr.index);
    // 关闭音轨 = 同时静音（隐藏即静音）；重新打开时恢复用户静音设置
    const t = score.tracks[tr.index];
    if (api && t) api.changeTrackMute([t], !show || tr.muted);
    // renderTracks receives Track objects (not indices)
    api?.renderTracks(visibleTracks.map((idx) => score.tracks[idx]));
  }
  function toggleMute(i: number) {
    markResumeIntent();
    const tr = tracks[i];
    const muted = !tr.muted;
    tracks = tracks.map((x, idx) => (idx === i ? { ...x, muted } : x));
    api?.changeTrackMute([score.tracks[tr.index]], muted);
  }
  function toggleSolo(i: number) {
    markResumeIntent();
    const tr = tracks[i];
    const soloed = !tr.soloed;
    tracks = tracks.map((x, idx) => (idx === i ? { ...x, soloed } : x));
    api?.changeTrackSolo([score.tracks[tr.index]], soloed);
  }
  function changeVolume(i: number, v: number) {
    markResumeIntent();
    const tr = tracks[i];
    tracks = tracks.map((x, idx) => (idx === i ? { ...x, volume: v } : x));
    api?.changeTrackVolume([score.tracks[tr.index]], v / 100);
  }
  function applyTrackInstrument(track: any, program: number) {
    if (!Number.isSafeInteger(program) || program < 0 || program > 127) throw new RangeError('GM 音色必须在 0–127 范围内');
    const name = instrumentName(program);
    track.playbackInfo.program = program;
    track.name = name;
    track.shortName = name;
    track.mimiInstrumentOverride = true;
    track.mimiSoundfontFlavor = 'gm';
    // MidiFileGenerator 先按音轨初始化发出 Program Change，随后逐拍处理
    // Instrument 自动化（GP 首拍常冗余写死原音色），若不同步更新会覆盖新音色。
    const instrType = (model as any).AutomationType?.Instrument ?? 2;
    for (const st of track.staves ?? []) {
      for (const bar of st.bars ?? []) {
        for (const v of bar.voices ?? []) {
          for (const beat of v.beats ?? []) {
            for (const auto of beat.automations ?? []) {
              if (auto && auto.type === instrType) auto.value = program;
            }
          }
        }
      }
    }
    return name;
  }

  async function changeInstrument(i: number, program: number) {
    markResumeIntent();
    const tr = tracks[i];
    if (!tr || tr.percussion || !Number.isSafeInteger(program) || program < 0 || program > 127) return;
    fretboardAudition.invalidate();
    const track = score.tracks[tr.index];
    const name = applyTrackInstrument(track, program);
    tracks = tracks.map((x, idx) => (idx === i
      ? { ...x, program, name, instrumentOverride: true, instrumentFlavor: 'gm' }
      : x));
    publishPrimaryInstrumentSelection();
    const soundfontPlan = planScoreAuditionSoundfonts(score?.tracks, category);
    if (!soundfontPlan.ok) {
      failClosedForSoundfontConflict(soundfontPlan);
      return;
    }
    const currentApi = api;
    if (currentApi && score) {
      await withRenderPreservingPosition(async () => {
        await loadSoundfonts();
        await enqueueRender(() => currentApi.renderScore(score, visibleTracks));
      }, { reloadMidi: true });
    }
  }

  async function restoreSourceInstrument(i: number): Promise<void> {
    const selected = tracks[i];
    if (!selected || selected.percussion || !selected.instrumentOverride || !scoreJsonRaw) return;
    markResumeIntent();
    fretboardAudition.invalidate();
    tracks = tracks.map((track, index) => index === i
      ? { ...track, program: track.sourceProgram, name: track.sourceName, instrumentOverride: false, instrumentFlavor: track.sourceFlavor }
      : track);
    const restoredScore = buildScoreFromJson(scoreDisplayMode);
    score = restoredScore;
    rebuildTrackState(restoredScore);
    publishPrimaryInstrumentSelection();

    const currentApi = api;
    if (!currentApi) return;
    await withRenderPreservingPosition(async () => {
      await loadSoundfonts(currentApi, loadGeneration, playerAbort?.signal ?? null);
      if (api !== currentApi) throw new Error('播放器已更新，原谱音色恢复已取消');
      await enqueueRender(() => currentApi.renderScore(restoredScore, visibleTracks));
    }, { reloadMidi: true });
  }

  async function handleFretboardNoteClick(note: { string: number; fret: number; midi?: number }) {
    const track = primaryInstrumentTrack;
    if (!track || track.percussion) return;
    const midi = note.midi ?? getNoteMidi(note.string, note.fret);
    const generation = fretboardAudition.begin();
    let session: GuitarAudioSession | null = null;
    try {
      session = await acquireGuitarAudioSession();
      if (!fretboardAudition.attach(generation, session, showFretboard)) return;
      await playProgramNote(midi, track.program, 1.2, session, track.instrumentFlavor);
    } catch (reason) {
      if (fretboardAudition.isCurrent(generation, showFretboard)
        && !(reason instanceof DOMException && reason.name === 'AbortError')) {
        renderNotice = reason instanceof Error ? reason.message : '指板试听音色加载失败。';
      }
    } finally {
      if (session) fretboardAudition.finish(session);
    }
  }

  // 进度条拖拽 seek
  function seekStart(e: Event) {
    beginSeekFromInput(e);
  }
  function seekInput(e: Event) {
    const inputTick = clampTick(Number((e.currentTarget as HTMLInputElement).value), endTick);
    if (!dragging || !seekPreviewState || seekPreviewState.generation !== loadGeneration) {
      beginSeekFromInput(e);
      return;
    }
    seekPreviewState = updateSeekPreview(seekPreviewState, inputTick);
    dragTick = inputTick;
  }
  function seekEnd() {
    if (!dragging) return;
    const outcome = settleSeekPreview(seekPreviewState, loadGeneration, 'commit');
    seekPreviewState = null;
    dragging = false;
    if (outcome?.kind !== 'commit') return;
    const targetTick = clampTick(outcome.tick, endTick);
    if (targetTick !== outcome.latestActual.tick && api && score) {
      void seekPracticePosition(targetTick).catch((reason) => {
        if (!(reason instanceof Error) || !reason.message.includes('已取消')) {
          renderNotice = reason instanceof Error ? reason.message : '位置跳转未能确认，请重试。';
        }
      });
    }
  }

  function beginSeekFromInput(e: Event): void {
    const inputTick = clampTick(Number((e.currentTarget as HTMLInputElement).value), endTick);
    const actual = getPracticePositionSnapshot();
    seekPreviewState = beginSeekPreview(loadGeneration, actual, inputTick);
    dragTick = inputTick;
    dragging = true;
  }

  async function runScoreExport(kind: 'print' | 'pdf' | 'image') {
    if (exportBusy || !score) return;
    exportBusy = true;
    exportFailed = false;
    exportMessage = '正在生成谱面，请稍候…';
    try {
      const m = await import('../../lib/printScore');
      if (kind === 'print') await m.printScore(score, title, artist, [...visibleTracks]);
      else if (kind === 'pdf') await m.downloadPdf(score, title, artist, [...visibleTracks]);
      else {
        if (!api) throw new Error('乐谱渲染器尚未就绪。');
        await m.exportScoreToImage(api, title);
      }
      exportMessage = kind === 'print' ? '已发起系统打印。' : '谱面已生成并发起下载，请确认文件保存在设备中。';
    } catch (cause) {
      exportFailed = true;
      exportMessage = `谱面导出未完成：${cause instanceof Error ? cause.message : String(cause)}`;
    } finally { exportBusy = false; }
  }
  const printScore = () => runScoreExport('print');
  const downloadPdf = () => runScoreExport('pdf');
  const exportImage = () => runScoreExport('image');

  let sourceCapoText = $derived(sourceCapoSummary(sourceStaffCapos));
  let primaryOriginalCapo = $derived(primarySourceCapo(sourceStaffCapos, primaryTrackIndex()));
  let activeCapo = $derived(useSourceCapo ? primaryOriginalCapo : capoMode);
  let capoCustomized = $derived(!useSourceCapo && sourceStaffCapos.some((track) => track.some((value) => value !== capoMode)));
  let selectedCapoLabel = $derived(useSourceCapo ? `原谱 · ${sourceCapoText}` : formatCapoValue(capoMode));
  let transposedKeyDisplay = $derived(
    displayKey
      ? displayKey + ' → ' + (transposeKeyName(displayKey, totalTransposition(activeCapo, 0, transpose)) ?? displayKey)
      : ''
  );
  let bannerText = $derived(!loopArmed ? '请点击音符开始' : !loopStartSet ? '请点击开始音符' : !loopEndSet ? '请点击结束音符' : '循环中');
  let playLabel = $derived(playing ? '暂停' : (loadingSounds && playRequested) ? '准备中…' : '播放');
  let tunedTrackCount = $derived(score ? countTabTracks(score) : 0);
  let canMixed = $derived(score ? tunedTrackCount >= 1 : false);
  let isCustomized = $derived(
    speed !== clampTargetBpm(sourceTempo) || Math.abs(playbackRatio - 1) > 0.0001 ||
    capoCustomized ||
    transpose !== 0 ||
    fontScale !== 1
  );
</script>

<div bind:this={scorePlayerCard} class="card relative rounded-3xl border border-[#e2d8c3] bg-gradient-to-b from-[#fbf9f4] via-[#faf7f0] to-[#f5efe4] shadow-[0_16px_48px_rgba(76,59,43,0.06)] score-player-card {isFullscreen ? '!fixed !inset-0 z-[70] !m-0 !overflow-hidden is-score-fullscreen' : ''} {isScoreFixed ? 'is-fixed' : ''}">
  <!-- 四角暗金金属护角装裱 -->
  <div class="pointer-events-none absolute top-3 left-3 w-4 h-4 border-t-2 border-l-2 border-[#c49a45]/40 rounded-tl-sm z-20"></div>
  <div class="pointer-events-none absolute top-3 right-3 w-4 h-4 border-t-2 border-r-2 border-[#c49a45]/40 rounded-tr-sm z-20"></div>
  <div class="pointer-events-none absolute bottom-3 left-3 w-4 h-4 border-b-2 border-l-2 border-[#c49a45]/40 rounded-bl-sm z-20"></div>
  <div class="pointer-events-none absolute bottom-3 right-3 w-4 h-4 border-b-2 border-r-2 border-[#c49a45]/40 rounded-br-sm z-20"></div>

  <!-- 顶部悬浮磨砂主控制条 (Frosted Floating Toolbar) -->
  <div class="relative z-30 flex flex-wrap items-center gap-2.5 sm:gap-3 border-b border-[#e8dfd2] bg-[#fbf9f4]/95 px-4 sm:px-5 py-3 backdrop-blur-md rounded-t-3xl score-toolbar {isFullscreen ? 'hidden' : ''}">
    <!-- 主播放/暂停按键（无需被后台音源加载锁定，点击即可即时响应） -->
    <button
      id="btn-play"
      class="btn min-h-[44px] {playing ? 'btn-primary !bg-signal !border-signal text-paper shadow-xs' : 'btn-primary'} !rounded-pill !px-4 !py-1.5 text-xs font-semibold flex items-center gap-1.5 active:scale-95 transition-all cursor-pointer"
      onclick={playPause}
      disabled={!score || !!error}
      aria-label={playLabel}
    >
      {#if loadingSounds && playRequested}
        <svg class="h-3.5 w-3.5 animate-spin text-current" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <circle cx="12" cy="12" r="10" stroke-opacity="0.25"></circle>
          <path d="M12 2a10 10 0 0 1 10 10" stroke-linecap="round"></path>
        </svg>
      {:else if playing}
        <svg class="h-3.5 w-3.5 fill-current" viewBox="0 0 24 24">
          <rect x="6" y="4" width="4" height="16" rx="1"></rect>
          <rect x="14" y="4" width="4" height="16" rx="1"></rect>
        </svg>
      {:else}
        <svg class="h-3.5 w-3.5 fill-current" viewBox="0 0 24 24">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
      {/if}
      <span>{playLabel}</span>
    </button>

    <button type="button" class="btn btn-ghost min-h-[44px] !rounded-pill !px-3 !py-1.5 text-xs" onclick={stop} disabled={!score} aria-label="重来并回到开头" title="重来并从开头播放">
      <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M3 2v6h6"></path>
        <path d="M3 13a9 9 0 1 0 3-7.7L3 8"></path>
      </svg>
      <span class="hidden sm:inline">重来</span>
    </button>

    <button type="button" class="btn min-h-[44px] {loopArmed ? 'btn-signal !border-signal' : 'btn-ghost'} !rounded-pill !px-3 !py-1.5 text-xs" onclick={toggleLoop} disabled={!score} aria-label={loopArmed ? '取消选定循环区间' : '设置循环区间'} aria-pressed={loopArmed}>
      <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="17 1 21 5 17 9"></polyline>
        <path d="M3 11V9a4 4 0 0 1 4-4h14"></path>
        <polyline points="7 23 3 19 7 15"></polyline>
        <path d="M21 13v2a4 4 0 0 1-4 4H3"></path>
      </svg>
      <span class="hidden sm:inline">循环</span>
    </button>

    <!-- 速度控制 -->
    <div class="flex min-h-[44px] items-center gap-2 rounded-pill border hairline bg-surface-alt px-3 py-1 text-xs">
      <span class="text-mid-gray font-medium">目标 BPM</span>
      <input type="range" min="20" max="300" step="1" value={speed} oninput={(event) => changeSpeed(Number((event.currentTarget as HTMLInputElement).value))} class="min-h-[44px] w-20 sm:w-24" disabled={!score} aria-label="目标播放速度 BPM" />
      <span class="w-7 text-right tabular-nums font-mono font-medium text-ink">{speed}</span>
    </div>

    <!-- 节拍辅助选项 -->
    <div class="hidden lg:flex items-center gap-2 text-xs">
      <label class="inline-flex cursor-pointer items-center gap-1.5 rounded-pill border hairline bg-surface-alt px-2.5 py-1 text-charcoal hover:bg-paper">
        <input type="checkbox" bind:checked={metronome} onchange={toggleMetronome} disabled={!score} class="accent-signal" />
        节拍器
      </label>
      <label class="inline-flex cursor-pointer items-center gap-1.5 rounded-pill border hairline bg-surface-alt px-2.5 py-1 text-charcoal hover:bg-paper">
        <input type="checkbox" bind:checked={countIn} onchange={toggleCountIn} disabled={!score} class="accent-signal" />
        预备拍
      </label>
    </div>

    <!-- 变调夹：按钮+下拉（18px 胶囊浮动面板） -->
    <div class="relative z-40 flex items-center text-xs" bind:this={capoMenuRoot}>
      <button
        bind:this={capoTrigger}
        class="btn btn-ghost min-h-[44px] !rounded-pill !px-3 !py-1.5 text-xs font-medium"
        onclick={() => (capoMenuOpen = !capoMenuOpen)}
        aria-expanded={capoMenuOpen}
        aria-controls="score-capo-options"
        disabled={!score}
      >
        {selectedCapoLabel} · 变调夹
        <svg class="h-3 w-3 ml-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="6 9 12 15 18 9"></polyline>
        </svg>
      </button>
      <div
        id="score-capo-options"
        hidden={!capoMenuOpen}
        inert={!capoMenuOpen}
        class="animate-stagger-in absolute left-0 top-full z-50 mt-1.5 max-h-[min(70dvh,32rem)] w-64 max-w-[calc(100vw-2rem)] overflow-y-auto overscroll-contain rounded-2xl border hairline bg-paper p-1.5 shadow-2xl backdrop-blur-2xl"
        role="group"
        aria-label="变调夹选项"
      >
        <button
          type="button"
          class="block min-h-[44px] w-full rounded-xl px-3 py-2 text-left text-xs font-medium transition hover:bg-canvas focus-visible:outline focus-visible:outline-2 focus-visible:outline-signal {useSourceCapo ? 'text-signal font-semibold bg-signal/10' : 'text-charcoal'}"
          aria-pressed={useSourceCapo}
          onclick={selectSourceCapo}
        >
          <span class="block">使用原谱变调夹</span>
          <span class="mt-0.5 block break-words text-[10px] text-mid-gray">{sourceCapoText}</span>
        </button>
        {#each CAPO_OPTIONS as o}
          <button
            type="button"
            class="block min-h-[44px] w-full rounded-pill px-3 py-1.5 text-left text-xs font-medium transition hover:bg-canvas focus-visible:outline focus-visible:outline-2 focus-visible:outline-signal {!useSourceCapo && o.value === capoMode ? 'text-signal font-semibold bg-signal/10' : 'text-charcoal'}"
            aria-pressed={!useSourceCapo && o.value === capoMode}
            onclick={() => selectCapo(o.value)}
          >
            {o.label}
          </button>
        {/each}
      </div>
    </div>

    <!-- 整曲转调 ±12 半音 -->
    <div class="flex items-center gap-1.5 rounded-pill border hairline bg-surface-alt px-2.5 py-1 text-xs">
      <span class="text-mid-gray font-medium">转调</span>
      <button type="button" class="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-full bg-paper border hairline text-xs font-bold transition hover:bg-canvas disabled:opacity-40" onclick={() => changeTranspose(-1)} disabled={!score || transposePending || transpose <= -12} aria-label="转调降低半音">−</button>
      <span class="w-6 text-center tabular-nums font-mono font-medium text-ink" aria-live="polite">{transpose > 0 ? '+' : ''}{transpose}</span>
      <button type="button" class="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-full bg-paper border hairline text-xs font-bold transition hover:bg-canvas disabled:opacity-40" onclick={() => changeTranspose(1)} disabled={!score || transposePending || transpose >= 12} aria-label="转调升高半音">+</button>
    </div>

    {#if transposedKeyDisplay}
      <span class="text-caption text-signal font-mono font-medium" title="整曲转调后调名">{transposedKeyDisplay}</span>
    {/if}

    <!-- 恢复默认速度/变调夹/转调一键按钮 -->
    <button
      type="button"
      onclick={resetToDefaults}
      disabled={!score || !isCustomized}
      class="btn min-h-[44px] !rounded-pill !px-3 !py-1 text-xs font-medium flex items-center gap-1.5 transition-all {isCustomized ? 'bg-[#faf5eb] border border-[#c49a45]/60 text-[#966b26] hover:bg-[#966b26] hover:text-white shadow-2xs active:scale-95' : 'bg-surface-alt border hairline text-mid-gray/50 opacity-60 cursor-not-allowed'}"
      title="一键恢复默认速度 ({sourceTempo} BPM)、原谱变调夹 ({sourceCapoText}) 与原调 (0 转调)"
      aria-label="恢复默认速度变调转调"
    >
      <svg class="h-3.5 w-3.5 transition-transform" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
        <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"></path>
        <path d="M3 3v5h5"></path>
      </svg>
      <span>恢复默认</span>
      {#if isCustomized}
        <span class="flex h-1.5 w-1.5 rounded-full bg-signal animate-pulse"></span>
      {/if}
    </button>

    <!-- 谱面缩放 -->
    <div class="hidden sm:flex items-center gap-2 rounded-pill border hairline bg-surface-alt px-3 py-1 text-xs">
      <span class="text-mid-gray font-medium">字号</span>
      <input type="range" min="0.6" max="1.6" step="0.05" value={fontScale} oninput={(e) => changeFontScale(Number((e.target as HTMLInputElement).value))} class="w-16" disabled={!score} />
    </div>

    <!-- 和弦模式切换 -->
    <div class="inline-flex items-center rounded-pill border hairline bg-surface-alt p-0.5" role="group" aria-label="和弦显示模式">
      <button type="button" class="min-h-[44px] rounded-pill px-2.5 py-1 text-xs font-medium transition-all {chordMode === 'name' ? 'bg-paper text-ink shadow-xs' : 'text-mid-gray hover:text-ink'}" onclick={() => setChordMode('name')} disabled={!score} aria-pressed={chordMode === 'name'}>仅字母</button>
      <button type="button" class="min-h-[44px] rounded-pill px-2.5 py-1 text-xs font-medium transition-all {chordMode === 'diagram' ? 'bg-paper text-ink shadow-xs' : 'text-mid-gray hover:text-ink'}" onclick={() => setChordMode('diagram')} disabled={!score} aria-pressed={chordMode === 'diagram'}>字母+指法</button>
    </div>

    <!-- 谱面排版模式 -->
    <div class="inline-flex items-center rounded-pill border hairline bg-surface-alt p-0.5" role="group" aria-label="谱面显示模式">
      <button type="button" class="min-h-[44px] rounded-pill px-2.5 py-1 text-xs font-medium transition-all {scoreDisplayMode === SCORE_DISPLAY_MODES.MIXED ? 'bg-paper text-ink shadow-xs' : 'text-mid-gray hover:text-ink'}" onclick={() => setScoreDisplayMode(SCORE_DISPLAY_MODES.MIXED)} disabled={!score || !canMixed} title={canMixed ? '' : '吉他谱+简谱模式不可用'} aria-pressed={scoreDisplayMode === SCORE_DISPLAY_MODES.MIXED}>简谱并排</button>
      <button type="button" class="min-h-[44px] rounded-pill px-2.5 py-1 text-xs font-medium transition-all {scoreDisplayMode === SCORE_DISPLAY_MODES.ALL_TAB ? 'bg-paper text-ink shadow-xs' : 'text-mid-gray hover:text-ink'}" onclick={() => setScoreDisplayMode(SCORE_DISPLAY_MODES.ALL_TAB)} disabled={!score || !canMixed} aria-pressed={scoreDisplayMode === SCORE_DISPLAY_MODES.ALL_TAB}>{isUkulele ? '纯四线谱' : '纯六线谱'}</button>
    </div>

    <button class="btn min-h-[44px] {numberTab ? 'btn-signal' : 'btn-ghost'} !rounded-pill !px-3 !py-1.5 text-xs font-medium hidden sm:inline-flex" onclick={toggleNumberTab} disabled={!score} aria-pressed={numberTab}>数字简谱</button>
    <button class="btn min-h-[44px] {showFretboard ? 'btn-signal !border-signal' : 'btn-ghost'} !rounded-pill !px-3 !py-1.5 text-xs font-medium hidden sm:inline-flex" onclick={toggleFretboard} disabled={!score} aria-pressed={showFretboard}>{isUkulele ? '🪵 尤克里里指板' : '🎸 虚拟指板'}</button>
    <button
      type="button"
      id="score-player-tracks-trigger"
      bind:this={desktopTracksPanelTrigger}
      class="btn btn-ghost min-h-[44px] !rounded-pill !px-3 !py-1.5 text-xs font-medium hidden sm:inline-flex"
      onclick={toggleTracksPanel}
      disabled={!score || tracks.length === 0}
      aria-controls={tracksPanelId}
      aria-expanded={showTracksPanel}
    >音轨分层</button>
    <button
      type="button"
      id="score-player-instruments-trigger"
      bind:this={desktopInstrumentsPanelTrigger}
      class="btn btn-ghost min-h-[44px] !rounded-pill !px-3 !py-1.5 text-xs font-medium hidden sm:inline-flex"
      onclick={toggleInstrumentsPanel}
      disabled={!score || tracks.length === 0}
      aria-controls={instrumentsPanelId}
      aria-expanded={showInstrumentsPanel}
    >音色乐器</button>

    <button class="btn btn-ghost !rounded-pill !px-3 !py-1.5 text-xs font-medium shrink-0" onclick={toggleFullscreen} disabled={!score} title={isFullscreen ? '退出全屏' : '全屏显示乐谱'} aria-label={isFullscreen ? '退出全屏' : '全屏显示乐谱'}>
      <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"></path>
      </svg>
      <span class="hidden sm:inline">{isFullscreen ? '退出全屏' : '全屏'}</span>
    </button>

    <div class="ml-auto flex items-center gap-1.5 sm:gap-2 shrink-0">
      <button class="btn btn-ghost !rounded-pill !px-2.5 sm:!px-3 !py-1.5 text-xs hidden sm:inline-flex" onclick={exportImage} disabled={!score} title="导出高清 PNG 乐谱长图">🖼️ 导出长图</button>
      <button class="btn btn-primary !rounded-pill !px-3 sm:!px-3.5 !py-1.5 text-xs font-medium shadow-xs inline-flex items-center gap-1" onclick={downloadPdf} disabled={!score} title="导出标准 A4 分页 PDF">📄 PDF 导出</button>
      <button class="btn btn-ghost !rounded-pill !px-2.5 sm:!px-3 !py-1.5 text-xs hidden md:inline-flex" onclick={printScore} disabled={!score} title="打印乐谱">🖨️ 打印</button>
    </div>
  </div>

  <!-- 实时位置指示：进度条 + 时间 + 小节/拍号 (Frosted Secondary Bar) -->
  {#if exportMessage}<p role={exportFailed ? 'alert' : 'status'} class="px-4 py-2 text-sm {exportFailed ? 'text-danger' : 'text-mid-gray'}">{exportMessage}</p>{/if}
  <div class="relative z-10 border-b hairline bg-surface-alt/70 px-4 sm:px-5 py-1.5 sm:py-2 {isFullscreen ? 'hidden' : ''}">
    <div class="flex items-center gap-3">
      <span class="w-12 shrink-0 text-right font-mono text-caption tabular-nums text-mid-gray">{formatMilliseconds(curTime)}</span>
      <div class="relative flex h-[44px] flex-1 items-center">
        {#if loopActive && endTick > 0}
          <div
            class="absolute h-1.5 rounded-full"
            style="left:{Math.max(0, (loopStartTick / endTick) * 100)}%;width:{Math.max((Math.min(loopEndTick, endTick) - Math.min(loopStartTick, endTick)) / endTick * 100, 0.6)}%;background:rgba(65,161,207,0.25)"
          ></div>
        {/if}
        <input
          type="range" min="0" max={endTick} step="1"
          value={dragging ? dragTick : pendingSeek?.tick ?? clampTick(curTick, endTick)}
          class="score-progress-slider relative z-10 h-[44px] min-h-[44px] w-full touch-pan-y"
          onpointerdown={seekStart}
          oninput={seekInput}
          onpointerup={seekEnd}
          onpointercancel={cancelSeekPreview}
          onlostpointercapture={cancelSeekPreview}
          onblur={cancelSeekPreview}
          onkeyup={seekEnd}
          disabled={!score || endTick <= 0}
          aria-label="播放进度"
        />
      </div>
      <span class="w-12 shrink-0 font-mono text-caption tabular-nums text-mid-gray">{formatMilliseconds(endTime)}</span>
      <span class="hidden sm:inline-block w-36 shrink-0 text-right font-mono text-caption tabular-nums text-charcoal">
        {#if curBar > 0}第 <strong class="text-ink">{curBar}</strong> 小节 · 第 {curBeat} 拍{:else if loadingSounds}正在准备音源{:else if soundError}音源未就绪{:else if soundReady && !loading}准备就绪{:else}尚未就绪{/if}
      </span>
    </div>
  </div>

  {#if soundError}
    <div role="alert" class="flex flex-wrap items-center justify-center gap-2 border-b hairline bg-red-50/80 px-4 py-2 text-center text-xs font-medium text-danger"><span>{soundError}</span><button type="button" class="min-h-[44px] rounded px-2 underline" disabled={loadingSounds || !api} onclick={retrySoundfonts}>重试音源</button></div>
  {/if}

  <!-- 音轨面板 (Frosted Glass Drawer) -->
  <div
    id={tracksPanelId}
    role="region"
    aria-labelledby="score-player-tracks-trigger"
    aria-hidden={!showTracksPanel || tracks.length === 0}
    inert={!showTracksPanel || tracks.length === 0}
  >
    {#if showTracksPanel && tracks.length > 0}
      <div
        use:registerMotionSurface
        transition:surfaceMotion={{ kind: 'panel' }}
        role="group"
        aria-label="音轨控制"
        onkeydown={closeTracksPanelOnEscape}
        class="grid grid-cols-1 gap-3 border-b hairline bg-surface-alt/90 p-4 backdrop-blur-sm sm:p-5 md:grid-cols-2"
      >
        {#each tracks as tr, i (tr.index)}
          <div class="grid min-w-0 grid-cols-[44px_minmax(0,1fr)] gap-x-2 gap-y-2 rounded-2xl border hairline bg-paper p-3 shadow-2xs">
            <label class="flex min-h-[44px] min-w-[44px] items-center justify-center" aria-label={`显示音轨：${tr.name}`}>
              <input type="checkbox" checked={tr.show} onchange={() => toggleTrack(i)} class="h-4 w-4 accent-signal" aria-label={`显示音轨：${tr.name}`} />
            </label>
            <span class="min-w-0 self-center truncate font-medium text-body-sm text-ink">{tr.name}</span>
            <div class="col-span-2 flex min-w-0 flex-wrap items-center gap-2">
              <button
                type="button"
                class="btn btn-ghost min-h-[44px] min-w-[44px] flex-1 !rounded-pill !px-2.5 !py-1 text-xs sm:flex-none"
                onclick={() => toggleMute(i)}
                aria-label={`静音音轨：${tr.name}`}
                aria-pressed={tr.muted}
              >{tr.muted ? '已静音' : '静音'}</button>
              <button
                type="button"
                class="btn btn-ghost min-h-[44px] min-w-[44px] flex-1 !rounded-pill !px-2.5 !py-1 text-xs sm:flex-none"
                onclick={() => toggleSolo(i)}
                aria-label={`独奏音轨：${tr.name}`}
                aria-pressed={tr.soloed}
              >{tr.soloed ? '已独奏' : '独奏'}</button>
              <input
                type="range"
                min="0"
                max="100"
                step="1"
                value={tr.volume}
                oninput={(e) => changeVolume(i, Number((e.target as HTMLInputElement).value))}
                class="min-h-[44px] min-w-[7rem] flex-1 sm:flex-none"
                aria-label={`音量：${tr.name}`}
              />
            </div>
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- 乐器音色面板 (Frosted Glass Drawer) -->
  <div
    id={instrumentsPanelId}
    role="region"
    aria-labelledby="score-player-instruments-trigger"
    aria-hidden={!showInstrumentsPanel || tracks.length === 0}
    inert={!showInstrumentsPanel || tracks.length === 0}
  >
    {#if showInstrumentsPanel && tracks.length > 0}
      <div
        use:registerMotionSurface
        transition:surfaceMotion={{ kind: 'panel' }}
        role="group"
        aria-label="音色控制"
        onkeydown={closeInstrumentsPanelOnEscape}
        class="grid grid-cols-1 gap-3 border-b hairline bg-surface-alt/90 p-4 backdrop-blur-sm sm:p-5 md:grid-cols-2"
      >
        {#each tracks as tr, i (tr.index)}
          <div class="grid min-w-0 gap-2 rounded-2xl border hairline bg-paper p-3 shadow-2xs sm:grid-cols-[7rem_minmax(0,1fr)] sm:items-center">
            <span class="min-w-0 truncate font-medium text-body-sm text-ink">{tr.name}</span>
            <select
              value={tr.instrumentOverride ? tr.program : 'source'}
              onchange={(e) => {
                const value = (e.target as HTMLSelectElement).value;
                if (value === 'source') void restoreSourceInstrument(i);
                else void changeInstrument(i, Number(value));
              }}
              disabled={tr.percussion}
              class="min-h-[44px] min-w-0 w-full rounded-pill border hairline bg-surface-alt px-3 py-1.5 text-xs text-ink outline-none focus:border-signal"
              aria-label={`音色：${tr.name}`}
            >
              <option value="source">{tr.sourceName}</option>
              {#each GM_INSTRUMENTS as [pg, nm]}
                <option value={pg}>GM {pg} · {nm}</option>
              {/each}
            </select>
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- 虚拟指板展开抽屉 (Live Synchronized Virtual Fretboard) -->
  {#if showFretboard}
    <div class="animate-stagger-in border-b hairline bg-surface-alt/80 p-3 sm:p-4 backdrop-blur-sm">
      <VirtualFretboard
        activeNotes={liveActiveNotes}
        tuning={fretboardTuning}
        capo={activeCapo}
        theme="light"
        showNoteNames={true}
        interactive={true}
        soundEnabled={false}
        program={primaryInstrumentTrack?.program}
        soundfontFlavor={primaryInstrumentTrack?.instrumentFlavor ?? 'gm'}
        currentChord={liveCurrentChord}
        scoreKey={displayKey || 'C'}
        onNoteClick={handleFretboardNoteClick}
      />
    </div>
  {/if}

  <!-- 循环与状态提示条 -->
  {#if loopArmed}
    <div class="px-4 py-2 text-center text-xs font-medium text-paper bg-ink flex items-center justify-center gap-2">
      <span class="h-2 w-2 rounded-full bg-signal animate-pulse"></span>
      <span>{bannerText}</span>
    </div>
  {/if}

  {#if practiceScoreRef}
    <PracticePanel
      score={practiceScoreRef}
      currentTick={curTick}
      currentTime={curTime}
      currentBeatEndTick={currentBeatEndTick}
      lapCompletion={completedLoopLap}
      {loopGeneration}
      {lapInterruptionRevision}
      {resumeIntentRevision}
      {playbackRatio}
      trackMix={practiceTrackMix}
      display={practiceDisplay}
      {endTick}
      currentBar={curBar}
      currentBeat={curBeat}
      currentTickIsSeek={currentTickIsSeek}
      repeatAmbiguous={currentRepeatAmbiguous}
      currentBpm={speed}
      getNativeTempoAtTick={(tick: number) => score && !loading ? nativeTempoAtTick(api?.tickCache?.masterBars, tick) : null}
      capo={activeCapo}
      {useSourceCapo}
      transpose={transpose}
      trackIndexes={visibleTracks}
      {metronome}
      {countIn}
      loop={loopActive ? { startTick: loopStartTick, endTick: loopEndTick } : null}
      {playing}
      focusOwned={audioFocusHeld}
      ready={!!score && !loading && soundReady && !pendingSeek && !dragging}
      onPlay={playPause}
      onPause={pausePlayback}
      onStop={stop}
      onSeek={seekPracticePosition}
      onSetLoop={applyPracticeLoop}
      onClearLoop={endLoop}
      onSpeedChange={changeSpeed}
      onSpeedMultiplier={(multiplier, targetBpm) => setPlaybackRatio(multiplier, targetBpm)}
      onContinue={restorePracticeResume}
      getPositionSnapshot={getPracticePositionSnapshot}
      {onRegisterPracticeLeaveGuard}
    />
  {/if}

  <!-- 谱面容器（绝对保持 AlphaTab 渲染逻辑与 ID 隔离） -->
  <div id="score-scroll" class="score-page render-contain relative z-0 {isFullscreen ? '!max-h-none !rounded-none' : ''} overflow-y-auto rounded-b-3xl p-3 sm:p-4 lg:p-6">
    {#if renderNotice}
      <div role="status" class="relative z-[1] mb-3 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
        <span>{renderNotice}</span>
        <div class="flex shrink-0 items-center gap-2">
          <button type="button" class="btn btn-primary !px-3 !py-1 text-xs" onclick={retryLoad} disabled={loading}>重新加载</button>
          {#if sourceDownloadHref}
            <a class="btn btn-ghost !px-3 !py-1 text-xs" href={sourceDownloadHref} download>下载原谱</a>
          {/if}
        </div>
      </div>
    {/if}
    {#if displayKey || displayTempo > 0}
      <div class="score-page-head mb-4">
        <div class="flex flex-wrap items-baseline gap-x-5 gap-y-1 px-1">
          <span class="score-page-ornament" aria-hidden="true">♩</span>
          {#if displayKey}<span class="score-page-kv">调性 <strong>{displayKey}</strong>{displayTimeSig ? ' · ' + displayTimeSig : ''}</span>{/if}
          {#if displayTempo > 0}<span class="score-page-kv">速度 <strong>♩= {displayTempo}</strong></span>{/if}
          {#if title}<span class="score-page-song ml-auto truncate">{title}</span>{/if}
        </div>
        <div class="score-page-rule" aria-hidden="true"></div>
      </div>
    {/if}
    <ScoreNoteSparkTrails
      {api}
      isPlaying={playing}
      scoreContainer={container}
    />
    <div bind:this={container} class="min-h-[40rem]"></div>
    <div class="score-page-foot">
      <span>{title || '乐谱'}</span>
      <span class="score-page-foot-dot" aria-hidden="true">✦</span>
      <span>MIMI Guitar · 谱页</span>
    </div>
    {#if loading}
      <div class="absolute inset-0 z-10 flex items-center justify-center bg-paper/90 text-mid-gray backdrop-blur-xs">
        <div class="flex flex-col items-center gap-3">
          <div class="h-6 w-6 animate-spin rounded-full border-2 border-signal border-t-transparent"></div>
          <span class="text-body-sm font-medium">乐谱与音频引擎加载中…</span>
        </div>
      </div>
    {:else if error}
      <div class="absolute inset-0 z-10 flex items-center justify-center bg-paper/90 text-danger backdrop-blur-xs">
        <div class="flex flex-col items-center gap-2">
          <svg class="h-6 w-6 text-danger" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <circle cx="12" cy="12" r="10"></circle>
            <line x1="12" y1="8" x2="12" y2="12"></line>
            <line x1="12" y1="16" x2="12.01" y2="16"></line>
          </svg>
          <span role="alert" class="text-body-sm max-w-xl text-center font-medium">{error}</span>
          <div class="mt-2 flex flex-wrap items-center justify-center gap-2">
            {#if errorCanRetry}
              <button type="button" class="btn btn-primary !px-4 !py-1.5 text-xs" onclick={retryLoad}>重试加载</button>
            {/if}
            {#if errorCanDownload && sourceDownloadHref}
              <a class="btn btn-ghost !px-4 !py-1.5 text-xs" href={sourceDownloadHref} download>下载原谱</a>
            {/if}
          </div>
        </div>
      </div>
    {/if}
  </div>

  {#if isFullscreen}
    <!-- 全屏右上角控制组 -->
    <div class="fixed top-4 right-4 z-[80] flex items-start gap-2">
      <!-- 设置面板 -->
      {#if fullscreenSettingsOpen}
        <div class="mr-2 rounded-2xl border border-white/20 bg-black/50 px-3 py-2.5 text-xs text-white backdrop-blur-md space-y-2 min-w-[160px]">
          <!-- 变调夹 -->
          <div class="flex items-center justify-between gap-2">
            <span class="text-white/60">变调夹</span>
            <div class="flex items-center gap-1">
              {#each [0,1,2,3,4,5,6] as n}
                <button
                  class="h-6 w-6 rounded-full text-[10px] font-medium transition {!useSourceCapo && capoMode === n ? 'bg-white/30 text-white' : 'bg-white/10 text-white/60 hover:bg-white/20'}"
                  onclick={() => selectCapo(n)}>
                  {n}
                </button>
              {/each}
            </div>
          </div>
          <!-- 转调 -->
          <div class="flex items-center justify-between gap-2">
            <span class="text-white/60">转调</span>
            <div class="flex items-center gap-1">
              <button class="flex h-6 w-6 items-center justify-center rounded-full bg-white/10 text-xs text-white/80 hover:bg-white/20" onclick={() => changeTranspose(-1)} disabled={transposePending || transpose <= -12}>−</button>
              <span class="w-5 text-center font-mono text-white/90">{transpose > 0 ? '+' : ''}{transpose}</span>
              <button class="flex h-6 w-6 items-center justify-center rounded-full bg-white/10 text-xs text-white/80 hover:bg-white/20" onclick={() => changeTranspose(1)} disabled={transposePending || transpose >= 12}>+</button>
            </div>
          </div>
          <!-- 和弦显示模式 -->
          <div class="flex items-center justify-between gap-2">
            <span class="text-white/60">和弦</span>
            <div class="flex items-center gap-1">
              <button class="rounded-pill px-2 py-0.5 text-[10px] font-medium transition {chordMode === 'name' ? 'bg-white/30 text-white' : 'bg-white/10 text-white/60 hover:bg-white/20'}" onclick={() => setChordMode('name')}>字母</button>
              <button class="rounded-pill px-2 py-0.5 text-[10px] font-medium transition {chordMode === 'diagram' ? 'bg-white/30 text-white' : 'bg-white/10 text-white/60 hover:bg-white/20'}" onclick={() => setChordMode('diagram')}>指法</button>
            </div>
          </div>
          <!-- 谱面显示模式 -->
          <div class="flex items-center justify-between gap-2">
            <span class="text-white/60">谱面</span>
            <div class="flex items-center gap-1">
              <button class="rounded-pill px-2 py-0.5 text-[10px] font-medium transition {scoreDisplayMode === SCORE_DISPLAY_MODES.MIXED ? 'bg-white/30 text-white' : 'bg-white/10 text-white/60 hover:bg-white/20'}" onclick={() => setScoreDisplayMode(SCORE_DISPLAY_MODES.MIXED)}>混排</button>
              <button class="rounded-pill px-2 py-0.5 text-[10px] font-medium transition {scoreDisplayMode === SCORE_DISPLAY_MODES.ALL_TAB ? 'bg-white/30 text-white' : 'bg-white/10 text-white/60 hover:bg-white/20'}" onclick={() => setScoreDisplayMode(SCORE_DISPLAY_MODES.ALL_TAB)}>六线</button>
            </div>
          </div>
        </div>
      {/if}
      <!-- 设置按钮 -->
      <button
        type="button"
        onclick={() => (fullscreenSettingsOpen = !fullscreenSettingsOpen)}
        class="flex h-11 w-11 min-h-[44px] min-w-[44px] items-center justify-center rounded-full border border-white/20 bg-black/30 text-white backdrop-blur-md transition hover:bg-black/50 active:scale-90"
        aria-label="设置"
        title="设置"
      >
        <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="3"></circle>
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path>
        </svg>
      </button>
      <!-- 退出全屏按钮 -->
      <button
        bind:this={fullscreenExitTrigger}
        type="button"
        onclick={toggleFullscreen}
        class="flex h-11 w-11 min-h-[44px] min-w-[44px] items-center justify-center rounded-full border border-white/20 bg-black/30 text-white backdrop-blur-md transition hover:bg-black/50 active:scale-90"
        aria-label="退出全屏"
        title="退出全屏"
      >
        <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
      </button>
    </div>
  {/if}

  <!-- 底部悬浮磨砂胶囊控制台 (Floating HUD) -->
  <FloatingPlayerHUD
    isPlaying={playing}
    {curTime}
    {endTime}
    {curTick}
    {endTick}
    bpm={sourceTempo}
    {playbackRatio}
    {speed}
    {title}
    {artist}
    tracksCount={tracks.length}
    {showTracksPanel}
    {tracksPanelId}
    forceVisible={isFullscreen}
    scrollThreshold={isFullscreen ? 0 : 350}
    disabled={!score || !!error || !soundReady}
    onPlayPause={playPause}
    onSeekStart={seekStart}
    onSeekInput={seekInput}
    onSeekEnd={seekEnd}
    onSeekCancel={cancelSeekPreview}
    seekGeneration={seekUiGeneration}
    pendingSeekTick={pendingSeek?.tick ?? null}
    onChangeSpeed={changeSpeed}
    onToggleTracks={toggleTracksPanel}
  />

  <!-- iOS 设备侧边静音拨片与音量浮动提示胶囊 -->
  {#if showIosSilentHint}
    <div
      role="status"
      aria-live="polite"
      class="fixed bottom-24 left-1/2 -translate-x-1/2 z-50 px-4 py-2 rounded-full bg-[#2c2825]/95 text-[#faf7ef] text-xs sm:text-sm font-serif shadow-2xl border border-[#c49a45]/40 backdrop-blur-md flex items-center gap-2 max-w-[90vw] transition-all duration-500 animate-in fade-in slide-in-from-bottom-2 pointer-events-auto cursor-pointer select-none"
      onclick={() => (showIosSilentHint = false)}
    >
      <span>💡 若听不到声音，请检查手机是否开启侧边静音拨片，并调高媒体音量</span>
      <span class="text-[#c49a45] text-xs font-sans opacity-75 ml-1">✕</span>
    </div>
  {/if}
</div>


<style>
  .score-progress-slider {
    appearance: none;
    margin: 0;
    background: transparent;
    cursor: pointer;
  }
  .score-progress-slider::-webkit-slider-runnable-track {
    height: 4px;
    border-radius: 9999px;
    background: var(--color-hairline);
  }
  .score-progress-slider::-webkit-slider-thumb {
    appearance: none;
    width: 16px;
    height: 16px;
    margin-top: -6px;
    border: 2px solid #fff;
    border-radius: 9999px;
    background: #41a1cf;
    box-shadow: 0 1px 4px rgba(22, 35, 40, 0.25);
  }
  .score-progress-slider::-moz-range-track {
    height: 4px;
    border-radius: 9999px;
    background: var(--color-hairline);
  }
  .score-progress-slider::-moz-range-progress {
    height: 4px;
    background: transparent;
  }
  .score-progress-slider::-moz-range-thumb {
    width: 12px;
    height: 12px;
    border: 2px solid #fff;
    border-radius: 9999px;
    background: #41a1cf;
    box-shadow: 0 1px 4px rgba(22, 35, 40, 0.25);
  }
  .score-progress-slider:focus-visible {
    outline: 2px solid #41a1cf;
    outline-offset: 2px;
    border-radius: 9999px;
  }
  /* —— 谱面「纸页」展示：暖纸渐变 + 发丝框 + 活字印刷风页眉/页脚 —— */
  .score-page {
    background:
      radial-gradient(120% 70% at 50% 0%, rgba(255, 255, 255, 0.55), rgba(255, 255, 255, 0) 55%),
      linear-gradient(180deg, #fdfcf8 0%, #faf7ef 55%, #f5f1e6 100%);
    border: 1px solid #e6dfd0;
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.85),
      0 1px 2px rgba(70, 55, 30, 0.05),
      0 10px 28px rgba(70, 55, 30, 0.07);
  }
  .score-page-head {
    padding: 0.25rem 0.25rem 0;
  }
  .score-page-head .score-page-ornament {
    font-family: var(--font-display);
    color: #b08d57;
    font-size: 1.05rem;
    line-height: 1;
  }
  .score-page-head .score-page-kv {
    font-family: var(--font-display);
    font-size: 0.875rem;
    font-weight: 500;
    letter-spacing: 0.01em;
    color: #4a4237;
  }
  .score-page-head .score-page-kv strong {
    font-weight: 600;
    color: #2d2720;
  }
  .score-page-head .score-page-song {
    font-family: var(--font-display);
    font-size: 0.8125rem;
    font-weight: 400;
    letter-spacing: 0.02em;
    color: #9a8f7c;
  }
  .score-page-rule {
    margin-top: 0.6rem;
    margin-bottom: 1rem;
    height: 1px;
    background: linear-gradient(90deg, #e3dccb, #d9d0bc 50%, #e3dccb);
  }
  .score-page-foot {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    margin-top: 1.75rem;
    padding: 0.875rem 0 0.25rem;
    border-top: 1px solid #ece6d8;
    font-family: var(--font-display);
    font-size: 0.75rem;
    letter-spacing: 0.03em;
    color: #a3967f;
  }
  .score-page-foot-dot {
    color: #c2ab7f;
    font-size: 0.6rem;
  }
  /* 纸页上 AlphaTab 谱面保持清晰墨色 */
  .score-page :global(.at-surface) {
    color: #2d2720;
  }
  /* 工具栏子项：禁止压缩与文字换行（保证按钮横向排布） */
  .score-toolbar > :global(*) {
    flex-shrink: 0;
    white-space: nowrap;
  }
  /* 短视口（横屏手机、小屏设备）：乐谱卡吸顶到导航栏下方，最大化乐谱显示范围 */
  @media (max-height: 600px) {
    .score-player-card.is-fixed {
      display: flex;
      flex-direction: column;
      position: fixed;
      top: 60px;
      left: 0;
      right: 0;
      z-index: 10;
      height: calc(100dvh - 60px);
      max-height: none;
      border-radius: 0;
      margin: 0;
    }
    .score-player-card.is-fixed .score-toolbar {
      flex-wrap: nowrap !important;
      overflow-x: auto;
      -webkit-overflow-scrolling: touch;
      scrollbar-width: none;
    }
    .score-player-card.is-fixed .score-toolbar::-webkit-scrollbar {
      display: none;
    }
    .score-player-card.is-fixed #score-scroll {
      flex: 1;
      min-height: 0;
      max-height: none;
    }
  }
</style>
