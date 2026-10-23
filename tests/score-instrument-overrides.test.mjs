import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isUkulelePresetProgram, resolveResumeInstrument, sourceInstrumentFlavor } from '../src/lib/player/scoreInstrumentOverrides.ts';

test('only original Uke scores use the isolated Uke presets for programs 0, 24, and 25', () => {
  assert.equal(sourceInstrumentFlavor('ukulele', [69, 64, 60, 67], 0), 'ukulele');
  assert.equal(sourceInstrumentFlavor('ukulele', [69, 64, 60, 67], 24), 'ukulele');
  assert.equal(sourceInstrumentFlavor('ukulele', [69, 64, 60, 67], 25), 'ukulele');
  assert.equal(sourceInstrumentFlavor('ukulele', [69, 64, 60, 67], 105), 'gm');
  assert.equal(sourceInstrumentFlavor('ukulele', [69, 64, 60, 55, 50, 45], 25), 'gm');
  assert.equal(sourceInstrumentFlavor('', [69, 64, 60, 67], 25), 'gm');
  assert.equal(sourceInstrumentFlavor('guitar', [69, 64, 60, 67], 25), 'gm');
});

test('resume markers distinguish equal-number explicit GM choices from original source presets', () => {
  assert.deepEqual(resolveResumeInstrument(0, 0, true), { program: 0, instrumentOverride: true });
  assert.deepEqual(resolveResumeInstrument(0, 25, true), { program: 25, instrumentOverride: true });
  assert.deepEqual(resolveResumeInstrument(0, 25, false), { program: 0, instrumentOverride: false });
});

test('legacy resumes conservatively treat equal programs as source and differing programs as overrides', () => {
  assert.deepEqual(resolveResumeInstrument(24, 24), { program: 24, instrumentOverride: false });
  assert.deepEqual(resolveResumeInstrument(24, 0), { program: 0, instrumentOverride: true });
  assert.deepEqual(resolveResumeInstrument(24), { program: 24, instrumentOverride: false });
});

test('the isolated Uke preset set is exact', () => {
  assert.deepEqual([0, 24, 25].map(isUkulelePresetProgram), [true, true, true]);
  assert.equal(isUkulelePresetProgram(105), false);
});
