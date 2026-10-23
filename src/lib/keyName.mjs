// 调性换算纯函数（供 ScorePlayer 组件与 node --test 单测共用，纯 JS 以便 .mjs 直接导入）

/** AlphaTab KeySignature 枚举 → 大调调名（0=C, 1=G, 2=D... 升号；-1=F, -2=Bb... 降号） */
export const MAJOR_KEYS = {
  0: 'C', 1: 'G', 2: 'D', 3: 'A', 4: 'E', 5: 'B', 6: 'F#', 7: 'C#',
  '-1': 'F', '-2': 'Bb', '-3': 'Eb', '-4': 'Ab', '-5': 'Db', '-6': 'Gb', '-7': 'Cb',
};

const PC_SHARP = {
  C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, Fb: 4,
  F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11, Cb: 11,
};
const NAME_BY_PC = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/** 大调名 → 关系小调名（大调根音降 3 个半音；结果统一用升号记法） */
export function relativeMinor(majorName) {
  const pc = PC_SHARP[majorName];
  if (pc == null) return null;
  return NAME_BY_PC[(((pc - 3) % 12) + 12) % 12];
}

/**
 * AlphaTab KeySignature 枚举 + KeySignatureType → 调名。
 * type: 0=Major（返回大调名，如 G），1=Minor（返回关系小调名，如 Em）。
 */
export function keySignatureName(sig, type = 0) {
  const maj = MAJOR_KEYS[sig];
  if (!maj) return null;
  return type === 1 ? relativeMinor(maj) : maj;
}
