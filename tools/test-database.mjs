import { PrismaClient } from '@prisma/client';
import { spawnSync } from 'node:child_process';

// This command owns only its isolated fixture database. It never seeds the user's catalog.
const databaseUrl = process.env.DATABASE_URL;
let target;
try { target = new URL(databaseUrl); } catch { throw new Error('Set DATABASE_URL to the isolated mimi_platform_test database'); }
if (!['postgres:', 'postgresql:'].includes(target.protocol) ||
    !['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname) ||
    target.pathname !== '/mimi_platform_test') {
  throw new Error('Database tests require a local database named mimi_platform_test; no data was written');
}

const db = new PrismaClient();
try {
  await db.$connect();
  for (const row of [
    { id: 'test-guitar-seven', title: '晴天', artist: '周杰伦', category: 'guitar', difficulty: 2, sheetForm: 7 },
    { id: 'test-guitar-four', title: '晴天练习', artist: '周杰伦', category: 'guitar', difficulty: 2, sheetForm: 4 },
    { id: 'test-guitar-song', title: '晴天伴奏', artist: '周杰伦', category: 'guitar', difficulty: 2, sheetForm: 1 },
    { id: 'test-ukulele', title: '晴天', artist: '测试艺人', category: 'ukulele', difficulty: 1, sheetForm: 7 },
  ]) {
    await db.tab.upsert({ where: { id: row.id }, create: { ...row, format: 'ibe', heat: 1 }, update: row });
  }
} finally {
  await db.$disconnect();
}

const result = spawnSync(process.execPath, ['--test', 'tests/search.test.mjs', 'tests/sheetform.test.mjs'], {
  stdio: 'inherit', env: { ...process.env, REQUIRE_TEST_DATABASE: '1' },
});
if (result.error) throw result.error;
process.exit(result.status ?? 1);
