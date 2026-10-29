// Fetch all 129 GM sf2 (0-128) from the original guistudy CDN, convert stereo->mono,
// write into public/storage/soundfonts/, rebuild index.json.
import fs from 'node:fs';
import path from 'node:path';
import { convertSf2, analyzeSf2 } from './convert-sf2-mono.mjs';

const BASE = 'https://p.insstudy.com/puquanle/soudfont';
const DIR = 'D:/MIMIguitarweb/public/storage/soundfonts';
const STAGE = 'D:/MIMIguitarweb/tools/sf2-staging';
const PROGRAMS = Array.from({ length: 129 }, (_, i) => i);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchWithRetry(url, retries = 3) {
  let lastErr = null;
  for (let i = 0; i < retries; i++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(60000) });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const buf = Buffer.from(await res.arrayBuffer());
      return buf;
    } catch (e) {
      lastErr = e;
      await sleep(1000 * Math.pow(2, i));
    }
  }
  throw lastErr;
}

async function main() {
  fs.mkdirSync(STAGE, { recursive: true });
  fs.mkdirSync(DIR, { recursive: true });
  console.log('fetching all 129 programs...');
  let ok = 0;
  const failed = [];
  const queue = [...PROGRAMS];
  async function worker() {
    while (queue.length) {
      const p = queue.shift();
      const url = `${BASE}/${p}.sf2`;
      try {
        const buf = await fetchWithRetry(url);
        let out = buf;
        const a = analyzeSf2(buf);
        const hasStereo = a.types[2] || a.types[4];
        if (hasStereo) {
          out = convertSf2(buf);
          const a2 = analyzeSf2(out);
          console.log(`#${p} stereo->mono samples ${a.count}->${a2.count}`);
        } else {
          console.log(`#${p} ok (mono, samples=${a.count})`);
        }
        fs.writeFileSync(path.join(STAGE, `${p}.sf2`), out);
        ok++;
      } catch (e) {
        console.log(`#${p} FAILED: ${e.message}`);
        failed.push(p);
      }
    }
  }
  await Promise.all(Array.from({ length: 4 }, worker));
  console.log(`\nfetched ok: ${ok}, failed: ${failed.length} ${JSON.stringify(failed)}`);

  for (const f of fs.readdirSync(STAGE)) {
    if (f.endsWith('.sf2')) fs.renameSync(path.join(STAGE, f), path.join(DIR, f));
  }
  const final = fs.readdirSync(DIR).filter((f) => f.endsWith('.sf2')).map((f) => Number(f.split('.')[0])).sort((a, b) => a - b);
  fs.writeFileSync(path.join(DIR, 'index.json'), JSON.stringify(final));
  console.log('index.json programs:', final.length);
  let stereoLeft = [];
  for (const p of final) {
    const a = analyzeSf2(fs.readFileSync(path.join(DIR, `${p}.sf2`)));
    if (a.types[2] || a.types[4]) stereoLeft.push(p);
  }
  console.log('remaining stereo files:', JSON.stringify(stereoLeft));
}

main().catch((e) => { console.error(e); process.exit(1); });