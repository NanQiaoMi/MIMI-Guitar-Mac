import fs from 'fs';
import path from 'path';
import { parseRiff, parseListSubChunks, parseShdr } from './convert-sf2-mono.mjs';

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

function buildPhdrEntry(name, preset, bank, pbagNdx) {
  const b = Buffer.alloc(38);
  b.write(name.padEnd(20, '\0').slice(0, 20), 0, 20, 'latin1');
  b.writeUInt16LE(preset, 20);
  b.writeUInt16LE(bank, 22);
  b.writeUInt16LE(pbagNdx, 24);
  b.writeUInt32LE(0, 26);
  b.writeUInt32LE(0, 30);
  b.writeUInt32LE(0, 34);
  return b;
}

export function createUkuleleSoundfont(baseSf2Path, targetPath) {
  const buf = fs.readFileSync(baseSf2Path);
  const top = parseRiff(buf);
  const sdta = top.find((r) => r.id === 'LIST' && r.type === 'sdta');
  const pdta = top.find((r) => r.id === 'LIST' && r.type === 'pdta');
  const info = top.find((r) => r.id === 'LIST' && r.type === 'INFO');
  if (!sdta || !pdta) throw new Error('SF2 缺少 sdta/pdta');

  const pdtaSubs = parseListSubChunks(pdta, buf);
  const igenRec = pdtaSubs.find((s) => s.id === 'igen');
  const ibagRec = pdtaSubs.find((s) => s.id === 'ibag');
  const shdrRec = pdtaSubs.find((s) => s.id === 'shdr');
  const instRec = pdtaSubs.find((s) => s.id === 'inst');

  if (!igenRec || !ibagRec || !shdrRec || !instRec) {
    throw new Error('缺少 igen/ibag/shdr/inst');
  }

  // 1. Rebuild igen:
  // Fix keyRange in ibag 1/13 to cover 0..43 (0x2B00 -> 11008)
  // Fix keyRange in ibag 11/23 to cover 76..127 (0x7F4C -> 32588)
  // Fix op54 (sampleModes) in ibag 11/23 to 0 (no loop, eliminating 0-length loop silence on high notes!)
  const igenLen = igenRec.dataEnd - igenRec.dataStart;
  const newIgen = Buffer.from(buf.subarray(igenRec.dataStart, igenRec.dataEnd));
  
  for (let i = 0; i < igenLen; i += 4) {
    const op = newIgen.readUInt16LE(i);
    let val = newIgen.readUInt16LE(i + 2);
    
    // op 43: keyRange
    if (op === 43) {
      const low = val & 0xff;
      const high = (val >> 8) & 0xff;
      if (low === 23) {
        // Expand lower range to 0
        val = (high << 8) | 0;
        newIgen.writeUInt16LE(val, i + 2);
      } else if (high === 120) {
        // Expand higher range to 127
        val = (127 << 8) | low;
        newIgen.writeUInt16LE(val, i + 2);
      }
    }
    
    // op 54: sampleModes. Must be 0 (no loop) for plucks!
    if (op === 54) {
      newIgen.writeUInt16LE(0, i + 2);
    }
  }

  // 2. Rebuild phdr, pbag, pgen for Presets 0, 24, 25:
  // We will map:
  // Preset 0: Ukulele Acoustic
  // Preset 24: Ukulele Nylon
  // Preset 25: Ukulele Steel
  // EOP: End of presets
  const phdrEntries = [
    buildPhdrEntry('Ukulele Acoustic', 0, 0, 0),
    buildPhdrEntry('Ukulele Nylon', 24, 0, 3),
    buildPhdrEntry('Ukulele Steel', 25, 0, 6),
    buildPhdrEntry('EOP', 0, 0, 9),
  ];
  const newPhdrData = Buffer.concat(phdrEntries);

  // pbag:
  // Each preset has 3 zones:
  // Zone 0: global (genNdx 0)
  // Zone 1: inst 0 (genNdx 0 -> op 41 val 0)
  // Zone 2: inst 1 (genNdx 1 -> op 41 val 1)
  // Total 9 zones + 1 terminal zone (genNdx 2)
  const pbagBuf = Buffer.alloc(10 * 4);
  const pbagMappings = [0, 0, 1, 0, 0, 1, 0, 0, 1, 2];
  pbagMappings.forEach((gNdx, idx) => {
    pbagBuf.writeUInt16LE(gNdx, idx * 4);
    pbagBuf.writeUInt16LE(0, idx * 4 + 2);
  });

  // pgen:
  // gen 0: op 41 val 0 (inst 0)
  // gen 1: op 41 val 1 (inst 1)
  // gen 2: op 0 val 0 (terminal)
  const pgenBuf = Buffer.alloc(3 * 4);
  pgenBuf.writeUInt16LE(41, 0);
  pgenBuf.writeUInt16LE(0, 2);
  pgenBuf.writeUInt16LE(41, 4);
  pgenBuf.writeUInt16LE(1, 6);
  pgenBuf.writeUInt16LE(0, 8);
  pgenBuf.writeUInt16LE(0, 10);

  // pmod: 10 zero bytes
  const pmodBuf = Buffer.alloc(10);

  // 3. Assemble new pdta
  const newPdtaSubs = [];
  for (const s of pdtaSubs) {
    if (s.id === 'phdr') newPdtaSubs.push({ id: 'phdr', data: newPhdrData });
    else if (s.id === 'pbag') newPdtaSubs.push({ id: 'pbag', data: pbagBuf });
    else if (s.id === 'pmod') newPdtaSubs.push({ id: 'pmod', data: pmodBuf });
    else if (s.id === 'pgen') newPdtaSubs.push({ id: 'pgen', data: pgenBuf });
    else if (s.id === 'igen') newPdtaSubs.push({ id: 'igen', data: newIgen });
    else newPdtaSubs.push({ id: s.id, data: buf.subarray(s.dataStart, s.dataEnd) });
  }

  // INFO chunk
  const infoData = info ? buf.subarray(info.dataStart, info.dataEnd) : Buffer.from('INFO');
  const infoSubs = info ? parseListSubChunks(info, buf).map((s) => ({ id: s.id, data: buf.subarray(s.dataStart, s.dataEnd) })) : [];
  
  const sdtaData = buf.subarray(sdta.off, sdta.dataEnd + (sdta.size % 2));

  const outTop = [
    listChunk('INFO', infoSubs),
    chunk(sdta.id, buf.subarray(sdta.dataStart, sdta.dataEnd)),
    listChunk('pdta', newPdtaSubs),
  ];

  const body = Buffer.concat(outTop);
  const head = Buffer.alloc(12);
  head.write('RIFF', 0, 4, 'latin1');
  head.writeUInt32LE(body.length + 4, 4);
  head.write('sfbk', 8, 4, 'latin1');
  const finalBuf = Buffer.concat([head, body]);

  fs.writeFileSync(targetPath, finalBuf);
  console.log(`Created ${targetPath} successfully (${(finalBuf.length / 1024 / 1024).toFixed(2)} MB)`);
  return finalBuf;
}

// Build ukulele_fast.sf2 from 24.sf2
const target = 'public/storage/soundfonts/ukulele_fast.sf2';
createUkuleleSoundfont('public/storage/soundfonts/24.sf2', target);

// Also patch 24.sf2 and 25.sf2 so they have complete key ranges and op54=0
createUkuleleSoundfont('public/storage/soundfonts/24.sf2', 'public/storage/soundfonts/24.sf2');
createUkuleleSoundfont('public/storage/soundfonts/25.sf2', 'public/storage/soundfonts/25.sf2');
