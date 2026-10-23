import test from 'node:test';
import assert from 'node:assert/strict';
import { bassArticulationBoost, applyVelocityBoostToMidi } from '../src/lib/bassArticulation.mjs';

test('bassArticulationBoost: slap/pop/tap 增量与无技巧返回 0', () => {
  assert.equal(bassArticulationBoost({ slap: true }), 22);
  assert.equal(bassArticulationBoost({ pop: true }), 18);
  assert.equal(bassArticulationBoost({ tap: true }), 10);
  assert.equal(bassArticulationBoost({}), 0);
  assert.equal(bassArticulationBoost(null), 0);
  assert.equal(bassArticulationBoost({ slap: true, pop: true }), 22); // slap 优先
});

test('applyVelocityBoostToMidi: format0 单 track + 事件 track 字段', () => {
  const midi = {
    tracks: [{ events: [
      { track: 7, type: 128, tick: 480, noteVelocity: 79 },   // 命中 track7
      { track: 7, type: 128, tick: 960, noteVelocity: 79 },   // 未命中
      { track: 7, type: 144, tick: 480, noteVelocity: 0 },    // NoteOff 不动
      { track: 0, type: 128, tick: 480, noteVelocity: 79 },   // 其他轨不动
    ] }],
  };
  const boostMap = new Map([[7, new Map([[480, 22]])]]);
  applyVelocityBoostToMidi(midi, boostMap);
  assert.equal(midi.tracks[0].events[0].noteVelocity, 101);
  assert.equal(midi.tracks[0].events[1].noteVelocity, 79);
  assert.equal(midi.tracks[0].events[2].noteVelocity, 0);
  assert.equal(midi.tracks[0].events[3].noteVelocity, 79);
});

test('applyVelocityBoostToMidi: format1 多 track 也生效', () => {
  const midi = {
    tracks: [
      { events: [{ track: 0, type: 128, tick: 480, noteVelocity: 60 }] },
      { events: [{ track: 7, type: 128, tick: 480, noteVelocity: 60 }] },
    ],
  };
  applyVelocityBoostToMidi(midi, new Map([[7, new Map([[480, 22]])]]));
  assert.equal(midi.tracks[0].events[0].noteVelocity, 60);
  assert.equal(midi.tracks[1].events[0].noteVelocity, 82);
});

test('applyVelocityBoostToMidi: clamp 上限 127', () => {
  const midi = { tracks: [{ events: [{ track: 0, type: 128, tick: 10, noteVelocity: 120 }] }] };
  applyVelocityBoostToMidi(midi, new Map([[0, new Map([[10, 22]])]]));
  assert.equal(midi.tracks[0].events[0].noteVelocity, 127);
});

test('applyVelocityBoostToMidi: 空 map / 无 events 安全', () => {
  const midi = { tracks: [{ events: [] }, {}] };
  applyVelocityBoostToMidi(midi, new Map());
  applyVelocityBoostToMidi(midi, new Map([[0, new Map([[1, 22]])]]));
  assert.deepEqual(midi.tracks[0].events, []);
});