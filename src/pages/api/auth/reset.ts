import type { APIRoute } from 'astro';
import { db } from '../../../lib/db';
import { hashPassword } from '../../../lib/auth';
import { json, readJson } from '../../../lib/api';
import { consumeCode } from '../../../lib/sms';

export const POST: APIRoute = async ({ request }) => {
  const mockSmsEnabled = import.meta.env.DEV && process.env.MIMI_ENABLE_MOCK_SMS === 'true';
  if (!mockSmsEnabled) return json({ error: '当前环境未配置真实短信服务，密码重置不可用' }, 503);
  const body = await readJson(request);
  const phone = String(body.phone ?? '').trim();
  const code = String(body.code ?? '').trim();
  const password = String(body.password ?? '');
  if (password.length < 6) return json({ error: '密码至少 6 位' }, 400);
  if (!consumeCode(phone, code)) return json({ error: '验证码错误或已过期' }, 400);
  const user = await db.user.findUnique({ where: { phone } });
  if (!user) return json({ error: '该手机号未注册' }, 404);
  await db.user.update({ where: { id: user.id }, data: { passwordHash: hashPassword(password) } });
  return json({ ok: true, message: '密码已重置' });
};
