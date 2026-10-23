/**
 * AlphaTab's SVG beat groups use `b${beat.id}`. Beat IDs are renderer identifiers,
 * so they must be resolved through the score model before they can identify a bar.
 */
export function buildManuscriptBeatBarIndex(tracks) {
  const beatToBarIndex = new Map();
  const ambiguousBeatIds = new Set();

  for (const track of Array.isArray(tracks) ? tracks : []) {
    for (const staff of Array.isArray(track?.staves) ? track.staves : []) {
      for (const bar of Array.isArray(staff?.bars) ? staff.bars : []) {
        const barIndex = bar?.index;
        if (!Number.isSafeInteger(barIndex) || barIndex < 0) continue;

        for (const voice of Array.isArray(bar?.voices) ? bar.voices : []) {
          for (const beat of Array.isArray(voice?.beats) ? voice.beats : []) {
            const beatId = beat?.id;
            if (!Number.isSafeInteger(beatId) || beatId < 0 || ambiguousBeatIds.has(beatId)) continue;

            const previousBarIndex = beatToBarIndex.get(beatId);
            if (previousBarIndex === undefined || previousBarIndex === barIndex) {
              beatToBarIndex.set(beatId, barIndex);
            } else {
              beatToBarIndex.delete(beatId);
              ambiguousBeatIds.add(beatId);
            }
          }
        }
      }
    }
  }

  return beatToBarIndex;
}

/** Resolve only AlphaTab beat group tokens; a token such as `b8` is never bar 8. */
export function resolveManuscriptBarIndexForBeatGroup(classNames, beatToBarIndex) {
  const tokens = String(classNames ?? '').split(/\s+/).filter(Boolean);
  const resolvedBarIndices = new Set();

  for (const token of tokens) {
    const match = token.match(/^b(\d+)$/);
    if (!match) continue;
    const beatId = Number(match[1]);
    if (!Number.isSafeInteger(beatId)) continue;

    const barIndex = beatToBarIndex?.get(beatId);
    if (Number.isSafeInteger(barIndex) && barIndex >= 0) resolvedBarIndices.add(barIndex);
  }

  return resolvedBarIndices.size === 1 ? [...resolvedBarIndices][0] : null;
}
