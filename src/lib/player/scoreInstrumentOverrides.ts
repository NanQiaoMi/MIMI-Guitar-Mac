import { resolveScoreAuditionSourceFlavor } from './scoreAuditionResources.ts';

export type ScoreInstrumentFlavor = 'gm' | 'ukulele';

const UKULELE_PRESET_PROGRAMS = new Set([0, 24, 25]);

export function isUkulelePresetProgram(program: number): boolean {
  return UKULELE_PRESET_PROGRAMS.has(program);
}

/** Source Uke banks only contain the matching 0/24/25 presets; other programs stay GM. */
export function sourceInstrumentFlavor(
  category: string,
  tuning: readonly number[] | undefined,
  program: number,
): ScoreInstrumentFlavor {
  return resolveScoreAuditionSourceFlavor({ playbackInfo: { program }, staves: [{ tuning }] }, category);
}

/**
 * Resolve current and legacy resume entries against the freshly rebuilt source
 * score. Older entries have no marker, so only a differing program is treated
 * as an override; equal programs keep the source preset and its automation.
 */
export function resolveResumeInstrument(
  sourceProgram: number,
  savedProgram?: number,
  savedOverride?: boolean,
): { program: number; instrumentOverride: boolean } {
  const validSavedProgram = Number.isSafeInteger(savedProgram) && savedProgram! >= 0 && savedProgram! <= 127;
  if (savedOverride === true) {
    return validSavedProgram
      ? { program: savedProgram!, instrumentOverride: true }
      : { program: sourceProgram, instrumentOverride: false };
  }
  if (savedOverride === false) return { program: sourceProgram, instrumentOverride: false };
  if (validSavedProgram && savedProgram !== sourceProgram) {
    return { program: savedProgram!, instrumentOverride: true };
  }
  return { program: sourceProgram, instrumentOverride: false };
}
