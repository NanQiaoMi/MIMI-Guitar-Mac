import { getMotionPreferenceSnapshot, subscribeMotionPreference } from './motionPreferences.ts';
import { motionTokens } from './motion.ts';

/** A one-shot reveal for decorative section wrappers. Content stays visible without JS. */
export function paperReveal(node: HTMLElement, options: { delay?: number } = {}) {
  let observer: IntersectionObserver | null = null;
  let animation: Animation | null = null;
  let revealed = false;
  let destroyed = false;
  let observed = false;

  const settle = () => {
    if (!animation) return;
    try { animation.finish(); } catch { animation.cancel(); }
    animation = null;
  };
  const reveal = () => {
    if (revealed || destroyed) return;
    revealed = true;
    observer?.disconnect();
    observer = null;
    const { mode } = getMotionPreferenceSnapshot();
    if (mode === 'off' || node.matches?.(':focus-within') || typeof node.animate !== 'function') return;
    const computed = getComputedStyle(node);
    const baseline = computed.transform;
    const opacity = Number.parseFloat(computed.opacity);
    const finalOpacity = Number.isFinite(opacity) ? opacity : 1;
    const transform = baseline === 'none' ? '' : baseline;
    const delay = Math.min(60, Math.max(0, options.delay ?? 0));
    try {
      animation = node.animate([
        { opacity: 0, transform: mode === 'full' ? `${transform} translateY(10px)` : transform || 'none' },
        { opacity: finalOpacity, transform: transform || 'none' },
      ], { duration: mode === 'gentle' ? 140 : 220, delay: mode === 'gentle' ? 0 : delay, easing: motionTokens.easing.settle.css, fill: 'backwards' });
      animation.onfinish = () => { animation = null; };
    } catch { animation = null; }
  };
  let previousMode = getMotionPreferenceSnapshot().mode;
  const unsubscribe = subscribeMotionPreference(({ mode }) => {
    if (mode !== previousMode) settle();
    previousMode = mode;
    if (mode === 'off') {
      observer?.disconnect();
      observer = null;
      revealed = true;
    }
  });
  const handleFocus = () => {
    settle();
    revealed = true;
    observer?.disconnect();
    observer = null;
  };
  node.addEventListener?.('focusin', handleFocus);
  if (!revealed) {
    if (typeof IntersectionObserver === 'function') {
      observer = new IntersectionObserver((entries) => {
        const initiallyVisible = !observed;
        observed = true;
        if (!entries.some((entry) => entry.isIntersecting)) return;
        // Never hide already-painted SSR content when hydration first observes it.
        if (initiallyVisible) {
          revealed = true;
          observer?.disconnect();
          observer = null;
        } else reveal();
      }, { threshold: 0.08 });
      observer.observe(node);
    } else revealed = true;
  }
  return {
    destroy() {
      destroyed = true;
      observer?.disconnect();
      animation?.cancel();
      animation = null;
      node.removeEventListener?.('focusin', handleFocus);
      unsubscribe();
    },
  };
}
