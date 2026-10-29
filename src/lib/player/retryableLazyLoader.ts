/** Shares an in-flight module load and forgets a rejected load so callers can retry. */
export function createRetryableLazyLoader<T>(load: () => Promise<T>): () => Promise<T> {
  let value: T | undefined;
  let loaded = false;
  let pending: Promise<T> | null = null;

  return () => {
    if (loaded) return Promise.resolve(value as T);
    if (pending) return pending;

    const attempt = Promise.resolve().then(load).then(
      (loadedValue) => {
        value = loadedValue;
        loaded = true;
        return loadedValue;
      },
      (error) => {
        if (pending === attempt) pending = null;
        throw error;
      },
    );
    pending = attempt;
    return attempt;
  };
}
