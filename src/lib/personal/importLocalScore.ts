import { OUR_KEY, OUR_MAGIC, normalizeScoreJson, xorBytes } from '../ibe.ts';
import { decodeIbeToJsonBrowser } from '../ibe.browser.ts';
import { validateDecodedScore } from '../ibe.payload.ts';

function exactBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(copy).set(bytes);
  return copy;
}

export interface PreparedLocalScore {
  originalBytes: Uint8Array;
  playableBytes: Uint8Array;
  scoreJson: Record<string, unknown>;
  title: string;
  artist: string;
  sourceFormat: 'ibe' | 'gp';
}

async function encodeJsonToIbe(value: Record<string, unknown>): Promise<Uint8Array> {
  const normalized = normalizeScoreJson(value);
  const raw = new TextEncoder().encode(JSON.stringify(normalized));
  const compressed = new Uint8Array(await new Response(new Blob([exactBuffer(raw)]).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer());
  const encrypted = xorBytes(compressed, OUR_KEY);
  const output = new Uint8Array(OUR_MAGIC.length + encrypted.length);
  output.set(new TextEncoder().encode(OUR_MAGIC), 0);
  output.set(new Uint8Array(encrypted.buffer, encrypted.byteOffset, encrypted.byteLength), OUR_MAGIC.length);
  return output;
}

export async function prepareLocalScore(file: File): Promise<PreparedLocalScore> {
  const extension = file.name.split('.').pop()?.toLowerCase() ?? '';
  if (file.size <= 0) throw new Error('文件为空，未保存任何个人资料');
  if (file.size > 30 * 1024 * 1024) throw new Error('文件超过 30 MiB，未保存任何个人资料');
  const originalBytes = new Uint8Array(await file.arrayBuffer());
  let scoreJson: Record<string, unknown>;
  let playableBytes: Uint8Array<ArrayBufferLike> = originalBytes;
  let sourceFormat: 'ibe' | 'gp';

  if (extension === 'ibe') {
    const { installBrowserAr } = await import('../ar.browser.ts');
    installBrowserAr();
    scoreJson = await decodeIbeToJsonBrowser(originalBytes);
    sourceFormat = 'ibe';
  } else if (['gp', 'gp3', 'gp4', 'gp5', 'gpx'].includes(extension)) {
    const alphaTab = await import('@coderline/alphatab');
    const settings = new alphaTab.Settings();
    settings.player.enablePlayer = false;
    try {
      const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(originalBytes, settings);
      scoreJson = JSON.parse(alphaTab.model.JsonConverter.scoreToJson(score)) as Record<string, unknown>;
      scoreJson = validateDecodedScore(normalizeScoreJson(scoreJson), `${extension.toUpperCase()} 文件`);
      playableBytes = await encodeJsonToIbe(scoreJson);
      await decodeIbeToJsonBrowser(playableBytes);
    } catch (error) {
      throw new Error(`无法完整解析 ${extension.toUpperCase()} 多音轨谱：${error instanceof Error ? error.message : String(error)}`);
    }
    sourceFormat = 'gp';
  } else {
    throw new Error('首期个人曲库支持 .ibe、.gp、.gp3、.gp4、.gp5、.gpx；其他格式未导入，原页面保持不变。');
  }

  const title = typeof scoreJson.title === 'string' && scoreJson.title.trim() ? scoreJson.title.trim() : file.name.replace(/\.[^.]+$/, '');
  const artist = typeof scoreJson.artist === 'string' ? scoreJson.artist.trim() : '';
  return { originalBytes, playableBytes, scoreJson, title, artist, sourceFormat };
}
