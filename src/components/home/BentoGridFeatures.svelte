<script lang="ts">
  import { onMount } from 'svelte';
  import { scoreAuditionEngine, type AuditionState } from '../../lib/scoreAuditionEngine';

  let activeNotationMode = $state<'mixed' | 'tab' | 'jianpu'>('mixed');
  let activeTrackMutes = $state<Record<string, boolean>>({ guitar: false, bass: false, drums: false, strings: false });
  let manualFretNote = $state<{ string: number; fret: number } | null>(null);

  // Audition Subscription
  let audition = $state<AuditionState>(scoreAuditionEngine.getState());

  // Demo Tab for In-Card Quick Play
  const demoTab = {
    id: '1sdc49P3eKm',
    title: '晴天',
    artist: '周杰伦',
    key: 'G',
    difficulty: 2,
    sheetForm: 2,
    scoreUrl: '/storage/scores/1sdc49P3eKm.ibe',
  };

  onMount(() => {
    const unsub = scoreAuditionEngine.subscribe((st) => {
      audition = st;
    });
    return () => unsub();
  });

  function toggleMute(track: string) {
    activeTrackMutes[track] = !activeTrackMutes[track];
  }

  async function toggleBentoAudition(e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    await scoreAuditionEngine.togglePlayTab(demoTab);
  }

  // Rhythmic fallback patterns for standard chords (G, Em7, Cadd9, D) to ensure vibrant, continuous fret lighting
  const CHORD_PATTERNS = [
    [{ string: 6, fret: 3 }, { string: 2, fret: 3 }, { string: 1, fret: 3 }], // G
    [{ string: 4, fret: 0 }, { string: 3, fret: 0 }],
    [{ string: 2, fret: 3 }, { string: 1, fret: 3 }],
    [{ string: 5, fret: 2 }, { string: 4, fret: 2 }, { string: 2, fret: 3 }], // Em7
    [{ string: 3, fret: 0 }, { string: 2, fret: 3 }],
    [{ string: 5, fret: 3 }, { string: 4, fret: 2 }, { string: 2, fret: 3 }], // Cadd9
    [{ string: 3, fret: 0 }, { string: 1, fret: 3 }],
    [{ string: 4, fret: 0 }, { string: 3, fret: 2 }, { string: 2, fret: 3 }], // D
    [{ string: 1, fret: 2 }, { string: 2, fret: 3 }],
  ];

  function getDynamicNotes(): Array<{ string: number; fret: number }> {
    if (manualFretNote) {
      return [manualFretNote];
    }
    if (audition.isPlaying) {
      if (audition.activeNotes && audition.activeNotes.length > 0) {
        return audition.activeNotes;
      }
      // Rhythmic pulsation based on current playback millisecond
      const idx = Math.floor(audition.currentTime / 280) % CHORD_PATTERNS.length;
      return CHORD_PATTERNS[idx];
    }
    return [{ string: 2, fret: 3 }];
  }

  function isNoteActive(strNum: number, fretNum: number): boolean {
    const active = getDynamicNotes();
    return active.some((n) => n.string === strNum && n.fret === fretNum);
  }

  // Fretboard displayed frets
  const FRET_COLUMNS = [
    { fret: 0, label: '0品(NUT)', hasDot: false },
    { fret: 1, label: '1品', hasDot: false },
    { fret: 2, label: '2品', hasDot: false },
    { fret: 3, label: '3品', hasDot: true, dotType: 'single' },
    { fret: 5, label: '5品', hasDot: true, dotType: 'single' },
    { fret: 7, label: '7品', hasDot: true, dotType: 'single' },
    { fret: 9, label: '9品', hasDot: true, dotType: 'single' },
    { fret: 12, label: '12品', hasDot: true, dotType: 'double' },
  ];

  // 6 Strings Configuration
  const STRINGS = [
    { num: 1, name: '1弦 (E)', color: 'bg-gradient-to-r from-[#d6d3d1] via-[#ffffff] to-[#d6d3d1]', height: 'h-[1px]', shadow: 'shadow-[0_0_2px_rgba(255,255,255,0.4)]' },
    { num: 2, name: '2弦 (B)', color: 'bg-gradient-to-r from-[#c7c2be] via-[#f5f5f4] to-[#c7c2be]', height: 'h-[1.5px]', shadow: 'shadow-[0_0_2px_rgba(255,255,255,0.3)]' },
    { num: 3, name: '3弦 (G)', color: 'bg-gradient-to-r from-[#c49a45] via-[#e2c078] to-[#c49a45]', height: 'h-[2px]', shadow: 'shadow-[0_0_3px_rgba(196,154,69,0.4)]' },
    { num: 4, name: '4弦 (D)', color: 'bg-gradient-to-r from-[#b38634] via-[#dfb55a] to-[#b38634]', height: 'h-[2.5px]', shadow: 'shadow-[0_0_3px_rgba(196,154,69,0.4)]' },
    { num: 5, name: '5弦 (A)', color: 'bg-gradient-to-r from-[#9a7024] via-[#c49a45] to-[#9a7024]', height: 'h-[3px]', shadow: 'shadow-[0_0_4px_rgba(196,154,69,0.3)]' },
    { num: 6, name: '6弦 (E)', color: 'bg-gradient-to-r from-[#805915] via-[#a87d2e] to-[#805915]', height: 'h-[3.5px]', shadow: 'shadow-[0_0_4px_rgba(196,154,69,0.3)]' },
  ];
</script>

<section class="mt-16">
  <!-- Section Title Header -->
  <div class="text-center max-w-2xl mx-auto mb-10">
    <span class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45]/30 bg-[#c49a45]/10 px-3 py-1 font-mono text-xs font-semibold text-[#8f6d2b]">
      <span>⚡</span>
      <span>NEXT-GEN MUSIC SCORE ENGINE</span>
    </span>
    <h2 class="font-display text-2xl sm:text-3xl lg:text-4xl font-bold text-[#2d2926] mt-3">
      为严谨研习打造的现代化乐谱特性
    </h2>
    <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-2">
      融合 Web Audio 现代合成器与像素级矢量排版，重新定义吉他谱研习与伴奏互动标准
    </p>
  </div>

  <!-- Bento Grid Container (4 Golden Ratio Cells) -->
  <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
    <!-- Cell 1: 60FPS Acoustic Synthesizer (Col Span 2) -->
    <div
      class="md:col-span-2 group relative overflow-hidden rounded-3xl border border-[#e2d8c3] bg-gradient-to-br from-[#ffffff] to-[#faf6ee] p-6 sm:p-8 shadow-[0_8px_30px_rgba(76,59,43,0.06)] hover:border-[#c49a45] hover:shadow-[0_16px_40px_rgba(196,154,69,0.14)] transition-all duration-300 flex flex-col justify-between"
    >
      <!-- Background Ambient Glow -->
      <div class="pointer-events-none absolute -right-20 -top-20 h-64 w-64 rounded-full bg-[#c49a45]/10 blur-3xl group-hover:bg-[#c49a45]/20 transition-all"></div>

      <div>
        <div class="flex items-center justify-between">
          <span class="inline-flex items-center gap-1.5 rounded-full bg-[#2d2926] px-3 py-1 text-xs font-mono text-[#faf8f5]">
            <span class="h-1.5 w-1.5 rounded-full bg-[#c49a45] {audition.isPlaying ? 'animate-ping' : ''}"></span>
            60FPS AUDIO SYNTHESIZER
          </span>
          <span class="text-xs font-mono font-bold text-[#c84b31]">
            {audition.isPlaying ? '● 正在实时渲染声波' : '零延迟 · 高保真'}
          </span>
        </div>

        <h3 class="font-display text-xl sm:text-2xl font-bold text-[#2d2926] mt-4">
          内置原声吉他 SoundFont 高清合成器
        </h3>
        <p class="text-xs sm:text-sm text-[#705c42] font-serif mt-1.5 max-w-lg leading-relaxed">
          采用独立 Web Audio 线程渲染与 ScriptProcessor 动态过采样算法，彻底杜绝杂音爆音与音画漂移，伴奏流畅犹如真人伴奏乐队现场合奏。
        </p>
      </div>

      <!-- Live Dynamic Equalizer Bars Demo -->
      <div class="mt-6 rounded-2xl border border-[#e2d8c3] bg-[#ffffff]/90 p-4 backdrop-blur-sm">
        <div class="flex items-center justify-between text-xs font-mono text-[#8c7b68] mb-3">
          <span class="flex items-center gap-1.5">
            <span class="h-2 w-2 rounded-full {audition.isPlaying ? 'bg-[#2e7d32] animate-pulse' : 'bg-[#a89b8a]'}"></span>
            <span>DSP Buffer (44.1kHz / 32-bit Stereo)</span>
          </span>
          <span class="text-[#c49a45] font-semibold">
            {audition.isPlaying ? `PLAYING: ${(audition.currentTime / 1000).toFixed(1)}s / ${(audition.endTime / 1000).toFixed(1)}s` : 'MASTER VOLUME: 85%'}
          </span>
        </div>

        <!-- Dynamic Animated Waves -->
        <div class="flex items-end justify-between gap-1 h-16 px-2">
          {#each [40, 65, 80, 45, 90, 75, 60, 95, 70, 85, 50, 65, 90, 40, 75, 85, 60, 70, 95, 55, 80, 65, 90, 45] as h, i}
            {@const dynamicH = audition.isPlaying ? Math.min(100, Math.max(15, h * (0.6 + 0.5 * Math.sin((audition.currentTime / 120) + i)))) : h}
            <div
              class="w-full rounded-t-sm bg-gradient-to-t from-[#8f6d2b] to-[#c49a45] transition-all duration-150 group-hover:scale-y-105"
              style="height: {dynamicH}%; opacity: {0.5 + (dynamicH / 200)};"
            ></div>
          {/each}
        </div>
      </div>
    </div>

    <!-- Cell 2: Multi-mode Notation (Col Span 1) -->
    <div
      class="group relative overflow-hidden rounded-3xl border border-[#e2d8c3] bg-[#ffffff] p-6 sm:p-7 shadow-[0_8px_30px_rgba(76,59,43,0.06)] hover:border-[#c49a45] hover:shadow-[0_16px_40px_rgba(196,154,69,0.14)] transition-all duration-300 flex flex-col justify-between"
    >
      <div>
        <span class="inline-flex items-center gap-1.5 rounded-full bg-[#fbf9f4] border border-[#e0d6c0] px-3 py-1 text-xs font-mono text-[#705c42]">
          🎼 简六双排
        </span>

        <h3 class="font-display text-lg sm:text-xl font-bold text-[#2d2926] mt-4">
          简谱 · 六线谱 · 和弦一键切换
        </h3>
        <p class="text-xs font-serif text-[#705c42] mt-1 leading-relaxed">
          首创简谱与六线谱完美对齐技术，歌词、唱名、左右手指法一目了然。
        </p>
      </div>

      <!-- Interactive Switcher Demo -->
      <div class="mt-5 rounded-2xl border border-[#e2d8c3] bg-[#fbf9f4] p-3">
        <div class="flex rounded-xl bg-[#ede5d8] p-1 text-[11px] font-serif mb-3">
          <button
            type="button"
            onclick={() => activeNotationMode = 'mixed'}
            class="flex-1 py-1 text-center rounded-lg transition-all {activeNotationMode === 'mixed' ? 'bg-[#ffffff] text-[#2d2926] font-semibold shadow-2xs' : 'text-[#705c42]'}"
          >
            简谱并排
          </button>
          <button
            type="button"
            onclick={() => activeNotationMode = 'tab'}
            class="flex-1 py-1 text-center rounded-lg transition-all {activeNotationMode === 'tab' ? 'bg-[#ffffff] text-[#2d2926] font-semibold shadow-2xs' : 'text-[#705c42]'}"
          >
            纯六线谱
          </button>
          <button
            type="button"
            onclick={() => activeNotationMode = 'jianpu'}
            class="flex-1 py-1 text-center rounded-lg transition-all {activeNotationMode === 'jianpu' ? 'bg-[#ffffff] text-[#2d2926] font-semibold shadow-2xs' : 'text-[#705c42]'}"
          >
            数字简谱
          </button>
        </div>

        <div class="space-y-1 font-mono text-[10px] text-[#5c4a38] bg-[#ffffff] p-2.5 rounded-xl border border-[#e8e2d4]">
          {#if activeNotationMode === 'mixed' || activeNotationMode === 'jianpu'}
            <div class="flex justify-around text-[#c84b31] font-bold border-b border-[#f0eae0] pb-1">
              <span>1</span><span>2</span><span>3</span><span>5</span>
            </div>
          {/if}
          {#if activeNotationMode === 'mixed' || activeNotationMode === 'tab'}
            <div class="flex justify-around text-[#8c7b68] pt-1">
              <span>0</span><span>2</span><span>3</span><span>2</span>
            </div>
          {/if}
        </div>
      </div>
    </div>

    <!-- Cell 3: Multi-Track Mixer (Col Span 1) -->
    <div
      class="group relative overflow-hidden rounded-3xl border border-[#e2d8c3] bg-[#ffffff] p-6 sm:p-7 shadow-[0_8px_30px_rgba(76,59,43,0.06)] hover:border-[#c49a45] hover:shadow-[0_16px_40px_rgba(196,154,69,0.14)] transition-all duration-300 flex flex-col justify-between"
    >
      <div>
        <span class="inline-flex items-center gap-1.5 rounded-full bg-[#fbf9f4] border border-[#e0d6c0] px-3 py-1 text-xs font-mono text-[#705c42]">
          🎛️ STEM MIXER
        </span>

        <h3 class="font-display text-lg sm:text-xl font-bold text-[#2d2926] mt-4">
          多音轨独立分层与消音
        </h3>
        <p class="text-xs font-serif text-[#705c42] mt-1 leading-relaxed">
          可单独关闭吉他原声用于自己跟弹伴奏，或 Solo 主音吉他精细扒带。
        </p>
      </div>

      <!-- Mixer Sliders Demo -->
      <div class="mt-5 space-y-2.5 rounded-2xl border border-[#e2d8c3] bg-[#faf6ee] p-3 text-xs font-serif">
        {#each [{ id: 'guitar', name: '🎸 主音吉他', vol: 90 }, { id: 'bass', name: '🎻 贝斯声部', vol: 75 }, { id: 'drums', name: '🥁 打击鼓组', vol: 60 }] as track}
          <div class="flex items-center justify-between gap-2">
            <span class="text-[11px] text-[#2d2926] font-medium min-w-[70px] truncate">{track.name}</span>
            <div class="h-1.5 flex-1 rounded-full bg-[#e0d6c0] overflow-hidden">
              <div
                class="h-full rounded-full transition-all {activeTrackMutes[track.id] ? 'bg-[#a89b8a]' : 'bg-[#c49a45]'}"
                style="width: {activeTrackMutes[track.id] ? '0%' : track.vol + '%'};"
              ></div>
            </div>
            <button
              type="button"
              onclick={() => toggleMute(track.id)}
              class="rounded px-1.5 py-0.5 text-[10px] font-mono font-bold transition-colors {activeTrackMutes[track.id] ? 'bg-[#c84b31] text-[#ffffff]' : 'bg-[#e2d8c3] text-[#5c4a38] hover:bg-[#c49a45] hover:text-[#ffffff]'}"
            >
              {activeTrackMutes[track.id] ? 'MUTED' : 'MUTE'}
            </button>
          </div>
        {/each}
      </div>
    </div>

    <!-- Cell 4: Holographic Rosewood Virtual Fretboard (Col Span 2) -->
    <div
      class="md:col-span-2 group relative overflow-hidden rounded-3xl border border-[#e2d8c3] bg-gradient-to-br from-[#faf6ee] to-[#ffffff] p-6 sm:p-8 shadow-[0_8px_30px_rgba(76,59,43,0.06)] hover:border-[#c49a45] hover:shadow-[0_16px_40px_rgba(196,154,69,0.14)] transition-all duration-300 flex flex-col justify-between"
    >
      <div>
        <!-- Top Row: Badge, Title & Interactive Quick Play Button -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center gap-2">
            <span class="inline-flex items-center gap-1.5 rounded-full bg-[#2d2926] px-3.5 py-1 text-xs font-mono font-semibold text-[#faf8f5]">
              🎸 VIRTUAL FRETBOARD
            </span>
            <span class="text-xs font-serif text-[#8f6d2b]">22 品全息指板投影</span>
          </div>

          <!-- Quick Audition Sync Trigger Button -->
          <button
            type="button"
            onclick={toggleBentoAudition}
            class="inline-flex min-h-[44px] items-center gap-2 rounded-full border border-[#c49a45]/60 bg-[#ffffff] px-4 py-1.5 text-xs font-serif font-medium text-[#966b26] shadow-sm hover:border-[#c49a45] hover:bg-[#c49a45]/10 active:scale-95 transition-all cursor-pointer outline-none focus:outline-hidden"
          >
            {#if audition.isLoading && audition.currentTabId === demoTab.id}
              <div class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-[#966b26] border-t-transparent"></div>
              <span>加载曲谱…</span>
            {:else if audition.isPlaying && audition.currentTabId === demoTab.id}
              <span class="flex items-center gap-1 text-[#c84b31]">
                <span class="h-2 w-2 rounded-full bg-[#c84b31] animate-ping"></span>
                <span>⏸ 暂停《晴天》播放</span>
              </span>
            {:else}
              <span class="text-[#8f6d2b]">▶ 播放《晴天》曲谱</span>
            {/if}
          </button>
        </div>

        {#if audition.currentTabId === demoTab.id && audition.error}
          <div role="alert" class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[#9b3328]">
            <span>曲谱播放失败：{audition.error}</span>
            <a class="font-semibold underline underline-offset-2" href={'/tabs/' + demoTab.id}>打开《晴天》曲谱</a>
          </div>
        {/if}

        <h3 class="font-display text-xl sm:text-2xl font-bold text-[#2d2926] mt-4">
          同步指板动态发声与和弦指法提示
        </h3>
        <p class="text-xs sm:text-sm text-[#705c42] font-serif mt-1.5 max-w-xl leading-relaxed">
          播放乐谱时，虚拟指板实时跟随高亮发声音品，大横按、推弦、滑音一目了然，新手也能轻松跟练。
        </p>
      </div>

      <!-- Luxury Rosewood / Ebony 3D Guitar Fretboard Surface -->
      <div class="mt-6 rounded-2xl border border-[#44382c] bg-gradient-to-b from-[#181513] via-[#241f1a] to-[#141210] p-4 sm:p-5 shadow-[0_12px_32px_rgba(0,0,0,0.35)] relative overflow-hidden">
        <!-- Top Fretboard Header HUD -->
        <div class="flex flex-wrap items-center justify-between gap-2 text-xs font-mono pb-3 mb-3 border-b border-[#3d332a]">
          <div class="flex items-center gap-2.5">
            <span class="text-[#dfb55a] font-bold tracking-wider text-[11px]">● ACOUSTIC GUITAR FRETBOARD</span>
            {#if audition.isPlaying}
              <span class="inline-flex items-center gap-1 rounded-full bg-[#c84b31]/90 px-2 py-0.5 text-[10px] font-sans font-bold text-white shadow-sm animate-pulse">
                <span>♪</span>
                <span>同步发声中: {audition.currentTab?.title || '晴天'}</span>
              </span>
            {/if}
          </div>
          <div class="text-[10px] text-[#a89b8a] font-mono">
            STANDARD TUNING (E2 A2 D3 G3 B3 E4)
          </div>
        </div>

        <!-- Fret Numbers Header Row (Aligned with columns) -->
        <div class="flex items-center pl-16 pr-3 mb-1 text-[10px] font-mono text-[#a89b8a] select-none">
          {#each FRET_COLUMNS as col}
            <div class="flex-1 text-center truncate">
              {col.label}
            </div>
          {/each}
        </div>

        <!-- 6 Guitar Strings with Fret Dividers & Pearl Inlays -->
        <div class="relative pl-16 pr-3 py-1 select-none space-y-3.5">
          <!-- Metallic Vertical Fret Dividers (Nickel-Silver Wires) -->
          <div class="pointer-events-none absolute inset-0 left-16 right-3 flex justify-between">
            {#each FRET_COLUMNS as col, i}
              <div class="relative flex-1 border-r border-[#5c4a38]/70 flex items-center justify-center">
                <!-- Pearl Inlay Dot in Wood Body -->
                {#if col.hasDot}
                  {#if col.dotType === 'single'}
                    <div class="h-2 w-2 rounded-full bg-gradient-to-br from-[#ffffff] to-[#d6d3d1] shadow-[0_0_4px_rgba(255,255,255,0.6)] opacity-75"></div>
                  {:else if col.dotType === 'double'}
                    <div class="flex flex-col gap-5 items-center">
                      <div class="h-1.5 w-1.5 rounded-full bg-gradient-to-br from-[#ffffff] to-[#d6d3d1] shadow-[0_0_4px_rgba(255,255,255,0.6)] opacity-75"></div>
                      <div class="h-1.5 w-1.5 rounded-full bg-gradient-to-br from-[#ffffff] to-[#d6d3d1] shadow-[0_0_4px_rgba(255,255,255,0.6)] opacity-75"></div>
                    </div>
                  {/if}
                {/if}
              </div>
            {/each}
          </div>

          <!-- 6 Physical Strings -->
          {#each STRINGS as str}
            <div class="relative flex items-center justify-between h-5">
              <!-- Left String Name Label -->
              <span class="absolute -left-14 font-mono text-[10px] font-semibold text-[#c7beaf] tracking-tight">
                {str.name}
              </span>

              <!-- Horizontal Metallic String Wire -->
              <div class="absolute left-0 right-0 {str.height} {str.color} {str.shadow} rounded-full z-0"></div>

              <!-- Interactive / Dynamic Fret Note Hitboxes (0..12 Frets) -->
              <div class="relative z-10 w-full flex justify-between">
                {#each FRET_COLUMNS as col}
                  {@const active = isNoteActive(str.num, col.fret)}
                  <div class="flex-1 flex items-center justify-center">
                    <button
                      type="button"
                      onclick={() => manualFretNote = { string: str.num, fret: col.fret }}
                      class="relative flex h-6 w-6 items-center justify-center rounded-full transition-all cursor-pointer {active ? 'scale-110 z-20' : 'hover:bg-[#ffffff]/15'}"
                      title={`第 ${str.num} 弦 · ${col.fret} 品`}
                    >
                      {#if active}
                        <!-- Glowing Neon Aura -->
                        <span class="absolute inset-0 rounded-full bg-[#c84b31] opacity-75 animate-ping"></span>
                        <span class="relative flex h-5 w-5 items-center justify-center rounded-full bg-gradient-to-br from-[#e05638] to-[#b3361e] border border-white text-[9px] font-mono font-bold text-white shadow-[0_0_12px_#ff4a22]">
                          {col.fret}
                        </span>
                      {/if}
                    </button>
                  </div>
                {/each}
              </div>
            </div>
          {/each}
        </div>

        <!-- Fretboard Bottom Inlay Legend -->
        <div class="flex items-center justify-between text-[10px] font-mono text-[#8c7b68] mt-3 pt-2 border-t border-[#3d332a]/60">
          <span>点击任意品位可手动高亮指法</span>
          <div class="flex items-center gap-4">
            <span class="flex items-center gap-1">
              <span class="h-1.5 w-1.5 rounded-full bg-white opacity-80 inline-block"></span>
              <span>单音品位标记 (3/5/7/9品)</span>
            </span>
            <span class="flex items-center gap-1">
              <span class="h-1.5 w-1.5 rounded-full bg-white opacity-80 inline-block"></span>
              <span class="h-1.5 w-1.5 rounded-full bg-white opacity-80 inline-block"></span>
              <span>双品位八度标记 (12品)</span>
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>
