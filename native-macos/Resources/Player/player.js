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
  let lastPositionMessage = 0;
  let lastPositionSample = null;
  let lastWorkerPositionSample = null;
  let pendingPauseSample = null;
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

  function capturePauseSample(targetApi = api) {
    if (!targetApi) return null;
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
    const raw = targetApi._player && targetApi._player.currentPosition || lastPositionSample || {};
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
          targetApi.playbackSpeed = targetRatio;
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

  function trackSnapshot() {
    if (!api || !api.score) return [];
    return api.score.tracks.map((track, index) => {
      const existing = trackMix.find((value) => value.index === index);
      const program = Number(track.playbackInfo && track.playbackInfo.program);
      const percussion = !!track.isPercussion || program === 128;
      return {
        index,
        name: String(track.name || `音轨 ${index + 1}`),
        program: Number.isSafeInteger(program) ? program : (percussion ? 128 : 0),
        sourceProgram: existing ? existing.sourceProgram : (Number.isSafeInteger(program) ? program : 0),
        sourceCapo: sourceCapos[index] && sourceCapos[index].length ? sourceCapos[index][0] : 0,
        percussion,
        show: visibleTrackIndexes.includes(index),
        muted: existing ? existing.muted : false,
        soloed: existing ? existing.soloed : false,
        volume: existing ? existing.volume : 1,
        instrumentOverride: existing ? existing.instrumentOverride : false,
        tuning: (track.staves && track.staves[0] && track.staves[0].stringTuning && track.staves[0].stringTuning.tunings || []).map((value) => Number(value)),
      };
    });
  }

  function applyTrackProgram(track, program) {
    if (!track || track.isPercussion || !Number.isSafeInteger(program) || program < 0 || program > 127) return;
    const gm = window.NativePracticeCore && window.NativePracticeCore.gmInstruments;
    const name = gm && gm[program] ? String(gm[program][1]) : `GM ${program + 1}`;
    track.playbackInfo.program = program;
    track.name = name;
    track.shortName = name;
    const instrumentType = window.alphaTab.model.AutomationType && window.alphaTab.model.AutomationType.Instrument;
    if (!Number.isSafeInteger(instrumentType)) return;
    for (const staff of (track.staves || [])) for (const bar of (staff.bars || [])) {
      for (const voice of (bar.voices || [])) for (const beat of (voice.beats || [])) {
        for (const automation of (beat.automations || [])) if (automation.type === instrumentType) automation.value = program;
      }
    }
  }

  function createTrackMixState(score, previous = null, visible = null) {
    const previousByIndex = new Map((previous || []).map((state) => [state.index, state]));
    return score.tracks.map((track, index) => {
      const old = previousByIndex.get(index);
      const sourceProgram = Number(track.playbackInfo && track.playbackInfo.program) || 0;
      const state = old
        ? { ...old, index, sourceProgram: Number(old.sourceProgram) || sourceProgram, sourceName: old.sourceName || String(track.name || `音轨 ${index + 1}`) }
        : {
          index,
          show: visible ? visible.includes(index) : true,
          muted: false,
          soloed: false,
          volume: 1,
          program: sourceProgram,
          sourceProgram,
          sourceName: String(track.name || `音轨 ${index + 1}`),
          instrumentOverride: false,
        };
      if (!old) state.program = sourceProgram;
      if (state.instrumentOverride && !track.isPercussion) {
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

  function readManuscriptPages() {
    if (!scoreElement) return;
    const pageNodes = Array.from(scoreElement.querySelectorAll('.at-page, .at-surface'))
      .filter((node, index, all) => !all.some((other, otherIndex) => otherIndex !== index && other.contains(node)));
    manuscriptPageNodes = pageNodes.length ? pageNodes : Array.from(scoreElement.querySelectorAll('svg'));
    manuscriptPageCount = Math.max(1, manuscriptPageNodes.length);
    updateCurrentManuscriptPage(false);
  }

  function updateCurrentManuscriptPage(notify = true) {
    const rootRect = scoreScroll.getBoundingClientRect();
    const focusY = rootRect.top + Math.min(rootRect.height * 0.38, 260);
    let nearestIndex = 0;
    let nearestDistance = Infinity;
    manuscriptPageNodes.forEach((node, index) => {
      const rect = node.getBoundingClientRect();
      const distance = focusY < rect.top ? rect.top - focusY : focusY > rect.bottom ? focusY - rect.bottom : 0;
      if (distance < nearestDistance) { nearestDistance = distance; nearestIndex = index; }
    });
    const currentPage = Math.min(manuscriptPageCount, nearestIndex + 1);
    if (notify) send('manuscript', { pageCount: manuscriptPageCount, currentPage });
    else send('manuscript', { pageCount: manuscriptPageCount, currentPage });
  }

  function scrollToPage(pageNumber) {
    const page = Math.max(1, Math.min(manuscriptPageCount, Math.trunc(Number(pageNumber) || 1)));
    const node = manuscriptPageNodes[page - 1];
    if (!node) return;
    const rootRect = scoreScroll.getBoundingClientRect();
    const nodeRect = node.getBoundingClientRect();
    scoreScroll.scrollTo({ top: scoreScroll.scrollTop + nodeRect.top - rootRect.top - 14, behavior: 'smooth' });
    send('manuscript', { pageCount: manuscriptPageCount, currentPage: page });
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
    seek(tick);
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
    manuscriptScrollHandler = () => updateCurrentManuscriptPage();
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
    send('error', { message: safeMessage });
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
    api.playbackSpeed = ratio;
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

  function createApi(metadata, loadID, loadGeneration) {
    const alphaTab = window.alphaTab;
    if (!alphaTab || !alphaTab.AlphaTabApi) throw new Error('本地 AlphaTab 引擎无法启动。');
    const rendering = scoreRenderingRuntime();
    if (api) {
      try { api.destroy(); } catch (_) { /* A failed previous load may already be disposed. */ }
      api = null;
    }

    const settings = rendering.createScoreSettings();
    settings.core.useWorkers = false;
    settings.core.enableLazyLoading = false;
    settings.core.scriptFile = `${BASE}/alphaTab.js`;
    settings.core.fontDirectory = `${BASE}/font/`;
    settings.player.soundFont = `${BASE}/soundfont/main`;
    settings.player.scrollElement = '#score-scroll';
    settings.display.scale = BASE_SCORE_SCALE * zoom;

    api = new alphaTab.AlphaTabApi(scoreElement, settings);
    const isCurrentLoad = () => loadGeneration === generation && loadID === activeLoadID;
    api.renderStarted.on(() => { if (isCurrentLoad()) sendFor(loadID, 'stage', { value: '排版乐谱' }); });
    api.renderFinished.on(() => {
      if (!isCurrentLoad()) return;
      installManuscriptInteraction(loadID);
      sendFor(loadID, 'scoreReady', { mode: 'score' });
    });
    api.error.on((error) => { if (!isCurrentLoad()) return; sendFor(loadID, 'error', {
      message: error && error.message ? error.message : String(error || 'AlphaTab 载入失败。'),
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
    api.soundFontLoaded.on(() => { if (isCurrentLoad()) sendFor(loadID, 'soundReady'); });
    api.playerStateChanged.on((event) => {
      if (isCurrentLoad()) {
        const state = Number(event && event.state);
        const wasPlaying = isPlaying;
        isPlaying = state === 1;
        if (state === 1) {
          if (Number(pendingPlaybackSpeedRatio) > 0) armPlaybackSpeedAckWatchdog();
        } else {
          cancelPlaybackSpeedAckWatchdog(false);
        }
        if (wasPlaying && !isPlaying) {
          interruptionRevision += 1;
          if (pendingPauseSample && !(event && event.stopped)) {
            const pauseTick = Number(pendingPauseSample.currentTick);
            const snappedTick = Number(api.tickPosition);
            if (Number.isFinite(pauseTick) && Number.isFinite(snappedTick) && Math.abs(pauseTick - snappedTick) > 0.01) {
              // AlphaTab 1.8.4 snaps to the beat start as part of pause. Restore the sampled tick
              // through the same audio player so pause, resume and cursor remain on one position.
              api.tickPosition = pauseTick;
            }
          } else {
            lastPositionSample = sampleCurrentPosition(api, false);
          }
          pendingPauseSample = null;
        }
        if (state === 1) lastPositionSample = sampleCurrentPosition(api, false);
        if (state === 2) lastPositionSample = sampleCurrentPosition(api, false);
        const anchor = currentPositionAnchor(isPlaying);
        const preserveAudioFocus = state !== 1 && preserveAudioFocusForRender;
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
      const pendingRatio = Number(pendingPlaybackSpeedRatio);
      if (pendingRatio > 0) {
        if (!speedRatiosMatch(eventSpeedRatio, pendingRatio)) return;
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
    api.renderFinished.on(() => { if (isCurrentLoad()) sendFor(loadID, 'playerSnapshot', {
      tracks: trackSnapshot(),
      scoreEndTick: Number(api.endTick) || 0,
      gmInstruments: window.NativePracticeCore ? window.NativePracticeCore.gmInstruments : [],
      displayMode, numberTab, chordMode, capo, useSourceCapo, transpose,
      metronome: metronomeEnabled, countIn: countInEnabled, loop: playbackRange,
    }); });
    return api;
  }

  async function load(parameters) {
    if (!parameters || typeof parameters.kind !== 'string' || typeof parameters.loadID !== 'string') {
      fail('谱面来源无效。');
      return;
    }
    const loadID = parameters.loadID;
    activeLoadID = loadID;
    const loadGeneration = ++generation;
    if (sourceAbortController) sourceAbortController.abort();
    const controller = new AbortController();
    sourceAbortController = controller;
    currentMode = parameters.kind;
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

      const currentApi = createApi(parameters, loadID, loadGeneration);
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
    if (isPlaying) {
      capturePauseSample(api);
      cancelPlaybackSpeedAckWatchdog(false);
    }
    try { api.playPause(); }
    catch (error) { send('error', { message: error && error.message ? error.message : String(error) }); }
  }

  function pause() {
    if (!api) return;
    if (isPlaying) {
      capturePauseSample(api);
      cancelPlaybackSpeedAckWatchdog(false);
    }
    try { api.pause(); }
    catch (error) { send('error', { message: error && error.message ? error.message : String(error) }); }
  }

  function stop() {
    if (!api) return;
    cancelPlaybackSpeedAckWatchdog(false);
    pendingPauseSample = null;
    try { api.stop(); }
    catch (error) { send('error', { message: error && error.message ? error.message : String(error) }); }
    interruptionRevision += 1;
    isPlaying = false;
  }

  function play() {
    if (!api || isPlaying || !isAudibleOwner || !nativeViewVisible || document.visibilityState === 'hidden') return;
    try {
      const result = api.play();
      if (result === false) send('error', { message: '播放器没有接受播放请求。' });
    } catch (error) {
      send('error', { message: error && error.message ? error.message : String(error) });
    }
  }

  function seek(tick) {
    const value = Number(tick);
    if (!api || !Number.isFinite(value) || !Number.isFinite(api.endTick) || api.endTick <= 0) return;
    api.tickPosition = Math.max(0, Math.min(api.endTick, Math.floor(value)));
    lastPositionSample = sampleCurrentPosition(api, true);
    pendingPauseSample = null;
    const anchor = positionFields(lastPositionSample, isPlaying);
    send('position', { ...anchor, anchorReason: 'seek' });
    send('playbackState', { state: isPlaying ? 1 : 0, ...anchor, anchorReason: 'seek' });
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
    if (!nativeViewVisible) interruptionRevision += 1;
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
      if (!track.isPercussion && saved.instrumentOverride === true && Number.isSafeInteger(saved.program) && saved.program >= 0 && saved.program <= 127) {
        applyTrackProgram(track, saved.program);
        state.program = saved.program;
        state.instrumentOverride = true;
      } else if (!track.isPercussion) {
        track.playbackInfo.program = state.sourceProgram;
        track.name = state.sourceName;
        track.shortName = state.sourceName;
        state.program = state.sourceProgram;
        state.instrumentOverride = false;
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
    if (!(await rebuildJsonScore(displayMode, { targetTick: Number(resume.tick) || 0 }))) {
      await renderWithAudioReload();
    }
    if (currentApi !== api) return;
    seek(Math.min(Number(currentApi.endTick) || 0, Math.max(0, Number(resume.tick) || 0)));
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
      api.renderTracks(visibleTrackIndexes.map((trackIndex) => api.score.tracks[trackIndex]));
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
      if (track.isPercussion || !Number.isSafeInteger(program) || program < 0 || program > 127) return;
      applyTrackProgram(track, program);
      state.program = program;
      state.instrumentOverride = true;
      void renderWithAudioReload();
    } else if (field === 'restoreProgram') {
      track.playbackInfo.program = state.sourceProgram;
      track.name = state.sourceName;
      track.shortName = state.sourceName;
      state.program = state.sourceProgram;
      state.instrumentOverride = false;
      void renderWithAudioReload();
    }
    send('tracks', { tracks: trackSnapshot() });
  }

  let renderQueue = Promise.resolve();

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

  async function performJsonScoreRebuild(mode = displayMode, options = {}) {
    const currentApi = api;
    if (!currentApi || !currentApi.score || !rawScoreJson || !['ibe', 'json'].includes(currentMode)) return false;
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
      const rendering = scoreRenderingRuntime();
      const settings = rendering.createScoreSettings();
      settings.display.scale = BASE_SCORE_SCALE * zoom;
      const score = rendering.createScoreFromJson(rawScoreJson, settings, mode);
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
      currentApi.tickPosition = validRange
        ? Math.min(Math.max(clampedTick, validRange.startTick), validRange.endTick - 1)
        : clampedTick;
      lastPositionSample = null;
      pendingPauseSample = null;
      if (reloadState.wasPlaying) {
        const started = isAudibleOwner ? currentApi.play() : false;
        preserveAudioFocusForRender = false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
          send('error', { message: '谱面显示已更新，但音频焦点未就绪，播放器没有自动恢复。' });
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
        currentApi.tickPosition = Math.max(0, Math.min(Number(currentApi.endTick) || targetTick, targetTick));
        const started = isAudibleOwner ? currentApi.play() : false;
        preserveAudioFocusForRender = false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
          send('error', { message: '谱面显示更新失败，播放器无法自动恢复播放。' });
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
      currentApi.tickPosition = Math.min(targetTick, Number(currentApi.endTick) || targetTick);
      if (wasPlaying) {
        const started = isAudibleOwner ? currentApi.play() : false;
        preserveAudioFocusForRender = false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
          send('error', { message: '谱面更新完成，但音频焦点未就绪，播放器没有自动恢复。' });
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
        currentApi.tickPosition = Math.min(targetTick, Number(currentApi.endTick) || targetTick);
        const started = isAudibleOwner ? currentApi.play() : false;
        if (started === false) {
          send('playbackState', { state: 0, ...positionFields(sampleCurrentPosition(currentApi), false), preserveAudioFocus: false });
        }
      }
      send('error', { message: error && error.message ? error.message : String(error) });
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
    if (rawScoreJson && ['ibe', 'json'].includes(currentMode)) {
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
      if (state.instrumentOverride) {
        const track = currentApi.score.tracks[state.index];
        if (track && !track.isPercussion) {
          track.playbackInfo.program = state.sourceProgram;
          track.name = state.sourceName;
          track.shortName = state.sourceName;
          const instrumentType = window.alphaTab.model.AutomationType && window.alphaTab.model.AutomationType.Instrument;
          if (Number.isSafeInteger(instrumentType)) {
            for (const staff of track.staves || []) for (const bar of (staff.bars || [])) {
              for (const voice of (bar.voices || [])) for (const beat of (voice.beats || [])) {
                for (const automation of (beat.automations || [])) if (automation.type === instrumentType) automation.value = state.sourceProgram;
              }
            }
          }
          state.program = state.sourceProgram;
          state.instrumentOverride = false;
        }
      }
      const track = currentApi.score.tracks[state.index];
      if (!track) continue;
      currentApi.changeTrackMute([track], false);
      currentApi.changeTrackSolo([track], false);
      currentApi.changeTrackVolume([track], 1);
      (track.staves || []).forEach((staff, staffIndex) => {
        staff.capo = Number(sourceCapos[state.index] && sourceCapos[state.index][staffIndex]) || 0;
        staff.transpositionPitch = 0;
      });
    }
    if (rawScoreJson && ['ibe', 'json'].includes(currentMode)) {
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
    zoom = Math.max(0.6, Math.min(1.6, next));
    if (!api) return;
    api.settings.display.scale = BASE_SCORE_SCALE * zoom;
    api.updateSettings();
    api.render();
  }

  function scrollManuscriptToPage(pageNumber) { scrollToPage(pageNumber); }

  function dispose() {
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

  window.NativePlayer = Object.freeze({
    load, playPause, play, pause, stop, seek, setTempo: setPlaybackSpeed, setZoom,
    setLoopPoint, applyLoop, clearLoop, toggleMetronome, toggleCountIn, setTrack,
    setAudioFocus, setNativeViewVisible, setMotionPreference, setViewportWidth, setCapo, setTranspose, setDisplayMode, setNumberTab, setChordMode, restoreDefaults,
    createSpeedPlan, setSpeedPlan, clearSpeedPlan, restoreResume,
    setStaticExport, exportPdfPages, exportPngData, scrollManuscriptToPage, seekBar, dispose,
  });
  send('ready');
})();
