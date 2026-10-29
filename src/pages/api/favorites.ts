import type { APIRoute } from 'astro';
import { db } from '../../lib/db';
import { json, currentUser } from '../../lib/api';

export const GET: APIRoute = async ({ cookies }) => {
  const user = await currentUser(cookies);
  if (!user) return json({ error: '未登录' }, 401);
  const favs = await db.favorite.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: 'desc' },
    include: {
      tab: {
        select: {
          id: true, title: true, artist: true, category: true, key: true,
          sheetForm: true, difficulty: true, heat: true, screenshotUrl: true,
        },
      },
    },
  });
  return json({ ok: true, favorites: favs.map((f) => f.tab) });
};