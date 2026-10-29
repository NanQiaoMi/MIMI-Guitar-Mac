export interface PracticeSeekReceipt { tick: number; timeMs: number }

/** Capture the time from the matching engine seek event, not a stale API getter. */
export function seekWithReceipt(options: {
  tick: number;
  isCurrent: () => boolean;
  subscribe: (listener: (position: { isSeek: boolean; currentTick: number; currentTime: number }) => void) => () => void;
  seek: () => void;
  signal?: AbortSignal | null;
  timeoutMs?: number;
}): Promise<PracticeSeekReceipt> {
  return new Promise((resolve, reject) => {
    if (!Number.isSafeInteger(options.tick) || options.tick < 0 || !options.isCurrent() || options.signal?.aborted) {
      reject(new Error('播放器已更新，位置跳转已取消。')); return;
    }
    let dispose = () => {};
    let settled = false;
    const cleanup = () => { dispose(); clearTimeout(timer); options.signal?.removeEventListener('abort', abort); };
    const fail = (message: string) => { if (settled) return; settled = true; cleanup(); reject(new Error(message)); };
    const abort = () => fail('播放器已更新，位置跳转已取消。');
    const timer = setTimeout(() => fail('位置跳转尚未得到引擎确认，请重试。'), options.timeoutMs ?? 2000);
    options.signal?.addEventListener('abort', abort, { once: true });
    try {
      dispose = options.subscribe((position) => {
        if (settled) return;
        if (!options.isCurrent()) { abort(); return; }
        if (!position.isSeek || !Number.isFinite(position.currentTick) || Math.abs(position.currentTick - options.tick) > 1
          || !Number.isFinite(position.currentTime) || position.currentTime < 0) return;
        settled = true;
        cleanup();
        resolve({ tick: options.tick, timeMs: position.currentTime });
      });
      if (options.signal?.aborted) abort();
      if (!settled) options.seek();
    } catch { fail('播放器未能完成位置跳转，请重试。'); }
  });
}
