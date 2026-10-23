export const STUDIO_SHORTCUT_CATEGORIES = [
  { id: 'all', label: '全部' },
  { id: 'edit', label: '编辑' },
  { id: 'rhythm', label: '节奏' },
  { id: 'technique', label: '技法' },
  { id: 'playback', label: '播放' },
  { id: 'project', label: '工程与草稿' },
] as const;

export type StudioShortcutCategory = (typeof STUDIO_SHORTCUT_CATEGORIES)[number]['id'];

export interface StudioShortcut {
  key: string;
  desc: string;
  category: Exclude<StudioShortcutCategory, 'all'>;
  keyCombos?: readonly string[];
  searchTerms?: string;
}

export const STUDIO_SHORTCUTS: readonly StudioShortcut[] = [
  { key: '0 ~ 9', desc: '输入品位；1/2 可继续输入第二位组成 10–24 品。0 是空弦', category: 'edit', searchTerms: 'fret 品位 空弦 0 1 2 3 4 5 6 7 8 9 10 11 12品 13 14 15 16 17 18 19 20 21 22 23 24' },
  { key: '↑ / ↓', desc: '在当前音轨琴弦之间移动，1 弦为高音弦', category: 'edit', searchTerms: '上下方向键 琴弦' },
  { key: '← / →', desc: '向前 / 向后移动一拍；末拍后会自动加小节', category: 'edit', searchTerms: '左右方向键 光标 拍位' },
  { key: 'Tab / Shift+Tab', desc: '在页面控件之间移动焦点，不执行谱面编辑', category: 'edit', keyCombos: ['Shift+Tab'], searchTerms: '焦点 导航 tab' },
  { key: 'Delete / Backspace', desc: '删除当前拍选中琴弦上的音符', category: 'edit', searchTerms: '删除 音符' },
  { key: 'Shift+Delete', desc: '删除当前拍', category: 'edit', keyCombos: ['Shift+Delete'], searchTerms: '删除 拍位' },
  { key: 'Insert / Shift+Insert', desc: '插入小节 / 在当前拍前插入一拍', category: 'edit', keyCombos: ['Shift+Insert'], searchTerms: '插入 小节 拍' },
  { key: 'Ctrl/Cmd + Z', desc: '撤销上一步操作', category: 'edit', keyCombos: ['Ctrl+Z', 'Cmd+Z'], searchTerms: 'Ctrl+Z Cmd+Z Command+Z Meta+Z MacCmd+Z ⌘Z undo 撤销' },
  { key: 'Shift + Ctrl/Cmd + Z', desc: '重做上一步撤销', category: 'edit', keyCombos: ['Ctrl+Shift+Z', 'Cmd+Shift+Z'], searchTerms: 'Ctrl+Shift+Z Shift+Ctrl+Z Cmd+Shift+Z Shift+Cmd+Z Command+Shift+Z Shift+Command+Z Meta+Shift+Z Shift+Meta+Z MacCmd+Shift+Z ⌘ShiftZ redo 重做' },
  { key: 'Ctrl/Cmd + Y', desc: '重做上一步撤销', category: 'edit', keyCombos: ['Ctrl+Y', 'Cmd+Y'], searchTerms: 'Ctrl+Y Cmd+Y Command+Y Meta+Y MacCmd+Y ⌘Y redo 重做' },
  { key: 'Alt+1…6', desc: '全、二、四、八、十六、三十二分音符', category: 'rhythm', keyCombos: ['Alt+1', 'Alt+2', 'Alt+3', 'Alt+4', 'Alt+5', 'Alt+6'], searchTerms: 'Alt+1 Alt+2 Alt+3 Alt+4 Alt+5 Alt+6 时值 音符 长短 duration' },
  { key: '. / 斜杠', desc: '切换附点 / 三连音', category: 'rhythm', searchTerms: '附点 三连音 dotted triplet' },
  { key: 'R', desc: '切换当前拍为休止符；0 仍表示空弦', category: 'rhythm', searchTerms: '休止符 rest' },
  { key: 'L', desc: '添加 / 取消 延音线 (Tie)', category: 'technique', searchTerms: '连音 tie' },
  { key: 'H', desc: '添加 / 取消 击勾弦 (Hammer-on / Pull-off)', category: 'technique', searchTerms: '击弦 勾弦 hammer pull off' },
  { key: 'S', desc: '添加 / 取消 滑音 (Slide)', category: 'technique', searchTerms: '滑音 slide' },
  { key: 'B', desc: '添加 / 取消 推弦 (Bend)', category: 'technique', searchTerms: '推弦 bend' },
  { key: 'N', desc: '添加 / 取消 泛音 (Harmonic)', category: 'technique', searchTerms: '泛音 harmonic' },
  { key: 'P', desc: '添加 / 取消 闷音 (Palm Mute)', category: 'technique', searchTerms: '闷音 palm mute' },
  { key: 'X', desc: '切换为死音/哑音 (Dead Note)', category: 'technique', searchTerms: '死音 哑音 dead note' },
  { key: 'V', desc: '添加 / 取消 颤音揉弦 (Vibrato)', category: 'technique', searchTerms: '颤音 揉弦 vibrato' },
  { key: 'Space (空格键)', desc: '播放 / 暂停乐谱原声试听', category: 'playback', searchTerms: '空格 space play pause 试听' },
  { key: 'Ctrl/Cmd + S', desc: '保存当前乐谱工程至本地草稿箱', category: 'project', keyCombos: ['Ctrl+S', 'Cmd+S'], searchTerms: 'Ctrl+S Cmd+S Command+S Meta+S MacCmd+S ⌘S save 保存 草稿 本地' },
];

type ShortcutModifier = 'alt' | 'cmd' | 'ctrl' | 'shift';

const MODIFIER_ALIASES: Record<string, ShortcutModifier[]> = {
  alt: ['alt'],
  option: ['alt'],
  cmd: ['cmd'],
  command: ['cmd'],
  meta: ['cmd'],
  maccmd: ['cmd'],
  ctrl: ['ctrl'],
  control: ['ctrl'],
  'ctrl/cmd': ['ctrl', 'cmd'],
  'cmd/ctrl': ['cmd', 'ctrl'],
  shift: ['shift'],
};

const COMPACT_MODIFIER_ALIASES = Object.keys(MODIFIER_ALIASES).sort((left, right) => right.length - left.length);

function splitCompactModifierToken(token: string): { modifiers: ShortcutModifier[][]; key: string } | null {
  let remainder = token;
  const modifiers: ShortcutModifier[][] = [];

  while (remainder) {
    const alias = COMPACT_MODIFIER_ALIASES.find(
      (candidate) => remainder.startsWith(candidate) && remainder.length > candidate.length,
    );
    if (!alias) break;
    modifiers.push(MODIFIER_ALIASES[alias]);
    remainder = remainder.slice(alias.length);
  }

  if (modifiers.length === 0 || !/^(?:[a-z0-9]|backspace|delete|insert|tab|space|escape|enter)$/u.test(remainder)) {
    return null;
  }
  return { modifiers, key: remainder };
}

function parseShortcutComboQuery(query: string): string[] | null {
  const tokens = query
    .normalize('NFKC')
    .replace(/⌘/gu, ' cmd ')
    .replace(/\s*\/\s*/gu, '/')
    .trim()
    .split(/[+\s]+/u)
    .filter(Boolean);
  const modifierOptions: ShortcutModifier[][] = [];
  const keyTokens: string[] = [];

  for (const token of tokens) {
    const normalizedToken = token.toLocaleLowerCase('en-US');
    const modifiers = MODIFIER_ALIASES[normalizedToken];
    if (modifiers) modifierOptions.push(modifiers);
    else {
      const compactToken = splitCompactModifierToken(normalizedToken);
      if (compactToken) {
        modifierOptions.push(...compactToken.modifiers);
        keyTokens.push(compactToken.key);
      } else keyTokens.push(normalizedToken);
    }
  }

  if (modifierOptions.length === 0 || keyTokens.length !== 1) return null;

  let variants: ShortcutModifier[][] = [[]];
  for (const options of modifierOptions) {
    variants = variants.flatMap((variant) =>
      options.map((modifier) => (variant.includes(modifier) ? variant : [...variant, modifier])),
    );
  }

  const normalizedKey = keyTokens[0];
  return [...new Set(variants.map((variant) => `${[...variant].sort().join('+')}+${normalizedKey}`))];
}

function normalizeSearchText(value: string): string {
  return value.normalize('NFKC').replace(/⌘/gu, 'cmd').toLocaleLowerCase('zh-CN').replace(/[\s\p{P}\p{S}]/gu, '');
}

export function filterStudioShortcuts(
  query: string,
  category: StudioShortcutCategory = 'all',
): StudioShortcut[] {
  const shortcutComboQuery = parseShortcutComboQuery(query);
  const normalizedQuery = normalizeSearchText(query);
  return STUDIO_SHORTCUTS.filter((shortcut) => {
    if (category !== 'all' && shortcut.category !== category) return false;
    if (!normalizedQuery) return true;
    if (shortcutComboQuery) {
      return (shortcut.keyCombos ?? []).some((combo) =>
        parseShortcutComboQuery(combo)?.some((parsedCombo) => shortcutComboQuery.includes(parsedCombo)),
      );
    }
    const categoryLabel = STUDIO_SHORTCUT_CATEGORIES.find((item) => item.id === shortcut.category)?.label ?? '';
    const searchableText = normalizeSearchText(
      `${shortcut.key} ${shortcut.desc} ${shortcut.searchTerms ?? ''} ${categoryLabel}`,
    );
    return searchableText.includes(normalizedQuery);
  });
}
