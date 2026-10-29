import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeLyrics, normalizeScoreJson, sanitizeChords } from '../src/lib/ibe.ts';
import { keySignatureName, MAJOR_KEYS, relativeMinor } from '../src/lib/keyName.mjs';
import { totalTransposition, transposeKeyName } from '../src/lib/pitch.mjs';

function makeScore(opts = {}) {
  return {
    title: 'T',
    masterbars: [{ keysignature: 1, keysignaturetype: 0, timesignaturenumerator: 4, timesignaturedenominator: 4 }],
    tracks: [
      {
        name: 't1',
        staves: [
          {
            chords: opts.chords ?? {},
            bars: [
              {
                voices: [
                  {
                    beats: opts.beats ?? [],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  };
}

test('normalizeLyrics: 字符串数组原样保留（LyricsGlyph 按字符串渲染）', () => {
  assert.deepEqual(normalizeLyrics(['故', '事', '的']), ['故', '事', '的']);
});

test('normalizeLyrics: 对象数组抽取 text 为字符串，空数组不变', () => {
  assert.deepEqual(normalizeLyrics([{ text: '故', beats: 2 }]), ['故']);
  assert.deepEqual(normalizeLyrics([{ text: '故' }]), ['故']);
  assert.deepEqual(normalizeLyrics([]), []);
  assert.equal(normalizeLyrics(null), null);
});

test('normalizeScoreJson: 端到端歌词映射 + 无效和弦引用清空', () => {
  const src = makeScore({
    chords: { Em7: { name: 'Em7', firstfret: 1, strings: [0, 3, 0, 2, 2, 0] } },
    beats: [
      { id: 1, lyrics: ['故'], chordid: 'Em7' },
      { id: 2, lyrics: ['事'], chordid: 'NO_SUCH_CHORD' },
    ],
  });
  const out = normalizeScoreJson(src);
  const beats = out.tracks[0].staves[0].bars[0].voices[0].beats;
  assert.deepEqual(beats[0].lyrics, ['故']);
  assert.deepEqual(beats[1].lyrics, ['事']);
  assert.equal(beats[0].chordid, 'Em7');
  assert.equal(beats[1].chordid, undefined);
  assert.equal(out.tracks[0].staves[0].chords.Em7.name, 'Em7');
});

test('sanitizeChords: 畸形和弦丢弃并清空引用，有效和弦保留', () => {
  const score = makeScore({
    chords: {
      OK: { name: 'OK', firstfret: 1, strings: [0, 3, 0, 2, 2, 0] },
      BAD1: { name: 'BAD1', firstfret: null, strings: [0, 2] },
      BAD2: { name: 'BAD2', firstfret: 1, strings: [] },
      BAD3: { name: 'BAD3', firstfret: 1, strings: null },
      BAD4: { name: 'BAD4' },
    },
    beats: [
      { id: 1, chordid: 'OK' },
      { id: 2, chordid: 'BAD1' },
      { id: 3, chordid: 'BAD2' },
      { id: 4, chordid: 'BAD3' },
      { id: 5, chordid: 'BAD4' },
      { id: 6 },
    ],
  });
  sanitizeChords(score);
  const chords = score.tracks[0].staves[0].chords;
  assert.deepEqual(Object.keys(chords), ['OK']);
  const beats = score.tracks[0].staves[0].bars[0].voices[0].beats;
  assert.equal(beats[0].chordid, 'OK');
  assert.equal(beats[1].chordid, undefined);
  assert.equal(beats[2].chordid, undefined);
  assert.equal(beats[3].chordid, undefined);
  assert.equal(beats[4].chordid, undefined);
  assert.equal(beats[5].chordid, undefined);
});

test('sanitizeChords: 无 chords 对象时归一为空 map 且不崩溃', () => {
  const score = makeScore({});
  delete score.tracks[0].staves[0].chords;
  sanitizeChords(score);
  assert.deepEqual(score.tracks[0].staves[0].chords, {});
});

test('keySignatureName: 大调与关系小调映射', () => {
  assert.equal(MAJOR_KEYS[1], 'G');
  assert.equal(keySignatureName(0), 'C');
  assert.equal(keySignatureName(1), 'G');
  assert.equal(keySignatureName(2), 'D');
  assert.equal(keySignatureName(7), 'C#');
  assert.equal(keySignatureName(-1), 'F');
  assert.equal(keySignatureName(-2), 'Bb');
  assert.equal(keySignatureName(-3), 'Eb');
  assert.equal(keySignatureName(-5), 'Db');
  assert.equal(keySignatureName(1, 1), 'E'); // G 大调 → E 小调
  assert.equal(keySignatureName(-3, 1), 'C'); // Eb 大调 → C 小调
  assert.equal(keySignatureName(99), null);
});

test('relativeMinor: 大调 → 关系小调（升号记法）', () => {
  assert.equal(relativeMinor('C'), 'A');
  assert.equal(relativeMinor('G'), 'E');
  assert.equal(relativeMinor('D'), 'B');
  assert.equal(relativeMinor('F'), 'D');
  assert.equal(relativeMinor('Bb'), 'G');
  assert.equal(relativeMinor('F#'), 'D#');
  assert.equal(relativeMinor('Eb'), 'C');
  assert.equal(relativeMinor('XYZ'), null);
});

test('组合：keySignatureName + totalTransposition + transposeKeyName', () => {
  const songKey = keySignatureName(1); // G
  assert.equal(transposeKeyName(songKey, totalTransposition(3, 0, 0)), 'A#');
  assert.equal(transposeKeyName(songKey, totalTransposition(0, 0, 2)), 'A');
  assert.equal(transposeKeyName(songKey, totalTransposition(-1, 0, 0)), 'F#'); // 降半调
  assert.equal(transposeKeyName('Eb', totalTransposition(0, 0, 3)), 'F#');
  assert.equal(transposeKeyName('G', 0), 'G');
});
