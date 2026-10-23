import type { APIRoute } from 'astro';
import { json, currentUser } from '../../../lib/api';

export const GET: APIRoute = async ({ cookies }) => {
  const user = await currentUser(cookies);
  if (!user) return json({ error: '未登录' }, 401);
  return json({ ok: true, user });
};