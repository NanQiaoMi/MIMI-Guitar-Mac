import type { AlphaTabApi } from '@coderline/alphatab';

type ScorePlaybackApi = Pick<
  AlphaTabApi,
  'scoreLoaded' | 'playerReady' | 'isReadyForPlayback' | 'playerState' | 'playerStateChanged' | 'play'
>;

export const SCORE_PLAYBACK_READY_TIMEOUT_MS = 30_000;
export const SCORE_PLAYBACK_START_TIMEOUT_MS = 5_000;
const PLAYING_STATE = 1;

/** Serialize score/synth setup without letting one rejection poison later work. */
export function createSerialTaskQueue() {
  let tail: Promise<void> = Promise.resolve();
  return {
    run<T>(task: () => T | Promise<T>): Promise<T> {
      const current = tail.then(task, task);
      tail = current.then(() => {}, () => {});
      return current;
    },
  };
}

function makeAbortError(): Error {
  if (typeof DOMException !== 'undefined') return new DOMException('Aborted', 'AbortError');
  const error = new Error('Aborted');
  error.name = 'AbortError';
  return error;
}

function namedError(name: string, message: string): Error {
  const error = new Error(message);
  error.name = name;
  return error;
}

export interface ScorePlaybackReadyWaiter {
  promise: Promise<void>;
  cancel(reason?: unknown): void;
}

/**
 * Wait for a fresh scoreLoaded event followed by AlphaTab's documented
 * playerReady event. The caller must create this waiter before renderScore().
 * Existing isReadyForPlayback state is deliberately ignored because it can
 * still describe the previously loaded song while the next score is queued.
 */
export function createScorePlaybackReadyWaiter(
  api: Pick<ScorePlaybackApi, 'scoreLoaded' | 'playerReady' | 'isReadyForPlayback'>,
  options: { timeoutMs?: number } = {},
): ScorePlaybackReadyWaiter {
  const timeoutMs = Math.max(1, options.timeoutMs ?? SCORE_PLAYBACK_READY_TIMEOUT_MS);
  let settled = false;
  let sawCurrentScore = false;
  let sawCurrentPlayerReady = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let resolvePromise!: () => void;
  let rejectPromise!: (error: unknown) => void;

  const promise = new Promise<void>((resolve, reject) => {
    resolvePromise = resolve;
    rejectPromise = reject;
  });

  const cleanup = () => {
    if (timer !== undefined) clearTimeout(timer);
    api.scoreLoaded.off(onScoreLoaded);
    api.playerReady.off(onPlayerReady);
  };

  const finish = (error?: unknown) => {
    if (settled) return;
    settled = true;
    cleanup();
    if (error !== undefined) rejectPromise(error);
    else resolvePromise();
  };

  const onScoreLoaded = () => {
    sawCurrentScore = true;
  };
  const onPlayerReady = () => {
    // A delayed readiness event from a superseded render must not satisfy this
    // waiter before this request's own scoreLoaded notification.
    if (sawCurrentScore && api.isReadyForPlayback === true) sawCurrentPlayerReady = true;
    if (sawCurrentScore && sawCurrentPlayerReady) finish();
  };

  api.scoreLoaded.on(onScoreLoaded);
  api.playerReady.on(onPlayerReady);
  timer = setTimeout(() => {
    finish(namedError('ScorePlaybackReadyTimeoutError', '乐谱试听引擎就绪超时'));
  }, timeoutMs);

  return {
    promise,
    cancel(reason = makeAbortError()) {
      finish(reason);
    },
  };
}

/** Start the loaded score and resolve only after AlphaTab reports Playing. */
export async function startAlphaTabPlayback(
  api: Pick<ScorePlaybackApi, 'isReadyForPlayback' | 'playerState' | 'playerStateChanged' | 'play'>,
  options: { signal?: AbortSignal; timeoutMs?: number } = {},
): Promise<void> {
  const { signal } = options;
  if (signal?.aborted) throw makeAbortError();
  if (api.isReadyForPlayback !== true) {
    throw new Error('乐谱试听引擎尚未就绪');
  }

  const timeoutMs = Math.max(1, options.timeoutMs ?? SCORE_PLAYBACK_START_TIMEOUT_MS);
  await new Promise<void>((resolve, reject) => {
    let settled = false;
    let sawPlaying = false;
    let playAccepted = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const cleanup = () => {
      if (timer !== undefined) clearTimeout(timer);
      api.playerStateChanged.off(onPlayerStateChanged);
      signal?.removeEventListener('abort', onAbort);
    };

    const finish = (error?: unknown) => {
      if (settled) return;
      settled = true;
      cleanup();
      if (error !== undefined) reject(error);
      else resolve();
    };

    const maybeResolve = () => {
      if (playAccepted && sawPlaying) finish();
    };

    const onPlayerStateChanged = (args: { state?: number } | undefined) => {
      if (args?.state === PLAYING_STATE || api.playerState === PLAYING_STATE) {
        sawPlaying = true;
        maybeResolve();
      }
    };
    const onAbort = () => finish(makeAbortError());

    api.playerStateChanged.on(onPlayerStateChanged);
    signal?.addEventListener('abort', onAbort, { once: true });
    timer = setTimeout(() => {
      finish(namedError('PlaybackStartTimeoutError', '试听引擎未确认已开始播放'));
    }, timeoutMs);

    try {
      playAccepted = api.play() !== false;
      if (!playAccepted) {
        finish(new Error('试听引擎未能开始播放'));
        return;
      }
      if (api.playerState === PLAYING_STATE) sawPlaying = true;
      maybeResolve();
    } catch (error) {
      finish(error);
    }
  });
}
