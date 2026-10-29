import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeOriginalIbeToJson, xorBytes, isOurFormat } from '../src/lib/ibe.ts';
import { decodeIbeToJsonNode, encodeJsonToIbeNode } from '../src/lib/ibe.node.ts';
import * as at from '@coderline/alphatab';
import { decodeIbeToJsonBrowser } from '../src/lib/ibe.browser.ts';

installNodeAr();

const fixture = new URL('./fixtures/qingtian.ibe', import.meta.url);

test('xorBytes 往返一致', () => {
  const data = new TextEncoder().encode('hello world 12345');
  const enc = xorBytes(data, 'guitartabspro');
  const dec = xorBytes(new Uint8Array(enc.buffer, enc.byteOffset, enc.length), 'guitartabspro');
  assert.equal(Buffer.from(dec.buffer, dec.byteOffset, dec.length).toString(), 'hello world 12345');
});

test('真实 .ibe 样本解码为归一化 JSON', () => {
  const ibe = new Uint8Array(readFileSync(fixture));
  const json = decodeOriginalIbeToJson(ibe);
  assert.equal(json.title, '晴天');
  assert.ok(Array.isArray(json.masterbars));
  assert.ok(Array.isArray(json.tracks));
  assert.equal(json.masterbars.length, 53);
  assert.equal(json.tracks.length, 2);
  const mb0 = json.masterbars[0];
  assert.equal(mb0.timesignaturenumerator, 4);
  assert.ok(Array.isArray(mb0.tempoautomations));
  assert.equal(mb0.tempoautomations[0].value, json.tempo);
});

test('归一化 JSON 可被官方 alphaTab 解析为 Score', () => {
  const ibe = new Uint8Array(readFileSync(fixture));
  const json = decodeOriginalIbeToJson(ibe);
  const settings = new at.Settings();
  const score = at.model.JsonConverter.jsonToScore(JSON.stringify(json), settings);
  assert.equal(score.title, '晴天');
  assert.equal(score.tracks.length, 2);
  assert.equal(score.masterBars.length, 53);
  const st0 = score.tracks[0].staves[0];
  assert.equal(st0.bars.length, 53);
  assert.ok(st0.showTablature);
});

test('自有 MIMI 格式 encode/decode 往返', () => {
  const ibe = new Uint8Array(readFileSync(fixture));
  const json = decodeOriginalIbeToJson(ibe);
  const encoded = encodeJsonToIbeNode(json);
  assert.ok(isOurFormat(encoded));
  const decoded = decodeIbeToJsonNode(encoded);
  assert.equal(decoded.title, '晴天');
  assert.equal(decoded.masterbars.length, 53);
});

test('旧版 alphaTex-only MIMI 容器会转成可读的 AlphaTab 乐谱', async () => {
  const source = decodeOriginalIbeToJson(new Uint8Array(readFileSync(fixture)));
  const settings = new at.Settings();
  const sourceScore = at.model.JsonConverter.jsonToScore(JSON.stringify(source), settings);
  const alphaTex = new at.exporter.AlphaTexExporter().exportToString(sourceScore, settings);
  const encoded = encodeJsonToIbeNode({
    title: '旧版包装测试',
    artist: 'MIMI',
    tempo: 96,
    capo: 2,
    alphaTex,
  });

  for (const decoded of [decodeIbeToJsonNode(encoded), await decodeIbeToJsonBrowser(encoded)]) {
    assert.equal(decoded.title, '旧版包装测试');
    assert.equal(decoded.artist, 'MIMI');
    assert.equal(decoded.tempo, 96);
    assert.ok(decoded.masterbars.length > 0);
    assert.ok(decoded.tracks[0].staves[0].bars.length > 0);
    const score = at.model.JsonConverter.jsonToScore(JSON.stringify(decoded), new at.Settings());
    assert.equal(score.tracks.length, 2);
    assert.ok(score.masterBars.length > 0);
  }
});

test('损坏的 MIMI AlphaTex 会带诊断失败，而不是返回空谱', () => {
  const encoded = encodeJsonToIbeNode({ title: '坏谱', alphaTex: '\\track "Bad"\n. 0.99' });
  assert.throws(() => decodeIbeToJsonNode(encoded), /AlphaTex 内容无效.*208/);
});

test('缺少小节数据的 MIMI 容器会明确失败', () => {
  const encoded = encodeJsonToIbeNode({ title: '空谱容器', tracks: [{ name: '空音轨' }] });
  assert.throws(() => decodeIbeToJsonNode(encoded), /缺少 AlphaTab 小节数据/);
});
