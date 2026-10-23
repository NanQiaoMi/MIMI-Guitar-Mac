export const SCORE_PREVIEW_DURATIONS = [30, 60] as const;
export const DEFAULT_SCORE_PREVIEW_SECONDS = SCORE_PREVIEW_DURATIONS[0];
export const MAX_SCORE_PREVIEW_SECONDS = SCORE_PREVIEW_DURATIONS[1];

/** Bound a requested preview without turning invalid input into immediate silence. */
export function normalizeScorePreviewSeconds(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return DEFAULT_SCORE_PREVIEW_SECONDS;
  }
  return Math.min(MAX_SCORE_PREVIEW_SECONDS, Math.max(1, value));
}
