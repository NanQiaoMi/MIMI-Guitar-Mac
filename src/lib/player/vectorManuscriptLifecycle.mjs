/** Own one render attempt, including its request, callbacks and AlphaTab instance. */
export function createVectorManuscriptLifecycle() {
  let generation = 0;
  let active = null;
  const release = () => {
    const previous = active;
    active = null;
    if (!previous) return;
    previous.controller.abort();
    for (const cleanup of previous.cleanups.splice(0)) {
      try { cleanup(); } catch { /* Continue releasing the remaining owned resources. */ }
    }
    try { previous.api?.destroy(); } catch { /* A failed renderer still relinquishes ownership. */ }
  };
  return {
    get generation() { return generation; },
    isCurrent(value) { return active?.generation === value && !active.controller.signal.aborted; },
    begin() {
      release();
      const current = { generation: ++generation, controller: new AbortController(), api: null, cleanups: [] };
      active = current;
      const isCurrent = () => active === current && !current.controller.signal.aborted;
      return {
        generation: current.generation,
        signal: current.controller.signal,
        isCurrent,
        attach(api) {
          if (!isCurrent()) { api.destroy(); return; }
          current.api = api;
        },
        track(cleanup) {
          if (isCurrent()) current.cleanups.push(cleanup);
          else cleanup();
        },
        dispose() { if (active === current) release(); },
      };
    },
    dispose() { ++generation; release(); },
  };
}
