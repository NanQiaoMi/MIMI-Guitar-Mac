import type { APIRoute } from 'astro';
import { db } from '../../lib/db';
import { json, readJson, currentUser } from '../../lib/api';

/** 发布文章（登录态）：title/category/content */
export const POST: APIRoute = async ({ request, cookies }) => {
  const user = await currentUser(cookies);
  if (!user) return json({ error: '请先登录' }, 401);
  const body = await readJson(request);
  const title = String(body.title ?? '').trim();
  const content = String(body.content ?? '').trim();
  const category = String(body.category ?? '').trim() || null;
  if (!title || title.length > 100) return json({ error: '标题不能为空且不超过 100 字' }, 400);
  if (!content || content.length < 10) return json({ error: '内容不能为空且不少于 10 字' }, 400);
  const article = await db.article.create({ data: { title, content, category } });
  return json({ ok: true, id: article.id });
};