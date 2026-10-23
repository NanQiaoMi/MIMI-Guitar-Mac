import type { APIRoute } from 'astro';
import { db } from '../../../../lib/db';
import { currentUser } from '../../../../lib/api';
import { readFileSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { DEMO_TABS } from '../../../../lib/demoData';
import { installNodeAr } from '../../../../lib/ar.node';
import { decodeIbeToJsonNode } from '../../../../lib/ibe.node';

/** 登录后下载 .ibe 原谱 */
export const GET: APIRoute = async ({ params, cookies }) => {
  const id = params.id ?? '';
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(id)) return new Response('bad id', { status: 400 });
  const user = await currentUser(cookies);
  if (!user) return new Response(JSON.stringify({ error: '请先登录' }), { status: 401, headers: { 'content-type': 'application/json; charset=utf-8' } });

  let tab: any = null;
  let databaseUnavailable = false;
  try {
    tab = await db.tab.findUnique({ where: { id } });
  } catch {
    databaseUnavailable = true;
  }
  if (!tab) tab = DEMO_TABS.find((item) => item.id === id) ?? null;
  if (!tab) return new Response(databaseUnavailable ? 'score database unavailable' : 'not found', { status: databaseUnavailable ? 503 : 404 });

  // XHE 文本谱没有 .ibe 文件，不支持下载
  if (!tab.scoreUrl) return new Response(JSON.stringify({ error: '文本谱（XHE）不支持下载' }), { status: 400, headers: { 'content-type': 'application/json; charset=utf-8' } });

  const rel = String(tab.scoreUrl).replace(/^\/+/, '').replace(/\\/g, '/');
  if (!rel.startsWith('storage/scores/') || rel.includes('..') || !rel.toLowerCase().endsWith('.ibe')) {
    return new Response('score path is not a supported IBE file', { status: 422 });
  }

  const publicRoot = path.resolve(process.cwd(), 'public');
  const file = path.resolve(publicRoot, ...rel.split('/'));
  const relative = path.relative(publicRoot, file);
  if (relative.startsWith('..') || path.isAbsolute(relative) || !existsSync(file)) return new Response('file missing', { status: 404 });
  if (!statSync(file).isFile()) return new Response('score file is not a regular file', { status: 422 });

  const buf = new Uint8Array(readFileSync(file));
  if (buf.length === 0) return new Response('score file is empty', { status: 422 });
  try {
    installNodeAr();
    decodeIbeToJsonNode(buf);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    return new Response(`score file is not readable: ${reason}`, { status: 422 });
  }

  const scoreName = String(tab.title || id).replace(/[\r\n"\\/]/g, '_');
  return new Response(buf, {
    status: 200,
    headers: {
      'content-type': 'application/octet-stream',
      'content-disposition': `attachment; filename="${encodeURIComponent(scoreName)}.ibe"; filename*=UTF-8''${encodeURIComponent(scoreName)}.ibe`,
      'content-length': String(buf.length),
      'cache-control': 'no-store',
    },
  });
};
