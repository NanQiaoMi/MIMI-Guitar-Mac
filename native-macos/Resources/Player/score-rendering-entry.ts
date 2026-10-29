import * as alphaTab from '@coderline/alphatab';
import {
  createScoreSettings as createOriginalScoreSettings,
  installScoreLayoutFixes,
} from '../../../src/lib/playerSettings.ts';
import {
  applyScoreDisplayMode,
  DEFAULT_SCORE_DISPLAY_MODE,
  replaceWholeRestsInSecondaryTracks,
  SCORE_DISPLAY_MODES,
} from '../../../src/lib/scoreDisplayMode.mjs';
import { addLyricsTopSpacer } from '../../../src/lib/scoreLyricsLayout.mjs';
import { keySignatureName } from '../../../src/lib/keyName.mjs';
import {
  renderScorePdfPageImages as renderOriginalScorePdfPageImages,
  renderScorePngData as renderOriginalScorePngData,
} from '../../../src/lib/printScore.ts';
import './ibe-entry.ts';
import './guitar-audio-entry.ts';

type NativeScoreRendering = {
  alphaTab: typeof alphaTab;
  createScoreSettings(): ReturnType<typeof createOriginalScoreSettings>;
  installScoreLayoutFixes: typeof installScoreLayoutFixes;
  prepareScoreJson(scoreJson: unknown, mode: string): unknown;
  createScoreFromJson(
    scoreJson: unknown,
    settings: ReturnType<typeof createOriginalScoreSettings>,
    mode: string,
  ): ReturnType<typeof alphaTab.model.JsonConverter.jsonToScore>;
  applyScoreDisplayMode: typeof applyScoreDisplayMode;
  replaceWholeRestsInSecondaryTracks: typeof replaceWholeRestsInSecondaryTracks;
  addLyricsTopSpacer: typeof addLyricsTopSpacer;
  renderPdfPageImages: typeof renderOriginalScorePdfPageImages;
  renderPngData: typeof renderOriginalScorePngData;
  defaultDisplayMode: typeof DEFAULT_SCORE_DISPLAY_MODE;
  displayModes: typeof SCORE_DISPLAY_MODES;
  keySignatureName: typeof keySignatureName;
};

const scope = globalThis as typeof globalThis & {
  alphaTab?: typeof alphaTab;
  MimiScoreRendering?: NativeScoreRendering;
};

function assertRuntimeIdentity(): void {
  if (scope.alphaTab !== alphaTab) {
    throw new Error('AlphaTab 谱面设置与播放器运行时不一致。');
  }
}

function createScoreSettings(): ReturnType<typeof createOriginalScoreSettings> {
  assertRuntimeIdentity();
  installScoreLayoutFixes();
  return createOriginalScoreSettings();
}

function prepareScoreJson(scoreJson: unknown, mode: string): unknown {
  const source = JSON.parse(JSON.stringify(scoreJson));
  if (mode === SCORE_DISPLAY_MODES.MIXED) {
    replaceWholeRestsInSecondaryTracks(source);
  }
  addLyricsTopSpacer(source);
  return source;
}

function createScoreFromJson(
  scoreJson: unknown,
  settings: ReturnType<typeof createOriginalScoreSettings>,
  mode: string,
): ReturnType<typeof alphaTab.model.JsonConverter.jsonToScore> {
  assertRuntimeIdentity();
  const prepared = prepareScoreJson(scoreJson, mode);
  const score = alphaTab.model.JsonConverter.jsonToScore(JSON.stringify(prepared), settings);
  for (const track of score.tracks) {
    for (const staff of track.staves) staff.showStandardNotation = false;
  }
  applyScoreDisplayMode(score, mode);
  return score;
}

// The page and the settings factory deliberately share this exact module
// instance. alphaTab.js remains the local worker script, not the main-thread
// renderer runtime.
scope.alphaTab = alphaTab;
installScoreLayoutFixes();
// AlphaTab 1.8.4 copies defaultFonts into each Settings instance in the
// RenderingResources constructor. The source factory then changes the shared
// effect font to 11px, so its first Settings instance copies the initial 12px
// values while later instances copy the adjusted 11px/Cascadia values. Prime
// that same factory once in this module runtime before the native player's
// first real Settings instance; this matches the source's repeated-factory
// initialization order without changing any rendered score after creation.
createOriginalScoreSettings();
scope.MimiScoreRendering = Object.freeze({
  alphaTab,
  createScoreSettings,
  installScoreLayoutFixes,
  prepareScoreJson,
  createScoreFromJson,
  applyScoreDisplayMode,
  replaceWholeRestsInSecondaryTracks,
  addLyricsTopSpacer,
  renderPdfPageImages: renderOriginalScorePdfPageImages,
  renderPngData: renderOriginalScorePngData,
  defaultDisplayMode: DEFAULT_SCORE_DISPLAY_MODE,
  displayModes: SCORE_DISPLAY_MODES,
  keySignatureName,
});
