process.loadEnvFile?.('.env');
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const rows = await prisma.tab.findMany({ orderBy: { heat: 'desc' }, take: 6 });
for (const r of rows) console.log([r.id, r.title, r.artist, 'cat=' + r.category, 'diff=' + r.difficulty, 'form=' + r.sheetForm, 'key=' + r.key, 'bpm=' + r.bpm, 'capo=' + r.capo, 'heat=' + r.heat, 'tuning=' + r.tuning, 'sig=' + r.timeSig].join(' | '));
console.log('total tabs:', await prisma.tab.count());
await prisma.$disconnect();