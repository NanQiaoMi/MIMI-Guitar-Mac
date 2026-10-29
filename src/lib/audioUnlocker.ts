/**
 * Global Mobile Audio Unlocker & AudioContext Registry
 * Resolves Web Audio autoplay restrictions and silent freezes on iOS Safari,
 * iPadOS, Android, and WeChat in-app browsers.
 */

const activeAudioContexts = new Set<AudioContext>();
let hasUnlocked = false;
let isInitialized = false;
let globalPrewarmContext: AudioContext | null = null;

const INTERACTION_EVENTS = ['touchstart', 'touchend', 'pointerdown', 'click', 'keydown'] as const;

export interface ResumableAudioContext {
  readonly state: AudioContextState;
  resume(): Promise<void>;
}

/** Small injectable registry keeps context registration idempotent and resume failures contained. */
export function createAudioContextRegistry() {
  const contexts = new Set<ResumableAudioContext>();
  const unlocking = new WeakSet<ResumableAudioContext>();
  let unlocked = false;

  const resume = (ctx: ResumableAudioContext): void => {
    if (ctx.state !== 'suspended') return;
    if (unlocking.has(ctx)) return;
    // Guard each context before calling resume, which may synchronously re-enter.
    // Other contexts must still resume within the same user-gesture stack.
    unlocking.add(ctx);
    try {
      void Promise.resolve(ctx.resume()).catch(() => {}).finally(() => {
        unlocking.delete(ctx);
      });
    } catch {
      unlocking.delete(ctx);
    }
  };

  return {
    register(ctx: ResumableAudioContext): () => void {
      const alreadyRegistered = contexts.has(ctx);
      contexts.add(ctx);
      if (unlocked && !alreadyRegistered && !unlocking.has(ctx)) {
        resume(ctx);
      }
      return () => { contexts.delete(ctx); };
    },
    unlock(ctx: ResumableAudioContext): void {
      if (unlocking.has(ctx)) return;
      contexts.add(ctx);
      resume(ctx);
    },
    unlockAll(): void {
      unlocked = true;
      for (const ctx of contexts) {
        if (!unlocking.has(ctx)) {
          resume(ctx);
        }
      }
    },
    get size(): number { return contexts.size; },
  };
}

const contextRegistry = createAudioContextRegistry();

/**
 * Detects if the current device is running iOS (iPhone, iPad, iPod, WKWebView in WeChat,
 * or iPadOS in desktop Safari mode).
 */
export function isIosDevice(): boolean {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent || '';
  const isIos = /iPhone|iPad|iPod/i.test(ua);
  const isMacWithTouch =
    /Macintosh/i.test(ua) &&
    typeof navigator.maxTouchPoints === 'number' &&
    navigator.maxTouchPoints > 1;
  return isIos || isMacWithTouch;
}

/**
 * Plays a 1ms silent buffer to pre-warm and unlock the AudioContext immediately
 * without producing audible noise.
 */
function playSilentBuffer(ctx: AudioContext) {
  try {
    if (ctx.state === 'closed') return;
    const buf = ctx.createBuffer(1, 1, 22050);
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.connect(ctx.destination);
    src.start(0);
    src.onended = () => {
      try {
        src.disconnect();
      } catch {}
    };
  } catch (e) {
    // Some browsers or restrictive policies might throw, safely catch
  }
}

/**
 * Immediately unlocks a given AudioContext synchronously and asynchronously:
 * - Triggers synchronous ctx.resume() within user gesture handler stack
 * - Plays 1ms silent buffer to activate hardware audio pipe
 * - Registers ctx into the tracked set
 */
export function unlockAudioContextImmediately(ctx: AudioContext): Promise<void> {
  if (!ctx || ctx.state === 'closed') return Promise.resolve();

  contextRegistry.unlock(ctx);

  // Play silent buffer to activate output node
  playSilentBuffer(ctx);

  return Promise.resolve();
}

/**
 * Registers an AudioContext instance to be tracked and automatically resumed
 * upon user interaction, page visibility change, pageshow, and window focus.
 */
export function registerAudioContext(ctx: AudioContext): () => void {
  if (!ctx) return () => {};
  activeAudioContexts.add(ctx);
  const unregister = contextRegistry.register(ctx);
  return () => { activeAudioContexts.delete(ctx); unregister(); };
}

/**
 * Resumes all active tracked AudioContexts when returning from background
 */
function resumeAllContexts() {
  if (typeof document !== 'undefined' && document.hidden) return;

  for (const ctx of activeAudioContexts) {
    if (ctx.state === 'closed') {
      activeAudioContexts.delete(ctx);
      continue;
    }
    if (ctx.state === 'suspended') {
      contextRegistry.unlock(ctx);
    }
  }
}

/**
 * Global first-interaction handler
 */
function handleFirstInteraction(_event: Event) {
  if (hasUnlocked) return;
  hasUnlocked = true;
  contextRegistry.unlockAll();

  // Remove one-time interaction listeners
  removeInteractionListeners();

  // Create or pre-warm global context to establish hardware audio session permission
  try {
    if (!globalPrewarmContext) {
      const AudioCtx = window.AudioContext;
      if (AudioCtx) {
        globalPrewarmContext = new AudioCtx();
        registerAudioContext(globalPrewarmContext);
      }
    }
  } catch {}

  // Unlock all registered contexts
  for (const ctx of activeAudioContexts) {
    if (ctx.state !== 'closed') {
      playSilentBuffer(ctx);
    }
  }
}

function removeInteractionListeners() {
  if (typeof window === 'undefined') return;
  for (const evt of INTERACTION_EVENTS) {
    window.removeEventListener(evt, handleFirstInteraction, true);
  }
}

/**
 * Initializes the global mobile audio unlocker.
 * Automatically called when module is loaded in browser.
 */
export function initAudioUnlocker() {
  if (typeof window === 'undefined' || isInitialized) return;
  isInitialized = true;

  // Listen for user interaction events in capture phase to unlock early
  for (const evt of INTERACTION_EVENTS) {
    window.addEventListener(evt, handleFirstInteraction, { capture: true, passive: true });
  }

  // Handle visibility change (switching apps / WeChat backgrounding)
  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) {
        resumeAllContexts();
      }
    });
  }

  // Handle pageshow (bfcache restore on iOS Safari) and window focus
  window.addEventListener('pageshow', () => {
    resumeAllContexts();
  });
  window.addEventListener('focus', () => {
    resumeAllContexts();
  });
}

// Auto-initialize on client
if (typeof window !== 'undefined') {
  initAudioUnlocker();
}
