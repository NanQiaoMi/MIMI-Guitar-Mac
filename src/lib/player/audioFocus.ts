type FocusLossHandler = (reason: 'superseded' | 'remote') => void;

interface FocusMessage {
  ownerId: string;
  kind: 'claim' | 'release';
  tabId: string;
}

const tabId = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `tab-${Date.now()}-${Math.random()}`;
let localOwner: { id: string; token: string; onLost: FocusLossHandler; releaseLock: (() => void) | null; lockDone: Promise<void> } | null = null;
let claimGeneration = 0;
let channel: BroadcastChannel | null = null;
const remoteClaims = new Map<string, string>();

function getChannel(): BroadcastChannel | null {
  if (typeof window === 'undefined' || typeof BroadcastChannel === 'undefined') return null;
  if (!channel) {
    channel = new BroadcastChannel('mimi-audio-focus-v1');
    channel.addEventListener('message', (event: MessageEvent<FocusMessage>) => {
      const message = event.data;
      if (!message || message.tabId === tabId || typeof message.ownerId !== 'string') return;
      if (message.kind === 'claim') {
        remoteClaims.set(message.tabId, message.ownerId);
        if (localOwner) {
          const previous = localOwner;
          // Invalidate claims waiting behind a local handoff as well as the current holder.
          claimGeneration++;
          localOwner = null;
          previous.releaseLock?.();
          previous.onLost('remote');
        }
      } else {
        remoteClaims.delete(message.tabId);
      }
    });
  }
  return channel;
}

/** Claim the single audible-player slot for this tab and origin. A new claim pauses the previous owner. */
export async function claimAudioFocus(ownerId: string, onLost: FocusLossHandler): Promise<() => void> {
  if (typeof window === 'undefined') throw new Error('音频焦点只能在浏览器中获取');
  if (!ownerId.trim()) throw new Error('Audio focus ownerId must not be empty');
  if (!navigator.locks?.request) throw new Error('当前浏览器不支持安全的跨标签音频焦点锁定');
  const generation = ++claimGeneration;
  const previous = localOwner;
  if (previous) {
    localOwner = null;
    previous.releaseLock?.();
    previous.onLost('superseded');
    await previous.lockDone;
  }
  if (generation !== claimGeneration) throw new Error('音频焦点申请已被更新');
  const token = crypto.randomUUID();
  localOwner = { id: ownerId, token, onLost, releaseLock: null, lockDone: Promise.resolve() };
  getChannel()?.postMessage({ ownerId, kind: 'claim', tabId } satisfies FocusMessage);

  let releaseHold: (() => void) | null = null;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(new Error('音频焦点交接超时')), 2000);
  const acquired = new Promise<void>((resolve, reject) => {
    const request = navigator.locks.request('mimi-audio-focus-v1', { mode: 'exclusive', signal: controller.signal }, async (lock) => {
      if (localOwner?.token !== token) { reject(new Error('音频焦点申请已被更新')); return; }
      localOwner.releaseLock = () => releaseHold?.();
      resolve();
      await new Promise<void>((release) => { releaseHold = release; });
    });
    if (localOwner?.token === token) localOwner.lockDone = request.then(() => undefined, () => undefined);
    void request.catch(reject);
  });
  try {
    await acquired;
  } catch (error) {
    if (localOwner?.token === token) localOwner = null;
    throw controller.signal.aborted ? new Error('音频焦点交接超时或已取消') : error;
  } finally {
    clearTimeout(timeout);
  }

  let released = false;
  return () => {
    if (released) return;
    released = true;
    if (localOwner?.token !== token) return;
    localOwner = null;
    releaseHold?.();
    getChannel()?.postMessage({ ownerId, kind: 'release', tabId } satisfies FocusMessage);
  };
}

export function hasAudioFocus(ownerId: string): boolean {
  return localOwner?.id === ownerId && localOwner.releaseLock !== null;
}

export function closeAudioFocusChannelForTests(): void {
  claimGeneration++;
  localOwner?.releaseLock?.();
  channel?.close();
  channel = null;
  localOwner = null;
  remoteClaims.clear();
}
