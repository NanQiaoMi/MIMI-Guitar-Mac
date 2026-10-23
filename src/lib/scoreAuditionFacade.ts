import { createRetryableLazyLoader } from './player/retryableLazyLoader.ts';
import { DEFAULT_SCORE_PREVIEW_SECONDS, normalizeScorePreviewSeconds } from './player/scorePreviewDuration.ts';
import type {
  AuditionListener,
  AuditionState,
  ScoreAuditionPreviewHandle,
  ScoreAuditionPreviewStartResult,
  ScoreAuditionRuntime,
} from './scoreAuditionTypes.ts';

type PreviewTimer = ReturnType<typeof setTimeout>;
type TimerDriver = Pick<typeof globalThis, 'setTimeout' | 'clearTimeout'>;

interface ActivePreview {
  ticket: number;
  tabId: string;
  timer: PreviewTimer | null;
  settle(result: ScoreAuditionPreviewStartResult): void;
}

const EMPTY_STATE: AuditionState = {
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

function copyState(state: AuditionState): AuditionState {
  return { ...state, activeNotes: [...state.activeNotes] };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error || '试听模块加载失败');
}

export function createScoreAuditionFacade(
  loadRuntime: () => Promise<ScoreAuditionRuntime>,
  pageTarget: Pick<Window, 'addEventListener' | 'removeEventListener'> | null =
    typeof window === 'undefined' ? null : window,
  timers: TimerDriver = globalThis,
) {
  const getRuntime = createRetryableLazyLoader(loadRuntime);
  const listeners = new Set<AuditionListener>();
  let state = copyState(EMPTY_STATE);
  let intent = 0;
  let disposed = false;
  let runtime: ScoreAuditionRuntime | null = null;
  let unsubscribeRuntime: (() => void) | null = null;
  let activePreview: ActivePreview | null = null;

  function clearActivePreview(): ActivePreview | null {
    const previous = activePreview;
    activePreview = null;
    if (previous?.timer !== null && previous?.timer !== undefined) {
      timers.clearTimeout(previous.timer);
      previous.timer = null;
    }
    previous?.settle({ status: 'cancelled' });
    return previous;
  }

  function pausePreview(preview: ActivePreview, result: ScoreAuditionPreviewStartResult) {
    if (activePreview !== preview || preview.ticket !== intent) return;
    clearActivePreview();
    ++intent;

    if (runtime) {
      const before = runtime.getState();
      if (before.currentTabId === preview.tabId && (before.isLoading || before.isPlaying)) {
        runtime.pause();
        // Return a completed short preview to its start so the next explicit
        // audition begins at the same musical phrase instead of resuming mid-bar.
        runtime.seek(0);
      }
      const after = runtime.getState();
      if (after.currentTabId === preview.tabId) {
        setState({ ...after, isLoading: false, isPlaying: false, activeNotes: [] });
      } else {
        setState({ ...state, isLoading: false, isPlaying: false, activeNotes: [] });
      }
    } else {
      setState({ ...state, isLoading: false, isPlaying: false, activeNotes: [] });
    }
    preview.settle(result);
  }

  function invalidatePreview() {
    clearActivePreview();
  }

  function notify() {
    const snapshot = copyState(state);
    for (const listener of listeners) {
      try { listener(snapshot); } catch (error) { console.error('[ScoreAuditionFacade] listener error:', error); }
    }
  }

  function setState(next: AuditionState) {
    state = copyState(next);
    notify();
  }

  function setError(error: unknown) {
    setState({ ...state, isLoading: false, isPlaying: false, activeNotes: [], error: errorMessage(error) });
  }

  function connect(nextRuntime: ScoreAuditionRuntime) {
    if (runtime === nextRuntime) return;
    unsubscribeRuntime?.();
    runtime = nextRuntime;
    let ignoreInitialSnapshot = true;
    unsubscribeRuntime = nextRuntime.subscribe((next) => {
      if (ignoreInitialSnapshot) {
        ignoreInitialSnapshot = false;
        return;
      }
      // The facade owns user intent. Runtime notifications are accepted only from
      // the shared current engine, never from an obsolete lazy-load continuation.
      if (runtime !== nextRuntime) return;
      // AlphaTab can emit the previous score's stop event while a new score is
      // being installed. Do not let that event roll the user-visible selection back.
      if (next.currentTabId !== state.currentTabId) return;
      // Natural completion or focus loss ends this preview as well. A stale
      // timer must not retain ownership after the runtime has already stopped.
      if (activePreview?.timer != null && !next.isPlaying && !next.isLoading) {
        clearActivePreview();
      }
      setState(next);
    });
  }

  function syncRuntime(nextRuntime: ScoreAuditionRuntime) {
    if (runtime === nextRuntime) setState(nextRuntime.getState());
  }

  async function playTab(tab: any): Promise<void> {
    if (disposed || !tab?.id) return;
    invalidatePreview();
    const ticket = ++intent;
    setState({
      ...state,
      currentTabId: tab.id,
      currentTab: tab,
      isPlaying: false,
      isLoading: true,
      currentTime: 0,
      endTime: 0,
      progress: 0,
      activeNotes: [],
      error: null,
    });

    try {
      const loadedRuntime = await getRuntime();
      if (ticket !== intent) return;
      connect(loadedRuntime);
      await loadedRuntime.playTab(tab);
      if (ticket === intent) syncRuntime(loadedRuntime);
    } catch (error) {
      if (ticket === intent) setError(error);
    }
  }

  async function togglePlayTab(tab: any): Promise<void> {
    if (!tab?.id) return;
    if (state.currentTabId === tab.id) {
      if (state.isLoading || state.isPlaying) pause();
      else await resume();
      return;
    }
    await playTab(tab);
  }

  function previewTab(tab: any, durationSeconds: number = DEFAULT_SCORE_PREVIEW_SECONDS): ScoreAuditionPreviewHandle {
    if (disposed || !tab?.id) {
      return {
        promise: Promise.resolve({ status: 'failed', error: '没有可试听的曲谱' }),
        cancel() {},
      };
    }

    invalidatePreview();
    const ticket = ++intent;
    const tabId = String(tab.id);
    const durationMs = normalizeScorePreviewSeconds(durationSeconds) * 1000;
    let settlePromise!: (result: ScoreAuditionPreviewStartResult) => void;
    let hasSettled = false;
    const promise = new Promise<ScoreAuditionPreviewStartResult>((resolve) => {
      settlePromise = resolve;
    });
    const settle = (result: ScoreAuditionPreviewStartResult) => {
      if (hasSettled) return;
      hasSettled = true;
      settlePromise(result);
    };
    const preview: ActivePreview = { ticket, tabId, timer: null, settle };
    activePreview = preview;

    setState({
      ...state,
      currentTabId: tabId,
      currentTab: tab,
      isPlaying: false,
      isLoading: true,
      currentTime: 0,
      endTime: 0,
      progress: 0,
      activeNotes: [],
      error: null,
    });

    void (async () => {
      try {
        const loadedRuntime = await getRuntime();
        if (disposed || ticket !== intent || activePreview !== preview) {
          settle({ status: 'cancelled' });
          return;
        }
        connect(loadedRuntime);
        await loadedRuntime.playTab(tab);
        if (disposed || ticket !== intent || activePreview !== preview) {
          settle({ status: 'cancelled' });
          return;
        }
        syncRuntime(loadedRuntime);
        const runtimeState = loadedRuntime.getState();
        if (runtimeState.currentTabId !== tabId || !runtimeState.isPlaying) {
          activePreview = null;
          settle(runtimeState.error
            ? { status: 'failed', error: runtimeState.error }
            : { status: 'cancelled' });
          return;
        }

        // Loading and soundfont preparation do not consume preview time.
        preview.timer = timers.setTimeout(() => {
          preview.timer = null;
          pausePreview(preview, { status: 'started' });
        }, durationMs);
        settle({ status: 'started' });
      } catch (error) {
        if (ticket !== intent || activePreview !== preview) {
          settle({ status: 'cancelled' });
          return;
        }
        activePreview = null;
        const message = errorMessage(error);
        setError(error);
        settle({ status: 'failed', error: message });
      }
    })();

    return {
      promise,
      cancel() {
        pausePreview(preview, { status: 'cancelled' });
      },
    };
  }

  function pause() {
    if (disposed) return;
    invalidatePreview();
    ++intent;
    state = { ...state, isLoading: false, isPlaying: false, activeNotes: [] };
    if (runtime) {
      runtime.pause();
      state = copyState(runtime.getState());
      // Some runtimes only publish when there was active audio. Keep cancellation
      // authoritative even when pause interrupted a pending load.
      state.isLoading = false;
      state.isPlaying = false;
    }
    notify();
  }

  async function resume(): Promise<void> {
    if (disposed) return;
    if (state.isPlaying || state.isLoading) return;
    invalidatePreview();
    const tab = state.currentTab;
    if (!tab) return;
    const ticket = ++intent;
    setState({ ...state, error: null });
    try {
      const loadedRuntime = await getRuntime();
      if (ticket !== intent) return;
      connect(loadedRuntime);
      const runtimeState = loadedRuntime.getState();
      if (runtimeState.currentTabId !== tab.id || !runtimeState.currentTab) {
        await loadedRuntime.playTab(tab);
      } else {
        await loadedRuntime.resume();
      }
      if (ticket === intent) syncRuntime(loadedRuntime);
    } catch (error) {
      if (ticket === intent) setError(error);
    }
  }

  function stop() {
    if (disposed) return;
    invalidatePreview();
    ++intent;
    if (runtime) runtime.stop();
    setState(copyState(EMPTY_STATE));
  }

  function pagehide() {
    if (disposed) return;
    invalidatePreview();
    ++intent;
    if (runtime) {
      runtime.pause();
      state = copyState(runtime.getState());
      state.isLoading = false;
      state.isPlaying = false;
      state.activeNotes = [];
    } else {
      state = { ...state, isLoading: false, isPlaying: false, activeNotes: [] };
    }
    notify();
  }

  if (pageTarget) pageTarget.addEventListener('pagehide', pagehide);

  async function prewarm(): Promise<void> {
    if (disposed) return;
    const ticket = intent;
    try {
      const loadedRuntime = await getRuntime();
      if (disposed || ticket !== intent) return;
      connect(loadedRuntime);
      await loadedRuntime.prewarm();
    } catch (error) {
      if (!disposed && ticket === intent) setError(error);
    }
  }

  return {
    getState: () => copyState(state),
    subscribe(listener: AuditionListener) {
      listeners.add(listener);
      listener(copyState(state));
      return () => listeners.delete(listener);
    },
    togglePlayTab,
    previewTab,
    playTab,
    pause,
    resume,
    stop,
    prewarm,
    seek(ratio: number) { runtime?.seek(ratio); },
    seekBySeconds(delta: number) { runtime?.seekBySeconds(delta); },
    dispose() {
      if (disposed) return;
      disposed = true;
      invalidatePreview();
      ++intent;
      runtime?.stop();
      setState(copyState(EMPTY_STATE));
      if (pageTarget) pageTarget.removeEventListener('pagehide', pagehide);
      unsubscribeRuntime?.();
      runtime = null;
      unsubscribeRuntime = null;
      listeners.clear();
    },
  };
}
