import type { APIRoute } from 'astro';
import { db } from '../../lib/db';
import { json } from '../../lib/api';
import type { CatalogSource } from '../../lib/tabQuery';
import { withCatalogRead } from '../../lib/catalogReadGate';

/** GET /api/search?q=...&category=...&limit=... */
export const GET: APIRoute = async ({ request }) => {
  const url = new URL(request.url);
  const q = (url.searchParams.get('q') ?? '').trim();
  const requestedCategory = (url.searchParams.get('category') ?? 'all').trim();
  const category = ['all', 'guitar', 'ukulele'].includes(requestedCategory) ? requestedCategory : 'all';
  const rawLimit = url.searchParams.get('limit');
  const parsedLimit = rawLimit && /^\d+$/.test(rawLimit) ? Number(rawLimit) : 10;
  const limit = Number.isSafeInteger(parsedLimit) && parsedLimit > 0 ? Math.min(parsedLimit, 40) : 10;
  const where: any = {};
  if (category !== 'all') where.category = category;
  if (q) where.OR = [
    { title: { contains: q, mode: 'insensitive' } },
    { artist: { contains: q, mode: 'insensitive' } },
    { tags: { contains: q, mode: 'insensitive' } },
    { key: { contains: q, mode: 'insensitive' } },
  ];

  try {
    const [tabsResult, countResult] = await Promise.allSettled([
      withCatalogRead(() => db.tab.findMany({
        where,
        select: { id: true, title: true, artist: true, category: true, difficulty: true, sheetForm: true,
          key: true, tuning: true, heat: true, screenshotUrl: true, format: true, bpm: true, scoreUrl: true, xheUrl: true },
        orderBy: q ? [{ heat: 'desc' }] : [{ heat: 'desc' }, { publishDate: 'desc' }],
        take: limit,
      })),
      withCatalogRead(() => db.tab.count({ where })),
    ]);
    if (tabsResult.status === 'rejected') throw tabsResult.reason;
    if (countResult.status === 'rejected') throw countResult.reason;
    const tabs = tabsResult.value;
    const total = countResult.value;
    return json({ ok: true, source: 'catalog' satisfies CatalogSource, query: q, category, total, tabs });
  } catch {
    try {
      const { DEMO_TABS } = await import('../../lib/demoData');
      const needle = q.toLocaleLowerCase();
      const filtered = DEMO_TABS.filter((tab) =>
        (category === 'all' || tab.category === category) && (!needle || [tab.title, tab.artist, tab.key, tab.tags]
          .some((value) => String(value ?? '').toLocaleLowerCase().includes(needle)))
      ).sort((a, b) => b.heat - a.heat);
      return json({ ok: true, source: 'demo' satisfies CatalogSource, query: q, category, total: filtered.length, tabs: filtered.slice(0, limit) });
    } catch {
      return json({ ok: false, source: 'unavailable' satisfies CatalogSource, error: 'catalog_unavailable', query: q, category, total: 0, tabs: [] }, 503);
    }
  }
};
