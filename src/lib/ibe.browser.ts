import { decodeOriginalIbeToJson, isOurFormat, normalizeScoreJson, OUR_KEY, xorBytes, extractScoreMeta } from './ibe.ts';
import { decodeMimiPayload, validateDecodedScore } from './ibe.payload.ts';
export { extractScoreMeta };

/** 浏览器端 deflate 解压（DecompressionStream） */
export async function inflateDeflate(bytes: Uint8Array): Promise<Uint8Array> {
  const ds = new DecompressionStream('deflate');
  const stream = new Blob([bytes]).stream().pipeThrough(ds);
  const buf = await new Response(stream).arrayBuffer();
  return new Uint8Array(buf);
}

/** 浏览器端完整解码：原站 AR 格式 + 自有 MIMI 格式 */
export async function decodeIbeToJsonBrowser(ibe: Uint8Array): Promise<Record<string, unknown>> {
  if (isOurFormat(ibe)) {
    const body = xorBytes(ibe.subarray(4), OUR_KEY);
    const inflated = await inflateDeflate(new Uint8Array(body.buffer, body.byteOffset, body.length));
    const payload = JSON.parse(new TextDecoder().decode(inflated)) as Record<string, unknown>;
    return decodeMimiPayload(payload);
  }
  return validateDecodedScore(decodeOriginalIbeToJson(ibe), '原站 IBE 乐谱');
}
