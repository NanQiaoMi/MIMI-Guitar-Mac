export type ScoreSoundfontFlavor = 'gm' | 'ukulele';

export type ScoreSoundfontRequest = {
  bank: number;
  program: number;
  flavor: ScoreSoundfontFlavor;
};

export type VerifiedScoreSoundfont = ScoreSoundfontRequest & {
  url: string;
  bytes: Uint8Array;
  presetName: string;
};

export type ScoreSoundfontPresetInfo = {
  bank: number;
  program: number;
  presetName: string;
  instrumentIndices: number[];
  sampleNames: string[];
};

export const SCORE_GM_SOUNDFONT_URL = '/soundfonts/sonivox.sf2';
export const SCORE_UKULELE_SOUNDFONT_URL = '/storage/soundfonts/ukulele_fast.sf2';

const GM_SHA256 = '4978cf37e7164206f2d22dc4fdf4020ffe040787210bf781e31bdc79961f59ef';
const UKULELE_SHA256 = 'e57ba29a8040ed9afd336e0ebe2bb39090369cd1bd14e1e476f01be9e5089b38';
const UKULELE_PROGRAMS = new Set([0, 24, 25]);
const SOURCES: Record<ScoreSoundfontFlavor, { url: string; sha256: string }> = {
  gm: { url: SCORE_GM_SOUNDFONT_URL, sha256: GM_SHA256 },
  ukulele: { url: SCORE_UKULELE_SOUNDFONT_URL, sha256: UKULELE_SHA256 },
};

type Chunk = { id: string; start: number; dataStart: number; size: number; end: number; paddedEnd: number };
type ParsedSoundfont = {
  bytes: Uint8Array;
  pdta: Chunk;
  sdta: Chunk;
  pdtaChunks: Map<string, Chunk>;
  sdtaChunks: Map<string, Chunk>;
};

const textDecoder = new TextDecoder('ascii');

function fail(message: string): never {
  throw new Error(`Invalid SoundFont: ${message}`);
}

function readU16(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function readU32(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}

function readI8(bytes: Uint8Array, offset: number): number {
  return bytes[offset] > 127 ? bytes[offset] - 256 : bytes[offset];
}

function writeU16(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >>> 8) & 0xff;
}

function writeU32(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >>> 8) & 0xff;
  bytes[offset + 2] = (value >>> 16) & 0xff;
  bytes[offset + 3] = (value >>> 24) & 0xff;
}

function chunkId(bytes: Uint8Array, offset: number): string {
  return textDecoder.decode(bytes.subarray(offset, offset + 4));
}

function readChunks(bytes: Uint8Array, start: number, end: number): Chunk[] {
  const chunks: Chunk[] = [];
  let offset = start;
  while (offset < end) {
    if (offset + 8 > end) fail('truncated chunk header');
    const id = chunkId(bytes, offset);
    const size = readU32(bytes, offset + 4);
    const dataStart = offset + 8;
    const chunkEnd = dataStart + size;
    const paddedEnd = chunkEnd + (size & 1);
    if (chunkEnd > end || paddedEnd > end) fail(`chunk ${id} extends outside its parent`);
    chunks.push({ id, start: offset, dataStart, size, end: chunkEnd, paddedEnd });
    offset = paddedEnd;
  }
  if (offset !== end) fail('misaligned chunk table');
  return chunks;
}

function uniqueChunk(chunks: Chunk[], id: string): Chunk {
  const matches = chunks.filter((chunk) => chunk.id === id);
  if (matches.length !== 1) fail(`expected one ${id} chunk, found ${matches.length}`);
  return matches[0];
}

function listChildren(bytes: Uint8Array, list: Chunk, type: string): Chunk[] {
  if (list.id !== 'LIST' || list.size < 4 || chunkId(bytes, list.dataStart) !== type) {
    fail(`missing LIST ${type}`);
  }
  return readChunks(bytes, list.dataStart + 4, list.end);
}

function parseSoundfont(input: Uint8Array): ParsedSoundfont {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  if (bytes.byteLength < 12 || chunkId(bytes, 0) !== 'RIFF' || chunkId(bytes, 8) !== 'sfbk') {
    fail('expected a RIFF sfbk file');
  }
  if (readU32(bytes, 4) + 8 !== bytes.byteLength) fail('RIFF length does not match file length');
  const rootChunks = readChunks(bytes, 12, bytes.byteLength);
  const lists = rootChunks.filter((chunk) => chunk.id === 'LIST' && chunk.size >= 4);
  const pdtaMatches = lists.filter((chunk) => chunkId(bytes, chunk.dataStart) === 'pdta');
  const sdtaMatches = lists.filter((chunk) => chunkId(bytes, chunk.dataStart) === 'sdta');
  if (pdtaMatches.length !== 1 || sdtaMatches.length !== 1) fail('expected one pdta list and one sdta list');
  const pdta = pdtaMatches[0];
  const sdta = sdtaMatches[0];
  const pdtaChildren = listChildren(bytes, pdta, 'pdta');
  const sdtaChildren = listChildren(bytes, sdta, 'sdta');
  const pdtaChunks = new Map<string, Chunk>();
  for (const id of ['phdr', 'pbag', 'pmod', 'pgen', 'inst', 'ibag', 'imod', 'igen', 'shdr']) {
    pdtaChunks.set(id, uniqueChunk(pdtaChildren, id));
  }
  const sdtaChunks = new Map<string, Chunk>();
  for (const id of ['smpl']) sdtaChunks.set(id, uniqueChunk(sdtaChildren, id));
  return { bytes, pdta, sdta, pdtaChunks, sdtaChunks };
}

function chunkBytes(parsed: ParsedSoundfont, table: Map<string, Chunk>, id: string): Uint8Array {
  const chunk = table.get(id)!;
  return parsed.bytes.subarray(chunk.dataStart, chunk.end);
}

function recordRows(bytes: Uint8Array, recordSize: number, id: string): number {
  if (bytes.byteLength % recordSize !== 0) fail(`${id} chunk has a partial record`);
  return bytes.byteLength / recordSize;
}

function nameAt(bytes: Uint8Array, offset: number, length: number): string {
  const slice = bytes.subarray(offset, offset + length);
  const zero = slice.indexOf(0);
  return textDecoder.decode(zero < 0 ? slice : slice.subarray(0, zero)).trim();
}

function targetPreset(parsed: ParsedSoundfont, bank: number, program: number) {
  const phdr = chunkBytes(parsed, parsed.pdtaChunks, 'phdr');
  const pbag = chunkBytes(parsed, parsed.pdtaChunks, 'pbag');
  const pmod = chunkBytes(parsed, parsed.pdtaChunks, 'pmod');
  const pgen = chunkBytes(parsed, parsed.pdtaChunks, 'pgen');
  const inst = chunkBytes(parsed, parsed.pdtaChunks, 'inst');
  const ibag = chunkBytes(parsed, parsed.pdtaChunks, 'ibag');
  const igen = chunkBytes(parsed, parsed.pdtaChunks, 'igen');
  const shdr = chunkBytes(parsed, parsed.pdtaChunks, 'shdr');
  const smpl = chunkBytes(parsed, parsed.sdtaChunks, 'smpl');
  const phdrRows = recordRows(phdr, 38, 'phdr');
  const pbagRows = recordRows(pbag, 4, 'pbag');
  const pmodRows = recordRows(pmod, 10, 'pmod');
  const pgenRows = recordRows(pgen, 4, 'pgen');
  const instRows = recordRows(inst, 22, 'inst');
  const ibagRows = recordRows(ibag, 4, 'ibag');
  const igenRows = recordRows(igen, 4, 'igen');
  const shdrRows = recordRows(shdr, 46, 'shdr');
  if (phdrRows < 2 || pbagRows < 1 || pmodRows < 1 || pgenRows < 1 || instRows < 2 || ibagRows < 1 || igenRows < 1 || shdrRows < 2) {
    fail('preset, instrument, or sample tables are incomplete');
  }
  if (nameAt(phdr, (phdrRows - 1) * 38, 20) !== 'EOP') fail('phdr terminal record is missing');
  if (nameAt(inst, (instRows - 1) * 22, 20) !== 'EOI') fail('inst terminal record is missing');
  if (nameAt(shdr, (shdrRows - 1) * 46, 20) !== 'EOS') fail('shdr terminal record is missing');
  if (smpl.byteLength % 2 !== 0) fail('smpl data is not 16-bit aligned');

  const matches: Array<{ index: number; name: string; bagStart: number; bagEnd: number }> = [];
  for (let index = 0; index < phdrRows - 1; index++) {
    const offset = index * 38;
    if (readU16(phdr, offset + 20) !== program || readU16(phdr, offset + 22) !== bank) continue;
    matches.push({
      index,
      name: nameAt(phdr, offset, 20),
      bagStart: readU16(phdr, offset + 24),
      bagEnd: readU16(phdr, offset + 38 + 24),
    });
  }
  if (matches.length !== 1) fail(`bank ${bank}, program ${program} has ${matches.length} presets`);
  const preset = matches[0];
  if (!preset.name) fail('target preset has an empty name');
  if (preset.bagStart >= preset.bagEnd || preset.bagEnd >= pbagRows) fail('target preset has invalid bag bounds');

  const instrumentIndices = new Set<number>();
  for (let bagIndex = preset.bagStart; bagIndex < preset.bagEnd; bagIndex++) {
    const genStart = readU16(pbag, bagIndex * 4);
    const genEnd = readU16(pbag, (bagIndex + 1) * 4);
    const modStart = readU16(pbag, bagIndex * 4 + 2);
    const modEnd = readU16(pbag, (bagIndex + 1) * 4 + 2);
    if (genStart > pgenRows - 1 || genEnd > pgenRows - 1 || modStart > pmodRows - 1 || modEnd > pmodRows - 1) {
      fail('target preset zone has invalid generator/modulator bounds');
    }
    // A few legacy split banks reset the generator index at a preset boundary;
    // that makes the last bag empty (descending indexes), while preceding
    // zones still carry a valid instrument reference. Ignore only that empty
    // reset slot and retain the original bag table when producing a filtered
    // preset so the source's valid zone indexing remains unchanged.
    if (genEnd < genStart || modEnd < modStart) continue;
    for (let genIndex = genStart; genIndex < genEnd; genIndex++) {
      const genOffset = genIndex * 4;
      if (readU16(pgen, genOffset) === 41) instrumentIndices.add(readU16(pgen, genOffset + 2));
    }
  }
  if (instrumentIndices.size === 0) fail('target preset does not reference an instrument');

  const sampleNames = new Set<string>();
  for (const instrumentIndex of instrumentIndices) {
    if (instrumentIndex >= instRows - 1) fail(`preset references missing instrument ${instrumentIndex}`);
    const instOffset = instrumentIndex * 22;
    const firstBag = readU16(inst, instOffset + 20);
    const afterBag = readU16(inst, instOffset + 22 + 20);
    if (firstBag >= afterBag || afterBag >= ibagRows) fail(`instrument ${instrumentIndex} has invalid bag bounds`);
    let instrumentHasSample = false;
    for (let bagIndex = firstBag; bagIndex < afterBag; bagIndex++) {
      const genStart = readU16(ibag, bagIndex * 4);
      const genEnd = readU16(ibag, (bagIndex + 1) * 4);
      if (genStart > genEnd || genEnd > igenRows - 1) fail(`instrument ${instrumentIndex} has invalid generator bounds`);
      for (let genIndex = genStart; genIndex < genEnd; genIndex++) {
        const genOffset = genIndex * 4;
        if (readU16(igen, genOffset) !== 53) continue;
        const sampleIndex = readU16(igen, genOffset + 2);
        if (sampleIndex >= shdrRows - 1) fail(`instrument ${instrumentIndex} references missing sample ${sampleIndex}`);
        const sampleOffset = sampleIndex * 46;
        const sampleName = nameAt(shdr, sampleOffset, 20);
        const sampleStart = readU32(shdr, sampleOffset + 20);
        const sampleEnd = readU32(shdr, sampleOffset + 24);
        const sampleRate = readU32(shdr, sampleOffset + 36);
        if (!sampleName || sampleStart >= sampleEnd || sampleEnd > smpl.byteLength / 2 || sampleRate === 0) {
          fail(`sample ${sampleIndex} has invalid sample data bounds`);
        }
        instrumentHasSample = true;
        sampleNames.add(sampleName);
      }
    }
    if (!instrumentHasSample) fail(`instrument ${instrumentIndex} has no sample zones`);
  }

  return {
    preset,
    phdr,
    pbag,
    pmod,
    pgen,
    pbagRows,
    pmodRows,
    pgenRows,
    instrumentIndices: [...instrumentIndices].sort((left, right) => left - right),
    sampleNames: [...sampleNames].sort(),
  };
}

/** Parse and validate one preset, including its instrument and sample references. */
export function inspectScoreSoundfontPreset(bytes: Uint8Array, bank: number, program: number): ScoreSoundfontPresetInfo {
  validateRequestNumbers(bank, program);
  const parsed = parseSoundfont(bytes);
  const result = targetPreset(parsed, bank, program);
  return {
    bank,
    program,
    presetName: result.preset.name,
    instrumentIndices: result.instrumentIndices,
    sampleNames: result.sampleNames,
  };
}

type PresetData = ReturnType<typeof targetPreset>;

function fourcc(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function makeChunk(id: string, payload: Uint8Array): Uint8Array {
  const result = new Uint8Array(8 + payload.byteLength + (payload.byteLength & 1));
  result.set(fourcc(id), 0);
  writeU32(result, 4, payload.byteLength);
  result.set(payload, 8);
  return result;
}

function concat(parts: Uint8Array[]): Uint8Array {
  const size = parts.reduce((sum, part) => sum + part.byteLength, 0);
  const result = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.byteLength;
  }
  return result;
}

function replacePresetTables(parsed: ParsedSoundfont, info: PresetData): Uint8Array {
  const { preset, phdr } = info;
  // Keep the original pbag/pgen offsets intact. Some old soundfonts reuse
  // their zone tables in a way that is accepted by AlphaTab but does not obey
  // the monotonically increasing-index assumption needed to compact them.
  // Restricting phdr to one preset plus EOP is sufficient to prevent any other
  // preset from being selected by AlphaTab.
  const filteredPhdr = new Uint8Array(76);
  filteredPhdr.set(phdr.subarray(preset.index * 38, (preset.index + 1) * 38), 0);
  filteredPhdr.set(phdr.subarray((recordRows(phdr, 38, 'phdr') - 1) * 38), 38);
  writeU16(filteredPhdr, 24, preset.bagStart);
  writeU16(filteredPhdr, 38 + 24, preset.bagEnd);

  const replacementData = new Map<string, Uint8Array>([['phdr', filteredPhdr]]);
  const pdtaChildren = listChildren(parsed.bytes, parsed.pdta, 'pdta');
  const rewrittenPdtaChildren = pdtaChildren.map((chunk) => {
    const replacement = replacementData.get(chunk.id);
    return replacement ? makeChunk(chunk.id, replacement) : parsed.bytes.subarray(chunk.start, chunk.paddedEnd);
  });
  const pdtaPayload = concat([fourcc('pdta'), ...rewrittenPdtaChildren]);
  const rewrittenRoot = readChunks(parsed.bytes, 12, parsed.bytes.byteLength).map((chunk) =>
    chunk.start === parsed.pdta.start ? makeChunk('LIST', pdtaPayload) : parsed.bytes.subarray(chunk.start, chunk.paddedEnd),
  );
  const rootPayload = concat([fourcc('sfbk'), ...rewrittenRoot]);
  const result = makeChunk('RIFF', rootPayload);
  return result;
}

/** Return a valid SF2 containing only the requested preset in its preset table. */
export function filterScoreSoundfontPreset(bytes: Uint8Array, bank: number, program: number): Uint8Array {
  validateRequestNumbers(bank, program);
  const parsed = parseSoundfont(bytes);
  const info = targetPreset(parsed, bank, program);
  return replacePresetTables(parsed, info);
}

function validateRequestNumbers(bank: number, program: number): void {
  if (!Number.isInteger(bank) || bank < 0 || bank > 16383) throw new Error(`Invalid SoundFont bank ${bank}`);
  if (!Number.isInteger(program) || program < 0 || program > 127) throw new Error(`Invalid SoundFont program ${program}`);
}

function validateSoundfontRequest(request: ScoreSoundfontRequest): { flavor: ScoreSoundfontFlavor; source: { url: string; sha256: string } } {
  const flavor = request.flavor;
  if (flavor !== 'gm' && flavor !== 'ukulele') throw new Error(`Unsupported SoundFont flavor: ${String(flavor)}`);
  validateRequestNumbers(request.bank, request.program);
  if (flavor === 'gm' && request.bank !== 0 && request.bank !== 128) {
    throw new Error(`GM SoundFont bank ${request.bank} is unavailable`);
  }
  if (flavor === 'ukulele' && (request.bank !== 0 || !UKULELE_PROGRAMS.has(request.program))) {
    throw new Error(`Ukulele SoundFont bank ${request.bank}, program ${request.program} is unavailable`);
  }
  return { flavor, source: SOURCES[flavor] };
}

const sourceBytesPromises = new Map<string, Promise<Uint8Array>>();
const verifiedSourceBytes = new Map<string, Uint8Array>();

function abortError(): Error {
  if (typeof DOMException !== 'undefined') return new DOMException('Aborted', 'AbortError');
  const error = new Error('Aborted');
  error.name = 'AbortError';
  return error;
}

function awaitCallerAbort<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) return Promise.reject(abortError());
  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const cleanup = () => signal.removeEventListener('abort', onAbort);
    const finish = (callback: (value: any) => void, value: unknown) => {
      if (settled) return;
      settled = true;
      cleanup();
      callback(value);
    };
    const onAbort = () => finish(reject, abortError());
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then((value) => finish(resolve, value), (error) => finish(reject, error));
  });
}

async function sha256(bytes: Uint8Array): Promise<string> {
  if (!globalThis.crypto?.subtle) throw new Error('无法验证音色库完整性：当前浏览器不支持 Web Crypto');
  const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('');
}

function getVerifiedSourceBytes(source: { url: string; sha256: string }): Promise<Uint8Array> {
  const cached = verifiedSourceBytes.get(source.url);
  if (cached) return Promise.resolve(cached);
  const active = sourceBytesPromises.get(source.url);
  if (active) return active;

  const promise = Promise.resolve().then(async () => {
    const controller = new AbortController();
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    let timedOut = false;
    const timeout = new Promise<never>((_resolve, reject) => {
      timeoutId = setTimeout(() => {
        timedOut = true;
        controller.abort();
        reject(new Error(`音色库加载超时：${source.url}`));
      }, 15000);
    });
    const readSource = (async () => {
      const response = await fetch(source.url, { signal: controller.signal });
      if (!response.ok) throw new Error(`无法加载音色库 ${source.url} (HTTP ${response.status})`);
      return new Uint8Array(await response.arrayBuffer());
    })();
    let bytes: Uint8Array;
    try {
      bytes = await Promise.race([readSource, timeout]);
    } catch (error) {
      if (timedOut) throw new Error(`音色库加载超时：${source.url}`);
      throw error;
    } finally {
      if (timeoutId !== undefined) clearTimeout(timeoutId);
    }
    if (bytes.byteLength === 0) throw new Error(`音色库为空：${source.url}`);
    const actualSha256 = await sha256(bytes);
    if (actualSha256 !== source.sha256) {
      throw new Error(`音色库校验失败：${source.url} SHA-256 不匹配`);
    }
    // A pinned hash identifies the exact trusted binary. Parse it before any
    // caller can hand the bytes to AlphaTab or the offline renderer.
    parseSoundfont(bytes);
    verifiedSourceBytes.set(source.url, bytes);
    return bytes;
  }).catch((error) => {
    if (sourceBytesPromises.get(source.url) === promise) sourceBytesPromises.delete(source.url);
    throw error;
  });
  sourceBytesPromises.set(source.url, promise);
  return promise;
}

/**
 * Fetch one pinned local SoundFont, validate the exact requested preset and
 * its sample references, and return a defensive byte copy. A caller abort
 * rejects only that caller; the shared validated fetch remains usable by peers.
 */
export async function loadVerifiedScoreSoundfont(request: {
  bank: number;
  program: number;
  flavor?: ScoreSoundfontFlavor;
  signal?: AbortSignal;
}): Promise<VerifiedScoreSoundfont> {
  const flavor = request.flavor ?? 'gm';
  const { source } = validateSoundfontRequest({ bank: request.bank, program: request.program, flavor });
  const sharedBytes = await awaitCallerAbort(getVerifiedSourceBytes(source), request.signal);
  if (request.signal?.aborted) throw abortError();
  const preset = inspectScoreSoundfontPreset(sharedBytes, request.bank, request.program);
  const outputBytes = flavor === 'ukulele'
    ? filterScoreSoundfontPreset(sharedBytes, request.bank, request.program)
    : sharedBytes.slice();
  return {
    url: source.url,
    bytes: outputBytes,
    bank: request.bank,
    program: request.program,
    flavor,
    presetName: preset.presetName,
  };
}

/** Verify every requested preset and return only the distinct payloads to load. */
export async function loadVerifiedScoreSoundfontPlan(
  requests: readonly ScoreSoundfontRequest[],
  signal?: AbortSignal,
): Promise<VerifiedScoreSoundfont[]> {
  const uniqueRequests = [...new Map(requests.map((request) => [
    `${request.flavor}:${request.bank}:${request.program}`,
    request,
  ])).values()].sort((left, right) => {
    const leftPriority = left.flavor === 'gm' ? 0 : 1;
    const rightPriority = right.flavor === 'gm' ? 0 : 1;
    return leftPriority - rightPriority || left.bank - right.bank || left.program - right.program;
  });

  const flavorByPreset = new Map<string, ScoreSoundfontFlavor>();
  const sourceByRequest = new Map<string, { url: string; sha256: string }>();
  for (const request of uniqueRequests) {
    const { flavor, source } = validateSoundfontRequest(request);
    const presetKey = `${request.bank}:${request.program}`;
    const existingFlavor = flavorByPreset.get(presetKey);
    if (existingFlavor && existingFlavor !== flavor) {
      throw new Error(`Conflicting SoundFont flavors for bank ${request.bank}, program ${request.program}`);
    }
    flavorByPreset.set(presetKey, flavor);
    sourceByRequest.set(`${flavor}:${request.bank}:${request.program}`, source);
  }

  // Fetch each source once. Validate every requested preset against its shared
  // read-only buffer, then allocate one GM copy and one filtered payload for
  // each requested Uke preset. This avoids N full-file copies for N GM tracks.
  const sourceByUrl = new Map<string, { url: string; sha256: string }>();
  for (const source of sourceByRequest.values()) sourceByUrl.set(source.url, source);
  const rawByUrl = new Map(await Promise.all([...sourceByUrl.values()].map(async (source) => [
    source.url,
    await awaitCallerAbort(getVerifiedSourceBytes(source), signal),
  ] as const)));
  if (signal?.aborted) throw abortError();

  const validated = uniqueRequests.map((request) => {
    const source = sourceByRequest.get(`${request.flavor}:${request.bank}:${request.program}`)!;
    const bytes = rawByUrl.get(source.url)!;
    const preset = inspectScoreSoundfontPreset(bytes, request.bank, request.program);
    return { request, source, bytes, preset };
  });

  const gm = validated.find(({ request }) => request.flavor === 'gm');
  const result: VerifiedScoreSoundfont[] = [];
  if (gm) {
    result.push({
      ...gm.request,
      url: gm.source.url,
      bytes: gm.bytes.slice(),
      presetName: gm.preset.presetName,
    });
  }
  for (const entry of validated) {
    if (entry.request.flavor !== 'ukulele') continue;
    result.push({
      ...entry.request,
      url: entry.source.url,
      bytes: filterScoreSoundfontPreset(entry.bytes, entry.request.bank, entry.request.program),
      presetName: entry.preset.presetName,
    });
  }
  return result;
}
