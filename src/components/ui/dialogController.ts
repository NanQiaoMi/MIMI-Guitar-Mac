type InlineScrollStyle = {
  overflow: string;
  overscrollBehavior: string;
};

type ScrollLockRecord = {
  count: number;
  previous: InlineScrollStyle;
  applied: InlineScrollStyle;
};

const scrollLocks = new WeakMap<HTMLElement, ScrollLockRecord>();

/**
 * Acquires a shared body-scroll lock. Nested dialogs share one snapshot so
 * closing one layer cannot unlock scrolling while another modal is still open.
 */
export function acquireBodyScrollLock(body: HTMLElement): () => void {
  let record = scrollLocks.get(body);
  if (!record) {
    const previous = {
      overflow: body.style.overflow,
      overscrollBehavior: body.style.overscrollBehavior,
    };
    const applied = { overflow: 'hidden', overscrollBehavior: 'none' };
    record = { count: 0, previous, applied };
    scrollLocks.set(body, record);
    body.style.overflow = applied.overflow;
    body.style.overscrollBehavior = applied.overscrollBehavior;
  }

  record.count += 1;
  let released = false;

  return () => {
    if (released) return;
    released = true;

    const active = scrollLocks.get(body);
    if (!active) return;
    active.count -= 1;
    if (active.count > 0) return;

    // Preserve changes made by another owner while this lease was active.
    if (body.style.overflow === active.applied.overflow) {
      body.style.overflow = active.previous.overflow;
    }
    if (body.style.overscrollBehavior === active.applied.overscrollBehavior) {
      body.style.overscrollBehavior = active.previous.overscrollBehavior;
    }
    scrollLocks.delete(body);
  };
}

/** Return focus only when the original trigger still belongs to the document. */
export function restoreFocus(target: HTMLElement | null, documentRef?: Document): boolean {
  if (!target?.isConnected || typeof target.focus !== 'function') return false;
  try {
    target.focus({ preventScroll: true });
  } catch {
    target.focus();
  }
  return documentRef ? documentRef.activeElement === target : true;
}
