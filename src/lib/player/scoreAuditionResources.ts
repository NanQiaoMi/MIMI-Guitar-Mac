import {
  SCORE_GM_SOUNDFONT_URL,
  SCORE_UKULELE_SOUNDFONT_URL,
  type ScoreSoundfontFlavor,
  type ScoreSoundfontRequest,
} from './verifiedScoreSoundfont.ts';

export type ScoreAuditionSourceResult =
  | { ok: true; url: string }
  | { ok: false; reason: 'missing-id' | 'missing-score' | 'unsupported-format' | 'unsafe-url' | 'score-id-mismatch' };

const SAFE_SCORE_ID = /^[A-Za-z0-9_-]{1,80}$/;
const IBE_SCORE_URL = /^\/storage\/scores\/([A-Za-z0-9_-]{1,80})\.ibe$/;

/**
 * Resolve only an explicitly supplied IBE resource belonging to this exact
 * catalog ID. Missing, XHE-only, unsafe, and cross-ID URLs fail closed instead
 * of silently playing an unrelated historical alias.
 */
export function resolveScoreAuditionSource(tab: unknown): ScoreAuditionSourceResult {
  if (!tab || typeof tab !== 'object') return { ok: false, reason: 'missing-id' };
  const candidate = tab as { id?: unknown; scoreUrl?: unknown; format?: unknown };
  if (typeof candidate.id !== 'string' || !SAFE_SCORE_ID.test(candidate.id)) {
    return { ok: false, reason: 'missing-id' };
  }
  if (typeof candidate.format === 'string' && candidate.format.trim().toLowerCase() === 'xhe') {
    return { ok: false, reason: 'unsupported-format' };
  }
  if (typeof candidate.scoreUrl !== 'string' || candidate.scoreUrl.trim() === '') {
    return { ok: false, reason: 'missing-score' };
  }

  const url = candidate.scoreUrl.trim();
  const match = IBE_SCORE_URL.exec(url);
  if (!match) return { ok: false, reason: 'unsafe-url' };
  if (match[1] !== candidate.id) return { ok: false, reason: 'score-id-mismatch' };
  return { ok: true, url };
}

type TrackLike = {
  isPercussion?: unknown;
  mimiSoundfontFlavor?: unknown;
  playbackInfo?: { program?: unknown } | null;
  staves?: Array<{
    isPercussion?: unknown;
    tuning?: unknown;
    bars?: Array<{
      voices?: Array<{
        beats?: Array<{
          notes?: unknown[];
          automations?: Array<{ type?: unknown; value?: unknown }>;
        }>;
      }>;
    }>;
  }>;
};

export type ScoreAuditionSoundfontPlan =
  | { ok: true; presets: ScoreSoundfontRequest[]; urls: string[] }
  | { ok: false; reason: 'conflicting-program'; bank: number; program: number };

const INSTRUMENT_AUTOMATION = 2;
const UKULELE_PROGRAMS = new Set([0, 24, 25]);

function validProgram(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 127
    ? value
    : null;
}

function programsUsedBy(track: TrackLike): number[] {
  const programs = new Set<number>();
  const initial = validProgram(track.playbackInfo?.program);
  if (initial !== null) programs.add(initial);

  for (const staff of track.staves ?? []) {
    for (const bar of staff.bars ?? []) {
      for (const voice of bar.voices ?? []) {
        for (const beat of voice.beats ?? []) {
          for (const automation of beat.automations ?? []) {
            if (automation.type !== INSTRUMENT_AUTOMATION && automation.type !== 'Instrument') continue;
            const program = validProgram(automation.value);
            if (program !== null) programs.add(program);
          }
        }
      }
    }
  }
  return [...programs];
}

function isPercussionTrack(track: TrackLike): boolean {
  return track.isPercussion === true || (track.staves ?? []).some((staff) => staff.isPercussion === true);
}

function isFourStringTrack(track: TrackLike): boolean {
  return (track.staves ?? []).some((staff) => Array.isArray(staff.tuning) && staff.tuning.length === 4);
}

/**
 * Identify a source ukulele track before any UI instrument override is applied.
 * Explicit GM choices should be carried as `mimiSoundfontFlavor: 'gm'` on the
 * runtime clone and are never inferred back to ukulele from category/tuning.
 */
export function resolveScoreAuditionSourceFlavor(track: unknown, category: unknown): ScoreSoundfontFlavor {
  if (!track || typeof track !== 'object' || category !== 'ukulele') return 'gm';
  const source = track as TrackLike;
  const program = validProgram(source.playbackInfo?.program);
  return isFourStringTrack(source) && program !== null && UKULELE_PROGRAMS.has(program)
    ? 'ukulele'
    : 'gm';
}

/**
 * Return every bank needed by the score, preserving distinct GM programs and
 * the separate General MIDI percussion bank. AlphaTab renders only track zero
 * here, but synthesizes every score track, so selection must use all tracks.
 */
export function resolveScoreAuditionSoundfontUrls(
  tracks: unknown,
  _category: unknown = 'guitar',
): string[] {
  const plan = planScoreAuditionSoundfonts(tracks);
  return plan.ok ? plan.urls : [];
}

export function planScoreAuditionSoundfonts(
  tracks: unknown,
  _category?: unknown,
): ScoreAuditionSoundfontPlan {
  if (!Array.isArray(tracks)) return { ok: true, presets: [], urls: [] };
  const requests = new Map<string, ScoreSoundfontRequest>();
  const flavorByPreset = new Map<string, ScoreSoundfontFlavor>();
  for (const item of tracks) {
    if (!item || typeof item !== 'object') continue;
    const track = item as TrackLike;
    if (isPercussionTrack(track)) {
      const key = '128:0';
      const existing = flavorByPreset.get(key);
      if (existing && existing !== 'gm') return { ok: false, reason: 'conflicting-program', bank: 128, program: 0 };
      flavorByPreset.set(key, 'gm');
      requests.set('gm:128:0', { bank: 128, program: 0, flavor: 'gm' });
      continue;
    }
    const programs = programsUsedBy(track);
    for (const program of programs) {
      const flavor = track.mimiSoundfontFlavor === 'ukulele' && UKULELE_PROGRAMS.has(program)
        ? 'ukulele'
        : 'gm';
      const presetKey = `0:${program}`;
      const existingFlavor = flavorByPreset.get(presetKey);
      if (existingFlavor && existingFlavor !== flavor) {
        return { ok: false, reason: 'conflicting-program', bank: 0, program };
      }
      flavorByPreset.set(presetKey, flavor);
      requests.set(`${flavor}:0:${program}`, { bank: 0, program, flavor });
    }
  }

  const presets = [...requests.values()].sort((left, right) => {
    const priority = (request: ScoreSoundfontRequest) => request.flavor === 'gm' ? 0 : 1;
    return priority(left) - priority(right) || left.bank - right.bank || left.program - right.program;
  });
  const urls = [...new Set(presets.map((request) => request.flavor === 'gm'
    ? SCORE_GM_SOUNDFONT_URL
    : SCORE_UKULELE_SOUNDFONT_URL))];
  return { ok: true, presets, urls };
}

export function hasScoreAuditionNotes(tracks: unknown): boolean {
  if (!Array.isArray(tracks)) return false;
  return tracks.some((item) => {
    if (!item || typeof item !== 'object') return false;
    const track = item as TrackLike;
    return (track.staves ?? []).some((staff) =>
      (staff.bars ?? []).some((bar) =>
        (bar.voices ?? []).some((voice) =>
          (voice.beats ?? []).some((beat: any) => Array.isArray(beat.notes) && beat.notes.length > 0),
        ),
      ),
    );
  });
}

/** True only when at least one non-percussion staff contains a pitched note. */
export function hasScoreAuditionMelodicNotes(tracks: unknown): boolean {
  if (!Array.isArray(tracks)) return false;
  return tracks.some((item) => {
    if (!item || typeof item !== 'object') return false;
    const track = item as TrackLike;
    return (track.staves ?? []).some((staff) => {
      if (track.isPercussion === true || staff.isPercussion === true) return false;
      return (staff.bars ?? []).some((bar) =>
        (bar.voices ?? []).some((voice) =>
          (voice.beats ?? []).some((beat) => Array.isArray(beat.notes) && beat.notes.length > 0),
        ),
      );
    });
  });
}
