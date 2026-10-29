import type { APIRoute } from 'astro';
import { currentUser } from '../../lib/api';
import { ScoreSourceError, searchSongsterr, ingestSongFromSongsterr } from '../../lib/musicResourceCollector.ts';

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};

function errorResponse(error: unknown, fallback: string) {
  const status = error instanceof ScoreSourceError ? error.status : 502;
  const message = error instanceof Error ? error.message : fallback;
  return new Response(JSON.stringify({ success: false, message }), { status, headers: JSON_HEADERS });
}

export const GET: APIRoute = async ({ url }) => {
  const query = (url.searchParams.get('q') ?? '').trim();
  if (!query) {
    return new Response(JSON.stringify({ success: false, message: 'Query parameter q is required' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  try {
    const results = await searchSongsterr(query);
    return new Response(JSON.stringify({ success: true, count: results.length, results }), {
      status: 200,
      headers: JSON_HEADERS,
    });
  } catch (error) {
    return errorResponse(error, 'Songsterr search failed');
  }
};

export const POST: APIRoute = async ({ request, cookies }) => {
  if (!await currentUser(cookies)) {
    return new Response(JSON.stringify({ success: false, message: '请先登录后再导入来源曲谱' }), {
      status: 401,
      headers: JSON_HEADERS,
    });
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ success: false, message: '请求体必须是有效 JSON' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  const songId = typeof body?.songId === 'number' || typeof body?.songId === 'string'
    ? String(body.songId).trim()
    : '';
  if (!/^\d{1,12}$/.test(songId) || Number(songId) <= 0) {
    return new Response(JSON.stringify({ success: false, message: 'songId 必须是有效的正整数' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  const customId = body?.customId == null || body.customId === '' ? null : String(body.customId);
  if (customId !== null && !/^[A-Za-z0-9_-]{1,80}$/.test(customId)) {
    return new Response(JSON.stringify({ success: false, message: 'customId 只能使用 1–80 位英文字母、数字、下划线或短横线' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  try {
    const tab = await ingestSongFromSongsterr(Number(songId), customId);
    return new Response(JSON.stringify({ success: true, tab }), {
      status: 200,
      headers: JSON_HEADERS,
    });
  } catch (error) {
    return errorResponse(error, 'Songsterr ingestion failed');
  }
};
