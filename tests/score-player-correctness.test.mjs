import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as alphaTab from '@coderline/alphatab';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import { studioProjectToAlphaTabScore } from '../src/lib/studio/studioScoreBridge.ts';
import {
  applyCapoSelection,
  beatLookupTick,
  captureSourceCapos,
  formatCapoValue,
  positionBeatMetadata,
  pausePositionRestoreTarget,
  practicePositionSnapshot,
  primarySourceCapo,
  resolvedCatalogScoreUrl,
  sourceCapoSummary,
  shouldKeepVerifiedPracticeScore,
  shouldIgnorePositionDuringSeek,
  trackVolumePercent,
} from '../src/lib/player/scorePlayerCorrectness.mjs';

test('track volume keeps a muted track at zero while defaulting missing values', () => {
  assert.equal(trackVolumePercent(0), 0);
  assert.equal(trackVolumePercent(-1), 0);
  assert.equal(trackVolumePercent(8), 50);
  assert.equal(trackVolumePercent(16), 100);
  assert.equal(trackVolumePercent(17), 100);
  assert.equal(trackVolumePercent(undefined), 100);
  assert.equal(trackVolumePercent(NaN), 100);
});

test('source capo capture and restore preserve different staves and support numeric override', () => {
  const sourceScore = { tracks: [
    { staves: [{ capo: 2 }, { capo: 4 }] },
    { staves: [{ capo: 0 }] },
  ] };
  const originals = captureSourceCapos(sourceScore);
  const rendered = structuredClone(sourceScore);
  applyCapoSelection(rendered, originals, { useSourceCapo: false, capo: 0 });
  assert.deepEqual(rendered.tracks.map((track) => track.staves.map((staff) => staff.capo)), [[0, 0], [0]]);

  applyCapoSelection(rendered, originals, { useSourceCapo: true, capo: 0 });
  assert.deepEqual(rendered.tracks.map((track) => track.staves.map((staff) => staff.capo)), [[2, 4], [0]]);
  assert.equal(primarySourceCapo(originals, 0), 2);
  assert.equal(sourceCapoSummary(originals), '第1轨 2品/4品；第2轨 不夹');
  assert.equal(formatCapoValue(9), '9品');
});

test('source capo capture defaults absent values to the score model default', () => {
  assert.deepEqual(captureSourceCapos({ tracks: [{ staves: [{}, { capo: null }] }] }), [[0, 0]]);
  assert.equal(sourceCapoSummary([[0], [0]]), '不夹');
});

test('an unverified catalog placeholder cannot replace the same verified score identity', () => {
  const verified = { id: 'catalog:a', source: 'catalog', sourceId: 'a', scoreUrl: '/tabs/a.ibe', revision: 'a'.repeat(64) };
  assert.equal(shouldKeepVerifiedPracticeScore(verified, { ...verified, revision: 'unverified' }), true);
  assert.equal(shouldKeepVerifiedPracticeScore(verified, { ...verified, sourceId: 'b', revision: 'unverified' }), false);
  assert.equal(shouldKeepVerifiedPracticeScore(verified, { ...verified, revision: 'b'.repeat(64) }), false);
  assert.equal(shouldKeepVerifiedPracticeScore({ ...verified, source: 'private' }, { ...verified, source: 'private', revision: 'unverified' }), false);
  const verifiedWithoutUrl = { ...verified, scoreUrl: undefined };
  assert.equal(shouldKeepVerifiedPracticeScore(verifiedWithoutUrl, { ...verifiedWithoutUrl, revision: 'unverified' }), true);
});

test('catalog request resolution keeps missing scoreUrl out of durable identity', () => {
  assert.equal(resolvedCatalogScoreUrl({ sourceId: 'practice id' }, '/fallback'), '/api/tabs/practice%20id/download');
  assert.equal(resolvedCatalogScoreUrl({ scoreUrl: '/custom.ibe', sourceId: 'catalog id' }, '/fallback'), '/custom.ibe');
  assert.equal(resolvedCatalogScoreUrl({}, '/fallback'), '/fallback');
});

test('practice snapshots prefer the last confirmed position over a preview and preserve natural end', () => {
  const confirmed = { tick: 422, timeMs: 3900 };
  const preview = { tick: 7680, timeMs: 0 };
  assert.deepEqual(practicePositionSnapshot(confirmed, preview), confirmed);
  assert.deepEqual(practicePositionSnapshot(confirmed, preview, { tick: 7680, timeMs: 62000 }), {
    tick: 7680, timeMs: 62000,
  });
  assert.deepEqual(practicePositionSnapshot(null, preview), preview);
});

test('seek metadata uses the current unfolded beat and exposes the score end as its exclusive end', () => {
  const masterBar = { index: 3, start: 5760, timeSignatureNumerator: 4, timeSignatureDenominator: 4,
    repeatGroup: { isOpened: true, masterBars: [{}, {}] } };
  const lookup = {
    end: 7680,
    beat: {
      playbackStart: 0,
      voice: { bar: { masterBar } },
    },
    masterBar: { masterBar },
  };
  assert.equal(beatLookupTick(7680, 7680), 7679);
  assert.deepEqual(positionBeatMetadata(lookup, 7680, 7680), {
    bar: 4, beat: 1, beatEndTick: 7680, repeatAmbiguous: true,
  });
  assert.deepEqual(positionBeatMetadata(lookup, 7681, 7680), {
    bar: 4, beat: 1, beatEndTick: 7680, repeatAmbiguous: true,
  });
});

test('seek metadata rounds fractional engine positions before looking up the beat', () => {
  const masterBar = { index: 3, start: 5760.25, timeSignatureNumerator: 4, timeSignatureDenominator: 4 };
  const lookup = {
    end: 7680.4,
    beat: { playbackStart: 0.25, voice: { bar: { masterBar } } },
    masterBar: { masterBar },
  };
  assert.equal(beatLookupTick(7679.7, 7680.2), 7679);
  assert.deepEqual(positionBeatMetadata(lookup, 7679.7, 7680.2), {
    bar: 4, beat: 1, beatEndTick: 7680, repeatAmbiguous: false,
  });
});

test('real AlphaTab JSON conversion and MIDI lookup report beat four in both passes of a repeated second bar', () => {
  const project = createBlankProject('guitar');
  project.bars[0].repeatStart = true;
  project.bars[1].repeatEnd = true;
  project.bars[1].repeatCount = 2;

  const sourceScore = studioProjectToAlphaTabScore(project);
  const serialized = alphaTab.model.JsonConverter.scoreToJson(sourceScore);
  const score = alphaTab.model.JsonConverter.jsonToScore(serialized, new alphaTab.Settings());
  const midiFile = new alphaTab.midi.MidiFile();
  const generator = new alphaTab.midi.MidiFileGenerator(
    score,
    new alphaTab.Settings(),
    new alphaTab.midi.AlphaSynthMidiFileHandler(midiFile),
  );
  generator.generate();

  const endTick = Math.max(...generator.tickLookup.masterBars.map((bar) => bar.end));
  const tracks = new Set([0]);
  const firstPass = generator.tickLookup.findBeat(tracks, 6720);
  const secondPass = generator.tickLookup.findBeat(tracks, 14400);

  assert.ok(firstPass);
  assert.ok(secondPass);
  assert.equal(firstPass.beat.playbackStart, 2880);
  assert.equal(firstPass.beat.absolutePlaybackStart, 6720);
  assert.deepEqual(positionBeatMetadata(firstPass, 6720, endTick), {
    bar: 2, beat: 4, beatEndTick: 7680, repeatAmbiguous: true,
  });
  assert.equal(secondPass.start, 14400);
  assert.equal(secondPass.end, 15360);
  assert.equal(secondPass.beat.playbackStart, 2880);
  const sourceBeatStart = generator.tickLookup.getBeatStart(secondPass.beat);
  assert.equal(generator.tickLookup.getBeatStart(firstPass.beat), firstPass.start);
  assert.equal(sourceBeatStart, firstPass.start);
  assert.notEqual(secondPass.start, sourceBeatStart);
  assert.deepEqual(positionBeatMetadata(secondPass, 14400, endTick), {
    bar: 2, beat: 4, beatEndTick: 15360, repeatAmbiguous: true,
  });
  assert.equal(pausePositionRestoreTarget({
    tick: 14500,
    unfoldedBeatStartTick: secondPass.start,
    sourceBeatStartTick: sourceBeatStart,
  }, 14500), 14500);
  assert.equal(pausePositionRestoreTarget({
    tick: 6800,
    unfoldedBeatStartTick: firstPass.start,
    sourceBeatStartTick: generator.tickLookup.getBeatStart(firstPass.beat),
  }, firstPass.start), null);
});

test('pause recovery uses repeated source mapping and active A/B bounds without trusting a stale tick getter', () => {
  const capture = {
    tick: 13026,
    unfoldedBeatStartTick: 12288,
    sourceBeatStartTick: 4800,
    rangeStartTick: 12288,
    rangeEndTick: 15360,
  };
  assert.equal(pausePositionRestoreTarget(capture, 4801), 13026);
  assert.equal(pausePositionRestoreTarget(capture, 13020), 13026);
  assert.equal(pausePositionRestoreTarget({
    ...capture,
    unfoldedBeatStartTick: 4800,
    sourceBeatStartTick: 4800,
  }, 13020), null);
  assert.equal(pausePositionRestoreTarget({ ...capture, tick: 11000 }, 4801), 11000);
  assert.equal(pausePositionRestoreTarget({
    tick: 13026,
    unfoldedBeatStartTick: 12288,
    sourceBeatStartTick: 4800,
    rangeStartTick: 12288,
    rangeEndTick: 15360,
  }, 2000), 13026);
  assert.equal(pausePositionRestoreTarget({
    tick: 13026,
    unfoldedBeatStartTick: null,
    sourceBeatStartTick: null,
    rangeStartTick: 12288,
    rangeEndTick: 15360,
  }, 2000), 13026);
});

test('seek metadata remains unknown when AlphaTab does not provide a valid beat boundary', () => {
  assert.deepEqual(positionBeatMetadata(null, 400, 7680), {
    bar: 0, beat: 0, beatEndTick: 0, repeatAmbiguous: false,
  });
  assert.deepEqual(positionBeatMetadata({
    beat: { playbackStart: 1920, voice: { bar: { masterBar: { index: 1, start: 1920 } } } },
    beatLookup: { end: 240 },
    masterBar: { start: 1920 },
  }, 1920, 3840), {
    bar: 0, beat: 0, beatEndTick: 0, repeatAmbiguous: false,
  });
  assert.equal(beatLookupTick(20, 0), 20);
});

test('a pending rapid seek ignores an earlier seek and ordinary playback positions', () => {
  const latestTarget = 7680;
  assert.equal(shouldIgnorePositionDuringSeek(latestTarget, { isSeek: true, currentTick: 0 }), true);
  assert.equal(shouldIgnorePositionDuringSeek(latestTarget, { isSeek: false, currentTick: 7679 }), true);
  assert.equal(shouldIgnorePositionDuringSeek(latestTarget, { isSeek: true, currentTick: 7679 }), false);
  assert.equal(shouldIgnorePositionDuringSeek(null, { isSeek: false, currentTick: 10 }), false);
});
