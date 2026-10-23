import { createScoreAuditionFacade } from './scoreAuditionFacade.ts';

export type { AuditionState } from './scoreAuditionTypes.ts';

/** Lightweight shared facade; the AlphaTab runtime is loaded only on explicit use. */
export const scoreAuditionEngine = createScoreAuditionFacade(async () => {
  const runtime = await import('./scoreAuditionRuntime.ts');
  return runtime.createScoreAuditionRuntime();
});
