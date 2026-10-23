import { test } from 'node:test';
import assert from 'node:assert/strict';
import { convertSf2, analyzeSf2, parseRiff, parseListSubChunks, parseShdr } from '../tools/convert-sf2-mono.mjs';

// ---------- 最小 SF2 构造 ----------
function chunk(id, data) {
  const head = Buffer.alloc(8);
  head.write(id, 0, 4, 'latin1');
  head.writeUInt32LE(data.length, 4);
  return Buffer.concat([head, data, Buffer.alloc(data.length % 2)]);
}
function list(type, subChunks) {
  return chunk('LIST', Buffer.concat([Buffer.from(type, 'latin1'), ...subChunks.map((c) => chunk(c.id, c.data))]));
}

function buildMinimalSf2() {
  // 采样数据：L(8) + R(8) + Mono(3) = 19 个 Int16
  const L = [10, 20, 30, 40, 50, 60, 70, 80];
  const R = [0, 2, 4, 6, 8, 10, 12, 14];
  const Mono = [100, 200, 300];
  const smplData = Buffer.alloc((L.length + R.length + Mono.length) * 2);
  const all = [...L, ...R, ...Mono];
  all.forEach((v, i) => smplData.writeInt16LE(v, i * 2));

  // shdr：TestL(type4) / TestR(type2) / MonoS(type1) / EOS(type0)
  function shdrRow(name, start, end, rate, origPitch, link, type) {
    const b = Buffer.alloc(46);
    b.write(name.padEnd(20, '\0'), 0, 20, 'latin1');
    b.writeUInt32LE(start, 20);
    b.writeUInt32LE(end, 24);
    b.writeUInt32LE(start, 28);
    b.writeUInt32LE(end, 32);
    b.writeUInt32LE(rate, 36);
    b.writeUInt8(origPitch, 40);
    b.writeUInt16LE(link, 42);
    b.writeUInt16LE(type, 44);
    return b;
  }
  const shdrData = Buffer.concat([
    shdrRow('TestL', 0, 8, 44100, 60, 1, 4),
    shdrRow('TestR', 8, 16, 44100, 60, 0, 2),
    shdrRow('MonoS', 16, 19, 44100, 60, 0, 1),
    shdrRow('EOS', 0, 0, 0, 0, 0, 0),
  ]);

  // igen：3 个 instrument zone（sample 0/1/2）+ 终止符
  function gen(op, amount) { const b = Buffer.alloc(4); b.writeUInt16LE(op, 0); b.writeUInt16LE(amount, 2); return b; }
  const igenData = Buffer.concat([gen(53, 0), gen(53, 1), gen(53, 2), gen(0, 0)]);

  // phdr(2*38) / pbag(2*4) / pmod(2*10) / pgen(2*4) / inst(2*22) / ibag(4*4) / imod(4*10)
  const phdr = Buffer.alloc(76); // 全 0 即可（合法结构）
  const pbag = Buffer.alloc(8);
  pbag.writeUInt16LE(0, 0); // zone0 genIndex 0
  pbag.writeUInt16LE(0, 2); // zone0 modIndex 0
  pbag.writeUInt16LE(2, 4); // terminator genIndex 2
  pbag.writeUInt16LE(1, 6); // terminator modIndex 1
  const pmod = Buffer.alloc(20);
  const pgen = Buffer.concat([gen(41, 0), gen(0, 0)]);
  const inst = Buffer.alloc(44); // 全 0（zoneIndex 0）
  const ibag = Buffer.alloc(16);
  ibag.writeUInt16LE(0, 0); ibag.writeUInt16LE(0, 2); // zone0 -> igen gen0
  ibag.writeUInt16LE(1, 4); ibag.writeUInt16LE(0, 6); // zone1 -> igen gen1
  ibag.writeUInt16LE(2, 8); ibag.writeUInt16LE(0, 10); // zone2 -> igen gen2
  ibag.writeUInt16LE(3, 12); ibag.writeUInt16LE(4, 14); // terminator
  const imod = Buffer.alloc(40);

  const ifil = Buffer.alloc(4); ifil.writeUInt16LE(2, 0); ifil.writeUInt16LE(1, 2);
  const isng = Buffer.from('TestSound', 'latin1');
  const inam = Buffer.from('TestFont', 'latin1');

  const info = list('INFO', [{ id: 'ifil', data: ifil }, { id: 'isng', data: isng }, { id: 'INAM', data: inam }]);
  const sdta = list('sdta', [{ id: 'smpl', data: smplData }]);
  const pdta = list('pdta', [
    { id: 'phdr', data: phdr }, { id: 'pbag', data: pbag }, { id: 'pmod', data: pmod }, { id: 'pgen', data: pgen },
    { id: 'inst', data: inst }, { id: 'ibag', data: ibag }, { id: 'imod', data: imod }, { id: 'igen', data: igenData },
    { id: 'shdr', data: shdrData },
  ]);
  const body = Buffer.concat([info, sdta, pdta]);
  const head = Buffer.alloc(12);
  head.write('RIFF', 0, 4, 'latin1');
  head.writeUInt32LE(body.length + 4, 4);
  head.write('sfbk', 8, 4, 'latin1');
  return Buffer.concat([head, body]);
}

function getIgenAmounts(buf, op) {
  const top = parseRiff(buf);
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  const subs = parseListSubChunks(pdta, buf);
  const igen = subs.find((s) => s.id === 'igen');
  const n = Math.floor((igen.dataEnd - igen.dataStart) / 4);
  const out = [];
  for (let i = 0; i < n; i++) {
    const b = igen.dataStart + i * 4;
    if (buf.readUInt16LE(b) === op) out.push(buf.readUInt16LE(b + 2));
  }
  return out;
}

function getSmplRegion(buf, startSamples, len) {
  const top = parseRiff(buf);
  const sdta = top.find((r) => r.id === 'LIST' && r.type === 'sdta');
  const subs = parseListSubChunks(sdta, buf);
  const smpl = subs.find((s) => s.id === 'smpl');
  const out = [];
  for (let i = 0; i < len; i++) out.push(buf.readInt16LE(smpl.dataStart + (startSamples + i) * 2));
  return out;
}

function getShdr(buf) {
  const top = parseRiff(buf);
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  const subs = parseListSubChunks(pdta, buf);
  const sh = subs.find((s) => s.id === 'shdr');
  return parseShdr(buf, sh.dataStart, sh.dataEnd);
}

test('convertSf2: 立体声对混合为单声道，类型全为 1，igen 重映射正确', () => {
  const input = buildMinimalSf2();
  const before = analyzeSf2(input);
  assert.deepEqual(before.types, { 4: 1, 2: 1, 1: 1, 0: 1 });

  const out = convertSf2(input);
  const after = analyzeSf2(out);
  // 立体声对合并 → TestMono + MonoS + EOS = 3 条 shdr
  assert.equal(after.count, 3);
  assert.deepEqual(after.types, { 1: 2, 0: 1 });

  // 混合值 (L+R)/2
  const rows = getShdr(out);
  const mono = rows[0];
  assert.equal(mono.name, 'Test');
  assert.equal(mono.sampleType, 1);
  assert.equal(mono.start, 0);
  assert.equal(mono.end, 8);
  const data = getSmplRegion(out, 0, 8);
  assert.deepEqual(data, [5, 11, 17, 23, 29, 35, 41, 47]);

  // 第二个采样是原 MonoS 复制
  const mono2 = rows[1];
  assert.equal(mono2.name, 'MonoS');
  assert.equal(mono2.sampleType, 1);
  assert.deepEqual(getSmplRegion(out, mono2.start, 3), [100, 200, 300]);

  // EOS 在末尾，start=end=总采样数
  const eos = rows[2];
  assert.equal(eos.sampleType, 0);
  assert.equal(eos.start, 11);
  assert.equal(eos.end, 11);

  // igen genOp 53 重映射：旧 0,1→0；旧 2→1
  assert.deepEqual(getIgenAmounts(out, 53), [0, 0, 1]);
});

test('convertSf2: 全单声道文件保持不变（无 2/4 时不改变结构）', () => {
  const input = buildMinimalSf2();
  // 把 TestL/TestR 都改成 type1（模拟无立体声）
  const top = parseRiff(input);
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  const subs = parseListSubChunks(pdta, input);
  const sh = subs.find((s) => s.id === 'shdr');
  const copy = Buffer.from(input);
  copy.writeUInt16LE(1, sh.dataStart + 44);
  copy.writeUInt16LE(1, sh.dataStart + 46 + 44);
  const before = analyzeSf2(copy);
  assert.deepEqual(before.types, { 1: 3, 0: 1 });
  const out = convertSf2(copy);
  const after = analyzeSf2(out);
  assert.deepEqual(after.types, { 1: 3, 0: 1 });
  // 仍可解析且 igen 不变
  assert.deepEqual(getIgenAmounts(out, 53), [0, 1, 2]);
});

test('convertSf2: 输出 RIFF 结构可完整重解析（尺寸一致、子块齐全）', () => {
  const input = buildMinimalSf2();
  const out = convertSf2(input);
  const top = parseRiff(out);
  const ids = top.map((r) => r.id + (r.type ? ':' + r.type : ''));
  assert.deepEqual(ids, ['LIST:INFO', 'LIST:sdta', 'LIST:pdta']);
  for (const rec of top) {
    // 子块边界不越界
    assert.ok(rec.dataEnd <= out.length);
  }
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  const subIds = parseListSubChunks(pdta, out).map((s) => s.id);
  assert.deepEqual(subIds, ['phdr', 'pbag', 'pmod', 'pgen', 'inst', 'ibag', 'imod', 'igen', 'shdr']);
});