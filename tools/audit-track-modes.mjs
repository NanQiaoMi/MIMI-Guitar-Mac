#!/usr/bin/env node
// ???????????????? -> JsonConverter ?? -> ?????? + ??????/???
// ???node tools/audit-track-modes.mjs [--limit N] [--min-heat H]
// ????? stdout???? tools/track-mode-audit.json
process.loadEnvFile?.('.env');
import { PrismaClient } from '@prisma/client';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { Settings } from '@coderline/alphatab';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeIbeToJsonNode } from '../src/lib/ibe.node.ts';
import { canUseMixedMode, hasWholeRestCrash } from '../src/lib/scoreDisplayMode.mjs';

installNodeAr();
const prisma = new PrismaClient();
const settings = new Settings();

const rawArgs = process.argv.slice(2);
const args = {};
for (let i = 0; i < rawArgs.length; i++) {
  const a = rawArgs[i];
  if (!a.startsWith('--')) continue;
  const eq = a.indexOf('=');
  if (eq >= 0) args[a.slice(2, eq)] = a.slice(eq + 1);
  else if (i + 1 < rawArgs.length && !rawArgs[i + 1].startsWith('--')) { args[a.slice(2)] = rawArgs[i + 1]; i++; }
  else args[a.slice(2)] = true;
}
const LIMIT = Number(args.limit ?? 0) || null;
const MIN_HEAT = Number(args['min-heat'] ?? 0) || 0;

const rows = await prisma.tab.findMany({
  where: { scoreUrl: { not: null } },
  select: { id: true, title: true, artist: true, category: true, heat: true },
  orderBy: { heat: 'desc' },
});
const sample = (LIMIT ? rows.slice(0, LIMIT) : rows).filter((r) => r.heat >= MIN_HEAT);

const stats = {
  total: sample.length,
  decoded: 0,
  decodeFail: 0,
  modelFail: 0,
  singleTrack: 0,
  multiOneTuned: 0,
  multiTwoPlusTuned: 0,
  mixedApplicable: 0,
  mixedGuarded: 0,
  errorScores: [],
};
const details = [];

for (const r of sample) {
  const file = 'public/storage/scores/' + r.id + '.ibe';
  if (!existsSync(file)) { stats.errorScores.push({ id: r.id, title: r.title, err: 'missing file' }); continue; }
  let json, score;
  try {
    const ibe = new Uint8Array(readFileSync(file));
    json = decodeIbeToJsonNode(ibe);
    stats.decoded++;
    const { model } = await import('@coderline/alphatab');
    score = model.JsonConverter.jsonToScore(JSON.stringify(json), settings);
  } catch (e) {
    if (!json) stats.decodeFail++; else stats.modelFail++;
    stats.errorScores.push({ id: r.id, title: r.title, err: (json ? 'model: ' : 'decode: ') + e.message });
    continue;
  }
  const tracks = score.tracks;
  const tuned = tracks.map((t) => (t.staves ?? []).some((st) => (st.stringTuning?.tunings?.length ?? 0) > 0));
  const tunedCount = tuned.filter(Boolean).length;
  const trackInfo = tracks.map((t, i) => ({
    i,
    name: String(t?.name ?? ''),
    program: t?.playbackInfo?.program ?? null,
    tuning: (t?.staves?.[0]?.stringTuning?.tunings?.length ?? 0),
    wholeRest: (t?.staves ?? []).some((st) => hasWholeRestCrash(st)),
    wholeRestBars: (t?.staves ?? []).reduce((acc, st) => acc + (st.bars ?? []).filter((b) => b.voices.some((v) => v.beats.some((bt) => bt.isRest && bt.duration === 1))).length, 0),
  }));
  let cls;
  if (tunedCount === 0) cls = 'singleTrack';
  else if (tracks.length === 1 || tunedCount === 1) cls = 'multiOneTuned';
  else cls = 'multiTwoPlusTuned';
  stats[cls]++;
  const canMixed = canUseMixedMode(score);
  if (cls === 'multiTwoPlusTuned') {
    if (canMixed) stats.mixedApplicable++;
    else stats.mixedGuarded++;
  }
  details.push({ id: r.id, title: r.title, artist: r.artist, category: r.category, heat: r.heat, cls, canMixed, trackInfo });
}

writeFileSync('tools/track-mode-audit.json', JSON.stringify({ stats, details }, null, 2));
console.log(JSON.stringify(stats, null, 2));
console.log('--- multiTwoPlusTuned canMixed ---');
for (const d of details.filter((x) => x.cls === 'multiTwoPlusTuned' && x.canMixed).slice(0, 10)) {
  console.log(d.id, '|', d.title, '-', d.artist, '|', JSON.stringify(d.trackInfo.map((t) => t.name + '(p' + t.program + ',t' + t.tuning + ')')), 'canMixed', d.canMixed);
}
console.log('--- guarded (forced all-tab) ---');
for (const d of details.filter((x) => x.cls === 'multiTwoPlusTuned' && !x.canMixed).slice(0, 10)) {
  console.log(d.id, '|', d.title, '-', d.artist, '|', JSON.stringify(d.trackInfo), 'canMixed', d.canMixed);
}
await prisma.$disconnect();

