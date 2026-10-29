import type { APIRoute } from 'astro';
import { db } from '../../../lib/db';
import { signToken, verifyPassword } from '../../../lib/auth';
import { json, readJson, setSessionCookie } from '../../../lib/api';
import { rateLimit, ipKey } from '../../../lib/rateLimit';

export const POST: APIRoute = async ({ request, cookies }) => {
  if (!rateLimit(ipKey(request, 'login'), 10, 60_000)) return json({ error: '尝试过于频繁，请稍后再试' }, 429);
  const body = await readJson(request);
  const account = String(body.account ?? '').trim();
  const password = String(body.password ?? '');
  if (!account || !password) return json({ error: '账号与密码不能为空' }, 400);
  const isEmail = account.includes('@');
  const user = isEmail
    ? await db.user.findUnique({ where: { email: account } })
    : await db.user.findUnique({ where: { phone: account } });
  if (!user || !verifyPassword(password, user.passwordHash)) {
    return json({ error: '账号或密码错误' }, 401);
  }
  setSessionCookie(cookies, signToken({ sub: user.id }));
  return json({
    ok: true,
    user: { id: user.id, email: user.email, phone: user.phone, nickname: user.nickname, avatarUrl: user.avatarUrl, createdAt: user.createdAt },
  });
};