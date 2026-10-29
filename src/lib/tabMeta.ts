/** 详情页元数据工具：调弦/标题/难度描述等展示辅助（对齐原站格式） */

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

export function midiNoteName(midi: number): string {
  if (!Number.isFinite(midi)) return '';
  return NOTE_NAMES[((midi % 12) + 12) % 12];
}

/** 调弦文本（MIDI 号逗号串）→ ①=E ②=B ③=G ④=D ⑤=A ⑥=E */
export function tuningDisplay(tuningText: string | null | undefined): string {
  if (!tuningText) return '-';
  const notes = tuningText.split(',').map((v) => midiNoteName(Number(v))).filter(Boolean);
  if (notes.length === 0) return '-';
  const cn = ['①', '②', '③', '④', '⑤', '⑥'];
  return notes.map((n, i) => `${cn[i] ?? i + 1}=${n}`).join(' ');
}

export function difficultyLabel(d: number | null | undefined): string {
  const m: Record<number, string> = { 1: '零基础', 2: '初级', 3: '中级', 4: '高级', 5: '专业' };
  return d ? (m[d] ?? '') : '';
}

export const FORM_LABELS: Record<number, string> = { 1: '弹唱', 2: '指弹', 3: '和弦', 4: '六线', 7: '六线' };

/** 原站标题格式：{title}{乐器}_{artist}_{key}调_{难度}{类型}谱_高清{类型}谱 */
export function tabTitle(t: { title: string; artist?: string | null; key?: string | null; difficulty?: number | null; sheetForm?: number | null; category?: string | null }): string {
  const inst = t.category === 'ukulele' ? '尤克里里' : '吉他';
  const diff = difficultyLabel(t.difficulty);
  const form = FORM_LABELS[t.sheetForm ?? 0] ?? '';
  const formFull = form ? form + '谱' : '谱';
  const diffForm = diff && form ? diff + form : '';
  const parts = [
    `${t.title}${inst}`,
    t.artist ?? '',
    t.key ? `${t.key}调` : '',
    diffForm ? `${diffForm}谱` : '',
    formFull ? `高清${formFull}` : '',
  ].filter(Boolean);
  return parts.join('_');
}

/** 难度描述（数据无 description 时的通用文案） */
export function difficultyBlurb(t: { difficulty?: number | null; sheetForm?: number | null; category?: string | null }): string {
  const diff = difficultyLabel(t.difficulty);
  const form = FORM_LABELS[t.sheetForm ?? 0] ?? '';
  const inst = t.category === 'ukulele' ? '尤克里里' : '吉他';
  if (!diff) return `${inst}${form ? form + '谱' : '曲谱'}，适合吉他爱好者学习弹唱`;
  const map: Record<string, string> = {
    零基础: '适合完全没接触过吉他的初学者，和弦简单、节奏平稳，容易上手。',
    初级: '节奏简单易上手，适合刚入门、正在积累曲库的吉他爱好者。',
    中级: '节奏与和弦有一定变化，适合有一定基础的练习者。',
    高级: '指法与节奏较复杂，适合中高级进阶练习。',
    专业: '编配完整、难度较高，适合专业水平的演奏者。',
  };
  return `${diff}${form ? form + '谱' : '曲谱'}，${map[diff] ?? '适合对应水平的练习者。'}`;
}
