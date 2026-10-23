import assert from 'node:assert/strict';
import test from 'node:test';
import { studioCursorAtClientPoint, studioCursorFromBeat } from '../src/lib/studio/scoreBounds.ts';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';

test('AlphaTab beats map by their actual track, bar, and beat indexes', () => {
  const project = createBlankProject('band');
  const beat = {
    index: 2,
    voice: {
      bar: {
        masterBar: { index: 3 },
        staff: { track: { index: 2 } },
      },
    },
  };
  const actual = studioCursorFromBeat(beat, project, 1, { string: 3 });

  assert.deepEqual(actual, { trackIndex: 2, barIndex: 3, beatIndex: 2, stringIndex: 2 });
  assert.equal(studioCursorFromBeat({ ...beat, index: 99 }, project, 1), null);
});

test('partial SVG hit testing uses the shared AlphaTab renderer origin for later systems', () => {
  const project = createBlankProject('band');
  project.bars.length = 9;
  project.bars[8] = { ...project.bars[0], index: 8 };
  const rendererPoint = { x: 50.5, y: 860.25 };
  let lookupPoint = null;
  const beat = {
    index: 1,
    voice: { bar: { masterBar: { index: 8 }, staff: { track: { index: 1 } } } },
  };
  const partialSvgs = [
    { getBoundingClientRect: () => ({ left: 180, top: 130 }) },
    { getBoundingClientRect: () => ({ left: 205, top: 980 }) },
  ];
  const lookup = {
    getBeatAtPos(x, y) {
      lookupPoint = { x, y };
      // The second system starts at renderer y=820, while the selected partial
      // SVG's own y is 10.25; a per-SVG transform would hit the wrong system.
      return x >= 40 && x <= 60 && y >= 820 && y <= 900 ? beat : null;
    },
    getNoteAtPos(foundBeat, x, y) {
      assert.equal(foundBeat, beat);
      assert.deepEqual({ x, y }, rendererPoint);
      return { string: 5 };
    },
  };
  const surface = { getBoundingClientRect: () => ({ left: 180, top: 130 }) };
  // This screen point is in the second partial SVG, whose origin is x=25,y=850.
  const clientX = 180 + rendererPoint.x;
  const clientY = 130 + rendererPoint.y;
  const actual = studioCursorAtClientPoint(lookup, surface, clientX, clientY, project, 1);

  assert.deepEqual(lookupPoint, rendererPoint);
  assert.equal(partialSvgs[1].getBoundingClientRect().top - surface.getBoundingClientRect().top, 850);
  assert.deepEqual(actual, { trackIndex: 1, barIndex: 8, beatIndex: 1, stringIndex: 2 });
});

test('fractional viewport coordinates remain in AlphaTab surface CSS pixels', () => {
  const project = createBlankProject('guitar');
  const beat = { index: 0, voice: { bar: { masterBar: { index: 0 }, staff: { track: { index: 0 } } } } };
  let lookupPoint = null;
  const lookup = { getBeatAtPos(x, y) { lookupPoint = { x, y }; return beat; } };
  const surface = { getBoundingClientRect: () => ({ left: 101.5, top: 80.25 }) };
  const actual = studioCursorAtClientPoint(lookup, surface, 176.5, 980.75, project, 2);

  assert.deepEqual(lookupPoint, { x: 75, y: 900.5 });
  assert.deepEqual(actual, { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 2 });
});

test('bounds lookup misses remain misses instead of guessing a beat from bar pixels', () => {
  const project = createBlankProject('guitar');
  const surface = { getBoundingClientRect: () => ({ left: 10, top: 20 }) };
  assert.equal(studioCursorAtClientPoint({ getBeatAtPos: () => null }, surface, 24, 80, project, 2), null);
});
