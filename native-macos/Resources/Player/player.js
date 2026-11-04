(() => {
  'use strict';

  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mimi;
  const scoreElement = document.getElementById('score');
  const scoreSection = document.getElementById('score');
  const scoreScroll = document.getElementById('score-scroll');
  const scorePageHead = document.getElementById('score-page-head');
  const scorePageKey = document.getElementById('score-page-key');
  const scorePageKeyValue = document.getElementById('score-page-key-value');
  const scorePageTimeSig = document.getElementById('score-page-timesig');
  const scorePageTempo = document.getElementById('score-page-tempo');
  const scorePageTempoValue = document.getElementById('score-page-tempo-value');
  const scorePageSong = document.getElementById('score-page-song');
  const scorePageFoot = document.querySelector('.score-page-foot');
  const scorePageFootTitle = document.getElementById('score-page-foot-title');
  const xheSection = document.getElementById('xhe');
  const xheTitle = document.getElementById('xhe-title');
  const xheContent = document.getElementById('xhe-content');
  const webError = document.getElementById('web-error');
  const BASE = `${location.protocol}//${location.host}`;

  let api = null;
  let runtimeDisposed = false;
  let alphaTabWorkerBlobURL = null;
  let alphaTabWorkerPreparation = null;
  let alphaTabWorkerPreparationAbortController = null;
  let workerFactoryInstalled = false;
  let sourceTempo = 80;
  let requestedTempo = 80;
  let pendingPlaybackSpeedRatio = null;
  let playbackSpeedAckTimer = null;
  let playbackSpeedAckRetryCount = 0;
  let tempoSyncFailedRatio = null;
  let tempoSyncFailedTargetRatio = null;
  const PLAYBACK_SPEED_ACK_TIMEOUT_MS = 1200;
  let zoom = 1;
  let lastViewportWidth = null;
  const BASE_SCORE_SCALE = 0.84;
  const SCORE_FONT_READY_TIMEOUT_MS = 12000;
  const SEEK_ACK_TIMEOUT_MS = 1500;
  const SEEK_PAUSE_STATE_TIMEOUT_MS = 500;
  let scoreFontReadyDocument = null;
  let scoreFontReadyPromise = null;
  let lastPositionMessage = 0;
  let lastPositionSample = null;
  let lastWorkerPositionSample = null;
  let pendingPauseSample = null;
  let pendingInitialRenderBarrier = null;
  let pendingSeek = null;
  let nextSeekRequestID = 0;
  let rawScoreJson = null;
  let scoreSourceMetadata = {};
  let pendingScoreReloadState = null;
  let currentMode = null;
  let activeLoadID = null;
  let generation = 0;
  let sourceAbortController = null;
  let visibleTrackIndexes = [];
  let trackMix = [];
  let pointA = null;
  let playbackRange = null;
  let metronomeEnabled = false;
  let countInEnabled = false;
  let displayMode = window.MimiScoreRendering && window.MimiScoreRendering.defaultDisplayMode || 'mixed';
  let numberTab = true;
  let chordMode = 'diagram';
  let capo = 0;
  let useSourceCapo = true;
  let transpose = 0;
  let sourceCapos = [];
  // 音源计划（与网页版 ScorePlayer 的 flavor/plan 规则一致）：尤克里里类别曲目的
  // 原谱音色使用 ukulele_fast.sf2 的 0/24/25 预设；其它音色使用 GM sonivox。
  const UKULELE_PROGRAMS = new Set([0, 24, 25]);
  const SCORE_GM_SOUNDFONT_PATH = '/soundfonts/sonivox.sf2';
  const SCORE_UKULELE_SOUNDFONT_PATH = '/storage/soundfonts/ukulele_fast.sf2';
  const SOUNDFONT_LOAD_TIMEOUT_MS = 15000;
  const soundfontFetchCache = new Map();
  let scoreCategory = '';
  let gmSoundfontLoaded = false;
  let loadedUkePrograms = new Set();
  let soundfontPlanInitStarted = false;
  let soundfontReadySent = false;
  let soundfontConflictMessage = null;
  let soundfontConflictActive = false;
  let isPlaying = false;
  let isAudibleOwner = false;
  let preserveAudioFocusForRender = false;
  let nativeViewVisible = true;
  let lastTick = null;
  let loopGeneration = 0;
  let interruptionRevision = 0;
  let loopLapSequence = 0;
  let loopLapProgress = null;
  let activeSpeedPlan = null;
  let manuscriptObserver = null;
  let manuscriptPageNodes = [];
  let manuscriptPageCount = 1;
  let manuscriptClickHandler = null;
  let manuscriptScrollHandler = null;
  let manuscriptRefreshTimer = null;
  const seenSpeedLapIDs = new Set();

  // --- Playhead stability helpers ------------------------------------------------
  // AlphaTab's animated beat cursor is a 3px scaled layer driven by CSS transform
  // transitions. Several engine paths re-place it with a 0ms transition, which the
  // user perceives as the red line blinking / jumping:
  //   1. every container resize calls renderer.resizeRender(); its postRenderFinished
  //      handler clears the cached beat and force-places the cursor. While a window
  //      is resizing this happened once per animation frame.
  //   2. pause() rewinds the engine tick to the current beat start and calls
  //      scrollToCursor() before our pause sample could be kept.
  //   3. redundant playbackSpeed / seek writes are implemented as mainSeek and force
  //      another cursor place.
  // The helpers below coalesce or avoid those redundant places.
  const RESIZE_RENDER_COALESCE_MS = 140;
  const SEEK_COALESCE_MS = 70;
  let seekCoalesceTimer = null;
  let seekCoalesceLatestTick = null;
  let seekCoalesceIssuedTick = null;

  function installResizeRenderCoalescer(targetApi) {
    const renderer = targetApi && targetApi.renderer;
    if (!renderer || typeof renderer.resizeRender !== 'function' || renderer.mimiResizeRenderCoalescer) return;
    const originalResizeRender = renderer.resizeRender.bind(renderer);
    let timer = null;
    renderer.resizeRender = () => {
      if (timer !== null) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        try { originalResizeRender(); }
        catch (error) { send('error', { message: '谱面重排失败：' + (error && error.message ? error.message : String(error)) }); }
      }, RESIZE_RENDER_COALESCE_MS);
    };
    renderer.mimiResizeRenderCoalescer = true;
  }

  // AlphaTab's pause handler rewinds the engine to the current beat start (and calls
  // scrollToCursor()) before it emits playerStateChanged; that schedules one forced
  // cursor place at the beat start. The player then restores the sampled tick with a
  // seek, which forces a second place one frame later. Those two places in successive
  // frames are the visible "playhead jumps back and blinks" on pause. While the pause
  // position is being restored the guard below freezes cursor placement and follow
  // scrolling, then places the cursor exactly once at the sampled tick.
  let pauseCursorGuard = null;

  function beginPauseCursorGuard(targetApi) {
    if (!targetApi || pauseCursorGuard) return;
    const original = targetApi._cursorUpdateTick;
    if (typeof original !== 'function') return;
    pauseCursorGuard = { api: targetApi, original };
    targetApi._cursorUpdateTick = function () { /* frozen while the pause position is restored */ };
    const handler = targetApi.customScrollHandler;
    if (handler) handler.suppressScroll = true;
  }

  function endPauseCursorGuard(tick, place = true) {
    const guard = pauseCursorGuard;
    if (!guard) return;
    pauseCursorGuard = null;
    const targetApi = guard.api;
    try { targetApi._cursorUpdateTick = guard.original; } catch (_) { /* api may be disposed */ }
    const handler = targetApi.customScrollHandler;
    if (handler) handler.suppressScroll = false;
    if (!place || targetApi !== api) return;
    const value = Number(tick);
    if (!Number.isFinite(value)) return;
    try { guard.original.call(targetApi, value, false, 1, false, true); } catch (_) { /* keep the last painted frame */ }
  }

  function cancelSeekCoalescer() {
    if (seekCoalesceTimer !== null) clearTimeout(seekCoalesceTimer);
    seekCoalesceTimer = null;
    seekCoalesceLatestTick = null;
    seekCoalesceIssuedTick = null;
  }

  document.documentElement.dataset.motion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches
    ? 'gentle'
    : 'full';

  function scoreRenderingRuntime() {
    const rendering = window.MimiScoreRendering;
    if (!rendering || rendering.alphaTab !== window.alphaTab) {
      throw new Error('乐谱设置与 AlphaTab 播放器运行时不一致。');
    }
    return rendering;
  }

  function ensureScoreFontsReady(loadID, loadGeneration) {
    const targetDocument = document;
    const fontSet = targetDocument.fonts;
    if (!fontSet || typeof fontSet.load !== 'function' || !fontSet.ready || typeof fontSet.ready.then !== 'function') {
      return Promise.reject(new Error('本地谱面字体不可用：当前 WebKit 未提供 document.fonts 字体加载接口。'));
    }

    if (scoreFontReadyDocument !== targetDocument || !scoreFontReadyPromise) {
      // Keep AlphaTab's source font-checker order intact. Its first available family (Cascadia)
      // is sufficient for the CJK fallback chain; preloading FZ here seeds a different static
      // FontSizes table before the source checker can select Cascadia.
      const loadAll = fontSet.load('11px "Cascadia Code"').then(async (faces) => {
        if (!Array.isArray(faces) || faces.length === 0 || faces.some((face) => !face || face.status !== 'loaded')) {
          throw new Error('本地谱面字体不可用：未能加载 Cascadia Code 字体文件。');
        }
        await fontSet.ready;
        if (faces.some((face) => !face || face.status !== 'loaded')) {
          throw new Error('本地谱面字体不可用：Cascadia Code 字体没有完成加载。');
        }
      });
      let sharedPromise;
      const boundedLoad = new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('本地谱面字体加载超时；请重试打开乐谱。')), SCORE_FONT_READY_TIMEOUT_MS);
        loadAll.then(resolve, reject).finally(() => clearTimeout(timer));
      });
      sharedPromise = boundedLoad.catch((error) => {
        if (scoreFontReadyDocument === targetDocument && scoreFontReadyPromise === sharedPromise) {
          scoreFontReadyDocument = null;
          scoreFontReadyPromise = null;
        }
        throw error;
      });
      scoreFontReadyDocument = targetDocument;
      scoreFontReadyPromise = sharedPromise;
    }

    return scoreFontReadyPromise.then(() => loadID === activeLoadID && loadGeneration === generation);
  }

  function positionFields(sample, playing = isPlaying) {
    let current = sample;
    if (!current && api) {
      const speedRatio = Number(api.playbackSpeed) || 1;
      const originalTempo = Number(sourceTempo) > 0 ? Number(sourceTempo) : 80;
      current = {
        currentTime: Number(api.timePosition) || 0,
        endTime: Number(api.endTime) || 0,
        currentTick: Number(api.tickPosition) || 0,
        endTick: Number(api.endTick) || 0,
        isSeek: false,
        originalTempo,
        modifiedTempo: originalTempo * speedRatio,
        speedRatio,
        sampledAtMonotonicMs: performance.now(),
      };
    }
    if (!current) {
      current = {
        currentTime: 0,
        endTime: 0,
        currentTick: 0,
        endTick: 0,
        isSeek: false,
        originalTempo: Number(sourceTempo) || 80,
        modifiedTempo: Number(sourceTempo) || 80,
        speedRatio: 1,
        sampledAtMonotonicMs: performance.now(),
      };
    }
    const currentTime = Number(current.currentTime);
    const endTime = Number(current.endTime);
    const tick = Number(current.currentTick);
    const endTick = Number(current.endTick);
    const originalTempo = Number(current.originalTempo) > 0 ? Number(current.originalTempo) : (Number(sourceTempo) || 80);
    const modifiedTempo = Number(current.modifiedTempo) > 0 ? Number(current.modifiedTempo) : originalTempo * (Number(api && api.playbackSpeed) || 1);
    const speedRatio = Number(current.speedRatio) > 0 ? Number(current.speedRatio) : modifiedTempo / originalTempo;
    return {
      currentTime: Number.isFinite(currentTime) ? currentTime : 0,
      endTime: Number.isFinite(endTime) ? endTime : 0,
      tick: Number.isFinite(tick) ? tick : 0,
      endTick: Number.isFinite(endTick) ? endTick : 0,
      isSeek: !!current.isSeek,
      timeMs: Number.isFinite(currentTime) ? currentTime : 0,
      durationMs: Number.isFinite(endTime) ? endTime : 0,
      speedRatio,
      originalTempo,
      modifiedTempo,
      isPlaying: !!playing,
      sampledAtMonotonicMs: Number.isFinite(Number(current.sampledAtMonotonicMs))
        ? Number(current.sampledAtMonotonicMs)
        : performance.now(),
      beat: findBeatPosition(Number.isFinite(tick) ? tick : 0),
    };
  }

  function currentPositionAnchor(playing = isPlaying) {
    const anchor = positionFields(lastPositionSample, playing);
    if (api) {
      anchor.speedRatio = Number(tempoSyncFailedRatio) > 0
        ? Number(tempoSyncFailedRatio)
        : (Number(api.playbackSpeed) || anchor.speedRatio);
      anchor.modifiedTempo = anchor.originalTempo * anchor.speedRatio;
      anchor.isPlaying = !!playing;
    }
    return anchor;
  }

  function isSameWorkerPosition(left, right) {
    if (!left || !right) return false;
    const pairs = [
      [left.currentTime, right.currentTime],
      [left.endTime, right.endTime],
      [left.currentTick, right.currentTick],
      [left.endTick, right.endTick],
    ];
    return pairs.every(([a, b]) => Number.isFinite(Number(a)) && Number.isFinite(Number(b)) && Math.abs(Number(a) - Number(b)) <= 0.001);
  }

  function hasUnconfirmedApiSeek(targetApi = api) {
    const raw = targetApi && targetApi._player && targetApi._player.currentPosition;
    if (!raw || !raw.isSeek) return false;
    return !lastWorkerPositionSample || !lastWorkerPositionSample.isSeek || !isSameWorkerPosition(raw, lastWorkerPositionSample);
  }

  function capturePauseSample(targetApi = api) {
    if (!targetApi) return null;
    if ((pendingSeek && pendingSeek.api === targetApi) || hasUnconfirmedApiSeek(targetApi)) {
      const confirmed = lastWorkerPositionSample || lastPositionSample;
      if (!confirmed) return null;
      const sample = { ...confirmed, isSeek: false, sampledAtMonotonicMs: performance.now() };
      pendingPauseSample = sample;
      return sample;
    }
    const workerSample = sampleRawWorkerPosition(targetApi);
    if (workerSample) lastWorkerPositionSample = workerSample;
    const playerPosition = targetApi._player && targetApi._player.currentPosition;
    const fallback = lastPositionSample || {};
    const raw = playerPosition || fallback;
    const currentTime = Number(raw.currentTime ?? targetApi.timePosition ?? fallback.currentTime);
    const endTime = Number(raw.endTime ?? targetApi.endTime ?? fallback.endTime);
    const currentTick = Number(raw.currentTick ?? targetApi.tickPosition ?? fallback.currentTick);
    const endTick = Number(raw.endTick ?? targetApi.endTick ?? fallback.endTick);
    const originalTempo = Number(raw.originalTempo) > 0 ? Number(raw.originalTempo) : (Number(sourceTempo) || 80);
    const modifiedTempo = Number(raw.modifiedTempo) > 0 ? Number(raw.modifiedTempo) : originalTempo * (Number(targetApi.playbackSpeed) || 1);
    const sample = normalizePendingSpeedSample({
      currentTime: Number.isFinite(currentTime) ? currentTime : 0,
      endTime: Number.isFinite(endTime) ? endTime : 0,
      currentTick: Number.isFinite(currentTick) ? currentTick : 0,
      endTick: Number.isFinite(endTick) ? endTick : 0,
      isSeek: false,
      originalTempo,
      modifiedTempo,
      speedRatio: modifiedTempo / originalTempo,
      sampledAtMonotonicMs: performance.now(),
    });
    pendingPauseSample = sample;
    lastPositionSample = sample;
    return sample;
  }

  function sampleCurrentPosition(targetApi = api, isSeek = false, applyPendingSpeed = true) {
    if (!targetApi) return null;
    const playerPosition = targetApi._player && targetApi._player.currentPosition;
    const raw = hasUnconfirmedApiSeek(targetApi)
      ? (lastWorkerPositionSample || lastPositionSample || {})
      : (playerPosition || lastPositionSample || {});
    const currentTime = Number(raw.currentTime ?? targetApi.timePosition ?? 0);
    const endTime = Number(raw.endTime ?? targetApi.endTime ?? 0);
    const currentTick = Number(raw.currentTick ?? targetApi.tickPosition ?? 0);
    const endTick = Number(raw.endTick ?? targetApi.endTick ?? 0);
    const originalTempo = Number(raw.originalTempo) > 0 ? Number(raw.originalTempo) : (Number(sourceTempo) || 80);
    const modifiedTempo = Number(raw.modifiedTempo) > 0 ? Number(raw.modifiedTempo) : originalTempo * (Number(targetApi.playbackSpeed) || 1);
    const sample = {
      currentTime: Number.isFinite(currentTime) ? currentTime : 0,
      endTime: Number.isFinite(endTime) ? endTime : 0,
      currentTick: Number.isFinite(currentTick) ? currentTick : 0,
      endTick: Number.isFinite(endTick) ? endTick : 0,
      isSeek: !!isSeek,
      originalTempo,
      modifiedTempo,
      speedRatio: modifiedTempo / originalTempo,
      sampledAtMonotonicMs: performance.now(),
    };
    return applyPendingSpeed ? normalizePendingSpeedSample(sample) : sample;
  }

  function sampleRawWorkerPosition(targetApi = api) {
    const raw = targetApi && targetApi._player && targetApi._player.currentPosition;
    if (!raw) return null;
    if (hasUnconfirmedApiSeek(targetApi)) return lastWorkerPositionSample ? { ...lastWorkerPositionSample } : null;
    const currentTime = Number(raw.currentTime);
    const endTime = Number(raw.endTime);
    const currentTick = Number(raw.currentTick);
    const endTick = Number(raw.endTick);
    const originalTempo = Number(raw.originalTempo) > 0 ? Number(raw.originalTempo) : (Number(sourceTempo) || 80);
    const modifiedTempo = Number(raw.modifiedTempo);
    return {
      currentTime: Number.isFinite(currentTime) ? currentTime : 0,
      endTime: Number.isFinite(endTime) ? endTime : 0,
      currentTick: Number.isFinite(currentTick) ? currentTick : 0,
      endTick: Number.isFinite(endTick) ? endTick : 0,
      isSeek: !!raw.isSeek,
      originalTempo,
      modifiedTempo: Number.isFinite(modifiedTempo) && modifiedTempo > 0 ? modifiedTempo : 0,
      speedRatio: Number.isFinite(modifiedTempo) && modifiedTempo > 0 ? modifiedTempo / originalTempo : 0,
      sampledAtMonotonicMs: performance.now(),
    };
  }

  function positionSpeedRatio(sample) {
    const speedRatio = Number(sample && sample.speedRatio);
    if (Number.isFinite(speedRatio) && speedRatio > 0) return speedRatio;
    const originalTempo = Number(sample && sample.originalTempo);
    const modifiedTempo = Number(sample && sample.modifiedTempo);
    if (originalTempo > 0 && modifiedTempo > 0) return modifiedTempo / originalTempo;
    return 0;
  }

  function speedRatiosMatch(left, right) {
    return Number.isFinite(left) && Number.isFinite(right)
      && Math.abs(left - right) <= Math.max(1e-5, Math.abs(right) * 1e-4);
  }

  function cancelPlaybackSpeedAckWatchdog(resetRetry = false) {
    if (playbackSpeedAckTimer !== null) {
      clearTimeout(playbackSpeedAckTimer);
      playbackSpeedAckTimer = null;
    }
    if (resetRetry) playbackSpeedAckRetryCount = 0;
  }

  function clearPlaybackSpeedSyncState() {
    cancelPlaybackSpeedAckWatchdog(true);
    pendingPlaybackSpeedRatio = null;
    tempoSyncFailedRatio = null;
    tempoSyncFailedTargetRatio = null;
  }

  function finishPlaybackSpeedSync(sample) {
    cancelPlaybackSpeedAckWatchdog(true);
    pendingPlaybackSpeedRatio = null;
    tempoSyncFailedRatio = null;
    tempoSyncFailedTargetRatio = null;
    if (sample) lastPositionSample = sample;
  }

  function tempoControlAnchor(sample, ratio, playing) {
    const anchor = positionFields(sample, playing);
    const originalTempo = Number(sourceTempo) || 80;
    anchor.originalTempo = originalTempo;
    anchor.speedRatio = ratio;
    anchor.modifiedTempo = originalTempo * ratio;
    return anchor;
  }

  function publishPlaybackSpeedAcknowledgement(targetLoadID, sample, ratio) {
    if (!sample || targetLoadID !== activeLoadID) return;
    finishPlaybackSpeedSync(sample);
    lastPositionSample = sample;
    const actualTempo = (Number(sourceTempo) || 80) * ratio;
    requestedTempo = actualTempo;
    if (scorePageTempoValue) scorePageTempoValue.textContent = String(Math.round(actualTempo));
    const anchor = tempoControlAnchor(sample, ratio, isPlaying);
    sendFor(targetLoadID, 'tempo', {
      source: Number(sourceTempo) || 80,
      actual: actualTempo,
      ...anchor,
      anchorReason: 'speedAckRecovered',
    });
    sendFor(targetLoadID, 'playbackState', {
      state: isPlaying ? 1 : 0,
      ...anchor,
      anchorReason: 'speedAckRecovered',
    });
  }

  function failPlaybackSpeedSync(targetApi, targetLoadID, targetRatio, workerSample) {
    if (targetApi !== api || targetLoadID !== activeLoadID || !speedRatiosMatch(Number(pendingPlaybackSpeedRatio), targetRatio)) return;
    cancelPlaybackSpeedAckWatchdog(true);
    try { targetApi.pause(); } catch (_) { /* Still report the observed worker position below. */ }
    isPlaying = false;

    const observedSample = sampleRawWorkerPosition(targetApi)
      || workerSample
      || lastWorkerPositionSample
      || lastPositionSample
      || sampleCurrentPosition(targetApi, false, false);
    const actualRatio = positionSpeedRatio(observedSample) || positionSpeedRatio(lastPositionSample) || 1;
    const actualTempo = (Number(sourceTempo) || 80) * actualRatio;
    pendingPlaybackSpeedRatio = null;
    tempoSyncFailedRatio = actualRatio;
    tempoSyncFailedTargetRatio = targetRatio;
    lastPositionSample = observedSample;
    requestedTempo = actualTempo;
    if (scorePageTempoValue) scorePageTempoValue.textContent = String(Math.round(actualTempo));
    const anchor = tempoControlAnchor(observedSample, actualRatio, false);
    const targetTempo = (Number(sourceTempo) || 80) * targetRatio;
    const message = `播放速度同步失败，已暂停播放；当前实测约 ${Math.round(actualTempo)} BPM。`;

    // Clear the native tempo fence before sending its fallback anchor.
    sendFor(targetLoadID, 'tempoSyncFailed', {
      targetTempo,
      actualTempo,
      speedRatio: actualRatio,
      message,
      ...anchor,
    });
    sendFor(targetLoadID, 'tempo', {
      source: Number(sourceTempo) || 80,
      actual: actualTempo,
      ...anchor,
      anchorReason: 'speedSyncFailed',
    });
  }

  function armPlaybackSpeedAckWatchdog() {
    cancelPlaybackSpeedAckWatchdog(false);
    const targetRatio = Number(pendingPlaybackSpeedRatio);
    const targetApi = api;
    const targetLoadID = activeLoadID;
    if (!targetApi || !targetLoadID || !isPlaying || !(targetRatio > 0)) return;

    playbackSpeedAckTimer = setTimeout(() => {
      playbackSpeedAckTimer = null;
      if (targetApi !== api || targetLoadID !== activeLoadID || !isPlaying
        || !speedRatiosMatch(Number(pendingPlaybackSpeedRatio), targetRatio)) return;

      const workerSample = sampleRawWorkerPosition(targetApi);
      const workerRatio = positionSpeedRatio(workerSample);
      if (speedRatiosMatch(workerRatio, targetRatio)) {
        publishPlaybackSpeedAcknowledgement(targetLoadID, workerSample, targetRatio);
        return;
      }

      if (playbackSpeedAckRetryCount === 0) {
        playbackSpeedAckRetryCount = 1;
        try {
          if (!speedRatiosMatch(Number(targetApi.playbackSpeed), targetRatio)) targetApi.playbackSpeed = targetRatio;
          armPlaybackSpeedAckWatchdog();
          return;
        } catch (_) {
          // A failed retry takes the same explicit pause-and-report path.
        }
      }
      failPlaybackSpeedSync(targetApi, targetLoadID, targetRatio, workerSample);
    }, PLAYBACK_SPEED_ACK_TIMEOUT_MS);
  }

  function retimePositionSample(sample, targetRatio, originalTempoOverride = null) {
    const nextRatio = Number(targetRatio);
    const oldRatio = positionSpeedRatio(sample);
    const scale = oldRatio > 0 && nextRatio > 0 ? oldRatio / nextRatio : 1;
    const sampleOriginalTempo = Number(sample && sample.originalTempo);
    const originalTempo = Number(originalTempoOverride) > 0
      ? Number(originalTempoOverride)
      : (sampleOriginalTempo > 0 ? sampleOriginalTempo : (Number(sourceTempo) || 80));
    const currentTime = Number(sample && sample.currentTime);
    const endTime = Number(sample && sample.endTime);
    return {
      ...(sample || {}),
      currentTime: Number.isFinite(currentTime) ? currentTime * scale : 0,
      endTime: Number.isFinite(endTime) ? endTime * scale : 0,
      originalTempo,
      modifiedTempo: originalTempo * nextRatio,
      speedRatio: nextRatio,
      sampledAtMonotonicMs: performance.now(),
    };
  }

  function normalizePendingSpeedSample(sample) {
    if (!sample || !(Number(pendingPlaybackSpeedRatio) > 0)) return sample;
    if (speedRatiosMatch(positionSpeedRatio(sample), Number(pendingPlaybackSpeedRatio))) return sample;
    return retimePositionSample(sample, pendingPlaybackSpeedRatio);
  }

  function setScorePageHeader(score, metadata = {}) {
    const firstStaff = score && score.tracks && score.tracks.find((track) => track.staves && track.staves.length)?.staves?.[0];
    const firstBar = firstStaff && firstStaff.bars && firstStaff.bars[0];
    const masterBar = score && score.masterBars && score.masterBars[0]
      || firstBar && firstBar.masterBar;
    const signature = Number(firstBar && firstBar.keySignature);
    const signatureType = Number(firstBar && firstBar.keySignatureType);
    const rendering = window.MimiScoreRendering;
    const key = metadata.key || (rendering && rendering.keySignatureName(signature, signatureType)) || '';
    const numerator = Number(masterBar && masterBar.timeSignatureNumerator);
    const denominator = Number(masterBar && masterBar.timeSignatureDenominator);
    const timeSignature = numerator > 0 && denominator > 0 ? `${numerator}/${denominator}` : '';
    const title = String(score && score.title || metadata.title || '');
    const tempo = Number(sourceTempo) > 0 ? Number(sourceTempo) : Number(metadata.bpm) || 0;
    scorePageHead.hidden = !key && !(tempo > 0);
    scorePageKey.hidden = !key;
    scorePageKeyValue.textContent = key;
    scorePageTimeSig.textContent = timeSignature ? ` · ${timeSignature}` : '';
    scorePageTempo.hidden = !(tempo > 0);
    scorePageTempoValue.textContent = tempo > 0 ? String(Math.round(tempo)) : '';
    scorePageSong.textContent = title;
    scorePageFootTitle.textContent = title || '乐谱';
    scorePageFoot.hidden = false;
  }

  function installAlphaTabWorkerFactory(alphaTab, workerBlobURL) {
    const environment = alphaTab && alphaTab.Environment;
    if (!environment || typeof environment.initializeMain !== 'function') {
      throw new Error('本地 AlphaTab worker 接口不可用。');
    }
    environment.initializeMain((settings, name) => {
      if (runtimeDisposed || alphaTabWorkerBlobURL !== workerBlobURL) {
        throw new Error('本地 AlphaTab worker 已关闭。');
      }
      return new Worker(workerBlobURL, { name });
    }, (context, settings) => context.audioWorklet.addModule(settings.core.scriptFile));
    workerFactoryInstalled = true;
  }

  async function prepareAlphaTabWorker() {
    const alphaTab = window.alphaTab;
    if (!alphaTab || !alphaTab.Environment || typeof alphaTab.Environment.initializeMain !== 'function') {
      throw new Error('本地 AlphaTab worker 接口不可用。');
    }
    if (runtimeDisposed) throw new Error('播放器页面已关闭。');
    if (alphaTabWorkerBlobURL) {
      if (!workerFactoryInstalled) installAlphaTabWorkerFactory(alphaTab, alphaTabWorkerBlobURL);
      return;
    }
    if (!alphaTabWorkerPreparation) {
      const controller = new AbortController();
      alphaTabWorkerPreparationAbortController = controller;
      const preparation = (async () => {
        const response = await fetch(`${BASE}/alphaTab.js`, { signal: controller.signal });
        if (!response.ok) throw new Error(`本地 AlphaTab worker 读取失败（${response.status}）。`);
        const runtimeSource = await response.text();
        if (runtimeDisposed || controller.signal.aborted) return;
        const blobURL = URL.createObjectURL(new Blob([runtimeSource], { type: 'text/javascript' }));
        if (runtimeDisposed || controller.signal.aborted) {
          URL.revokeObjectURL(blobURL);
          return;
        }
        alphaTabWorkerBlobURL = blobURL;
        try {
          installAlphaTabWorkerFactory(alphaTab, blobURL);
        } catch (error) {
          alphaTabWorkerBlobURL = null;
          URL.revokeObjectURL(blobURL);
          throw error;
        }
      })();
      alphaTabWorkerPreparation = preparation;
    }
    const preparation = alphaTabWorkerPreparation;
    try {
      await preparation;
    } finally {
      if (alphaTabWorkerPreparation === preparation) alphaTabWorkerPreparation = null;
      if (alphaTabWorkerPreparationAbortController && alphaTabWorkerPreparation === null) {
        alphaTabWorkerPreparationAbortController = null;
      }
    }
    if (runtimeDisposed) throw new Error('播放器页面已关闭。');
    if (!alphaTabWorkerBlobURL || !workerFactoryInstalled) throw new Error('本地 AlphaTab worker 准备失败。');
  }

  function normalizeScoreCategory(value) {
    const raw = typeof value === 'string' ? value.trim().toLowerCase() : '';
    return ['guitar', 'ukulele', 'bass'].includes(raw) ? raw : '';
  }

  function gmInstrumentName(program) {
    const gm = window.NativePracticeCore && window.NativePracticeCore.gmInstruments;
    if (Array.isArray(gm)) {
      const entry = gm.find((pair) => Array.isArray(pair) && Number(pair[0]) === program);
      if (entry && typeof entry[1] === 'string' && entry[1]) return String(entry[1]);
    }
    return `MIDI ${program + 1}`;
  }

  function trackTunings(track) {
    const tunings = [];
    for (const staff of (track.staves || [])) {
      const tuning = staff && ((staff.stringTuning && staff.stringTuning.tunings) || staff.tuning);
      if (Array.isArray(tuning) && tuning.length > 0) tunings.push(tuning.map((value) => Number(value)));
    }
    return tunings;
  }

  function isPercussionTrack(track) {
    return !!(track && (track.isPercussion || (track.staves || []).some((staff) => staff && staff.isPercussion)));
  }

  function isFourStringTrack(track) {
    return trackTunings(track).some((tuning) => tuning.length === 4);
  }

  /** 原谱音源类别：ukulele 仅当 category=ukulele/未知导入 + 4 弦 + program∈{0,24,25}。 */
  function resolveSourceFlavor(track) {
    const program = Number(track && track.playbackInfo && track.playbackInfo.program);
    if (!Number.isSafeInteger(program) || !UKULELE_PROGRAMS.has(program)) return 'gm';
    if (isPercussionTrack(track)) return 'gm';
    const category = normalizeScoreCategory(scoreCategory);
    if (category === 'bass') return 'gm';
    if (category === 'ukulele') return isFourStringTrack(track) ? 'ukulele' : 'gm';
    // 本地导入/缺类别数据：四弦 + 原谱吉他系 program 时按尤克里里原谱处理。
    return isFourStringTrack(track) ? 'ukulele' : 'gm';
  }

  function sourceInstrumentLabel(program, flavor, percussion) {
    if (percussion) return '原谱 · 打击乐';
    if (flavor === 'ukulele') {
      const preset = program === 0 ? '原声' : program === 24 ? '尼龙弦' : program === 25 ? '钢弦' : '';
      return `原谱 · 尤克里里${preset ? `（${preset}）` : ''}`;
    }
    return `原谱 · ${gmInstrumentName(program)}`;
  }

  function instrumentAutomationType() {
    const type = window.alphaTab && window.alphaTab.model && window.alphaTab.model.AutomationType
      ? window.alphaTab.model.AutomationType.Instrument
      : null;
    return Number.isSafeInteger(type) ? type : 2;
  }

  function trackProgramsUsed(track) {
    const programs = new Set();
    const initial = Number(track && track.playbackInfo && track.playbackInfo.program);
    if (Number.isSafeInteger(initial) && initial >= 0 && initial <= 127) programs.add(initial);
    const instrumentType = instrumentAutomationType();
    for (const staff of (track.staves || [])) for (const bar of (staff.bars || [])) {
      for (const voice of (bar.voices || [])) for (const beat of (voice.beats || [])) {
        for (const automation of (beat.automations || [])) {
          if (!automation) continue;
          const type = automation.type;
          if (type !== instrumentType && type !== 'Instrument') continue;
          const value = Number(automation.value);
          if (Number.isSafeInteger(value) && value >= 0 && value <= 127) programs.add(value);
        }
      }
    }
    return programs;
  }

  /**
   * 汇总当前音轨组合需要的音源预设（与网页版 planScoreAuditionSoundfonts 等价）。
   * 同一个 bank:program 被同时要求 GM 与尤克里里音源时返回冲突，调用方应暂停并提示。
   */
  function computeSoundfontPlan() {
    const gmPrograms = new Set();
    const ukePrograms = new Set();
    if (!api || !api.score) return { ok: true, gmPrograms, ukePrograms };
    for (const state of trackMix) {
      const track = api.score.tracks[state.index];
      if (!track) continue;
      if (isPercussionTrack(track)) { gmPrograms.add(128); continue; }
      if (state.instrumentOverride) {
        const program = Number(state.program);
        if (Number.isSafeInteger(program) && program >= 0 && program <= 127) gmPrograms.add(program);
        continue;
      }
      const flavor = state.sourceFlavor || state.flavor || 'gm';
      // 使用创建音轨状态时记录的原始 program 集合：当前 score 的 program/自动化
      // 可能已被一次音色覆盖改写，不能作为“原谱音源需要什么”的可靠来源。
      const sourcePrograms = Array.isArray(state.sourcePrograms) && state.sourcePrograms.length
        ? state.sourcePrograms
        : [state.sourceProgram];
      for (const rawProgram of sourcePrograms) {
        const program = Number(rawProgram);
        if (!Number.isSafeInteger(program) || program < 0 || program > 127) continue;
        if (flavor === 'ukulele' && UKULELE_PROGRAMS.has(program)) ukePrograms.add(program);
        else gmPrograms.add(program);
      }
    }
    for (const program of ukePrograms) {
      if (gmPrograms.has(program)) return { ok: false, bank: 0, program, gmPrograms, ukePrograms };
    }
    return { ok: true, gmPrograms, ukePrograms };
  }

  function soundfontConflictText(plan) {
    return `音轨音色冲突：bank ${plan.bank} program ${plan.program} 同时需要 GM 与尤克里里音源，当前音轨组合无法安全播放。请把该音轨恢复原谱音色，或把另一条音轨换成其它音色。`;
  }

  async function fetchSoundfontBytes(path) {
    if (soundfontFetchCache.has(path)) return soundfontFetchCache.get(path);
    const response = await fetch(`${BASE}${path}`, { cache: 'no-store' });
    if (!response.ok) throw new Error(`本地音源读取失败（${response.status}）：${path}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0) throw new Error(`本地音源内容为空：${path}`);
    soundfontFetchCache.set(path, bytes);
    return bytes;
  }

  function loadSoundfontAndWait(targetApi, bytes, append) {
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer = null;
      const cleanup = () => { try { targetApi.soundFontLoaded.off(onLoaded); } catch (_) { /* emitter gone */ } };
      const finish = (error) => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timer) clearTimeout(timer);
        if (error) reject(error);
        else resolve();
      };
      const onLoaded = () => finish(null);
      try { targetApi.soundFontLoaded.on(onLoaded); }
      catch (error) { reject(error); return; }
      timer = setTimeout(() => finish(new Error('等待本地音源加载超时。')), SOUNDFONT_LOAD_TIMEOUT_MS);
      try { targetApi.loadSoundFont(bytes, append === true); }
      catch (error) { finish(error); }
    });
  }

  // ---- SF2 预设过滤（移植自网页版 verifiedScoreSoundfont.ts）--------------------
  // ukulele_fast.sf2 同时含 bank0 的 0/24/25 三个预设；整包 append 会把同 program 的
  // GM 预设（例如 Vocal 轨的 program 0 钢琴）也覆盖成尤克里里。因此只保留需要的预设。
  const sf2TextDecoder = new TextDecoder('ascii');
  const sf2TextEncoder = new TextEncoder();

  function sf2ReadU16(bytes, offset) { return bytes[offset] | (bytes[offset + 1] << 8); }

  function sf2ReadU32(bytes, offset) {
    return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
  }

  function sf2WriteU32(bytes, offset, value) {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >>> 8) & 0xff;
    bytes[offset + 2] = (value >>> 16) & 0xff;
    bytes[offset + 3] = (value >>> 24) & 0xff;
  }

  function sf2ChunkId(bytes, offset) {
    return sf2TextDecoder.decode(bytes.subarray(offset, offset + 4));
  }

  function sf2ReadChunks(bytes, start, end) {
    const chunks = [];
    let offset = start;
    while (offset < end) {
      if (offset + 8 > end) throw new Error('SF2 数据损坏：chunk 头被截断。');
      const id = sf2ChunkId(bytes, offset);
      const size = sf2ReadU32(bytes, offset + 4);
      const dataStart = offset + 8;
      const chunkEnd = dataStart + size;
      const paddedEnd = chunkEnd + (size & 1);
      if (chunkEnd > end || paddedEnd > end) throw new Error(`SF2 数据损坏：${id} 越界。`);
      chunks.push({ id, start: offset, dataStart, size, end: chunkEnd, paddedEnd });
      offset = paddedEnd;
    }
    return chunks;
  }

  function sf2MakeChunk(id, payload) {
    const result = new Uint8Array(8 + payload.byteLength + (payload.byteLength & 1));
    result.set(sf2TextEncoder.encode(id), 0);
    sf2WriteU32(result, 4, payload.byteLength);
    result.set(payload, 8);
    return result;
  }

  function sf2Concat(parts) {
    let size = 0;
    for (const part of parts) size += part.byteLength;
    const result = new Uint8Array(size);
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.byteLength; }
    return result;
  }

  /** 返回仅保留指定 bank:program 预设的合法 SF2 数据（其余 pbag/pgen 索引保持不变）。 */
  function filterSoundfontPreset(input, bank, program) {
    const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
    if (bytes.byteLength < 12 || sf2ChunkId(bytes, 0) !== 'RIFF' || sf2ChunkId(bytes, 8) !== 'sfbk') {
      throw new Error('尤克里里音源不是有效的 SF2 文件。');
    }
    const rootChunks = sf2ReadChunks(bytes, 12, bytes.byteLength);
    const listChunks = rootChunks.filter((chunk) => chunk.id === 'LIST' && chunk.size >= 4);
    const pdta = listChunks.find((chunk) => sf2ChunkId(bytes, chunk.dataStart) === 'pdta');
    if (!pdta) throw new Error('尤克里里音源缺少 pdta 表。');
    const pdtaChildren = sf2ReadChunks(bytes, pdta.dataStart + 4, pdta.end);
    const phdrChunk = pdtaChildren.find((chunk) => chunk.id === 'phdr');
    if (!phdrChunk) throw new Error('尤克里里音源缺少 phdr 表。');
    const phdr = bytes.subarray(phdrChunk.dataStart, phdrChunk.end);
    if (phdr.byteLength % 38 !== 0) throw new Error('尤克里里音源的 phdr 表不完整。');
    const rows = phdr.byteLength / 38;
    let presetIndex = -1;
    for (let index = 0; index < rows - 1; index += 1) {
      const offset = index * 38;
      if (sf2ReadU16(phdr, offset + 20) !== program || sf2ReadU16(phdr, offset + 22) !== bank) continue;
      presetIndex = index;
      break;
    }
    if (presetIndex < 0) throw new Error(`尤克里里音源缺少 bank ${bank} program ${program} 预设。`);
    const filteredPhdr = new Uint8Array(76);
    filteredPhdr.set(phdr.subarray(presetIndex * 38, (presetIndex + 1) * 38), 0);
    filteredPhdr.set(phdr.subarray((rows - 1) * 38, rows * 38), 38);
    // 预设记录第 24 字节起是 bag 索引；下一记录的 bag 索引即本预设的 bag 结束位置。
    // 两者必须在拷贝 EOP 记录之后再写，否则 presetIndex=0 时 EOP 拷贝会覆盖 bag 结束位置。
    filteredPhdr.set(phdr.subarray(presetIndex * 38 + 24, presetIndex * 38 + 26), 24);
    filteredPhdr.set(phdr.subarray((presetIndex + 1) * 38 + 24, (presetIndex + 1) * 38 + 26), 38 + 24);
    const rewrittenChildren = pdtaChildren.map((chunk) => chunk.id === 'phdr'
      ? sf2MakeChunk('phdr', filteredPhdr)
      : bytes.subarray(chunk.start, chunk.paddedEnd));
    const pdtaPayload = sf2Concat([sf2TextEncoder.encode('pdta'), ...rewrittenChildren]);
    const rewrittenRoot = rootChunks.map((chunk) => chunk.start === pdta.start
      ? sf2MakeChunk('LIST', pdtaPayload)
      : bytes.subarray(chunk.start, chunk.paddedEnd));
    return sf2MakeChunk('RIFF', sf2Concat([sf2TextEncoder.encode('sfbk'), ...rewrittenRoot]));
  }

  /**
   * 让 AlphaTab 的预设表与当前 trackMix 计划一致。
   * 返回 false 表示计划冲突（已发送 soundfontConflict），调用方不得继续播放。
   */
  async function ensureSoundfontPlan(targetApi) {
    if (!targetApi || targetApi !== api) return true;
    const plan = computeSoundfontPlan();
    if (!plan.ok) {
      const message = soundfontConflictText(plan);
      soundfontConflictActive = true;
      if (message !== soundfontConflictMessage) {
        soundfontConflictMessage = message;
        send('soundfontConflict', { message });
      }
      return false;
    }
    soundfontConflictMessage = null;
    if (soundfontConflictActive) {
      // 冲突解除后重新宣告音源就绪，让原生层恢复播放能力。
      soundfontConflictActive = false;
      send('soundReady');
    }
    if (!gmSoundfontLoaded) return true;
    const gmCollision = [...plan.gmPrograms].filter((program) => program !== 128 && loadedUkePrograms.has(program));
    const missingUke = [...plan.ukePrograms].filter((program) => !loadedUkePrograms.has(program));
    if (gmCollision.length === 0 && missingUke.length === 0) return true;
    if (gmCollision.length === 0) {
      // 只缺尤克里里预设时直接 append（last-match 覆盖同 program 的 GM 预设）；
      // 冲突规则已保证当前计划里没有 GM 轨占用这些 program。
      const ukuleleBytes = await fetchSoundfontBytes(SCORE_UKULELE_SOUNDFONT_PATH);
      for (const program of missingUke.sort((left, right) => left - right)) {
        const filtered = filterSoundfontPreset(ukuleleBytes, 0, program);
        await loadSoundfontAndWait(targetApi, filtered, true);
        loadedUkePrograms.add(program);
      }
      return true;
    }

    // 需要移除已加载的尤克里里预设时，按网页版顺序整份重载：
    // 先 GM（append=false），再逐个过滤后的尤克里里预设（append=true）。
    targetApi.resetSoundFonts();
    gmSoundfontLoaded = false;
    loadedUkePrograms = new Set();
    const gmBytes = await fetchSoundfontBytes(SCORE_GM_SOUNDFONT_PATH);
    await loadSoundfontAndWait(targetApi, gmBytes, false);
    gmSoundfontLoaded = true;
    if (plan.ukePrograms.size > 0) {
      const ukuleleBytes = await fetchSoundfontBytes(SCORE_UKULELE_SOUNDFONT_PATH);
      for (const program of [...plan.ukePrograms].sort((left, right) => left - right)) {
        const filtered = filterSoundfontPreset(ukuleleBytes, 0, program);
        await loadSoundfontAndWait(targetApi, filtered, true);
        loadedUkePrograms.add(program);
      }
    }
    return true;
  }

  function sendSoundReady(loadID) {
    if (soundfontReadySent) return;
    soundfontReadySent = true;
    sendFor(loadID, 'soundReady');
  }

  function trackSnapshot() {
    if (!api || !api.score) return [];
    return api.score.tracks.map((track, index) => {
      const existing = trackMix.find((value) => value.index === index);
      const program = Number(track.playbackInfo && track.playbackInfo.program);
      const percussion = isPercussionTrack(track) || program === 128;
      const safeProgram = Number.isSafeInteger(program) ? program : 0;
      return {
        index,
        name: String(track.name || `音轨 ${index + 1}`),
        program: percussion ? 128 : safeProgram,
        sourceProgram: existing ? existing.sourceProgram : safeProgram,
        sourceCapo: sourceCapos[index] && sourceCapos[index].length ? sourceCapos[index][0] : 0,
        percussion,
        show: visibleTrackIndexes.includes(index),
        muted: existing ? existing.muted : false,
        soloed: existing ? existing.soloed : false,
        volume: existing ? existing.volume : 1,
        instrumentOverride: existing ? !!existing.instrumentOverride : false,
        sourceFlavor: existing ? (existing.sourceFlavor || 'gm') : 'gm',
        instrumentFlavor: existing ? (existing.instrumentOverride ? 'gm' : (existing.sourceFlavor || 'gm')) : 'gm',
        sourceName: existing ? existing.sourceLabel : sourceInstrumentLabel(safeProgram, 'gm', percussion),
        tuning: (track.staves && track.staves[0] && track.staves[0].stringTuning && track.staves[0].stringTuning.tunings || []).map((value) => Number(value)),
      };
    });
  }

  function applyTrackProgram(track, program) {
    if (!track || isPercussionTrack(track) || !Number.isSafeInteger(program) || program < 0 || program > 127) return;
    const name = gmInstrumentName(program);
    track.playbackInfo.program = program;
    track.name = name;
    track.shortName = name;
    const instrumentType = instrumentAutomationType();
    for (const staff of (track.staves || [])) for (const bar of (staff.bars || [])) {
      for (const voice of (bar.voices || [])) for (const beat of (voice.beats || [])) {
        for (const automation of (beat.automations || [])) if (automation && automation.type === instrumentType) automation.value = program;
      }
    }
  }

  /** 恢复某轨原谱音色：program、名称与 Instrument 自动化都要回到原谱值。 */
  function restoreTrackProgramToSource(track, state) {
    if (!track || !state || isPercussionTrack(track)) return;
    track.playbackInfo.program = state.sourceProgram;
    const name = state.sourceName || `音轨 ${state.index + 1}`;
    track.name = name;
    track.shortName = name;
    const instrumentType = instrumentAutomationType();
    for (const staff of (track.staves || [])) for (const bar of (staff.bars || [])) {
      for (const voice of (bar.voices || [])) for (const beat of (voice.beats || [])) {
        for (const automation of (beat.automations || [])) if (automation && automation.type === instrumentType) automation.value = state.sourceProgram;
      }
    }
  }

  /** 兼容旧断点：缺 instrumentOverride 时用 program 与当前原谱 program 的差异推断。 */
  function resolveSavedInstrument(sourceProgram, savedProgram, savedOverride) {
    const validSavedProgram = Number.isSafeInteger(savedProgram) && savedProgram >= 0 && savedProgram <= 127;
    if (savedOverride === true) {
      return validSavedProgram ? { program: savedProgram, instrumentOverride: true } : { program: sourceProgram, instrumentOverride: false };
    }
    if (savedOverride === false) return { program: sourceProgram, instrumentOverride: false };
    if (validSavedProgram && savedProgram !== sourceProgram) return { program: savedProgram, instrumentOverride: true };
    return { program: sourceProgram, instrumentOverride: false };
  }

  function clampTrackVolume(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : 1;
  }

  function createTrackMixState(score, previous = null, visible = null) {
    const previousByIndex = new Map((previous || []).map((state) => [state.index, state]));
    return score.tracks.map((track, index) => {
      const old = previousByIndex.get(index);
      const percussion = isPercussionTrack(track);
      const sourceProgram = percussion ? 0 : (Number(track.playbackInfo && track.playbackInfo.program) || 0);
      const sourceFlavor = old && old.sourceFlavor ? old.sourceFlavor : resolveSourceFlavor(track);
      const sourceTrackName = String(track.name || `音轨 ${index + 1}`);
      const sourceLabel = sourceInstrumentLabel(sourceProgram, sourceFlavor, percussion);
      const sourceVolume = clampTrackVolume((Number(track.playbackInfo && track.playbackInfo.volume) || 15) / 16);
      const state = old
        ? {
          ...old,
          index,
          sourceProgram: Number.isSafeInteger(old.sourceProgram) ? old.sourceProgram : sourceProgram,
          sourceName: old.sourceName || sourceTrackName,
          sourceFlavor,
          sourceLabel,
          program: percussion ? 128 : Number(old.program),
          sourcePrograms: Array.isArray(old.sourcePrograms) && old.sourcePrograms.length
            ? old.sourcePrograms
            : [old.sourceProgram],
          flavor: percussion ? 'gm' : (old.instrumentOverride ? 'gm' : sourceFlavor),
        }
        : {
          index,
          show: visible ? visible.includes(index) : true,
          muted: false,
          soloed: false,
          volume: sourceVolume,
          program: percussion ? 128 : sourceProgram,
          sourceProgram,
          sourcePrograms: [...trackProgramsUsed(track)],
          sourceName: sourceTrackName,
          sourceFlavor,
          sourceLabel,
          flavor: sourceFlavor,
          instrumentOverride: false,
        };
      if (!old) state.program = percussion ? 128 : sourceProgram;
      if (state.instrumentOverride && !percussion) {
        applyTrackProgram(track, Number(state.program));
      }
      return state;
    });
  }

  function applyTrackMixToApi(targetApi) {
    if (!targetApi || !targetApi.score) return;
    for (const state of trackMix) {
      const track = targetApi.score.tracks[state.index];
      if (!track) continue;
      targetApi.changeTrackMute([track], state.muted || state.show === false);
      targetApi.changeTrackSolo([track], state.soloed);
      targetApi.changeTrackVolume([track], state.volume);
    }
  }

  function sendPlayerState() {
    if (!api || !api.score) return;
    send('playerSnapshot', {
      tracks: trackSnapshot(),
      scoreEndTick: Number(api.endTick) || 0,
      gmInstruments: window.NativePracticeCore ? window.NativePracticeCore.gmInstruments : [],
      category: scoreCategory,
      soundfontConflict: soundfontConflictMessage,
      displayMode,
      numberTab,
      chordMode,
      capo,
      useSourceCapo,
      transpose,
      metronome: metronomeEnabled,
      countIn: countInEnabled,
      loop: playbackRange,
    });
  }

  function findBeatPosition(tick) {
    if (!api || !api.tickCache || !api.score || !Number.isFinite(tick)) return null;
    try {
      const trackIndexes = new Set(api.score.tracks.map((track, index) => index));
      const lookup = api.tickCache.findBeat(trackIndexes, tick);
      const beat = lookup && lookup.beat;
      if (!beat) return null;
      const range = api.tickCache.getRelativeBeatPlaybackRange(beat);
      const fallbackStartTick = Number(api.tickCache.getBeatStart(beat));
      const lookupStartTick = Number(lookup.start);
      const lookupEndTick = Number(lookup.end);
      const startTick = Number.isFinite(lookupStartTick) ? lookupStartTick : fallbackStartTick;
      const rangeDuration = range ? Number(range.endTick) - Number(range.startTick) : Number(beat.playbackDuration);
      let duration = Number.isFinite(lookupEndTick) && lookupEndTick > startTick
        ? lookupEndTick - startTick
        : rangeDuration;
      if (!Number.isFinite(duration) || duration <= 0) duration = Number(beat.playbackDuration);
      if (!Number.isFinite(startTick) || !Number.isFinite(duration) || duration <= 0) return null;
      const endTick = Math.min(Number(api.endTick) || startTick + duration, startTick + duration);
      const metricBeat = Number.isFinite(startTick)
        ? metricBeatNumber(beat, Math.max(0, tick - startTick))
        : null;
      return {
        startTick,
        endTick,
        bar: Number(beat.voice && beat.voice.bar && beat.voice.bar.index) + 1,
        beat: metricBeat,
        trackIndex: Number(beat.voice && beat.voice.bar && beat.voice.bar.staff && beat.voice.bar.staff.track && beat.voice.bar.staff.track.index),
        notes: (beat.notes || []).map((note) => ({ string: Number(note.string), fret: Number(note.fret), midi: Number(note.realValue) })),
        chord: beat.chord && typeof beat.chord.name === 'string' ? beat.chord.name : '',
      };
    } catch (_) {
      return null;
    }
  }

  function metricBeatNumber(beat, elapsedSinceBeatStart = 0) {
    const masterBar = beat && beat.voice && beat.voice.bar && beat.voice.bar.masterBar;
    const numerator = Number(masterBar && masterBar.timeSignatureNumerator);
    const denominator = Number(masterBar && masterBar.timeSignatureDenominator);
    const playbackStart = Number(beat && beat.playbackStart);
    const elapsed = Number(elapsedSinceBeatStart);
    if (!Number.isSafeInteger(numerator) || numerator <= 0
      || !Number.isSafeInteger(denominator) || denominator <= 0
      || !Number.isFinite(playbackStart) || !Number.isFinite(elapsed)) return null;

    const ticksPerBeat = 960 * 4 / denominator;
    if (!Number.isFinite(ticksPerBeat) || ticksPerBeat <= 0) return null;
    const barRelativeTick = playbackStart + Math.max(0, elapsed);
    if (!Number.isFinite(barRelativeTick)) return null;
    return Math.max(1, Math.min(numerator, Math.floor(barRelativeTick / ticksPerBeat) + 1));
  }

  let manuscriptScrollFrame = 0;
  let lastManuscriptPageSignature = '';

  function readManuscriptPages() {
    if (!scoreElement) return;
    const pageNodes = Array.from(scoreElement.querySelectorAll('.at-page, .at-surface'))
      .filter((node, index, all) => !all.some((other, otherIndex) => otherIndex !== index && other.contains(node)));
    manuscriptPageNodes = pageNodes.length ? pageNodes : Array.from(scoreElement.querySelectorAll('svg'));
    manuscriptPageCount = Math.max(1, manuscriptPageNodes.length);
    updateCurrentManuscriptPage();
  }

  function sendManuscriptPage(currentPage) {
    const signature = `${manuscriptPageCount}:${currentPage}`;
    if (signature === lastManuscriptPageSignature) return;
    lastManuscriptPageSignature = signature;
    send('manuscript', { pageCount: manuscriptPageCount, currentPage });
  }

  function updateCurrentManuscriptPage() {
    const rootRect = scoreScroll.getBoundingClientRect();
    const focusY = rootRect.top + Math.min(rootRect.height * 0.38, 260);
    let nearestIndex = 0;
    let nearestDistance = Infinity;
    manuscriptPageNodes.forEach((node, index) => {
      const rect = node.getBoundingClientRect();
      const distance = focusY < rect.top ? rect.top - focusY : focusY > rect.bottom ? focusY - rect.bottom : 0;
      if (distance < nearestDistance) { nearestDistance = distance; nearestIndex = index; }
    });
    sendManuscriptPage(Math.min(manuscriptPageCount, nearestIndex + 1));
  }

  function scheduleManuscriptPageUpdate() {
    if (manuscriptScrollFrame) return;
    manuscriptScrollFrame = requestAnimationFrame(() => {
      manuscriptScrollFrame = 0;
      updateCurrentManuscriptPage();
    });
  }

  function scrollToPage(pageNumber) {
    const page = Math.max(1, Math.min(manuscriptPageCount, Math.trunc(Number(pageNumber) || 1)));
    const node = manuscriptPageNodes[page - 1];
    if (!node) return;
    const rootRect = scoreScroll.getBoundingClientRect();
    const nodeRect = node.getBoundingClientRect();
    scoreScroll.scrollTo({ top: scoreScroll.scrollTop + nodeRect.top - rootRect.top - 14, behavior: 'smooth' });
    sendManuscriptPage(page);
  }

  function barStartTick(barIndex, preferredTick = 0) {
    if (!api || !api.score || !api.tickCache || !window.NativePracticeCore || !Number.isSafeInteger(barIndex)) return null;
    const beatToBar = window.NativePracticeCore.buildManuscriptBeatBarIndex(api.score.tracks);
    const matches = [];
    for (const track of api.score.tracks || []) for (const staff of track.staves || []) for (const bar of staff.bars || []) {
      if (Number(bar.index) !== barIndex) continue;
      for (const voice of bar.voices || []) for (const beat of voice.beats || []) {
        if (!Number.isSafeInteger(Number(beat.id)) || beatToBar.get(Number(beat.id)) !== barIndex) continue;
        const tick = Number(api.tickCache.getBeatStart(beat));
        if (Number.isFinite(tick)) matches.push(tick);
      }
    }
    if (!matches.length) return null;
    matches.sort((a, b) => a - b);
    const upcoming = matches.find((tick) => tick >= Number(preferredTick || 0));
    return upcoming === undefined ? matches[0] : upcoming;
  }

  function seekBar(barIndex) {
    const index = Number(barIndex);
    const tick = barStartTick(index, api && api.tickPosition);
    if (tick === null) {
      send('barSeek', { ok: false, barIndex: index, message: '无法从当前谱面找到该小节的真实拍点。' });
      return false;
    }
    if (!seek(tick)) {
      send('barSeek', { ok: false, barIndex: index, message: '播放器没有接受定位请求。' });
      return false;
    }
    send('barSeek', { ok: true, barIndex: index, tick });
    return true;
  }

  function installManuscriptInteraction(loadID) {
    if (manuscriptObserver) manuscriptObserver.disconnect();
    if (manuscriptClickHandler) scoreElement.removeEventListener('click', manuscriptClickHandler, true);
    if (manuscriptScrollHandler) scoreScroll.removeEventListener('scroll', manuscriptScrollHandler);
    if (manuscriptRefreshTimer) clearTimeout(manuscriptRefreshTimer);
    readManuscriptPages();
    manuscriptObserver = new MutationObserver(() => {
      if (manuscriptRefreshTimer) clearTimeout(manuscriptRefreshTimer);
      manuscriptRefreshTimer = setTimeout(() => { manuscriptRefreshTimer = null; readManuscriptPages(); }, 60);
    });
    manuscriptObserver.observe(scoreElement, { childList: true, subtree: true });
    manuscriptClickHandler = (event) => {
      if (loadID !== activeLoadID || !window.NativePracticeCore) return;
      const beatGroup = event.target && event.target.closest ? event.target.closest('g[class]') : null;
      if (!beatGroup) return;
      const index = window.NativePracticeCore.resolveManuscriptBarIndexForBeatGroup(beatGroup.getAttribute('class'), window.NativePracticeCore.buildManuscriptBeatBarIndex(api && api.score && api.score.tracks));
      if (index !== null) seekBar(index);
    };
    scoreElement.addEventListener('click', manuscriptClickHandler, true);
    manuscriptScrollHandler = () => scheduleManuscriptPageUpdate();
    scoreScroll.addEventListener('scroll', manuscriptScrollHandler, { passive: true });
  }

  function send(type, values = {}) {
    if (!bridge) return;
    if (type !== 'ready' && !activeLoadID) return;
    try { bridge.postMessage({ type, ...(type === 'ready' ? {} : { loadID: activeLoadID }), ...values }); }
    catch (_) { /* WebKit may be tearing down the view. */ }
  }

  function sendFor(loadID, type, values = {}) {
    if (loadID !== activeLoadID) return;
    send(type, values);
  }

  function fail(message) {
    const safeMessage = String(message || '谱面读取失败。');
    webError.textContent = safeMessage;
    webError.hidden = false;
    send('error', { message: safeMessage, fatal: true });
  }

  function clearPage() {
    webError.hidden = true;
    webError.textContent = '';
    scoreSection.hidden = false;
    scorePageHead.hidden = true;
    scorePageFoot.hidden = true;
    xheSection.hidden = true;
    xheSection.classList.remove('xhe-static');
    xheContent.classList.remove('xhe-loaded');
    xheContent.replaceChildren();
  }

  async function fetchSourceBytes(loadID, controller) {
    const response = await fetch(`${BASE}/source/current`, { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error(`本地谱面读取失败（${response.status}）。`);

    const declaredTotal = Number(response.headers.get('Content-Length'));
    const total = Number.isFinite(declaredTotal) && declaredTotal > 0 ? declaredTotal : 0;
    if (!response.body) return new Uint8Array(await response.arrayBuffer());

    const reader = response.body.getReader();
    const chunks = [];
    let loaded = 0;
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      if (!part.value) continue;
      chunks.push(part.value);
      loaded += part.value.byteLength;
      if (total > 0) sendFor(loadID, 'fileProgress', { loaded, total });
    }
    const bytes = new Uint8Array(loaded);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return bytes;
  }

  function renderXhe(raw, title) {
    const decoder = window.MimiIbe;
    if (!decoder) throw new Error('文本谱解析器未加载。');
    const parsed = decoder.parseXhe(raw);
    if (parsed.kind === 'empty') throw new Error('文本谱内容为空。');

    scoreSection.hidden = true;
    scorePageHead.hidden = true;
    scorePageFoot.hidden = true;
    xheSection.hidden = false;
    xheTitle.textContent = title || '文本和弦谱';
    xheContent.replaceChildren();
    if (parsed.kind === 'text') {
      const pre = document.createElement('pre');
      pre.className = 'xhe-plain';
      pre.textContent = parsed.text;
      xheContent.append(pre);
      addXheSweep();
      return;
    }

    const blocks = decoder.buildXheBlocks(parsed.items);
    if (blocks.length === 0) throw new Error('文本谱没有可显示的内容。');
    const body = document.createElement('div');
    body.className = 'xhe-body';
    const normalizedChord = (segment) => decoder.normalizeChord(segment && segment.kind === 'chord' ? segment.chord : '');
    const segmentChar = (segment) => segment.char && segment.char.length > 0 ? segment.char : '\u00a0\u00a0';
    const isCjk = (character) => {
      const code = character.codePointAt(0) || 0;
      return (code >= 0x2e80 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff) || (code >= 0xff00 && code <= 0xffef);
    };
    const textWidth = (text) => Array.from(text || '').reduce((width, character) => width + (isCjk(character) ? 16 : 9.6), 0);
    const appendDiagramOrFallback = (container, segment, fallbackClass) => {
      const name = normalizedChord(segment);
      const fingering = decoder.lookupChord(name);
      if (fingering) {
        const wrapper = document.createElement('span');
        wrapper.innerHTML = decoder.chordSvg(name, fingering);
        container.append(wrapper.firstElementChild);
      } else if (name) {
        const fallback = document.createElement('span');
        fallback.className = fallbackClass;
        fallback.textContent = name;
        container.append(fallback);
      }
    };

    for (const block of blocks) {
      if (block.kind === 'headline') {
        const element = document.createElement('h3');
        element.className = 'xhe-headline';
        element.textContent = block.text;
        body.append(element);
      } else if (block.kind === 'rhythm') {
        const element = document.createElement('div');
        element.className = 'xhe-rhythm';
        const label = document.createElement('span');
        label.className = 'xhe-rhythm-label';
        label.textContent = '节奏';
        const rhythm = document.createElement('span');
        rhythm.className = 'xhe-rhythm-body';
        rhythm.textContent = block.rhythm;
        element.append(label, rhythm);
        body.append(element);
      } else if (block.kind === 'tab') {
        const element = document.createElement('pre');
        element.className = 'xhe-tab';
        element.textContent = block.tab;
        body.append(element);
      } else {
        if (block.chordOnly) {
          const row = document.createElement('div');
          row.className = 'xhe-chord-row';
          for (const segment of block.segments) {
            const cell = document.createElement('div');
            cell.className = 'xhe-chord-cell';
            appendDiagramOrFallback(cell, segment, 'xhe-chord-fallback');
            row.append(cell);
          }
          body.append(row);
          continue;
        }
        let offset = 0;
        const anchors = [];
        const line = document.createElement('div');
        line.className = 'xhe-line';
        const lyric = document.createElement('div');
        lyric.className = 'xhe-lyric';
        for (const segment of block.segments) {
          if (segment.kind === 'text') {
            const span = document.createElement('span');
            span.className = 'xhe-text-seg';
            span.textContent = segment.text;
            lyric.append(span);
            offset += textWidth(segment.text);
          } else {
            const anchor = document.createElement('span');
            anchor.className = 'xhe-anchor';
            const character = document.createElement('span');
            character.className = 'xhe-anchor-char';
            character.textContent = segmentChar(segment);
            anchor.append(character);
            lyric.append(anchor);
            anchors.push({ segment, left: offset - 6 });
            offset += textWidth(segmentChar(segment));
          }
        }
        line.append(lyric);
        let previousRight = -Infinity;
        for (const anchor of anchors) {
          if (anchor.left < previousRight + 4) anchor.left = previousRight + 4;
          previousRight = anchor.left + 48;
          const chordPosition = document.createElement('span');
          chordPosition.className = 'xhe-chord-pos';
          chordPosition.style.left = `${anchor.left}px`;
          appendDiagramOrFallback(chordPosition, anchor.segment, 'xhe-chord-pos-name');
          line.append(chordPosition);
        }
        body.append(line);
      }
    }
    xheContent.append(body);
    xheContent.classList.add('xhe-loaded');
    addXheSweep();
  }

  function addXheSweep() {
    const sweep = document.createElement('div');
    sweep.className = 'score-sweep-line';
    xheContent.prepend(sweep);
  }

  function setPlaybackSpeed(targetBpm) {
    if (!api || !Number.isFinite(sourceTempo) || sourceTempo <= 0) return;
    const requested = Number(targetBpm);
    if (!Number.isFinite(requested)) return;
    requestedTempo = Math.max(20, Math.min(300, requested));
    const requestedRatio = requestedTempo / sourceTempo;
    const ratio = Math.max(0.125, Math.min(8, requestedRatio));
    const previousSample = sampleCurrentPosition(api, false, false);
    const previousRatio = positionSpeedRatio(previousSample) || Number(api.playbackSpeed) || 1;
    const alreadyAwaitingSpeed = Number(pendingPlaybackSpeedRatio) > 0;
    cancelPlaybackSpeedAckWatchdog(true);
    tempoSyncFailedRatio = null;
    tempoSyncFailedTargetRatio = null;
    // Writing the same ratio is a no-op for the engine but still performs a mainSeek,
    // which force-places the playhead. Only write when the ratio really changes.
    const currentApiRatio = Number(api.playbackSpeed);
    if (!speedRatiosMatch(currentApiRatio, ratio)) api.playbackSpeed = ratio;
    const actual = Number(api.playbackSpeed);
    const actualTempo = sourceTempo * actual;
    if (Number.isFinite(actualTempo) && actual > 0) {
      requestedTempo = actualTempo;
      if (scorePageTempoValue) scorePageTempoValue.textContent = String(Math.round(actualTempo));
      pendingPlaybackSpeedRatio = alreadyAwaitingSpeed || !speedRatiosMatch(previousRatio, actual) ? actual : null;
      lastWorkerPositionSample = previousSample;
      lastPositionSample = retimePositionSample(previousSample, actual, sourceTempo);
      const anchor = positionFields(lastPositionSample, isPlaying);
      send('tempo', { source: sourceTempo, actual: actualTempo, ...anchor, anchorReason: 'speedChange' });
      send('playbackState', { state: isPlaying ? 1 : 0, ...anchor, anchorReason: 'speedChange' });
      if (Number(pendingPlaybackSpeedRatio) > 0 && isPlaying) armPlaybackSpeedAckWatchdog();
    }
  }

  function createOffsetAwareContinuousScrollHandler(targetApi) {
    let lastBarTop = Number.NaN;
    const scrollToBeatContinuously = (beatBounds, force = false) => {
      if (targetApi.customScrollHandler && targetApi.customScrollHandler.suppressScroll) return;
      const bar = beatBounds && beatBounds.barBounds && beatBounds.barBounds.masterBarBounds;
      const ui = targetApi.uiFacade;
      if (!bar || !bar.visualBounds || !bar.realBounds || !ui) return;
      const scroll = ui.getScrollContainer();
      if (!scroll) return;
      const containerOffset = ui.getOffset(scroll, targetApi.container);

      if (!force && bar.realBounds.y === lastBarTop) return;
      lastBarTop = bar.realBounds.y;

      const systemTop = containerOffset.y + bar.realBounds.y;
      const targetY = bar.realBounds.y <= 0 ? 0 : Math.max(0, systemTop + (targetApi.settings.player.scrollOffsetY || -40));
      ui.scrollToY(scroll, targetY, targetApi.settings.player.scrollSpeed || 150);
    };

    return {
      suppressScroll: false,
      invalidate() {
        lastBarTop = Number.NaN;
      },
      forceScrollTo(beatBounds) {
        scrollToBeatContinuously(beatBounds, true);
      },
      onBeatCursorUpdating(startBeat) {
        scrollToBeatContinuously(startBeat, false);
      },
    };
  }

  function createOffsetAwareOffscreenScrollHandler(targetApi) {
    let lastBarTop = Number.NaN;
    const scrollToBeatIfOffscreen = (beatBounds, force = false) => {
      if (targetApi.customScrollHandler && targetApi.customScrollHandler.suppressScroll) return;
      const bar = beatBounds && beatBounds.barBounds && beatBounds.barBounds.masterBarBounds;
      const ui = targetApi.uiFacade;
      if (!bar || !bar.visualBounds || !bar.realBounds || !ui) return;
      const scroll = ui.getScrollContainer();
      if (!scroll) return;
      const containerOffset = ui.getOffset(scroll, targetApi.container);
      const viewport = ui.getOffset(null, scroll);

      if (!force && bar.realBounds.y === lastBarTop) return;
      lastBarTop = bar.realBounds.y;

      // AlphaTab's built-in vertical OffScreen handler compares score-local
      // bounds directly with scrollTop. This page has a header/padding before
      // #score, so map system bounds into #score-scroll content coordinates.
      const systemTop = containerOffset.y + bar.visualBounds.y;
      const systemBottom = systemTop + bar.visualBounds.h;
      const viewportTop = scroll.scrollTop;
      const viewportBottom = viewportTop + viewport.h;
      if (systemBottom >= viewportBottom || systemTop < viewportTop) {
        const targetY = containerOffset.y + bar.realBounds.y + targetApi.settings.player.scrollOffsetY;
        ui.scrollToY(scroll, targetY, targetApi.settings.player.scrollSpeed);
      }
    };

    return {
      suppressScroll: false,
      invalidate() {
        lastBarTop = Number.NaN;
      },
      forceScrollTo(beatBounds) {
        scrollToBeatIfOffscreen(beatBounds, true);
      },
      onBeatCursorUpdating(startBeat) {
        scrollToBeatIfOffscreen(startBeat);
      },
    };
  }

  function createApi(metadata, loadID, loadGeneration) {
    const alphaTab = window.alphaTab;
    if (!alphaTab || !alphaTab.AlphaTabApi) throw new Error('本地 AlphaTab 引擎无法启动。');
    const rendering = scoreRenderingRuntime();
    if (api) {
      endPauseCursorGuard(null, false);
      try { api.destroy(); } catch (_) { /* A failed previous load may already be disposed. */ }
      api = null;
    }

    const settings = rendering.createScoreSettings();
    settings.core.useWorkers = false;
    settings.core.enableLazyLoading = false;
    settings.core.scriptFile = `${BASE}/alphaTab.js`;
    settings.core.fontDirectory = `${BASE}/font/`;
    settings.player.soundFont = `${BASE}/soundfont/main`;
    settings.player.bufferTimeInMilliseconds = 1500;
    settings.player.scrollElement = '#score-scroll';
    settings.player.scrollMode = alphaTab.ScrollMode.Continuous;
    settings.player.scrollOffsetY = -40;
    // Row-wrap hand-off: AlphaTab places the beat cursor on the next system before the
    // follow-scroll animation has brought that system into view. A shorter follow (the
    // original web setting was 250 ms) keeps the line from sitting off-screen for a
    // visible moment at every line change while still scrolling smoothly.
    settings.player.scrollSpeed = Math.min(Number(settings.player.scrollSpeed) || 250, 150);
    settings.display.scale = BASE_SCORE_SCALE * zoom;

    api = new alphaTab.AlphaTabApi(scoreElement, settings);
    gmSoundfontLoaded = false;
    loadedUkePrograms = new Set();
    soundfontPlanInitStarted = false;
    soundfontReadySent = false;
    soundfontConflictMessage = null;
    installResizeRenderCoalescer(api);
    let customScrollHandler = null;
    if (settings.player.scrollMode === alphaTab.ScrollMode.Continuous) {
      customScrollHandler = createOffsetAwareContinuousScrollHandler(api);
      api.customScrollHandler = customScrollHandler;
    } else if (settings.player.scrollMode === alphaTab.ScrollMode.OffScreen) {
      customScrollHandler = createOffsetAwareOffscreenScrollHandler(api);
      api.customScrollHandler = customScrollHandler;
    }
    const isCurrentLoad = () => loadGeneration === generation && loadID === activeLoadID;
    api.renderStarted.on(() => {
      if (!isCurrentLoad()) return;
      if (customScrollHandler) customScrollHandler.invalidate();
      sendFor(loadID, 'stage', { value: '排版乐谱' });
    });
    api.renderFinished.on(() => {
      if (!isCurrentLoad()) return;
      installManuscriptInteraction(loadID);
      sendFor(loadID, 'scoreReady', { mode: 'score' });
    });
    api.error.on((error) => { if (!isCurrentLoad()) return; sendFor(loadID, 'error', {
      message: error && error.message ? error.message : String(error || 'AlphaTab 载入失败。'),
      // 谱面已经载入后的错误（音源重载、播放操作等）是可恢复状态，不能把播放器打成永久失败。
      fatal: !(api && api.score),
    }); });
    api.scoreLoaded.on((score) => {
      if (!isCurrentLoad()) return;
      const rendering = scoreRenderingRuntime();
      const reloadState = pendingScoreReloadState;
      if (reloadState) {
        displayMode = reloadState.displayMode;
        numberTab = reloadState.numberTab;
        chordMode = reloadState.chordMode;
      }
      if (metadata.title) score.title = metadata.title;
      if (metadata.artist) score.artist = metadata.artist;
      for (const track of score.tracks) for (const staff of track.staves || []) staff.showStandardNotation = false;
      rendering.applyScoreDisplayMode(score, displayMode);
      if (!numberTab) for (const track of score.tracks) for (const staff of track.staves || []) staff.showNumbered = false;
      if (score.stylesheet) score.stylesheet.globalDisplayChordDiagramsInScore = chordMode === 'diagram';
      const scoreTempo = Number(score.tempo);
      sourceTempo = Number.isFinite(scoreTempo) && scoreTempo > 0
        ? scoreTempo
        : (Number(metadata.bpm) > 0 ? Number(metadata.bpm) : 80);
      sourceCapos = score.tracks.map((track) => (track.staves || []).map((staff) => Number(staff.capo) || 0));
      if (reloadState) {
        capo = reloadState.capo;
        useSourceCapo = reloadState.useSourceCapo;
        transpose = reloadState.transpose;
        pointA = reloadState.pointA;
        playbackRange = reloadState.playbackRange;
        const reloadVisibleTracks = Array.isArray(reloadState.visibleTrackIndexes) ? reloadState.visibleTrackIndexes : [];
        visibleTrackIndexes = score.tracks
          .map((_track, index) => index)
          .filter((index) => reloadVisibleTracks.includes(index));
        trackMix = createTrackMixState(score, reloadState.trackMix, visibleTrackIndexes);
        for (let trackIndex = 0; trackIndex < score.tracks.length; trackIndex += 1) {
          const track = score.tracks[trackIndex];
          for (let staffIndex = 0; staffIndex < (track.staves || []).length; staffIndex += 1) {
            const staff = track.staves[staffIndex];
            staff.capo = useSourceCapo
              ? (Number(sourceCapos[trackIndex] && sourceCapos[trackIndex][staffIndex]) || 0)
              : capo;
            staff.transpositionPitch = -transpose;
          }
        }
        api.isLooping = !!playbackRange;
        api.playbackRange = playbackRange;
        loopLapProgress = null;
        lastTick = reloadState.targetTick;
      } else {
        visibleTrackIndexes = score.tracks.map((_track, index) => index);
        trackMix = createTrackMixState(score);
        pointA = null;
        playbackRange = null;
        loopGeneration += 1;
        loopLapProgress = null;
        capo = 0;
        useSourceCapo = true;
        transpose = 0;
        lastTick = null;
        setPlaybackSpeed(Number(metadata.bpm) > 0 ? Number(metadata.bpm) : sourceTempo);
      }
      const primaryStaff = score.tracks.find((track) => (track.staves || []).some((staff) => staff.stringTuning && staff.stringTuning.tunings && staff.stringTuning.tunings.length))?.staves?.[0]
        || score.tracks[0]?.staves?.[0];
      const primaryBar = primaryStaff && primaryStaff.bars && primaryStaff.bars[0];
      const signature = Number(primaryBar && primaryBar.keySignature);
      const signatureType = Number(primaryBar && primaryBar.keySignatureType);
      const keyLabel = rendering.keySignatureName(signature, signatureType) || String(metadata.key || '');
      setScorePageHeader(score, { ...metadata, key: keyLabel });
      const tuningLabel = primaryStaff && primaryStaff.stringTuning && primaryStaff.stringTuning.tunings
        ? primaryStaff.stringTuning.tunings.map((pitch) => String(pitch)).join(' · ')
        : '';
      const masterBar = score.masterBars && score.masterBars[0]
        || primaryBar && primaryBar.masterBar;
      const numerator = Number(masterBar && masterBar.timeSignatureNumerator);
      const denominator = Number(masterBar && masterBar.timeSignatureDenominator);
      const timeSignature = numerator > 0 && denominator > 0 ? `${numerator}/${denominator}` : '';
      sendFor(loadID, 'scoreMetadata', {
        title: score.title || metadata.title || '',
        artist: score.artist || metadata.artist || '',
        album: score.album || '',
        key: keyLabel,
        timeSignature,
        tuning: tuningLabel,
        sourceTempo,
        barCount: Math.max(1, ...score.tracks.flatMap((track) => (track.staves || []).map((staff) => (staff.bars || []).length))),
      });
      sendPlayerState();
    });
    api.playerReady.on(() => { if (isCurrentLoad()) sendFor(loadID, 'playerReady'); });
    api.soundFontLoad.on((event) => {
      if (!isCurrentLoad()) return;
      if (event && Number(event.total) > 0) {
        sendFor(loadID, 'soundProgress', { loaded: Number(event.loaded), total: Number(event.total) });
      }
    });
    api.soundFontLoaded.on(() => {
      if (!isCurrentLoad()) return;
      gmSoundfontLoaded = true;
      if (soundfontPlanInitStarted) return;
      soundfontPlanInitStarted = true;
      const targetApi = api;
      void (async () => {
        try {
          const planOK = await ensureSoundfontPlan(targetApi);
          if (!isCurrentLoad() || targetApi !== api) return;
          if (!planOK) { sendPlayerState(); return; }
          sendSoundReady(loadID);
          sendPlayerState();
        } catch (error) {
          if (!isCurrentLoad() || targetApi !== api) return;
          sendFor(loadID, 'error', {
            message: `本地音源加载失败：${error && error.message ? error.message : String(error)}`,
            fatal: false,
          });
        }
      })();
    });
    api.playerStateChanged.on((event) => {
      if (isCurrentLoad()) {
        const state = Number(event && event.state);
        const wasPlaying = isPlaying;
        isPlaying = state === 1;
        if (state === 1) {
          if (Number(pendingPlaybackSpeedRatio) > 0) armPlaybackSpeedAckWatchdog();
          endPauseCursorGuard(lastPositionSample ? lastPositionSample.currentTick : Number(api.tickPosition));
        } else {
          cancelPlaybackSpeedAckWatchdog(false);
        }
        if (wasPlaying && !isPlaying) {
          interruptionRevision += 1;
          if (pendingPauseSample && !(event && event.stopped)) {
            const pauseTick = Number(pendingPauseSample.currentTick);
            const snappedTick = Number(api.tickPosition);
            if (Number.isFinite(pauseTick) && Number.isFinite(snappedTick) && Math.abs(pauseTick - snappedTick) > 0.01) {
              // AlphaTab 1.8.4 rewinds the engine to the beat start as part of pause.
              // Restore the sampled tick so pause, resume and cursor stay on one position;
              // beginPauseCursorGuard() freezes cursor placement until this seek is confirmed.
              requestSeek(pauseTick, false);
            } else {
              endPauseCursorGuard(pauseTick);
            }
          } else if (!pendingSeek && !hasUnconfirmedApiSeek(api)) {
            lastPositionSample = sampleCurrentPosition(api, false);
            endPauseCursorGuard(lastPositionSample.currentTick);
          } else {
            endPauseCursorGuard(lastPositionSample ? lastPositionSample.currentTick : Number(api.tickPosition));
          }
          pendingPauseSample = null;
        }
        if (!pendingSeek && !hasUnconfirmedApiSeek(api) && (state === 1 || state === 2)) {
          lastPositionSample = sampleCurrentPosition(api, false);
        }
        const preserveAudioFocus = state !== 1 && preserveAudioFocusForRender;
        if (pendingSeek) {
          pendingSeek.preserveAudioFocus = pendingSeek.preserveAudioFocus || preserveAudioFocus;
          if (pendingSeek.timedOut && state !== 1) {
            finishPendingSeek(pendingSeek, false);
            return;
          }
          if (state !== 1 && preserveAudioFocus) preserveAudioFocusForRender = false;
          if (state === 1) preserveAudioFocusForRender = false;
          return;
        }
        const anchor = currentPositionAnchor(isPlaying);
        if (hasUnconfirmedApiSeek(api)) {
          sendFor(loadID, 'playbackState', { state, isPlaying, preserveAudioFocus });
          if (state !== 1 && preserveAudioFocus) preserveAudioFocusForRender = false;
          if (state === 1) preserveAudioFocusForRender = false;
          return;
        }
        sendFor(loadID, 'playbackState', { state, ...anchor, preserveAudioFocus });
        if (state !== 1 && preserveAudioFocus) preserveAudioFocusForRender = false;
        if (state === 1) preserveAudioFocusForRender = false;
      }
    });
    api.playerPositionChanged.on((event) => {
      if (!isCurrentLoad()) return;
      const originalTempo = Number(event.originalTempo) > 0 ? Number(event.originalTempo) : (Number(sourceTempo) || 80);
      const modifiedTempo = Number(event.modifiedTempo) > 0 ? Number(event.modifiedTempo) : originalTempo * (Number(api.playbackSpeed) || 1);
      const eventSpeedRatio = modifiedTempo / originalTempo;
      const sample = {
        currentTime: Number(event.currentTime),
        endTime: Number(event.endTime),
        currentTick: Number(event.currentTick),
        endTick: Number(event.endTick),
        isSeek: !!event.isSeek,
        originalTempo,
        modifiedTempo,
        speedRatio: eventSpeedRatio,
        sampledAtMonotonicMs: performance.now(),
      };
      lastWorkerPositionSample = sample;
      const seekRequest = pendingSeek && pendingSeek.api === api && pendingSeek.loadID === loadID
        && pendingSeek.generation === generation ? pendingSeek : null;
      const matchingSeekAck = seekRequest && isPendingSeekAck(sample, seekRequest);
      const pendingRatio = Number(pendingPlaybackSpeedRatio);
      if (pendingRatio > 0) {
        if (!speedRatiosMatch(eventSpeedRatio, pendingRatio)) {
          if (matchingSeekAck) seekRequest.ackSample = sample;
          return;
        }
        finishPlaybackSpeedSync(sample);
      } else if (Number(tempoSyncFailedTargetRatio) > 0
        && speedRatiosMatch(eventSpeedRatio, Number(tempoSyncFailedTargetRatio))) {
        tempoSyncFailedRatio = null;
        tempoSyncFailedTargetRatio = null;
        lastPositionSample = sample;
        const recoveredAnchor = tempoControlAnchor(sample, eventSpeedRatio, isPlaying);
        const recoveredTempo = (Number(sourceTempo) || 80) * eventSpeedRatio;
        requestedTempo = recoveredTempo;
        if (scorePageTempoValue) scorePageTempoValue.textContent = String(Math.round(recoveredTempo));
        sendFor(loadID, 'tempo', {
          source: Number(sourceTempo) || 80,
          actual: recoveredTempo,
          ...recoveredAnchor,
          anchorReason: 'speedSyncRecovered',
        });
      }
      if (seekRequest && pendingSeek === seekRequest) {
        if (matchingSeekAck) {
          if (Number(seekRequest.targetTick) !== Number(seekRequest.inFlightTick)) {
            resetLoopProgressForSeek(sample);
            seekRequest.inFlightTick = null;
            seekRequest.ackSample = null;
            issuePendingSeek(seekRequest);
            return;
          }
          finishPendingSeek(seekRequest, true, sample);
        } else {
          if (sample.isSeek) resetLoopProgressForSeek(sample);
          if (seekRequest.ackSample && !(Number(pendingPlaybackSpeedRatio) > 0)) {
            seekRequest.ackSample = null;
            seekRequest.inFlightTick = null;
            issuePendingSeek(seekRequest);
          }
          return;
        }
      }
      lastPositionSample = sample;
      const now = Date.now();
      if (now - lastPositionMessage < 120 && event.currentTime < event.endTime && !event.isSeek) return;
      lastPositionMessage = now;
      const tick = Number(event.currentTick);
      const previousTick = lastTick;
      lastTick = Number.isFinite(tick) ? tick : lastTick;
      const core = window.NativePracticeCore;
      if (core && playbackRange && Number.isFinite(tick)) {
        if (!loopLapProgress || loopLapProgress.generation !== loopGeneration) {
          loopLapProgress = core.createLoopLapProgress(loopGeneration, interruptionRevision, playbackRange);
        }
        loopLapProgress = core.observeLoopLapProgress(loopLapProgress, {
          tick,
          isSeek: !!event.isSeek,
          generation: loopGeneration,
          interruptionRevision,
          range: playbackRange,
          playing: isPlaying,
          focused: isAudibleOwner,
          visible: nativeViewVisible && document.visibilityState !== 'hidden',
        });
        const completed = core.isCompletedLoopLap(previousTick, tick, playbackRange, !!event.isSeek);
        if (completed && core.canCountLoopCompletion({
          playing: isPlaying,
          focused: isAudibleOwner,
          visible: nativeViewVisible && document.visibilityState !== 'hidden',
          observedFromA: loopLapProgress.observedFromA,
          event: { startTick: playbackRange.startTick, endTick: playbackRange.endTick },
          range: playbackRange,
        })) {
          loopLapSequence += 1;
          sendFor(loadID, 'loopLap', {
            lapId: `${loopGeneration}:${loopLapSequence}`,
            range: playbackRange,
            tick,
          });
          if (activeSpeedPlan) {
            const lapId = `${loopGeneration}:${loopLapSequence}`;
            const advanced = core.advanceSpeedPlan(activeSpeedPlan, lapId, seenSpeedLapIDs);
            if (advanced.changed) {
              activeSpeedPlan = advanced.plan;
              setPlaybackSpeed(activeSpeedPlan.currentBpm);
              sendFor(loadID, 'speedPlan', { plan: activeSpeedPlan, lapId });
            }
          }
        }
      }
      sendFor(loadID, 'position', positionFields(sample, isPlaying));
    });
    api.playedBeatChanged.on((beat) => {
      if (!isCurrentLoad() || !beat) return;
      sendFor(loadID, 'playedBeat', {
        bar: Number(beat.voice && beat.voice.bar && beat.voice.bar.index) + 1,
        beat: metricBeatNumber(beat),
        notes: (beat.notes || []).map((note) => ({ string: Number(note.string), fret: Number(note.fret), midi: Number(note.realValue), finger: Number(note.leftHandFinger) || 0 })),
        chord: beat.chord && typeof beat.chord.name === 'string' ? beat.chord.name : '',
      });
    });
    api.playerFinished.on(() => {
      if (!isCurrentLoad()) return;
      if (api.isLooping) return;
      cancelPlaybackSpeedAckWatchdog(false);
      isPlaying = false;
      interruptionRevision += 1;
      lastPositionSample = sampleCurrentPosition(api, false);
      sendFor(loadID, 'playbackFinished', currentPositionAnchor(false));
    });
    api.renderFinished.on(() => { if (isCurrentLoad()) sendPlayerState(); });
    return api;
  }

  function cancelPendingInitialRenderBarrier() {
    const barrier = pendingInitialRenderBarrier;
    if (!barrier || barrier.settled) return;
    barrier.settled = true;
    pendingInitialRenderBarrier = null;
    if (barrier.frameID !== null) cancelAnimationFrame(barrier.frameID);
    barrier.frameID = null;
    if (barrier.timeoutID !== null) clearTimeout(barrier.timeoutID);
    barrier.timeoutID = null;
    barrier.resolve(false);
  }

  function waitForInitialRenderFrame(targetApi, loadID, loadGeneration) {
    cancelPendingInitialRenderBarrier();
    return new Promise((resolve) => {
      const barrier = { frameID: null, timeoutID: null, settled: false, resolve };
      pendingInitialRenderBarrier = barrier;
      const settle = () => {
        if (barrier.settled) return;
        barrier.settled = true;
        if (barrier.frameID !== null) {
          cancelAnimationFrame(barrier.frameID);
          barrier.frameID = null;
        }
        if (barrier.timeoutID !== null) {
          clearTimeout(barrier.timeoutID);
          barrier.timeoutID = null;
        }
        if (pendingInitialRenderBarrier === barrier) pendingInitialRenderBarrier = null;
        resolve(targetApi === api && loadID === activeLoadID && loadGeneration === generation);
      };
      // AlphaTab queued initialRender in its constructor first. This one-shot RAF runs after
      // initialRender has attached the preRender cleanup; if RAF is suspended (background tab,
      // occluded audition host, CLI probe), the 50ms timer guarantees deadlock prevention.
      barrier.frameID = requestAnimationFrame(() => settle());
      barrier.timeoutID = setTimeout(() => settle(), 50);
    });
  }

  async function load(parameters) {
    if (!parameters || typeof parameters.kind !== 'string' || typeof parameters.loadID !== 'string') {
      fail('谱面来源无效。');
      return;
    }
    const loadID = parameters.loadID;
    cancelPendingInitialRenderBarrier();
    cancelPendingSeek();
    cancelSeekCoalescer();
    endPauseCursorGuard(null, false);
    activeLoadID = loadID;
    const loadGeneration = ++generation;
    if (sourceAbortController) sourceAbortController.abort();
    const controller = new AbortController();
    sourceAbortController = controller;
    currentMode = parameters.kind;
    scoreCategory = normalizeScoreCategory(parameters.category);
    scoreSourceMetadata = { ...parameters };
    rawScoreJson = null;
    pendingScoreReloadState = null;
    lastPositionSample = null;
    lastWorkerPositionSample = null;
    pendingPauseSample = null;
    clearPlaybackSpeedSyncState();
    lastPositionMessage = 0;
    lastTick = null;
    isPlaying = false;
    preserveAudioFocusForRender = false;
    clearPage();
    sendFor(loadID, 'stage', { value: '读取本地谱面' });

    try {
      if (currentMode !== 'xhe') {
        sendFor(loadID, 'stage', { value: '准备本地播放器' });
        await prepareAlphaTabWorker();
        if (loadGeneration !== generation || loadID !== activeLoadID) return;
      }
      const bytes = await fetchSourceBytes(loadID, controller);
      if (loadGeneration !== generation || loadID !== activeLoadID) return;
      if (currentMode === 'xhe') {
        const raw = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
        renderXhe(raw, parameters.title || '');
        sendFor(loadID, 'xheReady', { audio: false });
        return;
      }

      sendFor(loadID, 'stage', { value: '加载本地谱面字体' });
      const fontsReady = await ensureScoreFontsReady(loadID, loadGeneration);
      if (!fontsReady || loadGeneration !== generation || loadID !== activeLoadID) return;

      const currentApi = createApi(parameters, loadID, loadGeneration);
      if (!(await waitForInitialRenderFrame(currentApi, loadID, loadGeneration))
        || currentApi !== api || loadGeneration !== generation || loadID !== activeLoadID) return;
      let scoreInput;
      if (currentMode === 'ibe') {
        sendFor(loadID, 'stage', { value: '解码 IBE 谱面' });
        if (!window.MimiIbe) throw new Error('IBE 解码器未加载。');
        const json = await window.MimiIbe.decodeIbe(bytes);
        if (loadGeneration !== generation || loadID !== activeLoadID) return;
        rawScoreJson = json;
        scoreInput = scoreRenderingRuntime().createScoreFromJson(json, currentApi.settings, displayMode);
      } else if (currentMode === 'json') {
        sendFor(loadID, 'stage', { value: '读取 AlphaTab JSON' });
        const parsed = JSON.parse(new TextDecoder('utf-8', { fatal: false }).decode(bytes));
        if (!parsed || !Array.isArray(parsed.tracks) || !parsed.tracks.every((track) => Array.isArray(track.staves))) {
          throw new Error('JSON 文件不是 AlphaTab 谱面数据；MIMI 工程 JSON 请在工坊中打开。');
        }
        rawScoreJson = parsed;
        scoreInput = scoreRenderingRuntime().createScoreFromJson(parsed, currentApi.settings, displayMode);
      } else if (currentMode === 'gp' || currentMode === 'musicxml') {
        sendFor(loadID, 'stage', { value: '导入 Guitar Pro / MusicXML' });
        const rendering = scoreRenderingRuntime();
        const importedScore = rendering.alphaTab.importer.ScoreLoader.loadScoreFromBytes(bytes, currentApi.settings);
        rawScoreJson = JSON.parse(rendering.alphaTab.model.JsonConverter.scoreToJson(importedScore));
        scoreInput = rendering.createScoreFromJson(rawScoreJson, currentApi.settings, displayMode);
      } else {
        throw new Error('支持 IBE、Guitar Pro 3–8 与 MusicXML 谱面。');
      }

      const accepted = currentApi.load(scoreInput, [-1]);
      if (accepted === false) throw new Error('AlphaTab 不支持此文件内容或格式。');
    } catch (error) {
      if (loadGeneration !== generation || loadID !== activeLoadID) return;
      fail(error && error.message ? error.message : String(error));
    }
  }

  function playPause() {
    if (!api) return;
    if (!isPlaying && soundfontConflictMessage) {
      send('notice', { message: soundfontConflictMessage });
      return;
    }
    if (isPlaying) {
      capturePauseSample(api);
      cancelPlaybackSpeedAckWatchdog(false);
      beginPauseCursorGuard(api);
    }
    try { api.playPause(); }
    catch (error) {
      endPauseCursorGuard(lastPositionSample ? lastPositionSample.currentTick : Number(api && api.tickPosition));
      send('error', { message: error && error.message ? error.message : String(error), fatal: false });
    }
  }

  function pause() {
    if (!api) return;
    if (isPlaying) {
      capturePauseSample(api);
      cancelPlaybackSpeedAckWatchdog(false);
      beginPauseCursorGuard(api);
    }
    try { api.pause(); }
    catch (error) {
      endPauseCursorGuard(lastPositionSample ? lastPositionSample.currentTick : Number(api && api.tickPosition));
      send('error', { message: error && error.message ? error.message : String(error) });
    }
  }

  function stop() {
    if (!api) return;
    cancelPlaybackSpeedAckWatchdog(false);
    cancelPendingSeek();
    cancelSeekCoalescer();
    endPauseCursorGuard(null, false);
    pendingPauseSample = null;
    try { api.stop(); }
    catch (error) { send('error', { message: error && error.message ? error.message : String(error) }); }
    interruptionRevision += 1;
    isPlaying = false;
  }

  function play() {
    if (!api || isPlaying || !isAudibleOwner || !nativeViewVisible) return;
    if (soundfontConflictMessage) {
      send('notice', { message: soundfontConflictMessage });
      return;
    }
    try {
      const result = api.play();
      if (result === false) send('error', { message: '播放器没有接受播放请求。', fatal: false });
    } catch (error) {
      send('error', { message: error && error.message ? error.message : String(error), fatal: false });
    }
  }

  function finishPendingSeek(request, confirmed, sample = null, failureMessage = null) {
    if (!request || pendingSeek !== request) return false;
    if (request.timer !== null) clearTimeout(request.timer);
    if (request.pauseTimer !== null) clearTimeout(request.pauseTimer);
    request.timer = null;
    request.pauseTimer = null;
    pendingSeek = null;
    if (confirmed && sample) {
      pendingPauseSample = null;
      lastPositionSample = sample;
      const anchor = positionFields(sample, isPlaying);
      sendFor(request.loadID, 'playbackState', {
        state: isPlaying ? 1 : 0,
        ...anchor,
        preserveAudioFocus: !isPlaying && !!request.preserveAudioFocus,
        anchorReason: 'seek',
      });
    } else {
      if (isPlaying && request.api === api) {
        try { request.api.pause(); } catch (_) { /* Keep the last confirmed sample on a failed seek. */ }
      }
      isPlaying = false;
      pendingPauseSample = null;
      sendFor(request.loadID, 'seekSyncFailed', {
        targetTick: request.targetTick,
        message: failureMessage || '无法确认定位结果，播放已暂停；请重试。',
      });
      sendFor(request.loadID, 'playbackState', { state: 0, isPlaying: false });
    }
    if (pauseCursorGuard && pauseCursorGuard.api === request.api) {
      endPauseCursorGuard(confirmed && sample
        ? sample.currentTick
        : (lastPositionSample ? lastPositionSample.currentTick : Number(request.api.tickPosition)));
    }
    for (const resolve of request.waiters) resolve(!!confirmed);
    request.waiters.length = 0;
    return true;
  }

  function cancelPendingSeek() {
    const request = pendingSeek;
    if (!request) return;
    if (request.timer !== null) clearTimeout(request.timer);
    if (request.pauseTimer !== null) clearTimeout(request.pauseTimer);
    request.timer = null;
    request.pauseTimer = null;
    pendingSeek = null;
    for (const resolve of request.waiters) resolve(false);
    request.waiters.length = 0;
  }

  function armPendingSeekTimeout(request) {
    if (request.timer !== null) clearTimeout(request.timer);
    request.timer = setTimeout(() => {
      request.timer = null;
      if (pendingSeek !== request || request.api !== api || request.loadID !== activeLoadID || request.generation !== generation) return;
      request.timedOut = true;
      if (isPlaying) {
        try { request.api.pause(); } catch (_) { /* The bounded fallback below still reports the failure. */ }
        request.pauseTimer = setTimeout(() => finishPendingSeek(request, false), SEEK_PAUSE_STATE_TIMEOUT_MS);
      } else {
        finishPendingSeek(request, false);
      }
    }, SEEK_ACK_TIMEOUT_MS);
  }

  function issuePendingSeek(request) {
    if (pendingSeek !== request || request.api !== api || request.loadID !== activeLoadID || request.generation !== generation) return false;
    request.inFlightTick = request.targetTick;
    request.issuedAtMonotonicMs = performance.now();
    request.timedOut = false;
    if (request.pauseTimer !== null) clearTimeout(request.pauseTimer);
    request.pauseTimer = null;
    armPendingSeekTimeout(request);
    try {
      request.api.tickPosition = request.inFlightTick;
      return true;
    } catch (error) {
      finishPendingSeek(request, false, null, error && error.message ? error.message : '播放器没有接受定位请求。');
      return false;
    }
  }

  function requestSeek(tick, waitForConfirmation = false) {
    const value = Number(tick);
    if (!api || !Number.isFinite(value) || !Number.isFinite(api.endTick) || api.endTick <= 0) {
      return waitForConfirmation ? Promise.resolve(false) : false;
    }
    const targetTick = Math.max(0, Math.min(Number(api.endTick), Math.floor(value)));
    pendingPauseSample = null;

    let request = pendingSeek;
    if (request && (request.api !== api || request.loadID !== activeLoadID || request.generation !== generation)) {
      cancelPendingSeek();
      request = null;
    }
    if (!request) {
      request = {
        id: ++nextSeekRequestID,
        api,
        loadID: activeLoadID,
        generation,
        targetTick,
        inFlightTick: null,
        issuedAtMonotonicMs: 0,
        timer: null,
        pauseTimer: null,
        timedOut: false,
        ackSample: null,
        preserveAudioFocus: preserveAudioFocusForRender,
        waiters: [],
      };
      pendingSeek = request;
    } else {
      request.targetTick = targetTick;
      request.preserveAudioFocus = request.preserveAudioFocus || preserveAudioFocusForRender;
      if (request.timedOut) {
        if (request.timer !== null) clearTimeout(request.timer);
        if (request.pauseTimer !== null) clearTimeout(request.pauseTimer);
        request.timer = null;
        request.pauseTimer = null;
        request.inFlightTick = null;
        request.timedOut = false;
      }
    }

    let promise = null;
    if (waitForConfirmation) promise = new Promise((resolve) => request.waiters.push(resolve));
    if (request.inFlightTick === null) issuePendingSeek(request);
    return waitForConfirmation ? promise : true;
  }

  function seek(tick) {
    const value = Number(tick);
    if (!Number.isFinite(value)) return false;
    seekCoalesceLatestTick = value;
    if (seekCoalesceTimer !== null) return true;
    // First request applies immediately (bar click / keyboard); the progress slider
    // sends a seek for every pointer sample, so rapid follow-ups are coalesced to the
    // latest tick instead of forcing a playhead place ~60 times per second.
    seekCoalesceIssuedTick = value;
    const accepted = requestSeek(value, false);
    seekCoalesceTimer = setTimeout(() => {
      seekCoalesceTimer = null;
      const latest = seekCoalesceLatestTick;
      seekCoalesceLatestTick = null;
      if (!Number.isFinite(latest)) return;
      if (Number.isFinite(seekCoalesceIssuedTick) && Math.abs(latest - seekCoalesceIssuedTick) <= 0.5) return;
      seekCoalesceIssuedTick = latest;
      requestSeek(latest, false);
    }, SEEK_COALESCE_MS);
    return accepted;
  }

  function seekAndWait(tick) {
    return requestSeek(tick, true);
  }

  function isPendingSeekAck(sample, request = pendingSeek) {
    return !!request && request.api === api && request.loadID === activeLoadID
      && request.generation === generation && !!sample && sample.isSeek
      && Number.isFinite(Number(request.inFlightTick))
      && Number.isFinite(Number(sample.currentTick))
      && Math.abs(Number(sample.currentTick) - Number(request.inFlightTick)) <= 1;
  }

  function resetLoopProgressForSeek(sample) {
    const tick = Number(sample && sample.currentTick);
    const core = window.NativePracticeCore;
    if (!core || !playbackRange || !Number.isFinite(tick)) return;
    if (!loopLapProgress || loopLapProgress.generation !== loopGeneration) {
      loopLapProgress = core.createLoopLapProgress(loopGeneration, interruptionRevision, playbackRange);
    }
    loopLapProgress = core.observeLoopLapProgress(loopLapProgress, {
      tick,
      isSeek: true,
      generation: loopGeneration,
      interruptionRevision,
      range: playbackRange,
      playing: isPlaying,
      focused: isAudibleOwner,
      visible: nativeViewVisible && document.visibilityState !== 'hidden',
    });
  }

  function applyLoop(startTick, endTick) {
    if (!api || !Number.isSafeInteger(startTick) || !Number.isSafeInteger(endTick) ||
        startTick < 0 || endTick <= startTick || endTick > Number(api.endTick)) return;
    playbackRange = { startTick, endTick };
    loopGeneration += 1;
    loopLapSequence = 0;
    interruptionRevision += 1;
    loopLapProgress = window.NativePracticeCore
      ? window.NativePracticeCore.createLoopLapProgress(loopGeneration, interruptionRevision, playbackRange)
      : null;
    activeSpeedPlan = null;
    seenSpeedLapIDs.clear();
    api.isLooping = true;
    api.playbackRange = playbackRange;
    send('loop', { range: playbackRange, pointA: null });
    sendPlayerState();
  }

  function clearLoop() {
    pointA = null;
    playbackRange = null;
    loopGeneration += 1;
    interruptionRevision += 1;
    loopLapSequence = 0;
    loopLapProgress = null;
    if (api) {
      api.isLooping = false;
      api.playbackRange = null;
    }
    send('loop', { range: null, pointA: null });
    sendPlayerState();
  }

  function setLoopPoint(which) {
    if (!api || !['A', 'B'].includes(which)) return;
    const tick = Number(api.tickPosition);
    const beat = findBeatPosition(tick);
    if (!Number.isSafeInteger(Math.floor(tick)) || !beat) {
      send('error', { message: '暂时无法确认当前拍点，请稍后重试。' });
      return;
    }
    if (which === 'A') {
      pointA = { tick: Math.floor(tick), beatEndTick: beat.endTick };
      playbackRange = null;
      api.playbackRange = null;
      api.isLooping = true;
      interruptionRevision += 1;
      send('loop', { range: null, pointA });
      sendPlayerState();
      return;
    }
    if (!pointA || !window.NativePracticeCore) {
      send('error', { message: '请先设置 A 点。' });
      return;
    }
    try {
      const range = window.NativePracticeCore.normalizeLoop({
        pointATick: pointA.tick,
        pointABeatEndTick: pointA.beatEndTick,
        currentTick: Math.floor(tick),
        currentBeatEndTick: beat.endTick,
        scoreEndTick: Math.floor(Number(api.endTick)),
      });
      applyLoop(range.startTick, range.endTick);
    } catch (error) {
      send('error', { message: error && error.message ? error.message : '无法建立 A-B 区间。' });
    }
  }

  function toggleMetronome(enabled) {
    metronomeEnabled = !!enabled;
    if (api) api.metronomeVolume = metronomeEnabled ? 1 : 0;
    sendPlayerState();
  }

  function toggleCountIn(enabled) {
    countInEnabled = !!enabled;
    if (api) api.countInVolume = countInEnabled ? 1 : 0;
    sendPlayerState();
  }

  function setAudioFocus(enabled) {
    isAudibleOwner = !!enabled;
    if (!isAudibleOwner) interruptionRevision += 1;
  }

  function setNativeViewVisible(enabled) {
    nativeViewVisible = !!enabled;
    if (!nativeViewVisible) {
      interruptionRevision += 1;
      if (isPlaying) {
        pause();
      }
    }
  }

  function setMotionPreference(value) {
    const mode = ['full', 'gentle', 'off'].includes(value) ? value : 'full';
    document.documentElement.dataset.motion = mode;
    return mode;
  }

  function setViewportWidth(value) {
    const width = Number(value);
    if (!Number.isFinite(width) || width <= 0) return false;
    if (width === lastViewportWidth) return true;

    const rootFontSize = Math.max(14, Math.min(17.5, 13.44 + 0.0035 * width));
    const scorePadding = width < 640 ? '.75rem' : (width < 1024 ? '1rem' : '1.5rem');
    const root = document.documentElement;
    root.style.setProperty('--native-viewport-root-font-size', `${rootFontSize}px`);
    root.style.setProperty('--native-score-scroll-padding', scorePadding);
    lastViewportWidth = width;
    return true;
  }

  function createSpeedPlan(parameters) {
    const core = window.NativePracticeCore;
    if (!core || !playbackRange || !parameters || !api) return;
    try {
      activeSpeedPlan = core.createSpeedPlan(
        String(parameters.revision || ''),
        Number(parameters.startBpm),
        Number(parameters.targetBpm),
        Number(parameters.stepBpm),
        Number(parameters.lapsPerLevel),
        Number(sourceTempo),
        playbackRange,
      );
      seenSpeedLapIDs.clear();
      setPlaybackSpeed(activeSpeedPlan.currentBpm);
      send('speedPlan', { plan: activeSpeedPlan, lapId: null });
    } catch (error) {
      send('error', { message: error && error.message ? error.message : '提速计划无效。' });
    }
  }

  function setSpeedPlan(plan) {
    if (!plan || !Number.isFinite(Number(plan.currentBpm))) {
      activeSpeedPlan = null;
      seenSpeedLapIDs.clear();
      return;
    }
    activeSpeedPlan = plan;
    seenSpeedLapIDs.clear();
  }

  function clearSpeedPlan() {
    activeSpeedPlan = null;
    seenSpeedLapIDs.clear();
  }

  async function restoreResume(resume) {
    if (!api || !api.score || !resume || typeof resume !== 'object') return;
    const currentApi = api;
    if (isPlaying) {
      capturePauseSample(currentApi);
      currentApi.pause();
      isPlaying = false;
    }
    metronomeEnabled = resume.metronome === true;
    countInEnabled = resume.countIn === true;
    currentApi.metronomeVolume = metronomeEnabled ? 1 : 0;
    currentApi.countInVolume = countInEnabled ? 1 : 0;
    displayMode = resume.display && resume.display.scoreDisplayMode === 'tab' ? 'tab' : 'mixed';
    numberTab = !resume.display || resume.display.numberTab !== false;
    chordMode = !resume.display || resume.display.chordMode !== 'name' ? 'diagram' : 'name';
    if (resume.display && Number.isFinite(Number(resume.display.fontScale))) {
      zoom = Math.max(0.6, Math.min(1.6, Number(resume.display.fontScale)));
      currentApi.settings.display.scale = BASE_SCORE_SCALE * zoom;
      currentApi.updateSettings();
    }
    const wanted = Array.isArray(resume.trackIndexes)
      ? [...new Set(resume.trackIndexes.filter((index) => Number.isSafeInteger(index) && index >= 0 && index < currentApi.score.tracks.length))]
      : currentApi.score.tracks.map((_track, index) => index);
    visibleTrackIndexes = wanted.length ? wanted : [0];
    for (const state of trackMix) state.show = visibleTrackIndexes.includes(state.index);
    for (let trackIndex = 0; trackIndex < currentApi.score.tracks.length; trackIndex += 1) {
      const track = currentApi.score.tracks[trackIndex];
      for (let staffIndex = 0; staffIndex < (track.staves || []).length; staffIndex += 1) {
        const staff = track.staves[staffIndex];
        const source = sourceCapos[trackIndex] && sourceCapos[trackIndex][staffIndex];
        staff.capo = resume.useSourceCapo === true ? (Number(source) || 0) : (Number(resume.capo) || 0);
        staff.transpositionPitch = -(Number(resume.transpose) || 0);
      }
    }
    if (currentApi.score.stylesheet) currentApi.score.stylesheet.globalDisplayChordDiagramsInScore = chordMode === 'diagram';
    scoreRenderingRuntime().applyScoreDisplayMode(currentApi.score, displayMode);
    if (!numberTab) for (const track of currentApi.score.tracks) for (const staff of track.staves || []) staff.showNumbered = false;
    for (const saved of (Array.isArray(resume.trackMix) ? resume.trackMix : [])) {
      if (!Number.isSafeInteger(saved.index) || saved.index < 0 || saved.index >= currentApi.score.tracks.length) continue;
      const track = currentApi.score.tracks[saved.index];
      const state = trackMix[saved.index];
      if (!state) continue;
      // 旧断点可能没有 instrumentOverride；用 program 与原谱 program 的差异推断，避免丢用户音色。
      const resolved = resolveSavedInstrument(state.sourceProgram, saved.program, saved.instrumentOverride);
      const hadOverride = !!state.instrumentOverride;
      state.program = resolved.program;
      state.instrumentOverride = resolved.instrumentOverride;
      state.flavor = resolved.instrumentOverride ? 'gm' : (state.sourceFlavor || 'gm');
      if (resolved.instrumentOverride && !isPercussionTrack(track)) {
        applyTrackProgram(track, resolved.program);
      } else if (hadOverride) {
        restoreTrackProgramToSource(track, state);
      }
      state.muted = saved.muted === true;
      state.soloed = saved.soloed === true;
      state.volume = Number.isFinite(Number(saved.volume)) ? Math.max(0, Math.min(1, Number(saved.volume))) : 1;
      currentApi.changeTrackMute([track], state.muted || !visibleTrackIndexes.includes(saved.index));
      currentApi.changeTrackSolo([track], state.soloed);
      currentApi.changeTrackVolume([track], state.volume);
    }
    capo = Number(resume.capo) || 0;
    useSourceCapo = resume.useSourceCapo === true;
    transpose = Number(resume.transpose) || 0;
    const ratio = Number(resume.playbackRatio);
    if (Number.isFinite(ratio) && ratio >= 0.125 && ratio <= 8) currentApi.playbackSpeed = ratio;
    else setPlaybackSpeed(Number(resume.speed) || sourceTempo);
    const end = Number(currentApi.endTick) || 0;
    const range = resume.loop && Number.isSafeInteger(resume.loop.startTick) && Number.isSafeInteger(resume.loop.endTick) &&
      resume.loop.startTick >= 0 && resume.loop.endTick > resume.loop.startTick && resume.loop.endTick <= end
      ? { startTick: resume.loop.startTick, endTick: resume.loop.endTick }
      : null;
    playbackRange = range;
    currentApi.isLooping = !!range;
    currentApi.playbackRange = range;
    const planOK = await ensureSoundfontPlan(currentApi);
    if (currentApi !== api) return;
    if (!planOK) { sendPlayerState(); return; }
    if (!(await rebuildJsonScore(displayMode, { targetTick: Number(resume.tick) || 0 }))) {
      await renderWithAudioReload();
    }
    if (currentApi !== api) return;
    const seekConfirmed = await seekAndWait(Math.min(Number(currentApi.endTick) || 0, Math.max(0, Number(resume.tick) || 0)));
    if (!seekConfirmed || currentApi !== api) return;
    send('resumeRestored', { tick: currentApi.tickPosition, ratio: Number(currentApi.playbackSpeed) || 1 });
    sendPlayerState();
  }

  function setTrack(index, field, value) {
    if (!api || !api.score || !Number.isSafeInteger(index) || index < 0 || index >= api.score.tracks.length) return;
    const track = api.score.tracks[index];
    const state = trackMix[index];
    if (!track || !state) return;
    if (field === 'show') {
      state.show = !!value;
      visibleTrackIndexes = trackMix.filter((entry) => entry.show !== false).map((entry) => entry.index);
      api.changeTrackMute([track], !state.show || state.muted);
      const targetApi = api;
      void enqueueApiRender(
        targetApi,
        () => visibleTrackIndexes.length > 0,
        () => targetApi.renderTracks(visibleTrackIndexes.map((trackIndex) => targetApi.score.tracks[trackIndex])),
      ).catch((error) => send('error', { message: error && error.message ? error.message : String(error) }));
    } else if (field === 'muted') {
      state.muted = !!value;
      api.changeTrackMute([track], state.muted || state.show === false);
    } else if (field === 'soloed') {
      state.soloed = !!value;
      api.changeTrackSolo([track], state.soloed);
    } else if (field === 'volume') {
      const volume = Number(value);
      if (!Number.isFinite(volume)) return;
      state.volume = Math.max(0, Math.min(1, volume));
      api.changeTrackVolume([track], state.volume);
    } else if (field === 'program') {
      const program = Number(value);
      if (isPercussionTrack(track) || !Number.isSafeInteger(program) || program < 0 || program > 127) return;
      applyTrackProgram(track, program);
      state.program = program;
      state.instrumentOverride = true;
      state.flavor = 'gm';
      void renderWithAudioReload();
    } else if (field === 'restoreProgram') {
      if (isPercussionTrack(track)) return;
      state.program = state.sourceProgram;
      state.instrumentOverride = false;
      state.flavor = state.sourceFlavor || 'gm';
      if (hasRebuildableRawScore()) {
        // 从原始谱面 JSON 重建，才能同时把切音色时改写的 Instrument 自动化恢复为原谱值。
        void rebuildJsonScore(displayMode).catch((error) => send('error', {
          message: error && error.message ? error.message : '恢复原谱音色失败。',
          fatal: false,
        }));
      } else {
        restoreTrackProgramToSource(track, state);
        void renderWithAudioReload();
      }
    }
    send('tracks', { tracks: trackSnapshot() });
  }

  let renderQueue = Promise.resolve();

  function enqueueApiRender(targetApi, shouldRender, render) {
    const operation = renderQueue.then(async () => {
      if (targetApi !== api || !targetApi.score || !shouldRender()) return false;
      const rendered = waitForRenderFinished(targetApi);
      try { render(); }
      catch (error) { void rendered.catch(() => undefined); throw error; }
      await rendered;
      return true;
    });
    renderQueue = operation.catch(() => undefined);
    return operation;
  }

  function rebuildJsonScore(mode = displayMode, options = {}) {
    const targetApi = api;
    const targetGeneration = generation;
    const operation = renderQueue.then(() => {
      if (targetApi !== api || targetGeneration !== generation) return false;
      return performJsonScoreRebuild(mode, options);
    });
    renderQueue = operation.catch(() => undefined);
    return operation;
  }

  function waitForRenderFinished(targetApi, timeoutMs = 15000) {
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer = null;
      const cleanup = () => {
        if (timer) clearTimeout(timer);
        targetApi.renderFinished.off(onFinished);
      };
      const finish = (error = null) => {
        if (settled) return;
        settled = true;
        cleanup();
        if (error) reject(error);
        else resolve();
      };
      const onFinished = () => finish();
      targetApi.renderFinished.on(onFinished);
      timer = setTimeout(() => finish(new Error('等待谱面排版超时。')), timeoutMs);
    });
  }

  function waitForMidiLoaded(targetApi, timeoutMs = 15000) {
    const midiLoaded = targetApi && targetApi._player && targetApi._player._instance && targetApi._player._instance.midiLoaded;
    if (!midiLoaded || typeof midiLoaded.on !== 'function' || typeof midiLoaded.off !== 'function') {
      return Promise.reject(new Error('播放器没有可用的 MIDI 加载状态。'));
    }
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer = null;
      const cleanup = () => {
        if (timer) clearTimeout(timer);
        midiLoaded.off(onLoaded);
      };
      const finish = (error = null) => {
        if (settled) return;
        settled = true;
        cleanup();
        if (error) reject(error);
        else resolve();
      };
      const onLoaded = () => finish();
      midiLoaded.on(onLoaded);
      timer = setTimeout(() => finish(new Error('等待音频谱面更新超时。')), timeoutMs);
    });
  }

  function hasRebuildableRawScore() {
    return !!rawScoreJson && ['ibe', 'json', 'gp', 'musicxml'].includes(currentMode);
  }

  async function performJsonScoreRebuild(mode = displayMode, options = {}) {
    const currentApi = api;
    if (!currentApi || !currentApi.score || !hasRebuildableRawScore()) return false;
    const wasPlaying = isPlaying;
    const pauseSample = wasPlaying ? capturePauseSample(currentApi) : null;
    const requestedTick = Number(options.targetTick);
    const targetTick = Number.isFinite(requestedTick)
      ? requestedTick
      : (pauseSample ? Number(pauseSample.currentTick) : Number(currentApi.tickPosition) || 0);
    const reloadState = {
      wasPlaying,
      targetTick,
      playbackSpeed: Number(currentApi.playbackSpeed) || 1,
      displayMode: mode,
      numberTab,
      chordMode,
      capo,
      useSourceCapo,
      transpose,
      visibleTrackIndexes: [...visibleTrackIndexes],
      trackMix: trackMix.map((state) => ({ ...state })),
      pointA: pointA ? { ...pointA } : null,
      playbackRange: playbackRange ? { ...playbackRange } : null,
    };
    if (wasPlaying) {
      preserveAudioFocusForRender = true;
      currentApi.pause();
    }

    try {
      const planOK = await ensureSoundfontPlan(currentApi);
      if (currentApi !== api) return false;
      if (!planOK) {
        preserveAudioFocusForRender = false;
        sendPlayerState();
        return false;
      }
      const rendering = scoreRenderingRuntime();
      const score = rendering.createScoreFromJson(rawScoreJson, currentApi.settings, mode);
      if (scoreSourceMetadata.title) score.title = scoreSourceMetadata.title;
      if (scoreSourceMetadata.artist) score.artist = scoreSourceMetadata.artist;
      pendingScoreReloadState = reloadState;

      const rendered = waitForRenderFinished(currentApi);
      const midiReady = waitForMidiLoaded(currentApi);
      const selectedTrackIndexes = reloadState.visibleTrackIndexes
        .filter((index) => Number.isSafeInteger(index) && index >= 0 && index < score.tracks.length);
      const readiness = Promise.all([rendered, midiReady]);
      try { currentApi.renderScore(score, selectedTrackIndexes); }
      catch (error) { void readiness.catch(() => undefined); throw error; }
      await readiness;
      if (currentApi !== api) return false;
      pendingScoreReloadState = null;
      const validRange = reloadState.playbackRange
        && reloadState.playbackRange.startTick >= 0
        && reloadState.playbackRange.endTick > reloadState.playbackRange.startTick
        && reloadState.playbackRange.endTick <= Number(currentApi.endTick)
        ? reloadState.playbackRange
        : null;
      playbackRange = validRange;
      pointA = validRange ? null : reloadState.pointA;
      currentApi.isLooping = !!validRange || !!pointA;
      currentApi.playbackRange = validRange;
      currentApi.playbackSpeed = reloadState.playbackSpeed;
      applyTrackMixToApi(currentApi);
      const clampedTick = Math.max(0, Math.min(Number(currentApi.endTick) || targetTick, targetTick));
      requestSeek(validRange
        ? Math.min(Math.max(clampedTick, validRange.startTick), validRange.endTick - 1)
        : clampedTick, false);
      pendingPauseSample = null;
      if (reloadState.wasPlaying) {
        const started = isAudibleOwner ? currentApi.play() : false;
        preserveAudioFocusForRender = false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
          send('error', { message: '谱面显示已更新，但音频焦点未就绪，播放器没有自动恢复。', fatal: false });
        }
      } else {
        preserveAudioFocusForRender = false;
      }
      sendPlayerState();
      return true;
    } catch (error) {
      pendingScoreReloadState = null;
      pendingPauseSample = null;
      if (currentApi === api && reloadState.wasPlaying) {
        requestSeek(Math.max(0, Math.min(Number(currentApi.endTick) || targetTick, targetTick)), false);
        const started = isAudibleOwner ? currentApi.play() : false;
        preserveAudioFocusForRender = false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
          send('error', { message: '谱面显示更新失败，播放器无法自动恢复播放。', fatal: false });
        }
      } else {
        preserveAudioFocusForRender = false;
      }
      throw error;
    }
  }

  async function renderWithAudioReload() {
    const currentApi = api;
    if (!currentApi || !currentApi.score) return;
    const wasPlaying = isPlaying;
    let targetTick = Number(currentApi.tickPosition) || 0;
    if (wasPlaying) {
      const pauseSample = capturePauseSample(currentApi);
      if (pauseSample && Number.isFinite(Number(pauseSample.currentTick))) targetTick = Number(pauseSample.currentTick);
      preserveAudioFocusForRender = true;
      currentApi.pause();
    }
    const operation = renderQueue.then(async () => {
      if (currentApi !== api) return;
      // 音源计划可能与音色改动一起变化（例如恢复原谱尤克里里音色），先同步音源再重排。
      const planOK = await ensureSoundfontPlan(currentApi);
      if (currentApi !== api) return;
      if (!planOK) {
        preserveAudioFocusForRender = false;
        send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
        sendPlayerState();
        return;
      }
      let removeRender = null;
      const rendered = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          if (removeRender) removeRender();
          reject(new Error('等待谱面重排超时。'));
        }, 15000);
        const onFinished = () => {
          clearTimeout(timeout);
          if (removeRender) removeRender();
          resolve();
        };
        currentApi.renderFinished.on(onFinished);
        removeRender = () => currentApi.renderFinished.off(onFinished);
      });
      currentApi.renderScore(currentApi.score, visibleTrackIndexes);
      await rendered;
      if (currentApi !== api) return;
      const instance = currentApi._player && currentApi._player._instance;
      const midiLoaded = instance && instance.midiLoaded;
      if (midiLoaded && typeof currentApi.loadMidiForScore === 'function') {
        let onLoaded = null;
        const loaded = new Promise((resolve, reject) => {
          const timeout = setTimeout(() => {
            if (onLoaded) midiLoaded.off(onLoaded);
            reject(new Error('等待音频谱面更新超时。'));
          }, 15000);
          onLoaded = () => {
            clearTimeout(timeout);
            midiLoaded.off(onLoaded);
            resolve();
          };
          midiLoaded.on(onLoaded);
        });
        currentApi.loadMidiForScore();
        await loaded;
      }
      if (currentApi !== api) return;
      // MIDI 重新加载会重建通道状态：必须重新应用静音/独奏/音量，
      // 否则面板显示“已静音/30%”但实际按原音量发声。
      applyTrackMixToApi(currentApi);
      requestSeek(Math.min(targetTick, Number(currentApi.endTick) || targetTick), false);
      if (wasPlaying) {
        const started = isAudibleOwner ? currentApi.play() : false;
        preserveAudioFocusForRender = false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
          send('error', { message: '谱面更新完成，但音频焦点未就绪，播放器没有自动恢复；可以再按一次播放。', fatal: false });
        }
      } else {
        preserveAudioFocusForRender = false;
      }
      sendPlayerState();
    });
    renderQueue = operation.catch(() => undefined);
    try { await operation; }
    catch (error) {
      preserveAudioFocusForRender = false;
      if (currentApi === api && wasPlaying) {
        requestSeek(Math.min(targetTick, Number(currentApi.endTick) || targetTick), false);
        const started = isAudibleOwner ? currentApi.play() : false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
        }
      }
      send('error', { message: error && error.message ? error.message : String(error), fatal: false });
    }
  }

  function setCapo(value, useSource) {
    if (!api || !api.score) return;
    const next = Number(value);
    if (!Number.isSafeInteger(next) || next < 0 || next > 12) return;
    capo = next;
    useSourceCapo = !!useSource;
    api.score.tracks.forEach((track, trackIndex) => (track.staves || []).forEach((staff, staffIndex) => {
      const source = sourceCapos[trackIndex] && sourceCapos[trackIndex][staffIndex];
      staff.capo = useSourceCapo ? (Number(source) || 0) : next;
    }));
    void renderWithAudioReload();
  }

  function setTranspose(value) {
    if (!api || !api.score) return;
    const next = Number(value);
    if (!Number.isSafeInteger(next) || next < -24 || next > 24) return;
    transpose = next;
    for (const track of api.score.tracks) for (const staff of track.staves || []) staff.transpositionPitch = -next;
    void renderWithAudioReload();
  }

  function setDisplayMode(value) {
    if (!api || !api.score || !['mixed', 'tab'].includes(value)) return;
    displayMode = value;
    if (hasRebuildableRawScore()) {
      void rebuildJsonScore(value).catch((error) => send('error', { message: error && error.message ? error.message : String(error) }));
      return;
    }
    scoreRenderingRuntime().applyScoreDisplayMode(api.score, value);
    void renderWithAudioReload();
  }

  function setNumberTab(value) {
    if (!api || !api.score) return;
    numberTab = !!value;
    if (!numberTab) for (const track of api.score.tracks) for (const staff of track.staves || []) staff.showNumbered = false;
    else scoreRenderingRuntime().applyScoreDisplayMode(api.score, displayMode);
    void renderWithAudioReload();
  }

  function setChordMode(value) {
    if (!api || !api.score || !['name', 'diagram'].includes(value)) return;
    chordMode = value;
    api.score.stylesheet.globalDisplayChordDiagramsInScore = value === 'diagram';
    void renderWithAudioReload();
  }

  function restoreDefaults() {
    if (!api || !api.score) return;
    const currentApi = api;
    setPlaybackSpeed(sourceTempo);
    zoom = 1;
    currentApi.settings.display.scale = BASE_SCORE_SCALE;
    currentApi.updateSettings();
    capo = 0;
    useSourceCapo = true;
    transpose = 0;
    displayMode = 'mixed';
    numberTab = true;
    chordMode = 'diagram';
    visibleTrackIndexes = trackMix.map((state) => state.index);
    for (const state of trackMix) {
      state.show = true;
      state.muted = false;
      state.soloed = false;
      state.volume = 1;
      const wasOverride = !!state.instrumentOverride;
      state.program = state.sourceProgram;
      state.instrumentOverride = false;
      state.flavor = state.sourceFlavor || 'gm';
      const track = currentApi.score.tracks[state.index];
      if (!track) continue;
      if (wasOverride) restoreTrackProgramToSource(track, state);
      currentApi.changeTrackMute([track], false);
      currentApi.changeTrackSolo([track], false);
      currentApi.changeTrackVolume([track], 1);
      (track.staves || []).forEach((staff, staffIndex) => {
        staff.capo = Number(sourceCapos[state.index] && sourceCapos[state.index][staffIndex]) || 0;
        staff.transpositionPitch = 0;
      });
    }
    if (hasRebuildableRawScore()) {
      void rebuildJsonScore('mixed').catch((error) => send('error', { message: error && error.message ? error.message : String(error) }));
    } else {
      scoreRenderingRuntime().applyScoreDisplayMode(currentApi.score, 'mixed');
      if (currentApi.score.stylesheet) currentApi.score.stylesheet.globalDisplayChordDiagramsInScore = true;
      void renderWithAudioReload();
    }
    sendPlayerState();
  }

  function setZoom(value) {
    const next = Number(value);
    if (!Number.isFinite(next)) return;
    const updatedZoom = Math.max(0.6, Math.min(1.6, next));
    if (updatedZoom === zoom) return;
    zoom = updatedZoom;
    const requestedZoom = updatedZoom;
    const targetApi = api;
    if (!targetApi) return;
    void enqueueApiRender(targetApi, () => true, () => {
      targetApi.settings.display.scale = BASE_SCORE_SCALE * requestedZoom;
      targetApi.updateSettings();
      targetApi.render();
    }).catch((error) => send('error', { message: error && error.message ? error.message : String(error) }));
  }

  function scrollManuscriptToPage(pageNumber) { scrollToPage(pageNumber); }

  function dispose() {
    cancelPendingInitialRenderBarrier();
    cancelPendingSeek();
    generation += 1;
    runtimeDisposed = true;
    activeLoadID = null;
    clearPlaybackSpeedSyncState();
    lastWorkerPositionSample = null;
    if (sourceAbortController) sourceAbortController.abort();
    sourceAbortController = null;
    if (alphaTabWorkerPreparationAbortController) alphaTabWorkerPreparationAbortController.abort();
    alphaTabWorkerPreparationAbortController = null;
    alphaTabWorkerPreparation = null;
    if (alphaTabWorkerBlobURL) URL.revokeObjectURL(alphaTabWorkerBlobURL);
    alphaTabWorkerBlobURL = null;
    workerFactoryInstalled = false;
    if (manuscriptObserver) manuscriptObserver.disconnect();
    manuscriptObserver = null;
    if (manuscriptClickHandler) scoreElement.removeEventListener('click', manuscriptClickHandler, true);
    manuscriptClickHandler = null;
    if (manuscriptScrollHandler) scoreScroll.removeEventListener('scroll', manuscriptScrollHandler);
    manuscriptScrollHandler = null;
    if (manuscriptRefreshTimer) clearTimeout(manuscriptRefreshTimer);
    manuscriptRefreshTimer = null;
    if (manuscriptScrollFrame) {
      cancelAnimationFrame(manuscriptScrollFrame);
      manuscriptScrollFrame = 0;
    }
    cancelSeekCoalescer();
    endPauseCursorGuard(null, false);
    if (!api) return;
    try { api.stop(); } catch (_) { /* A failed player may already be stopped. */ }
    try { api.destroy(); } catch (_) { /* A failed player may already be disposed. */ }
    api = null;
    currentMode = null;
  }

  function setStaticExport(enabled) {
    xheSection.classList.toggle('xhe-static', !!enabled);
  }

  async function exportPdfPages(author) {
    const rendering = scoreRenderingRuntime();
    if (!api?.score || typeof rendering.renderPdfPageImages !== 'function') throw new Error('谱面尚未载入，无法生成分页 PDF。');
    const pages = await rendering.renderPdfPageImages(api.score, author || api.score.artist || '', visibleTrackIndexes);
    return JSON.stringify(pages);
  }

  async function exportPngData() {
    const rendering = scoreRenderingRuntime();
    if (!api?.score || typeof rendering.renderPngData !== 'function') throw new Error('谱面尚未载入，无法生成长图。');
    return await rendering.renderPngData(api);
  }

  function positionSnapshotSample(sample) {
    if (!sample) return null;
    return {
      timeMs: Number.isFinite(Number(sample.currentTime)) ? Number(sample.currentTime) : null,
      durationMs: Number.isFinite(Number(sample.endTime)) ? Number(sample.endTime) : null,
      tick: Number.isFinite(Number(sample.currentTick)) ? Number(sample.currentTick) : null,
      endTick: Number.isFinite(Number(sample.endTick)) ? Number(sample.endTick) : null,
      isSeek: !!sample.isSeek,
      speedRatio: Number.isFinite(Number(sample.speedRatio)) ? Number(sample.speedRatio) : null,
      originalTempo: Number.isFinite(Number(sample.originalTempo)) ? Number(sample.originalTempo) : null,
      modifiedTempo: Number.isFinite(Number(sample.modifiedTempo)) ? Number(sample.modifiedTempo) : null,
      sampledAtMonotonicMs: Number.isFinite(Number(sample.sampledAtMonotonicMs))
        ? Number(sample.sampledAtMonotonicMs)
        : null,
    };
  }

  function positionSnapshot() {
    const targetApi = api;
    const now = performance.now();
    const raw = targetApi && targetApi._player && targetApi._player.currentPosition;
    const request = pendingSeek;
    return {
      ready: !!targetApi,
      loadID: activeLoadID,
      isPlaying,
      sampledAtMonotonicMs: now,
      pendingSeek: request ? {
        id: request.id,
        generation: request.generation,
        targetTick: request.targetTick,
        inFlightTick: request.inFlightTick,
        ageMs: Math.max(0, now - request.issuedAtMonotonicMs),
        timedOut: request.timedOut,
      } : null,
      rawWorkerPosition: positionSnapshotSample(lastWorkerPositionSample),
      lastPosition: positionSnapshotSample(lastPositionSample),
      apiPlayerCurrentPosition: positionSnapshotSample(raw),
    };
  }

  function diagnostics() {
    const targetApi = api;
    if (!targetApi) return { ready: false, diagnosticsReadOnly: true };
    const settings = targetApi.settings;
    const ui = targetApi.uiFacade;
    let scroll = null;
    let scrollDom = null;
    let containerOffset = null;
    try {
      scroll = ui && typeof ui.getScrollContainer === 'function' ? ui.getScrollContainer() : null;
      scrollDom = scroll && scroll.element ? scroll.element : null;
      if (scroll && typeof ui.getOffset === 'function') {
        const offset = ui.getOffset(scroll, targetApi.container);
        if (offset) containerOffset = { x: offset.x, y: offset.y, width: offset.w, height: offset.h };
      }
    } catch (_) { /* Diagnostics must never interrupt playback. */ }

    const alphaTab = window.alphaTab;
    const resources = settings.display && settings.display.resources;
    const notationElementNames = [
      'ChordDiagrams', 'EffectChordNames', 'EffectLyrics', 'EffectMarker',
      'GuitarTuning', 'TrackNames', 'ScoreWords', 'ScoreMusic', 'ScoreWordsAndMusic',
    ];
    const notationElements = {};
    for (const name of notationElementNames) {
      const element = alphaTab && alphaTab.NotationElement && alphaTab.NotationElement[name];
      notationElements[name] = settings.notation && settings.notation.elements
        ? settings.notation.elements.get(element)
        : null;
    }
    const fontNames = [
      'EffectChordNames', 'EffectHammerOnPullOffText', 'EffectSlideText',
      'EffectText', 'EffectLyrics', 'EffectCapo', 'BarNumber', 'RepeatCount',
    ];
    const elementFonts = {};
    for (const name of fontNames) {
      const element = alphaTab && alphaTab.NotationElement && alphaTab.NotationElement[name];
      const font = resources && resources.elementFonts && resources.elementFonts.get(element);
      elementFonts[name] = font ? {
        size: font.size,
        families: Array.isArray(font.families) ? [...font.families] : font.families,
        style: font.style,
      } : null;
    }

    const fontSizes = alphaTab && alphaTab.platform && alphaTab.platform.FontSizes;
    const lookupTables = fontSizes && fontSizes.fontSizeLookupTables;
    const controlChars = Number.isFinite(Number(fontSizes && fontSizes.ControlChars))
      ? Number(fontSizes.ControlChars)
      : 32;
    const cacheSampleCharacters = ['5', '7', 'H', 'P', 'C', 'a', 'd', '9'];
    const sampleCachedTable = (table) => {
      if (!table || !table.characterWidths || !table.characterHeights) return null;
      const samples = {};
      for (const character of cacheSampleCharacters) {
        const index = character.charCodeAt(0) - controlChars;
        samples[character] = index >= 0 && index < table.characterWidths.length
          ? { width: table.characterWidths[index], height: table.characterHeights[index] }
          : null;
      }
      return samples;
    };
    const fontSizeLookupCache = {
      available: lookupTables instanceof Map,
      controlChars,
      families: [],
      elements: {},
    };
    if (lookupTables instanceof Map) {
      fontSizeLookupCache.families = Array.from(lookupTables, ([family, table]) => ({
        family,
        cached: true,
        samples: sampleCachedTable(table),
      }));
    }
    for (const name of fontNames) {
      const descriptor = elementFonts[name];
      const families = descriptor && Array.isArray(descriptor.families) ? descriptor.families : [];
      const cachedFamily = lookupTables instanceof Map
        ? families.find((family) => lookupTables.has(family)) || null
        : null;
      const cachedTable = cachedFamily && lookupTables.get(cachedFamily);
      fontSizeLookupCache.elements[name] = {
        cached: !!cachedFamily,
        preferredFamily: families[0] || null,
        selectedCachedFamily: cachedFamily,
        samples: cachedFamily ? sampleCachedTable(cachedTable) : null,
      };
    }

    const scrollHandler = targetApi._defaultScrollHandler;
    return {
      ready: true,
      diagnosticsReadOnly: true,
      settings: {
        notation: {
          rhythmMode: settings.notation && settings.notation.rhythmMode,
          rhythmHeight: settings.notation && settings.notation.rhythmHeight,
          namedElements: notationElements,
          elements: settings.notation && settings.notation.elements
            ? Array.from(settings.notation.elements.entries(), ([key, value]) => [String(key), value])
            : [],
        },
        layoutMode: settings.display && settings.display.layoutMode,
        scrollMode: settings.player && settings.player.scrollMode,
        scrollSpeed: settings.player && settings.player.scrollSpeed,
        scrollOffsetY: settings.player && settings.player.scrollOffsetY,
        scrollElement: settings.player && settings.player.scrollElement,
      },
      scroll: {
        id: scrollDom && scrollDom.id || '',
        tag: scrollDom && scrollDom.tagName || '',
        scrollTop: scrollDom && scrollDom.scrollTop,
        clientHeight: scrollDom && scrollDom.clientHeight,
        scrollHeight: scrollDom && scrollDom.scrollHeight,
        containerOffset,
      },
      cursor: {
        defaultScrollHandler: scrollHandler && scrollHandler.constructor ? scrollHandler.constructor.name : '',
        customScrollHandlerInstalled: !!targetApi.customScrollHandler,
        scrollHandlerMode: targetApi._scrollHandlerMode,
        scrollHandlerVertical: targetApi._scrollHandlerVertical,
        beatMouseDown: !!targetApi._isBeatMouseDown,
      },
      fonts: {
        effectFontSize: resources && resources.effectFont && resources.effectFont.size,
        elementFonts,
        fontSizeLookupCache,
      },
    };
  }

  window.addEventListener('pagehide', () => { dispose(); });
  window.addEventListener('beforeunload', () => { dispose(); });

  window.NativePlayer = Object.freeze({
    diagnosticsReadOnly: true,
    load, playPause, play, pause, stop, seek, setTempo: setPlaybackSpeed, setZoom,
    setLoopPoint, applyLoop, clearLoop, toggleMetronome, toggleCountIn, setTrack,
    setAudioFocus, setNativeViewVisible, setMotionPreference, setViewportWidth, setCapo, setTranspose, setDisplayMode, setNumberTab, setChordMode, restoreDefaults,
    createSpeedPlan, setSpeedPlan, clearSpeedPlan, restoreResume,
    setStaticExport, exportPdfPages, exportPngData, diagnostics, positionSnapshot, scrollManuscriptToPage, seekBar, dispose,
  });
  send('ready');
})();
