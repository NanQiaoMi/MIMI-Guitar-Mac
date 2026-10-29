(() => {
  'use strict';

  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.studio;
  const scoreHost = document.getElementById('studio-score');
  const errorHost = document.getElementById('studio-error');
  let api = null;
  let project = null;
  let disposed = false;
  let bootstrapGeneration = 0;
  let alphaTabWorkerBlobURL = null;
  let alphaTabWorkerPreparation = null;
  let alphaTabWorkerPreparationAbortController = null;
  let workerFactoryInstalled = false;
  let renderGeneration = 0;
  let pendingCanvasDraw = null;
  let cursor = { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1 };
  let pendingDigit = '';
  let digitTimer = 0;

  function send(type, values = {}) {
    if (disposed || !bridge) return;
    try { bridge.postMessage({ type, ...values }); } catch {}
  }

  function fail(error) {
    errorHost.hidden = false;
    errorHost.textContent = error instanceof Error ? error.message : String(error || '谱面渲染失败');
    recordRenderTrace('failure', { message: errorHost.textContent });
    send('renderError', { message: errorHost.textContent });
  }

  function recordRenderTrace(stage, values = {}) {
    if (window.__MIMI_RUNTIME_RENDER_TRACE !== true) return;
    let trace = window.__mimiStudioRenderTrace;
    if (!trace || !Array.isArray(trace.events)) {
      trace = { events: [] };
      window.__mimiStudioRenderTrace = trace;
    }
    if (trace.events.length < 96) {
      trace.events.push({ stage, atMs: Math.round(performance.now()), ...values });
    }
  }

  function installAlphaTabWorkerFactory(alphaTab, workerBlobURL) {
    const environment = alphaTab && alphaTab.Environment;
    if (!environment || typeof environment.initializeMain !== 'function') {
      throw new Error('本地 AlphaTab worker 接口不可用。');
    }
    environment.initializeMain((settings, name) => {
      if (disposed || alphaTabWorkerBlobURL !== workerBlobURL) {
        throw new Error('工坊 AlphaTab worker 已关闭。');
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
    if (disposed) throw new Error('工坊页面已关闭。');
    if (alphaTabWorkerBlobURL) {
      if (!workerFactoryInstalled) installAlphaTabWorkerFactory(alphaTab, alphaTabWorkerBlobURL);
      return;
    }
    if (!alphaTabWorkerPreparation) {
      const generation = bootstrapGeneration;
      const controller = new AbortController();
      alphaTabWorkerPreparationAbortController = controller;
      const preparation = (async () => {
        const response = await fetch('/alphaTab.js', { signal: controller.signal });
        if (!response.ok) throw new Error(`本地 AlphaTab worker 读取失败（${response.status}）。`);
        const runtimeSource = await response.text();
        if (disposed || generation !== bootstrapGeneration || controller.signal.aborted) return;
        const blobURL = URL.createObjectURL(new Blob([runtimeSource], { type: 'text/javascript' }));
        if (disposed || generation !== bootstrapGeneration || controller.signal.aborted) {
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
    if (disposed) throw new Error('工坊页面已关闭。');
    if (!alphaTabWorkerBlobURL || !workerFactoryInstalled) throw new Error('本地 AlphaTab worker 准备失败。');
  }

  function configureApi() {
    const alphaTab = window.alphaTab;
    if (!alphaTab || !alphaTab.AlphaTabApi || !window.NativeStudioCore) throw new Error('本地工坊谱面引擎未能启动。');
    const settings = new alphaTab.Settings();
    settings.core.scriptFile = '/alphaTab.js';
    settings.core.fontDirectory = '/font/';
    settings.core.useWorkers = false;
    settings.core.enableLazyLoading = false;
    settings.importer.beatTextAsLyrics = true;
    settings.display.scale = 0.95;
    settings.display.layoutMode = alphaTab.LayoutMode.Page;
    settings.display.staveProfile = alphaTab.StaveProfile.ScoreTab;
    settings.player.enablePlayer = true;
    settings.player.playerMode = alphaTab.PlayerMode.EnabledSynthesizer;
    settings.player.outputMode = alphaTab.PlayerOutputMode.WebAudioScriptProcessor;
    settings.player.enableCursor = true;
    settings.player.enableAnimatedBeatCursor = true;
    settings.player.enableElementHighlighting = true;
    settings.player.enableUserInteraction = true;
    settings.player.soundFont = '/soundfont/main';
    settings.player.scrollElement = '#studio-score-scroll';
    settings.player.scrollMode = alphaTab.ScrollMode.OffScreen;
    if (settings.display.resources?.engravingSettings) settings.display.resources.engravingSettings.tabLineSpacing = 16.5;
    api = new alphaTab.AlphaTabApi(scoreHost, settings);
    window.__studioApi = api;
    api.error.on((event) => {
      recordRenderTrace('alphaTabError', {
        type: Number.isFinite(Number(event?.type)) ? Number(event.type) : null,
        message: String(event?.message || event || ''),
      });
      if (event && Number(event.type) <= 2) fail(event.message || 'AlphaTab 无法解析当前工程。');
    });
    api.postRenderFinished.on(() => {
      errorHost.hidden = true;
      recordRenderTrace('postRenderFinished', {
        hasScore: !!api?.score,
        trackCount: Number(api?.score?.tracks?.length || 0),
        barCount: Number(api?.score?.masterBars?.length || 0),
      });
      send('ready', { title: project?.title || '', cursor });
    });
    api.beatMouseDown.on((beat) => placeCursor(beat, null));
    api.beatMouseUp.on((beat) => beat && placeCursor(beat, null));
    api.noteMouseDown.on((note) => placeCursor(note?.beat, note));
    api.playedBeatChanged.on((beat) => {
      if (!beat || !project) return;
      const barIndex = Number(beat.voice?.bar?.masterBar?.index ?? beat.voice?.bar?.index ?? 0);
      const beatIndex = Number(beat.index ?? 0);
      send('playedBeat', { barIndex, beatIndex });
    });
    const player = api.player || api._player;
    player?.stateChanged?.on((state) => send('playback', { isPlaying: Number(state?.state ?? state) === 1 }));
    player?.positionChanged?.on((position) => send('position', { currentTime: Number(position?.currentTime ?? position ?? 0), endTime: Number(api.endTick ?? 0) }));
    api.scoreLoaded.on(() => {
      recordRenderTrace('scoreLoaded', {
        hasScore: !!api?.score,
        trackCount: Number(api?.score?.tracks?.length || 0),
        barCount: Number(api?.score?.masterBars?.length || 0),
      });
      send('loaded', { endTime: Number(api.endTick ?? 0) });
    });
    scoreHost.addEventListener('pointerdown', () => scoreHost.focus({ preventScroll: true }));
    scoreHost.addEventListener('pointerup', (event) => {
      const hit = window.NativeStudioCore.getCursor(project, event.clientX, event.clientY, cursor.stringIndex);
      if (hit) setCursor(hit);
    });
  }

  function placeCursor(beat, note) {
    if (!project || !window.NativeStudioCore) return;
    const trackIndex = Number(beat?.voice?.bar?.staff?.track?.index);
    const barIndex = Number(beat?.voice?.bar?.masterBar?.index);
    const beatIndex = Number(beat?.index);
    const stringCount = project.tracks[trackIndex]?.tuning?.length || 6;
    const stringIndex = note?.string ? stringCount + 1 - Number(note.string) : cursor.stringIndex;
    if (Number.isInteger(trackIndex) && Number.isInteger(barIndex) && Number.isInteger(beatIndex)) {
      cursor = { trackIndex, barIndex, beatIndex, stringIndex };
      send('cursor', { cursor });
    }
  }

  function draw(nextProject) {
    project = nextProject;
    const generation = ++renderGeneration;
    cancelPendingCanvasDraw('superseded');
    recordRenderTrace('drawReceived', {
      generation,
      hasApi: !!api,
      hasProject: !!project,
      hasCore: !!window.NativeStudioCore,
      barCount: Number(project?.bars?.length || 0),
      trackCount: Number(project?.tracks?.length || 0),
    });
    if (!api || !project || !window.NativeStudioCore) {
      recordRenderTrace('drawSkipped', {
        generation,
        reason: !api ? 'api_missing' : !project ? 'project_missing' : 'core_missing',
      });
      return null;
    }
    try {
      errorHost.hidden = true;
      const tex = window.NativeStudioCore.getAlphaTex(project);
      const tracks = project.tracks.map((_track, index) => index);
      recordRenderTrace('alphaTexGenerated', { generation, characterCount: String(tex).length });
      const scheduled = { generation, frameID: null, watchdogID: null };
      pendingCanvasDraw = scheduled;
      const run = (source) => {
        if (pendingCanvasDraw !== scheduled) {
          recordRenderTrace('drawCallbackSkipped', { generation, source, reason: 'already_cancelled_or_run' });
          return;
        }
        pendingCanvasDraw = null;
        if (scheduled.frameID !== null) window.cancelAnimationFrame(scheduled.frameID);
        if (scheduled.watchdogID !== null) window.clearTimeout(scheduled.watchdogID);
        if (disposed || generation !== renderGeneration || !api) {
          recordRenderTrace('drawCallbackSkipped', {
            generation,
            source,
            reason: disposed ? 'disposed' : generation !== renderGeneration ? 'superseded' : 'api_missing',
          });
          return;
        }
        recordRenderTrace('drawCallbackEntered', { generation, source });
        try {
          api.tex(tex, tracks);
          recordRenderTrace('apiTexReturned', {
            generation,
            source,
            hasScore: !!api?.score,
            trackCount: Number(api?.score?.tracks?.length || 0),
            barCount: Number(api?.score?.masterBars?.length || 0),
          });
        } catch (error) {
          recordRenderTrace('apiTexThrew', { generation, source, message: error instanceof Error ? error.message : String(error) });
          fail(error);
        }
      };
      scheduled.frameID = window.requestAnimationFrame(() => run('animationFrame'));
      // WebKit can suspend animation frames when the window is occluded. A single
      // short watchdog keeps initial project loading from depending on visibility.
      scheduled.watchdogID = window.setTimeout(() => run('watchdog'), 120);
      recordRenderTrace('drawFrameScheduled', {
        generation,
        frameID: Number(scheduled.frameID),
        watchdogDelayMs: 120,
      });
      return generation;
    } catch (error) { fail(error); }
    return null;
  }

  function cancelPendingCanvasDraw(reason) {
    const scheduled = pendingCanvasDraw;
    if (!scheduled) return;
    pendingCanvasDraw = null;
    if (scheduled.frameID !== null) window.cancelAnimationFrame(scheduled.frameID);
    if (scheduled.watchdogID !== null) window.clearTimeout(scheduled.watchdogID);
    recordRenderTrace('drawCancelled', { generation: scheduled.generation, reason });
  }

  function playing() { return !!(api?.player?.isPlaying ?? api?._player?.isPlaying); }

  function previewInstrument(track, requestedProgram, allowUkulelePalette = false) {
    const tuning = Array.isArray(track?.tuning) && track.tuning.length
      ? track.tuning
      : [64, 59, 55, 50, 45, 40];
    const hasRequestedProgram = Number.isInteger(requestedProgram);
    const program = hasRequestedProgram
      ? requestedProgram
      : Number.isInteger(track?.program) ? track.program : 25;
    const isUkulelePalette = allowUkulelePalette && !hasRequestedProgram
      && tuning.length === 4 && track?.program === 24;
    return {
      tuning,
      capo: Math.max(0, Math.min(24, Math.trunc(Number(track?.capo) || 0))),
      program,
      flavor: isUkulelePalette ? 'ukulele' : 'gm',
    };
  }

  function cancelGuitarPreview() {
    window.NativeGuitarAudio?.cancel?.();
  }

  function setCursor(next) {
    cursor = { ...cursor, ...next };
    send('cursor', { cursor });
  }

  function stepBeat(delta) {
    if (!project) return;
    const beats = project.bars[cursor.barIndex]?.trackBeats?.[project.tracks[cursor.trackIndex]?.id] || [];
    let nextBeat = cursor.beatIndex + delta;
    let nextBar = cursor.barIndex;
    if (nextBeat >= beats.length) {
      if (cursor.barIndex === project.bars.length - 1) send('shortcut', { action: 'insertBar', cursor });
      else { nextBar++; nextBeat = 0; }
    } else if (nextBeat < 0) {
      nextBar = Math.max(0, nextBar - 1);
      nextBeat = Math.max(0, (project.bars[nextBar]?.trackBeats?.[project.tracks[cursor.trackIndex]?.id] || []).length - 1);
    }
    setCursor({ barIndex: nextBar, beatIndex: nextBeat });
  }

  function sendAction(action, extra = {}) { send('shortcut', { action, cursor, ...extra }); }

  function handleKey(event) {
    if (disposed || !project || !scoreHost.contains(document.activeElement)) return;
    const key = event.key;
    const command = event.metaKey || event.ctrlKey;
    if (key === 'Tab') return; // Native focus traversal; never edit a note.
    if (command && key.toLowerCase() === 's') { event.preventDefault(); sendAction('save'); return; }
    if (command && key.toLowerCase() === 'z') { event.preventDefault(); sendAction(event.shiftKey ? 'redo' : 'undo'); return; }
    if (command && key.toLowerCase() === 'y') { event.preventDefault(); sendAction('redo'); return; }
    if (command) return;
    if (event.altKey && /^[1-6]$/.test(key)) { event.preventDefault(); sendAction('duration', { duration: [1, 2, 4, 8, 16, 32][Number(key) - 1] }); return; }
    if (key === 'ArrowUp' || key === 'ArrowDown') { event.preventDefault(); setCursor({ stringIndex: Math.max(1, Math.min(project.tracks[cursor.trackIndex]?.tuning?.length || 6, cursor.stringIndex + (key === 'ArrowUp' ? -1 : 1))) }); return; }
    if (key === 'ArrowLeft' || key === 'ArrowRight') { event.preventDefault(); stepBeat(key === 'ArrowRight' ? 1 : -1); return; }
    if (key === 'Delete' || key === 'Backspace') { event.preventDefault(); sendAction(event.shiftKey ? 'deleteBeat' : 'deleteNote'); return; }
    if (key === 'Insert') { event.preventDefault(); sendAction(event.shiftKey ? 'insertBeat' : 'insertBar'); return; }
    if (key === '.') { event.preventDefault(); sendAction('dot'); return; }
    if (key === '/') { event.preventDefault(); sendAction('triplet'); return; }
    const techniques = { l: 'tie', h: 'hammerPull', s: 'slide', b: 'bend', n: 'harmonic', p: 'palmMute', x: 'dead', v: 'vibrato' };
    if (key.toLowerCase() in techniques) { event.preventDefault(); sendAction('technique', { technique: techniques[key.toLowerCase()] }); return; }
    if (key.toLowerCase() === 'r') { event.preventDefault(); sendAction('rest'); return; }
    if (/^[0-9]$/.test(key)) {
      event.preventDefault();
      if (key === '0') { pendingDigit = ''; sendAction('fret', { fret: 0 }); return; }
      pendingDigit += key;
      window.clearTimeout(digitTimer);
      const number = Number(pendingDigit);
      if (pendingDigit.length === 2 && number <= 24) { pendingDigit = ''; sendAction('fret', { fret: number }); return; }
      digitTimer = window.setTimeout(() => { const fret = Number(pendingDigit); pendingDigit = ''; if (fret <= 9) sendAction('fret', { fret }); }, 450);
      return;
    }
    if (key === ' ') { event.preventDefault(); sendAction('playPause'); }
  }

  document.addEventListener('keydown', handleKey, true);
  window.NativeStudio = {
    setProject(value) {
      const generation = draw(value);
      return { accepted: generation !== null, generation };
    },
    setCursor(value) { setCursor(value); },
    async importBytes(base64, fileName, sourceId) {
      try {
        const bytes = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
        return JSON.stringify(await window.NativeStudioCore.importBytes(bytes, fileName, sourceId));
      } catch (error) {
        const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
        const stack = error instanceof Error && typeof error.stack === 'string' ? error.stack : '';
        return JSON.stringify({ __studioImportError: message, __studioImportStack: stack });
      }
    },
    async exportBytes(value, format) {
      const bytes = await window.NativeStudioCore.exportBytes(value, format);
      let binary = '';
      for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
      return btoa(binary);
    },
    async exportPdfPages(value) {
      if (!value || !window.NativeStudioCore?.exportPdfPages) throw new Error('谱面尚未载入，无法生成分页 PDF。');
      return JSON.stringify(await window.NativeStudioCore.exportPdfPages(value, value.artist || ''));
    },
    async exportPngData(value) {
      if (!value || !window.NativeStudioCore?.exportPngData) throw new Error('谱面尚未载入，无法生成长图。');
      return await window.NativeStudioCore.exportPngData(value);
    },
    previewNote(track, stringIndex, fret) {
      const audio = window.NativeGuitarAudio;
      if (typeof audio?.previewFret !== 'function') throw new Error('工坊试听音频引擎未加载。');
      const instrument = previewInstrument(track);
      const string = Math.max(1, Math.min(instrument.tuning.length, Math.trunc(Number(stringIndex) || 1)));
      const selectedFret = Math.max(0, Math.min(24, Math.trunc(Number(fret) || 0)));
      return audio.previewFret({ ...instrument, string, fret: selectedFret });
    },
    previewChord(track, notes, program) {
      const audio = window.NativeGuitarAudio;
      if (typeof audio?.previewChord !== 'function') throw new Error('工坊试听音频引擎未加载。');
      const instrument = previewInstrument(track, program, true);
      const normalizedNotes = (Array.isArray(notes) ? notes : []).slice(0, 16).map((note) => ({
        string: Math.max(1, Math.min(instrument.tuning.length, Math.trunc(Number(note.string) || 1))),
        fret: Math.max(0, Math.min(24, Math.trunc(Number(note.fret) || 0))),
      }));
      if (normalizedNotes.length === 0) throw new Error('试听和弦没有可播放音符。');
      const beat = project?.bars?.[cursor.barIndex]?.trackBeats?.[track?.id]?.[cursor.beatIndex];
      return audio.previewChord({
        ...instrument,
        notes: normalizedNotes,
        direction: beat?.brush === 'up' ? 'up' : 'down',
      });
    },
    playback(action) {
      cancelGuitarPreview();
      if (!api) return;
      if (action === 'play') api.play();
      else if (action === 'pause') api.pause();
      else if (action === 'stop') { api.pause(); api.tickPosition = 0; }
    },
    seek(barIndex, beatIndex) {
      const bounds = api?.renderer?.boundsLookup?.findMasterBarByIndex?.(barIndex);
      const beat = bounds?.bars?.flatMap((bar) => bar.beats || []).find((entry) => entry.beat?.index === beatIndex)?.beat;
      if (beat && api?.score) api.tickPosition = Number(beat.playbackStart || 0);
    },
    dispose() {
      cancelGuitarPreview();
      disposed = true;
      bootstrapGeneration++;
      renderGeneration++;
      cancelPendingCanvasDraw('disposed');
      if (alphaTabWorkerPreparationAbortController) alphaTabWorkerPreparationAbortController.abort();
      alphaTabWorkerPreparationAbortController = null;
      alphaTabWorkerPreparation = null;
      if (alphaTabWorkerBlobURL) URL.revokeObjectURL(alphaTabWorkerBlobURL);
      alphaTabWorkerBlobURL = null;
      workerFactoryInstalled = false;
      document.removeEventListener('keydown', handleKey, true);
      window.clearTimeout(digitTimer);
      try { api?.destroy(); } catch {}
      if (window.__studioApi === api) window.__studioApi = null;
      api = null;
    },
  };

  const currentBootstrap = ++bootstrapGeneration;
  prepareAlphaTabWorker().then(() => {
    if (disposed || currentBootstrap !== bootstrapGeneration) return;
    configureApi();
    if (project) draw(project);
    send('booted');
  }).catch((error) => {
    if (!disposed && currentBootstrap === bootstrapGeneration) fail(error);
  });
})();
