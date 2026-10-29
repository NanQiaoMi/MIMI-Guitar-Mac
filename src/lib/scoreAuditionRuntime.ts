/** AlphaTab-backed runtime for explicit score audition requests. */

import {
  AlphaTabApi,
  Settings,
  PlayerMode,
  PlayerOutputMode,
  model,
} from '@coderline/alphatab';
import { decodeIbeToJsonBrowser } from './ibe.browser.ts';
import { installBrowserAr } from './ar.browser.ts';
import { claimAudioFocus } from './player/audioFocus.ts';
import {
  hasScoreAuditionNotes,
  hasScoreAuditionMelodicNotes,
  planScoreAuditionSoundfonts,
  resolveScoreAuditionSourceFlavor,
  resolveScoreAuditionSource,
} from './player/scoreAuditionResources.ts';
import {
  loadVerifiedScoreSoundfontPlan,
  type ScoreSoundfontRequest,
} from './player/verifiedScoreSoundfont.ts';
import { loadSoundfontWithReceipt } from './player/soundfontLoadReceipt.ts';
import {
  createSerialTaskQueue,
  createScorePlaybackReadyWaiter,
  startAlphaTabPlayback,
} from './player/scoreAuditionReadiness.ts';
import type { AuditionListener, AuditionState, ScoreAuditionRuntime as ScoreAuditionRuntimeContract } from './scoreAuditionTypes.ts';

function makeAbortError(): Error {
  if (typeof DOMException !== 'undefined') return new DOMException('Aborted', 'AbortError');
  const error = new Error('Aborted');
  error.name = 'AbortError';
  return error;
}

function awaitOrAbort<T>(operation: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(makeAbortError());
  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const cleanup = () => signal.removeEventListener('abort', onAbort);
    const finish = (callback: (value: any) => void, value: unknown) => {
      if (settled) return;
      settled = true;
      cleanup();
      callback(value);
    };
    const onAbort = () => finish(reject, makeAbortError());
    signal.addEventListener('abort', onAbort, { once: true });
    operation.then(
      (value) => finish(resolve, value),
      (error) => finish(reject, error),
    );
  });
}

export class ScoreAuditionRuntime implements ScoreAuditionRuntimeContract {
  private api: AlphaTabApi | null = null;
  private container: HTMLDivElement | null = null;
  private currentScore: any = null;
  private currentGeneration = 0;
  // AlphaTab's playerReady event carries no score identity. Serialize only the
  // synth setup/render/readiness segment so a cancelled score's late MIDI-ready
  // event cannot satisfy the next score's waiter.
  private synthSetupQueue = createSerialTaskQueue();
  private listeners = new Set<AuditionListener>();
  private abortController: AbortController | null = null;
  private audioFocusRelease: (() => void) | null = null;

  // Current AlphaTab payload plan and readiness state.
  private currentLoadedSoundfontKey: string | null = null;
  private isSoundfontReady = false;
  private soundfontLoadingPromise: { key: string; promise: Promise<void> } | null = null;

  private state: AuditionState = {
    currentTabId: null,
    currentTab: null,
    isPlaying: false,
    isLoading: false,
    currentTime: 0,
    endTime: 0,
    progress: 0,
    activeNotes: [],
    error: null,
  };

  public subscribe(listener: AuditionListener): () => void {
    this.listeners.add(listener);
    listener({ ...this.state });
    return () => {
      this.listeners.delete(listener);
    };
  }

  private notify() {
    const copy = { ...this.state, activeNotes: [...this.state.activeNotes] };
    for (const l of this.listeners) {
      try {
        l(copy);
      } catch (e) {
        console.error('[ScoreAuditionRuntime] listener error:', e);
      }
    }
  }

  private ensureHost(): HTMLDivElement {
    if (!this.container && typeof document !== 'undefined') {
      let el = document.getElementById('headless-score-audition-host') as HTMLDivElement;
      if (!el) {
        el = document.createElement('div');
        el.id = 'headless-score-audition-host';
        el.style.position = 'fixed';
        el.style.left = '-99999px';
        el.style.top = '0px';
        el.style.width = '800px';
        el.style.height = '600px';
        el.style.visibility = 'hidden';
        el.style.opacity = '0';
        el.style.pointerEvents = 'none';
        el.style.zIndex = '-9999';
        el.scrollIntoView = () => {};
        el.focus = () => {};
        document.body.appendChild(el);
      }
      this.container = el;
    }
    return this.container!;
  }

  private initApi(): AlphaTabApi {
    if (this.api) return this.api;
    const host = this.ensureHost();

    const s = new Settings();
    s.core.scriptFile = '/alphaTab.js';
    s.core.fontDirectory = '/font/';
    s.core.useWorkers = false;
    s.core.enableLazyLoading = false;

    // 关闭自动滚动与焦点捕获
    (s.core as any).autoScroll = 0;
    (s.player as any).scrollMode = 0;
    (s.player as any).scrollSpeed = 0;
    (s.player as any).scrollElement = null;

    s.player.enablePlayer = false;
    s.player.playerMode = PlayerMode.Disabled;
    s.player.outputMode = PlayerOutputMode.WebAudioScriptProcessor;
    s.player.bufferTimeInMilliseconds = 800;

    const api = new AlphaTabApi(host, s);
    this.api = api;

    // 覆盖底层 Web Worker 工厂：使用绝对路径运行时
    const facade = (api as any).uiFacade;
    if (facade?.constructor) {
      facade.constructor.createAlphaSynthWebWorker = function () {
        const code = `importScripts(location.origin + '/alphaTab.js');`;
        const blob = new Blob([code], { type: 'application/javascript' });
        return new Worker(URL.createObjectURL(blob));
      };
    }

    s.player.enablePlayer = true;
    s.player.playerMode = PlayerMode.EnabledSynthesizer;
    (api as any)._setupOrDestroyPlayer();

    // 事件绑定：播放状态变化
    api.playerStateChanged.on((args: any) => {
      if (this.api !== api) return;
      const isPlaying = args.state === 1; // 1 = playing
      this.state.isPlaying = isPlaying;
      if (isPlaying) {
        this.state.isLoading = false;
      } else {
        this.releaseAudioFocus();
        this.state.activeNotes = [];
      }
      this.notify();
    });

    // 实时播放进度变化
    api.playerPositionChanged.on((args: any) => {
      if (this.api !== api) return;
      if (args) {
        this.state.currentTime = args.currentTime ?? 0;
        this.state.endTime = args.endTime ?? this.state.endTime;
        this.state.progress = this.state.endTime > 0 ? this.state.currentTime / this.state.endTime : 0;
        this.notify();
      }
    });

    const updateActiveNotesFromBeat = (beat: any) => {
      if (!beat || !beat.notes || beat.notes.length === 0) return;
      const notes: Array<{ string: number; fret: number }> = [];
      for (const n of beat.notes) {
        if (n.string != null && n.fret != null && !n.isDead) {
          notes.push({ string: n.string, fret: n.fret });
        }
      }
      if (notes.length > 0) {
        this.state.activeNotes = notes;
        this.notify();
      }
    };

    if (api.playedBeatChanged) {
      api.playedBeatChanged.on((beat: any) => {
        if (this.api === api) updateActiveNotesFromBeat(beat);
      });
    }

    api.playerFinished.on(() => {
      if (this.api !== api) return;
      this.state.isPlaying = false;
      this.releaseAudioFocus();
      this.state.currentTime = 0;
      this.state.progress = 0;
      this.state.activeNotes = [];
      this.notify();
    });

    // 监听 soundFontLoaded 事件
    api.soundFontLoaded.on(() => {
      if (this.api !== api) return;
      console.log('[ScoreAuditionRuntime] SoundFont loaded & ready!');
      this.isSoundfontReady = true;
    });

    return api;
  }

  public async prewarm(): Promise<void> {
    if (typeof window === 'undefined') return;
    installBrowserAr();
    const api = this.initApi();
    await this.ensureSoundfontsLoaded(api, [{ bank: 0, program: 0, flavor: 'gm' }]);
  }

  private async ensureSoundfontsLoaded(
    api: AlphaTabApi,
    targetPresets: readonly ScoreSoundfontRequest[],
    signal?: AbortSignal,
  ): Promise<void> {
    const requests = [...new Map(targetPresets.map((request) => [
      `${request.flavor}:${request.bank}:${request.program}`,
      request,
    ])).values()];
    if (requests.length === 0) throw new Error('该曲谱没有可用的乐器音色');
    const key = requests.map(({ flavor, bank, program }) => `${flavor}:${bank}:${program}`).sort().join('|');
    if (this.currentLoadedSoundfontKey === key && this.isSoundfontReady) return;
    const activeLoad = this.soundfontLoadingPromise;
    if (activeLoad) {
      if (activeLoad.key === key) {
        return signal ? awaitOrAbort(activeLoad.promise, signal) : activeLoad.promise;
      }
      // A new track may need a different instrument bank. Let the current global
      // AlphaTab load finish, then request the selected bank. Caller cancellation
      // only stops waiting and does not cancel a load shared by another request.
      const queuedLoad = activeLoad.promise.catch(() => {}).then(() => this.ensureSoundfontsLoaded(api, requests));
      return signal ? awaitOrAbort(queuedLoad, signal) : queuedLoad;
    }

    const promise = (async () => {
      try {
        const soundfontFonts = await loadVerifiedScoreSoundfontPlan(requests);
        this.isSoundfontReady = false;
        this.currentLoadedSoundfontKey = null;

        for (let index = 0; index < soundfontFonts.length; index++) {
          const font = soundfontFonts[index];
          // Keep this shared plan alive if its initiating caller cancels. The
          // receipt helper serializes actual worker loads and consumes each
          // generic AlphaTab event before allowing the next request to start.
          const receipt = await loadSoundfontWithReceipt(api, font.bytes, index > 0);
          if (receipt.status === 'cancelled') throw makeAbortError();
          if (receipt.status !== 'loaded') {
            const error = receipt.error ?? new Error(`音色库加载${receipt.status === 'timeout' ? '超时' : '失败'}`);
            this.isSoundfontReady = false;
            this.currentLoadedSoundfontKey = null;
            // The helper poisons APIs whose worker receipt is unreliable; a
            // fresh AlphaTab instance is required before another plan can load.
            this.invalidateApi(api);
            throw error;
          }
        }
        this.isSoundfontReady = true;
        this.currentLoadedSoundfontKey = key;
      } catch (e: any) {
        console.warn('[ScoreAuditionRuntime] ensureSoundfontLoaded error:', e);
        this.isSoundfontReady = false;
        this.currentLoadedSoundfontKey = null;
        throw e;
      }
    })();
    const nextLoad = { key, promise };
    this.soundfontLoadingPromise = nextLoad;
    const clearActiveLoad = () => {
      if (this.soundfontLoadingPromise === nextLoad) this.soundfontLoadingPromise = null;
    };
    void promise.then(clearActiveLoad, clearActiveLoad);
    if (signal) await awaitOrAbort(promise, signal);
    else await promise;
  }

  public async togglePlayTab(tab: any): Promise<void> {
    if (!tab || !tab.id) return;

    if (this.state.currentTabId === tab.id) {
      if (this.state.isPlaying) {
        this.pause();
      } else {
        this.resume();
      }
      return;
    }

    // 播放新曲谱
    await this.playTab(tab);
  }

  public async playTab(tab: any): Promise<void> {
    if (typeof window === 'undefined') return;

    // 1. 立即中断上一曲正在进行的网络抓取与解码，消除快速切歌竞态
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }
    const abortController = new AbortController();
    this.abortController = abortController;
    const { signal } = abortController;

    const generation = ++this.currentGeneration;
    this.stopInternal();

    this.state.currentTabId = tab.id;
    this.state.currentTab = tab;
    this.state.isLoading = true;
    this.state.isPlaying = false;
    this.state.currentTime = 0;
    this.state.endTime = 0;
    this.state.progress = 0;
    this.state.activeNotes = [];
    this.state.error = null;
    this.currentScore = null;
    this.notify();

    try {
      installBrowserAr();
      let api = this.initApi();
      const source = resolveScoreAuditionSource(tab);
      if (!source.ok) {
        const reason = source.reason;
        const message = reason === 'unsupported-format'
          ? '该曲目目前只有 XHE 曲谱，无法进行音乐试听'
          : reason === 'score-id-mismatch'
            ? '曲谱资源与曲目编号不一致，已停止试听'
            : reason === 'unsafe-url'
              ? '该曲目的乐谱资源不是受支持的 IBE 文件'
              : '未找到该曲目的有效 IBE 乐谱文件';
        throw new Error(message);
      }

      const response = await fetch(source.url, { signal });
      if (!response.ok) {
        throw new Error(`谱面文件加载失败 (HTTP ${response.status}): ${source.url}`);
      }
      const scoreBytes = new Uint8Array(await response.arrayBuffer());

      if (signal.aborted || this.currentGeneration !== generation) return;

      // 解析乐谱 JSON
      const json = await decodeIbeToJsonBrowser(scoreBytes);
      if (signal.aborted || this.currentGeneration !== generation) return;

      // Keep the score's original track programs, volumes, and program-change
      // automations. AlphaTab synthesizes all tracks, even when only track zero
      // is selected for this hidden notation render.
      const sc = model.JsonConverter.jsonToScore(JSON.stringify(json), api.settings);
      if (!hasScoreAuditionNotes(sc?.tracks)) throw new Error('该曲谱没有可试听的音符');
      if (!hasScoreAuditionMelodicNotes(sc?.tracks)) {
        throw new Error('该曲谱仅有打击乐，没有旋律音符，暂不提供音乐试听');
      }
      for (const track of sc?.tracks ?? []) {
        (track as typeof track & { mimiSoundfontFlavor?: 'gm' | 'ukulele' }).mimiSoundfontFlavor =
          resolveScoreAuditionSourceFlavor(track, tab.category);
      }
      const soundfontPlan = planScoreAuditionSoundfonts(sc?.tracks);
      if (!soundfontPlan.ok) {
        throw new Error(`曲谱中的 bank ${soundfontPlan.bank} / GM ${soundfontPlan.program} 乐器需要互斥音色，无法准确混合试听`);
      }
      if (soundfontPlan.presets.length === 0) throw new Error('该曲谱没有可匹配的乐器音色');
      const readyApi = await this.prepareScoreAndWaitForReadiness(api, sc, soundfontPlan.presets, signal);
      if (!readyApi) return;
      api = readyApi;

      if (signal.aborted || this.currentGeneration !== generation) return;

      // Preserve the source track dynamics; only set the engine master to its
      // standard unity level.
      api.masterVolume = 1.0;
      const release = await claimAudioFocus('score-audition', () => this.handleAudioFocusLost(api));
      if (signal.aborted || this.currentGeneration !== generation || this.api !== api) {
        release();
        return;
      }
      this.audioFocusRelease?.();
      this.audioFocusRelease = release;
      await startAlphaTabPlayback(api, { signal });
      if (signal.aborted || this.currentGeneration !== generation || this.api !== api) return;
      if (!this.state.isPlaying) throw new Error('试听引擎未确认播放状态');

      this.state.isLoading = false;
      if (this.abortController === abortController) this.abortController = null;
      this.notify();
    } catch (err: any) {
      if (signal.aborted || err?.name === 'AbortError' || this.currentGeneration !== generation) {
        return;
      }
      console.error('[ScoreAuditionRuntime] playTab failed:', err);
      if (err?.name === 'PlaybackStartTimeoutError' && this.api) this.invalidateApi(this.api);
      this.state.isLoading = false;
      this.state.isPlaying = false;
      this.currentScore = null;
      this.releaseAudioFocus();
      this.state.activeNotes = [];
      this.state.error = err?.message || '试听播放失败';
      if (this.abortController === abortController) this.abortController = null;
      this.notify();
    }
  }

  private prepareScoreAndWaitForReadiness(
    api: AlphaTabApi,
    score: any,
    soundfontPresets: readonly ScoreSoundfontRequest[],
    signal: AbortSignal,
  ): Promise<AlphaTabApi | null> {
    const operation = this.synthSetupQueue.run(async () => {
      if (signal.aborted) return null;
      // A prior timeout can destroy the API while this request waits in the
      // render queue. Recreate it here, after the stale event source is gone.
      const activeApi = this.api === api ? api : this.initApi();
      await this.ensureSoundfontsLoaded(activeApi, soundfontPresets, signal);
      if (signal.aborted) return null;

      this.currentScore = score;
      const ready = createScorePlaybackReadyWaiter(activeApi);
      try {
        // Both readiness listeners are attached before renderScore. A fresh
        // scoreLoaded followed by AlphaTab's playerReady confirms this score's
        // MIDI and synth are ready, even when the previous song was already
        // ready before this request began.
        activeApi.renderScore(score, [0]);
      } catch (error) {
        ready.cancel(error);
        this.invalidateApi(activeApi);
      }
      try {
        await ready.promise;
      } catch (error: any) {
        if (error?.name === 'ScorePlaybackReadyTimeoutError') this.invalidateApi(activeApi);
        throw error;
      }
      return activeApi;
    });
    // The queued task retains its readiness wait after its caller cancels. The
    // eventual playerReady belongs to that render and must be consumed before
    // another score can render into the same AlphaTab instance.
    return awaitOrAbort(operation, signal);
  }

  private invalidateApi(api: AlphaTabApi): void {
    if (this.api !== api) return;
    this.api = null;
    this.currentScore = null;
    this.currentLoadedSoundfontKey = null;
    this.isSoundfontReady = false;
    this.releaseAudioFocus();
    try { api.stop(); } catch { /* the worker may already be stopping */ }
    try { api.destroy(); } catch { /* ensure a later request can construct a fresh engine */ }
  }

  public pause(): void {
    this.currentGeneration++;
    this.abortController?.abort();
    this.abortController = null;
    if (this.state.isLoading) {
      this.currentScore = null;
    }
    if (this.api && (this.state.isPlaying || this.state.isLoading)) {
      try { this.api.pause(); } catch { /* the player may already be stopping */ }
      this.state.isPlaying = false;
      this.state.isLoading = false;
      this.state.activeNotes = [];
      this.notify();
    }
    this.releaseAudioFocus();
  }

  public async resume(): Promise<void> {
    if (!this.currentScore && this.state.currentTab) {
      await this.playTab(this.state.currentTab);
      return;
    }
    const api = this.api;
    if (!api || this.state.isPlaying) return;
    this.abortController?.abort();
    const abortController = new AbortController();
    this.abortController = abortController;
    const generation = ++this.currentGeneration;
    this.state.isLoading = true;
    this.state.error = null;
    this.notify();
    let release: (() => void) | null = null;
    try {
      release = await claimAudioFocus('score-audition', () => this.handleAudioFocusLost(api));
      if (this.api !== api || this.currentGeneration !== generation || abortController.signal.aborted) {
        release();
        return;
      }
      this.audioFocusRelease?.();
      this.audioFocusRelease = release;
      await startAlphaTabPlayback(api, { signal: abortController.signal });
      if (this.api !== api || this.currentGeneration !== generation || abortController.signal.aborted) return;
      if (!this.state.isPlaying) throw new Error('试听引擎未确认播放状态');
      this.state.isLoading = false;
      if (this.abortController === abortController) this.abortController = null;
      this.notify();
    } catch (error) {
      if (this.currentGeneration !== generation || this.api !== api || abortController.signal.aborted) return;
      if ((error as Error)?.name === 'PlaybackStartTimeoutError') this.invalidateApi(api);
      if (this.audioFocusRelease === release) this.releaseAudioFocus();
      else release?.();
      this.state.isLoading = false;
      this.state.error = error instanceof Error ? error.message : '无法取得试听音频焦点';
      this.state.isPlaying = false;
      this.currentScore = null;
      if (this.abortController === abortController) this.abortController = null;
      this.notify();
    }
  }

  public stop(): void {
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }
    this.currentGeneration++;
    this.stopInternal();
    this.state.currentTabId = null;
    this.state.currentTab = null;
    this.state.endTime = 0;
    this.state.currentTime = 0;
    this.state.progress = 0;
    this.state.activeNotes = [];
    this.currentScore = null;
    this.notify();
  }

  private stopInternal(): void {
    this.releaseAudioFocus();
    if (this.api) {
      try {
        this.api.stop();
      } catch {}
    }
    this.state.isPlaying = false;
    this.state.isLoading = false;
    this.state.currentTime = 0;
    this.state.progress = 0;
    this.state.activeNotes = [];
  }

  private releaseAudioFocus(): void {
    this.audioFocusRelease?.();
    this.audioFocusRelease = null;
  }

  private handleAudioFocusLost(api: AlphaTabApi): void {
    if (this.api !== api) return;
    const startWasPending = this.state.isLoading;
    this.currentGeneration++;
    this.abortController?.abort();
    this.abortController = null;
    if (startWasPending) {
      // A play message may already be queued in AlphaSynth while its state
      // event is still pending. Destroy this engine so it cannot start audio
      // after another player has acquired the focus.
      this.invalidateApi(api);
    } else {
      try { api.pause(); } catch { /* the player may already have stopped */ }
    }
    this.audioFocusRelease = null;
    this.state.isPlaying = false;
    this.state.isLoading = false;
    this.state.activeNotes = [];
    this.notify();
  }

  public seek(ratio: number): void {
    if (!this.api || !Number.isFinite(this.api.endTick) || this.api.endTick <= 0) return;
    const targetTick = Math.max(0, Math.min(this.api.endTick, Math.floor(ratio * this.api.endTick)));
    this.api.tickPosition = targetTick;
  }

  public seekBySeconds(delta: number): void {
    if (!this.api || !Number.isFinite(this.api.endTick) || this.api.endTick <= 0 || !this.api.endTime) return;
    const targetTime = Math.max(0, Math.min(this.api.endTime, this.api.timePosition + delta * 1000));
    this.api.timePosition = targetTime;
  }

  public getState(): AuditionState {
    return { ...this.state, activeNotes: [...this.state.activeNotes] };
  }
}

export function createScoreAuditionRuntime(): ScoreAuditionRuntime {
  return new ScoreAuditionRuntime();
}
