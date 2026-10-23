import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeChord, lookupChord, chordSvg, GUITAR_CHORDS } from '../src/lib/chords.ts';

test('normalizeChord: 别名/笔误归一', () => {
  assert.equal(normalizeChord('EM'), 'Em');
  assert.equal(normalizeChord('Am'), 'Am');
  assert.equal(normalizeChord('DM7'), 'Dmaj7');
  assert.equal(normalizeChord('Famj7'), 'Fmaj7');
  assert.equal(normalizeChord('Fxm'), 'F#m');
  assert.equal(normalizeChord('D/#F'), 'D/F#');
  assert.equal(normalizeChord('f'), 'F');
  assert.equal(normalizeChord('G#'), 'Ab');
  assert.equal(normalizeChord('G2'), 'Gsus2');
  assert.equal(normalizeChord(''), '');
});

test('lookupChord: 覆盖 JSON XHE 全量 70 个和弦（剔除 I 占位）', () => {
  // 从真实数据提取的全部和弦
  const all = ['G','C','F','Am','Em','D','Dm','Dm7','Fmaj7','Am7','Bm','E','G7','C7','Cmaj7','A','Em7','G/B','B7','E7','Fm','D/F#','Cadd9','A7','D7','D11','Am7/G','Bm7','F/A','C/G','F7','D/#F','F7M','Dsus4','Fmaj9','Cm','B','EM','G6','Gsus4','Gadd9','Bb','Caug','Am/F#','Gsus2','Famj7','D6','D6add9','Gm','Dsus2','A7sus4','Am9','D2','Asus4','F#m','F#/D','F/G','Ab','DM7','Em/B','AM','Fxm','DM','Esus4','G2','f','C/E','G#','I'];
  const missing = [];
  for (const c of all) {
    if (normalizeChord(c) === '') continue; // 'I' 占位忽略
    if (!lookupChord(c)) missing.push(c);
  }
  assert.deepEqual(missing, []);
});

test('lookupChord: 未知和弦返回 null', () => {
  assert.equal(lookupChord('H7'), null);
  assert.equal(lookupChord('Qmaj13'), null);
  assert.equal(lookupChord(''), null);
});

test('chordSvg: 结构与参考站一致（C 和弦 x32010）', () => {
  const svg = chordSvg('C', ['x', 3, 2, 0, 1, 0]);
  assert.ok(svg.includes('<text x="23" y="11" font-size="8" fill="#E53E3E"'));
  assert.ok(svg.includes('>C</text>'));
  // 5 品线 + 6 弦线
  assert.equal((svg.match(/<line x1="8" y1="\d+" x2="38"/g) || []).length, 5);
  assert.equal((svg.match(/<line x1="8" y1="16" x2="8" y2="44"/g) || []).length, 1);
  // 指位点：A3 D2 B1
  assert.ok(svg.includes('cx="14" cy="33.5"'));
  assert.ok(svg.includes('cx="20" cy="26.5"'));
  assert.ok(svg.includes('cx="32" cy="19.5"'));
  // 闷音 X
  assert.ok(svg.includes('x1="6.5"'));
  // 空弦无记号
  assert.ok(!svg.includes('cx="26" cy="'));
  assert.ok(!svg.includes('cx="38" cy="'));
});

test('chordSvg: 指法坐标随品数递增（F=133211）', () => {
  const svg = chordSvg('F', [1, 3, 3, 2, 1, 1]);
  // 低音 E 1品 = 19.5，A 3品 = 33.5
  assert.ok(svg.includes('cx="8" cy="19.5"'));
  assert.ok(svg.includes('cx="14" cy="33.5"'));
  assert.ok(svg.includes('cx="26" cy="26.5"'));
});

test('chordSvg: 特殊字符转义', () => {
  const svg = chordSvg('G/B', ['x', 2, 0, 0, 0, 3]);
  assert.ok(svg.includes('G/B'));
});

test('GUITAR_CHORDS: 关键和弦指法正确', () => {
  assert.deepEqual(GUITAR_CHORDS.C, ['x', 3, 2, 0, 1, 0]);
  assert.deepEqual(GUITAR_CHORDS.G, [3, 2, 0, 0, 0, 3]);
  assert.deepEqual(GUITAR_CHORDS.F, [1, 3, 3, 2, 1, 1]);
  assert.deepEqual(GUITAR_CHORDS.Am, ['x', 0, 2, 2, 1, 0]);
  assert.deepEqual(GUITAR_CHORDS.Em, [0, 2, 2, 0, 0, 0]);
  assert.deepEqual(GUITAR_CHORDS.Bm, ['x', 2, 4, 4, 3, 2]);
});
