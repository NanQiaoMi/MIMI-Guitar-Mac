#!/usr/bin/env node
/**
 * M7.4 风格回填：从原站风格列表页抓取曲谱 id，按 style 值写入本地 DB。
 * 用法：node tools/backfill-style.mjs [--pages 3] [--pace 700]
 * 说明：原站 sheetInfo 不含 style 字段，风格只能从 /tabs?style=N 列表页反推（热门子集内）。
 */
process.loadEnvFile?.('.env');
import { PrismaClient } from '@prisma/client';
import { setTimeout as sleep } from 'node:timers/promises';

const prisma = new PrismaClient();
const BASE = 'https://guistudy.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const raw = process.argv.slice(2);
const args = {};
for (let i = 0; i < raw.length; i++) { if (!raw[i].startsWith('--')) continue; const k = raw[i].slice(2); const v = raw[i + 1] && !raw[i + 1].startsWith('--') ? raw[i + 1] : true; args[k] = v; i += v === true ? 0 : 1; }
const PAGES = Number(args.pages ?? 3);
const PACE = Number(args.pace ?? 700);
const STYLES = [101, 102, 103, 105, 107, 109];

async function fetchIds(listPath, style, no) {
  const url = `${BASE}/${listPath}?difficulty=0&style=${style}&sheetForm=0&sort=1&keynotes=null&tuning=null&no=${no}`;
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' ' + url);
  const t = await res.text();
  const re = new RegExp('href="/' + listPath + '/([A-Za-z0-9]+)"', 'g');
  const ids = [...t.matchAll(re)].map((m) => m[1]);
  return [...new Set(ids)];
}

const total = { updated: 0, fetched: 0 };
for (const style of STYLES) {
  for (const cat of ['guitar', 'ukulele']) {
    const listPath = cat === 'ukulele' ? 'ukulele' : 'tabs';
    let pageOk = 0;
    for (let no = 1; no <= PAGES; no++) {
      try {
        const ids = await fetchIds(listPath, style, no);
        if (ids.length === 0) break;
        const r = await prisma.tab.updateMany({ where: { id: { in: ids } }, data: { style } });
        total.updated += r.count;
        total.fetched += ids.length;
        pageOk++;
        console.log('[style ' + style + ' ' + cat + '] no=' + no + ': 命中本地 ' + r.count + '/' + ids.length + '（累计 updated=' + total.updated + '）');
      } catch (e) {
        console.error('[style ' + style + ' ' + cat + '] no=' + no + ' 失败: ' + e.message);
        break;
      }
      await sleep(PACE);
    }
    if (pageOk === 0) console.log('[style ' + style + ' ' + cat + '] 无有效页');
  }
}
await prisma.$disconnect();
console.log('完成：共抓取 ' + total.fetched + ' 条，本地更新 ' + total.updated + ' 条');
