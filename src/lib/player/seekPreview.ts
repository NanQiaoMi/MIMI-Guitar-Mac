export type SeekPreviewPosition = Readonly<{ tick: number; timeMs: number }>;

export type SeekPreviewState = Readonly<{
  generation: number;
  origin: SeekPreviewPosition;
  previewTick: number;
  latestActual: SeekPreviewPosition;
}>;

export type SeekPreviewOutcome =
  | Readonly<{ kind: 'commit'; tick: number; origin: SeekPreviewPosition; latestActual: SeekPreviewPosition }>
  | Readonly<{ kind: 'cancel'; position: SeekPreviewPosition }>
  | Readonly<{ kind: 'stale' }>;

function validPosition(position: SeekPreviewPosition): boolean {
  return Number.isSafeInteger(position.tick) && position.tick >= 0
    && Number.isFinite(position.timeMs) && position.timeMs >= 0;
}

function copyPosition(position: SeekPreviewPosition): SeekPreviewPosition {
  if (!validPosition(position)) throw new RangeError('seek position must be a non-negative tick and time');
  return { tick: position.tick, timeMs: position.timeMs };
}

function validateTick(tick: number): number {
  if (!Number.isSafeInteger(tick) || tick < 0) throw new RangeError('seek preview tick must be a non-negative integer');
  return tick;
}

export function beginSeekPreview(
  generation: number,
  actual: SeekPreviewPosition,
  previewTick: number,
): SeekPreviewState {
  if (!Number.isSafeInteger(generation) || generation < 0) throw new RangeError('seek generation must be a non-negative integer');
  const origin = copyPosition(actual);
  return { generation, origin, previewTick: validateTick(previewTick), latestActual: origin };
}

export function updateSeekPreview(state: SeekPreviewState, previewTick: number): SeekPreviewState {
  return { ...state, previewTick: validateTick(previewTick) };
}

export function observeSeekPreviewPosition(
  state: SeekPreviewState | null,
  generation: number,
  actual: SeekPreviewPosition,
): SeekPreviewState | null {
  if (!state || state.generation !== generation) return state;
  return { ...state, latestActual: copyPosition(actual) };
}

export function settleSeekPreview(
  state: SeekPreviewState | null,
  generation: number,
  action: 'commit' | 'cancel',
): SeekPreviewOutcome | null {
  if (!state) return null;
  if (state.generation !== generation) return { kind: 'stale' };
  if (action === 'commit') {
    return {
      kind: 'commit',
      tick: state.previewTick,
      origin: state.origin,
      latestActual: state.latestActual,
    };
  }
  return { kind: 'cancel', position: state.latestActual };
}
