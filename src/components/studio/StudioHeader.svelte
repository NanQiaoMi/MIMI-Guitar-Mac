<script lang="ts">
  import { tick } from 'svelte';
  import { registerMotionSurface, surfaceMotion } from '../../lib/ui/motion';
  import type { StudioProject } from '../../lib/studio/studioScoreModel';

  let {
    project,
    selectedTrackIndex = 0,
    isPlaying = false,
    canUndo = false,
    canRedo = false,
    hasLoop = false,
    metronome = false,
    countIn = false,
    onTogglePlay,
    onStop,
    onToggleLoop,
    onToggleMetronome,
    onToggleCountIn,
    onUndo,
    onRedo,
    onOpenMixer,
    onOpenLyrics,
    onOpenShortcuts,
    onOpenGuide,
    onOpenDrafts,
    onDownloadSource,
    onSaveDraft,
    onAddToPractice,
    onNewProject,
    onExportFile,
    onExportImage,
    onExportPdf,
    onUpdateProject,
  }: {
    project: StudioProject;
    selectedTrackIndex?: number;
    isPlaying: boolean;
    canUndo: boolean;
    canRedo: boolean;
    hasLoop: boolean;
    metronome: boolean;
    countIn: boolean;
    onTogglePlay?: () => void;
    onStop?: () => void;
    onToggleLoop?: () => void;
    onToggleMetronome?: () => void;
    onToggleCountIn?: () => void;
    onUndo?: () => void;
    onRedo?: () => void;
    onOpenMixer?: () => void;
    onOpenLyrics?: () => void;
    onOpenShortcuts?: () => void;
    onOpenGuide?: () => void;
    onOpenDrafts?: () => void;
    onDownloadSource?: () => void | Promise<void>;
    onSaveDraft?: () => void;
    onAddToPractice?: () => void | Promise<void>;
    onNewProject?: (type: 'guitar' | 'ukulele' | 'bass') => void | Promise<void>;
    onExportFile?: (format: 'json' | 'ibe' | 'gp' | 'tex') => void | Promise<void>;
    onExportImage?: () => void;
    onExportPdf?: () => void;
    onUpdateProject?: (updated: StudioProject) => void;
  } = $props();

  let showExportMenu = $state(false);
  let showNewMenu = $state(false);
  let practiceActionPending = $state(false);
  let newProjectPending = $state(false);
  let newMenuRegion: HTMLDivElement | null = $state(null);
  let exportMenuRegion: HTMLDivElement | null = $state(null);
  let newMenuTrigger: HTMLButtonElement | null = $state(null);
  let exportMenuTrigger: HTMLButtonElement | null = $state(null);

  type StudioMenu = 'new' | 'export';

  function setOpenMenu(menu: StudioMenu | null) {
    showNewMenu = menu === 'new';
    showExportMenu = menu === 'export';
  }

  function toggleMenu(menu: StudioMenu) {
    const alreadyOpen = menu === 'new' ? showNewMenu : showExportMenu;
    setOpenMenu(alreadyOpen ? null : menu);
  }

  function closeMenu(menu: StudioMenu, restoreFocus = false) {
    const wasOpen = menu === 'new' ? showNewMenu : showExportMenu;
    if (!wasOpen) return;
    setOpenMenu(null);

    if (restoreFocus) {
      const trigger = menu === 'new' ? newMenuTrigger : exportMenuTrigger;
      if (trigger?.isConnected && !trigger.closest('[inert]')) trigger.focus({ preventScroll: true });
    }
  }

  function menuRegion(menu: StudioMenu) {
    return menu === 'new' ? newMenuRegion : exportMenuRegion;
  }

  function handleMenuFocusOut(event: FocusEvent, menu: StudioMenu) {
    const next = event.relatedTarget;
    if (!(next instanceof Node) || !menuRegion(menu)?.contains(next)) closeMenu(menu);
  }

  function handleWindowPointerDown(event: PointerEvent) {
    const target = event.target;
    if (showNewMenu && (!(target instanceof Node) || !newMenuRegion?.contains(target))) closeMenu('new');
    if (showExportMenu && (!(target instanceof Node) || !exportMenuRegion?.contains(target))) closeMenu('export');
  }

  function handleWindowKeyDown(event: KeyboardEvent) {
    if (event.key !== 'Escape') return;
    const openMenu: StudioMenu | null = showExportMenu ? 'export' : showNewMenu ? 'new' : null;
    if (!openMenu) return;
    event.preventDefault();
    event.stopPropagation();
    closeMenu(openMenu, true);
  }

  async function runNewProject(type: 'guitar' | 'ukulele' | 'bass') {
    if (newProjectPending) return;
    closeMenu('new', true);
    newProjectPending = true;
    try {
      await onNewProject?.(type);
    } finally {
      newProjectPending = false;
      await tick();
      if (newMenuTrigger?.isConnected && !newMenuTrigger.closest('[inert]')) {
        newMenuTrigger.focus({ preventScroll: true });
      }
    }
  }

  async function addCurrentProjectToPractice() {
    if (practiceActionPending) return;
    practiceActionPending = true;
    try {
      await onAddToPractice?.();
    } finally {
      practiceActionPending = false;
    }
  }

  const KEY_OPTIONS = ['C', 'G', 'D', 'A', 'E', 'F', 'Bb', 'Eb', 'Am', 'Em', 'Dm', 'Bm', 'F#m'];
  const TIME_SIGNATURE_OPTIONS = [
    { num: 4, den: 4, label: '4/4 拍' },
    { num: 3, den: 4, label: '3/4 拍' },
    { num: 2, den: 4, label: '2/4 拍' },
    { num: 6, den: 8, label: '6/8 拍' },
    { num: 12, den: 8, label: '12/8 拍' },
  ];

  function handleTitleChange(val: string) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.title = val;
    onUpdateProject?.(next);
  }

  function handleArtistChange(val: string) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.artist = val;
    onUpdateProject?.(next);
  }

  function handleBpmChange(bpm: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.initialTempo = Math.max(30, Math.min(300, bpm));
    if (next.bars[0]) next.bars[0].tempo = next.initialTempo;
    onUpdateProject?.(next);
  }

  function handleKeyChange(key: string) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.key = key;
    onUpdateProject?.(next);
  }

  function handleCapoChange(capo: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    if (next.tracks[selectedTrackIndex]) next.tracks[selectedTrackIndex].capo = capo;
    onUpdateProject?.(next);
  }

  function handleTimeSignatureChange(num: number, den: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.timeSignatureNumerator = num;
    next.timeSignatureDenominator = den;
    next.bars.forEach((bar) => {
      bar.timeSignatureNumerator = num;
      bar.timeSignatureDenominator = den;
    });
    onUpdateProject?.(next);
  }
</script>

<svelte:window onpointerdown={handleWindowPointerDown} onkeydown={handleWindowKeyDown} />

<header class="relative w-full bg-[#f8f5ee]/95 text-[#2c2825] border-b border-[#e4dbcc] px-4 sm:px-8 py-3 flex flex-wrap items-center justify-between gap-3 select-none backdrop-blur-md shadow-2xs">
  <!-- 左侧：工程曲名与作者编辑 -->
  <div class="flex min-w-0 items-center gap-3.5">
    <a
      href="/tabs"
      class="min-h-[44px] flex items-center gap-1 text-[#8a6b29] hover:text-[#2c2825] bg-[#ede5d8]/70 hover:bg-[#ede5d8] px-2.5 rounded-full transition-colors font-serif font-bold text-xs"
      title="返回曲库"
    >
      <span>‹</span>
      <span class="hidden sm:inline">曲库</span>
    </a>

    <div class="flex w-60 max-w-full min-w-0 shrink flex-col">
      <input
        type="text"
        value={project.title}
        oninput={(e) => handleTitleChange((e.currentTarget as HTMLInputElement).value)}
        placeholder="输入乐谱名称..."
        class="min-h-[44px] min-w-[44px] w-full max-w-full bg-transparent text-base sm:text-lg font-serif font-bold text-[#2c2825] focus:bg-[#ede5d8] px-2 py-0.5 rounded-lg border border-transparent focus:border-[#c49a45]/50 focus:outline-hidden truncate transition-colors"
      />
      <input
        type="text"
        value={project.artist}
        oninput={(e) => handleArtistChange((e.currentTarget as HTMLInputElement).value)}
        placeholder="原唱 / 艺术家..."
        class="min-h-[44px] min-w-[44px] w-full max-w-full bg-transparent text-xs font-serif text-[#8c7b68] focus:bg-[#ede5d8] px-2 py-0.5 rounded-lg border border-transparent focus:border-[#c49a45]/50 focus:outline-hidden truncate transition-colors"
      />
    </div>
  </div>

  <!-- 中间：传输控制台 (Transport HUD) 与 播放/速度 -->
  <div class="flex items-center gap-2 flex-wrap justify-center">
    <!-- 撤销 / 重做 -->
    <div class="flex items-center bg-[#ede5d8]/80 p-0.5 rounded-xl border border-[#dfd6c7]">
      <button
        type="button"
        onclick={onUndo}
        disabled={!canUndo}
        class="min-h-[44px] px-2.5 text-xs font-medium text-[#5c4a38] hover:text-[#2c2825] hover:bg-[#ffffff]/60 rounded-lg disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
        title="撤销 (Ctrl + Z)"
      >
        ↩ 撤销
      </button>
      <button
        type="button"
        onclick={onRedo}
        disabled={!canRedo}
        class="min-h-[44px] px-2.5 text-xs font-medium text-[#5c4a38] hover:text-[#2c2825] hover:bg-[#ffffff]/60 rounded-lg disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
        title="重做 (Ctrl + Y)"
      >
        ↪ 重做
      </button>
    </div>

    <!-- 播放 / 暂停 / 停止 -->
    <div class="flex items-center bg-[#ede5d8]/80 p-1 rounded-full border border-[#dfd6c7] gap-1 shadow-xs">
      <button
        type="button"
        onclick={onTogglePlay}
        class="flex items-center justify-center min-w-[44px] min-h-[44px] rounded-full bg-[#c49a45] text-[#ffffff] font-bold text-xs hover:bg-[#b08836] transition-colors shadow-sm"
        title="播放 / 暂停 (空格键)"
      >
        {#if isPlaying}
          <span>⏸</span>
        {:else}
          <span class="ml-0.5">▶</span>
        {/if}
      </button>

      <button
        type="button"
        onclick={onStop}
        class="flex items-center justify-center min-w-[44px] min-h-[44px] rounded-full bg-[#f4eee4] text-[#705c42] hover:text-[#2c2825] hover:bg-[#ffffff] transition-colors text-xs"
        title="停止并归零"
      >
        ⏹
      </button>
    </div>

    <!-- 节拍器 / 预备拍 / 循环 -->
    <div class="flex items-center bg-[#ede5d8]/80 p-1 rounded-xl border border-[#dfd6c7] gap-1">
      <button
        type="button"
        onclick={onToggleMetronome}
        class="min-h-[44px] px-2 rounded-lg text-xs font-mono transition-colors {metronome ? 'bg-[#2c2825] text-[#fbfaf7] font-bold shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/60 hover:text-[#2c2825]'}"
        aria-label="节拍器"
        aria-pressed={metronome}
        title="节拍器打点"
      >
        ⏱️ 节拍器
      </button>
      <button
        type="button"
        onclick={onToggleCountIn}
        class="min-h-[44px] px-2 rounded-lg text-xs font-mono transition-colors {countIn ? 'bg-[#2c2825] text-[#fbfaf7] font-bold shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/60 hover:text-[#2c2825]'}"
        aria-label="预备拍"
        aria-pressed={countIn}
        title="按当前小节拍号先打一次预备拍"
      >
        1234
      </button>
      <button
        type="button"
        onclick={onToggleLoop}
        class="min-h-[44px] px-2 rounded-lg text-xs font-mono transition-colors {hasLoop ? 'bg-[#2c2825] text-[#fbfaf7] font-bold shadow-xs' : 'text-[#705c42] hover:bg-[#ffffff]/60 hover:text-[#2c2825]'}"
        aria-label="整首乐谱循环"
        aria-pressed={hasLoop}
        title="整首乐谱循环试听"
      >
        🔄 整曲循环
      </button>
    </div>

    <!-- 速度 BPM -->
    <div class="flex items-center bg-[#ede5d8]/80 px-2.5 py-1 rounded-xl border border-[#dfd6c7] gap-1.5 text-xs font-mono">
      <span class="text-[#705c42] font-semibold">BPM</span>
      <input
        type="number"
        min="30"
        max="300"
        value={project.initialTempo}
        onchange={(e) => handleBpmChange(Number((e.currentTarget as HTMLInputElement).value))}
        class="min-h-[44px] w-12 bg-[#ffffff] text-[#966b1a] text-center font-bold px-1 rounded-lg border border-[#dfd6c7] focus:border-[#c49a45] focus:outline-hidden"
      />
    </div>

    <!-- 调性与拍号 -->
    <div class="flex items-center gap-1.5 hidden lg:flex">
      <select
        value={project.key}
        onchange={(e) => handleKeyChange((e.currentTarget as HTMLSelectElement).value)}
        class="min-h-[44px] bg-[#ede5d8]/80 text-[#2c2825] text-xs px-2.5 rounded-xl border border-[#dfd6c7] focus:border-[#c49a45] focus:outline-hidden font-serif"
      >
        {#each KEY_OPTIONS as k}
          <option value={k}>{k} 调</option>
        {/each}
      </select>

      <select
        value={`${project.timeSignatureNumerator}/${project.timeSignatureDenominator}`}
        onchange={(e) => {
          const [n, d] = (e.currentTarget as HTMLSelectElement).value.split('/').map(Number);
          handleTimeSignatureChange(n, d);
        }}
        class="min-h-[44px] bg-[#ede5d8]/80 text-[#2c2825] text-xs px-2.5 rounded-xl border border-[#dfd6c7] focus:border-[#c49a45] focus:outline-hidden font-serif"
      >
        {#each TIME_SIGNATURE_OPTIONS as ts}
          <option value={`${ts.num}/${ts.den}`}>{ts.label}</option>
        {/each}
      </select>

      <!-- 变调夹 Capo -->
      <select
        value={project.tracks[selectedTrackIndex]?.capo || 0}
        onchange={(e) => handleCapoChange(Number((e.currentTarget as HTMLSelectElement).value))}
        class="min-h-[44px] bg-[#ede5d8]/80 text-[#2c2825] text-xs px-2.5 rounded-xl border border-[#dfd6c7] focus:border-[#c49a45] focus:outline-hidden font-serif"
      >
        <option value={0}>原调 (无Capo)</option>
        <option value={1}>Capo 1 品</option>
        <option value={2}>Capo 2 品</option>
        <option value={3}>Capo 3 品</option>
        <option value={4}>Capo 4 品</option>
        <option value={5}>Capo 5 品</option>
        <option value={6}>Capo 6 品</option>
      </select>
    </div>
  </div>

  <!-- 右侧：抽屉触发器、导出与保存 -->
  <div class="flex min-w-0 max-w-full flex-wrap items-center justify-end gap-2">
    <!-- 调音台 / 歌词 / 快捷键 抽屉按钮 -->
    <button
      type="button"
      onclick={onOpenMixer}
      id="studio-open-mixer"
      aria-label="打开多轨调音台"
      class="min-h-[44px] min-w-[44px] px-3 bg-[#ede5d8]/70 text-[#5c4a38] hover:text-[#2c2825] hover:bg-[#ede5d8] rounded-xl border border-[#dfd6c7] text-xs font-serif transition-colors inline-flex items-center gap-1"
      title="打开多轨调音台"
    >
      <span>🎛️ 调音台</span>
    </button>

    <button
      type="button"
      onclick={onOpenLyrics}
      id="studio-open-lyrics"
      aria-label="打开歌词智能对齐"
      class="min-h-[44px] min-w-[44px] px-3 bg-[#ede5d8]/70 text-[#5c4a38] hover:text-[#2c2825] hover:bg-[#ede5d8] rounded-xl border border-[#dfd6c7] text-xs font-serif transition-colors inline-flex items-center gap-1"
      title="智能歌词对齐"
    >
      <span>📝 歌词</span>
    </button>

    <button
      type="button"
      onclick={onOpenShortcuts}
      id="studio-open-shortcuts"
      aria-label="打开快捷键速查"
      class="min-w-[44px] min-h-[44px] rounded-xl bg-[#ede5d8]/70 hover:bg-[#ede5d8] border border-[#dfd6c7] text-[#705c42] hover:text-[#2c2825] flex items-center justify-center text-xs transition-colors"
      title="快捷键速查"
    >
      ⌨️
    </button>
    <button
      type="button"
      onclick={onOpenGuide}
      id="studio-open-guide"
      aria-label="打开制谱教程、格式说明和常见问题"
      class="min-h-[44px] min-w-[44px] px-2.5 rounded-xl bg-[#ede5d8]/70 hover:bg-[#ede5d8] border border-[#dfd6c7] text-[#705c42] hover:text-[#2c2825] inline-flex items-center gap-1 text-xs transition-colors"
      title="查看制谱教程、格式说明和常见问题"
    >
      📖 <span>教程</span>
    </button>

    <!-- 新建工程下拉菜单 -->
    <div bind:this={newMenuRegion} class="static inline-block min-w-0 text-left sm:relative" onfocusout={(event) => handleMenuFocusOut(event, 'new')}>
      <button
        bind:this={newMenuTrigger}
        type="button"
        id="studio-new-menu-trigger"
        aria-expanded={showNewMenu}
        aria-controls="studio-new-menu"
        onclick={() => toggleMenu('new')}
        class="min-h-[44px] min-w-[44px] px-3 bg-[#ede5d8]/70 hover:bg-[#ede5d8] border border-[#dfd6c7] text-[#5c4a38] hover:text-[#2c2825] rounded-xl text-xs font-serif transition-colors flex items-center gap-1"
        title="新建乐谱工程"
      >
        <span>➕ 新建 ▼</span>
      </button>

      <div
        id="studio-new-menu"
        aria-labelledby="studio-new-menu-trigger"
        aria-hidden={!showNewMenu}
        inert={!showNewMenu}
        class={`absolute left-4 right-4 top-full mt-2 w-auto max-w-[calc(100vw_-_2rem)] max-h-[78vh] overflow-y-auto z-50 sm:top-auto sm:left-auto sm:right-0 sm:mt-2 sm:w-48 ${showNewMenu ? 'pointer-events-auto' : 'pointer-events-none'}`}
      >
        {#if showNewMenu}
          <div
            use:registerMotionSurface
            transition:surfaceMotion={{ kind: 'menu' }}
            class="w-full rounded-2xl bg-[#ffffff] border border-[#e2d7c5] shadow-2xl p-2 text-xs flex flex-col gap-1"
          >
          <button
            type="button"
            disabled={newProjectPending}
            onclick={() => { void runNewProject('guitar'); }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors disabled:cursor-wait disabled:opacity-60"
          >
            <span class="text-base">🎸</span>
            <div>
              <div class="font-bold font-serif">6 弦民谣吉他</div>
              <div class="text-[10px] text-[#8c7b68]">标准 EADGBE 调弦</div>
            </div>
          </button>
          <button
            type="button"
            disabled={newProjectPending}
            onclick={() => { void runNewProject('ukulele'); }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors disabled:cursor-wait disabled:opacity-60"
          >
            <span class="text-base">🌺</span>
            <div>
              <div class="font-bold font-serif">4 弦尤克里里</div>
              <div class="text-[10px] text-[#8c7b68]">标准 GCEA 调弦</div>
            </div>
          </button>
          <button
            type="button"
            disabled={newProjectPending}
            onclick={() => { void runNewProject('bass'); }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors disabled:cursor-wait disabled:opacity-60"
          >
            <span class="text-base">⚡</span>
            <div>
              <div class="font-bold font-serif">4 弦电贝斯</div>
              <div class="text-[10px] text-[#8c7b68]">低音 EADG 调弦</div>
            </div>
          </button>
          </div>
        {/if}
      </div>
    </div>

    <button
      type="button"
      onclick={onOpenDrafts}
      id="studio-open-drafts"
      aria-label="打开本地草稿箱"
      class="min-h-[44px] min-w-[44px] px-3 bg-[#ede5d8]/70 hover:bg-[#ede5d8] border border-[#dfd6c7] text-[#5c4a38] hover:text-[#2c2825] rounded-xl text-xs font-serif transition-colors"
      title="本地草稿箱"
    >
      📁 草稿
    </button>

    <!-- 导出 / 发布 下拉菜单 -->
    <div bind:this={exportMenuRegion} class="static inline-block min-w-0 text-left sm:relative" onfocusout={(event) => handleMenuFocusOut(event, 'export')}>
      <button
        bind:this={exportMenuTrigger}
        type="button"
        id="studio-export-menu-trigger"
        aria-expanded={showExportMenu}
        aria-controls="studio-export-menu"
        onclick={() => toggleMenu('export')}
        class="min-h-[44px] min-w-[44px] px-4 bg-[#2c2825] text-[#fbfaf7] font-serif font-bold text-xs rounded-xl hover:bg-[#403b37] transition-colors flex items-center gap-1 shadow-xs"
      >
        <span>保存 / 导出 ▼</span>
      </button>

      <div
        id="studio-export-menu"
        aria-labelledby="studio-export-menu-trigger"
        aria-hidden={!showExportMenu}
        inert={!showExportMenu}
        class={`absolute left-4 right-4 top-full mt-2 w-auto max-w-[calc(100vw_-_2rem)] max-h-[78vh] overflow-y-auto z-50 sm:top-auto sm:left-auto sm:right-0 sm:mt-2 sm:w-64 ${showExportMenu ? 'pointer-events-auto' : 'pointer-events-none'}`}
      >
        {#if showExportMenu}
          <div
            use:registerMotionSurface
            transition:surfaceMotion={{ kind: 'menu' }}
            class="w-full rounded-2xl bg-[#ffffff] border border-[#e2d7c5] shadow-2xl p-2 text-xs flex flex-col gap-1"
          >
          <button
            type="button"
            onclick={() => {
              closeMenu('export', true);
              onSaveDraft?.();
            }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">💾</span>
            <div>
              <div class="font-bold font-serif">保存到草稿箱</div>
              <div class="text-[10px] text-[#8c7b68]">Ctrl + S 本地防丢</div>
            </div>
          </button>

          <button
            type="button"
            disabled={practiceActionPending}
            onclick={() => { closeMenu('export', true); void addCurrentProjectToPractice(); }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors disabled:cursor-wait disabled:opacity-60"
          >
            <span class="text-base">🎯</span>
            <div>
              <div class="font-bold font-serif">{practiceActionPending ? '正在加入待练…' : '保存并加入待练'}</div>
              <div class="text-[10px] text-[#8c7b68]">保存当前版本，进入 A-B 分段、逐步提速与练习记录</div>
            </div>
          </button>

          <button
            type="button"
            onclick={() => {
              closeMenu('export', true);
              onExportImage?.();
            }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">🖼️</span>
            <div>
              <div class="font-bold font-serif">导出谱面长图</div>
              <div class="text-[10px] text-[#8c7b68]">PNG · 最长 14 页，长谱请用 PDF</div>
            </div>
          </button>

          <button
            type="button"
            onclick={() => {
              closeMenu('export', true);
              onExportPdf?.();
            }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">📄</span>
            <div>
              <div class="font-bold font-serif">导出标准 A4 分页 PDF</div>
              <div class="text-[10px] text-[#8c7b68]">A4 分页 · 请检查导出文件中的谱面</div>
            </div>
          </button>

          <button
            type="button"
            onclick={() => {
              closeMenu('export', true);
              onExportFile?.('json');
            }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">📦</span>
            <div>
              <div class="font-bold font-serif">导出工坊工程 JSON</div>
              <div class="text-[10px] text-[#8c7b68]">保留可继续编辑的本机工程</div>
            </div>
          </button>

          <button
            type="button"
            onclick={() => {
              closeMenu('export', true);
              onExportFile?.('ibe');
            }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">🎼</span>
            <div>
              <div class="font-bold font-serif">导出 MIMI .ibe 乐谱</div>
              <div class="text-[10px] text-[#8c7b68]">可被本项目播放器读取的二进制谱</div>
            </div>
          </button>

          <button
            type="button"
            onclick={() => { closeMenu('export', true); onExportFile?.('gp'); }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">🎸</span>
            <div>
              <div class="font-bold font-serif">导出 Guitar Pro 7</div>
              <div class="text-[10px] text-[#8c7b68]">GP 文件，可在兼容软件继续制谱</div>
            </div>
          </button>

          <button
            type="button"
            onclick={() => { closeMenu('export', true); onExportFile?.('tex'); }}
            class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#2c2825] hover:bg-[#f5efe6] transition-colors"
          >
            <span class="text-base">⌨️</span>
            <div>
              <div class="font-bold font-serif">导出 AlphaTex</div>
              <div class="text-[10px] text-[#8c7b68]">可读的乐谱标记文本</div>
            </div>
          </button>

          {#if project.source}
            <div class="border-t border-[#e8dfd2] my-1"></div>
            <button
              type="button"
              onclick={() => { closeMenu('export', true); onDownloadSource?.(); }}
              class="min-h-[44px] flex items-center gap-2 px-3 py-2.5 rounded-xl text-left text-[#8d3b27] hover:bg-[#fff4ef] transition-colors"
            >
              <span class="text-base">🛡️</span>
              <div>
                <div class="font-bold font-serif">下载导入时的原始文件</div>
                <div class="text-[10px] text-[#8c7b68] truncate">{project.source.fileName}</div>
              </div>
            </button>
          {/if}
          </div>
        {/if}
      </div>
    </div>
  </div>
</header>
