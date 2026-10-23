<script lang="ts">
  import { onMount } from 'svelte';
  import {
    acquireGuitarAudioSession,
    playProgramChordStrum,
    setGlobalProgram,
    getGlobalInstrumentSelection,
    type GuitarAudioSession,
  } from '../../lib/guitarSound.ts';
  import {
    ALL_GM_INSTRUMENTS,
    GM_CATEGORIES,
    getInstrumentByProgram,
    type GMInstrumentInfo,
  } from '../../lib/gmInstruments.ts';

  export let tab: {
    id: string;
    title: string;
    artist?: string;
    category?: 'guitar' | 'ukulele';
    key?: string;
    difficulty?: number;
    sheetForm?: number;
    bpm?: number;
    timeSig?: string;
    capo?: number;
    tuning?: string;
    tuningText?: string;
    heat?: number;
    uploader?: string;
    publishDate?: string | Date;
    tags?: string;
  };

  // 难度等级映射
  const diffLabels = ['', '零基础', '初级', '中级', '高级', '专业'];
  const difficulty = tab.difficulty ? diffLabels[tab.difficulty] ?? '初级' : '初级';
  const starCount = tab.difficulty ? Math.min(Math.max(tab.difficulty, 1), 5) : 2;

  // 热度格式化
  const heat = tab.heat ?? 9800;
  const heatText = heat >= 10000 ? (heat / 10000).toFixed(1) + '万' : String(heat);

  // 标准调弦展示
  const tuningStr = tab.category === 'ukulele' ? 'G - C - E - A (标准音)' : 'E - A - D - G - B - E (标准音)';
  const uploaderName = tab.uploader || 'MIMI 乐谱工坊 · 认证编配';

  // 解析标签
  let tagList: string[] = [];
  try {
    const parsed = typeof tab.tags === 'string' ? JSON.parse(tab.tags) : tab.tags;
    if (Array.isArray(parsed)) tagList = parsed;
  } catch {
    tagList = ['民谣', '流行', '经典编配'];
  }
  if (tagList.length === 0) tagList = ['经典', '流行', '吉他弹唱'];

  // 根据调性匹配推荐的核心和弦与和弦图字典（吉他 6 弦 5 品模型）
  interface ChordDef {
    name: string;
    degree: string;
    frets: number[];
    fingers?: number[];
    barre?: { fret: number; fromStr: number; toStr: number };
    audioNotes: number[];
  }

  const CHORD_DATABASE: Record<string, ChordDef[]> = {
    G: [
      { name: 'G', degree: 'I 级主和弦', frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3], audioNotes: [43, 47, 50, 55, 59, 67] },
      { name: 'Em7', degree: 'vi 级副和弦', frets: [0, 2, 2, 0, 3, 3], fingers: [0, 1, 2, 0, 3, 4], audioNotes: [40, 47, 52, 55, 59, 64] },
      { name: 'Cadd9', degree: 'IV 级色彩和弦', frets: [-1, 3, 2, 0, 3, 3], fingers: [-1, 2, 1, 0, 3, 4], audioNotes: [48, 52, 55, 62, 67] },
      { name: 'D', degree: 'V 级属和弦', frets: [-1, -1, 0, 2, 3, 2], fingers: [-1, -1, 0, 1, 3, 2], audioNotes: [50, 57, 62, 66] },
      { name: 'Am7', degree: 'ii 级和弦', frets: [-1, 0, 2, 0, 1, 0], fingers: [-1, 0, 2, 0, 1, 0], audioNotes: [45, 52, 55, 60, 64] },
      { name: 'Bm7', degree: 'iii 级和弦', frets: [-1, 2, 4, 2, 3, 2], fingers: [-1, 1, 3, 1, 2, 1], barre: { fret: 2, fromStr: 2, toStr: 6 }, audioNotes: [47, 54, 57, 62, 66] },
    ],
    C: [
      { name: 'C', degree: 'I 级主和弦', frets: [-1, 3, 2, 0, 1, 0], fingers: [-1, 3, 2, 0, 1, 0], audioNotes: [48, 52, 55, 60, 64] },
      { name: 'Am', degree: 'vi 级副和弦', frets: [-1, 0, 2, 2, 1, 0], fingers: [-1, 0, 2, 3, 1, 0], audioNotes: [45, 52, 57, 60, 64] },
      { name: 'F', degree: 'IV 级大横按', frets: [1, 3, 3, 2, 1, 1], fingers: [1, 3, 4, 2, 1, 1], barre: { fret: 1, fromStr: 1, toStr: 6 }, audioNotes: [41, 48, 53, 57, 60, 65] },
      { name: 'G', degree: 'V 级属和弦', frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3], audioNotes: [43, 47, 50, 55, 59, 67] },
      { name: 'Dm', degree: 'ii 级和弦', frets: [-1, -1, 0, 2, 3, 1], fingers: [-1, -1, 0, 2, 3, 1], audioNotes: [50, 57, 62, 65] },
      { name: 'Em', degree: 'iii 级和弦', frets: [0, 2, 2, 0, 0, 0], fingers: [0, 1, 2, 0, 0, 0], audioNotes: [40, 47, 52, 55, 59, 64] },
    ],
    D: [
      { name: 'D', degree: 'I 级主和弦', frets: [-1, -1, 0, 2, 3, 2], fingers: [-1, -1, 0, 1, 3, 2], audioNotes: [50, 57, 62, 66] },
      { name: 'Bm', degree: 'vi 级和弦', frets: [-1, 2, 4, 4, 3, 2], fingers: [-1, 1, 3, 4, 2, 1], barre: { fret: 2, fromStr: 2, toStr: 6 }, audioNotes: [47, 54, 59, 62, 66] },
      { name: 'G', degree: 'IV 级和弦', frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3], audioNotes: [43, 47, 50, 55, 59, 67] },
      { name: 'A', degree: 'V 级属和弦', frets: [-1, 0, 2, 2, 2, 0], fingers: [-1, 0, 1, 2, 3, 0], audioNotes: [45, 52, 57, 61, 64] },
      { name: 'Em', degree: 'ii 级和弦', frets: [0, 2, 2, 0, 0, 0], fingers: [0, 1, 2, 0, 0, 0], audioNotes: [40, 47, 52, 55, 59, 64] },
      { name: 'F#m', degree: 'iii 级和弦', frets: [2, 4, 4, 2, 2, 2], fingers: [1, 3, 4, 1, 1, 1], barre: { fret: 2, fromStr: 1, toStr: 6 }, audioNotes: [42, 49, 54, 57, 61, 66] },
    ],
    F: [
      { name: 'F', degree: 'I 级主和弦', frets: [1, 3, 3, 2, 1, 1], fingers: [1, 3, 4, 2, 1, 1], barre: { fret: 1, fromStr: 1, toStr: 6 }, audioNotes: [41, 48, 53, 57, 60, 65] },
      { name: 'Dm', degree: 'vi 级副和弦', frets: [-1, -1, 0, 2, 3, 1], fingers: [-1, -1, 0, 2, 3, 1], audioNotes: [50, 57, 62, 65] },
      { name: 'Bb', degree: 'IV 级横按', frets: [-1, 1, 3, 3, 3, 1], fingers: [-1, 1, 2, 3, 4, 1], barre: { fret: 1, fromStr: 2, toStr: 6 }, audioNotes: [46, 53, 58, 62, 65] },
      { name: 'C', degree: 'V 级属和弦', frets: [-1, 3, 2, 0, 1, 0], fingers: [-1, 3, 2, 0, 1, 0], audioNotes: [48, 52, 55, 60, 64] },
      { name: 'Gm', degree: 'ii 级和弦', frets: [3, 5, 5, 3, 3, 3], fingers: [1, 3, 4, 1, 1, 1], barre: { fret: 3, fromStr: 1, toStr: 6 }, audioNotes: [43, 50, 55, 58, 62, 67] },
      { name: 'Am', degree: 'iii 级和弦', frets: [-1, 0, 2, 2, 1, 0], fingers: [-1, 0, 2, 3, 1, 0], audioNotes: [45, 52, 57, 60, 64] },
    ],
    A: [
      { name: 'A', degree: 'I 级主和弦', frets: [-1, 0, 2, 2, 2, 0], fingers: [-1, 0, 1, 2, 3, 0], audioNotes: [45, 52, 57, 61, 64] },
      { name: 'F#m', degree: 'vi 级和弦', frets: [2, 4, 4, 2, 2, 2], fingers: [1, 3, 4, 1, 1, 1], barre: { fret: 2, fromStr: 1, toStr: 6 }, audioNotes: [42, 49, 54, 57, 61, 66] },
      { name: 'D', degree: 'IV 级和弦', frets: [-1, -1, 0, 2, 3, 2], fingers: [-1, -1, 0, 1, 3, 2], audioNotes: [50, 57, 62, 66] },
      { name: 'E', degree: 'V 级属和弦', frets: [0, 2, 2, 1, 0, 0], fingers: [0, 2, 3, 1, 0, 0], audioNotes: [40, 47, 52, 56, 59, 64] },
      { name: 'Bm', degree: 'ii 级和弦', frets: [-1, 2, 4, 4, 3, 2], fingers: [-1, 1, 3, 4, 2, 1], barre: { fret: 2, fromStr: 2, toStr: 6 }, audioNotes: [47, 54, 59, 62, 66] },
      { name: 'C#m', degree: 'iii 级和弦', frets: [-1, 4, 6, 6, 5, 4], fingers: [-1, 1, 3, 4, 2, 1], barre: { fret: 4, fromStr: 2, toStr: 6 }, audioNotes: [49, 56, 61, 64, 68] },
    ],
  };

  const currentKey = (tab.key || 'G').toUpperCase().trim();
  const chordList: ChordDef[] = CHORD_DATABASE[currentKey] || CHORD_DATABASE['G'];

  let activeChord: ChordDef | null = chordList[0] || null;
  let isPlayingStrum = false;

  // Do not inherit a page-global selection from another score. The real
  // primary-track choice arrives from this score's player when it is ready.
  let selectedProgram = 25;
  let selectedFlavor: 'gm' | 'ukulele' = 'gm';
  let selectionIsSource = false;
  let selectionKnown = false;
  let activeInstrument: GMInstrumentInfo = getInstrumentByProgram(selectedProgram);
  let strumDir: 'down' | 'up' = 'down';
  let auditionError = '';
  let activeStrumSession: GuitarAudioSession | null = null;
  let strumGeneration = 0;

  // 128 款全乐器库弹窗开关与搜索过滤
  let isModalOpen = false;
  let selectedCategoryTab = '全部';
  let instrumentSearchKeyword = '';

  // 常用快捷乐器列表
  const QUICK_INSTRUMENTS: GMInstrumentInfo[] = [
    getInstrumentByProgram(25), // 民谣钢弦木吉他
    getInstrumentByProgram(24), // 古典尼龙吉他
    getInstrumentByProgram(27), // 清音电吉他
    getInstrumentByProgram(29), // 过载摇滚电吉他
    getInstrumentByProgram(105), // 班卓琴
    getInstrumentByProgram(0), // 原声大钢琴
    getInstrumentByProgram(33), // 电贝斯
    getInstrumentByProgram(48), // 弦乐合奏
    getInstrumentByProgram(107), // 古筝
  ];

  function scoreIdMatches(candidate: unknown): boolean {
    if (typeof candidate !== 'string' || candidate.length === 0) return false;
    return candidate === tab.id || candidate === `catalog:${tab.id}`;
  }

  function cancelCurrentStrum(): void {
    strumGeneration++;
    activeStrumSession?.release();
    activeStrumSession = null;
    isPlayingStrum = false;
  }

  function applyInstrumentSelection(selection: {
    program: number;
    flavor?: 'gm' | 'ukulele';
    instrumentOverride?: boolean;
  }): void {
    if (!Number.isSafeInteger(selection.program) || selection.program < 0 || selection.program > 127) return;
    cancelCurrentStrum();
    selectedProgram = selection.program;
    selectedFlavor = selection.flavor === 'ukulele' ? 'ukulele' : 'gm';
    selectionIsSource = selection.instrumentOverride !== true;
    selectionKnown = true;
    activeInstrument = getInstrumentByProgram(selectedProgram);
  }

  function auditionSelectionLabel(): string {
    if (!selectionKnown) return '等待主音轨音色';
    if (selectionIsSource && selectedFlavor === 'ukulele') {
      const preset = selectedProgram === 0 ? '原声' : selectedProgram === 24 ? '尼龙弦' : '钢弦';
      return `原谱 · 尤克里里（${preset}）`;
    }
    return `${selectionIsSource ? '原谱' : '用户选择'} · ${activeInstrument.name} (Program ${selectedProgram})`;
  }

  onMount(() => {
    const acceptSnapshot = (selection: ReturnType<typeof getGlobalInstrumentSelection>) => {
      if (!scoreIdMatches(selection.scoreId)) return;
      if (selection.source !== 'player' && selection.source !== 'tab-metadata') return;
      applyInstrumentSelection(selection);
    };

    acceptSnapshot(getGlobalInstrumentSelection());
    const onInstrChange = (event: Event) => {
      const detail = (event as CustomEvent).detail;
      if (!scoreIdMatches(detail?.scoreId)) return;
      if (detail?.source !== 'player' && detail?.source !== 'tab-metadata') return;
      applyInstrumentSelection(detail);
    };
    window.addEventListener('mimi:instrument-change', onInstrChange);
    return () => {
      window.removeEventListener('mimi:instrument-change', onInstrChange);
      cancelCurrentStrum();
    };
  });

  async function handleProgramSelect(prog: number) {
    if (!Number.isSafeInteger(prog) || prog < 0 || prog > 127) return;
    cancelCurrentStrum();
    selectedProgram = prog;
    selectedFlavor = 'gm';
    selectionIsSource = false;
    selectionKnown = true;
    activeInstrument = getInstrumentByProgram(prog);
    auditionError = '';
    setGlobalProgram(prog, {
      source: 'tab-metadata',
      broadcast: true,
      flavor: 'gm',
      instrumentOverride: true,
      scoreId: tab.id,
    });
    isModalOpen = false;
    if (activeChord) {
      await playChordStrum(activeChord);
    }
  }

  // 播放和弦扫弦试听
  async function playChordStrum(chord: ChordDef) {
    if (!selectionKnown) {
      auditionError = '请等待乐谱主音轨音色就绪，或先明确选择一个 GM 音色。';
      return;
    }
    cancelCurrentStrum();
    const generation = strumGeneration;
    const program = selectedProgram;
    const flavor = selectedFlavor;
    activeChord = chord;
    let session: GuitarAudioSession | null = null;
    try {
      auditionError = '';
      session = await acquireGuitarAudioSession();
      if (generation !== strumGeneration || !session.active) {
        session.release();
        return;
      }
      activeStrumSession = session;
      isPlayingStrum = true;
      await playProgramChordStrum(chord.audioNotes, strumDir, program, session, flavor);
    } catch (error) {
      if (generation === strumGeneration && !(error instanceof DOMException && error.name === 'AbortError')) {
        auditionError = error instanceof Error ? error.message : '和弦试听音源加载失败。';
      }
    } finally {
      if (activeStrumSession === session) activeStrumSession = null;
      session?.release();
      if (generation === strumGeneration) isPlayingStrum = false;
    }
  }

  // 过滤全部 128 款乐器：只有当抽屉打开时才计算，首屏加载时 0 额外开销
  $: filteredInstruments = isModalOpen
    ? ALL_GM_INSTRUMENTS.filter((inst) => {
        const matchCategory = selectedCategoryTab === '全部' || inst.category === selectedCategoryTab;
        const kw = instrumentSearchKeyword.trim().toLowerCase();
        const matchSearch =
          !kw ||
          inst.name.toLowerCase().includes(kw) ||
          inst.enName.toLowerCase().includes(kw) ||
          String(inst.program).includes(kw);
        return matchCategory && matchSearch;
      })
    : [];

  // 格式化发布日期
  let pubDateStr = '2026-01-15';
  if (tab.publishDate) {
    if (typeof tab.publishDate === 'string') {
      pubDateStr = tab.publishDate.slice(0, 10);
    } else if (tab.publishDate instanceof Date) {
      pubDateStr = tab.publishDate.toISOString().slice(0, 10);
    }
  }
</script>

<div class="space-y-8 mt-10">
  <!-- 1. 温润棉纸工坊规格参数卡片 (Artisanal Parchment Specs Deck) -->
  <section class="rounded-3xl border border-[#e8e2d4] bg-[#fbf9f4] p-6 sm:p-8 shadow-[0_4px_24px_rgba(76,59,43,0.04)] relative overflow-hidden">
    <!-- 纸纹与装饰性黄铜光晕背景 -->
    <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,rgba(212,175,55,0.06),transparent_60%)]" />
    <div class="pointer-events-none absolute -right-6 -bottom-6 w-32 h-32 rounded-full border border-[#e3d7bf]/40 opacity-40" />

    <!-- 顶部工坊抬头与朱砂认证印章 -->
    <div class="flex items-center justify-between pb-5 mb-6 border-b border-[#e8e2d4]/80">
      <div class="flex items-center gap-3">
        <div class="w-8 h-8 rounded-full bg-[#eee7d7] border border-[#d8ccb4] flex items-center justify-center text-[#705c42] shadow-xs">
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
            <path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
          </svg>
        </div>
        <div>
          <h3 class="font-display text-base sm:text-lg font-semibold text-[#2c241b] tracking-wide">曲谱规格与乐理参数</h3>
          <p class="text-xs text-[#8c7b68]">Artisanal Acoustic Manuscript Specs</p>
        </div>
      </div>

      <!-- 制谱作者朱砂印章 -->
      <div class="flex items-center gap-2">
        <div class="px-2.5 py-1 rounded-lg border border-[#c84b31]/40 bg-[#c84b31]/5 text-[#c84b31] text-xs font-serif font-medium tracking-widest flex items-center gap-1.5 shadow-2xs">
          <span class="w-1.5 h-1.5 rounded-full bg-[#c84b31] animate-pulse" />
          <span>工坊定稿</span>
        </div>
      </div>
    </div>

    <!-- 10 项精雕细琢的工坊参数网格 -->
    <dl class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3.5 sm:gap-4">
      <!-- 调性 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>调性 / 调式</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">KEY</span>
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1 flex items-baseline gap-1.5">
          <span>{tab.key ?? 'G'} 调</span>
          <span class="text-xs font-normal text-[#8c7b68]">自然大调</span>
        </dd>
      </div>

      <!-- 难度 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>难度评级</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">LV</span>
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1 flex items-center gap-2">
          <span>{difficulty}</span>
          <span class="flex gap-0.5 text-xs text-[#c49a45]">
            {#each Array(5) as _, i}
              <span class={i < starCount ? 'opacity-100' : 'opacity-25'}>★</span>
            {/each}
          </span>
        </dd>
      </div>

      <!-- 速度 BPM (动态律动脉冲) -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>速度 (BPM)</span>
          <span class="w-2 h-2 rounded-full bg-[#10b981] animate-ping" />
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1 flex items-baseline gap-1">
          <span>{tab.bpm || 96}</span>
          <span class="text-xs font-normal text-[#8c7b68]">拍/分</span>
        </dd>
      </div>

      <!-- 拍号 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>节拍拍号</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">TIME</span>
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1">
          {tab.timeSig || '4/4 拍'}
        </dd>
      </div>

      <!-- 变调夹 Capo -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>变调夹 CAPO</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">CAPO</span>
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1">
          {tab.capo ? `夹 ${tab.capo} 品` : '原调 (不夹)'}
        </dd>
      </div>

      <!-- 调弦体系 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>弦位音高</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">TUNING</span>
        </dt>
        <dd class="text-[#2c241b] font-mono text-xs font-semibold mt-1 truncate" title={tuningStr}>
          {tuningStr}
        </dd>
      </div>

      <!-- 乐谱热度 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>研习热度</span>
          <span class="text-[#c84b31]">🔥</span>
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1 flex items-baseline gap-1">
          <span>{heatText}</span>
          <span class="text-xs font-normal text-[#8c7b68]">次弹奏</span>
        </dd>
      </div>

      <!-- 上传编配 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>编配作者</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">EDITOR</span>
        </dt>
        <dd class="text-[#2c241b] font-medium text-xs mt-1 truncate" title={uploaderName}>
          {uploaderName}
        </dd>
      </div>

      <!-- 发布日期 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>发布日期</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">DATE</span>
        </dt>
        <dd class="text-[#2c241b] font-mono text-xs font-semibold mt-1">
          {pubDateStr}
        </dd>
      </div>

      <!-- 调音模式 -->
      <div class="rounded-2xl border border-[#e8e2d4] bg-white/70 backdrop-blur-xs p-3.5 transition-all duration-200 hover:border-[#d4af37]/60 hover:shadow-xs group">
        <dt class="text-[11px] font-medium tracking-wider text-[#8c7b68] uppercase flex items-center justify-between">
          <span>调音模式</span>
          <span class="text-[10px] text-[#b0a18f] font-mono">MODE</span>
        </dt>
        <dd class="text-[#2c241b] font-display text-base font-semibold mt-1">
          {tab.tuning || 'Standard (标准)'}
        </dd>
      </div>
    </dl>
  </section>

  <!-- 2. 专业和弦乐理大赏与全 128 款乐器音色库 (All 128 GM Instruments Chord Palette) -->
  <section class="rounded-3xl border border-[#e8e2d4] bg-[#fbf9f4] p-6 sm:p-8 shadow-[0_4px_24px_rgba(76,59,43,0.04)] relative">
    <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-4 pb-5 mb-6 border-b border-[#e8e2d4]/80">
      <div>
        <div class="flex items-center gap-2">
          <span class="text-[#c49a45] text-lg">✦</span>
          <h3 class="font-display text-base sm:text-lg font-semibold text-[#2c241b]">曲目搭配和弦与指法图鉴</h3>
        </div>
        <p class="text-xs text-[#8c7b68] mt-0.5">
          和弦试听音色：<span class="font-semibold text-[#2c241b]">{auditionSelectionLabel()}</span> · 图鉴试听只作用于主音轨，其它音轨保留原谱音色
        </p>
      </div>

      <!-- 乐器音色选择器工具栏 (常用推荐 + 更多全库按钮) -->
      <div class="flex flex-wrap items-center gap-2">
        <div class="flex flex-wrap items-center gap-1 p-1 rounded-full bg-[#eee7d8] border border-[#d8ccb4] shadow-3xs max-w-full">
          {#each QUICK_INSTRUMENTS as inst}
            <button
              type="button"
              on:click={() => handleProgramSelect(inst.program)}
              class="px-2.5 py-1 rounded-full text-xs font-serif font-medium transition-all duration-200 flex items-center gap-1 cursor-pointer {selectionKnown && selectedFlavor === 'gm' && selectedProgram === inst.program
                ? 'bg-[#2c241b] text-[#fffdfa] shadow-xs scale-102 font-bold'
                : 'text-[#705c42] hover:text-[#2c241b] hover:bg-white/60'}"
              title={`将主音轨试听切换为 ${inst.name}；其它音轨保留原谱音色`}
            >
              <span>{inst.icon}</span>
              <span class="hidden sm:inline">{inst.name.split(' ')[0]}</span>
            </button>
          {/each}

          <!-- 全部 128 款音色库弹窗触发按钮 -->
          <button
            type="button"
            on:click={() => (isModalOpen = true)}
            class="px-3 py-1 rounded-full text-xs font-serif font-medium bg-[#c49a45]/15 text-[#8f6d2b] border border-[#c49a45]/30 hover:bg-[#c49a45]/25 transition-all duration-200 flex items-center gap-1 cursor-pointer"
            title="浏览并选择全部 128 款 GM 乐器音色"
          >
            <span>🎼</span>
            <span>全部 128 款音色…</span>
          </button>
        </div>

        <!-- 扫弦方向切换 (下扫 / 上扫) -->
        <button
          type="button"
          on:click={() => { strumDir = strumDir === 'down' ? 'up' : 'down'; if (activeChord) playChordStrum(activeChord); }}
          disabled={!selectionKnown || isPlayingStrum}
          class="flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-serif text-[#705c42] bg-[#eee7d8] border border-[#d8ccb4] hover:bg-white/80 transition-colors shadow-3xs cursor-pointer shrink-0"
          title="点击切换扫弦方向"
        >
          <span>{strumDir === 'down' ? '↓ 下扫' : '↑ 上扫'}</span>
        </button>
      </div>
    </div>

    {#if auditionError}
      <div role="alert" class="mb-4 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-800">{auditionError}</div>
    {/if}

    <!-- 和弦卡片矩阵 -->
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-3.5">
      {#each chordList as chord}
        <button
          type="button"
          on:click={() => playChordStrum(chord)}
          disabled={!selectionKnown || isPlayingStrum}
          class="relative flex flex-col items-center p-3 rounded-2xl border transition-all duration-200 text-center cursor-pointer group {activeChord?.name === chord.name
            ? 'border-[#c49a45] bg-gradient-to-b from-[#fffcf7] to-[#fbf5e8] shadow-sm ring-2 ring-[#c49a45]/30 -translate-y-1'
            : 'border-[#e8e2d4] bg-white/80 hover:border-[#c49a45]/60 hover:bg-white hover:-translate-y-0.5 shadow-2xs'}"
        >
          <!-- 和弦名称 & 级数 -->
          <span class="font-display text-base font-bold text-[#2c241b] group-hover:text-[#966b26]">
            {chord.name}
          </span>
          <span class="text-[10px] text-[#8c7b68] font-serif mt-0.5">
            {chord.degree}
          </span>

          <!-- 真实 SVG 六品和弦图 -->
          <div class="w-24 h-24 my-2 flex items-center justify-center">
            <svg viewBox="0 0 100 110" class="w-full h-full">
              <!-- 琴枕 (Nut) -->
              <rect x="20" y="16" width="60" height="3" fill="#6d5843" rx="1.5" />

              <!-- 6 根琴弦 (垂直线，粗细按 6弦到1弦递减) -->
              {#each [20, 32, 44, 56, 68, 80] as x, i}
                <line
                  x1={x}
                  y1="18"
                  x2={x}
                  y2="98"
                  stroke="#8c7b68"
                  stroke-width={2.2 - i * 0.25}
                  stroke-opacity="0.75"
                />
              {/each}

              <!-- 5 根品柱 (水平线) -->
              {#each [34, 50, 66, 82, 98] as y}
                <line x1="20" y1={y} x2="80" y2={y} stroke="#d0c4b2" stroke-width="1.2" />
              {/each}

              <!-- 横按标记 (Barre) -->
              {#if chord.barre}
                <rect
                  x={20 + (6 - chord.barre.toStr) * 12}
                  y={18 + (chord.barre.fret - 1) * 16 + 5}
                  width={(chord.barre.toStr - chord.barre.fromStr + 1) * 12}
                  height="6"
                  rx="3"
                  fill="#c49a45"
                  opacity="0.85"
                />
              {/if}

              <!-- 弦头标记 (X 哑音 / O 空弦) -->
              {#each chord.frets as fret, strIdx}
                {#if fret === -1}
                  <!-- ✕ 哑音 -->
                  <text
                    x={20 + strIdx * 12}
                    y="12"
                    text-anchor="middle"
                    font-size="9"
                    font-weight="bold"
                    fill="#a65d57"
                  >✕</text>
                {:else if fret === 0}
                  <!-- ○ 空弦 -->
                  <circle
                    cx={20 + strIdx * 12}
                    cy="10"
                    r="3"
                    fill="none"
                    stroke="#5c7a58"
                    stroke-width="1.2"
                  />
                {:else if fret > 0}
                  <!-- 按弦实心圆点与指法序号 -->
                  <circle
                    cx={20 + strIdx * 12}
                    cy={18 + (fret - 1) * 16 + 8}
                    r="4.5"
                    fill="#2c241b"
                  />
                  {#if chord.fingers && chord.fingers[strIdx] > 0}
                    <text
                      x={20 + strIdx * 12}
                      y={18 + (fret - 1) * 16 + 11}
                      text-anchor="middle"
                      font-size="7.5"
                      font-family="sans-serif"
                      fill="#ffffff"
                      font-weight="bold"
                    >{chord.fingers[strIdx]}</text>
                  {/if}
                {/if}
              {/each}
            </svg>
          </div>

          <!-- 点击试听状态指示 -->
          <span class="text-[10px] text-[#c49a45] font-medium tracking-wide flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <span>试听</span>
            <span>▶</span>
          </span>
        </button>
      {/each}
    </div>

    <!-- 3. 曲目风格与分类标签 (Song Style & Taxonomy Chips) -->
    <div class="mt-7 pt-5 border-t border-[#e8e2d4]/80 flex flex-wrap items-center gap-2">
      <span class="text-xs font-serif font-medium text-[#705c42] mr-2">风格标签：</span>
      {#each tagList as tag}
        <span class="px-3 py-1 rounded-full text-xs font-serif border border-[#dfd4be] bg-white/70 text-[#4a3e32] shadow-2xs hover:border-[#c49a45] hover:bg-[#fffcf7] transition-colors">
          #{tag}
        </span>
      {/each}
    </div>
  </section>
</div>

<!-- 全部 128 款 General MIDI 乐器音色库选择抽屉 / 模态弹窗 (仅在 isModalOpen===true 时挂载，关闭时彻底卸载) -->
{#if isModalOpen}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[#1f1a14]/60 backdrop-blur-xs animate-fade-in instruments-modal">
    <div
      class="relative w-full max-w-4xl max-h-[85vh] rounded-3xl border border-[#e8e2d4] bg-[#fdfbf7] p-6 sm:p-8 shadow-2xl flex flex-col overflow-hidden"
    >
      <!-- 弹窗头部 -->
      <div class="flex items-center justify-between pb-4 border-b border-[#e8e2d4]">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-2xl bg-[#eee7d8] border border-[#d8ccb4] flex items-center justify-center text-xl shadow-xs">
            🎼
          </div>
          <div>
            <h3 class="font-display text-lg font-bold text-[#2c241b]">全部 128 款 General MIDI 音色乐器库</h3>
            <p class="text-xs text-[#8c7b68]">选择任意 GM 音色用于和弦试听，并切换乐谱主音轨；其它音轨保留原谱音色</p>
          </div>
        </div>

        <button
          type="button"
          on:click={() => (isModalOpen = false)}
          class="w-9 h-9 rounded-full bg-[#f2ece0] border border-[#d8ccb4] text-[#705c42] hover:bg-[#2c241b] hover:text-white transition-colors flex items-center justify-center text-lg cursor-pointer"
        >
          ✕
        </button>
      </div>

      <!-- 搜索栏与分类选项卡 -->
      <div class="py-4 space-y-3 border-b border-[#e8e2d4]/70">
        <!-- 搜索输入框 -->
        <div class="relative">
          <input
            type="text"
            bind:value={instrumentSearchKeyword}
            placeholder="搜索 128 款乐器（如：钢弦、古典、萨克斯、小号、古筝、马林巴、失真）..."
            class="w-full pl-10 pr-4 py-2.5 rounded-2xl border border-[#d8ccb4] bg-white/90 text-sm text-[#2c241b] placeholder-[#a69888] focus:outline-hidden focus:border-[#c49a45] focus:ring-2 focus:ring-[#c49a45]/20 shadow-2xs font-serif"
          />
          <span class="absolute left-3.5 top-2.5 text-[#8c7b68]">🔍</span>
          {#if instrumentSearchKeyword}
            <button
              type="button"
              on:click={() => (instrumentSearchKeyword = '')}
              class="absolute right-3 top-2.5 text-xs text-[#8c7b68] hover:text-[#2c241b]"
            >
              清除
            </button>
          {/if}
        </div>

        <!-- 8 大乐器分类快速筛选标签 -->
        <div class="flex flex-wrap items-center gap-1.5">
          <button
            type="button"
            on:click={() => (selectedCategoryTab = '全部')}
            class="px-3 py-1 rounded-full text-xs font-serif font-medium transition-all {selectedCategoryTab === '全部'
              ? 'bg-[#2c241b] text-white shadow-2xs font-bold'
              : 'bg-[#eee7d8] text-[#705c42] hover:bg-white/80'}"
          >
            全部 (128)
          </button>
          {#each GM_CATEGORIES as cat}
            <button
              type="button"
              on:click={() => (selectedCategoryTab = cat)}
              class="px-3 py-1 rounded-full text-xs font-serif font-medium transition-all {selectedCategoryTab === cat
                ? 'bg-[#2c241b] text-white shadow-2xs font-bold'
                : 'bg-[#eee7d8] text-[#705c42] hover:bg-white/80'}"
            >
              {cat}
            </button>
          {/each}
        </div>
      </div>

      <!-- 128 款乐器网格列表 (带滚动条) -->
      <div class="flex-1 overflow-y-auto py-4 pr-1 min-h-[300px]">
        {#if filteredInstruments.length > 0}
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2.5">
            {#each filteredInstruments as inst}
              <button
                type="button"
                on:click={() => handleProgramSelect(inst.program)}
                class="instrument-option-card flex items-center gap-2.5 p-2.5 rounded-2xl border text-left transition-all duration-150 cursor-pointer group {selectionKnown && selectedFlavor === 'gm' && selectedProgram === inst.program
                  ? 'border-[#c49a45] bg-[#fbf5e8] ring-2 ring-[#c49a45]/30 shadow-xs'
                  : 'border-[#e8e2d4] bg-white/70 hover:border-[#c49a45]/60 hover:bg-white'}"
              >
                <div class="w-8 h-8 rounded-xl bg-[#eee7d8] flex items-center justify-center text-base shrink-0 group-hover:scale-108 transition-transform">
                  {inst.icon}
                </div>
                <div class="min-w-0 flex-1">
                  <div class="flex items-center justify-between gap-1">
                    <span class="font-display text-xs font-semibold text-[#2c241b] truncate group-hover:text-[#966b26]">
                      {inst.name}
                    </span>
                    <span class="text-[10px] font-mono text-[#b0a18f] shrink-0">
                      #{inst.program}
                    </span>
                  </div>
                  <p class="text-[10px] text-[#8c7b68] truncate font-serif">
                    {inst.enName}
                  </p>
                </div>
              </button>
            {/each}
          </div>
        {:else}
          <div class="flex flex-col items-center justify-center h-48 text-[#8c7b68] text-sm">
            <span class="text-3xl mb-2">🔍</span>
            <p>未找到与「{instrumentSearchKeyword}」匹配的乐器</p>
            <button
              type="button"
              on:click={() => { instrumentSearchKeyword = ''; selectedCategoryTab = '全部'; }}
              class="mt-2 text-xs text-[#c49a45] underline cursor-pointer"
            >
              重置所有筛选
            </button>
          </div>
        {/if}
      </div>

      <!-- 底部当前选定信息与关闭 -->
      <div class="pt-4 border-t border-[#e8e2d4] flex items-center justify-between text-xs text-[#705c42]">
        <div class="flex items-center gap-2">
          <span>当前选定音色：</span>
          <span class="font-bold text-[#2c241b]">{auditionSelectionLabel()}</span>
        </div>
        <button
          type="button"
          on:click={() => (isModalOpen = false)}
          class="px-4 py-1.5 rounded-full bg-[#2c241b] text-[#fbf8f1] font-medium hover:bg-[#4a3e32] transition-colors cursor-pointer"
        >
          完成选择
        </button>
      </div>
    </div>
  </div>
{/if}
