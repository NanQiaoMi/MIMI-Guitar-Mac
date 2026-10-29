import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildManuscriptBeatBarIndex,
  resolveManuscriptBarIndexForBeatGroup,
} from '../src/lib/player/manuscriptBeatBars.mjs';

function beat(id) {
  return { id };
}

function bar(index, ...beats) {
  return { index, voices: [{ beats }] };
}

function track(...bars) {
  return { staves: [{ bars }] };
}

test('maps AlphaTab beat ids to source bar indices across tracks, staves, and voices', () => {
  const scoreTracks = [
    track(bar(0, beat(360838), beat(360839)), bar(1, beat(360840))),
    {
      staves: [
        { bars: [{ index: 0, voices: [{ beats: [beat(360841)] }, { beats: [beat(360842)] }] }] },
        { bars: [bar(1, beat(360843))] },
      ],
    },
  ];
  const mapping = buildManuscriptBeatBarIndex(scoreTracks);

  assert.equal(resolveManuscriptBarIndexForBeatGroup('b360838', mapping), 0);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b360839', mapping), 0);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('staff b360840 selected', mapping), 1);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b360842', mapping), 0);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b360843', mapping), 1);
});

test('resolves an SVG token only as a beat id, never as a raw bar index', () => {
  const mapping = buildManuscriptBeatBarIndex([
    track(bar(2, beat(8), beat(360838)), bar(9, beat(90))),
  ]);

  assert.equal(resolveManuscriptBarIndexForBeatGroup('b360838', mapping), 2);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b8', mapping), 2);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b90', mapping), 9);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b9', mapping), null);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('not-a-beat-b2', mapping), null);
});

test('rejects an id that resolves to different bars instead of choosing one track', () => {
  const mapping = buildManuscriptBeatBarIndex([
    track(bar(3, beat(42))),
    track(bar(9, beat(42))),
  ]);

  assert.equal(mapping.has(42), false);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b42', mapping), null);
});

test('keeps mappings local to each rendered score when AlphaTab reuses an id', () => {
  const firstScore = buildManuscriptBeatBarIndex([track(bar(4, beat(7)))]);
  const secondScore = buildManuscriptBeatBarIndex([track(bar(11, beat(7)))]);

  assert.equal(resolveManuscriptBarIndexForBeatGroup('b7', firstScore), 4);
  assert.equal(resolveManuscriptBarIndexForBeatGroup('b7', secondScore), 11);
});
