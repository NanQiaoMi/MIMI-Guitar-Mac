import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseXhe, buildBlocks } from '../src/lib/xhe.ts';

test('parseXhe: JSON itemList 格式', () => {
  const p = parseXhe('{"itemList":[{"type":"HEADLINE","value":"主歌"},{"type":"CHORD_ANCHOR","value":"","attributes":{"chord":"C"}}]}');
  assert.equal(p.kind, 'json');
  if (p.kind === 'json') {
    assert.equal(p.items.length, 2);
    assert.equal(p.items[0].type, 'HEADLINE');
  }
});

test('parseXhe: 纯文本（Ultimate Guitar 风格）', () => {
  const p = parseXhe('Chords:\r\nC   (0003)\r\nStrumming D = Down');
  assert.equal(p.kind, 'text');
  if (p.kind === 'text') assert.ok(p.text.includes('C   (0003)'));
});

test('parseXhe: 空内容', () => {
  assert.equal(parseXhe('   ').kind, 'empty');
  assert.equal(parseXhe('').kind, 'empty');
});

test('parseXhe: 以 { 开头但非法 JSON 回退文本', () => {
  const p = parseXhe('{not json at all');
  assert.equal(p.kind, 'text');
});

test('buildBlocks: HEADLINE / RHYTHM / TAB / LINE_BREAK 切块', () => {
  const blocks = buildBlocks([
    { type: 'HEADLINE', value: '前奏' },
    { type: 'TEXT', value: '' },
    { type: 'CHORD_ANCHOR', value: '', attributes: { chord: 'Em' } },
    { type: 'LINE_BREAK' },
    { type: 'RHYTHM', attributes: { rhythm: '(d d) d' } },
    { type: 'TAB', attributes: { tab: '|-----|\n|--3--|' } },
  ]);
  assert.equal(blocks.length, 4);
  assert.equal(blocks[0].kind, 'headline');
  if (blocks[0].kind === 'headline') assert.equal(blocks[0].text, '前奏');
  assert.equal(blocks[1].kind, 'line');
  if (blocks[1].kind === 'line') {
    assert.equal(blocks[1].chordOnly, true);
    assert.equal(blocks[1].segments.length, 1);
  }
  assert.equal(blocks[2].kind, 'rhythm');
  if (blocks[2].kind === 'rhythm') assert.equal(blocks[2].rhythm, '(d d) d');
  assert.equal(blocks[3].kind, 'tab');
  if (blocks[3].kind === 'tab') assert.ok(blocks[3].tab.includes('--3--'));
});

test('buildBlocks: 歌词行（文本+和弦锚点）与纯空行丢弃', () => {
  const blocks = buildBlocks([
    { type: 'CHORD_ANCHOR', value: '�?', attributes: { chord: 'C' } },
    { type: 'TEXT', value: '故事的小黄花' },
    { type: 'LINE_BREAK' },
    { type: 'TEXT', value: '' },
    { type: 'LINE_BREAK' },
    { type: 'CHORD_ANCHOR', value: '', attributes: { chord: 'G' } },
    { type: 'LINE_BREAK' },
  ]);
  // 第一行：歌词行（chordOnly=false）；空行被丢弃；第三行：chordOnly
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].kind, 'line');
  if (blocks[0].kind === 'line') {
    assert.equal(blocks[0].chordOnly, false);
    assert.equal(blocks[0].segments.length, 2);
  }
  assert.equal(blocks[1].kind, 'line');
  if (blocks[1].kind === 'line') assert.equal(blocks[1].chordOnly, true);
});

test('buildBlocks: 无和弦的纯文本段落保留', () => {
  const blocks = buildBlocks([
    { type: 'TEXT', value: '定调用' },
    { type: 'LINE_BREAK' },
  ]);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].kind, 'line');
  if (blocks[0].kind === 'line') {
    assert.equal(blocks[0].chordOnly, false);
    assert.equal(blocks[0].segments[0].text, '定调用');
  }
});
