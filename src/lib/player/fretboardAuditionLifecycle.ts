export type ReleasableAuditionSession = {
  readonly active: boolean;
  release(): void;
};

/** Own one fretboard audition at a time and reject work that outlives its UI. */
export function createFretboardAuditionLifecycle<Session extends ReleasableAuditionSession>() {
  let generation = 0;
  let activeSession: Session | null = null;
  let disposed = false;
  const releasedSessions = new WeakSet<object>();

  function releaseOnce(session: Session): void {
    if (releasedSessions.has(session)) return;
    releasedSessions.add(session);
    try {
      session.release();
    } catch {
      // Cleanup must not interrupt player disposal or a newer audition.
    }
  }

  function isCurrent(token: number, visible: boolean): boolean {
    return !disposed && visible && token === generation;
  }

  function invalidate(): number {
    if (disposed) return generation;
    generation += 1;
    const previous = activeSession;
    activeSession = null;
    if (previous) releaseOnce(previous);
    return generation;
  }

  return {
    begin(): number {
      invalidate();
      return generation;
    },
    isCurrent,
    attach(token: number, session: Session, visible: boolean): boolean {
      if (!isCurrent(token, visible) || !session.active) {
        releaseOnce(session);
        return false;
      }
      if (activeSession && activeSession !== session) releaseOnce(activeSession);
      activeSession = session;
      return true;
    },
    finish(session: Session): void {
      if (activeSession === session) activeSession = null;
      releaseOnce(session);
    },
    invalidate,
    dispose(): void {
      if (disposed) return;
      invalidate();
      disposed = true;
    },
  };
}
