import { deflateSync, inflateSync } from 'node:zlib';
import {
  OUR_KEY,
  OUR_MAGIC,
  decodeOriginalIbeToJson,
  isOurFormat,
  xorBytes,
} from './ibe.ts';
import { decodeMimiPayload, validateDecodedScore } from './ibe.payload.ts';

/** Node 端完整解码：同时支持原站 AR 格式与自有 MIMI 格式 */
export function decodeIbeToJsonNode(ibe: Uint8Array): Record<string, unknown> {
  if (isOurFormat(ibe)) {
    const body = xorBytes(ibe.subarray(4), OUR_KEY);
    const inflated = inflateSync(new Uint8Array(body.buffer, body.byteOffset, body.length));
    const payload = JSON.parse(new TextDecoder().decode(inflated)) as Record<string, unknown>;
    return decodeMimiPayload(payload);
  }
  return validateDecodedScore(decodeOriginalIbeToJson(ibe), '原站 IBE 乐谱');
}

/** Node 端自有格式编码：归一化 JSON → MIMI 魔数 + deflate + XOR */
export function encodeJsonToIbeNode(scoreObj: Record<string, unknown>): Uint8Array {
  const json = JSON.stringify(scoreObj);
  const deflated = deflateSync(new TextEncoder().encode(json));
  const xored = xorBytes(new Uint8Array(deflated), OUR_KEY);
  const magic = new TextEncoder().encode(OUR_MAGIC);
  const out = new Uint8Array(magic.length + xored.length);
  out.set(magic, 0);
  out.set(new Uint8Array(xored.buffer, xored.byteOffset, xored.length), magic.length);
  return out;
}
