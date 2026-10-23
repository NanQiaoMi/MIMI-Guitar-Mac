<script lang="ts">
  import type { DurationValue } from '../../lib/studio/studioScoreModel';

  let {
    currentDuration = 4,
    hasDot = false,
    hasTriplet = false,
    isRest = false,
    isChordMode = false,
    activeTechniques = {},
    onSetDuration,
    onToggleDot,
    onToggleTriplet,
    onToggleRest,
    onToggleChordMode,
    onToggleTechnique,
    onInsertBeat,
    onDeleteBeat,
    onInsertBar,
    onDuplicateBar,
    onDeleteBar,
    onToggleRepeat,
    onSetSection,
  }: {
    currentDuration: DurationValue;
    hasDot: boolean;
    hasTriplet: boolean;
    isRest: boolean;
    isChordMode?: boolean;
    activeTechniques: Record<string, boolean>;
    onSetDuration?: (dur: DurationValue) => void;
    onToggleDot?: () => void;
    onToggleTriplet?: () => void;
    onToggleRest?: () => void;
    onToggleChordMode?: () => void;
    onToggleTechnique?: (tech: string) => void;
    onInsertBeat?: () => void;
    onDeleteBeat?: () => void;
    onInsertBar?: () => void;
    onDuplicateBar?: () => void;
    onDeleteBar?: () => void;
    onToggleRepeat?: (type: 'start' | 'end') => void;
    onSetSection?: (sec: string) => void;
  } = $props();

  const DURATIONS: Array<{ dur: DurationValue; label: string; icon: string; key: string }> = [
    { dur: 1, label: '全音符', icon: '𝅝', key: 'Alt+1' },
    { dur: 2, label: '二分', icon: '𝅗𝅥', key: 'Alt+2' },
    { dur: 4, label: '四分', icon: '𝅘𝅥', key: 'Alt+3' },
    { dur: 8, label: '八分', icon: '𝅘𝅥𝅮', key: 'Alt+4' },
    { dur: 16, label: '十六分', icon: '𝅘𝅥𝅯', key: 'Alt+5' },
    { dur: 32, label: '三十二分', icon: '𝅘𝅥𝅰', key: 'Alt+6' },
  ];

  const TECHNIQUES = [
    { id: 'tie', label: '延音线 (Tie)', shortcut: 'L', symbol: '⌒' },
    { id: 'hammerPull', label: '击/勾弦 (H/P)', shortcut: 'H', symbol: 'H/P' },
    { id: 'slide', label: '滑音 (Slide)', shortcut: 'S', symbol: 'sl.' },
    { id: 'bend', label: '推弦 (Bend)', shortcut: 'B', symbol: '↗' },
    { id: 'harmonic', label: '自然泛音 (Harm)', shortcut: 'N', symbol: '◆' },
    { id: 'palmMute', label: '闷音 (P.M.)', shortcut: 'P', symbol: 'P.M.' },
    { id: 'dead', label: '死音 (Dead)', shortcut: 'X', symbol: '✕' },
    { id: 'vibrato', label: '颤音揉弦 (Vib)', shortcut: 'V', symbol: '～' },
  ];
</script>

<div class="w-full bg-[#f5efe6] border-y border-[#e2d7c5] py-2 px-4 sm:px-8 flex flex-wrap items-center justify-between gap-3 text-[#2c2825] select-none shadow-2xs">
  <!-- 左侧：音符时值与节奏选择 -->
  <div class="flex min-w-0 max-w-full items-center gap-1.5 flex-wrap">
    <span class="text-[11px] font-serif font-bold text-[#705c42] mr-1 hidden sm:inline">时值:</span>
    <div class="flex max-w-full flex-wrap items-center bg-[#ede5d8]/90 p-1 rounded-xl border border-[#dfd6c7] gap-1 shadow-2xs">
      {#each DURATIONS as d}
        <button
          type="button"
          onclick={() => onSetDuration?.(d.dur)}
          aria-pressed={currentDuration === d.dur}
          aria-label={d.label}
          class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-mono font-bold transition-colors flex items-center justify-center gap-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {currentDuration === d.dur ? 'bg-[#2c2825] text-[#fbfaf7] shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/70 hover:text-[#2c2825]'}"
          title={`${d.label} (快捷键 ${d.key})`}
        >
          <span class="text-sm leading-none">{d.icon}</span>
          <span class="text-[10px] hidden md:inline font-serif">{d.label}</span>
        </button>
      {/each}
    </div>

    <!-- 附点 / 三连音 / 休止符 -->
    <div class="flex items-center bg-[#ede5d8]/90 p-1 rounded-xl border border-[#dfd6c7] gap-1 ml-1 shadow-2xs">
      <button
        type="button"
        onclick={onToggleDot}
        aria-pressed={hasDot}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {hasDot ? 'bg-[#2c2825] text-[#fbfaf7] shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/70'}"
        title="附点音符 (快捷键 .)"
      >
        · 附点
      </button>
      <button
        type="button"
        onclick={onToggleTriplet}
        aria-pressed={hasTriplet}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {hasTriplet ? 'bg-[#2c2825] text-[#fbfaf7] shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/70'}"
        title="三连音 (快捷键 /)"
      >
        3 连音
      </button>
      <button
        type="button"
        onclick={onToggleRest}
        aria-pressed={isRest}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {isRest ? 'bg-[#c84b31] text-[#ffffff] shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/70'}"
        title="切换休止符 (快捷键 R)"
      >
        𝄽 休止
      </button>
    </div>

    <!-- 拍位增删与录入模式 -->
    <div class="flex items-center bg-[#ede5d8]/90 p-1 rounded-xl border border-[#dfd6c7] gap-1 shadow-2xs">
      <button
        type="button"
        onclick={onInsertBeat}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif font-bold text-[#966b1a] hover:bg-[#ffffff]/80 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        title="在当前拍后插入一个空白拍"
      >
        + 插拍
      </button>
      <button
        type="button"
        onclick={onDeleteBeat}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif text-[#c84b31] hover:bg-[#c84b31]/15 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        title="删除当前拍"
      >
        - 删拍
      </button>
      <div class="w-px h-3.5 bg-[#d8cbba] mx-0.5"></div>
      <button
        type="button"
        onclick={onToggleChordMode}
        aria-pressed={isChordMode}
        class="min-h-[44px] px-3 py-2 rounded-lg text-xs font-serif font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {isChordMode ? 'bg-[#966b1a] text-[#ffffff] shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/70'}"
        title="录入模式切换：和弦模式下输入品数不自动向后跳拍，方便在同一拍录入多弦组合音"
      >
        {isChordMode ? '🎹 和弦模式' : '🎵 单音步进'}
      </button>
    </div>
  </div>

  <!-- 中间：吉他演奏技巧工具箱 -->
  <div class="flex items-center gap-1 flex-wrap">
    <span class="text-[11px] font-serif font-bold text-[#705c42] mr-1 hidden lg:inline">技法:</span>
    <div class="flex items-center bg-[#ede5d8]/90 p-1 rounded-xl border border-[#dfd6c7] gap-1 flex-wrap shadow-2xs">
      {#each TECHNIQUES as tech}
        {@const active = !!activeTechniques[tech.id]}
        <button
          type="button"
          onclick={() => onToggleTechnique?.(tech.id)}
          aria-pressed={active}
          aria-label={`${tech.label} (${tech.shortcut})`}
          class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-[11px] font-mono font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {active ? 'bg-[#2c2825] text-[#fbfaf7] shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/70 hover:text-[#2c2825]'}"
          title={`${tech.label} (快捷键 ${tech.shortcut})`}
        >
          <span>{tech.symbol}</span>
          <span class="ml-0.5 hidden xl:inline text-[10px] opacity-70">{tech.shortcut}</span>
        </button>
      {/each}
    </div>
  </div>

  <!-- 右侧：小节与结构操作 -->
  <div class="flex min-w-0 max-w-full flex-wrap items-center gap-1.5">
    <div class="flex items-center bg-[#ede5d8]/90 p-1 rounded-xl border border-[#dfd6c7] gap-1 shadow-2xs">
      <button
        type="button"
        onclick={onInsertBar}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif font-bold text-[#966b1a] hover:bg-[#ffffff]/80 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        title="在当前位置插入空白小节 (快捷键 Insert)"
      >
        + 加小节
      </button>
      <button
        type="button"
        onclick={onDuplicateBar}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif text-[#705c42] hover:bg-[#ffffff]/80 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        title="复制当前小节"
      >
        📋 复制节
      </button>
      <button
        type="button"
        onclick={onDeleteBar}
        class="min-h-[44px] min-w-[44px] px-2.5 py-2 rounded-lg text-xs font-serif text-[#c84b31] hover:bg-[#c84b31]/15 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        title="删除当前小节"
      >
        🗑️ 删节
      </button>
    </div>

    <!-- 段落快速标记下拉 -->
    <select
      onchange={(e) => {
        const val = (e.currentTarget as HTMLSelectElement).value;
        if (val) onSetSection?.(val);
        (e.currentTarget as HTMLSelectElement).value = '';
      }}
      class="min-h-[44px] bg-[#ede5d8]/90 text-[#705c42] text-[11px] px-2.5 py-2 rounded-xl border border-[#dfd6c7] focus:border-[#c49a45] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] font-serif"
    >
      <option value="">🏷️ 段落标记...</option>
      <option value="前奏">前奏 (Intro)</option>
      <option value="主歌">主歌 (Verse)</option>
      <option value="副歌">副歌 (Chorus)</option>
      <option value="间奏">间奏 (Interlude)</option>
      <option value="Solo">吉他独奏 (Solo)</option>
      <option value="桥段">桥段 (Bridge)</option>
      <option value="尾奏">尾奏 (Outro)</option>
    </select>
  </div>
</div>
