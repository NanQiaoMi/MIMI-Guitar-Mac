import type { APIRoute } from 'astro';
import { db } from '../../../lib/db';
import { DEMO_TABS } from '../../../lib/demoData';
import { json } from '../../../lib/api';

/** Read-only score metadata used by the studio's personal-copy workflow. */
export const GET: APIRoute = async ({ params }) => {
  const id = params.id ?? '';
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(id)) return json({ error: '曲谱编号不正确' }, 400);

  let tab: any = null;
  let source: 'database' | 'demo' = 'database';
  let catalogUnavailable = false;
  try {
    tab = await db.tab.findUnique({ where: { id } });
  } catch {
    catalogUnavailable = true;
  }
  if (!tab) {
    tab = DEMO_TABS.find((item) => item.id === id) ?? null;
    if (tab) source = 'demo';
  }
  if (!tab) return json({ error: catalogUnavailable ? '曲库暂时不可用，无法确认曲谱状态' : '没有找到这份曲谱' }, catalogUnavailable ? 503 : 404);

  return json({
    id: tab.id,
    title: tab.title,
    artist: tab.artist ?? '',
    category: tab.category ?? 'guitar',
    key: tab.key ?? 'C',
    tempo: tab.bpm ?? 120,
    format: tab.format ?? 'ibe',
    source,
    scoreUrl: tab.scoreUrl ?? '',
    xheUrl: tab.xheUrl ?? '',
    downloadUrl: `/api/tabs/${encodeURIComponent(id)}/download`,
  });
};
