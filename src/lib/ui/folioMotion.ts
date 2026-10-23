import type { MotionMode } from './motionPreferences.ts';

export type FolioFlipAnimationName = 'flip-page-next' | 'flip-page-prev';
export type FolioFlipEventType = 'animationend' | 'animationcancel';

/** The 3D page flip and its temporary input lock belong only to full motion. */
export function shouldRunFolioFlip(mode: MotionMode): boolean {
  return mode === 'full';
}

export interface FolioFlipAnimationEvent {
  type: FolioFlipEventType;
  target: unknown;
  currentTarget: unknown;
  animationName: string;
}

export interface FolioFlipControllerOptions {
  duration: number;
  fallbackPadding?: number;
  onActiveChange?: (active: boolean, generation: number, animationName: FolioFlipAnimationName | null) => void;
  schedule?: (callback: () => void, delayMs: number) => unknown;
  cancel?: (handle: unknown) => void;
}

export interface FolioFlipController {
  start(animationName: FolioFlipAnimationName): number;
  handleAnimationEvent(
    event: FolioFlipAnimationEvent,
    hasRunningAnimation: (animationName: FolioFlipAnimationName) => boolean,
  ): boolean;
  settle(): boolean;
  destroy(): void;
  isActive(): boolean;
  getGeneration(): number;
}

const defaultSchedule = (callback: () => void, delayMs: number): unknown => globalThis.setTimeout(callback, delayMs);
const defaultCancel = (handle: unknown): void => globalThis.clearTimeout(handle as ReturnType<typeof setTimeout>);

/**
 * Owns only the PaperFolio page-turn lock. The animation event is authoritative;
 * the bounded timer is a fallback for browsers that do not dispatch an end event.
 */
export function createFolioFlipController(options: FolioFlipControllerOptions): FolioFlipController {
  const duration = Number.isFinite(options.duration) ? Math.max(0, options.duration) : 0;
  const fallbackPadding = Number.isFinite(options.fallbackPadding) ? Math.max(0, options.fallbackPadding ?? 0) : 80;
  const schedule = options.schedule ?? defaultSchedule;
  const cancel = options.cancel ?? defaultCancel;

  let generation = 0;
  let activeAnimationName: FolioFlipAnimationName | null = null;
  let timer: unknown = null;
  let destroyed = false;

  function clearFallback(): void {
    if (timer === null) return;
    try {
      cancel(timer);
    } catch {
      // The controller still clears its reference if a host timer shim fails.
    } finally {
      timer = null;
    }
  }

  function settle(expectedGeneration = generation): boolean {
    if (destroyed || expectedGeneration !== generation || activeAnimationName === null) return false;
    clearFallback();
    activeAnimationName = null;
    options.onActiveChange?.(false, generation, null);
    return true;
  }

  return {
    start(animationName) {
      if (destroyed) return generation;
      clearFallback();
      generation += 1;
      const currentGeneration = generation;
      activeAnimationName = animationName;
      options.onActiveChange?.(true, currentGeneration, animationName);
      try {
        timer = schedule(() => settle(currentGeneration), duration + fallbackPadding);
      } catch {
        // Preserve the final state if a host timer is unavailable.
        settle(currentGeneration);
      }
      return currentGeneration;
    },

    handleAnimationEvent(event, hasRunningAnimation) {
      if (
        destroyed ||
        activeAnimationName === null ||
        (event.type !== 'animationend' && event.type !== 'animationcancel') ||
        event.target !== event.currentTarget ||
        event.animationName !== activeAnimationName
      ) {
        return false;
      }

      // A delayed event from the previous same-direction turn must not unlock a
      // newer instance that is still running on this same element.
      let sameNameStillRunning = false;
      try {
        sameNameStillRunning = hasRunningAnimation(activeAnimationName);
      } catch {
        sameNameStillRunning = false;
      }
      if (sameNameStillRunning) return false;

      return settle(generation);
    },

    settle() {
      return settle();
    },

    destroy() {
      if (destroyed) return;
      clearFallback();
      const wasActive = activeAnimationName !== null;
      activeAnimationName = null;
      generation += 1;
      destroyed = true;
      if (wasActive) options.onActiveChange?.(false, generation, null);
    },

    isActive() {
      return activeAnimationName !== null && !destroyed;
    },

    getGeneration() {
      return generation;
    },
  };
}
