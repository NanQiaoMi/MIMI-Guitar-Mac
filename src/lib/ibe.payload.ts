import { importer, model, Settings } from '@coderline/alphatab';
import { normalizeScoreJson } from './ibe.ts';

type JsonObject = Record<string, unknown>;

function isAlphaTabScore(value: JsonObject): boolean {
  const masterBars = value.masterbars;
  const tracks = value.tracks;
  if (!Array.isArray(masterBars) || masterBars.length === 0 || !Array.isArray(tracks) || tracks.length === 0) {
    return false;
  }

  return tracks.some((track) => {
    if (!track || typeof track !== 'object') return false;
    const staves = (track as JsonObject).staves;
    return Array.isArray(staves) && staves.some((staff) => {
      if (!staff || typeof staff !== 'object') return false;
      const bars = (staff as JsonObject).bars;
      return Array.isArray(bars) && bars.length > 0;
    });
  });
}

function assertAlphaTabScore(value: JsonObject, source: string): JsonObject {
  if (!isAlphaTabScore(value)) {
    throw new Error(`${source}缺少可读取的小节、音轨或谱表数据`);
  }
  return value;
}

function diagnosticLocation(diagnostic: any): string {
  const line = diagnostic?.start?.line;
  const column = diagnostic?.start?.column;
  return typeof line === 'number'
    ? `第 ${line} 行${typeof column === 'number' ? `第 ${column} 列` : ''}`
    : '位置未知';
}

function parseAlphaTex(text: string, settings = new Settings()): JsonObject {
  const parser = new importer.AlphaTexImporter();
  parser.logErrors = false;
  parser.initFromString(text, settings);

  let score;
  try {
    score = parser.readScore();
  } catch (error) {
    const diagnostics = [
      ...parser.lexerDiagnostics.errors,
      ...parser.parserDiagnostics.errors,
      ...parser.semanticDiagnostics.errors,
    ];
    const summary = diagnostics.slice(0, 4)
      .map((item) => `${item.code} ${diagnosticLocation(item)}：${item.message}`)
      .join('；');
    const more = diagnostics.length > 4 ? `；另有 ${diagnostics.length - 4} 项错误` : '';
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(diagnostics.length
      ? `AlphaTex 内容无效（${diagnostics.length} 项错误）：${summary}${more}`
      : `AlphaTex 解析失败：${message}`);
  }

  const errors = [
    ...parser.lexerDiagnostics.errors,
    ...parser.parserDiagnostics.errors,
    ...parser.semanticDiagnostics.errors,
  ];
  if (errors.length > 0) {
    const summary = errors.slice(0, 4)
      .map((item) => `${item.code} ${diagnosticLocation(item)}：${item.message}`)
      .join('；');
    const more = errors.length > 4 ? `；另有 ${errors.length - 4} 项错误` : '';
    throw new Error(`AlphaTex 内容无效（${errors.length} 项错误）：${summary}${more}`);
  }

  return normalizeScoreJson(JSON.parse(model.JsonConverter.scoreToJson(score)) as JsonObject);
}

/** Convert either a complete AlphaTab score or the legacy alphaTex-only MIMI wrapper. */
export function decodeMimiPayload(payload: JsonObject, settings = new Settings()): JsonObject {
  const normalized = normalizeScoreJson(payload);
  if (isAlphaTabScore(normalized)) return normalized;

  const alphaTex = normalized.alphatex;
  if (typeof alphaTex !== 'string' || alphaTex.trim().length === 0) {
    throw new Error('MIMI 乐谱容器缺少 AlphaTab 小节数据，也没有可转换的 AlphaTex 内容');
  }

  const score = assertAlphaTabScore(parseAlphaTex(alphaTex, settings), 'AlphaTex 转换结果');
  for (const key of ['title', 'artist', 'tempo', 'capo'] as const) {
    const value = normalized[key];
    if (value !== undefined && value !== null && value !== '') score[key] = value;
  }
  return score;
}

/** Fail before rendering/playback if a decoder returned a truncated AlphaTab JSON tree. */
export function validateDecodedScore(payload: JsonObject, source = '乐谱'): JsonObject {
  return assertAlphaTabScore(payload, source);
}
