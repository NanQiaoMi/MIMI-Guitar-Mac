#!/usr/bin/env node
/**
 * 候选清单枚举（M7.1）：遍历 /tabs 与 /ukulele 的多个列表视图，提取主列表曲谱 ID。
 * 用法：node tools/enum-candidates.mjs [--out tools/migrate-candidates.json] [--pace 350]
 * 视图：sort=0(最新)/sort=1(最热) + 难度 1-5 最热；吉他+尤克里里。
 * 输出：[{id, hint}]，hint: guitar|ukulele|unknown（两列表都出现）。
 */
process.loadEnvFile?.('.env');
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const outFile = process.argv[process.argv.indexOf('--out') + 1] ?? 'tools/migrate-candidates.json';
const pace = Number(process.argv[process.argv.indexOf('--pace') + 1] ?? 350);
const BASE = 'https://guistudy.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 视图清单：{ kind: 'tabs'|'ukulele', url }
const views = [];
for (const kind of ['tabs', 'ukulele']) {
  for (const sort of [0, 1]) {
    views.push({ kind, url: `${BASE}/${kind}?sort=${sort}` });
  }
}
for (const d of [1, 2, 3, 4, 5]) {
  views.push({ kind: 'tabs', url: `${BASE}/tabs?difficulty=${d}&sort=1` });
}

async function fetchWithRetry(url, attempts = 4) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 45000);
    try {
      const res = await fetch(url, { signal: ctrl.signal, headers: { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9' } });
      if (res.status === 567 || res.status === 429 || res.status === 503) {
        const wait = 4000 * (2 ** i);
        console.error(`限流 ${res.status}，等待 ${wait / 1000}s`);
        clearTimeout(t); await sleep(wait); continue;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.text();
    } catch (e) {
      lastErr = e; clearTimeout(t);
      if (i < attempts - 1) await sleep(1500 * (i + 1));
    }
  }
  throw lastErr;
}

async function collectView(view) {
  const map = new Map(); // id -> hint
  let no = 1;
  const pathPrefix = view.kind === 'ukulele' ? 'ukulele' : 'tabs';
  for (; no <= 1000; no++) {
    const html = await fetchWithRetry(`${view.url}&no=${no}`);
    const re = new RegExp(`<li><a href="/${pathPrefix}/([A-Za-z0-9]+)"`, 'g');
    const ids = [...html.matchAll(re)].map((m) => m[1]);
    if (ids.length === 0) break;
    for (const id of ids) map.set(id, view.kind);
    console.log(`  ${view.url} no=${no} +=${ids.length} (累计 ${map.size})`);
    await sleep(pace + Math.random() * 200);
  }
  return map;
}

// 合并（保留已有文件中的 hint 作为后备）
const merged = new Map();
if (existsSync(outFile)) {
  const raw = JSON.parse(readFileSync(outFile, 'utf8'));
  for (const item of raw) {
    const id = typeof item === 'string' ? item : item.id;
    merged.set(id, typeof item === 'string' ? 'guitar' : (item.hint ?? 'guitar'));
  }
  console.log('已有候选', merged.size);
}

for (const view of views) {
  console.log('枚举', view.url);
  const m = await collectView(view);
  for (const [id, kind] of m) {
    if (!merged.has(id)) merged.set(id, kind);
    else if (merged.get(id) !== kind) merged.set(id, 'unknown'); // 两处出现 → 未知，尝试两个路径
  }
}

const out = [...merged.entries()].map(([id, hint]) => ({ id, hint }));
writeFileSync(outFile, JSON.stringify(out, null, 0));
console.log(`完成：候选 ${out.length}（guitar=${out.filter((x) => x.hint === 'guitar').length} ukulele=${out.filter((x) => x.hint === 'ukulele').length} unknown=${out.filter((x) => x.hint === 'unknown').length}） -> ${outFile}`);
