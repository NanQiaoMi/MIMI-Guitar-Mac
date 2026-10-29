import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildCatalogCategoryHref,
  buildClearFiltersHref,
  buildSearchCategoryHref,
  buildTabQueryHref,
  buildTabWhere,
  buildListHref,
  matchesTabQuery,
  parseListParams,
  serializeListParams,
  sortCatalogTabs,
} from '../src/lib/tabQuery.ts';

test('query parser validates page and numeric filters and accepts the shared sort contract', () => {
  const parsed = parseListParams(new URLSearchParams('difficulty=3&style=102&sheetForm=4&sort=2&no=7&key=C%23&tuning=Drop+D'), 'guitar');
  assert.deepEqual(parsed, {
    category: 'guitar', difficulty: 3, style: 102, sheetForm: 4, sort: 2, no: 7, key: 'C#', tuning: 'Drop D',
    keyword: undefined, searchField: undefined,
  });

  for (const rawPage of ['0', '-1', '1.5', 'Infinity', '9007199254740992', 'oops']) {
    assert.equal(parseListParams(new URLSearchParams(`no=${encodeURIComponent(rawPage)}&difficulty=99&sort=8`), 'guitar').no, 1);
  }
  const invalid = parseListParams(new URLSearchParams('difficulty=99&style=abc&sheetForm=9&sort=8'), 'guitar');
  assert.equal(invalid.difficulty, undefined);
  assert.equal(invalid.style, undefined);
  assert.equal(invalid.sheetForm, undefined);
  assert.equal(invalid.sort, 1);
});

test('key filters compare the full key and tuning exactly, with six-line aliases retained', () => {
  const params = { category: 'guitar', key: 'C', tuning: 'Drop D', sheetForm: 4 };
  assert.equal(matchesTabQuery({ category: 'guitar', key: 'C', tuning: 'Drop D', sheetForm: 7 }, params), true);
  assert.equal(matchesTabQuery({ category: 'guitar', key: 'C#', tuning: 'Drop D', sheetForm: 4 }, params), false);
  assert.equal(matchesTabQuery({ category: 'guitar', key: 'C', tuning: 'Standard', sheetForm: 4 }, params), false);
});

test('all-category query keeps shared filters in one database where clause', () => {
  const params = parseListParams(new URLSearchParams('keyword=周杰伦&field=artist&difficulty=2&style=102&key=G&tuning=Drop+D&sheetForm=4'), 'all');
  const where = buildTabWhere(params);
  assert.equal('category' in where, false);
  assert.deepEqual(where.artist, { contains: '周杰伦', mode: 'insensitive' });
  assert.equal(where.difficulty, 2);
  assert.equal(where.style, 102);
  assert.equal(where.key, 'G');
  assert.equal(where.tuning, 'Drop D');
  assert.deepEqual(where.sheetForm, { in: [4, 7] });
  assert.equal(matchesTabQuery({ category: 'guitar', artist: '周杰伦', difficulty: 2, style: 102, key: 'G', tuning: 'Drop D', sheetForm: 7 }, params), true);
  assert.equal(matchesTabQuery({ category: 'ukulele', artist: '周杰伦', difficulty: 2, style: 102, key: 'G', tuning: 'Drop D', sheetForm: 7 }, params), true);
  assert.equal(matchesTabQuery({ category: 'bass', artist: '周杰伦', difficulty: 2, style: 102, key: 'G', tuning: 'Drop D', sheetForm: 7 }, params), true);
});

test('sort values map to newest, heat, and difficulty in a stable descending order', () => {
  const tabs = [
    { id: 'old', publishDate: '2020-01-01', heat: 99, difficulty: 1 },
    { id: 'hot', publishDate: '2022-01-01', heat: 100, difficulty: 2 },
    { id: 'new', publishDate: '2024-01-01', heat: 10, difficulty: 5 },
  ];
  assert.deepEqual(sortCatalogTabs([...tabs], 0).map((t) => t.id), ['new', 'hot', 'old']);
  assert.deepEqual(sortCatalogTabs([...tabs], 1).map((t) => t.id), ['hot', 'old', 'new']);
  assert.deepEqual(sortCatalogTabs([...tabs], 2).map((t) => t.id), ['new', 'hot', 'old']);
});

test('serialization and pagination links preserve all filters while replacing only the page', () => {
  const params = parseListParams(new URLSearchParams('keyword=blue&field=artist&difficulty=2&style=103&key=G&tuning=Open+G&sheetForm=1&sort=0&no=3&keep=yes'), 'guitar');
  const href = buildListHref('/tabs', { ...params, no: 4 }, new URLSearchParams('keep=yes&tracking=abc'));
  const url = new URL(href, 'https://example.test');
  assert.equal(url.pathname, '/tabs');
  assert.equal(url.searchParams.get('no'), '4');
  assert.equal(url.searchParams.get('keyword'), 'blue');
  assert.equal(url.searchParams.get('field'), 'artist');
  assert.equal(url.searchParams.get('difficulty'), '2');
  assert.equal(url.searchParams.get('style'), '103');
  assert.equal(url.searchParams.get('key'), 'G');
  assert.equal(url.searchParams.get('tuning'), 'Open G');
  assert.equal(url.searchParams.get('sheetForm'), '1');
  assert.equal(url.searchParams.get('sort'), '0');
  assert.equal(url.searchParams.get('tracking'), 'abc');

  const roundTrip = parseListParams(serializeListParams(params), 'guitar');
  assert.equal(roundTrip.keyword, params.keyword);
  assert.equal(roundTrip.no, params.no);
  assert.equal(roundTrip.sort, params.sort);
});

test('legacy record links keep explicit newest sort zero and remove stale page aliases', () => {
  const href = buildListHref('/tabs', { sort: 0, difficulty: 0, key: '全部', no: 2 }, new URLSearchParams('page=9&style=102'));
  const url = new URL(href, 'https://example.test');
  assert.equal(url.searchParams.get('sort'), '0');
  assert.equal(url.searchParams.get('no'), '2');
  assert.equal(url.searchParams.has('difficulty'), false);
  assert.equal(url.searchParams.has('page'), false);
  assert.equal(url.searchParams.get('style'), '102');

  const serialized = serializeListParams({ category: 'guitar', sort: 0, no: 3 }, new URLSearchParams('page=8&keyword=old'));
  assert.equal(serialized.get('sort'), '0');
  assert.equal(serialized.has('page'), false);
});

test('tab query updates preserve newest sort zero, existing query state, hash, and reset pagination', () => {
  const current = 'https://example.test/tabs?difficulty=2&style=102&sheetForm=4&keyword=blue&field=artist&tracking=keep&sort=2&no=9&page=6#results';
  const newest = new URL(buildTabQueryHref(current, { sort: 0 }), 'https://example.test');
  assert.equal(newest.pathname, '/tabs');
  assert.equal(newest.searchParams.get('sort'), '0');
  assert.equal(newest.searchParams.get('difficulty'), '2');
  assert.equal(newest.searchParams.get('style'), '102');
  assert.equal(newest.searchParams.get('sheetForm'), '4');
  assert.equal(newest.searchParams.get('keyword'), 'blue');
  assert.equal(newest.searchParams.get('field'), 'artist');
  assert.equal(newest.searchParams.get('tracking'), 'keep');
  assert.equal(newest.searchParams.get('no'), '1');
  assert.equal(newest.searchParams.has('page'), false);
  assert.equal(newest.hash, '#results');

  const cleared = new URL(
    buildTabQueryHref(newest.href, { difficulty: 0, style: '0', sheetForm: 0, sort: undefined }),
    'https://example.test',
  );
  for (const key of ['difficulty', 'style', 'sheetForm', 'sort', 'page']) {
    assert.equal(cleared.searchParams.has(key), false, `${key} should be cleared`);
  }
  assert.equal(cleared.searchParams.get('keyword'), 'blue');
  assert.equal(cleared.searchParams.get('tracking'), 'keep');
  assert.equal(cleared.searchParams.get('no'), '1');
  assert.equal(cleared.hash, '#results');
});

test('category switch opens the all-catalog route and preserves valid filters while resetting pagination', () => {
  const href = buildCatalogCategoryHref('https://example.test/tabs?keyword=blue&field=artist&difficulty=2&style=102&key=G&tuning=Drop+D&sheetForm=4&sort=0&page=9&no=9', 'all');
  const url = new URL(href, 'https://example.test');
  assert.equal(url.pathname, '/searchResults');
  assert.equal(url.searchParams.get('type'), 'all');
  assert.equal(url.searchParams.get('searchValue'), 'blue');
  assert.equal(url.searchParams.has('keyword'), false);
  assert.equal(url.searchParams.get('field'), 'artist');
  assert.equal(url.searchParams.get('difficulty'), '2');
  assert.equal(url.searchParams.get('style'), '102');
  assert.equal(url.searchParams.get('key'), 'G');
  assert.equal(url.searchParams.get('tuning'), 'Drop D');
  assert.equal(url.searchParams.get('sheetForm'), '4');
  assert.equal(url.searchParams.get('sort'), '0');
  assert.equal(url.searchParams.get('no'), '1');
  assert.equal(url.searchParams.has('page'), false);
});

test('clearing filters keeps the effective keyword and category but resets every filter, sort, and page', () => {
  const href = buildClearFiltersHref(
    'https://example.test/searchResults?type=all&searchValue=blue&keyword=stale&difficulty=2&style=102&key=G&tuning=Drop+D&sheetForm=4&field=artist&sort=0&no=8&page=4&tracking=abc',
    'all',
  );
  const url = new URL(href, 'https://example.test');
  assert.equal(url.pathname, '/searchResults');
  assert.equal(url.searchParams.get('type'), 'all');
  assert.equal(url.searchParams.get('searchValue'), 'blue');
  for (const key of ['keyword', 'difficulty', 'style', 'key', 'tuning', 'sheetForm', 'field', 'page', 'tracking']) {
    assert.equal(url.searchParams.has(key), false, `${key} should be cleared`);
  }
  assert.equal(url.searchParams.get('sort'), '1');
  assert.equal(url.searchParams.get('no'), '1');

  const legacyKeyword = new URL(buildClearFiltersHref('/searchResults?keyword=artist+name&key=G', 'guitar'), 'https://example.test');
  assert.equal(legacyKeyword.searchParams.get('type'), 'guitar');
  assert.equal(legacyKeyword.searchParams.get('searchValue'), 'artist name');
  assert.equal(legacyKeyword.searchParams.has('key'), false);
});

test('search category links open the catalog lists without losing valid filters or the effective keyword', () => {
  const current = 'https://example.test/searchResults?type=all&searchValue=blue&keyword=stale&field=artist&difficulty=2&style=102&key=G&tuning=Drop+D&sheetForm=4&sort=0&page=9&no=7';
  for (const [category, path] of [['guitar', '/tabs'], ['ukulele', '/ukulele']]) {
    const url = new URL(buildSearchCategoryHref(current, category, 0), 'https://example.test');
    assert.equal(url.pathname, path);
    assert.equal(url.searchParams.has('type'), false);
    assert.equal(url.searchParams.get('searchValue'), 'blue');
    assert.equal(url.searchParams.has('keyword'), false);
    assert.equal(url.searchParams.get('field'), 'artist');
    assert.equal(url.searchParams.get('difficulty'), '2');
    assert.equal(url.searchParams.get('style'), '102');
    assert.equal(url.searchParams.get('key'), 'G');
    assert.equal(url.searchParams.get('tuning'), 'Drop D');
    assert.equal(url.searchParams.get('sheetForm'), '4');
    assert.equal(url.searchParams.get('sort'), '0');
    assert.equal(url.searchParams.get('no'), '1');
    assert.equal(url.searchParams.has('page'), false);
  }
});

test('empty article search opens the article index; keyword article search keeps only supported query state', () => {
  assert.equal(buildSearchCategoryHref('/searchResults?type=all&key=G&no=8', 'article', 2), '/article');
  const url = new URL(
    buildSearchCategoryHref('/searchResults?type=all&searchValue=music&difficulty=2&key=G&page=8', 'article', 2),
    'https://example.test',
  );
  assert.equal(url.pathname, '/searchResults');
  assert.equal(url.searchParams.get('type'), 'article');
  assert.equal(url.searchParams.get('searchValue'), 'music');
  assert.equal(url.searchParams.get('sort'), '1');
  assert.equal(url.searchParams.get('no'), '1');
  assert.equal(url.searchParams.has('difficulty'), false);
  assert.equal(url.searchParams.has('key'), false);
  assert.equal(url.searchParams.has('page'), false);
});
