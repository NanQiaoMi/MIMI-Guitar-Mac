interface FretInputOptions {
  context: () => string;
  commit: (fret: number) => void;
  onPendingChange?: (pending: boolean) => void;
  schedule?: (callback: () => void, delay: number) => unknown;
  cancel?: (handle: unknown) => void;
}

/** Delayed 1/2 input belongs to one editor revision and cursor, never a later target. */
export function createStudioFretInput(options: FretInputOptions) {
  const schedule = options.schedule ?? ((callback, delay) => setTimeout(callback, delay));
  const cancelTimer = options.cancel ?? ((handle) => clearTimeout(handle as ReturnType<typeof setTimeout>));
  let pending: { digit: string; context: string; generation: number } | null = null;
  let timer: unknown;
  let generation = 0;

  function setPending(value: typeof pending) {
    const wasPending = pending !== null;
    pending = value;
    if (wasPending !== (pending !== null)) options.onPendingChange?.(pending !== null);
  }

  function cancel() {
    generation += 1;
    setPending(null);
    if (timer !== undefined) cancelTimer(timer);
    timer = undefined;
  }

  function flush() {
    const captured = pending;
    cancel();
    if (captured && captured.context === options.context()) options.commit(Number(captured.digit));
  }

  function push(digit: string) {
    if (!/^[0-9]$/.test(digit)) return;
    const captured = pending;
    const context = options.context();
    cancel();
    if (captured && captured.context === context) {
      const combined = Number(captured.digit + digit);
      if (combined <= 24) options.commit(combined);
      else {
        options.commit(Number(captured.digit));
        options.commit(Number(digit));
      }
      return;
    }
    if (digit !== '1' && digit !== '2') {
      options.commit(Number(digit));
      return;
    }
    const ticket = generation;
    setPending({ digit, context, generation: ticket });
    timer = schedule(() => {
      if (pending?.generation === ticket && generation === ticket) flush();
    }, 320);
  }

  return {
    push,
    flush,
    cancel,
    get hasPending() { return pending !== null; },
  };
}
