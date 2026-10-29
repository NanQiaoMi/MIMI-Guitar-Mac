type NavigationFeedbackAnchor = Pick<Element, 'setAttribute' | 'removeAttribute' | 'getAttribute' | 'hasAttribute' | 'closest'> & {
  href?: string;
};
type ClosestTarget = {
  closest?: (selector: string) => NavigationFeedbackAnchor | null;
};

interface RuntimeEventTarget {
  addEventListener(type: string, listener: EventListener, options?: boolean | AddEventListenerOptions): void;
  removeEventListener(type: string, listener: EventListener, options?: boolean | EventListenerOptions): void;
}

export interface NavigationFeedbackDocument extends RuntimeEventTarget {
  visibilityState?: DocumentVisibilityState;
  location?: Pick<Location, 'href'>;
}

export interface NavigationFeedbackWindow extends RuntimeEventTarget {}

export interface NavigationFeedbackConnection extends RuntimeEventTarget {
  saveData?: boolean;
  effectiveType?: string;
}

export interface NavigationFeedbackNavigator {
  connection?: NavigationFeedbackConnection;
}

const installedDocuments = new WeakSet<object>();
const FEEDBACK_ATTRIBUTE = 'data-navigation-pressed';
const PREFETCH_ATTRIBUTE = 'data-astro-prefetch';
const ASTRO_PREFETCH_STRATEGIES = new Set(['', 'hover', 'tap', 'viewport', 'load']);

function findFeedbackAnchor(
  event: Event,
  documentRef: NavigationFeedbackDocument,
): NavigationFeedbackAnchor | null {
  const target = event.target as ClosestTarget | null;
  if (!target || typeof target.closest !== 'function') return null;
  const anchor = target.closest('a[href]');
  if (!anchor) return null;
  if (!anchor.closest('nav, footer') && !anchor.hasAttribute('data-navigation-feedback')) return null;
  if (anchor.hasAttribute('download')) return null;

  const targetName = anchor.getAttribute('target')?.trim().toLowerCase();
  if (targetName && targetName !== '_self') return null;

  try {
    const current = new URL(documentRef.location?.href ?? 'http://localhost');
    const destination = new URL(anchor.href ?? anchor.getAttribute('href') ?? '', current.href);
    if (destination.origin !== current.origin || !['http:', 'https:'].includes(destination.protocol)) return null;
  } catch {
    return null;
  }
  return anchor;
}

/**
 * Adds a temporary pressed state to marked links without intercepting clicks,
 * forms, history, or browser navigation. The state lasts only for the physical
 * or keyboard press and is cleared on cancellation, visibility changes, and
 * page lifecycle events, including bfcache restoration.
 */
export function installNavigationFeedbackRuntime(
  documentRef: NavigationFeedbackDocument = document,
  windowRef: NavigationFeedbackWindow = window,
  navigatorRef: NavigationFeedbackNavigator = navigator as Navigator & NavigationFeedbackNavigator,
): () => void {
  if (installedDocuments.has(documentRef)) return () => undefined;
  installedDocuments.add(documentRef);

  const activeAnchors = new Set<NavigationFeedbackAnchor>();
  const guardedPrefetchAnchors = new Map<NavigationFeedbackAnchor, string>();
  const clear = (anchor?: NavigationFeedbackAnchor | null) => {
    const targets = anchor ? [anchor] : [...activeAnchors];
    for (const target of targets) {
      target.removeAttribute(FEEDBACK_ATTRIBUTE);
      activeAnchors.delete(target);
    }
  };
  const mark = (anchor: NavigationFeedbackAnchor | null) => {
    if (!anchor) return;
    anchor.setAttribute(FEEDBACK_ATTRIBUTE, '');
    activeAnchors.add(anchor);
  };

  const onPointerDown: EventListener = (event) => {
    const pointer = event as PointerEvent;
    if (pointer.button !== 0 || pointer.isPrimary === false) return;
    mark(findFeedbackAnchor(event, documentRef));
  };
  const onPointerEnd: EventListener = () => clear();
  const onKeyDown: EventListener = (event) => {
    const keyboard = event as KeyboardEvent;
    if (keyboard.key === 'Escape') {
      clear();
      return;
    }
    if (keyboard.key === 'Enter' && !keyboard.repeat) mark(findFeedbackAnchor(event, documentRef));
  };
  const onKeyUp: EventListener = (event) => {
    if ((event as KeyboardEvent).key === 'Enter') clear(findFeedbackAnchor(event, documentRef));
  };
  const onFocusOut: EventListener = (event) => clear(findFeedbackAnchor(event, documentRef));
  const onLifecycleReset: EventListener = () => clear();
  const onVisibilityChange: EventListener = () => {
    if (documentRef.visibilityState === 'hidden') clear();
  };

  const isSlowConnection = () => {
    const connection = navigatorRef.connection;
    return Boolean(connection?.saveData) || /2g/.test(connection?.effectiveType ?? '');
  };
  const restorePrefetchAttributes = () => {
    for (const [anchor, originalValue] of guardedPrefetchAnchors) {
      if (anchor.getAttribute(PREFETCH_ATTRIBUTE) === 'false') {
        anchor.setAttribute(PREFETCH_ATTRIBUTE, originalValue);
      }
    }
    guardedPrefetchAnchors.clear();
  };
  const suppressPrefetch = (anchor: NavigationFeedbackAnchor | null) => {
    if (!anchor) return;
    const currentValue = anchor.getAttribute(PREFETCH_ATTRIBUTE);
    if (currentValue === null || currentValue === 'false' || !ASTRO_PREFETCH_STRATEGIES.has(currentValue)) return;
    if (!guardedPrefetchAnchors.has(anchor)) guardedPrefetchAnchors.set(anchor, currentValue);
    anchor.setAttribute(PREFETCH_ATTRIBUTE, 'false');
  };
  const syncPrefetchGuard = () => {
    // Astro already skips hover prefetch on slow networks. Only restore taps
    // guarded below; suppressing all links here could make Astro skip installing
    // its hover/focus listeners before a later connection recovery.
    if (!isSlowConnection()) restorePrefetchAttributes();
  };
  const findPrefetchAnchor = (event: Event): NavigationFeedbackAnchor | null => {
    const target = event.target as ClosestTarget | null;
    if (!target || typeof target.closest !== 'function') return null;
    return target.closest(`a[${PREFETCH_ATTRIBUTE}]`);
  };
  const onPrefetchIntentCapture: EventListener = (event) => {
    // Astro's tap strategy listens in the bubble phase and ignores slow-network
    // checks. Capture the containing link first, including nested icon/text taps.
    if (isSlowConnection()) suppressPrefetch(findPrefetchAnchor(event));
  };
  const onConnectionChange: EventListener = () => syncPrefetchGuard();
  const onPageShow: EventListener = () => {
    clear();
    syncPrefetchGuard();
  };

  const options: AddEventListenerOptions = { capture: true };
  const listeners: Array<[RuntimeEventTarget, string, EventListener, boolean | AddEventListenerOptions]> = [
    [documentRef, 'pointerdown', onPointerDown, options],
    [documentRef, 'pointerup', onPointerEnd, options],
    [documentRef, 'pointercancel', onPointerEnd, options],
    [documentRef, 'keydown', onKeyDown, options],
    [documentRef, 'keyup', onKeyUp, options],
    [documentRef, 'focusout', onFocusOut, options],
    [documentRef, 'visibilitychange', onVisibilityChange, false],
    [documentRef, 'touchstart', onPrefetchIntentCapture, options],
    [documentRef, 'mousedown', onPrefetchIntentCapture, options],
    [windowRef, 'blur', onLifecycleReset, false],
    [windowRef, 'pagehide', onLifecycleReset, false],
    [windowRef, 'pageshow', onPageShow, false],
  ];

  for (const [target, type, listener, listenerOptions] of listeners) {
    target.addEventListener(type, listener, listenerOptions);
  }
  navigatorRef.connection?.addEventListener('change', onConnectionChange);
  syncPrefetchGuard();

  let disposed = false;
  return () => {
    if (disposed) return;
    disposed = true;
    clear();
    restorePrefetchAttributes();
    for (const [target, type, listener, listenerOptions] of listeners) {
      target.removeEventListener(type, listener, listenerOptions);
    }
    navigatorRef.connection?.removeEventListener('change', onConnectionChange);
    installedDocuments.delete(documentRef);
  };
}
