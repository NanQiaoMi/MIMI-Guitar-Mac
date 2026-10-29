export type MotionPreference = 'system' | 'gentle' | 'off';
export type MotionMode = 'full' | 'gentle' | 'off';

export interface MotionPreferenceSnapshot {
  preference: MotionPreference;
  mode: MotionMode;
  /** null means the browser cannot report this preference; the effective mode then fails closed to off. */
  systemReducedMotion: boolean | null;
  persistence: 'saved' | 'session-only';
  hasStoredPreference: boolean;
}

export interface MotionPreferenceStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export interface MotionAttributeTarget {
  setAttribute(name: string, value: string): void;
}

export interface MotionMediaQueryList {
  matches?: boolean;
  addEventListener?: (type: 'change', listener: (event: { matches?: boolean }) => void) => void;
  removeEventListener?: (type: 'change', listener: (event: { matches?: boolean }) => void) => void;
  addListener?: (listener: (event: { matches?: boolean }) => void) => void;
  removeListener?: (listener: (event: { matches?: boolean }) => void) => void;
}

export interface MotionPreferenceWindow {
  localStorage?: MotionPreferenceStorage;
  matchMedia?: (query: string) => MotionMediaQueryList;
  addEventListener?: (type: 'storage', listener: (event: { key: string | null; newValue: string | null }) => void) => void;
  removeEventListener?: (type: 'storage', listener: (event: { key: string | null; newValue: string | null }) => void) => void;
}

export interface MotionPreferenceEnvironment {
  window?: MotionPreferenceWindow | null;
  root?: MotionAttributeTarget | null;
}

export const MOTION_PREFERENCE_STORAGE_KEY = 'mimi:motion-preference:v1';
export const MOTION_PREFERENCE_MEDIA_QUERY = '(prefers-reduced-motion: reduce)';
export const MOTION_PREFERENCE_VALUES: readonly MotionPreference[] = Object.freeze(['system', 'gentle', 'off']);

const allowedPreferences = new Set<string>(MOTION_PREFERENCE_VALUES);
const serverSnapshot: MotionPreferenceSnapshot = Object.freeze({
  preference: 'system',
  mode: 'off',
  systemReducedMotion: null,
  persistence: 'session-only',
  hasStoredPreference: false,
});

let snapshot = serverSnapshot;
let runtimeOwners = 0;
let runtimeCleanup: (() => void) | null = null;
let activeEnvironment: Required<MotionPreferenceEnvironment> | null = null;
const subscribers = new Set<(value: MotionPreferenceSnapshot) => void>();

function isMotionPreference(value: unknown): value is MotionPreference {
  return typeof value === 'string' && allowedPreferences.has(value);
}

function parsePreference(value: string | null): MotionPreference | null {
  return isMotionPreference(value) ? value : null;
}

function defaultEnvironment(): Required<MotionPreferenceEnvironment> {
  let browserWindow: MotionPreferenceWindow | null = null;
  let root: MotionAttributeTarget | null = null;
  try {
    if (typeof window !== 'undefined') browserWindow = window as unknown as MotionPreferenceWindow;
  } catch {
    browserWindow = null;
  }
  try {
    if (typeof document !== 'undefined') root = document.documentElement;
  } catch {
    root = null;
  }
  return { window: browserWindow, root };
}

function normalizeEnvironment(
  root?: MotionAttributeTarget | null,
  environment?: MotionPreferenceEnvironment,
): Required<MotionPreferenceEnvironment> {
  const fallback = defaultEnvironment();
  return {
    window: environment && 'window' in environment ? environment.window ?? null : fallback.window,
    root: root !== undefined
      ? root
      : environment && 'root' in environment
        ? environment.root ?? null
        : fallback.root,
  };
}

function getStorage(browserWindow: MotionPreferenceWindow | null): MotionPreferenceStorage | null {
  try {
    return browserWindow?.localStorage ?? null;
  } catch {
    return null;
  }
}

function readStoredPreference(storage: MotionPreferenceStorage | null): {
  preference: MotionPreference;
  persistence: 'saved' | 'session-only';
  hasStoredPreference: boolean;
} {
  if (!storage) return { preference: 'system', persistence: 'session-only', hasStoredPreference: false };
  try {
    const raw = storage.getItem(MOTION_PREFERENCE_STORAGE_KEY);
    const preference = parsePreference(raw);
    return {
      preference: preference ?? 'system',
      persistence: 'saved',
      hasStoredPreference: preference !== null,
    };
  } catch {
    return { preference: 'system', persistence: 'session-only', hasStoredPreference: false };
  }
}

function readSystemPreference(browserWindow: MotionPreferenceWindow | null): boolean | null {
  try {
    if (typeof browserWindow?.matchMedia !== 'function') return null;
    const media = browserWindow.matchMedia(MOTION_PREFERENCE_MEDIA_QUERY);
    return typeof media?.matches === 'boolean' ? media.matches : null;
  } catch {
    return null;
  }
}

export function readMotionPreference(storage?: MotionPreferenceStorage | null): MotionPreference {
  const resolvedStorage = storage === undefined
    ? getStorage(defaultEnvironment().window)
    : storage;
  return readStoredPreference(resolvedStorage ?? null).preference;
}

export function resolveMotionMode(
  preference: MotionPreference,
  systemReducedMotion: boolean | null,
): MotionMode {
  if (preference === 'off' || systemReducedMotion !== false) return 'off';
  if (preference === 'gentle') return 'gentle';
  return 'full';
}

function createSnapshot(
  preference: MotionPreference,
  systemReducedMotion: boolean | null,
  persistence: 'saved' | 'session-only',
  hasStoredPreference: boolean,
): MotionPreferenceSnapshot {
  return Object.freeze({
    preference,
    mode: resolveMotionMode(preference, systemReducedMotion),
    systemReducedMotion,
    persistence,
    hasStoredPreference,
  });
}

function applySnapshot(root: MotionAttributeTarget | null, value: MotionPreferenceSnapshot): void {
  try {
    root?.setAttribute('data-motion', value.mode);
    root?.setAttribute('data-motion-preference', value.preference);
  } catch {
    // Preference state remains useful when a document shim rejects attributes.
  }
}

function publish(next: MotionPreferenceSnapshot, root: MotionAttributeTarget | null): MotionPreferenceSnapshot {
  snapshot = next;
  applySnapshot(root, next);
  for (const subscriber of [...subscribers]) {
    try {
      subscriber(next);
    } catch {
      // One consumer must not prevent other motion surfaces from updating.
    }
  }
  return next;
}

export function bootstrapMotionPreference(
  root?: MotionAttributeTarget | null,
  environment?: MotionPreferenceEnvironment,
): MotionPreferenceSnapshot {
  const target = normalizeEnvironment(root, environment);
  const stored = readStoredPreference(getStorage(target.window));
  return publish(
    createSnapshot(stored.preference, readSystemPreference(target.window), stored.persistence, stored.hasStoredPreference),
    target.root,
  );
}

function attachMediaListener(
  media: MotionMediaQueryList,
  listener: (event: { matches?: boolean }) => void,
): (() => void) | null {
  try {
    if (typeof media.addEventListener === 'function') {
      media.addEventListener('change', listener);
      return () => media.removeEventListener?.('change', listener);
    }
    if (typeof media.addListener === 'function') {
      media.addListener(listener);
      return () => media.removeListener?.(listener);
    }
  } catch {
    return null;
  }
  return null;
}

function handleStorageValue(value: string | null): void {
  if (!activeEnvironment) return;
  const preference = parsePreference(value) ?? 'system';
  const hasStoredPreference = parsePreference(value) !== null;
  const systemReducedMotion = readSystemPreference(activeEnvironment.window);
  publish(
    createSnapshot(preference, systemReducedMotion, 'saved', hasStoredPreference),
    activeEnvironment.root,
  );
}

function stopRuntime(): void {
  try {
    runtimeCleanup?.();
  } catch {
    // Listener teardown is best effort; the owner count is still reset.
  } finally {
    runtimeCleanup = null;
    activeEnvironment = null;
    runtimeOwners = 0;
  }
}

export function startMotionPreferenceRuntime(
  root?: MotionAttributeTarget | null,
  environment?: MotionPreferenceEnvironment,
): () => void {
  const target = normalizeEnvironment(root, environment);
  if (!target.window) return () => undefined;

  runtimeOwners += 1;
  if (!runtimeCleanup) {
    activeEnvironment = target;
    bootstrapMotionPreference(target.root, target);

    const removers: Array<() => void> = [];
    try {
      if (typeof target.window.matchMedia === 'function') {
        const media = target.window.matchMedia(MOTION_PREFERENCE_MEDIA_QUERY);
        const handleMediaChange = (event: { matches?: boolean }) => {
          if (!activeEnvironment) return;
          const matches = typeof event.matches === 'boolean'
            ? event.matches
            : readSystemPreference(activeEnvironment.window);
          publish(
            createSnapshot(
              snapshot.preference,
              matches,
              snapshot.persistence,
              snapshot.hasStoredPreference,
            ),
            activeEnvironment.root,
          );
        };
        const removeMediaListener = attachMediaListener(media, handleMediaChange);
        if (removeMediaListener) removers.push(removeMediaListener);
      }
    } catch {
      // The bootstrapped snapshot remains valid even if listener registration fails.
    }

    const handleStorage = (event: { key: string | null; newValue: string | null }) => {
      if (event.key !== MOTION_PREFERENCE_STORAGE_KEY && event.key !== null) return;
      handleStorageValue(event.key === null ? null : event.newValue);
    };
    try {
      if (typeof target.window.addEventListener === 'function' && typeof target.window.removeEventListener === 'function') {
        target.window.addEventListener('storage', handleStorage);
        removers.push(() => target.window?.removeEventListener?.('storage', handleStorage));
      }
    } catch {
      // Same-tab preference changes still work without storage-event support.
    }

    runtimeCleanup = () => {
      for (const remove of removers.splice(0).reverse()) {
        try {
          remove();
        } catch {
          // Continue cleaning up the remaining listeners.
        }
      }
    };
  } else {
    applySnapshot(target.root, snapshot);
  }

  let released = false;
  return () => {
    if (released) return;
    released = true;
    runtimeOwners = Math.max(0, runtimeOwners - 1);
    if (runtimeOwners === 0) stopRuntime();
  };
}

export function getMotionPreferenceSnapshot(): MotionPreferenceSnapshot {
  if (runtimeOwners > 0) return snapshot;
  if (typeof window !== 'undefined') return bootstrapMotionPreference();
  return serverSnapshot;
}

export function subscribeMotionPreference(
  listener: (value: MotionPreferenceSnapshot) => void,
): () => void {
  if (typeof window === 'undefined' && runtimeOwners === 0) {
    try {
      listener(serverSnapshot);
    } catch {
      // Keep subscriptions isolated from consumer errors.
    }
    return () => undefined;
  }

  const releaseRuntime = startMotionPreferenceRuntime(undefined, activeEnvironment ?? undefined);
  subscribers.add(listener);
  try {
    listener(getMotionPreferenceSnapshot());
  } catch {
    // Keep subscriptions isolated from consumer errors.
  }
  let subscribed = true;
  return () => {
    if (!subscribed) return;
    subscribed = false;
    subscribers.delete(listener);
    releaseRuntime();
  };
}

export function setMotionPreference(preference: MotionPreference): MotionPreferenceSnapshot {
  const normalized = isMotionPreference(preference) ? preference : 'system';
  const environment = activeEnvironment ?? normalizeEnvironment();
  const storage = getStorage(environment.window);
  let persistence: 'saved' | 'session-only' = storage ? 'saved' : 'session-only';
  let hasStoredPreference = false;

  if (storage) {
    try {
      storage.setItem(MOTION_PREFERENCE_STORAGE_KEY, normalized);
      hasStoredPreference = true;
    } catch {
      persistence = 'session-only';
    }
  }

  const systemReducedMotion = readSystemPreference(environment.window);
  return publish(
    createSnapshot(normalized, systemReducedMotion, persistence, hasStoredPreference),
    environment.root,
  );
}

const bootstrapConfig = Object.freeze({
  storageKey: MOTION_PREFERENCE_STORAGE_KEY,
  mediaQuery: MOTION_PREFERENCE_MEDIA_QUERY,
  values: MOTION_PREFERENCE_VALUES,
});

/** Synchronous head script for Astro's `is:inline set:html` to avoid a first-paint preference flash. */
export const motionPreferenceBootstrapScript = `(()=>{const c=${JSON.stringify(bootstrapConfig)};let p='system';try{const v=window.localStorage.getItem(c.storageKey);if(c.values.includes(v))p=v;}catch{}let r=null;try{if(typeof window.matchMedia==='function'){const q=window.matchMedia(c.mediaQuery);if(typeof q.matches==='boolean')r=q.matches;}}catch{}const m=p==='off'||r!==false?'off':p==='gentle'?'gentle':'full';const e=document.documentElement;e.setAttribute('data-motion',m);e.setAttribute('data-motion-preference',p);})();`;
