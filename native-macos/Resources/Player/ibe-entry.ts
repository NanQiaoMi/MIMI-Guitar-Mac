import { decodeIbeToJsonBrowser } from '../../../src/lib/ibe.browser.ts';
import { registerArLoader } from '../../../src/lib/ibe.ts';
import { buildBlocks, parseXhe } from '../../../src/lib/xhe.ts';
import { chordSvg, lookupChord, normalizeChord } from '../../../src/lib/chords.ts';
import { renderScorePdfPageImages, renderScorePngData } from '../../../src/lib/printScore.ts';

type PlayerDecoder = {
  decodeIbe: (bytes: Uint8Array) => Promise<Record<string, unknown>>;
  parseXhe: (raw: string) => ReturnType<typeof parseXhe>;
  buildXheBlocks: typeof buildBlocks;
  chordSvg: typeof chordSvg;
  lookupChord: typeof lookupChord;
  normalizeChord: typeof normalizeChord;
  renderPdfPageImages: (score: any, author: string, trackIndexes?: number[]) => Promise<{ widthPoints: number; heightPoints: number; pages: string[] }>;
  renderPngData: (sourceApi: any) => Promise<string>;
};

const scope = globalThis as typeof globalThis & {
  ar?: (data: Int8Array) => Int8Array;
  MimiIbe?: PlayerDecoder;
};

registerArLoader(() => {
  if (typeof scope.ar !== 'function') {
    throw new Error('本地 IBE 解码器未加载。');
  }
  return scope.ar;
});

scope.MimiIbe = {
  decodeIbe: async (bytes) => decodeIbeToJsonBrowser(bytes),
  parseXhe,
  buildXheBlocks: buildBlocks,
  chordSvg,
  lookupChord,
  normalizeChord,
  renderPdfPageImages: renderScorePdfPageImages,
  renderPngData: renderScorePngData,
};
