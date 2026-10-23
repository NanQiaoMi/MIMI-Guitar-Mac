import test from 'node:test';
import assert from 'node:assert/strict';
import {
  hasScoreAuditionNotes,
  hasScoreAuditionMelodicNotes,
  planScoreAuditionSoundfonts,
  resolveScoreAuditionSoundfontUrls,
  resolveScoreAuditionSourceFlavor,
  resolveScoreAuditionSource,
} from '../src/lib/player/scoreAuditionResources.ts';
import {
  SCORE_GM_SOUNDFONT_URL,
  SCORE_UKULELE_SOUNDFONT_URL,
} from '../src/lib/player/verifiedScoreSoundfont.ts';

test('audition source uses only an explicit IBE path whose file identity matches the selected song', () => {
  assert.deepEqual(resolveScoreAuditionSource({
    id: '1wmj8hqHnYf',
    title: '萱草花',
    format: 'gp',
    scoreUrl: '/storage/scores/1wmj8hqHnYf.ibe',
  }), { ok: true, url: '/storage/scores/1wmj8hqHnYf.ibe' });

  assert.deepEqual(resolveScoreAuditionSource({
    id: '1wmj8hqHnYf',
    title: '萱草花',
    format: 'gp',
    scoreUrl: '/storage/scores/1yDFAg9Z3mU.ibe',
  }), { ok: false, reason: 'score-id-mismatch' });
  assert.deepEqual(resolveScoreAuditionSource({ id: 'letting-go-01' }), { ok: false, reason: 'missing-score' });
});

test('XHE-only, external, traversal, query, and malformed sources fail without a fallback', () => {
  assert.deepEqual(resolveScoreAuditionSource({
    id: 'song-1', format: 'xhe', scoreUrl: '/storage/scores/song-1.ibe',
  }), { ok: false, reason: 'unsupported-format' });
  for (const scoreUrl of [
    'https://example.test/song-1.ibe',
    '//example.test/song-1.ibe',
    '/storage/scores/../other.ibe',
    '/storage/scores/song-1.ibe?copy=2',
    '/storage/xhe/song-1.xhe',
  ]) {
    assert.deepEqual(resolveScoreAuditionSource({ id: 'song-1', format: 'gp', scoreUrl }), {
      ok: false,
      reason: 'unsafe-url',
    });
  }
  assert.deepEqual(resolveScoreAuditionSource({ id: '../song', scoreUrl: '/storage/scores/song.ibe' }), {
    ok: false,
    reason: 'missing-id',
  });
});

test('all GM programs and percussion resolve to the complete verified Sonivox bank', () => {
  const guitarWithPianoAutomation = {
    playbackInfo: { program: 25 },
    staves: [{
      tuning: [64, 59, 55, 50, 45, 40],
      bars: [{ voices: [{ beats: [{ automations: [
        { type: 2, value: 0 },
        { type: 0, value: 120 },
        { type: 'Instrument', value: 25 },
      ] }] }] }],
    }],
  };
  const piano = { playbackInfo: { program: 0 }, staves: [{ tuning: [], bars: [] }] };
  const drums = {
    isPercussion: true,
    playbackInfo: { program: 0 },
    staves: [{ isPercussion: true, tuning: [], bars: [] }],
  };

  const plan = planScoreAuditionSoundfonts([guitarWithPianoAutomation, piano, drums]);
  assert.equal(plan.ok, true);
  assert.deepEqual(plan.presets, [
    { bank: 0, program: 0, flavor: 'gm' },
    { bank: 0, program: 25, flavor: 'gm' },
    { bank: 128, program: 0, flavor: 'gm' },
  ]);
  assert.deepEqual(plan.urls, [SCORE_GM_SOUNDFONT_URL]);
  assert.deepEqual(resolveScoreAuditionSoundfontUrls([guitarWithPianoAutomation, piano, drums]), [SCORE_GM_SOUNDFONT_URL]);
});

test('source Uke detection requires category, four strings, and an original Uke program', () => {
  const source = { playbackInfo: { program: 25 }, staves: [{ tuning: [67, 60, 64, 69], bars: [] }] };
  assert.equal(resolveScoreAuditionSourceFlavor(source, 'ukulele'), 'ukulele');
  assert.equal(resolveScoreAuditionSourceFlavor(source, 'guitar'), 'gm');
  assert.equal(resolveScoreAuditionSourceFlavor({ ...source, staves: [{ tuning: [64, 59, 55, 50, 45, 40] }] }, 'ukulele'), 'gm');
  assert.equal(resolveScoreAuditionSourceFlavor({ ...source, playbackInfo: { program: 0 } }, 'ukulele'), 'ukulele');
  assert.equal(resolveScoreAuditionSourceFlavor({ ...source, playbackInfo: { program: 26 } }, 'ukulele'), 'gm');
});

test('planner trusts only the runtime flavor marker; missing and invalid markers default to GM', () => {
  const sourceUke = { playbackInfo: { program: 24 }, staves: [{ tuning: [67, 60, 64, 69], bars: [] }], mimiSoundfontFlavor: 'ukulele' };
  const explicitGm = { ...sourceUke, mimiSoundfontFlavor: 'gm' };
  const plan = planScoreAuditionSoundfonts([sourceUke, explicitGm]);
  assert.deepEqual(plan, { ok: false, reason: 'conflicting-program', bank: 0, program: 24 });

  assert.deepEqual(planScoreAuditionSoundfonts([
    { playbackInfo: { program: 0 }, staves: [{ tuning: [67, 60, 64, 69], bars: [] }] },
  ], 'ukulele'), {
    ok: true,
    presets: [{ bank: 0, program: 0, flavor: 'gm' }],
    urls: [SCORE_GM_SOUNDFONT_URL],
  });
});

test('only explicitly marked Uke presets are isolated; unsupported Uke programs use their exact GM program', () => {
  const sourceUke = { playbackInfo: { program: 25 }, staves: [{ tuning: [67, 60, 64, 69], bars: [] }], mimiSoundfontFlavor: 'ukulele' };
  const plan = planScoreAuditionSoundfonts([sourceUke]);
  assert.deepEqual(plan, {
    ok: true,
    presets: [{ bank: 0, program: 25, flavor: 'ukulele' }],
    urls: [SCORE_UKULELE_SOUNDFONT_URL],
  });
  const withAutomation = planScoreAuditionSoundfonts([{
    ...sourceUke,
    staves: [{ tuning: [67, 60, 64, 69], bars: [{ voices: [{ beats: [{ automations: [{ type: 2, value: 25 }, { type: 2, value: 30 }] }] }] }] }],
  }]);
  assert.deepEqual(withAutomation.presets, [
    { bank: 0, program: 30, flavor: 'gm' },
    { bank: 0, program: 25, flavor: 'ukulele' },
  ]);
  assert.deepEqual(withAutomation.urls, [SCORE_GM_SOUNDFONT_URL, SCORE_UKULELE_SOUNDFONT_URL]);
});

test('score audibility check distinguishes a real note from empty or rest-only tracks', () => {
  const restOnly = [{ staves: [{ bars: [{ voices: [{ beats: [{ notes: [] }] }] }] }] }];
  const withNotes = [{ staves: [{ bars: [{ voices: [{ beats: [{ notes: [{ realValue: 64 }] }] }] }] }] }];
  const drumsOnly = [{
    isPercussion: true,
    staves: [{
      isPercussion: true,
      bars: [{ voices: [{ beats: [{ notes: [{ realValue: 36 }] }] }] }],
    }],
  }];
  const mixed = [drumsOnly[0], withNotes[0]];
  assert.equal(hasScoreAuditionNotes([]), false);
  assert.equal(hasScoreAuditionNotes(restOnly), false);
  assert.equal(hasScoreAuditionNotes(withNotes), true);
  assert.equal(hasScoreAuditionNotes(drumsOnly), true);
  assert.equal(hasScoreAuditionMelodicNotes(drumsOnly), false);
  assert.equal(hasScoreAuditionMelodicNotes(mixed), true);
});
