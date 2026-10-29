export type XheChordAnchor = {
  type: 'CHORD_ANCHOR';
  value?: string;
  attributes?: { chord?: string };
};
export type XheItem =
  | { type: 'HEADLINE'; value?: string }
  | { type: 'TEXT'; value?: string }
  | { type: 'LINE_BREAK' }
  | { type: 'RHYTHM'; attributes?: { rhythm?: string } }
  | { type: 'TAB'; attributes?: { tab?: string } }
  | XheChordAnchor;

export type XheJson = { itemList: XheItem[] };
export type XheParsed =
  | { kind: 'json'; items: XheItem[] }
  | { kind: 'text'; text: string }
  | { kind: 'empty' };

/** 解析 XHE 文本谱原始内容：JSON（itemList 和弦锚点格式）或纯文本（Ultimate Guitar 风格）。 */
export function parseXhe(raw: string): XheParsed {
  const t = (raw ?? '').trim();
  if (!t) return { kind: 'empty' };
  if (t.startsWith('{')) {
    try {
      const j = JSON.parse(raw) as XheJson;
      if (Array.isArray(j.itemList)) return { kind: 'json', items: j.itemList };
    } catch {
      /* fall through to text */
    }
  }
  return { kind: 'text', text: raw };
}

/** 将 CHORD_ANCHOR 所在的原始行切分为渲染片段（文本段 / 和弦锚点段）。 */
export type XheSegment =
  | { kind: 'text'; text: string }
  | { kind: 'chord'; chord: string; char: string };

/** 按 LINE_BREAK / HEADLINE / RHYTHM / TAB 切分 itemList 为有序渲染块。 */
export type XheBlock =
  | { kind: 'headline'; text: string }
  | { kind: 'line'; segments: XheSegment[]; chordOnly: boolean }
  | { kind: 'rhythm'; rhythm: string }
  | { kind: 'tab'; tab: string };

export function buildBlocks(items: XheItem[]): XheBlock[] {
  const blocks: XheBlock[] = [];
  let segments: XheSegment[] = [];

  const flushLine = () => {
    // 纯空行（无任何文本/和弦）直接丢弃
    const meaningful = segments.some(
      (s) => (s.kind === 'text' && s.text.trim() !== '') || s.kind === 'chord'
    );
    if (meaningful) {
      const chordOnly =
        segments.filter((s) => s.kind === 'chord').length > 0 &&
        segments.every((s) => s.kind === 'chord' || s.text.trim() === '');
      // 纯和弦行丢弃空文本段，保持片段只含和弦
      const cleanSegs = chordOnly ? segments.filter((s) => s.kind === 'chord') : segments;
      blocks.push({ kind: 'line', segments: cleanSegs, chordOnly });
    }
    segments = [];
  };

  for (const it of items) {
    switch (it.type) {
      case 'HEADLINE': {
        flushLine();
        blocks.push({ kind: 'headline', text: (it.value ?? '').trim() || ' ' });
        break;
      }
      case 'LINE_BREAK': {
        flushLine();
        break;
      }
      case 'TEXT': {
        segments.push({ kind: 'text', text: it.value ?? '' });
        break;
      }
      case 'CHORD_ANCHOR': {
        const chord = (it.attributes?.chord ?? '').trim();
        if (chord) segments.push({ kind: 'chord', chord, char: it.value ?? '' });
        break;
      }
      case 'RHYTHM': {
        flushLine();
        blocks.push({ kind: 'rhythm', rhythm: (it.attributes?.rhythm ?? '').trim() });
        break;
      }
      case 'TAB': {
        flushLine();
        blocks.push({ kind: 'tab', tab: it.attributes?.tab ?? '' });
        break;
      }
      default: {
        segments.push({ kind: 'text', text: '' });
      }
    }
  }
  flushLine();
  return blocks;
}
