<script lang="ts">
  import { onMount } from 'svelte';
  import { parseXhe, buildBlocks } from '../../lib/xhe';
  import type { XheParsed, XheBlock, XheSegment } from '../../lib/xhe';
  import { chordSvg, lookupChord, normalizeChord } from '../../lib/chords';

  export let xheUrl = '';
  export let title = '';

  let parsed: XheParsed = { kind: 'empty' };
  let blocks: XheBlock[] = [];
  let loading = true;
  let loadError = '';

  onMount(async () => {
    try {
      const res = await fetch(xheUrl);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const raw = await res.text();
      parsed = parseXhe(raw);
      if (parsed.kind === 'json') blocks = buildBlocks(parsed.items);
    } catch (e: any) {
      loadError = e?.message ?? String(e);
    } finally {
      loading = false;
    }
  });

  function segChord(seg: XheSegment): string {
    return normalizeChord(seg.kind === 'chord' ? seg.chord : '');
  }
  function segChar(seg: XheSegment): string {
    if (seg.kind === 'text') return seg.text;
    return seg.char && seg.char.length > 0 ? seg.char : '\u00A0\u00A0';
  }
  function diagramSvg(seg: XheSegment): string {
    const nm = segChord(seg);
    const fing = lookupChord(nm);
    if (!fing) return '';
    return chordSvg(nm, fing);
  }
  function unknownChord(seg: XheSegment): string {
    const nm = segChord(seg);
    return nm && !lookupChord(nm) ? nm : '';
  }

  // —— 歌词行布局：按等宽网格（中文=16px、拉丁/空格=9.6px）计算每个和弦图左侧位置，
  // 与参考站一致（left = 字符偏移 - 6），并对相邻和弦图施加最小间距避免重叠。
  function isCjk(ch: string): boolean {
    const c = ch.codePointAt(0) ?? 0;
    return (c >= 0x2e80 && c <= 0x9fff) || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xff00 && c <= 0xffef);
  }
  function runeWidth(ch: string): number {
    return isCjk(ch) ? 16 : 9.6;
  }
  function textWidth(s: string): number {
    let w = 0;
    for (const ch of s) w += runeWidth(ch);
    return w;
  }

  type ChordLayout = { seg: XheSegment; left: number };
  function layoutLine(segments: XheSegment[]): ChordLayout[] {
    let offset = 0;
    const anchors: ChordLayout[] = [];
    for (const seg of segments) {
      if (seg.kind === 'text') {
        offset += textWidth(seg.text);
      } else {
        anchors.push({ seg, left: offset - 6 });
        offset += textWidth(segChar(seg));
      }
    }
    // 最小间距：相邻和弦图至少 52px（48px 图 + 4px 间隙）
    let prevRight = -Infinity;
    for (const a of anchors) {
      if (a.left < prevRight + 4) a.left = prevRight + 4;
      prevRight = a.left + 48;
    }
    return anchors;
  }
</script>

<div class="xhe-viewer relative overflow-hidden">
  {#if !loading && !loadError}
    <div class="score-sweep-line pointer-events-none"></div>
  {/if}
  {#if loading}
    <div class="xhe-empty">文本谱加载中…</div>
  {:else if loadError}
    <div class="xhe-empty xhe-empty-error">文本谱加载失败：{loadError}</div>
  {:else if parsed.kind === 'text'}
    <div class="xhe-text-wrap">
      <pre class="xhe-text" id="chordScore">{parsed.text}</pre>
    </div>
  {:else if parsed.kind === 'json'}
    <div class="xhe-json">
      <div class="xhe-title">{title}</div>
      <div class="xhe-body">
        {#each blocks as block, i (i)}
          {#if block.kind === 'headline'}
            <h3 class="xhe-headline">{block.text}</h3>
          {:else if block.kind === 'rhythm'}
            <div class="xhe-rhythm">
              <span class="xhe-rhythm-label">节奏</span>
              <span class="xhe-rhythm-body">{block.rhythm}</span>
            </div>
          {:else if block.kind === 'tab'}
            <pre class="xhe-tab">{block.tab}</pre>
          {:else if block.chordOnly}
            <div class="xhe-chord-row">
              {#each block.segments as seg, j (j)}
                <div class="xhe-chord-cell">
                  {#if diagramSvg(seg)}
                    {@html diagramSvg(seg)}
                  {:else}
                    <span class="xhe-chord-fallback">{segChord(seg)}</span>
                  {/if}
                </div>
              {/each}
            </div>
          {:else}
            {@const chords = layoutLine(block.segments)}
            <div class="xhe-line">
              <div class="xhe-lyric">
                {#each block.segments as seg, j (j)}
                  {#if seg.kind === 'text'}
                    <span class="xhe-text-seg">{seg.text}</span>
                  {:else}
                    <span class="xhe-anchor">
                      <span class="xhe-anchor-char">{segChar(seg)}</span>
                    </span>
                  {/if}
                {/each}
              </div>
              {#each chords as c, k (k)}
                <span class="xhe-chord-pos" style="left: {c.left}px">
                  {#if diagramSvg(c.seg)}
                    {@html diagramSvg(c.seg)}
                  {:else if unknownChord(c.seg)}
                    <span class="xhe-chord-pos-name">{unknownChord(c.seg)}</span>
                  {/if}
                </span>
              {/each}
            </div>
          {/if}
        {/each}
      </div>
    </div>
  {/if}
</div>

<style>
  .xhe-viewer {
    font-family: 'Cascadia Code', 'Courier New', ui-monospace, monospace;
    color: #333;
    line-height: 1.5;
  }
  .xhe-empty {
    padding: 3rem 1rem;
    text-align: center;
    color: #646464;
    font-size: 0.9375rem;
  }
  .xhe-empty-error {
    color: #b3261e;
  }
  .xhe-text-wrap {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px 20px 20px 32px;
    overflow-x: auto;
  }
  .xhe-text {
    margin: 0;
    padding: 20px;
    font-family: inherit;
    font-size: 0.9375rem;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-word;
    color: #000;
  }
  .xhe-json {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px 20px 20px 40px;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
  }
  .xhe-title {
    padding: 20px;
    text-align: center;
    font-size: 1.5rem;
    line-height: 1.5;
    color: #000;
  }
  .xhe-body {
    padding: 20px;
    min-width: min-content;
  }
  .xhe-headline {
    margin: 30px 0 10px;
    padding: 5px 10px;
    background: #f2f2f2;
    color: #666;
    font-family: inherit;
    font-size: 1rem;
    font-weight: 600;
  }
  .xhe-line {
    position: relative;
    min-height: 60px;
    margin: 25px 0 15px;
    overflow: visible;
    padding-top: 44px;
  }
  .xhe-lyric {
    position: relative;
    color: #333;
    font-size: 16px;
    white-space: pre;
    font-family: inherit;
  }
  .xhe-anchor {
    position: relative;
  }
  .xhe-anchor-char {
    color: #333;
    position: relative;
    border-bottom: 1px solid #000;
  }
  .xhe-chord-pos {
    position: absolute;
    top: 0;
    width: 48px;
    height: 44px;
    z-index: 10;
    pointer-events: none;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    overflow: visible;
    line-height: 0;
  }
  .xhe-chord-pos svg {
    width: 50.4px;
    height: 52.8px;
    display: block;
  }
  .xhe-chord-pos-name {
    font-size: 12px;
    color: #e53e3e;
    font-weight: 700;
    line-height: 1;
    padding: 2px 4px;
    white-space: nowrap;
  }
  .xhe-chord-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5em;
    align-items: flex-end;
    margin: 25px 0 15px;
    min-height: 60px;
  }
  .xhe-chord-cell {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 40px;
  }
  .xhe-chord-cell svg {
    width: 50.4px;
    height: 52.8px;
    display: block;
  }
  .xhe-chord-fallback {
    font-size: 14px;
    font-weight: 700;
    color: #e53e3e;
  }
  .xhe-rhythm {
    margin: 20px 0;
    padding: 8px 12px;
    background: #f9faf7;
    border: 1px solid #dee2de;
    border-radius: 8px;
    font-size: 14px;
    color: #2c2c2c;
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0.5rem;
  }
  .xhe-rhythm-label {
    font-weight: 700;
    color: #646464;
  }
  .xhe-rhythm-body {
    font-family: 'Cascadia Code', 'Courier New', monospace;
    white-space: pre-wrap;
  }
  .xhe-tab {
    margin: 20px 0;
    padding: 12px;
    background: #f9faf7;
    border: 1px solid #dee2de;
    border-radius: 8px;
    font-family: 'Cascadia Code', 'Courier New', monospace;
    font-size: 14px;
    line-height: 1.4;
    white-space: pre;
    overflow-x: auto;
    color: #2c2c2c;
  }
</style>
