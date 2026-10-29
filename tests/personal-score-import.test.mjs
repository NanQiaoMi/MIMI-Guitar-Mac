import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as alphaTab from '@coderline/alphatab';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeIbeToJsonNode } from '../src/lib/ibe.node.ts';
import { prepareLocalScore } from '../src/lib/personal/importLocalScore.ts';

installNodeAr();

function noteCount(score) {
  return score.tracks.reduce((tracks, track) => tracks + track.staves.reduce((staves, staff) => staves + staff.bars.reduce((bars, bar) => bars + bar.voices.reduce((voices, voice) => voices + voice.beats.reduce((beats, beat) => beats + beat.notes.length, 0), 0), 0), 0), 0);
}

test('GP5 personal import retains every track, bar, and note through playable IBE round trip', async () => {
  const bytes = new Uint8Array(readFileSync(new URL('./fixtures/canon.gp5', import.meta.url)));
  const settings = new alphaTab.Settings();
  settings.player.enablePlayer = false;
  const originalScore = alphaTab.importer.ScoreLoader.loadScoreFromBytes(bytes, settings);
  const prepared = await prepareLocalScore(new File([bytes], 'canon.gp5'));
  const playableJson = decodeIbeToJsonNode(prepared.playableBytes);
  const roundTripped = alphaTab.model.JsonConverter.jsonToScore(JSON.stringify(playableJson), settings);

  assert.equal(prepared.sourceFormat, 'gp');
  assert.equal(prepared.scoreJson.tracks.length, originalScore.tracks.length);
  assert.equal(prepared.scoreJson.masterbars.length, originalScore.masterBars.length);
  assert.equal(roundTripped.tracks.length, originalScore.tracks.length);
  assert.equal(roundTripped.masterBars.length, originalScore.masterBars.length);
  assert.equal(noteCount(roundTripped), noteCount(originalScore));
});

test('empty, unsupported, and oversized score imports fail before producing a playable score', async () => {
  await assert.rejects(prepareLocalScore(new File([], 'empty.ibe')), /文件为空/);
  await assert.rejects(prepareLocalScore(new File([new Uint8Array([1, 2, 3])], 'bad.mid')), /支持/);
  await assert.rejects(prepareLocalScore(new File([new Uint8Array(30 * 1024 * 1024 + 1)], 'large.gp5')), /超过 30 MiB/);
});
