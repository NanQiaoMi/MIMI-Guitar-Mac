/**
 * Resolve a clicked source-score bar to its actual playback occurrence.
 * AlphaTab's tick-cache `masterBars` list is in playback order; repeated source
 * bars appear more than once with distinct start/end ticks.
 */
export function resolveManuscriptBarSeekTarget(tickCache, sourceBarIndex, currentTick) {
  if (!Number.isSafeInteger(sourceBarIndex) || sourceBarIndex < 0) return null;

  const playbackBars = Array.isArray(tickCache?.masterBars) ? tickCache.masterBars : [];
  const occurrences = [];

  for (const [playbackIndex, playbackBar] of playbackBars.entries()) {
    const start = playbackBar?.start;
    const end = playbackBar?.end;
    if (playbackBar?.masterBar?.index !== sourceBarIndex) continue;
    if (!Number.isSafeInteger(start) || start < 0 || !Number.isSafeInteger(end) || end <= start) continue;

    occurrences.push({
      playbackIndex,
      tick: start,
      end,
      occurrence: occurrences.length + 1,
    });
  }

  if (occurrences.length === 0) return null;

  const hasCurrentTick = Number.isSafeInteger(currentTick) && currentTick >= 0;
  const ranked = occurrences.map((occurrence) => {
    const containsCurrentTick = hasCurrentTick
      && currentTick >= occurrence.tick
      && currentTick < occurrence.end;
    const distance = !hasCurrentTick || containsCurrentTick
      ? 0
      : currentTick < occurrence.tick
        ? occurrence.tick - currentTick
        : currentTick - occurrence.end;

    return { ...occurrence, containsCurrentTick, distance };
  });

  ranked.sort((a, b) => Number(b.containsCurrentTick) - Number(a.containsCurrentTick)
    || a.distance - b.distance
    || a.tick - b.tick
    || a.playbackIndex - b.playbackIndex);

  const selected = ranked[0];
  return {
    sourceBarIndex,
    tick: selected.tick,
    occurrence: selected.occurrence,
    occurrenceCount: occurrences.length,
  };
}
