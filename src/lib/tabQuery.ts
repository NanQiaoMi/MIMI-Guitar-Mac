import { DEMO_TABS } from './demoData.ts';
import { withCatalogRead } from './catalogReadGate.ts';

export const DIFFICULTY_OPTIONS = [
  { value: 0, label: '全部' }, { value: 1, label: '零基础' }, { value: 2, label: '初级' },
  { value: 3, label: '中级' }, { value: 4, label: '高级' }, { value: 5, label: '专业' },
] as const;
export const STYLE_OPTIONS = [
  { value: 0, label: '全部类型' }, { value: 101, label: '流行' }, { value: 102, label: '摇滚' },
  { value: 103, label: '民谣' }, { value: 105, label: '配乐' }, { value: 107, label: '乡村' }, { value: 109, label: '金属' },
] as const;
export const FORM_OPTIONS = [
  { value: 0, label: '全部谱型' }, { value: 1, label: '弹唱谱' }, { value: 2, label: '指弹谱' },
  { value: 3, label: '和弦谱' }, { value: 4, label: '六线谱' },
] as const;
export const KEY_OPTIONS = ['全部', 'C', 'C#', 'D', 'Db', 'E', 'Eb', 'F', 'F#', 'G', 'G#', 'A', 'Ab', 'B', 'Bb'] as const;
export const TUNING_OPTIONS = ['全部', 'Standard', 'Half-Step Down', 'Drop D', 'Open G', 'DADGAD', 'Open D'] as const;
export const PAGE_SIZE = 90;

export type CatalogSource = 'catalog' | 'demo' | 'unavailable';
export type ListSort = 0 | 1 | 2; // 0=最新 1=热度 2=难度
export interface ListParams {
  category: string;
  difficulty?: number;
  style?: number;
  key?: string;
  tuning?: string;
  sheetForm?: number;
  sort?: ListSort;
  no?: number;
  keyword?: string;
  searchField?: 'title' | 'artist' | 'all';
  pageSize?: number;
}
export interface ListResult {
  tabs: any[];
  total: number;
  page: number;
  pageCount: number;
  pageSize: number;
  source: CatalogSource;
}

function validNumber(value: string | null, allowed: readonly number[]): number | undefined {
  if (value === null || !/^\d+$/.test(value)) return undefined;
  const n = Number(value);
  return Number.isSafeInteger(n) && allowed.includes(n) ? n : undefined;
}
function validText(value: string | null, allowed: readonly string[]): string | undefined {
  return value && allowed.includes(value) ? value : undefined;
}
export function parseListParams(search: URLSearchParams, category: string): ListParams {
  const difficulty = validNumber(search.get('difficulty'), [0, 1, 2, 3, 4, 5]);
  const style = validNumber(search.get('style'), [0, ...STYLE_OPTIONS.slice(1).map((item) => item.value)]);
  const sheetForm = validNumber(search.get('sheetForm'), [0, 1, 2, 3, 4, 7]);
  const sort = validNumber(search.get('sort'), [0, 1, 2]) as ListSort | undefined;
  const rawPage = search.get('no') ?? search.get('page');
  const no = rawPage && /^\d+$/.test(rawPage) && Number.isSafeInteger(Number(rawPage)) && Number(rawPage) > 0
    ? Number(rawPage) : 1;
  const field = validText(search.get('field'), ['title', 'artist', 'all']);
  return {
    category,
    difficulty: difficulty && difficulty > 0 ? difficulty : undefined,
    style: style && style > 0 ? style : undefined,
    key: validText(search.get('key'), KEY_OPTIONS.filter((key) => key !== '全部')),
    tuning: validText(search.get('tuning'), TUNING_OPTIONS.filter((tuning) => tuning !== '全部')),
    sheetForm: sheetForm && sheetForm > 0 ? sheetForm : undefined,
    sort: sort ?? 1,
    no,
    keyword: (search.get('keyword') ?? search.get('searchValue') ?? '').trim() || undefined,
    searchField: field as ListParams['searchField'],
  };
}

const PARAM_KEYS = ['difficulty', 'style', 'key', 'tuning', 'sheetForm', 'sort', 'no', 'page', 'keyword', 'searchValue', 'field', 'type'];
export function buildTabQueryHref(
  currentHref: string,
  overrides: Record<string, string | number | undefined>,
): string {
  const url = new URL(currentHref, 'http://localhost');
  for (const [key, value] of Object.entries(overrides)) {
    const isDefaultZero = (value === 0 || value === '0') && key !== 'sort';
    if (value === undefined || value === '' || isDefaultZero) url.searchParams.delete(key);
    else url.searchParams.set(key, String(value));
  }
  url.searchParams.set('no', '1');
  url.searchParams.delete('page');
  return `${url.pathname}${url.search}${url.hash}`;
}

export function serializeListParams(params: ListParams, base = new URLSearchParams()): URLSearchParams {
  const q = new URLSearchParams(base);
  for (const key of PARAM_KEYS) q.delete(key);
  if (params.difficulty) q.set('difficulty', String(params.difficulty));
  if (params.style) q.set('style', String(params.style));
  if (params.key) q.set('key', params.key);
  if (params.tuning) q.set('tuning', params.tuning);
  if (params.sheetForm) q.set('sheetForm', String(params.sheetForm));
  q.set('sort', String(params.sort ?? 1));
  q.set('no', String(params.no ?? 1));
  if (params.keyword) q.set('keyword', params.keyword);
  if (params.searchField && params.searchField !== 'all') q.set('field', params.searchField);
  return q;
}
export function buildListHref(pathOrCategory: string, params: ListParams | Record<string, string | number | undefined>, base = new URLSearchParams()): string {
  const path = pathOrCategory.startsWith('/') ? pathOrCategory : `/${pathOrCategory}`;
  if ('category' in params || 'searchField' in params) {
    const query = serializeListParams(params as ListParams, base).toString();
    return query ? `${path}?${query}` : path;
  }
  const merged = { ...Object.fromEntries(base), ...params } as Record<string, string | number | undefined>;
  delete merged.page;
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(merged)) {
    if (value === undefined || value === '' || (value === 0 && key !== 'sort') || value === '全部') continue;
    query.set(key, String(value));
  }
  const serialized = query.toString();
  return serialized ? `${path}?${serialized}` : path;
}

export function buildCatalogCategoryHref(currentHref: string, category: 'all' | 'guitar' | 'ukulele'): string {
  const url = new URL(currentHref, 'http://localhost');
  const keyword = (url.searchParams.get('searchValue') || url.searchParams.get('keyword') || '').trim();
  url.searchParams.delete('searchValue');
  url.searchParams.delete('keyword');
  if (keyword) url.searchParams.set('searchValue', keyword);
  if (category === 'all') {
    url.pathname = '/searchResults';
    url.searchParams.set('type', 'all');
  } else {
    url.pathname = category === 'ukulele' ? '/ukulele' : '/tabs';
    url.searchParams.delete('type');
  }
  url.searchParams.set('no', '1');
  url.searchParams.delete('page');
  return `${url.pathname}${url.search}`;
}

export function buildSearchCategoryHref(
  currentHref: string,
  category: 'all' | 'guitar' | 'ukulele' | 'article',
  sort: ListSort = 1,
): string {
  if (category !== 'article') return buildCatalogCategoryHref(currentHref, category);

  const url = new URL(currentHref, 'http://localhost');
  const keyword = (url.searchParams.get('searchValue') || url.searchParams.get('keyword') || '').trim();
  if (!keyword) return '/article';

  const query = new URLSearchParams({
    type: 'article',
    searchValue: keyword,
    sort: String(sort === 0 ? 0 : 1),
    no: '1',
  });
  return `/searchResults?${query.toString()}`;
}

export function buildClearFiltersHref(currentHref: string, category: 'all' | 'guitar' | 'ukulele' | 'article'): string {
  const url = new URL(currentHref, 'http://localhost');
  const keyword = (url.searchParams.get('searchValue') || url.searchParams.get('keyword') || '').trim();
  const query = new URLSearchParams({ type: category, sort: '1', no: '1' });
  if (keyword) query.set('searchValue', keyword);
  return `/searchResults?${query.toString()}`;
}

export function formLabel(f: number | null | undefined): string {
  const m: Record<number, string> = { 1: '弹唱谱', 2: '指弹谱', 3: '和弦谱', 4: '六线谱', 7: '六线谱' };
  return f ? (m[f] ?? '其他') : '谱';
}
export function heatText(heat: number | null | undefined): string {
  const h = heat ?? 0;
  if (h >= 10000) return (h / 10000).toFixed(1) + '万';
  return String(h);
}

export function sortCatalogTabs<T extends { heat?: number | null; difficulty?: number | null; publishDate?: string | Date | null }>(tabs: T[], sort: ListSort): T[] {
  return tabs.sort((a, b) => {
    if (sort === 0) return new Date(b.publishDate ?? 0).getTime() - new Date(a.publishDate ?? 0).getTime();
    if (sort === 2) return (b.difficulty ?? 0) - (a.difficulty ?? 0);
    return (b.heat ?? 0) - (a.heat ?? 0);
  });
}
export function matchesTabQuery(t: any, params: ListParams): boolean {
  if (params.category !== 'all' && t.category !== params.category) return false;
  if (params.keyword) {
    const q = params.keyword.toLocaleLowerCase();
    const title = String(t.title ?? '').toLocaleLowerCase();
    const artist = String(t.artist ?? '').toLocaleLowerCase();
    if (params.searchField === 'title' ? !title.includes(q) : params.searchField === 'artist' ? !artist.includes(q) : !title.includes(q) && !artist.includes(q)) return false;
  }
  if (params.difficulty && t.difficulty !== params.difficulty) return false;
  if (params.style && t.style !== params.style) return false;
  if (params.key && t.key !== params.key) return false;
  if (params.tuning && t.tuning !== params.tuning) return false;
  if (params.sheetForm && (params.sheetForm === 4 ? ![4, 7].includes(t.sheetForm) : t.sheetForm !== params.sheetForm)) return false;
  return true;
}

export function buildTabWhere(params: ListParams): Record<string, any> {
  const where: Record<string, any> = {};
  if (params.category !== 'all') where.category = params.category;
  if (params.keyword) {
    if (params.searchField === 'title') where.title = { contains: params.keyword, mode: 'insensitive' };
    else if (params.searchField === 'artist') where.artist = { contains: params.keyword, mode: 'insensitive' };
    else where.OR = [
      { title: { contains: params.keyword, mode: 'insensitive' } },
      { artist: { contains: params.keyword, mode: 'insensitive' } },
    ];
  }
  if (params.difficulty) where.difficulty = params.difficulty;
  if (params.style) where.style = params.style;
  if (params.key) where.key = params.key;
  if (params.tuning) where.tuning = params.tuning;
  if (params.sheetForm) where.sheetForm = params.sheetForm === 4 ? { in: [4, 7] } : params.sheetForm;
  return where;
}
function pageResult(tabs: any[], total: number, requestedPage: number, source: CatalogSource, pageSize: number): ListResult {
  const pageCount = Math.max(1, Math.ceil(total / pageSize));
  const page = Math.min(requestedPage, pageCount);
  return { tabs: tabs.slice((page - 1) * pageSize, page * pageSize), total, page, pageCount, pageSize, source };
}

export interface CatalogTabReader {
  count(args: { where: Record<string, any> }): Promise<number>;
  findMany(args: {
    where: Record<string, any>;
    orderBy: { publishDate?: 'asc' | 'desc'; difficulty?: 'asc' | 'desc'; heat?: 'asc' | 'desc' };
    skip: number;
    take: number;
  }): Promise<any[]>;
}

function settledValue<T>(result: PromiseSettledResult<T>): T {
  if (result.status === 'rejected') throw result.reason;
  return result.value;
}

/**
 * Execute count and the requested page concurrently. If count shows the page
 * is out of range, fetch the clamped page before returning a catalog result.
 */
export async function queryCatalogTabs(params: ListParams, reader: CatalogTabReader): Promise<ListResult> {
  const requestedPage = Number.isSafeInteger(params.no) && (params.no ?? 0) > 0 ? params.no! : 1;
  const pageSize = Number.isSafeInteger(params.pageSize) && (params.pageSize ?? 0) > 0 && (params.pageSize ?? 0) <= PAGE_SIZE ? params.pageSize! : PAGE_SIZE;
  const normalized = { ...params, sort: params.sort ?? 1 };
  const where = buildTabWhere(params);
  const orderBy = normalized.sort === 0 ? { publishDate: 'desc' as const }
    : normalized.sort === 2 ? { difficulty: 'desc' as const }
      : { heat: 'desc' as const };
  const readPage = (page: number) => reader.findMany({
    where,
    orderBy,
    skip: (page - 1) * pageSize,
    take: pageSize,
  });

  const [countResult, requestedRowsResult] = await Promise.allSettled([
    reader.count({ where }),
    readPage(requestedPage),
  ]);
  const total = settledValue(countResult);
  let tabs = settledValue(requestedRowsResult);
  const pageCount = Math.max(1, Math.ceil(total / pageSize));
  const page = Math.min(requestedPage, pageCount);
  if (page !== requestedPage) tabs = await readPage(page);

  return { tabs, total, page, pageCount, pageSize, source: 'catalog' };
}

export async function queryTabs(params: ListParams): Promise<ListResult> {
  const requestedPage = Number.isSafeInteger(params.no) && (params.no ?? 0) > 0 ? params.no! : 1;
  const pageSize = Number.isSafeInteger(params.pageSize) && (params.pageSize ?? 0) > 0 && (params.pageSize ?? 0) <= PAGE_SIZE ? params.pageSize! : PAGE_SIZE;
  const normalized = { ...params, sort: params.sort ?? 1 };
  try {
    const { db } = await import('./db');
    return await queryCatalogTabs({ ...params, ...normalized, pageSize }, {
      count: (args) => withCatalogRead(() => db.tab.count(args)),
      findMany: (args) => withCatalogRead(() => db.tab.findMany(args)),
    });
  } catch {
    try {
      const filtered = sortCatalogTabs(DEMO_TABS.filter((t) => matchesTabQuery(t, params)), normalized.sort!);
      return pageResult(filtered, filtered.length, requestedPage, 'demo', pageSize);
    } catch {
      return { tabs: [], total: 0, page: 1, pageCount: 1, pageSize, source: 'unavailable' };
    }
  }
}
