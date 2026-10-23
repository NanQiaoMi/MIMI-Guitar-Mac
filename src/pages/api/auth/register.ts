import type { APIRoute } from 'astro';
import { db } from '../../../lib/db';
import { hashPassword, signToken } from '../../../lib/auth';
import { json, readJson, setSessionCookie } from '../../../lib/api';
import { rateLimit, ipKey } from '../../../lib/rateLimit';

export const POST: APIRoute = async ({ request, cookies }) => {
  if (!rateLimit(ipKey(request, 'register'), 10, 60_000)) return json({ error: '尝试过于频繁，请稍后再试' }, 429);
  const body = await readJson(request);
  const account = String(body.account ?? '').trim();
  const password = String(body.password ?? '');
  const nickname = String(body.nickname ?? '').trim();
  if (!account || !password) return json({ error: '账号与密码不能为空' }, 400);
  if (password.length < 6) return json({ error: '密码至少 6 位' }, 400);
  const isEmail = account.includes('@');
  const existing = isEmail
    ? await db.user.findUnique({ where: { email: account } })
    : await db.user.findUnique({ where: { phone: account } });
  if (existing) return json({ error: '该账号已注册' }, 409);
  const user = await db.user.create({
    data: isEmail
      ? { email: account, passwordHash: hashPassword(password), nickname: nickname || null }
      : { phone: account, passwordHash: hashPassword(password), nickname: nickname || null },
    select: { id: true, email: true, phone: true, nickname: true, avatarUrl: true, createdAt: true },
  });
  setSessionCookie(cookies, signToken({ sub: user.id }));
  return json({ ok: true, user });
};