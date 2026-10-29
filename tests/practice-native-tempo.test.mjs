import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as alphaTab from '@coderline/alphatab';
import { nativeTempoAtTick } from '../src/lib/practice/nativeTempo.ts';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import { studioProjectToAlphaTabScore } from '../src/lib/studio/studioScoreBridge.ts';

test('native tempo resolves cold-start and exact changes from absolute playback ticks', () => {
  const bars = [
    { start: 0, end: 3840, tempoChanges: [{ tick: 0, tempo: 120 }, { tick: 1920, tempo: 160 }] },
    { start: 3840, end: 7680, tempoChanges: [{ tick: 3840, tempo: 160 }] },
  ];
  assert.equal(nativeTempoAtTick(bars, 0), 120);
  assert.equal(nativeTempoAtTick(bars, 1919), 120);
  assert.equal(nativeTempoAtTick(bars, 1920), 160);
  assert.equal(nativeTempoAtTick(bars, 960), 120);
  assert.equal(nativeTempoAtTick(bars, 3840), 160);
  assert.equal(nativeTempoAtTick(bars, 7680), null);
});

test('missing or corrupt native tempo remains unknown, never a guessed 80 BPM', () => {
  const bar = { start: 100, end: 200, tempoChanges: [{ tick: 100, tempo: 400 }] };
  assert.equal(nativeTempoAtTick([bar], 100), 400);
  for (const tick of [-1, NaN, Infinity, 99, 200]) assert.equal(nativeTempoAtTick([bar], tick), null);
  assert.equal(nativeTempoAtTick(null, 0), null);
  assert.equal(nativeTempoAtTick([], 0), null);
  for (const changes of [[], [{ tick: 150, tempo: 120 }], [{ tick: 100, tempo: NaN }],
    [{ tick: 100, tempo: 0 }], [{ tick: 100, tempo: 1001 }],
    [{ tick: 150, tempo: 100 }, { tick: 100, tempo: 120 }], [{ tick: 99, tempo: 120 }]]) {
    assert.equal(nativeTempoAtTick([{ ...bar, tempoChanges: changes }], 120), null);
  }
  assert.equal(nativeTempoAtTick([bar, { ...bar, start: 150, end: 300 }], 160), null);
});

test('installed AlphaTab tempo cache keeps repeat-pass tempo and within-bar automation', () => {
  const project = createBlankProject('guitar');
  project.initialTempo = 120;
  project.bars[0].repeatStart = true;
  project.bars[1].repeatEnd = true;
  project.bars[1].repeatCount = 2;
  project.bars[1].tempo = 160;
  const score = studioProjectToAlphaTabScore(project);
  const change = new alphaTab.model.Automation();
  change.type = alphaTab.model.AutomationType.Tempo;
  change.value = 200;
  change.ratioPosition = 0.5;
  score.masterBars[1].tempoAutomations.push(change);
  const midi = new alphaTab.midi.MidiFile();
  const generator = new alphaTab.midi.MidiFileGenerator(score, new alphaTab.Settings(), new alphaTab.midi.AlphaSynthMidiFileHandler(midi));
  generator.generate();
  const bars = generator.tickLookup.masterBars;
  assert.deepEqual(bars.map((bar) => bar.masterBar.index), [0, 1, 0, 1, 2, 3]);
  assert.equal(nativeTempoAtTick(bars, bars[0].start), 120);
  for (const bar of bars.filter((entry) => entry.masterBar.index === 1)) {
    assert.equal(nativeTempoAtTick(bars, bar.start), 160);
    assert.equal(nativeTempoAtTick(bars, bar.start + 1919), 160);
    assert.equal(nativeTempoAtTick(bars, bar.start + 1920), 200);
  }
  // The engine's actual repeat-pass map is authoritative, whether tempo resets
  // or carries from the preceding pass. Resolve its emitted first change.
  assert.equal(nativeTempoAtTick(bars, bars[2].start), bars[2].tempoChanges[0].tempo);
  assert.equal(nativeTempoAtTick(bars, bars.at(-1).end), null);
});
