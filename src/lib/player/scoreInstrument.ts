export function primaryStringTrackIndex(trackCount: number, defaultTrack: number, visibleTracks: readonly number[]): number {
  if (!Number.isInteger(trackCount) || trackCount <= 0) return 0;
  if (Number.isInteger(defaultTrack) && defaultTrack >= 0 && defaultTrack < trackCount) return defaultTrack;
  return visibleTracks.find((index) => Number.isInteger(index) && index >= 0 && index < trackCount) ?? 0;
}

export function isUkuleleScore(category: string, primaryTuning: readonly number[] | undefined): boolean {
  if (category === 'ukulele') return true;
  if (category === 'guitar' || category === 'bass') return false;
  return primaryTuning?.length === 4;
}
