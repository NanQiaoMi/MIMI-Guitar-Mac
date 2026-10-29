// SF2 立体声 → 单声道转换器
// AlphaSynth (@coderline/alphatab 1.8.4) 只支持 sampleType=1 单声道；type 2/4 的立体声采样会被跳过导致无声。
// 本工具：立体声 L/R 对逐点混合 (L+R)/2 → 单声道；重映射 igen 中 genOp=53 的样本索引；重建 smpl/shdr 与整文件。
import fs from 'node:fs';
import path from 'node:path';

// ---------- 解析 ----------
export function parseRiff(buf) {
  const top = [];
  let off = 12; // 'RIFF' + size + 'sfbk'
  while (off + 8 <= buf.length) {
    const id = buf.toString('latin1', off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    const dataStart = off + 8;
    const dataEnd = dataStart + size;
    const rec = { id, size, off, dataStart, dataEnd };
    if (id === 'LIST') {
      rec.type = buf.toString('latin1', dataStart, dataStart + 4);
      rec.subStart = dataStart + 4;
      rec.subEnd = dataEnd;
    }
    top.push(rec);
    off = dataEnd + (size % 2);
  }
  return top;
}

export function parseListSubChunks(rec, buf) {
  const subs = [];
  let off = rec.subStart;
  while (off + 8 <= rec.subEnd) {
    const id = buf.toString('latin1', off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    subs.push({ id, size, dataStart: off + 8, dataEnd: off + 8 + size });
    off = off + 8 + size + (size % 2);
  }
  return subs;
}

export function parseShdr(buf, start, end) {
  const rows = [];
  const n = Math.floor((end - start) / 46);
  for (let i = 0; i < n; i++) {
    const b = start + i * 46;
    rows.push({
      name: buf.toString('utf8', b, b + 20).replace(/\0+$/g, ''),
      start: buf.readUInt32LE(b + 20),
      end: buf.readUInt32LE(b + 24),
      startLoop: buf.readUInt32LE(b + 28),
      endLoop: buf.readUInt32LE(b + 32),
      sampleRate: buf.readUInt32LE(b + 36),
      originalPitch: buf.readUInt8(b + 40),
      pitchCorrection: buf.readInt8(b + 41),
      sampleLink: buf.readUInt16LE(b + 42),
      sampleType: buf.readUInt16LE(b + 44),
    });
  }
  return rows;
}

/** 返回 { count, types, rows }（用于 CLI 摘要与单测断言） */
export function analyzeSf2(buf) {
  const top = parseRiff(buf);
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  if (!pdta) return { count: 0, types: {}, rows: [] };
  const subs = parseListSubChunks(pdta, buf);
  const shdrRec = subs.find((s) => s.id === 'shdr');
  if (!shdrRec) return { count: 0, types: {}, rows: [] };
  const rows = parseShdr(buf, shdrRec.dataStart, shdrRec.dataEnd);
  const types = {};
  for (const r of rows) types[r.sampleType] = (types[r.sampleType] ?? 0) + 1;
  return { count: rows.length, types, rows };
}

// ---------- 重建 ----------
function chunk(id, data) {
  const head = Buffer.alloc(8);
  head.write(id, 0, 4, 'latin1');
  head.writeUInt32LE(data.length, 4);
  const pad = data.length % 2 ? Buffer.alloc(1) : Buffer.alloc(0);
  return Buffer.concat([head, data, pad]);
}

function listChunk(type, subs) {
  const body = Buffer.concat([Buffer.from(type, 'latin1'), ...subs.map((c) => chunk(c.id, c.data))]);
  return chunk('LIST', body);
}

function buildShdrEntry(ns) {
  const b = Buffer.alloc(46);
  b.write(ns.name.padEnd(20, '\0').slice(0, 20), 0, 20, 'latin1');
  b.writeUInt32LE(ns.offset, 20);
  b.writeUInt32LE(ns.offset + ns.data.length, 24);
  b.writeUInt32LE(ns.offset + ns.startLoop, 28);
  b.writeUInt32LE(ns.offset + ns.endLoop, 32);
  b.writeUInt32LE(ns.rate, 36);
  b.writeUInt8(ns.originalPitch, 40);
  b.writeInt8(ns.pitchCorrection, 41);
  b.writeUInt16LE(0, 42); // sampleLink = 0
  b.writeUInt16LE(1, 44); // sampleType = mono
  return b;
}

function buildEosEntry(totalSamples) {
  const b = Buffer.alloc(46);
  b.write('EOS'.padEnd(20, '\0'), 0, 20, 'latin1');
  b.writeUInt32LE(totalSamples, 20);
  b.writeUInt32LE(totalSamples, 24);
  b.writeUInt16LE(0, 44);
  return b;
}


/** 核心转换：输入 SF2 Buffer，输出单声道 SF2 Buffer（无副作用） */
export function convertSf2(input) {
  const buf = Buffer.from(input);
  const top = parseRiff(buf);
  const sdta = top.find((r) => r.id === 'LIST' && r.type === 'sdta');
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  const info = top.find((r) => r.id === 'LIST' && r.type === 'INFO');
  if (!sdta || !pdta) throw new Error('SF2 缺少 sdta/pdta');
  const sdtaSubs = parseListSubChunks(sdta, buf);
  const smplRec = sdtaSubs.find((s) => s.id === 'smpl');
  if (!smplRec) throw new Error('SF2 缺少 smpl');
  const smpl = buf.subarray(smplRec.dataStart, smplRec.dataEnd);
  const samples = new Int16Array(smpl.buffer, smpl.byteOffset, Math.floor(smpl.length / 2));

  const pdtaSubs = parseListSubChunks(pdta, buf);
  const shdrRec = pdtaSubs.find((s) => s.id === 'shdr');
  const igenRec = pdtaSubs.find((s) => s.id === 'igen');
  if (!shdrRec) throw new Error('SF2 缺少 shdr');
  const shdr = parseShdr(buf, shdrRec.dataStart, shdrRec.dataEnd);

  const newSamples = [];
  const oldToNew = new Map();
  const consumed = new Set();

  const readRegion = (start, len) => {
    const data = new Int16Array(len);
    for (let k = 0; k < len; k++) data[k] = samples[start + k] ?? 0;
    return data;
  };

  for (let i = 0; i < shdr.length; i++) {
    if (consumed.has(i)) continue;
    const s = shdr[i];
    const t = s.sampleType & 0x7fff;
    if (t === 0) {
      oldToNew.set(i, -1); // EOS 占位，末尾统一分配
      continue;
    }
    let paired = -1;
    if (t === 4 || t === 2) {
      // 用 sampleLink 找配对；找不到则向后找同长度反类型
      if (s.sampleLink > 0 && s.sampleLink < shdr.length) {
        const p = shdr[s.sampleLink];
        if (p && (p.sampleType & 0x7fff) === (t === 4 ? 2 : 4) && !consumed.has(s.sampleLink)) paired = s.sampleLink;
      }
      if (paired < 0) {
        for (let k = i + 1; k < shdr.length; k++) {
          if (consumed.has(k)) continue;
          if ((shdr[k].sampleType & 0x7fff) === (t === 4 ? 2 : 4)) { paired = k; break; }
        }
      }
      if (paired >= 0) {
        const s2 = shdr[paired];
        const L = (s.sampleType & 0x7fff) === 4 ? s : s2;
        const R = (s.sampleType & 0x7fff) === 2 ? s : s2;
        const len = Math.min(L.end - L.start, R.end - R.start);
        if (len > 0) {
          const data = new Int16Array(len);
          for (let k = 0; k < len; k++) {
            const l = samples[L.start + k] ?? 0;
            const r = samples[R.start + k] ?? 0;
            data[k] = Math.round((l + r) / 2);
          }
          const name = (L.name.endsWith('L') ? L.name.slice(0, -1) : L.name).trim();
          const newIdx = newSamples.length;
          newSamples.push({
            name: (name || 'Mono').slice(0, 20),
            data,
            rate: L.sampleRate,
            originalPitch: L.originalPitch,
            pitchCorrection: L.pitchCorrection,
            startLoop: Math.max(0, Math.min(L.startLoop - L.start, len)),
            endLoop: Math.max(0, Math.min(L.endLoop - L.start, len)),
          });
          oldToNew.set(i, newIdx);
          oldToNew.set(paired, newIdx);
          consumed.add(paired);
          continue;
        }
      }
      // 孤独的立体声采样：按单声道复制
    }
    const len = Math.max(0, s.end - s.start);
    const data = readRegion(s.start, len);
    const newIdx = newSamples.length;
    newSamples.push({
      name: (s.name || 'Sample').slice(0, 20),
      data,
      rate: s.sampleRate,
      originalPitch: s.originalPitch,
      pitchCorrection: s.pitchCorrection,
      startLoop: Math.max(0, Math.min(s.startLoop - s.start, len)),
      endLoop: Math.max(0, Math.min(s.endLoop - s.start, len)),
    });
    oldToNew.set(i, newIdx);
  }

  // 分配 smpl 偏移并组装
  let offset = 0;
  const parts = [];
  for (const ns of newSamples) {
    ns.offset = offset;
    offset += ns.data.length;
    const b = Buffer.alloc(ns.data.length * 2);
    for (let k = 0; k < ns.data.length; k++) b.writeInt16LE(ns.data[k], k * 2);
    parts.push(b);
  }
  const totalSamples = offset;
  const eosIndex = newSamples.length; // EOS 是最后一个（不在 newSamples 内）
  for (const [k, v] of oldToNew) if (v === -1) oldToNew.set(k, eosIndex);
  const smplData = Buffer.concat(parts);

  // 重建 shdr
  const shdrParts = [];
  for (const ns of newSamples) shdrParts.push(buildShdrEntry(ns));
  shdrParts.push(buildEosEntry(totalSamples));
  const shdrData = Buffer.concat(shdrParts);

  // 重建 igen（重映射 genOp=53 样本索引）
  let igenData = null;
  if (igenRec) {
    const gens = [];
    const n = Math.floor((igenRec.dataEnd - igenRec.dataStart) / 4);
    for (let i = 0; i < n; i++) {
      const b = igenRec.dataStart + i * 4;
      const op = buf.readUInt16LE(b);
      let amount = buf.readUInt16LE(b + 2);
      if (op === 53 && oldToNew.has(amount)) amount = oldToNew.get(amount);
      gens.push([op, amount]);
    }
    const g = Buffer.alloc(gens.length * 4);
    gens.forEach(([op, amount], i) => {
      g.writeUInt16LE(op, i * 4);
      g.writeUInt16LE(amount, i * 4 + 2);
    });
    igenData = g;
  }

  // 组装 pdta：其余子块原样复制，shdr/igen 替换
  const pdtaSubsNew = [];
  for (const sub of pdtaSubs) {
    if (sub.id === 'shdr') { pdtaSubsNew.push({ id: 'shdr', data: shdrData }); continue; }
    if (sub.id === 'igen' && igenData) { pdtaSubsNew.push({ id: 'igen', data: igenData }); continue; }
    pdtaSubsNew.push({ id: sub.id, data: buf.subarray(sub.dataStart, sub.dataEnd) });
  }

  const infoData = info ? buf.subarray(info.dataStart, info.dataEnd) : Buffer.from('INFO');
  const sdtaData = listChunk('sdta', [{ id: 'smpl', data: smplData }]);
  const pdtaData = listChunk('pdta', pdtaSubsNew);
  const infoChunk = listChunk('INFO', [
    ...parseListSubChunks(info ?? { subStart: infoData.length, subEnd: infoData.length }, buf).map((s) => ({ id: s.id, data: buf.subarray(s.dataStart, s.dataEnd) })),
  ]);

  const body = Buffer.concat([infoChunk, sdtaData, pdtaData]);
  const head = Buffer.alloc(12);
  head.write('RIFF', 0, 4, 'latin1');
  head.writeUInt32LE(body.length + 4, 4); // 文件总长 - 8
  head.write('sfbk', 8, 4, 'latin1');
  return Buffer.concat([head, body]);
}

// ---------- CLI ----------
function dateStamp() {
  const d = new Date();
  return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
}

async function main() {
  const args = process.argv.slice(2);
  const backupIdx = args.indexOf('--backup');
  const backupDir = backupIdx >= 0 ? (args[backupIdx + 1] || `tools/sf2-backup-${dateStamp()}`) : null;
  const dir = 'public/storage/soundfonts';
  if (backupDir) {
    fs.mkdirSync(backupDir, { recursive: true });
    fs.cpSync(dir, backupDir, { recursive: true });
    console.log('BACKUP -> ' + backupDir);
  }
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sf2')).sort((a, b) => Number(a.split('.')[0]) - Number(b.split('.')[0]));
  let converted = 0;
  for (const f of files) {
    const p = path.join(dir, f);
    const buf = fs.readFileSync(p);
    const before = analyzeSf2(buf);
    const has24 = before.types[2] || before.types[4];
    if (!has24) continue;
    const out = convertSf2(buf);
    const tmp = p + '.tmp';
    fs.writeFileSync(tmp, out);
    fs.renameSync(tmp, p);
    const after = analyzeSf2(fs.readFileSync(p));
    converted++;
    console.log(`${f} samples ${before.count}->${after.count} types ${JSON.stringify(before.types)}->${JSON.stringify(after.types)}`);
  }
  console.log('CONVERTED ' + converted + ' files');
}

if (process.argv[1] && process.argv[1].endsWith('convert-sf2-mono.mjs')) {
  main().catch((e) => { console.error(e); process.exit(1); });
}