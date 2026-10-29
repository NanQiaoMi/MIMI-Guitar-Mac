/**
 * `.ibe` 谱面解码核心（浏览器 + Node 双端可用，平台无关）
 *
 * 原站格式：XOR 加密（密钥 "guitartabspro"，自 len%10 偏移循环）→ AR 解压 → alphaTab JSON 谱面。
 * 自有格式：MIMI 魔数 + deflate 压缩 + XOR（自有密钥）→ alphaTab JSON 谱面。
 * JSON 键名需从原站驼峰 schema 归一化为官方 alphaTab 全小写 schema。
 *
 * AR 解压库通过 registerArLoader 注入（浏览器用 ?raw eval，Node 用 fs+vm）。
 */

export type ArFn = (data: Int8Array) => Int8Array;

export const ORIGINAL_KEY = 'guitartabspro';
export const OUR_KEY = 'mimi-guitar-2026';
export const OUR_MAGIC = 'MIMI';

let _ar: ArFn | null = null;
let _arLoader: (() => ArFn) | null = null;

export function registerArLoader(loader: () => ArFn): void {
  _arLoader = loader;
  _ar = null;
}

export function getAr(): ArFn {
  if (!_ar) {
    if (!_arLoader) throw new Error('AR 解压库未注册，请先调用 registerArLoader');
    _ar = _arLoader();
  }
  return _ar;
}

/** 原站 XOR 算法：以 data.length % 10 为起始偏移，循环异或 key 字节 */
export function xorBytes(data: Uint8Array, key: string): Int8Array {
  const kb = new TextEncoder().encode(key);
  const out = new Int8Array(data.length);
  let a = data.length % 10;
  for (let i = 0; i < data.length; i++) {
    if (a >= kb.length) a = 0;
    out[i] = data[i] ^ kb[a];
    a++;
  }
  return out;
}

function lowerKey(k: string): string {
  if (k === 'showNumberedNotation') return 'shownumbered';
  return k.toLowerCase();
}

/** 递归归一化：驼峰键 → 全小写；chords 映射的键（和弦名）保留原样 */
export function normalizeValue(v: unknown, parentKey = ''): unknown {
  if (Array.isArray(v)) return v.map((x) => normalizeValue(x, ''));
  if (v && typeof v === 'object') {
    const rec = v as Record<string, unknown>;
    if (parentKey === 'chords') {
      const out: Record<string, unknown> = {};
      for (const [k, val] of Object.entries(rec)) out[k] = normalizeValue(val, '');
      return out;
    }
    const out: Record<string, unknown> = {};
    for (const [k, val] of Object.entries(rec)) {
      if (k === 'tempoAutomation') {
        out['tempoautomations'] = val == null ? [] : [normalizeValue(val, '')];
      } else if (k === 'tempoLabel') {
        continue;
      } else {
        out[lowerKey(k)] = normalizeValue(val, k);
      }
    }
    return out;
  }
  return v;
}

/** 归一化整份谱面 JSON 并把顶层 tempo 注入 masterBars[0] */
export function normalizeScoreJson(obj: Record<string, unknown>): Record<string, unknown> {
  const out = normalizeValue(obj, '') as Record<string, unknown>;
  fixScoreContent(out);
  const tempo = obj.tempo as number | undefined;
  const tempoLabel = (obj.tempoLabel as string | undefined) ?? '';
  if (tempo != null) {
    const masterBars = (out.masterbars as Record<string, unknown>[] | undefined) ?? [];
    if (masterBars.length > 0) {
      const mb0 = (masterBars[0] ??= {}) as Record<string, unknown>;
      const tas = (mb0.tempoautomations as unknown[] | undefined) ?? [];
      if (tas.length === 0) {
        (mb0.tempoautomations as unknown[]) = [
          { type: 'Tempo', value: tempo, text: tempoLabel, isvisible: false, ratioposition: 0 },
        ];
      }
    }
  }
  return out;
}

/**
 * 归一化 beat.lyrics 为字符串数组（AlphaTab 1.8.4 的 LyricsGlyph 按字符串数组渲染；
 * 若传 { text, beats } 对象，fillText 收到对象会渲染失败）。
 * 原站 .ibe 中歌词是字符串数组（如 ["故"]），直接保留；对象数组则抽取 text 字段。
 */
export function normalizeLyrics(lyrics: unknown): unknown {
  if (!Array.isArray(lyrics) || lyrics.length === 0) return lyrics;
  const out: unknown[] = [];
  for (const item of lyrics) {
    if (typeof item === 'string') {
      out.push(item);
    } else if (item && typeof item === 'object' && 'text' in (item as Record<string, unknown>)) {
      out.push((item as Record<string, unknown>).text ?? '');
    }
    // 其他类型（数字/布尔/null）忽略，避免脏数据
  }
  return out;
}

/**
 * 清洗畸形和弦：firstfret 非正整数或 strings 非有效数组的和弦丢弃，
 * 并清空指向已删除和弦的 beat.chordid（避免 Chord.uniqueId 在渲染时崩溃）。
 * 有效和弦（晴天类：name/firstfret/strings 齐全）原样保留。
 */
export function sanitizeChords(score: Record<string, unknown>): void {
  const tracks = (score.tracks as Record<string, unknown>[] | undefined) ?? [];
  for (const track of tracks) {
    const staves = (track.staves as Record<string, unknown>[] | undefined) ?? [];
    for (const stave of staves) {
      const chords = stave.chords as Record<string, unknown> | null | undefined;
      if (!chords || typeof chords !== 'object') {
        stave.chords = {};
        continue;
      }
      const validKeys = new Set<string>();
      for (const [k, ch] of Object.entries(chords)) {
        const rec = (ch ?? {}) as Record<string, unknown>;
        const firstfret = rec.firstfret;
        const strings = rec.strings;
        const ok =
          typeof firstfret === 'number' &&
          Number.isInteger(firstfret) &&
          firstfret >= 1 &&
          Array.isArray(strings) &&
          strings.length > 0;
        if (ok) validKeys.add(k);
        else delete chords[k];
      }
      for (const bar of (stave.bars as Record<string, unknown>[] | undefined) ?? []) {
        for (const v of (bar.voices as Record<string, unknown>[] | undefined) ?? []) {
          for (const b of (v.beats as Record<string, unknown>[] | undefined) ?? []) {
            const cid = b.chordid;
            if (cid != null && !validKeys.has(String(cid))) delete b.chordid;
          }
        }
      }
    }
  }
}

/** 歌词映射 + 和弦清洗（在 normalizeValue 之后统一执行） */
function fixScoreContent(score: Record<string, unknown>): void {
  const tracks = (score.tracks as Record<string, unknown>[] | undefined) ?? [];
  for (const track of tracks) {
    for (const stave of (track.staves as Record<string, unknown>[] | undefined) ?? []) {
      for (const bar of (stave.bars as Record<string, unknown>[] | undefined) ?? []) {
        for (const v of (bar.voices as Record<string, unknown>[] | undefined) ?? []) {
          for (const b of (v.beats as Record<string, unknown>[] | undefined) ?? []) {
            if (b.lyrics != null) b.lyrics = normalizeLyrics(b.lyrics);
          }
        }
      }
    }
  }
  sanitizeChords(score);
}

/** 判断是否为自有 MIMI 格式 */
export function isOurFormat(ibe: Uint8Array): boolean {
  if (ibe.length < 8) return false;
  const m = new TextEncoder().encode(OUR_MAGIC);
  return ibe[0] === m[0] && ibe[1] === m[1] && ibe[2] === m[2] && ibe[3] === m[3];
}

/** 解析原站 AR 格式 .ibe → 归一化 JSON 对象（同步） */
export function decodeOriginalIbeToJson(ibe: Uint8Array): Record<string, unknown> {
  const xored = xorBytes(ibe, ORIGINAL_KEY);
  const arr = getAr()(xored);
  const json = new TextDecoder().decode(new Uint8Array(arr.buffer, arr.byteOffset, arr.length));
  return normalizeScoreJson(JSON.parse(json) as Record<string, unknown>);
}

/**
 * 从归一化后的谱�?JSON 提取初�调性（keySignature/keySignatureType）与拍号�? * 注意：Model.JsonConverter 会将 masterbars[0].keysignature 失为 0，故需在数据层直接读取�? */
export function extractScoreMeta(json: Record<string, unknown>): { keySignature: number | null; keySignatureType: number; timeSigNum: number; timeSigDen: number } {
  const mb0 = (json.masterbars as Record<string, unknown>[] | undefined)?.[0] ?? {};
  const num = mb0.timesignaturenumerator;
  const den = mb0.timesignaturedenominator;
  return {
    keySignature: typeof mb0.keysignature === 'number' ? mb0.keysignature : null,
    keySignatureType: mb0.keysignaturetype === 1 ? 1 : 0,
    timeSigNum: typeof num === 'number' && num > 0 ? num : 4,
    timeSigDen: typeof den === 'number' && den > 0 ? den : 4,
  };
}
