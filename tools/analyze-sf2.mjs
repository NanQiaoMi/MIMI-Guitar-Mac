import fs from 'node:fs';
import path from 'node:path';
const dir = 'public/storage/soundfonts';
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sf2')).sort((a, b) => Number(a.split('.')[0]) - Number(b.split('.')[0]));

function parseShdr(buf) {
  // pdta sub-chunks
  let off = 0;
  let shdr = null;
  const isPercussion = (program) => [128].includes(program);
  const chunks = [];
  while (off + 8 <= buf.length) {
    const id = buf.toString('ascii', off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    const dataStart = off + 8;
    if (id === 'shdr') { shdr = buf.subarray(dataStart, dataStart + size); break; }
    chunks.push(id);
    off = dataStart + size + (size % 2);
  }
  if (!shdr) return { chunks, count: 0, types: {}, first8: [] };
  const n = Math.floor(shdr.length / 46);
  const types = {};
  const first8 = [];
  for (let i = 0; i < n; i++) {
    const base = i * 46;
    const st = shdr.readUInt16LE(base + 44);
    types[st] = (types[st] ?? 0) + 1;
    if (i < 8) first8.push({ name: shdr.toString('utf8', base, base + 20).replace(/\0/g, ''), type: st });
  }
  return { chunks, count: n, types, first8 };
}

function parse(buf) {
  // walk top-level chunks, find pdta
  let off = 12; // skip RIFF + size + sfbk
  let pdta = null;
  const top = [];
  while (off + 8 <= buf.length) {
    const id = buf.toString('ascii', off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    top.push(id + ':' + size);
    if (id === 'LIST') {
      const type = buf.toString('ascii', off + 8, off + 12);
      if (type === 'pdta') { pdta = buf.subarray(off + 12, off + 8 + size); }
    }
    off = off + 8 + size + (size % 2);
  }
  const r = pdta ? parseShdr(pdta) : { chunks: [], count: 0, types: {}, first8: [] };
  return { top, ...r };
}

let stereo = 0, mono = 0, both = 0, total = 0;
const rows = [];
for (const f of files) {
  const buf = fs.readFileSync(path.join(dir, f));
  const r = parse(buf);
  const has2or4 = r.types[2] || r.types[4];
  const has1 = r.types[1];
  if (has2or4 && has1) both++;
  else if (has2or4) stereo++;
  else if (has1) mono++;
  rows.push({ f, size: buf.length, samples: r.count, types: r.types, first8: r.first8.slice(0, 2) });
  total += buf.length;
}
const summary = { files: files.length, stereoOnly: stereo, monoOnly: mono, both, totalBytes: total };
console.log('SUMMARY: ' + JSON.stringify(summary));
for (const r of rows) {
  console.log(r.f + ' samples=' + r.samples + ' types=' + JSON.stringify(r.types) + ' e.g.=' + JSON.stringify(r.first8));
}
