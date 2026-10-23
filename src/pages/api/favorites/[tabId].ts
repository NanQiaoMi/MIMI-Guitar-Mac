import type { APIRoute } from 'astro';
import { db } from '../../../lib/db';
import { json, currentUser } from '../../../lib/api';

export const GET: APIRoute = async ({ params, cookies }) => {
  const tabId = params.tabId ?? '';
  try {
    const user = await currentUser(cookies);
    if (!user) return json({ ok: true, favorited: false, count: 0 });
    const fav = await db.favorite.findUnique({ where: { userId_tabId: { userId: user.id, tabId } } });
    const count = await db.favorite.count({ where: { tabId } });
    return json({ ok: true, favorited: !!fav, count });
  } catch {
    return json({ error: '收藏状态暂时无法读取，请稍后重试' }, 503);
  }
};

export const POST: APIRoute = async ({ params, cookies }) => {
  const tabId = params.tabId ?? '';
  try {
    const user = await currentUser(cookies);
    if (!user) return json({ error: '请先登录' }, 401);
    const tab = await db.tab.findUnique({ where: { id: tabId } });
    if (!tab) return json({ error: '曲谱不存在' }, 404);
    await db.favorite.upsert({
      where: { userId_tabId: { userId: user.id, tabId } },
      update: {},
      create: { userId: user.id, tabId },
    });
    const count = await db.favorite.count({ where: { tabId } });
    return json({ ok: true, count });
  } catch {
    return json({ error: '收藏未能保存，请检查数据库连接后重试' }, 503);
  }
};

export const DELETE: APIRoute = async ({ params, cookies }) => {
  const tabId = params.tabId ?? '';
  try {
    const user = await currentUser(cookies);
    if (!user) return json({ error: '请先登录' }, 401);
    await db.favorite.deleteMany({ where: { userId: user.id, tabId } });
    const count = await db.favorite.count({ where: { tabId } });
    return json({ ok: true, count });
  } catch {
    return json({ error: '取消收藏未能保存，请检查数据库连接后重试' }, 503);
  }
};
