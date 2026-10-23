/**
 * Handles the inbound side of native cross-document view transitions. This
 * function is intentionally self-contained so Base.astro can serialize it into
 * a parser-blocking classic script in <head>.
 */
export function installNavigationEntryController(environment = {}) {
  const windowRef = environment.windowRef ?? window;
  const documentRef = environment.documentRef ?? document;
  const pageRevealSupported = environment.supportsPageReveal ?? ('onpagereveal' in windowRef);
  const root = documentRef.documentElement;
  let generation = 0;
  let disposed = false;
  let domReadyListener = null;

  const clearFallback = () => root?.removeAttribute('data-navigation-entry');
  const prefersReducedMotion = () => Boolean(windowRef.matchMedia?.('(prefers-reduced-motion: reduce)').matches);
  const applyFallback = (ticket) => {
    if (disposed || ticket !== generation || !root || prefersReducedMotion()) return;
    const mode = root.getAttribute('data-motion') || 'full';
    if (mode === 'off') return;
    root.setAttribute('data-navigation-entry', 'fallback');
  };
  const removeDomReadyListener = () => {
    if (!domReadyListener) return;
    documentRef.removeEventListener('DOMContentLoaded', domReadyListener);
    domReadyListener = null;
  };
  const scheduleDomReadyFallback = () => {
    const ticket = ++generation;
    clearFallback();
    if (documentRef.readyState === 'loading') {
      domReadyListener = () => {
        removeDomReadyListener();
        applyFallback(ticket);
      };
      documentRef.addEventListener('DOMContentLoaded', domReadyListener, { once: true });
      return;
    }
    applyFallback(ticket);
  };
  const onPageReveal = (event) => {
    removeDomReadyListener();
    const ticket = ++generation;
    clearFallback();
    const transition = event?.viewTransition;
    if (!transition) {
      applyFallback(ticket);
      return;
    }

    // A fulfilled ready promise means the browser owns the incoming animation.
    // Rejection means it will reveal without one; only then add our short CSS
    // fallback. The ticket prevents stale promises from touching a hidden page.
    if (!transition.ready || typeof transition.ready.then !== 'function') {
      applyFallback(ticket);
      return;
    }
    Promise.resolve(transition.ready).then(
      () => {},
      () => applyFallback(ticket),
    );
  };
  const onPageHide = () => {
    generation += 1;
    removeDomReadyListener();
    clearFallback();
  };
  const onPageShow = (event) => {
    if (!pageRevealSupported && event?.persisted) scheduleDomReadyFallback();
  };

  if (pageRevealSupported) windowRef.addEventListener('pagereveal', onPageReveal);
  else scheduleDomReadyFallback();
  windowRef.addEventListener('pagehide', onPageHide);
  windowRef.addEventListener('pageshow', onPageShow);

  return () => {
    if (disposed) return;
    disposed = true;
    generation += 1;
    removeDomReadyListener();
    clearFallback();
    if (pageRevealSupported) windowRef.removeEventListener('pagereveal', onPageReveal);
    windowRef.removeEventListener('pagehide', onPageHide);
    windowRef.removeEventListener('pageshow', onPageShow);
  };
}

export const navigationEntryBootstrapScript = `(${installNavigationEntryController.toString()})();`;
