import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addLyricsTopSpacer } from '../src/lib/scoreLyricsLayout.mjs';

function makeScore(lyrics) {
  return {
    tracks: [{
      staves: [{
        bars: [{
          voices: [{ beats: [{ lyrics }] }],
        }],
      }],
    }],
  };
}

function firstBeat(score) {
  return score.tracks[0].staves[0].bars[0].voices[0].beats[0];
}

test('addLyricsTopSpacer: visible lyrics receive one leading layout-only row', () => {
  const score = makeScore(['好']);
  assert.equal(addLyricsTopSpacer(score), 1);
  assert.deepEqual(firstBeat(score).lyrics, ['', '好']);
});

test('addLyricsTopSpacer: preserves multi-line lyrics and is idempotent', () => {
  const score = makeScore(['Verse 1', 'Verse 2']);
  assert.equal(addLyricsTopSpacer(score), 1);
  assert.deepEqual(firstBeat(score).lyrics, ['', 'Verse 1', 'Verse 2']);
  assert.equal(addLyricsTopSpacer(score), 0);
  assert.deepEqual(firstBeat(score).lyrics, ['', 'Verse 1', 'Verse 2']);
});

test('addLyricsTopSpacer: leaves empty, already-spaced, and malformed lyrics untouched', () => {
  for (const lyrics of [[], ['', '好'], [' '], null, { text: '好' }]) {
    const score = makeScore(lyrics);
    assert.equal(addLyricsTopSpacer(score), 0);
    assert.deepEqual(firstBeat(score).lyrics, lyrics);
  }
});
