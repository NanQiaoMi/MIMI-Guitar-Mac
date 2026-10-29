import assert from 'node:assert/strict';
import test from 'node:test';
import * as alphaTab from '@coderline/alphatab';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeIbeToJsonNode, encodeJsonToIbeNode } from '../src/lib/ibe.node.ts';
import { convertSongsterrToAlphaTex, ingestSongFromSongsterr, searchSongsterr, selectSongsterrTrackIndex } from '../src/lib/musicResourceCollector.ts';

installNodeAr();

test('Songsterr guitar track selection preserves valid zero-based indexes and skips vocals', () => {
  const metadata = {
    popularTrackGuitar: 1,
    tracks: [
      { instrument: 'Voice Oohs', name: 'Backing vocals' },
      { instrument: 'Acoustic Guitar (steel)', name: 'Rhythm guitar' },
      { instrument: 'Drums', name: 'Kit' },
    ],
  };
  assert.equal(selectSongsterrTrackIndex(metadata), 1);
  assert.equal(selectSongsterrTrackIndex(metadata, 0), 1);
  assert.equal(selectSongsterrTrackIndex({ popularTrackGuitar: 0, tracks: [{ instrument: 'Acoustic Guitar' }] }), 0);
  assert.equal(selectSongsterrTrackIndex({ tracks: metadata.tracks }), 1);
});

test('Songsterr conversion maps strings, rests, tuning, key, meter, tempo, tuplets and warnings', () => {
  const sourceTrack = {
    instrument: 'Acoustic Guitar (steel)',
    strings: 6,
    tuning: [64, 59, 55, 50, 45, 40],
    capo: 2,
    automations: { tempo: [
      { measure: 0, position: 0, bpm: 90, type: 4 },
      { measure: 0, position: 0.5, bpm: 96, type: 4 },
    ] },
    measures: [{
      signature: [3, 4],
      keySignature: { accidentalCount: 0, mode: 'major' },
      marker: { text: 'Intro' },
      voices: [{ beats: [
        { duration: [1, 4], type: 4, notes: [{ fret: 0, string: 0 }] },
        { duration: [3, 16], type: 8, notes: [{ fret: 2, string: 5, slide: true }] },
        { duration: [1, 12], type: 8, notes: [{ fret: 1, string: 2 }] },
        { duration: [1, 4], type: 4, notes: [{ rest: true }] },
        { duration: [1, 4], type: 4, notes: [{ fret: 3, string: 8 }] },
      ] }],
    }],
  };

  const converted = convertSongsterrToAlphaTex({ title: 'Source Test', artist: 'MIMI' }, sourceTrack);
  assert.match(converted.alphaTex, /\\tuning e4 b3 g3 d3 a2 e2/);
  assert.match(converted.alphaTex, /\\tempo 90/);
  assert.match(converted.alphaTex, /\\tempo \(96 "" 0\.5\)/);
  assert.match(converted.alphaTex, /\\ts 3 4/);
  assert.match(converted.alphaTex, /\\ks cmajor/);
  assert.equal(converted.key, 'C major');
  assert.match(converted.alphaTex, /\\section "Intro"/);
  assert.match(converted.alphaTex, /:8 2\.6 \{ d \}/);
  assert.match(converted.alphaTex, /:8 1\.3 \{ tu 3 2 \}/);
  assert.deepEqual(converted.warnings, [
    '1 个音符缺少有效品位或弦位，已跳过',
    '以下技法尚未映射到 AlphaTex：slide',
  ]);

  const encoded = encodeJsonToIbeNode({
    title: 'Source Test',
    artist: 'MIMI',
    tempo: converted.bpm,
    capo: converted.capo,
    alphaTex: converted.alphaTex,
    tracks: [{ name: 'Acoustic Guitar', tuning: sourceTrack.tuning, measuresCount: converted.measuresCount }],
  });
  const decoded = decodeIbeToJsonNode(encoded);
  const score = alphaTab.model.JsonConverter.jsonToScore(JSON.stringify(decoded), new alphaTab.Settings());
  assert.equal(decoded.masterbars.length, 1);
  assert.equal(score.tracks[0].staves[0].bars[0].voices[0].beats.length, 5);
  const notes = score.tracks[0].staves[0].bars[0].voices[0].beats.flatMap((beat) => beat.notes);
  assert.deepEqual(notes.slice(0, 3).map((note) => note.string), [6, 1, 4]);
  assert.deepEqual(notes.slice(0, 3).map((note) => note.stringTuning), [66, 42, 57]);
});

test('external collection entry points are closed without making network requests', async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalls = 0;
  globalThis.fetch = async () => { fetchCalls++; throw new Error('unexpected external call'); };
  try {
    await assert.rejects(searchSongsterr('example'), { status: 503, name: 'ScoreSourceError' });
    await assert.rejects(ingestSongFromSongsterr(123), { status: 503, name: 'ScoreSourceError' });
    assert.equal(fetchCalls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Songsterr conversion rejects empty tracks instead of saving an unreadable source', () => {
  assert.throws(() => convertSongsterrToAlphaTex({}, { measures: [] }), /没有可转换的小节/);
});
