import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formLabel } from '../src/lib/tabQuery.ts';
import { FORM_LABELS, tabTitle } from '../src/lib/tabMeta.ts';
import { db } from '../src/lib/db.ts';

test('formLabel(7) = 六线谱', () => {
  assert.equal(formLabel(7), '六线谱');
  assert.equal(formLabel(4), '六线谱');
  assert.equal(formLabel(1), '弹唱谱');
});

test('FORM_LABELS(7) = 六线', () => {
  assert.equal(FORM_LABELS[7], '六线');
  assert.equal(FORM_LABELS[4], '六线');
});

test('tabTitle 对 sheetForm=7 拼出「六线谱」', () => {
  const t = { title: 'Master Of Puppets', artist: 'Metallica', key: 'C', difficulty: 4, sheetForm: 7, category: 'guitar' };
  const title = tabTitle(t);
  assert.ok(title.includes('六线谱'), title);
});

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

test('sheetForm=4 筛选语义：in [4,7] 全部为六线谱且数量一致', { skip: !isDbAvailable }, async () => {
  // 对应 queryTabs 修复：where.sheetForm = sheetForm===4||7 ? { in: [4,7] } : sheetForm
  const where = { category: 'guitar', sheetForm: { in: [4, 7] } };
  const tabs = await db.tab.findMany({ where, take: 90 });
  const total = await db.tab.count({ where });
  assert.ok(total >= 1, '六线谱(4/7) 应有结果');
  for (const t of tabs) {
    assert.ok(t.sheetForm === 4 || t.sheetForm === 7, '应只包含六线谱谱面');
  }
});

test('DB 中存在 sheetForm=7 六线谱数据（修复目标）', { skip: !isDbAvailable }, async () => {
  const n7 = await db.tab.count({ where: { category: 'guitar', sheetForm: 7 } });
  const n4 = await db.tab.count({ where: { category: 'guitar', sheetForm: 4 } });
  assert.ok(n7 >= 1, '应有 sheetForm=7 的六线谱');
  assert.ok(n4 >= 0);
});
