#!/usr/bin/env node
/**
 * 迁移爬虫（M7.1）：基于预枚举候选清单扩充曲谱入库。
 * 用法：
 *   node tools/migrate.mjs --ids tools/migrate-candidates.json [--pace 800] [--state tools/migrate-state-m7.json]
 *   --ids   候选清单 [{id,hint}]（hint: guitar|ukulele，来自列表/搜索枚举）
 *   --pace  每次详情请求间隔 ms（含抖动）
 *   --state checkpoint 文件（断点续爬：done/failed 集合，重跑自动跳过）
 * 流程：详情页 -> sheetInfo -> 下载 .ibe/截图 -> 解码校验 -> PostgreSQL upsert。
 * 注意：目标站限流（HTTP 567/429/连接超时），已做指数退避；请保持低速运行。
 */
process.loadEnvFile?.('.env');
import { PrismaClient } from '@prisma/client';
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeIbeToJsonNode } from '../src/lib/ibe.node.ts';

installNodeAr();
const prisma = new PrismaClient();
const BASE = 'https://guistudy.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const STORAGE = process.env.SCORE_STORAGE_DIR || 'public/storage/scores';
const SHOT_DIR = 'public/storage/screenshots';

const rawArgs = process.argv.slice(2);
const args = {};
for (let i = 0; i < rawArgs.length; i++) {
  const a = rawArgs[i];
  if (!a.startsWith('--')) continue;
  const k = a.slice(2);
  const eq = k.indexOf('=');
  if (eq >= 0) args[k.slice(0, eq)] = k.slice(eq + 1);
  else if (i + 1 < rawArgs.length && !rawArgs[i + 1].startsWith('--')) { args[k] = rawArgs[i + 1]; i++; }
  else args[k] = true;
}
const IDS_FILE = args.ids;
const PACE = Number(args.pace ?? 800);
const STATE_FILE = args.state ?? 'tools/migrate-state-m7.json';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchWithRetry(url, opts, attempts = 5) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), opts.timeoutMs || 45000);
    try {
      const res = await fetch(url, { signal: ctrl.signal, headers: opts.headers ?? { 'User-Agent': UA } });
      if (res.status === 567 || res.status === 429 || res.status === 503) {
        const wait = 4000 * (2 ** i);
        console.error(`限流 HTTP ${res.status}，等待 ${wait / 1000}s 后重试（${i + 1}/${attempts}）`);
        clearTimeout(t); await sleep(wait); continue;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
      return res;
    } catch (e) {
      lastErr = e; clearTimeout(t);
      if (i < attempts - 1) await sleep(2000 * (i + 1));
    }
  }
  throw lastErr ?? new Error('fetch 重试耗尽');
}
async function fetchText(url) { const res = await fetchWithRetry(url, { headers: { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9' } }); return await res.text(); }
async function fetchBuffer(url) { const res = await fetchWithRetry(url, { timeoutMs: 180000 }); return Buffer.from(await res.arrayBuffer()); }

function extractSheetInfoRaw(html) {
  const marker = '&quot;sheetInfo&quot;:';
  const i = html.indexOf(marker);
  if (i < 0) return null;
  let j = i + marker.length;
  while (j < html.length && html[j] !== '[') j++;
  if (j >= html.length) return null;
  let depth = 0;
  for (; j < html.length; j++) {
    const c = html[j];
    if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') { depth--; if (depth === 0) break; }
  }
  return html.slice(i, j + 1);
}
function unescapeHtml(s) { return s.replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#x27;/g, "'"); }
function decodeIns(v) {
  if (Array.isArray(v)) {
    if (v.length === 2 && typeof v[0] === 'number') {
      const [tag, val] = v;
      return decodeIns(val);
    }
    return v.map(decodeIns);
  }
  if (v && typeof v === 'object') { const out = {}; for (const k of Object.keys(v)) out[k] = decodeIns(v[k]); return out; }
  return v;
}
function extractSheetInfo(html) {
  const raw = extractSheetInfoRaw(html);
  if (!raw) return null;
  try { const obj = JSON.parse('{' + unescapeHtml(raw) + '}'); const si = obj.sheetInfo; return si && Array.isArray(si) ? decodeIns(si) : si ?? null; }
  catch (e) { console.error('sheetInfo 解析失败:', e.message); return null; }
}
function tuningLabel(tunings) {
  if (!tunings || tunings.length !== 6) return null;
  const std = [64, 59, 55, 50, 45, 40]; const half = [63, 58, 54, 49, 44, 39];
  if (std.every((v, i) => v === tunings[i])) return 'Standard';
  if (half.every((v, i) => v === tunings[i])) return 'Half-Step Down';
  return null;
}
async function loadExistingIds() {
  const rows = await prisma.tab.findMany({ select: { id: true } });
  return new Set(rows.map((r) => r.id));
}
function loadCandidates() {
  const raw = JSON.parse(readFileSync(IDS_FILE, 'utf8'));
  const map = new Map();
  for (const item of raw) {
    const id = typeof item === 'string' ? item : item.id;
    const hint = typeof item === 'string' ? 'guitar' : (item.hint ?? 'guitar');
    if (id && !map.has(id)) map.set(id, hint === 'ukulele' || hint === 'unknown' ? hint : 'guitar');
  }
  return [...map.entries()].map(([id, hint]) => ({ id, hint }));
}
function loadState() {
  if (!existsSync(STATE_FILE)) return { done: new Set(), failed: new Set(), counts: { ok: 0, fail: 0, skip: 0 } };
  try {
    const s = JSON.parse(readFileSync(STATE_FILE, 'utf8'));
    return {
      done: new Set(s.done ?? []),
      failed: new Set(s.failed ?? []),
      counts: s.counts ?? { ok: 0, fail: 0, skip: 0 },
    };
  } catch (e) { console.error('state 读取失败，重置:', e.message); return { done: new Set(), failed: new Set(), counts: { ok: 0, fail: 0, skip: 0 } }; }
}
function saveState(state) {
  writeFileSync(STATE_FILE, JSON.stringify({
    startedAt: state.startedAt,
    updatedAt: new Date().toISOString(),
    done: [...state.done],
    failed: [...state.failed],
    counts: state.counts,
  }, null, 2));
}

async function processSheet(sheetInfo, hint) {
  const id = sheetInfo.sheetCode;
  if (!id) return null;
  const localShot = path.join(SHOT_DIR, `${id}.jpg`);
  if (sheetInfo.screenshotUrl && !existsSync(localShot)) {
    try { const shot = await fetchBuffer(String(sheetInfo.screenshotUrl).split('?')[0]); writeFileSync(localShot, shot); } catch { /* 截图失败不阻塞 */ }
  }
  const categoryLabel = sheetInfo.type === 'ukulele' || hint === 'ukulele' ? 'ukulele' : 'guitar';
  const bpm = Number(sheetInfo.bpm ?? 0) || null;
  const common = {
    id,
    title: String(sheetInfo.title ?? ''),
    artist: String(sheetInfo.artist ?? '') || null,
    category: categoryLabel,
    difficulty: Number(sheetInfo.difficulty ?? 0),
    style: null,
    key: String(sheetInfo.keynote ?? '') || null,
    sheetForm: Number(sheetInfo.sheetForm ?? 0),
    bpm,
    timeSig: String(sheetInfo.timeSignature ?? '') || null,
    capo: Number(sheetInfo.capo ?? 0),
    heat: Number(sheetInfo.totalViews ?? 0),
    uploader: String(sheetInfo.author ?? '') || null,
    publishDate: sheetInfo.sheetCreationTime ? new Date(Number(sheetInfo.sheetCreationTime)) : null,
    screenshotUrl: existsSync(localShot) ? '/storage/screenshots/' + id + '.jpg' : null,
    description: null,
    tags: JSON.stringify(Array.isArray(sheetInfo.chords) ? sheetInfo.chords : []),
  };
  // XHE 网页编辑器格式：无 scoreUrl，保存 xheContent JSON（文本谱，无音频）
  if (String(sheetInfo.format ?? '').toLowerCase() === 'xhe' || sheetInfo.xheContent) {
    const xhePath = path.join('public/storage/xhe', `${id}.json`);
    mkdirSync(path.dirname(xhePath), { recursive: true });
    try { writeFileSync(xhePath, typeof sheetInfo.xheContent === 'string' ? sheetInfo.xheContent : JSON.stringify(sheetInfo.xheContent)); }
    catch (e) { console.error(`[${id}] xhe 保存失败:`, e.message); return null; }
    return { ...common, format: 'xhe', scoreUrl: null, xheUrl: '/storage/xhe/' + id + '.json', tuning: null, tuningText: null };
  }
  if (!sheetInfo.scoreUrl) return null;
  // GP 格式：下载 .ibe 并解码校验
  const localIbe = path.join(STORAGE, `${id}.ibe`);
  let ibe;
  try {
    if (existsSync(localIbe)) ibe = new Uint8Array(readFileSync(localIbe));
    else { ibe = new Uint8Array(await fetchBuffer(sheetInfo.scoreUrl)); writeFileSync(localIbe, ibe); }
  } catch (e) { console.error(`[${id}] .ibe 下载失败:`, e.message); return null; }
  let scoreJson;
  try { scoreJson = decodeIbeToJsonNode(ibe); } catch (e) { console.error(`[${id}] .ibe 解码失败，跳过:`, e.message); return null; }
  const track0 = scoreJson.tracks?.[0];
  const stave0 = track0?.staves?.[0];
  const tunings = stave0?.stringtuning?.tunings ?? null;
  return {
    ...common,
    format: 'gp',
    scoreUrl: '/storage/scores/' + id + '.ibe',
    xheUrl: null,
    tuning: tuningLabel(tunings),
    tuningText: tunings ? tunings.join(',') : null,
  };
}

async function fetchSheetAt(id, hint) {
  const pathA = hint === 'ukulele' ? 'ukulele' : 'tabs';
  try {
    const html = await fetchText(`${BASE}/${pathA}/${id}`);
    const sheet = extractSheetInfo(html);
    if (sheet && sheet.sheetCode) return sheet;
    if (hint === 'unknown') {
      const pathB = pathA === 'tabs' ? 'ukulele' : 'tabs';
      const html2 = await fetchText(`${BASE}/${pathB}/${id}`);
      const sheet2 = extractSheetInfo(html2);
      if (sheet2 && sheet2.sheetCode) return sheet2;
    }
    return null;
  } catch (e) { console.error(`[${id}] 详情抓取失败:`, e.message); return null; }
}

async function main() {
  mkdirSync(STORAGE, { recursive: true });
  mkdirSync(SHOT_DIR, { recursive: true });
  const candidates = loadCandidates();
  const existing = await loadExistingIds();
  const state = await loadState();
  state.startedAt = state.startedAt ?? new Date().toISOString();
  console.log(`候选 ${candidates.length}，已在库 ${existing.size}，已完成 ${state.done.size}，失败 ${state.failed.size}，目标新增 ${candidates.length - existing.size - state.done.size}`);
  let { ok, fail, skip } = state.counts;
  let idx = 0;
  for (const { id, hint } of candidates) {
    idx++;
    if (existing.has(id)) { skip++; continue; }
    if (state.done.has(id)) continue;
    if (state.failed.has(id)) continue;
    const sheet = await fetchSheetAt(id, hint);
    if (!sheet) {
      state.failed.add(id); fail++;
      console.log(`[fail][${idx}/${candidates.length}] ${id} 无 sheetInfo`);
    } else {
      const record = await processSheet(sheet, hint);
      if (!record) {
        state.failed.add(id); fail++;
        console.log(`[fail][${idx}/${candidates.length}] ${id} 处理失败（解码/下载）`);
      } else {
        await prisma.tab.upsert({ where: { id: record.id }, update: record, create: record });
        state.done.add(id); ok++;
        console.log(`[ok][${idx}/${candidates.length}] ${record.title} - ${record.artist}（${record.category}，热度 ${record.heat}，ok=${ok} fail=${fail}）`);
      }
    }
    if (idx % 25 === 0) {
      state.counts = { ok, fail, skip };
      saveState(state);
      console.log(`-- checkpoint ${idx}/${candidates.length}（ok=${ok} fail=${fail} skip=${skip}）`);
    }
    await sleep(Number(PACE) + Math.random() * 250);
  }
  state.counts = { ok, fail, skip };
  saveState(state);
  await prisma.$disconnect();
  console.log(`\n完成。成功 ${ok}，失败 ${fail}，跳过 ${skip}。state -> ${STATE_FILE}`);
}
if (!IDS_FILE) { console.error('缺少 --ids 参数'); process.exit(1); }
main().catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
