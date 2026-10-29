import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { encodeStudioProjectToMimiIbe } from '../../../src/lib/studio/studioScoreBridge.ts';
import { createEmptyPersonalData, validatePersonalData } from '../../../src/lib/personal/validation.ts';
import { canonicalJson, dataCounts } from '../../../src/lib/personal/backup.ts';
import { hashBytes } from '../../../src/lib/personal/repository.ts';

// Self-authored acceptance input only. Import through the product's file chooser;
// this script never opens the real browser database or reads user data.
const folder = fileURLToPath(new URL('.', import.meta.url));
const fixture = JSON.parse(await readFile(new URL('../studio-interactions-2026-10-17/self-authored-studio.json', import.meta.url), 'utf8'));
fixture.id = 'practice-correctness-20261018';
fixture.title = '练习闭环验收 · 双轨变调夹';
fixture.tracks[0].capo = 2;
fixture.tracks[0].volume = 0;
fixture.tracks[1].capo = 5;
fixture.tracks[1].volume = 0.6;
await writeFile(resolve(folder, 'self-authored-practice.json'), JSON.stringify(fixture, null, 2) + '\n');
const normal = await encodeStudioProjectToMimiIbe(fixture);
await writeFile(resolve(folder, 'self-authored-practice.ibe'), normal);
const repeated = structuredClone(fixture);
repeated.id += '-repeat';
repeated.title = '练习边界验收 · 反复与变速';
repeated.tracks.forEach((track) => { track.capo = 0; track.volume = 0.5; });
repeated.bars[0].repeatStart = true;
repeated.bars[1].repeatEnd = true;
repeated.bars[1].repeatCount = 2;
repeated.bars[1].tempo = 90;
await writeFile(resolve(folder, 'self-authored-repeat.json'), JSON.stringify(repeated, null, 2) + '\n');
await writeFile(resolve(folder, 'self-authored-repeat.ibe'), await encodeStudioProjectToMimiIbe(repeated));

const data = createEmptyPersonalData();
data.migrationCompleted = true;
const now = Date.parse('2026-10-18T00:00:00+08:00');
for (const [index, name] of ['曲库校验甲', '曲库排序乙', '反复变速丙'].entries()) {
  const id = `catalog:acceptance-${index}`;
  data.scores.push({ id, source: 'catalog', sourceId: `acceptance-${index}`, title: name, artist: 'MIMI 自写测试', category: 'guitar', format: 'ibe', revision: 'unverified', scoreUrl: `/__practice-audit__/${index === 2 ? 'self-authored-repeat' : 'self-authored-practice'}.ibe`, createdAt: now, updatedAt: now });
  data.practiceItems.push({ scoreId: id, status: 'todo', order: index, note: '', updatedAt: now });
}
validatePersonalData(data);
const payload = { data, assets: [] };
const manifest = { formatVersion: 1, schemaVersion: data.schemaVersion, revision: data.revision,
  generatedAt: new Date(now).toISOString(), counts: dataCounts(data, 0), assets: [],
  payloadSha256: await hashBytes(new TextEncoder().encode(canonicalJson(payload))), assetBytes: 0 };
await writeFile(resolve(folder, 'self-authored-catalog-backup.json'), JSON.stringify({ format: 'mimi-personal-backup', manifest, payload }, null, 2) + '\n');

// Temporary acceptance resources, outside tracked product files. Re-run after build.
const target = resolve(process.argv[2] ?? 'dist/client', '__practice-audit__');
await mkdir(target, { recursive: true });
for (const name of ['self-authored-practice.ibe', 'self-authored-repeat.ibe']) await copyFile(resolve(folder, name), resolve(target, name));
console.log('Prepared self-authored UI-import fixtures and isolated acceptance resources.');
