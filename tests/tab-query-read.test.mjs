import { test } from 'node:test';
import assert from 'node:assert/strict';
import { queryCatalogTabs } from '../src/lib/tabQuery.ts';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test('catalog count and requested page begin concurrently', async () => {
  const count = deferred();
  const rows = deferred();
  const calls = [];
  const query = queryCatalogTabs({ category: 'guitar', sort: 0, no: 2, pageSize: 3 }, {
    count: (args) => { calls.push(['count', args]); return count.promise; },
    findMany: (args) => { calls.push(['findMany', args]); return rows.promise; },
  });

  assert.deepEqual(calls.map(([kind]) => kind), ['count', 'findMany']);
  assert.deepEqual(calls[1][1].orderBy, { publishDate: 'desc' });
  assert.equal(calls[1][1].skip, 3);
  rows.resolve([{ id: 'page-2' }]);
  count.resolve(5);

  assert.deepEqual(await query, {
    tabs: [{ id: 'page-2' }], total: 5, page: 2, pageCount: 2, pageSize: 3, source: 'catalog',
  });
});

test('out-of-range catalog pages issue a corrective query and return the clamped page', async () => {
  const calls = [];
  const result = await queryCatalogTabs({ category: 'ukulele', sort: 1, no: 5, pageSize: 2 }, {
    count: async (args) => { calls.push(['count', args]); return 5; },
    findMany: async (args) => {
      calls.push(['findMany', args]);
      return args.skip === 4 ? [{ id: 'last-page' }] : [];
    },
  });

  assert.equal(result.page, 3);
  assert.equal(result.pageCount, 3);
  assert.deepEqual(result.tabs, [{ id: 'last-page' }]);
  assert.deepEqual(calls.filter(([kind]) => kind === 'findMany').map(([, args]) => args.skip), [8, 4]);
});

test('zero-result catalog pagination still clamps to page one', async () => {
  const skips = [];
  const result = await queryCatalogTabs({ category: 'all', no: 9, pageSize: 10 }, {
    count: async () => 0,
    findMany: async ({ skip }) => { skips.push(skip); return []; },
  });

  assert.equal(result.page, 1);
  assert.equal(result.pageCount, 1);
  assert.deepEqual(skips, [80, 0]);
});
