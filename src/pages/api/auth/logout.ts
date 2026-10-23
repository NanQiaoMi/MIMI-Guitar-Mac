import type { APIRoute } from 'astro';
import { json, clearSessionCookie } from '../../../lib/api';

export const POST: APIRoute = async ({ cookies }) => {
  clearSessionCookie(cookies);
  return json({ ok: true });
};