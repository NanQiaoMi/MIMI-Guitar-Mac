import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { GpStructureError, inspectEditableStringStructure, parseGpToIbe } from '../src/lib/gpUpload.ts';
import { decodeIbeToJsonNode } from '../src/lib/ibe.node.ts';
import { isOurFormat } from '../src/lib/ibe.ts';
import * as at from '@coderline/alphatab';

const canon = new Uint8Array(readFileSync(new URL('./fixtures/canon.gp5', import.meta.url)));
const chords = new Uint8Array(readFileSync(new URL('./fixtures/chords.gp5', import.meta.url)));

test('GP5 解析：canon 元数据正确', () => {
  const { meta, ibe } = parseGpToIbe(canon);
  assert.equal(meta.title, 'Canon Rock');
  assert.equal(meta.artist, 'JerryC');
  assert.equal(meta.tempo, 90);
  assert.equal(meta.hasTablature, true);
  assert.equal(meta.sheetForm, 4);
  assert.ok(isOurFormat(ibe));
});

test('GP5 解析：chords 小文件可解析且调弦可读', () => {
  const { meta, json } = parseGpToIbe(chords);
  assert.ok(Array.isArray(json.masterbars));
  assert.equal(json.masterbars.length, 2);
  assert.equal(typeof meta.tuningText, 'string');
  assert.ok(meta.tuningText.length > 0);
});

test('MIMI 编码往返：解码后官方解析为 Score', () => {
  const { ibe } = parseGpToIbe(canon);
  const decoded = decodeIbeToJsonNode(ibe);
  assert.equal(decoded.title, 'Canon Rock');
  const settings = new at.Settings();
  const score = at.model.JsonConverter.jsonToScore(JSON.stringify(decoded), settings);
  assert.equal(score.title, 'Canon Rock');
  assert.equal(score.tracks.length, 9);
});

test('非法文件抛出异常', () => {
  assert.throws(() => parseGpToIbe(new Uint8Array([1, 2, 3, 4, 5])));
});

const makeScore = (staff) => ({
  masterBars: [{}],
  tracks: [{ isPercussion: false, staves: [staff] }],
});
const makeStaff = ({ isStringed = true, showTablature = true, tuning = [64, 59, 55, 50, 45, 40], bars = [] } = {}) => ({
  isStringed,
  showTablature,
  tuning,
  bars,
});
const makeBar = (notes = []) => ({
  voices: [{ beats: [{ notes }] }],
});

test('结构校验接受带有效弦音符的六线谱', () => {
  const result = inspectEditableStringStructure(makeScore(makeStaff({ bars: [makeBar([{ string: 1, fret: 0 }])] })));
  assert.equal(result.editableTrackCount, 1);
  assert.equal(result.editableStaffCount, 1);
  assert.equal(result.editableBarCount, 1);
  assert.equal(result.editableNoteCount, 1);
});

test('结构校验拒绝空谱、无六线谱、无小节和无弦上音符', () => {
  const cases = [
    [{ tracks: [], masterBars: [] }, 'EMPTY_SCORE'],
    [makeScore(makeStaff({ showTablature: false })), 'NO_TABLATURE'],
    [makeScore(makeStaff({ isStringed: false })), 'NO_TABLATURE'],
    [makeScore(makeStaff()), 'NO_BARS'],
    [makeScore(makeStaff({ bars: [makeBar([{ string: 7, fret: 2 }])] })), 'NO_NOTES'],
  ];
  for (const [score, code] of cases) {
    assert.throws(() => inspectEditableStringStructure(score), (error) => {
      assert.ok(error instanceof GpStructureError);
      assert.equal(error.code, code);
      assert.ok(error.message.length > 0);
      return true;
    });
  }
});
