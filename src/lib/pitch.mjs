// 音高换算纯函数（供 ScorePlayer 组件与 node --test 单测共用，纯 JS 以便 .mjs 直接导入）

/** 参考站变调夹下拉选项（value: -1=降半调调弦, 0=不夹, 1..6=品数） */
export const CAPO_OPTIONS = [
  { value: -1, label: '降半调调弦' },
  { value: 0, label: '不夹' },
  { value: 1, label: '1品' },
  { value: 2, label: '2品' },
  { value: 3, label: '3品' },
  { value: 4, label: '4品' },
  { value: 5, label: '5品' },
  { value: 6, label: '6品' },
];

export function capoLabel(value) {
  const o = CAPO_OPTIONS.find((x) => x.value === value);
  return o ? o.label : '不夹';
}

/** 变调夹选择相对谱面原始 Capo 的半音偏移（正=升高） */
export function capoDelta(capoValue, originalCapo) {
  return capoValue - (originalCapo || 0);
}

/** 总半音偏移 = 变调夹(含降半调调弦) + 整曲转调；正=升高 */
export function totalTransposition(capoValue, originalCapo, transpose) {
  return capoDelta(capoValue, originalCapo) + (transpose || 0);
}

/** 将转调值约束到 [-12, 12] 并取整 */
export function clampTranspose(v) {
  if (!Number.isFinite(v)) return 0;
  return Math.max(-12, Math.min(12, Math.round(v)));
}

/** 计算转调后的调名（统一以升号记法展示） */
export function transposeKeyName(baseKey, semitones) {
  if (!baseKey) return null;
  const KEYS = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  // 降号键 -> 等音升号表示
  const FLAT_MAP = {
    cb: 'B', db: 'C#', eb: 'D#', fb: 'E', gb: 'F#', ab: 'G#', bb: 'A#',
  };
  const raw = String(baseKey).trim();
  const lower = raw.toLowerCase();
  let norm = FLAT_MAP[lower];
  if (!norm) {
    // 去除重复 #（如 "C##"）并保持单个 #
    const letter = raw[0] || '';
    const hasSharp = /#/.test(raw.slice(1));
    norm = (letter.toUpperCase() + (hasSharp ? '#' : ''));
  }
  const idx = KEYS.indexOf(norm);
  if (idx < 0) return null;
  const steps = (((idx + Math.round(semitones)) % 12) + 12) % 12;
  return KEYS[steps];
}
