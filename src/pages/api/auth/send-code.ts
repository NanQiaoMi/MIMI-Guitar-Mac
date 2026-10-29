import type { APIRoute } from 'astro';
import { json, readJson } from '../../../lib/api';
import { rateLimit, ipKey } from '../../../lib/rateLimit';
import { issueCode } from '../../../lib/sms';

export const POST: APIRoute = async ({ request }) => {
  const mockSmsEnabled = import.meta.env.DEV && process.env.MIMI_ENABLE_MOCK_SMS === 'true';
  if (!mockSmsEnabled) return json({ error: '当前环境未配置真实短信服务，验证码功能不可用' }, 503);
  if (!rateLimit(ipKey(request, 'send-code'), 10, 60_000)) return json({ error: '尝试过于频繁，请稍后再试' }, 429);
  const body = await readJson(request);
  const phone = String(body.phone ?? '').trim();
  if (!/^1\d{10}$/.test(phone)) return json({ error: '手机号格式不正确' }, 400);
  const code = issueCode(phone);
  return json({ ok: true, code, message: '开发环境验证码（本地 mock）' });
};
