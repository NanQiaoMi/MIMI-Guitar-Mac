import {
  createBlankProject,
  deleteBar,
  deleteBeatInBar,
  deleteNote,
  duplicateBar,
  evaluateBarTiming,
  generateUid,
  insertBarAfter,
  insertBeatInBar,
  normalizeStudioProject,
  projectToAlphaTex,
  setBeatChord,
  setBeatDuration,
  setBeatBrush,
  setBeatLyrics,
  setNoteFret,
  toggleBeatDot,
  toggleBeatRest,
  toggleBeatTriplet,
  toggleNoteTechnique,
  updateBarMeta,
  type StudioProject,
} from '../../../src/lib/studio/studioScoreModel.ts';
import { encodeStudioProjectToMimiIbe, importStudioScoreBytes, studioProjectToAlphaTabScore } from '../../../src/lib/studio/studioScoreBridge.ts';
import { studioCursorAtClientPoint } from '../../../src/lib/studio/scoreBounds.ts';
import { applyStudioLyricsCommand, collectStudioLyrics } from '../../../src/lib/studio/studioLyrics.ts';
import { filterStudioShortcuts, STUDIO_SHORTCUTS, STUDIO_SHORTCUT_CATEGORIES } from '../../../src/lib/studio/studioShortcuts.ts';
import { renderScorePdfPageImages, renderScorePngDataForScore } from '../../../src/lib/printScore.ts';
import { AlphaTabApi, exporter, Settings } from '@coderline/alphatab';

type JsonObject = Record<string, any>;

function readProject(value: unknown): StudioProject {
  return normalizeStudioProject(value);
}

function changed(project: StudioProject): StudioProject {
  project.updatedAt = Date.now();
  return project;
}

export async function importBytes(bytes: Uint8Array, fileName: string, sourceId: string) {
  return importStudioScoreBytes(bytes, fileName, {
    kind: 'file', id: sourceId || generateUid('source'), fileName,
    format: fileName.split('.').pop()?.toLowerCase() ?? 'unknown',
  });
}

export async function exportBytes(value: unknown, format: 'json' | 'ibe' | 'gp' | 'tex') {
  const project = readProject(value);
  if (format === 'json') return new TextEncoder().encode(JSON.stringify(project, null, 2));
  if (format === 'ibe') return encodeStudioProjectToMimiIbe(project);
  const score = studioProjectToAlphaTabScore(project);
  const settings = new Settings();
  if (format === 'gp') return new Uint8Array(new exporter.Gp7Exporter().export(score, settings));
  return new TextEncoder().encode(new exporter.AlphaTexExporter().exportToString(score, settings));
}

export function applyOperation(value: unknown, operation: string, args: JsonObject): StudioProject {
  const project = readProject(value);
  const t = Number(args.trackIndex ?? 0), b = Number(args.barIndex ?? 0), beat = Number(args.beatIndex ?? 0), string = Number(args.stringIndex ?? 1);
  switch (operation) {
    case 'fret': return setNoteFret(project, t, b, beat, string, Number(args.fret));
    case 'deleteNote': return deleteNote(project, t, b, beat, string);
    case 'deleteBeat': return deleteBeatInBar(project, t, b, beat);
    case 'insertBeat': return insertBeatInBar(project, t, b, beat);
    case 'duration': return setBeatDuration(project, t, b, beat, Number(args.duration) as 1 | 2 | 4 | 8 | 16 | 32);
    case 'dot': return toggleBeatDot(project, t, b, beat);
    case 'triplet': return toggleBeatTriplet(project, t, b, beat);
    case 'rest': return toggleBeatRest(project, t, b, beat);
    case 'technique': return toggleNoteTechnique(project, t, b, beat, string, String(args.technique) as any);
    case 'brush': {
      const direction = args.direction === 'up' || args.direction === 'down' ? args.direction : null;
      return setBeatBrush(project, t, b, beat, direction);
    }
    case 'chord': return setBeatChord(project, t, b, beat, String(args.value ?? ''));
    case 'lyrics': return setBeatLyrics(project, t, b, beat, String(args.value ?? '') || null);
    case 'lyricsAlign': return replaceLyrics(project, t, String(args.value ?? ''));
    case 'insertBar': return insertBarAfter(project, Number(args.afterBarIndex ?? b));
    case 'deleteBar': return deleteBar(project, b);
    case 'duplicateBar': return duplicateBar(project, b);
    case 'barMeta': return updateBarMeta(project, b, { [String(args.field)]: args.value } as any);
    case 'metadata': {
      const next = { ...project } as any;
      for (const [key, value] of Object.entries(args.values ?? {})) if (['title', 'artist', 'album', 'words', 'music', 'tabber', 'key', 'initialTempo', 'timeSignatureNumerator', 'timeSignatureDenominator'].includes(key)) next[key] = value;
      return changed(next);
    }
    case 'track': {
      const next = JSON.parse(JSON.stringify(project)) as StudioProject;
      const track = next.tracks[t];
      if (!track) return project;
      const field = String(args.field);
      if (field === 'remove') {
        if (next.tracks.length < 2) return project;
        next.tracks.splice(t, 1);
        for (const bar of next.bars) delete bar.trackBeats[track.id];
      } else if (field === 'add') {
        const id = generateUid('trk');
        const source = next.tracks[0];
        const newTrack = { ...source, id, name: `音轨 ${next.tracks.length + 1}`, mute: false, solo: false };
        next.tracks.push(newTrack);
        for (const bar of next.bars) bar.trackBeats[id] = (bar.trackBeats[source.id] ?? []).map((item) => ({ ...item, id: generateUid('beat'), notes: [] }));
      } else if (['name', 'program', 'capo', 'volume', 'pan', 'mute', 'solo', 'tuningName'].includes(field)) (track as any)[field] = args.value;
      else if (field === 'tuning') track.tuning = String(args.value).split(/[ ,]+/).map(Number).filter((value) => Number.isInteger(value) && value >= 0 && value <= 127);
      return changed(next);
    }
    case 'new': return createBlankProject(String(args.instrument ?? 'guitar') as any);
    case 'normalize': return readProject(args.value);
    default: return project;
  }
}

export function getTiming(value: unknown, trackIndex: number, barIndex: number) {
  const project = readProject(value);
  const track = project.tracks[trackIndex];
  const bar = project.bars[barIndex];
  return track && bar ? evaluateBarTiming(bar, track.id) : null;
}

export function getAlphaTex(value: unknown): string { return projectToAlphaTex(readProject(value)); }
export function getCursor(value: unknown, x: number, y: number, stringIndex: number) {
  const api = (window as any).__studioApi;
  const surface = api?.canvasElement?.element as HTMLElement | null;
  return surface && api?.renderer?.boundsLookup
    ? studioCursorAtClientPoint(api.renderer.boundsLookup, surface, x, y, readProject(value), stringIndex)
    : null;
}
export function getLyrics(value: unknown, trackIndex: number) {
  const project = readProject(value);
  const track = project.tracks[trackIndex];
  return track ? collectStudioLyrics(project, track.id) : '';
}
export function replaceLyrics(value: unknown, trackIndex: number, text: string) {
  const project = readProject(value);
  const track = project.tracks[trackIndex];
  if (!track) return project;
  return applyStudioLyricsCommand(project, 0, {
    kind: 'align', projectId: project.id, trackId: track.id, expectedRevision: 0, text,
  });
}
export function applyLyricsCommand(value: unknown, currentRevision: number, command: unknown) {
  return applyStudioLyricsCommand(readProject(value), currentRevision, command as Parameters<typeof applyStudioLyricsCommand>[2]);
}
export const shortcuts = STUDIO_SHORTCUTS;
export const shortcutCategories = STUDIO_SHORTCUT_CATEGORIES;
export function searchShortcuts(query: string, category = 'all') { return filterStudioShortcuts(query, category as any); }
export function createBlank(instrument: string) { return createBlankProject(instrument as any); }
export function exportPdfPages(value: unknown, author: string) {
  const score = studioProjectToAlphaTabScore(readProject(value));
  return renderScorePdfPageImages(score, author, score.tracks.map((_track, index) => index), AlphaTabApi);
}
export function exportPngData(value: unknown) {
  const score = studioProjectToAlphaTabScore(readProject(value));
  return renderScorePngDataForScore(score);
}

// Keep a JSON-only adapter boundary. No native UI object or filesystem handle crosses it.
(window as any).NativeStudioCore = { importBytes, exportBytes, applyOperation, getTiming, getAlphaTex, getCursor, getLyrics, replaceLyrics, applyLyricsCommand, shortcuts, shortcutCategories, searchShortcuts, createBlank, exportPdfPages, exportPngData };
