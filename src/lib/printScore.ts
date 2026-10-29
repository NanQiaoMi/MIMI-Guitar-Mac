
import { AlphaTabApi, model, ScrollMode } from '@coderline/alphatab';
import { createScoreSettings } from './playerSettings.ts';

/** 打印/PDF 专用设置：关闭播放器与光标交互 */
function createPrintSettings(): any {
  const s = createScoreSettings();
  s.player.enableCursor = false;
  s.player.enablePlayer = false;
  s.player.enableElementHighlighting = false;
  s.player.enableUserInteraction = false;
  s.player.soundFont = null;
  // Studio uses #studio-score-scroll; the regular player uses #score-scroll.
  // A detached export renderer must not inherit either page-specific selector.
  s.player.scrollElement = 'html,body';
  s.player.scrollMode = ScrollMode.Off;
  s.core.useWorkers = false;
  return s;
}

const PRINT_ID = 'mimi-print-sheet';
let printFontCss: Promise<string> | null = null;

function loadPrintFontCss(): Promise<string> {
  printFontCss ??= Promise.all([
    ['MimiExportMusic', '/font/Bravura.woff2'],
    ['Cascadia Code', '/font/CascadiaCode.woff2'],
    ['方正小标宋简体', '/font/FZXiaoBiaoSong.woff2'],
  ].map(async ([family, url]) => {
    const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error(`导出字体资源缺失：${family}，请联网重试。`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length < 128 || bytes.length > 10 * 1024 * 1024 || String.fromCharCode(...bytes.subarray(0, 4)) !== 'wOF2') {
      throw new Error(`导出字体资源无效：${family}，未生成文件。`);
    }
    let binary = '';
    for (let offset = 0; offset < bytes.length; offset += 8192) binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
    return `@font-face{font-family:'${family}';src:url(data:font/woff2;base64,${btoa(binary)}) format('woff2');font-style:normal;font-weight:normal;}`;
  })).then((styles) => styles.join('')).catch((cause) => { printFontCss = null; throw cause; });
  return printFontCss;
}

function releasePrintResources(api: AlphaTabApi | null): void {
  try { api?.destroy(); } catch { /* cleanup must not hide the export's original result */ }
  document.getElementById(PRINT_ID)?.remove();
}

function getPrintRoot(): HTMLDivElement {
  let root = document.getElementById(PRINT_ID) as HTMLDivElement | null;
  if (root) throw new Error('另一份打印或导出正在生成，请等待完成后重试。');
  if (!root) {
    root = document.createElement('div');
    root.id = PRINT_ID;
    root.style.position = 'fixed';
    root.style.left = '0';
    root.style.top = '0';
    root.style.width = '794px';
    root.style.opacity = '0';
    root.style.pointerEvents = 'none';
    document.body.appendChild(root);
  }
  root.innerHTML = '';
  return root;
}

function watermarkSvg(text: string, width = 794, height = 1123): string {
  const safeText = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  const cols = Math.ceil(width / 300) + 2;
  const rows = Math.ceil(height / 180) + 2;
  let items = '';
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = 300 * c + (r % 2 === 0 ? 0 : 150);
      const y = 180 * r;
      items += `<text x="${x}" y="${y}" fill="#333" fill-opacity="0.05" font-size="24" font-family="Arial, sans-serif" font-weight="bold" transform="rotate(-25 ${x} ${y})">${safeText}</text>`;
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" class="print-watermark-svg" width="${width}" height="${height}" style="position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:1;overflow:visible">${items}</svg>`;
}

function svgPage(width: number, height: number, inner: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="${width}" height="${height}">${inner}</svg>`;
}

function svgToJpeg(svgText: string, scale = 2, fontCss = ''): Promise<{ imgData: string; width: number; height: number } | null> {
  return new Promise((resolve) => {
    try {
      const doc = new DOMParser().parseFromString(svgText, 'image/svg+xml');
      const root = doc.documentElement;
      const w = Number(root.getAttribute('width')) || 794;
      const h = Number(root.getAttribute('height')) || 1123;
      if (fontCss) {
        const style = doc.createElementNS('http://www.w3.org/2000/svg', 'style');
        style.textContent = fontCss + '.at-surface-svg text{dominant-baseline:alphabetic;white-space:pre;}';
        root.insertBefore(style, root.firstChild);
      }
      const standaloneSvg = new XMLSerializer().serializeToString(root);
      const url = `data:image/svg+xml;base64,${btoa(unescape(encodeURIComponent(standaloneSvg)))}`;
      const canvas = document.createElement('canvas');
      canvas.width = w * scale;
      canvas.height = h * scale;
      const ctx = canvas.getContext('2d');
      if (!ctx) return resolve(null);
      ctx.scale(scale, scale);
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, w, h);
      const img = new Image();
      img.onload = () => {
        try {
          ctx.drawImage(img, 0, 0, w, h);
          const imgData = canvas.toDataURL('image/jpeg', 0.92);
          resolve(imgData.startsWith('data:image/jpeg') ? { imgData, width: w, height: h } : null);
        } catch {
          resolve(null);
        }
      };
      img.onerror = () => resolve(null);
      img.src = url;
    } catch {
      resolve(null);
    }
  });
}

/** 生成分页 SVG 页（A4 794x1123），水印 @谱全了+作者 */
function paginateScore(svgs: SVGElement[], watermark: string): string[] {
  const pageW = 794;
  const pageH = 1123;
  const scale = 734 / pageW;
  const pages: string[] = [];
  let pageItems: string[] = [];
  let y = 40;
  for (const svg of svgs) {
    const printable = svg.cloneNode(true) as SVGElement;
    const musicGroups = [...svg.querySelectorAll<SVGElement>('.at')];
    [...printable.querySelectorAll<SVGElement>('.at')].forEach((group, index) => {
      // The original .at font rule depends on an ancestor outside the SVG.
      // Standalone SVG images cannot inherit document CSS or web font faces.
      group.style.fontFamily = 'MimiExportMusic';
      group.style.fontSize = getComputedStyle(musicGroups[index]).fontSize;
      group.style.fontStyle = 'normal';
      group.style.fontWeight = 'normal';
    });
    const hRaw = Number(svg.getAttribute('height'));
    const h = (isFinite(hRaw) && hRaw > 0 ? hRaw : svg.clientHeight || 100) * scale;
    if (h + 70 > pageH) throw new Error('单个谱面系统超过 A4 页面高度，请减少导出的音轨后重试；未生成文件。');
    if (pageItems.length && y + h + 30 >= pageH) {
      pages.push(svgPage(pageW, pageH, `<g transform="translate(30, 0) scale(${scale})">${pageItems.join('')}</g>`));
      pageItems = [];
      y = 40;
    }
    printable.setAttribute('y', String(y / scale));
    printable.setAttribute('overflow', 'visible');
    pageItems.push(printable.outerHTML);
    y += h;
  }
  if (pageItems.length > 0) pages.push(svgPage(pageW, pageH, `<g transform="translate(30, 0) scale(${scale})">${pageItems.join('')}</g>`));
  return pages;
}

async function renderForPrint(
  score: model.Score,
  watermark: string,
  trackIndexes?: number[],
  apiConstructor?: typeof AlphaTabApi,
): Promise<{ pages: string[]; api: AlphaTabApi | null; fontCss: string }> {
  if (!score || !Array.isArray(score.tracks) || score.tracks.length === 0) {
    throw new Error('乐谱尚未载入，无法生成打印文件。');
  }
  const selected = trackIndexes ?? score.tracks.map((_, index) => index);
  if (!selected.length || selected.some((index) => !Number.isInteger(index) || !score.tracks[index])) {
    throw new Error('导出音轨无效，请重新选择要显示的音轨。');
  }
  const root = getPrintRoot();
  const scoreBox = document.createElement('div');
  scoreBox.className = 'print-sheet-score';
  root.appendChild(scoreBox);
  root.insertAdjacentHTML('beforeend', watermarkSvg(watermark));

  const settings = createPrintSettings();
  let api: AlphaTabApi | null = null;
  try {
    const fontCss = await loadPrintFontCss();
    // The native shell loads AlphaTab's classic runtime for its live score. Reuse
    // that constructor for the detached renderer so model objects stay in the
    // same runtime; web pages without the global continue using the module copy.
    const nativeAlphaTabWindow = window as Window & {
      alphaTab?: { AlphaTabApi?: typeof AlphaTabApi };
    };
    const NativeOrModuleApi = apiConstructor ?? nativeAlphaTabWindow.alphaTab?.AlphaTabApi ?? AlphaTabApi;
    const renderer = new NativeOrModuleApi(scoreBox, settings);
    api = renderer;
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      let offFinished = () => {};
      let offError = () => {};
      const finish = (failure?: Error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        offFinished(); offError();
        if (failure) reject(failure); else resolve();
      };
      const timeout = setTimeout(() => finish(new Error('导出排版超时，未生成文件，请重试。')), 15000);
      offFinished = renderer.postRenderFinished.on(() => {
        if (renderer.score === score && [...scoreBox.querySelectorAll('svg')].some((svg) => svg.children.length)) finish();
      });
      offError = renderer.error.on(() => finish(new Error('导出排版失败，未生成文件，请检查谱面后重试。')));
      try { renderer.renderScore(score, [...new Set(selected)]); }
      catch (cause) { finish(cause instanceof Error ? cause : new Error(String(cause))); }
    });
    const svgs = Array.from(scoreBox.querySelectorAll('svg'));
    const pages = paginateScore(svgs, watermark);
    if (pages.length === 0) throw new Error('没有生成可打印的谱面内容，请检查工程后重试。');
    return { pages, api, fontCss };
  } catch (error) {
    try { api?.destroy(); } catch {}
    root.remove();
    throw error;
  }
}

/** 打印：隐藏容器重渲染 + window.print */
export async function printScore(score: model.Score, title: string, author: string, trackIndexes?: number[]): Promise<void> {
  const watermark = author ? `${author}@谱全了` : '@谱全了';
  const { pages, api, fontCss } = await renderForPrint(score, watermark, trackIndexes);
  api?.pause?.();
  try { api?.destroy(); } catch {}
  const root = document.getElementById(PRINT_ID)!;
  root.innerHTML = '';
  const fontStyle = document.createElement('style');
  fontStyle.textContent = fontCss;
  root.appendChild(fontStyle);
  for (const page of pages) {
    const section = document.createElement('div');
    section.className = 'mimi-print-page';
    section.innerHTML = page;
    root.appendChild(section);
  }
  const style = document.createElement('style');
  style.textContent = `@media print { @page { size: A4; margin: 0; } body * { visibility: hidden; } #${PRINT_ID}, #${PRINT_ID} * { visibility: visible; } #${PRINT_ID} { position: absolute !important; left: 0; top: 0; opacity: 1 !important; } #${PRINT_ID} .mimi-print-page { width: 794px; height: 1123px; overflow: hidden; break-after: page; } #${PRINT_ID} .mimi-print-page:last-child { break-after: auto; } }`;
  document.head.appendChild(style);
  window.print();
  setTimeout(() => { style.remove(); releasePrintResources(api); }, 1000);
}

type PdfPageImage = { imgData: string; width: number; height: number };
type PdfDocument = { addPage(): unknown; addImage(data: string, format: string, x: number, y: number, width: number, height: number): unknown; save(filename: string): unknown };

/** Adds every rasterized page before saving; an encoding error rejects the export. */
export async function savePdfPages(
  pages: string[],
  filename: string,
  createPdf: () => PdfDocument,
  rasterize: (page: string) => Promise<PdfPageImage | null> = svgToJpeg,
  afterPage: () => Promise<void> = () => new Promise((resolve) => {
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(() => resolve());
    else setTimeout(resolve, 0);
  }),
): Promise<void> {
  if (!pages.length) throw new Error('没有生成可打印的谱面页面，未保存 PDF。');
  const pdf = createPdf();
  for (let i = 0; i < pages.length; i++) {
    const image = await rasterize(pages[i]);
    if (!image?.imgData?.startsWith('data:image/jpeg')) {
      throw new Error(`第 ${i + 1} 页的谱面图像编码失败，未保存 PDF。`);
    }
    if (i > 0) pdf.addPage();
    pdf.addImage(image.imgData, 'JPEG', 0, 0, 210, 297);
    await afterPage();
  }
  pdf.save(filename);
}

/** 下载 PDF：分页 SVG → Canvas → JPEG → jsPDF */
export async function downloadPdf(score: model.Score, title: string, author: string, trackIndexes?: number[]): Promise<void> {
  const watermark = author ? `${author}@谱全了` : '@谱全了';
  const { pages, api, fontCss } = await renderForPrint(score, watermark, trackIndexes);
  try {
    const { jsPDF } = await import('jspdf');
    const filename = title ? `${title}.pdf` : 'score.pdf';
    await savePdfPages(
      pages,
      filename,
      () => new jsPDF({ orientation: 'p', unit: 'mm', format: 'a4' }),
      (page) => svgToJpeg(page, 2, fontCss),
    );
  } finally {
    releasePrintResources(api);
  }
}

/** Render each full-score A4 page as a JPEG for native PDF composition. */
export async function renderScorePdfPageImages(
  score: model.Score,
  author: string,
  trackIndexes?: number[],
  apiConstructor?: typeof AlphaTabApi,
): Promise<{ widthPoints: number; heightPoints: number; pages: string[] }> {
  const watermark = author ? `${author}@谱全了` : '@谱全了';
  const { pages, api, fontCss } = await renderForPrint(score, watermark, trackIndexes, apiConstructor);
  try {
    const images: string[] = [];
    for (let index = 0; index < pages.length; index++) {
      const image = await svgToJpeg(pages[index], 2, fontCss);
      if (!image?.imgData.startsWith('data:image/jpeg;base64,')) {
        throw new Error(`第 ${index + 1} 页无法转换为 PDF 图像，未生成文件。`);
      }
      images.push(image.imgData.slice('data:image/jpeg;base64,'.length));
    }
    if (!images.length) throw new Error('没有生成可打印的谱面页面，未生成文件。');
    return { widthPoints: 595.275590551, heightPoints: 841.88976378, pages: images };
  } finally {
    releasePrintResources(api);
  }
}

async function renderLongImageBlob(
  score: model.Score,
  trackIndexes: number[],
  apiConstructor?: typeof AlphaTabApi,
): Promise<Blob> {
  if (!score) throw new Error('请等待谱面加载完成后再导出。');
  const { pages, api, fontCss } = await renderForPrint(score, 'MIMI Guitar', trackIndexes, apiConstructor);
  try {
    const width = 794;
    const height = pages.length * 1123;
    if (!pages.length) throw new Error('谱面尚未排版完成，请重试。');
    if (height > 16384 || width * height > 16_000_000) {
      throw new Error('谱面超过长图导出上限，请使用分页 PDF 导出。');
    }
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('当前浏览器无法创建导出画布。');
    context.fillStyle = '#fff';
    context.fillRect(0, 0, width, height);
    for (let index = 0; index < pages.length; index++) {
      const rendered = await svgToJpeg(pages[index], 1, fontCss);
      if (!rendered) throw new Error(`第 ${index + 1} 页无法转换为图片，请重试。`);
      const image = new Image();
      image.src = rendered.imgData;
      await image.decode();
      context.drawImage(image, 0, index * 1123, width, 1123);
    }
    return await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(value => value ? resolve(value) : reject(new Error('图片编码失败。')), 'image/png');
    });
  } finally {
    releasePrintResources(api);
  }
}

async function blobToBase64(blob: Blob): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

/** Return the same paginated, canvas-limited PNG for native save panels. */
export async function renderScorePngData(sourceApi: AlphaTabApi): Promise<string> {
  if (!sourceApi?.score) throw new Error('请等待谱面加载完成后再导出。');
  return blobToBase64(await renderLongImageBlob(sourceApi.score, sourceApi.tracks.map((track) => track.index)));
}

/** Render a Studio snapshot with its own AlphaTab module instance. */
export async function renderScorePngDataForScore(score: model.Score): Promise<string> {
  return blobToBase64(await renderLongImageBlob(score, score.tracks.map((_track, index) => index), AlphaTabApi));
}

/** Export the rendered score, with explicit browser canvas limits. */
export async function exportScoreToImage(sourceApi: AlphaTabApi, title: string): Promise<void> {
  if (!sourceApi?.score) throw new Error('请等待谱面加载完成后再导出。');
  const blob = await renderLongImageBlob(sourceApi.score, sourceApi.tracks.map((track) => track.index));
  const url = URL.createObjectURL(blob);
  let anchor: HTMLAnchorElement | null = null;
  try {
    anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `${(title || 'score').replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').slice(0, 160)}.png`;
    document.body.appendChild(anchor);
    anchor.click();
  } finally {
    anchor?.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
}
