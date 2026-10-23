type SaveResult = { ok: true } | { ok: false; error: unknown };
export interface StudioSaveSnapshot {
  pending: boolean;
  error: unknown | null;
}

/** Wait for saves already issued by this editor before a destructive context switch. */
export function createStudioSaveBoundary() {
  let latest: Promise<SaveResult> | null = null;
  let pendingCount = 0;
  let latestError: unknown | null = null;
  const listeners = new Set<(snapshot: StudioSaveSnapshot) => void>();

  function getSnapshot(): StudioSaveSnapshot {
    return { pending: pendingCount > 0, error: latestError };
  }

  function notify() {
    const snapshot = getSnapshot();
    for (const listener of listeners) {
      try { listener(snapshot); } catch { /* observers must not change save outcomes */ }
    }
  }

  function track<T>(operation: Promise<T>): Promise<T> {
    // Observe rejection immediately, including when the caller handles it later.
    pendingCount += 1;
    latestError = null;
    latest = operation.then<SaveResult, SaveResult>(
      () => ({ ok: true }),
      (error) => ({ ok: false, error }),
    );
    const captured = latest;
    notify();
    void captured.then((result) => {
      pendingCount = Math.max(0, pendingCount - 1);
      if (captured === latest) latestError = result.ok ? null : result.error;
      notify();
    });
    return operation;
  }

  async function settle(): Promise<void> {
    while (latest) {
      const captured = latest;
      const result = await captured;
      // A newer queued save is authoritative; do not abandon it on an older failure.
      if (captured !== latest) continue;
      if (!result.ok) throw result.error;
      return;
    }
  }

  return {
    track,
    settle,
    getSnapshot,
    subscribe(listener: (snapshot: StudioSaveSnapshot) => void) {
      listeners.add(listener);
      listener(getSnapshot());
      return () => listeners.delete(listener);
    },
  };
}
