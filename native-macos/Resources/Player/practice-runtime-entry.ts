import {
  advanceSpeedPlan,
  canCountLoopCompletion,
  createLoopLapProgress,
  createPracticeSession,
  createSpeedPlan,
  isCompletedLoopLap,
  isResumeCheckpointDue,
  isValidPlaybackRatio,
  normalizePracticeLoopSelection,
  observeLoopLapProgress,
  preparePracticeResumeSettings,
  startsCompleteLoopLap,
} from '../../../src/lib/practice/practiceProgress.ts';
import {
  applyScoreDisplayMode,
  replaceWholeRestsInSecondaryTracks,
} from '../../../src/lib/scoreDisplayMode.mjs';
import { GM_INSTRUMENTS } from '../../../src/lib/gmInstruments.ts';
import {
  buildManuscriptBeatBarIndex,
  resolveManuscriptBarIndexForBeatGroup,
} from '../../../src/lib/player/manuscriptBeatBars.mjs';

type PracticeBridge = {
  normalizeLoop: typeof normalizePracticeLoopSelection;
  prepareResume: typeof preparePracticeResumeSettings;
  createSession: typeof createPracticeSession;
  createSpeedPlan: typeof createSpeedPlan;
  advanceSpeedPlan: typeof advanceSpeedPlan;
  isValidPlaybackRatio: typeof isValidPlaybackRatio;
  isResumeCheckpointDue: typeof isResumeCheckpointDue;
  isCompletedLoopLap: typeof isCompletedLoopLap;
  startsCompleteLoopLap: typeof startsCompleteLoopLap;
  canCountLoopCompletion: typeof canCountLoopCompletion;
  createLoopLapProgress: typeof createLoopLapProgress;
  observeLoopLapProgress: typeof observeLoopLapProgress;
  applyScoreDisplayMode: typeof applyScoreDisplayMode;
  replaceWholeRestsInSecondaryTracks: typeof replaceWholeRestsInSecondaryTracks;
  gmInstruments: typeof GM_INSTRUMENTS;
  buildManuscriptBeatBarIndex: typeof buildManuscriptBeatBarIndex;
  resolveManuscriptBarIndexForBeatGroup: typeof resolveManuscriptBarIndexForBeatGroup;
};

const scope = globalThis as typeof globalThis & { NativePracticeCore?: PracticeBridge };
scope.NativePracticeCore = Object.freeze({
  normalizeLoop: normalizePracticeLoopSelection,
  prepareResume: preparePracticeResumeSettings,
  createSession: createPracticeSession,
  createSpeedPlan,
  advanceSpeedPlan,
  isValidPlaybackRatio,
  isResumeCheckpointDue,
  isCompletedLoopLap,
  startsCompleteLoopLap,
  canCountLoopCompletion,
  createLoopLapProgress,
  observeLoopLapProgress,
  applyScoreDisplayMode,
  replaceWholeRestsInSecondaryTracks,
  gmInstruments: GM_INSTRUMENTS,
  buildManuscriptBeatBarIndex,
  resolveManuscriptBarIndexForBeatGroup,
});
