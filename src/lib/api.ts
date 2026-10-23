import { db } from './db';
import { verifyToken, COOKIE_NAME } from './auth';
import type { AstroCookies } from 'astro';

/** API 通用工具：JSON 响应、请求体解析、cookie 会话解析 */

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    return (await req.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export function setSessionCookie(cookies: AstroCookies, token: string): void {
  cookies.set(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: 'lax',
    path: '/',
    maxAge: 7 * 24 * 3600,
    secure: false, // 本地开发 http
  });
}

export function clearSessionCookie(cookies: AstroCookies): void {
  cookies.set(COOKIE_NAME, '', { httpOnly: true, sameSite: 'lax', path: '/', maxAge: 0 });
}

export async function currentUser(cookies: AstroCookies) {
  const token = cookies.get(COOKIE_NAME)?.value;
  if (!token) return null;
  const payload = verifyToken(token);
  if (!payload || typeof payload.sub !== 'string') return null;
  try {
    const user = await db.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, email: true, phone: true, nickname: true, avatarUrl: true, createdAt: true },
    });
    return user;
  } catch {
    return null;
  }
}