// 吉他 6 弦指法数据库（低音 E → 高音 e，0=空弦，x=闷音，数字=品数）+ 和弦图 SVG 生成
// 指法形状与参考站 guistudy.com XHE 和弦图一致（已逐一对拍 C/F/G/Am/Em/D/Dm/Dm7/Am7/Bm/G7/Cmaj7/E7/Em7/Fmaj7/G/B 等）。

export type FretMap = (string | number)[]; // length 6, low E -> high e

export const GUITAR_CHORDS: Record<string, FretMap> = {
  C: ['x', 3, 2, 0, 1, 0],
  C7: ['x', 3, 2, 3, 1, 0],
  Cmaj7: ['x', 3, 2, 0, 0, 0],
  Cadd9: ['x', 3, 2, 0, 3, 0],
  Cm: ['x', 3, 1, 0, 1, 3],
  Caug: ['x', 3, 2, 1, 1, 0],
  'C/E': [0, 3, 2, 0, 1, 0],
  'C/G': [3, 3, 2, 0, 1, 0],

  D: ['x', 'x', 0, 2, 3, 2],
  Dm: ['x', 'x', 0, 2, 3, 1],
  Dm7: ['x', 'x', 0, 2, 1, 1],
  D7: ['x', 'x', 0, 2, 1, 2],
  Dsus2: ['x', 'x', 0, 2, 3, 0],
  Dsus4: ['x', 'x', 0, 2, 3, 3],
  D6: ['x', 'x', 0, 2, 0, 2],
  D6add9: ['x', 'x', 0, 2, 0, 0],
  Dmaj7: ['x', 'x', 0, 2, 2, 2],
  D11: ['x', 5, 4, 5, 3, 0],
  'D/F#': [2, 'x', 0, 2, 3, 2],

  A: ['x', 0, 2, 2, 2, 0],
  Am: ['x', 0, 2, 2, 1, 0],
  Am7: ['x', 0, 2, 0, 1, 0],
  A7: ['x', 0, 2, 0, 2, 0],
  Asus4: ['x', 0, 2, 2, 3, 0],
  A7sus4: ['x', 0, 2, 0, 3, 0],
  Am9: ['x', 0, 2, 4, 1, 3],
  'Am7/G': [3, 0, 2, 0, 1, 0],
  'Am/F#': [2, 0, 2, 2, 1, 0],
  Ab: ['x', 'x', 1, 1, 1, 4],

  E: [0, 2, 2, 1, 0, 0],
  Em: [0, 2, 2, 0, 0, 0],
  Em7: [0, 2, 2, 0, 3, 0],
  Emaj7: [0, 2, 1, 1, 0, 0],
  E7: [0, 2, 0, 1, 0, 0],
  Esus4: [0, 2, 2, 2, 0, 0],
  'Em/B': ['x', 2, 2, 0, 0, 0],

  F: [1, 3, 3, 2, 1, 1],
  Fm: [1, 3, 3, 1, 1, 1],
  Fmaj7: [1, 'x', 3, 2, 1, 0],
  Fmaj9: [1, 'x', 2, 1, 1, 0],
  F7: [1, 3, 1, 2, 1, 1],
  'F/A': ['x', 0, 3, 2, 1, 1],
  'F/G': [3, 'x', 3, 2, 1, 1],

  G: [3, 2, 0, 0, 0, 3],
  G6: [3, 2, 0, 0, 0, 0],
  G7: [3, 2, 0, 0, 0, 1],
  Gsus4: [3, 2, 0, 0, 1, 3],
  Gsus2: [3, 0, 0, 0, 3, 3],
  Gadd9: [3, 0, 0, 0, 0, 3],
  Gm: [3, 1, 0, 0, 3, 3],
  'G/B': ['x', 2, 0, 0, 0, 3],

  B: ['x', 2, 4, 4, 4, 2],
  Bm: ['x', 2, 4, 4, 3, 2],
  Bm7: ['x', 2, 4, 2, 3, 2],
  B7: ['x', 2, 1, 2, 0, 2],
  Bb: ['x', 1, 3, 3, 3, 1],

  'F#m': [2, 4, 4, 2, 2, 2],
  'F#/D': ['x', 4, 4, 2, 2, 2],
};

export const UKULELE_CHORDS: Record<string, (string | number)[]> = {
  C: [0, 0, 0, 3],
  C7: [0, 0, 0, 1],
  Cmaj7: [0, 0, 0, 2],
  Cadd9: [0, 2, 0, 3],
  Cm: [0, 3, 3, 3],
  D: [2, 2, 2, 0],
  Dm: [2, 2, 1, 0],
  Dm7: [2, 2, 1, 3],
  D7: [2, 0, 2, 0],
  Dsus4: [2, 2, 3, 0],
  Dsus2: [2, 2, 0, 0],
  A: [2, 1, 0, 0],
  Am: [2, 0, 0, 0],
  Am7: [0, 0, 0, 0],
  A7: [0, 1, 0, 0],
  Asus4: [2, 2, 0, 0],
  E: [4, 4, 4, 2],
  Em: [0, 4, 3, 2],
  Em7: [0, 2, 0, 2],
  E7: [1, 2, 0, 2],
  F: [2, 0, 1, 0],
  Fm: [1, 0, 1, 3],
  Fmaj7: [2, 4, 1, 0],
  F7: [2, 3, 1, 0],
  G: [0, 2, 3, 2],
  G7: [0, 2, 1, 2],
  Gsus4: [0, 2, 3, 3],
  Gm: [0, 2, 3, 1],
  B: [4, 3, 2, 2],
  Bm: [4, 2, 2, 2],
  Bm7: [2, 2, 2, 2],
  B7: [2, 3, 2, 2],
  Bb: [3, 2, 1, 1],
  'F#m': [2, 1, 2, 0],
};

// 参考站数据里的别名/笔误 → 规范名
const ALIASES: Record<string, string> = {
  EM: 'Em',
  'EM7': 'Emaj7',
  AM: 'Am',
  DM: 'Dm',
  DM7: 'Dmaj7',
  Famj7: 'Fmaj7',
  F7M: 'Fmaj7',
  Fxm: 'F#m',
  'D/#F': 'D/F#',
  f: 'F',
  G2: 'Gsus2',
  D2: 'Dsus2',
  'G#': 'Ab',
  'I': '',
};

/** 规范化和弦名（去空白、统一大小写、处理笔误别名）。返回规范名；未知返回原 trim。 */
export function normalizeChord(name: string): string {
  let n = (name ?? '').trim();
  if (!n) return '';
  n = n.replace(/\s+/g, '');
  if (ALIASES[n] !== undefined) return ALIASES[n];
  return n;
}

/** 取和弦指法（6 弦，低音 E → 高音 e）；未知和弦返回 null。 */
export function lookupChord(name: string): FretMap | null {
  const n = normalizeChord(name);
  if (!n) return null;
  return GUITAR_CHORDS[n] ?? null;
}

const STRING_X = [8, 14, 20, 26, 32, 38]; // 6 根弦 x 坐标
const FRET_Y = (fret: number) => 19.5 + (fret - 1) * 7; // 1品=19.5, 2品=26.5, 3品=33.5, 4品=40.5

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/** 生成与参考站一致的 6 弦和弦图 SVG 字符串。 */
export function chordSvg(chordName: string, strings: FretMap): string {
  const name = esc(chordName);
  let lines = '';
  // 5 条品线
  for (const y of [16, 23, 30, 37, 44]) lines += `<line x1="8" y1="${y}" x2="38" y2="${y}" stroke-width="1"></line>`;
  // 6 条弦
  for (const x of STRING_X) lines += `<line x1="${x}" y1="16" x2="${x}" y2="44" stroke-width="1"></line>`;
  // 指位圆点 / 闷音 X
  for (let i = 0; i < 6; i++) {
    const v = strings[i];
    const x = STRING_X[i];
    if (v === 'x' || v === 'X') {
      lines += `<line x1="6.5" y1="12.5" x2="9.5" y2="15.5" stroke-width="1.5"></line><line x1="9.5" y1="12.5" x2="6.5" y2="15.5" stroke-width="1.5"></line>`;
    } else {
      const fret = Number(v);
      if (Number.isFinite(fret) && fret > 0) {
        lines += `<circle cx="${x}" cy="${FRET_Y(fret)}" r="2.5" fill="#555555"></circle>`;
      }
    }
  }
  return (
    `<svg width="50.4" height="52.8" viewBox="0 0 42 44" stroke="#333" fill="#333">` +
    `<text x="23" y="11" font-size="8" fill="#E53E3E" font-family="Arial, sans-serif" text-anchor="middle" stroke="none" font-weight="normal" letter-spacing="0px">${name}</text>` +
    lines +
    `</svg>`
  );
}
