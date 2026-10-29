import {
  getMotionPreferenceSnapshot,
  subscribeMotionPreference,
  type MotionMode,
} from './motionPreferences.ts';

/** Shared motion values for CSS and Svelte transitions. */
export type MotionKind = 'menu' | 'panel' | 'notice';
export type MotionDirection = 'in' | 'out' | 'both';

export interface SurfaceMotionOptions {
  kind?: MotionKind;
  /** Starting vertical offset in CSS pixels. The final position is always zero. */
  y?: number;
  /** Starting scale. The final scale is always one. */
  scale?: number;
  /** Optional duration override in milliseconds. */
  duration?: number;
}

export interface MotionTransitionConfig {
  delay?: number;
  duration?: number;
  easing?: (progress: number) => number;
  css?: (progress: number, remaining: number) => string;
  tick?: (progress: number, remaining: number) => void;
}

export interface MotionTransitionOptions {
  direction?: MotionDirection;
}

type MotionEasing = {
  css: string;
  fn: (progress: number) => number;
};

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

function cubicBezier(x1: number, y1: number, x2: number, y2: number) {
  const curve = (t: number, first: number, second: number) => {
    const inverse = 1 - t;
    return 3 * inverse * inverse * t * first + 3 * inverse * t * t * second + t * t * t;
  };
  const derivative = (t: number, first: number, second: number) =>
    3 * (1 - t) * (1 - t) * first + 6 * (1 - t) * t * (second - first) + 3 * t * t * (1 - second);

  return (input: number): number => {
    const x = clamp01(input);
    if (x === 0 || x === 1) return x;

    let parameter = x;
    for (let iteration = 0; iteration < 8; iteration += 1) {
      const error = curve(parameter, x1, x2) - x;
      const slope = derivative(parameter, x1, x2);
      if (Math.abs(error) < 1e-7 || Math.abs(slope) < 1e-7) break;
      const candidate = parameter - error / slope;
      if (candidate < 0 || candidate > 1) break;
      parameter = candidate;
    }

    if (Math.abs(curve(parameter, x1, x2) - x) >= 1e-7) {
      let low = 0;
      let high = 1;
      for (let iteration = 0; iteration < 24; iteration += 1) {
        parameter = (low + high) / 2;
        const currentX = curve(parameter, x1, x2);
        if (Math.abs(currentX - x) < 1e-7) break;
        if (currentX < x) low = parameter;
        else high = parameter;
      }
    }

    return clamp01(curve(parameter, y1, y2));
  };
}

const standardEasing: MotionEasing = Object.freeze({
  css: 'cubic-bezier(0.2, 0, 0, 1)',
  fn: cubicBezier(0.2, 0, 0, 1),
});

const settleEasing: MotionEasing = Object.freeze({
  css: 'cubic-bezier(0.22, 1, 0.36, 1)',
  fn: cubicBezier(0.22, 1, 0.36, 1),
});

export const motionTokens = Object.freeze({
  duration: Object.freeze({
    micro: 120,
    control: 200,
    panel: 260,
    page: 280,
    exit: 160,
    folio: 360,
  }),
  easing: Object.freeze({
    standard: standardEasing,
    settle: settleEasing,
  }),
});

const cssMotionProperties: ReadonlyArray<readonly [string, string]> = [
  ['--motion-duration-micro', `${motionTokens.duration.micro}ms`],
  ['--motion-duration-control', `${motionTokens.duration.control}ms`],
  ['--motion-duration-panel', `${motionTokens.duration.panel}ms`],
  ['--motion-duration-page', `${motionTokens.duration.page}ms`],
  ['--motion-duration-exit', `${motionTokens.duration.exit}ms`],
  ['--motion-duration-folio', `${motionTokens.duration.folio}ms`],
  ['--motion-ease-standard', motionTokens.easing.standard.css],
  ['--motion-ease-settle', motionTokens.easing.settle.css],
];

/** Inline CSS custom properties for the document root. Values come from motionTokens above. */
export const motionStyle = cssMotionProperties.map(([name, value]) => `${name}:${value}`).join(';');

/** The browser preference is clamped by system reduce; SSR and unknown states fail closed. */
export function getMotionMode(): MotionMode {
  return getMotionPreferenceSnapshot().mode;
}

/** Backwards-compatible predicate for callers that need a binary no-motion guard. */
export function prefersReducedMotion(): boolean {
  return getMotionMode() === 'off';
}

function motionDuration(duration: number, mode: MotionMode): number {
  if (mode === 'gentle') return Math.min(duration, motionTokens.duration.micro);
  return duration;
}

const kindDefaults: Record<MotionKind, { duration: number; y: number; scale: number; easing: MotionEasing }> = {
  menu: { duration: motionTokens.duration.control, y: 8, scale: 0.99, easing: motionTokens.easing.settle },
  panel: { duration: motionTokens.duration.panel, y: 12, scale: 0.985, easing: motionTokens.easing.standard },
  notice: { duration: motionTokens.duration.micro, y: 4, scale: 1, easing: motionTokens.easing.standard },
};

function finiteOr(value: number | undefined, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function readBaseline(node: Element): { transform: string; opacity: number } | null {
  if (typeof window === 'undefined') return null;
  const view = node.ownerDocument?.defaultView ?? window;
  if (typeof view.getComputedStyle !== 'function') return null;

  const computed = view.getComputedStyle(node);
  const opacityValue = Number.parseFloat(computed.opacity);
  return {
    transform: computed.transform && computed.transform !== 'none' ? computed.transform : '',
    opacity: Number.isFinite(opacityValue) ? clamp01(opacityValue) : 1,
  };
}

/**
 * Reversible Svelte transition that composes a short offset/scale with the node's
 * existing transform and opacity. Apply it to a wrapper when the child owns a
 * live transform (for example, pointer tilt). Svelte can reverse the same node
 * from its current progress when its state changes during an intro/outro.
 */
export function surfaceMotion(
  node: Element,
  params: SurfaceMotionOptions = {},
  transition: MotionTransitionOptions = {},
): MotionTransitionConfig {
  const mode = getMotionMode();
  if (mode === 'off') return { duration: 0 };

  const kind = params.kind ?? 'menu';
  const defaults = kindDefaults[kind];
  const direction = transition.direction ?? 'both';
  const duration = params.duration ?? (direction === 'out' ? motionTokens.duration.exit : defaults.duration);
  const gentle = mode === 'gentle';
  const y = gentle ? 0 : finiteOr(params.y, defaults.y);
  const startingScale = gentle ? 1 : finiteOr(params.scale, defaults.scale);
  const baseline = readBaseline(node);

  if (!baseline) return { duration: 0 };

  const baseTransform = baseline.transform ? `${baseline.transform} ` : '';
  return {
    duration: Math.max(0, motionDuration(finiteOr(duration, defaults.duration), mode)),
    easing: defaults.easing.fn,
    css: (progress) => {
      const t = clamp01(progress);
      if (gentle) return `opacity:${baseline.opacity * t};transform:${baseline.transform || 'none'}`;
      const offset = (1 - t) * y;
      const scale = startingScale + (1 - startingScale) * t;
      return `opacity:${baseline.opacity * t};transform:${baseTransform}translate3d(0,${offset}px,0) scale(${scale})`;
    },
  };
}

/** Reversible opacity-only Svelte transition that preserves the node's baseline opacity. */
export function fadeMotion(
  node: Element,
  params: Pick<SurfaceMotionOptions, 'kind' | 'duration'> = {},
  transition: MotionTransitionOptions = {},
): MotionTransitionConfig {
  const mode = getMotionMode();
  if (mode === 'off') return { duration: 0 };

  const kind = params.kind ?? 'menu';
  const defaults = kindDefaults[kind];
  const direction = transition.direction ?? 'both';
  const duration = params.duration ?? (direction === 'out' ? motionTokens.duration.exit : defaults.duration);
  const baseline = readBaseline(node);

  if (!baseline) return { duration: 0 };

  return {
    duration: Math.max(0, motionDuration(finiteOr(duration, defaults.duration), mode)),
    easing: defaults.easing.fn,
    css: (progress) => `opacity:${baseline.opacity * clamp01(progress)}`,
  };
}


type MotionSurfaceNode = Element & {
  getAnimations?: (options?: { subtree?: boolean }) => Animation[];
};

const registeredMotionSurfaces = new Set<MotionSurfaceNode>();
const attemptedAnimationFinishes = new WeakSet<object>();
let detachMotionPreferenceSubscription: (() => void) | null = null;
let finishingRegisteredSurfaces = false;
let previousMotionMode: MotionMode | null = null;

function finishRegisteredSurfaceAnimations(): void {
  // Snapshot once and never poll: finishing can dispatch events and re-enter this
  // handler, but cannot create a finish loop or keep a frame callback alive.
  if (finishingRegisteredSurfaces) return;
  finishingRegisteredSurfaces = true;
  try {
    for (const node of [...registeredMotionSurfaces]) {
      if (!registeredMotionSurfaces.has(node) || typeof node.getAnimations !== 'function') continue;

      let animations: Animation[];
      try {
        // subtree:false is deliberate: the wrapper owns its transition, not child
        // playback, score, or other business animations.
        animations = node.getAnimations({ subtree: false });
      } catch {
        continue;
      }

      for (const animation of animations) {
        if (!animation || typeof animation !== 'object' || typeof animation.finish !== 'function') continue;
        if (attemptedAnimationFinishes.has(animation)) continue;
        attemptedAnimationFinishes.add(animation);
        try {
          animation.finish();
        } catch {
          // A non-finishable animation must not prevent other registered surfaces
          // from settling, or be retried forever for the same Animation object.
        }
      }
    }
  } finally {
    finishingRegisteredSurfaces = false;
  }
}

function motionModeRank(mode: MotionMode): number {
  if (mode === 'full') return 2;
  if (mode === 'gentle') return 1;
  return 0;
}

function attachMotionPreferenceListener(): void {
  if (detachMotionPreferenceSubscription || registeredMotionSurfaces.size === 0) return;
  detachMotionPreferenceSubscription = subscribeMotionPreference((value) => {
    const previous = previousMotionMode;
    previousMotionMode = value.mode;
    if (previous !== null && motionModeRank(value.mode) < motionModeRank(previous)) {
      finishRegisteredSurfaceAnimations();
    }
  });
}

function detachMotionPreferenceListenerWhenUnused(): void {
  if (registeredMotionSurfaces.size > 0) return;
  try {
    detachMotionPreferenceSubscription?.();
  } catch {
    // Keep teardown safe if a consumer rejects its subscription cleanup.
  }
  detachMotionPreferenceSubscription = null;
  previousMotionMode = null;
}

/**
 * Register a dedicated wrapper whose only animations are owned by surfaceMotion
 * or fadeMotion. A single shared preference listener settles wrapper-level
 * transitions when the effective mode becomes less animated.
 *
 * Do not register player, score, or business-animated elements: descendants are
 * explicitly excluded via getAnimations({ subtree: false }).
 */
export function registerMotionSurface(node: Element): { destroy: () => void } {
  if (!node || typeof window === 'undefined') return { destroy: () => undefined };

  const surface = node as MotionSurfaceNode;
  if (registeredMotionSurfaces.has(surface)) return { destroy: () => undefined };

  registeredMotionSurfaces.add(surface);
  attachMotionPreferenceListener();

  let destroyed = false;
  return {
    destroy() {
      if (destroyed) return;
      destroyed = true;
      registeredMotionSurfaces.delete(surface);
      detachMotionPreferenceListenerWhenUnused();
    },
  };
}
