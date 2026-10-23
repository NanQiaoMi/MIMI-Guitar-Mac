/**
 * alphaTab exposes generic SoundFont completion events without a request ID.
 * Keep exactly one real load in flight per API so a late event can never be
 * mistaken for the receipt of a later request.
 */

export type SoundfontLoadStatus = 'loaded' | 'cancelled' | 'failed' | 'timeout';

export type SoundfontLoadReceipt = {
  status: SoundfontLoadStatus;
  error?: Error;
};

export type SoundfontLoadApi = {
  soundFontLoaded: {
    on(listener: () => void): unknown;
    off(listener: () => void): unknown;
  };
  soundFontLoadFailed?: {
    on(listener: (error: Error) => void): unknown;
    off(listener: (error: Error) => void): unknown;
  };
  loadSoundFont(bytes: Uint8Array, append: boolean): boolean | void;
};

export type SoundfontLoadOptions = {
  signal?: AbortSignal;
  timeoutMs?: number;
};

type ApiQueue = {
  tail: Promise<void>;
  poisonedBy: Error | null;
};

const DEFAULT_TIMEOUT_MS = 15_000;
const apiQueues = new WeakMap<object, ApiQueue>();

function asError(value: unknown, fallback: string): Error {
  return value instanceof Error ? value : new Error(value == null ? fallback : String(value));
}

function getQueue(api: object): ApiQueue {
  let queue = apiQueues.get(api);
  if (!queue) {
    queue = { tail: Promise.resolve(), poisonedBy: null };
    apiQueues.set(api, queue);
  }
  return queue;
}

/** Whether this AlphaTab API must be destroyed before another load attempt. */
export function isSoundfontReceiptPoisoned(api: object): boolean {
  return !!apiQueues.get(api)?.poisonedBy;
}

function failed(error: Error): SoundfontLoadReceipt {
  return { status: 'failed', error };
}

/**
 * Load one soundfont and wait for its own generic AlphaTab acknowledgement.
 *
 * Caller cancellation is intentionally separate from the worker operation:
 * an active request continues to hold this API's queue until its matching
 * loaded/failed event arrives. A timeout or worker failure poisons the API so
 * later requests cannot attach a listener that a stale event could satisfy.
 * A poisoned API must be destroyed and replaced by its owner.
 */
export function loadSoundfontWithReceipt(
  api: SoundfontLoadApi,
  bytes: Uint8Array,
  append: boolean,
  options: SoundfontLoadOptions = {},
): Promise<SoundfontLoadReceipt> {
  const signal = options.signal;
  if (signal?.aborted) return Promise.resolve({ status: 'cancelled' });
  if (!api || (typeof api !== 'object' && typeof api !== 'function')) {
    return Promise.resolve(failed(new TypeError('AlphaTab API is unavailable')));
  }
  if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0) {
    return Promise.resolve(failed(new TypeError('SoundFont bytes are empty or invalid')));
  }

  const queue = getQueue(api as object);
  if (queue.poisonedBy) {
    return Promise.resolve(failed(new Error(`AlphaTab SoundFont API is poisoned: ${queue.poisonedBy.message}`)));
  }

  let resolveCaller!: (receipt: SoundfontLoadReceipt) => void;
  let callerSettled = false;
  const callerResult = new Promise<SoundfontLoadReceipt>((resolve) => {
    resolveCaller = resolve;
  });
  const finishCaller = (receipt: SoundfontLoadReceipt) => {
    if (callerSettled) return;
    callerSettled = true;
    signal?.removeEventListener('abort', onCallerAbort);
    resolveCaller(receipt);
  };
  const onCallerAbort = () => finishCaller({ status: 'cancelled' });
  signal?.addEventListener('abort', onCallerAbort, { once: true });
  if (signal?.aborted) {
    onCallerAbort();
  }

  const timeoutMs = Number.isFinite(options.timeoutMs) && Number(options.timeoutMs) >= 0
    ? Number(options.timeoutMs)
    : DEFAULT_TIMEOUT_MS;

  const operation = queue.tail.then(async () => {
    // A queued caller can cancel before dispatch and must not start a worker load.
    if (signal?.aborted) {
      finishCaller({ status: 'cancelled' });
      return;
    }
    if (queue.poisonedBy) {
      finishCaller(failed(new Error(`AlphaTab SoundFont API is poisoned: ${queue.poisonedBy.message}`)));
      return;
    }

    const receipt = await new Promise<SoundfontLoadReceipt>((resolve) => {
      let settled = false;
      let loadedListenerAttached = false;
      let failedListenerAttached = false;
      let timer: ReturnType<typeof setTimeout> | undefined;

      const cleanup = () => {
        if (timer !== undefined) clearTimeout(timer);
        try {
          if (loadedListenerAttached) api.soundFontLoaded.off(onLoaded);
        } catch { /* do not strand the per-API barrier if a host event emitter throws */ }
        try {
          if (failedListenerAttached) api.soundFontLoadFailed?.off(onFailed);
        } catch { /* the receipt is already settled; continue queue cleanup */ }
      };
      const settle = (result: SoundfontLoadReceipt) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(result);
      };
      const onLoaded = () => settle({ status: 'loaded' });
      const onFailed = (error: Error) => settle(failed(asError(error, 'AlphaTab failed to load the SoundFont')));

      try {
        api.soundFontLoaded.on(onLoaded);
        loadedListenerAttached = true;
        if (api.soundFontLoadFailed) {
          api.soundFontLoadFailed.on(onFailed);
          failedListenerAttached = true;
        }
        timer = setTimeout(() => settle({
          status: 'timeout',
          error: new Error(`AlphaTab SoundFont load timed out after ${timeoutMs}ms`),
        }), timeoutMs);

        let accepted: boolean | void;
        try {
          accepted = api.loadSoundFont(bytes, append);
        } catch (error) {
          settle(failed(asError(error, 'AlphaTab rejected the SoundFont load')));
          return;
        }
        if (accepted === false) {
          settle(failed(new Error('AlphaTab did not accept the SoundFont load')));
        }
      } catch (error) {
        settle(failed(asError(error, 'Could not subscribe to AlphaTab SoundFont events')));
      }
    });

    if (receipt.status === 'failed' || receipt.status === 'timeout') {
      queue.poisonedBy = receipt.error ?? new Error(`AlphaTab SoundFont load ${receipt.status}`);
    }
    finishCaller(receipt);
  });

  // Keep the per-API barrier alive until the dispatched worker request itself
  // has a receipt, even if the caller-facing promise has already been aborted.
  queue.tail = operation.then(() => undefined, (error) => {
    const cause = asError(error, 'Unexpected AlphaTab SoundFont queue failure');
    queue.poisonedBy = cause;
    finishCaller(failed(cause));
  });

  return callerResult;
}
