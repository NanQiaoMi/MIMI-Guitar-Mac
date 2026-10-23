import type { CursorPosition, StudioProject } from './studioScoreModel.ts';

/** Maps an AlphaTab beat to the one-based studio track/bar/beat cursor. */
export function studioCursorFromBeat(
  beat: any,
  project: StudioProject,
  currentStringIndex: number,
  note?: any,
): CursorPosition | null {
  const bar = beat?.voice?.bar;
  const trackIndex = Number(bar?.staff?.track?.index);
  const barIndex = Number(bar?.masterBar?.index);
  const beatIndex = Number(beat?.index);
  const track = project.tracks[trackIndex];
  if (!track || !Number.isInteger(barIndex) || !project.bars[barIndex] || !Number.isInteger(beatIndex) || beatIndex < 0) return null;
  const studioBeats = project.bars[barIndex].trackBeats[track.id] ?? [];
  if (beatIndex >= studioBeats.length) return null;

  const stringCount = Math.max(1, track.tuning.length || 6);
  const alphaTabString = Number(note?.string);
  const studioString = stringCount + 1 - alphaTabString;
  const stringIndex = Number.isInteger(alphaTabString) && alphaTabString >= 1 && alphaTabString <= stringCount
    ? studioString
    : Math.max(1, Math.min(stringCount, Math.trunc(currentStringIndex || 1)));

  return { trackIndex, barIndex, beatIndex, stringIndex };
}

/**
 * Resolves CSS viewport coordinates relative to AlphaTab's whole render surface,
 * matching AlphaTab 1.8.4's native mouse path. BoundsLookup coordinates span all
 * partial SVG systems, so using an individual SVG origin would select the wrong
 * system after the first partial.
 */
export function studioCursorAtClientPoint(
  boundsLookup: any,
  surface: { getBoundingClientRect: () => { left: number; top: number } } | null,
  clientX: number,
  clientY: number,
  project: StudioProject,
  currentStringIndex: number,
): CursorPosition | null {
  if (!boundsLookup || typeof boundsLookup.getBeatAtPos !== 'function' || typeof surface?.getBoundingClientRect !== 'function') return null;
  try {
    const rect = surface.getBoundingClientRect();
    // AlphaTab's BrowserMouseEventArgs subtracts the canvas surface's page
    // origin (equivalent to client - rect); do not add a partial SVG's origin.
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    const beat = boundsLookup.getBeatAtPos(x, y);
    if (!beat) return null;
    const note = typeof boundsLookup.getNoteAtPos === 'function'
      ? boundsLookup.getNoteAtPos(beat, x, y)
      : null;
    return studioCursorFromBeat(beat, project, currentStringIndex, note);
  } catch {
    return null;
  }
}
