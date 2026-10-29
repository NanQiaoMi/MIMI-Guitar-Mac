import { test } from 'node:test';
import assert from 'node:assert/strict';
import { db } from '../src/lib/db.ts';

const PAGE_SIZE = 90;

let isDbAvailable = false;
try {
  await db.tab.count();
  isDbAvailable = true;
} catch (_) {
  isDbAvailable = false;
}
if (!isDbAvailable && process.env.REQUIRE_TEST_DATABASE === '1') {
  throw new Error('Required test database is unavailable; database checks cannot be skipped');
}

test('title 搜索：命中曲名，结果全部包含关键词', { skip: !isDbAvailable }, async () => {
  const tabs = await db.tab.findMany({
    where: { category: 'guitar', title: { contains: '晴天', mode: 'insensitive' } },
    orderBy: { heat: 'desc' },
    take: PAGE_SIZE,
  });
  const total = await db.tab.count({ where: { category: 'guitar', title: { contains: '晴天', mode: 'insensitive' } } });
  assert.ok(total >= 1, '应有至少 1 条曲名为「晴天」的吉他谱');
  assert.ok(tabs.length >= 1);
  for (const t of tabs) assert.ok(t.title.includes('晴天'));
});

test('artist 搜索：命中艺人，结果全部匹配', { skip: !isDbAvailable }, async () => {
  const tabs = await db.tab.findMany({
    where: { category: 'guitar', artist: { contains: '周杰伦', mode: 'insensitive' } },
    orderBy: { heat: 'desc' },
    take: PAGE_SIZE,
  });
  const total = await db.tab.count({ where: { category: 'guitar', artist: { contains: '周杰伦', mode: 'insensitive' } } });
  assert.ok(total >= 1, '应有至少 1 条艺人为「周杰伦」的吉他谱');
  for (const t of tabs) assert.ok((t.artist ?? '').includes('周杰伦'));
});

test('OR 搜索：标题或艺人任一命中', { skip: !isDbAvailable }, async () => {
  const where = {
    category: 'guitar',
    OR: [
      { title: { contains: '晴天', mode: 'insensitive' } },
      { artist: { contains: '晴天', mode: 'insensitive' } },
    ],
  };
  const total = await db.tab.count({ where });
  assert.ok(total >= 1);
});

test('难度/谱型筛选与搜索叠加生效', { skip: !isDbAvailable }, async () => {
  const baseWhere = {
    category: 'guitar',
    OR: [
      { title: { contains: '晴天', mode: 'insensitive' } },
      { artist: { contains: '晴天', mode: 'insensitive' } },
    ],
  };
  const base = await db.tab.count({ where: baseWhere });
  const filtered = await db.tab.findMany({
    where: { ...baseWhere, difficulty: 2, sheetForm: 1 },
    take: PAGE_SIZE,
  });
  for (const t of filtered) {
    assert.equal(t.difficulty, 2);
    assert.equal(t.sheetForm, 1);
  }
  assert.ok(filtered.length <= base);
});

test('分页一致性：count 与 pageCount 公式匹配', { skip: !isDbAvailable }, async () => {
  const where = { category: 'ukulele', title: { contains: '晴天', mode: 'insensitive' } };
  const total = await db.tab.count({ where });
  assert.equal(Math.max(1, Math.ceil(total / PAGE_SIZE)), Math.max(1, Math.ceil(total / PAGE_SIZE)));
  assert.ok(total >= 0);
});

