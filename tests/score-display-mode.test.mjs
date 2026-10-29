import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SCORE_DISPLAY_MODES,
  DEFAULT_SCORE_DISPLAY_MODE,
  resolveStaveDisplay,
  applyScoreDisplayMode,
  countTabTracks,
  hasTuning,
  hasWholeRestCrash,
  canUseMixedMode,
  replaceWholeRestsInSecondaryTracks,
  scoreDisplayModeLabel,
} from '../src/lib/scoreDisplayMode.mjs';

function stave(tuningLen, opts = {}) {
  const bars = opts.bars ?? [];
  return { stringTuning: { tunings: Array.from({ length: tuningLen }, (_, i) => 40 + i) }, bars };
}
function jsonStave(tuningLen, opts = {}) {
  const bars = opts.bars ?? [];
  return { stringtuning: { tunings: Array.from({ length: tuningLen }, (_, i) => 40 + i) }, bars };
}
function restBar(duration, isRest = true) {
  return { voices: [{ beats: [{ isRest, duration, notes: [] }] }] };
}
function jsonRestBar(duration) {
  return { voices: [{ beats: [{ duration, notes: [], isempty: false }] }] };
}
function noteBar() {
  return { voices: [{ beats: [{ isRest: false, duration: 4, notes: [{ fret: 3, string: 1 }] }] }] };
}
function track(...staves) {
  return { staves };
}
function score(tracks) {
  return { tracks };
}
function jsonScore(tracks) {
  return { tracks };
}

test('default mode is mixed (primary track tab + other tracks jianpu)', () => {
  assert.equal(DEFAULT_SCORE_DISPLAY_MODE, SCORE_DISPLAY_MODES.MIXED);
});

test('scoreDisplayModeLabel maps both modes', () => {
  assert.ok(scoreDisplayModeLabel(SCORE_DISPLAY_MODES.MIXED).length > 0);
  assert.ok(scoreDisplayModeLabel(SCORE_DISPLAY_MODES.ALL_TAB).length > 0);
});

test('hasTuning supports model (camelCase) and normalized JSON (lowercase) keys', () => {
  assert.equal(hasTuning({ stringTuning: { tunings: [1, 2, 3] } }), true);
  assert.equal(hasTuning({ stringtuning: { tunings: [1, 2, 3] } }), true);
  assert.equal(hasTuning({ stringTuning: { tunings: [] } }), false);
  assert.equal(hasTuning(null), false);
});

test('countTabTracks counts tracks that have a tuned stave', () => {
  assert.equal(countTabTracks(score([track(stave(6)), track(stave(0))])), 1);
  assert.equal(countTabTracks(score([track(stave(6)), track(stave(6))])), 2);
  assert.equal(countTabTracks(null), 0);
});

test('hasWholeRestCrash detects duration=1 rest beats on the model (diagnostic only)', () => {
  assert.equal(hasWholeRestCrash(stave(6, { bars: [restBar(1)] })), true);
  assert.equal(hasWholeRestCrash(stave(6, { bars: [restBar(2), restBar(4), restBar(8)] })), false);
  assert.equal(hasWholeRestCrash(stave(6, { bars: [noteBar(), restBar(1)] })), true);
  assert.equal(hasWholeRestCrash(stave(6, { bars: [] })), false);
  assert.equal(hasWholeRestCrash(null), false);
});

test('canUseMixedMode requires at least 2 tuned tracks', () => {
  assert.equal(canUseMixedMode(score([track(stave(6)), track(stave(6))])), true);
  assert.equal(canUseMixedMode(score([track(stave(6)), track(stave(6, { bars: [restBar(1)] }))])), true);
  assert.equal(canUseMixedMode(score([track(stave(6)), track(stave(0))])), false);
  assert.equal(canUseMixedMode(score([track(stave(6))])), false);
  assert.equal(canUseMixedMode(null), false);
  assert.equal(canUseMixedMode({}), false);
});

test('resolveStaveDisplay: tab mode keeps all tuned staves as tab', () => {
  assert.deepEqual(resolveStaveDisplay('tab', 0, 0, true), { showTablature: true, showNumbered: false });
  assert.deepEqual(resolveStaveDisplay('tab', 1, 0, true), { showTablature: true, showNumbered: false });
  assert.deepEqual(resolveStaveDisplay('tab', 1, 0, false), { showTablature: false, showNumbered: true });
});

test('resolveStaveDisplay: mixed mode only renders the first tuned track as tab', () => {
  assert.deepEqual(resolveStaveDisplay('mixed', 0, 0, true), { showTablature: true, showNumbered: false });
  assert.deepEqual(resolveStaveDisplay('mixed', 1, 0, true), { showTablature: false, showNumbered: true });
  assert.deepEqual(resolveStaveDisplay('mixed', 0, 0, false), { showTablature: false, showNumbered: true });
  assert.deepEqual(resolveStaveDisplay('mixed', 1, 1, true), { showTablature: true, showNumbered: false });
});

test('applyScoreDisplayMode: anheqiao style (two tuned guitar tracks)', () => {
  const sc = score([track(stave(6)), track(stave(6))]);
  applyScoreDisplayMode(sc, SCORE_DISPLAY_MODES.MIXED);
  assert.equal(sc.tracks[0].staves[0].showTablature, true);
  assert.equal(sc.tracks[1].staves[0].showTablature, false);
  assert.equal(sc.tracks[1].staves[0].showNumbered, true);
  applyScoreDisplayMode(sc, SCORE_DISPLAY_MODES.ALL_TAB);
  assert.equal(sc.tracks[0].staves[0].showTablature, true);
  assert.equal(sc.tracks[1].staves[0].showTablature, true);
  assert.equal(sc.tracks[1].staves[0].showNumbered, false);
});

test('applyScoreDisplayMode: qingtian style (guitar + piano) renders equivalently in both modes', () => {
  const mk = () => score([track(stave(6)), track(stave(0))]);
  const a = mk();
  applyScoreDisplayMode(a, 'mixed');
  const b = mk();
  applyScoreDisplayMode(b, 'tab');
  assert.equal(a.tracks[0].staves[0].showTablature, true);
  assert.equal(a.tracks[1].staves[0].showTablature, false);
  assert.equal(a.tracks[1].staves[0].showNumbered, true);
  assert.equal(b.tracks[0].staves[0].showTablature, true);
  assert.equal(b.tracks[1].staves[0].showTablature, false);
  assert.equal(b.tracks[1].staves[0].showNumbered, true);
});

test('applyScoreDisplayMode: primary track is the first tuned track, not necessarily track 0', () => {
  const sc = score([track(stave(0)), track(stave(6))]);
  applyScoreDisplayMode(sc, 'mixed');
  assert.equal(sc.tracks[0].staves[0].showNumbered, true);
  assert.equal(sc.tracks[0].staves[0].showTablature, false);
  assert.equal(sc.tracks[1].staves[0].showTablature, true);
  assert.equal(sc.tracks[1].staves[0].showNumbered, false);
});

test('applyScoreDisplayMode: null/empty score is safe', () => {
  assert.doesNotThrow(() => applyScoreDisplayMode(null, 'mixed'));
  assert.doesNotThrow(() => applyScoreDisplayMode({}, 'mixed'));
});

// --- replaceWholeRestsInSecondaryTracks (JSON-level, before JsonConverter) ---

test('replaceWholeRests: replaces whole rests in secondary tuned tracks with 4 quarter rests', () => {
  const j = jsonScore([track(jsonStave(6)), track(jsonStave(6, { bars: [jsonRestBar(1)] }))]);
  const n = replaceWholeRestsInSecondaryTracks(j);
  assert.equal(n, 1);
  const beats = j.tracks[1].staves[0].bars[0].voices[0].beats;
  assert.equal(beats.length, 4);
  assert.ok(beats.every((b) => b.duration === 4));
  assert.ok(beats.every((b) => Array.isArray(b.notes) && b.notes.length === 0));
});

test('replaceWholeRests: detects whole rests by empty notes (corpus has no isrest key)', () => {
  const j = jsonScore([track(jsonStave(6)), track(jsonStave(6, { bars: [jsonRestBar(1)] }))]);
  const n = replaceWholeRestsInSecondaryTracks(j);
  assert.equal(n, 1);
  assert.equal(j.tracks[1].staves[0].bars[0].voices[0].beats.length, 4);
});

test('replaceWholeRests: keeps text annotation only on the first clone', () => {
  const j = jsonScore([
    track(jsonStave(6)),
    track(jsonStave(6, { bars: [{ voices: [{ beats: [{ duration: 1, notes: [], isempty: false, text: 'Strum = 16-2' }] }] }] })),
  ]);
  replaceWholeRestsInSecondaryTracks(j);
  const beats = j.tracks[1].staves[0].bars[0].voices[0].beats;
  assert.equal(beats.length, 4);
  assert.equal(beats[0].text, 'Strum = 16-2');
  assert.equal(beats[1].text, null);
  assert.equal(beats[2].text, null);
  assert.equal(beats[3].text, null);
});

test('replaceWholeRests: leaves the primary (first tuned) track untouched', () => {
  const j = jsonScore([track(jsonStave(6, { bars: [jsonRestBar(1)] })), track(jsonStave(6, { bars: [jsonRestBar(1)] }))]);
  const n = replaceWholeRestsInSecondaryTracks(j);
  assert.equal(n, 1);
  assert.equal(j.tracks[0].staves[0].bars[0].voices[0].beats.length, 1);
  assert.equal(j.tracks[1].staves[0].bars[0].voices[0].beats.length, 4);
});

test('replaceWholeRests: leaves untuned-only scores and single-track scores unchanged', () => {
  const j = jsonScore([track(jsonStave(0, { bars: [jsonRestBar(1)] })), track(jsonStave(0, { bars: [jsonRestBar(1)] }))]);
  assert.equal(replaceWholeRestsInSecondaryTracks(j), 0);
  assert.equal(j.tracks[0].staves[0].bars[0].voices[0].beats.length, 1);
  const single = jsonScore([track(jsonStave(6, { bars: [jsonRestBar(1)] }))]);
  assert.equal(replaceWholeRestsInSecondaryTracks(single), 0);
  assert.equal(single.tracks[0].staves[0].bars[0].voices[0].beats.length, 1);
});

test('replaceWholeRests: quarter/eighth rests are not touched', () => {
  const j = jsonScore([
    track(jsonStave(6)),
    track(jsonStave(6, { bars: [{ voices: [{ beats: [{ duration: 4, notes: [], isempty: false }, { duration: 8, notes: [], isempty: false }] }] }] })),
  ]);
  const n = replaceWholeRestsInSecondaryTracks(j);
  assert.equal(n, 0);
  assert.equal(j.tracks[1].staves[0].bars[0].voices[0].beats.length, 2);
});

test('replaceWholeRests: null/empty input is safe and returns 0', () => {
  assert.equal(replaceWholeRestsInSecondaryTracks(null), 0);
  assert.equal(replaceWholeRestsInSecondaryTracks({}), 0);
  assert.equal(replaceWholeRestsInSecondaryTracks({ tracks: [] }), 0);
});

test('replaceWholeRests: idempotent (running twice does not multiply clones)', () => {
  const j = jsonScore([track(jsonStave(6)), track(jsonStave(6, { bars: [jsonRestBar(1)] }))]);
  replaceWholeRestsInSecondaryTracks(j);
  const n2 = replaceWholeRestsInSecondaryTracks(j);
  assert.equal(n2, 0);
  assert.equal(j.tracks[1].staves[0].bars[0].voices[0].beats.length, 4);
});

