/** The unfolded playback clock produced by AlphaTab's MidiTickLookup. */
export interface NativeTempoBar {
  start: number;
  end: number;
  tempoChanges: readonly { tick: number; tempo: number }[];
}

/**
 * Resolve the source tempo at an absolute playback tick, including repeat passes.
 * Never use the last player-position event: a paused seek may not have emitted it.
 * The exclusive score end, missing ranges and incomplete tempo maps are unknown.
 */
export function nativeTempoAtTick(bars: readonly NativeTempoBar[] | null | undefined, tick: number): number | null {
  if (!bars?.length || !Number.isFinite(tick) || tick < 0) return null;
  let low = 0;
  let high = bars.length - 1;
  let index = -1;
  while (low <= high) {
    const middle = (low + high) >>> 1;
    const start = bars[middle].start;
    if (!Number.isFinite(start)) return null;
    if (start <= tick) { index = middle; low = middle + 1; }
    else high = middle - 1;
  }
  if (index < 0) return null;
  const bar = bars[index];
  if (!Number.isFinite(bar.end) || bar.start < 0 || bar.end <= bar.start || tick >= bar.end) return null;
  if (index > 0 && bars[index - 1].end > bar.start) return null;
  if (index + 1 < bars.length && bars[index + 1].start < bar.end) return null;
  let resolved: number | null = null;
  let previousTick = -1;
  for (const change of bar.tempoChanges) {
    if (!Number.isFinite(change.tick) || change.tick < bar.start || change.tick > bar.end || change.tick < previousTick
      || !Number.isFinite(change.tempo) || change.tempo < 1 || change.tempo > 1000) return null;
    previousTick = change.tick;
    if (change.tick <= tick) resolved = change.tempo;
  }
  return resolved;
}
