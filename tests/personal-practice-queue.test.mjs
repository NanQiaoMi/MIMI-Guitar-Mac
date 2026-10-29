import assert from 'node:assert/strict';
import test from 'node:test';
import {
  appendPracticeQueueItem,
  createLatestReadCoordinator,
  isVerifiedCatalogPromotion,
  matchesCatalogVerificationRecord,
  movePracticeQueueItem,
  normalizePracticeQueue,
  preferredPracticeScoreId,
  setPracticeQueueStatus,
} from '../src/lib/personal/practiceQueue.ts';

const item = (scoreId, order, status = 'todo') => ({ scoreId, order, status, note: '', updatedAt: 1 });
const orderOf = (items) => items.map(({ scoreId, order }) => [scoreId, order]);

test('normalization preserves relative order, resolves collisions stably, and separates archived entries', () => {
  const source = [item('archived', 0, 'archived'), item('second', 1), item('first', 1), item('third', 8)];
  const result = normalizePracticeQueue(source);

  assert.deepEqual(orderOf(result), [['second', 0], ['first', 1], ['third', 2], ['archived', 3]]);
  assert.deepEqual(source.map((entry) => entry.order), [0, 1, 1, 8]);
});

test('adding after removal appends after active items without colliding with archived order', () => {
  const source = [item('first', 0), item('archived', 1, 'archived'), item('third', 4)];
  const afterRemoval = normalizePracticeQueue(source.filter((entry) => entry.scoreId !== 'first'));
  const result = appendPracticeQueueItem(afterRemoval, item('new', 0));

  assert.deepEqual(orderOf(result), [['third', 0], ['new', 1], ['archived', 2]]);
});

test('active items move one position and cannot cross into the archived group', () => {
  const source = [item('a', 0), item('b', 1), item('c', 2), item('old', 3, 'archived')];
  const moved = movePracticeQueueItem(source, 'c', -1);

  assert.deepEqual(moved.map((entry) => entry.scoreId), ['a', 'c', 'b', 'old']);
  assert.deepEqual(orderOf(moved), [['a', 0], ['c', 1], ['b', 2], ['old', 3]]);
  assert.deepEqual(orderOf(movePracticeQueueItem(moved, 'a', -1)), orderOf(moved));
  assert.deepEqual(orderOf(movePracticeQueueItem(moved, 'old', -1)), orderOf(moved));
});

test('archiving moves to its own section and restoring appends at the active tail', () => {
  const source = [item('a', 0), item('b', 1), item('c', 2), item('old', 3, 'archived')];
  const archived = setPracticeQueueStatus(source, 'b', 'archived');
  assert.deepEqual(orderOf(archived), [['a', 0], ['c', 1], ['old', 2], ['b', 3]]);

  const restored = setPracticeQueueStatus(archived, 'old', 'todo');
  assert.deepEqual(orderOf(restored), [['a', 0], ['c', 1], ['old', 2], ['b', 3]]);
  assert.equal(restored.find((entry) => entry.scoreId === 'old').status, 'todo');
});

test('changing status inside the active group preserves queue position; defaults follow order and explicit requests stay explicit', () => {
  const source = [item('later', 1), item('first', 0), item('archived', 2, 'archived')];
  const practicing = setPracticeQueueStatus(source, 'first', 'practicing');
  assert.deepEqual(practicing.map((entry) => entry.scoreId), ['first', 'later', 'archived']);
  assert.equal(preferredPracticeScoreId(practicing), 'first');
  assert.equal(preferredPracticeScoreId(practicing, 'later'), 'later');
  assert.equal(preferredPracticeScoreId(practicing, 'archived'), 'archived');
  assert.equal(preferredPracticeScoreId(practicing, 'removed'), 'removed');
});

test('a newer subscription can initialize state before the initial read and stale initial data cannot replace it', async () => {
  const pending = [];
  const applied = [];
  let selection = '';
  const coordinator = createLatestReadCoordinator(
    () => new Promise((resolve) => pending.push(resolve)),
    (value, isInitial) => {
      applied.push({ value, isInitial });
      if (isInitial || selection) selection = value;
    },
  );

  const initialRead = coordinator.refresh();
  const subscriptionRead = coordinator.refresh();
  pending[1]('subscription snapshot');
  await subscriptionRead;
  assert.equal(selection, 'subscription snapshot');
  assert.deepEqual(applied, [{ value: 'subscription snapshot', isInitial: true }]);

  pending[0]('stale initial snapshot');
  await initialRead;
  assert.equal(selection, 'subscription snapshot');
  assert.equal(applied.length, 1);
});

test('disposed read coordinators ignore pending results after component destruction', async () => {
  let resolve;
  const applied = [];
  const coordinator = createLatestReadCoordinator(
    () => new Promise((done) => { resolve = done; }),
    (value) => applied.push(value),
  );
  const pending = coordinator.refresh();
  coordinator.dispose();
  resolve('late result');
  await pending;
  assert.deepEqual(applied, []);
});

test('verified promotion requires the same current catalog identity and selection generation', () => {
  const sha = 'a'.repeat(64);
  const current = { id: 'catalog:42', source: 'catalog', sourceId: '42', format: 'ibe', category: 'guitar', scoreUrl: '/scores/42.ibe', revision: 'unverified' };
  const verified = { ...current, revision: sha };
  assert.equal(isVerifiedCatalogPromotion(current, verified, 7, 7), true);

  for (const patch of [
    { id: 'catalog:43' },
    { sourceId: '43' },
    { format: 'gp' },
    { category: 'ukulele' },
    { scoreUrl: '/scores/43.ibe' },
    { assetId: 'asset' },
    { revision: 'not-a-sha' },
  ]) assert.equal(isVerifiedCatalogPromotion(current, { ...verified, ...patch }, 7, 7), false);
  assert.equal(isVerifiedCatalogPromotion(current, verified, 8, 7), false);
  assert.equal(isVerifiedCatalogPromotion({ ...current, revision: sha }, verified, 7, 7), false);
});

test('a verification stamp accepts its exact persisted hash and its own pending placeholder only', () => {
  const sha = 'a'.repeat(64);
  const unverified = { id: 'catalog:42', source: 'catalog', sourceId: '42', format: 'ibe', category: 'guitar', scoreUrl: '/scores/42.ibe', revision: 'unverified' };
  const verified = { ...unverified, revision: sha };

  assert.equal(matchesCatalogVerificationRecord(unverified, verified, verified, 3, 3), true);
  assert.equal(matchesCatalogVerificationRecord(unverified, verified, unverified, 3, 3), true);
  assert.equal(matchesCatalogVerificationRecord(unverified, verified, { ...verified, revision: 'b'.repeat(64) }, 3, 3), false);
  assert.equal(matchesCatalogVerificationRecord(unverified, verified, { ...verified, category: 'ukulele' }, 3, 3), false);
  assert.equal(matchesCatalogVerificationRecord(unverified, verified, { ...verified, scoreUrl: '/scores/other.ibe' }, 3, 3), false);
  assert.equal(matchesCatalogVerificationRecord(unverified, verified, verified, 4, 3), false);
});
