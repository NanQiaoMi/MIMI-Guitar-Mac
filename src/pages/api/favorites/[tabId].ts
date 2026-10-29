import type { APIRoute } from 'astro';
import { db } from '../../../lib/db';
import { json, currentUser } from '../../../lib/api';
import { successResponse, errorResponse, isDatabaseError } from '../../../lib/errorBoundary';

export const GET: APIRoute = async ({ params, cookies }) => {
  const tabId = params.tabId ?? '';
  try {
    const user = await currentUser(cookies);
    if (!user) return json(successResponse({ favorited: false, count: 0 }));

    const fav = await db.favorite.findUnique({
      where: { userId_tabId: { userId: user.id, tabId } }
    });
    const count = await db.favorite.count({ where: { tabId } });

    return json(successResponse({ favorited: !!fav, count }));
  } catch (error) {
    console.error('[favorites] GET error:', error);
    if (isDatabaseError(error)) {
      return json(errorResponse('DATABASE_ERROR', '收藏状态暂时无法读取，请稍后重试', true), 503);
    }
    return json(errorResponse('INTERNAL_ERROR', '获取收藏状态失败', true), 500);
  }
};

export const POST: APIRoute = async ({ params, cookies }) => {
  const tabId = params.tabId ?? '';
  try {
    const user = await currentUser(cookies);
    if (!user) {
      return json(errorResponse('UNAUTHORIZED', '请先登录', false), 401);
    }

    const tab = await db.tab.findUnique({ where: { id: tabId } });
    if (!tab) {
      return json(errorResponse('NOT_FOUND', '曲谱不存在', false), 404);
    }

    await db.favorite.upsert({
      where: { userId_tabId: { userId: user.id, tabId } },
      update: {},
      create: { userId: user.id, tabId },
    });

    const count = await db.favorite.count({ where: { tabId } });
    return json(successResponse({ count }));
  } catch (error) {
    console.error('[favorites] POST error:', error);
    if (isDatabaseError(error)) {
      return json(errorResponse('DATABASE_ERROR', '收藏未能保存，请检查数据库连接后重试', true), 503);
    }
    return json(errorResponse('INTERNAL_ERROR', '收藏操作失败', true), 500);
  }
};

export const DELETE: APIRoute = async ({ params, cookies }) => {
  const tabId = params.tabId ?? '';
  try {
    const user = await currentUser(cookies);
    if (!user) {
      return json(errorResponse('UNAUTHORIZED', '请先登录', false), 401);
    }

    await db.favorite.deleteMany({ where: { userId: user.id, tabId } });
    const count = await db.favorite.count({ where: { tabId } });

    return json(successResponse({ count }));
  } catch (error) {
    console.error('[favorites] DELETE error:', error);
    if (isDatabaseError(error)) {
      return json(errorResponse('DATABASE_ERROR', '取消收藏未能保存，请检查数据库连接后重试', true), 503);
    }
    return json(errorResponse('INTERNAL_ERROR', '取消收藏失败', true), 500);
  }
};
