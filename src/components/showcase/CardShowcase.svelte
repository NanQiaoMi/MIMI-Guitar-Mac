<script lang="ts">
  import { onMount } from 'svelte';
  import CodeBlock from './CodeBlock.svelte';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences';

  // Sample tab cards data
  const sampleTabs = [
    {
      id: 'tab-1',
      title: '晴天 (Sunny Day)',
      artist: '周杰伦 · Jay Chou',
      key: 'G',
      sheetForm: '吉他弹唱',
      difficulty: 2,
      difficultyLabel: '初级',
      heat: '14.8万',
      bpm: 104,
      tuning: 'Standard E',
      tag: '热门经典',
      coverBg: 'from-[#0a0a0a] to-[#2c2c2c]',
      icon: '🎸',
    },
    {
      id: 'tab-2',
      title: '加州旅馆 (Hotel California)',
      artist: 'Eagles',
      key: 'Bm',
      sheetForm: '双吉他指弹',
      difficulty: 4,
      difficultyLabel: '高级',
      heat: '28.3万',
      bpm: 76,
      tuning: 'Standard E',
      tag: '大师独奏',
      coverBg: 'from-[#282834] to-[#1f1f29]',
      icon: '🦅',
    },
    {
      id: 'tab-3',
      title: '海阔天空 (Boundless Oceans)',
      artist: 'Beyond',
      key: 'F',
      sheetForm: '电吉他六线谱',
      difficulty: 3,
      difficultyLabel: '中级',
      heat: '19.5万',
      bpm: 68,
      tuning: 'Standard E',
      tag: '摇滚殿堂',
      coverBg: 'from-[#171717] to-[#444141]',
      icon: '🌊',
    },
    {
      id: 'tab-4',
      title: '小手拉大手 (Give Me Your Hand)',
      artist: '梁静茹',
      key: 'C',
      sheetForm: '尤克里里弹唱',
      difficulty: 1,
      difficultyLabel: '零基础',
      heat: '9.2万',
      bpm: 120,
      tuning: 'G C E A',
      tag: '尤克里里',
      coverBg: 'from-[#41a1cf]/30 to-[#0081c0]/20',
      icon: '🌴',
    },
    {
      id: 'tab-5',
      title: '风之诗 (Wind Song)',
      artist: '押尾光太郎 (Kotaro Oshio)',
      key: 'D',
      sheetForm: '原声指弹',
      difficulty: 5,
      difficultyLabel: '专业大师',
      heat: '21.4万',
      bpm: 82,
      tuning: 'DADGAD',
      tag: '指弹天花板',
      coverBg: 'from-[#e7000b]/20 to-[#0a0a0a]',
      icon: '🍃',
    },
    {
      id: 'tab-6',
      title: '卡农 (Canon in D)',
      artist: 'Johann Pachelbel',
      key: 'D',
      sheetForm: '指弹独奏',
      difficulty: 3,
      difficultyLabel: '中级',
      heat: '32.1万',
      bpm: 72,
      tuning: 'Drop D',
      tag: '古典改编',
      coverBg: 'from-[#2c2c2c] to-[#0a0a0a]',
      icon: '🎻',
    },
  ];

  // Interactive controls
  let maxTilt = $state(12); // degrees
  let enableHoloFoil = $state(true);
  let holoTheme = $state<'prismatic' | 'cerulean' | 'gold' | 'emerald' | 'ember'>('prismatic');
  let holoFlareRadius = $state(380);
  let staggerDelay = $state(45); // ms
  let layoutMode = $state<'bento' | 'grid' | 'list'>('bento');
  let animationKey = $state(0);
  let activePlayingTab = $state<string | null>(null);
  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  const holoThemes: Record<string, { flare: string; foil: string }> = {
    prismatic: {
      flare: 'rgba(65, 161, 207, 0.25)',
      foil: 'linear-gradient(135deg, transparent 15%, rgba(65, 161, 207, 0.25) 30%, rgba(231, 0, 11, 0.18) 48%, rgba(245, 158, 11, 0.2) 65%, rgba(6, 182, 212, 0.25) 82%, transparent 95%)',
    },
    cerulean: {
      flare: 'rgba(65, 161, 207, 0.35)',
      foil: 'linear-gradient(135deg, transparent 20%, rgba(65, 161, 207, 0.35) 45%, rgba(0, 129, 192, 0.3) 65%, transparent 90%)',
    },
    gold: {
      flare: 'rgba(245, 158, 11, 0.3)',
      foil: 'linear-gradient(135deg, transparent 15%, rgba(245, 158, 11, 0.35) 35%, rgba(254, 240, 138, 0.45) 55%, rgba(217, 119, 6, 0.3) 75%, transparent 95%)',
    },
    emerald: {
      flare: 'rgba(16, 185, 129, 0.3)',
      foil: 'linear-gradient(135deg, transparent 15%, rgba(16, 185, 129, 0.35) 40%, rgba(52, 211, 153, 0.4) 60%, rgba(5, 150, 105, 0.3) 80%, transparent 95%)',
    },
    ember: {
      flare: 'rgba(231, 0, 11, 0.25)',
      foil: 'linear-gradient(135deg, transparent 15%, rgba(231, 0, 11, 0.3) 35%, rgba(249, 115, 22, 0.35) 55%, rgba(225, 29, 72, 0.3) 75%, transparent 95%)',
    },
  };

  const currentHolo = $derived(holoThemes[holoTheme] || holoThemes.prismatic);

  // Track per-card 3D tilt coordinates
  type CardTransform = { rotateX: number; rotateY: number; mouseX: number; mouseY: number; hovering: boolean };
  let cardTransforms = $state<Record<string, CardTransform>>({});
  let fullTiltEnabled = $state(false);

  function cardTransformStyle(transform: CardTransform): string {
    if (!fullTiltEnabled) return 'none';
    return `perspective(1000px) rotateX(${transform.rotateX}deg) rotateY(${transform.rotateY}deg) translateY(${transform.hovering ? -4 : 0}px)`;
  }

  onMount(() => {
    const pointerQuery = window.matchMedia('(hover: hover) and (pointer: fine)');
    let fullMotionPreference = false;

    const syncTiltAvailability = () => {
      fullTiltEnabled = fullMotionPreference && pointerQuery.matches;
      if (!fullTiltEnabled) cardTransforms = {};
    };

    pointerQuery.addEventListener('change', syncTiltAvailability);
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      fullMotionPreference = mode === 'full';
      syncTiltAvailability();
    });

    return () => {
      unsubscribeMotion();
      pointerQuery.removeEventListener('change', syncTiltAvailability);
      fullTiltEnabled = false;
      cardTransforms = {};
    };
  });

  function handleCardMouseMove(e: MouseEvent, cardId: string) {
    if (!fullTiltEnabled) return;

    const cardEl = e.currentTarget as HTMLElement;
    const rect = cardEl.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const centerX = rect.width / 2;
    const centerY = rect.height / 2;

    const rotateX = ((y - centerY) / centerY) * -maxTilt;
    const rotateY = ((x - centerX) / centerX) * maxTilt;

    cardTransforms[cardId] = {
      rotateX,
      rotateY,
      mouseX: x,
      mouseY: y,
      hovering: true,
    };
  }

  function handleCardMouseLeave(cardId: string) {
    if (!fullTiltEnabled) return;

    cardTransforms[cardId] = {
      rotateX: 0,
      rotateY: 0,
      mouseX: -500,
      mouseY: -500,
      hovering: false,
    };
  }

  function retriggerStagger() {
    animationKey += 1;
  }

  function togglePlayPreview(id: string) {
    activePlayingTab = activePlayingTab === id ? null : id;
  }

  const featuredTab = $derived(sampleTabs[1]);
  const featuredCardTransform = $derived(
    cardTransforms[sampleTabs[1].id] || { rotateX: 0, rotateY: 0, mouseX: -500, mouseY: -500, hovering: false }
  );

  const snippetCode = `<!-- 3D Holographic Card Shimmer (.holo-card & .holo-foil) -->
<div 
  class="holo-card relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-white p-6 transition-all duration-200"
  style="
    transform: perspective(1000px) rotateX(\${rotateX}deg) rotateY(\${rotateY}deg) translateY(\${hovering ? -3 : 0}px);
    --mouse-x: \${mouseX}px;
    --mouse-y: \${mouseY}px;
    --holo-rotate-x: \${rotateX}deg;
    --holo-rotate-y: \${rotateY}deg;
  "
  onmousemove={handleMouseMove}
  onmouseleave={handleMouseLeave}
>
  <!-- 全息折射彩虹箔面覆层 (.holo-foil) -->
  <div 
    class="holo-foil"
    style="
      background: radial-gradient(\${flareRadius}px circle at var(--mouse-x) var(--mouse-y), rgba(65, 161, 207, 0.25), transparent 60%);
    "
  />

  <div class="relative z-10">
    <h3 class="font-display text-lg text-[#0a0a0a]">{tab.title}</h3>
    <p class="text-xs text-[#737373]">{tab.artist}</p>
  </div>
</div>`;

  const tokensSpec = `/* Refero UI TabCard & Holographic Foil Tokens */
--radius-card: 24px;
--card-border: 1px solid var(--color-hairline);
--shadow-card-default: 0 0 0 1px rgba(23, 23, 23, 0.04), 0 1px 3px rgba(0, 0, 0, 0.06);
--shadow-card-hover: 0 0 0 1px rgba(65, 161, 207, 0.25), 0 16px 36px -8px rgba(0, 0, 0, 0.1), 0 4px 12px -2px rgba(65, 161, 207, 0.08);
--holo-flare-gradient: radial-gradient(circle at var(--mouse-x) var(--mouse-y), rgba(65, 161, 207, 0.25), transparent 60%);
--tilt-perspective: 1200px;
--stagger-interval: 40ms;`;
</script>

<div class="space-y-8">
  <!-- Sub-Header & Switcher -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#41a1cf]"></span>
        MODULE 03 · 24px 卡片视差与 3D 全息反射
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">TabCard & Bento 矩阵 (Holographic Foil & 3D Tilt)</h2>
      <p class="mt-1 text-sm text-[#737373]">
        24px 极致卡片倒角、3D 全息彩虹反射 (.holo-card & .holo-foil)、发丝边框光晕吸附、3D 空间动态倾角与 40ms 级联淡入。
      </p>
    </div>

    <!-- View Switcher Tabs -->
    <div class="flex items-center rounded-[18px] border border-[#e5e5e5] bg-[#f5f5f5] p-1 text-xs font-medium">
      <button
        type="button"
        onclick={() => (activeTab = 'preview')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'preview' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        🌟 交互演示
      </button>
      <button
        type="button"
        onclick={() => (activeTab = 'code')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'code' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        💻 示例源码
      </button>
      <button
        type="button"
        onclick={() => (activeTab = 'tokens')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'tokens' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        📐 Token 规范
      </button>
    </div>
  </div>

  {#if activeTab === 'preview'}
    <div class="grid grid-cols-1 gap-6 lg:grid-cols-12">
      <!-- Main Cards Display Area -->
      <div class="lg:col-span-8 space-y-6">
        <!-- Layout Toolbar -->
        <div class="flex flex-wrap items-center justify-between gap-3 rounded-[20px] border border-[#e5e5e5] bg-[#fafafa] p-3 text-xs">
          <div class="flex items-center gap-2">
            <span class="font-medium text-[#444141]">布局模式:</span>
            <div class="flex items-center rounded-[14px] border border-[#e5e5e5] bg-white p-0.5">
              <button
                type="button"
                onclick={() => (layoutMode = 'bento')}
                class="rounded-[10px] px-2.5 py-1 font-medium transition {layoutMode === 'bento' ? 'bg-[#0a0a0a] text-white' : 'text-[#737373] hover:text-[#0a0a0a]'}"
              >
                🍱 Bento 矩阵
              </button>
              <button
                type="button"
                onclick={() => (layoutMode = 'grid')}
                class="rounded-[10px] px-2.5 py-1 font-medium transition {layoutMode === 'grid' ? 'bg-[#0a0a0a] text-white' : 'text-[#737373] hover:text-[#0a0a0a]'}"
              >
                📐 标准网格
              </button>
              <button
                type="button"
                onclick={() => (layoutMode = 'list')}
                class="rounded-[10px] px-2.5 py-1 font-medium transition {layoutMode === 'list' ? 'bg-[#0a0a0a] text-white' : 'text-[#737373] hover:text-[#0a0a0a]'}"
              >
                📋 紧凑列表
              </button>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="button"
              onclick={retriggerStagger}
              class="inline-flex items-center gap-1.5 rounded-[14px] border border-[#e5e5e5] bg-white px-3 py-1.5 font-medium text-[#0a0a0a] shadow-xs hover:bg-[#f5f5f5] active:scale-95"
            >
              <svg class="h-3.5 w-3.5 text-[#41a1cf]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              <span>重播级联淡入 ({staggerDelay}ms)</span>
            </button>
          </div>
        </div>

        <!-- Cards Container (Keyed for re-animation) -->
        {#key animationKey}
          {#if layoutMode === 'bento'}
            <!-- BENTO MATRIX VIEW -->
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <!-- Large Featured Bento Card (Spans 2 cols) with Holographic Foil -->
              <div
                class="sm:col-span-2 holo-card relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-white p-6 transition-all duration-200 animate-stagger-in shadow-xs select-none"
                style="
                  animation-delay: 0ms;
                  --holo-rotate-x: {featuredCardTransform.rotateX}deg;
                  --holo-rotate-y: {featuredCardTransform.rotateY}deg;
                  --mouse-x: {featuredCardTransform.mouseX}px;
                  --mouse-y: {featuredCardTransform.mouseY}px;
                  transform: {cardTransformStyle(featuredCardTransform)};
                "
                onmousemove={(e) => handleCardMouseMove(e, featuredTab.id)}
                onmouseleave={() => handleCardMouseLeave(featuredTab.id)}
              >
                <!-- Holographic Iridescent Foil Overlay -->
                {#if enableHoloFoil}
                  <div
                    class="holo-foil"
                    style="
                      background: radial-gradient({holoFlareRadius}px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), {currentHolo.flare}, transparent 60%);
                    "
                  ></div>
                {/if}

                <div class="relative z-10 flex flex-col justify-between h-full gap-6">
                  <div class="flex items-start justify-between">
                    <div>
                      <div class="inline-flex items-center gap-1.5 rounded-[14px] bg-[#0a0a0a] px-2.5 py-0.5 text-[10px] font-medium text-white">
                        <span>🔥 极高热度 · HOLOGRAPHIC MASTER</span>
                      </div>
                      <h3 class="mt-2 font-display text-xl sm:text-2xl text-[#0a0a0a]">{featuredTab.title}</h3>
                      <p class="text-xs text-[#737373] mt-0.5">{featuredTab.artist}</p>
                    </div>

                    <button
                      type="button"
                      onclick={() => togglePlayPreview(featuredTab.id)}
                      class="flex h-10 w-10 items-center justify-center rounded-full bg-[#0a0a0a] text-white shadow-md transition-all hover:scale-105 active:scale-95"
                      aria-label="试听乐谱伴奏"
                    >
                      {#if activePlayingTab === featuredTab.id}
                        <span class="h-3.5 w-3.5 flex items-center justify-center">⏸</span>
                      {:else}
                        <span class="h-3.5 w-3.5 flex items-center justify-center">▶</span>
                      {/if}
                    </button>
                  </div>

                  <!-- Mini Waveform Visualizer & Meta -->
                  <div class="rounded-[18px] border border-[#e5e5e5] bg-[#fafafa]/80 backdrop-blur-xs p-3">
                    <div class="flex items-center justify-between text-xs text-[#737373] mb-2">
                      <span class="font-mono">AlphaTab Audio Preview</span>
                      <span class="font-mono">{featuredTab.bpm} BPM · {featuredTab.tuning}</span>
                    </div>

                    <!-- Equalizer Bars -->
                    <div class="flex items-end gap-1 h-8 px-1">
                      {#each Array(24) as _, i}
                        <div
                          class="w-full rounded-full transition-all duration-300"
                          style="
                            height: {activePlayingTab === featuredTab.id ? `${20 + Math.sin(i * 0.8 + Date.now() * 0.005) * 60 + 20}%` : `${15 + (i % 5) * 12}%`};
                            background-color: {activePlayingTab === featuredTab.id ? '#41a1cf' : '#dee2de'};
                          "
                        ></div>
                      {/each}
                    </div>
                  </div>

                  <!-- Bottom Pills -->
                  <div class="flex flex-wrap items-center justify-between gap-2 border-t border-[#e5e5e5] pt-3 text-xs">
                    <div class="flex items-center gap-2">
                      <span class="rounded-[12px] border border-[#e5e5e5] bg-white px-2 py-0.5 font-medium text-[#0a0a0a]">{featuredTab.sheetForm}</span>
                      <span class="rounded-[12px] bg-[#f5f5f5] px-2 py-0.5 font-mono text-[#41a1cf]">{featuredTab.key} 调</span>
                    </div>
                    <span class="font-mono text-[#737373]">{featuredTab.heat} 播放</span>
                  </div>
                </div>
              </div>

              <!-- Other Bento Cards with Holographic Foil -->
              {#each sampleTabs.slice(0, 5) as tab, idx}
                {#if tab.id !== featuredTab.id}
                  {@const t = cardTransforms[tab.id] || { rotateX: 0, rotateY: 0, mouseX: -500, mouseY: -500, hovering: false }}
                  <div
                    class="holo-card relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-white p-5 transition-all duration-200 animate-stagger-in shadow-xs select-none flex flex-col justify-between"
                    style="
                      animation-delay: {(idx + 1) * staggerDelay}ms;
                      --holo-rotate-x: {t.rotateX}deg;
                      --holo-rotate-y: {t.rotateY}deg;
                      --mouse-x: {t.mouseX}px;
                      --mouse-y: {t.mouseY}px;
                      transform: {cardTransformStyle(t)};
                    "
                    onmousemove={(e) => handleCardMouseMove(e, tab.id)}
                    onmouseleave={() => handleCardMouseLeave(tab.id)}
                  >
                    <!-- Holographic Foil Overlay -->
                    {#if enableHoloFoil}
                      <div
                        class="holo-foil"
                        style="
                          background: radial-gradient({holoFlareRadius}px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), {currentHolo.flare}, transparent 60%);
                        "
                      ></div>
                    {/if}

                    <div class="relative z-10">
                      <div class="flex items-center justify-between">
                        <span class="flex h-8 w-8 items-center justify-center rounded-[12px] bg-[#f5f5f5] text-sm">
                          {tab.icon}
                        </span>
                        <span class="rounded-[10px] bg-[#fafafa] border border-[#e5e5e5] px-2 py-0.5 text-[10px] font-mono text-[#737373]">
                          {tab.tag}
                        </span>
                      </div>

                      <h4 class="mt-3 font-display text-base text-[#0a0a0a] line-clamp-1">{tab.title}</h4>
                      <p class="text-xs text-[#737373] line-clamp-1">{tab.artist}</p>

                      <!-- 5-bar Difficulty Indicator -->
                      <div class="mt-4 flex items-center justify-between border-t border-[#e5e5e5]/80 pt-3 text-[11px]">
                        <div class="flex items-center gap-1">
                          <span class="text-[#737373] mr-1">难度:</span>
                          {#each Array(5) as _, barIdx}
                            <span
                              class="h-2 w-2 rounded-full transition-colors"
                              style="background-color: {barIdx < tab.difficulty ? (tab.difficulty >= 4 ? '#e7000b' : '#41a1cf') : '#dee2de'};"
                            ></span>
                          {/each}
                        </div>
                        <span class="font-mono text-[#0a0a0a]">{tab.key} 调</span>
                      </div>
                    </div>
                  </div>
                {/if}
              {/each}
            </div>
          {:else if layoutMode === 'grid'}
            <!-- STANDARD 3-COL GRID -->
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {#each sampleTabs as tab, idx}
                {@const t = cardTransforms[tab.id] || { rotateX: 0, rotateY: 0, mouseX: -500, mouseY: -500, hovering: false }}
                <div
                  class="holo-card relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-white p-5 transition-all duration-200 animate-stagger-in shadow-xs select-none"
                  style="
                    animation-delay: {idx * staggerDelay}ms;
                    --holo-rotate-x: {t.rotateX}deg;
                    --holo-rotate-y: {t.rotateY}deg;
                    --mouse-x: {t.mouseX}px;
                    --mouse-y: {t.mouseY}px;
                    transform: {cardTransformStyle(t)};
                  "
                  onmousemove={(e) => handleCardMouseMove(e, tab.id)}
                  onmouseleave={() => handleCardMouseLeave(tab.id)}
                >
                  {#if enableHoloFoil}
                    <div
                      class="holo-foil"
                      style="
                        background: radial-gradient({holoFlareRadius}px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), {currentHolo.flare}, transparent 60%);
                      "
                    ></div>
                  {/if}

                  <div class="relative z-10">
                    <div class="flex items-center justify-between">
                      <span class="flex h-8 w-8 items-center justify-center rounded-[12px] bg-[#f5f5f5] text-sm">
                        {tab.icon}
                      </span>
                      <span class="rounded-[12px] bg-[#f5f5f5] px-2 py-0.5 font-mono text-[10px] text-[#41a1cf]">
                        {tab.key} 调
                      </span>
                    </div>

                    <h4 class="mt-3 font-display text-base text-[#0a0a0a] line-clamp-1">{tab.title}</h4>
                    <p class="text-xs text-[#737373] line-clamp-1">{tab.artist}</p>

                    <div class="mt-4 flex items-center justify-between border-t border-[#e5e5e5] pt-3 text-xs">
                      <span class="text-[11px] text-[#737373]">{tab.sheetForm}</span>
                      <span class="font-mono text-[11px] text-[#737373]">{tab.heat}</span>
                    </div>
                  </div>
                </div>
              {/each}
            </div>
          {:else}
            <!-- COMPACT LIST VIEW -->
            <div class="space-y-2">
              {#each sampleTabs as tab, idx}
                <div
                  class="flex items-center justify-between rounded-[18px] border border-[#e5e5e5] bg-white p-3.5 transition hover:border-[#41a1cf] hover:shadow-xs animate-stagger-in select-none"
                  style="animation-delay: {idx * staggerDelay}ms;"
                >
                  <div class="flex items-center gap-3">
                    <span class="flex h-8 w-8 items-center justify-center rounded-[10px] bg-[#f5f5f5] text-sm">
                      {tab.icon}
                    </span>
                    <div>
                      <h4 class="font-medium text-xs text-[#0a0a0a]">{tab.title}</h4>
                      <p class="text-[11px] text-[#737373]">{tab.artist}</p>
                    </div>
                  </div>

                  <div class="flex items-center gap-3 text-xs">
                    <span class="rounded-[10px] border border-[#e5e5e5] bg-[#fafafa] px-2 py-0.5 text-[10px] text-[#444141]">{tab.sheetForm}</span>
                    <span class="font-mono text-[#41a1cf]">{tab.key} 调</span>
                    <span class="font-mono text-[#737373] text-[11px]">{tab.heat}</span>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        {/key}
      </div>

      <!-- Right: Card Controls -->
      <div class="lg:col-span-4 space-y-5">
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs">
          <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 卡片物理与全息视差</h3>
          <p class="mt-1 text-xs text-[#737373]">微调 3D 空间倾角、全息箔面反射与级联进场速度。</p>

          <div class="mt-5 space-y-4 text-xs">
            <!-- 3D Tilt Angle Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>3D 最大倾斜角度 (Max Tilt)</span>
                <span class="font-mono text-[#0a0a0a]">±{maxTilt}°</span>
              </div>
              <input
                type="range"
                min="0"
                max="25"
                step="1"
                bind:value={maxTilt}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
            </div>

            <!-- Flare Radius Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>全息光斑折射半径</span>
                <span class="font-mono text-[#0a0a0a]">{holoFlareRadius}px</span>
              </div>
              <input
                type="range"
                min="200"
                max="600"
                step="20"
                bind:value={holoFlareRadius}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
            </div>

            <!-- Holo Theme Palette -->
            <div>
              <span class="font-medium text-[#444141]">全息箔面材质</span>
              <div class="mt-2 grid grid-cols-2 gap-1.5">
                {#each [
                  { id: 'prismatic', label: '🌈 全息棱镜' },
                  { id: 'cerulean', label: '🌊 信号蓝光' },
                  { id: 'gold', label: '✨ 稀有金箔' },
                  { id: 'emerald', label: '🍃 翡翠光晕' },
                  { id: 'ember', label: '🔥 炽焰流光' },
                ] as t}
                  <button
                    type="button"
                    onclick={() => (holoTheme = t.id as any)}
                    class="rounded-[10px] border p-1.5 text-center text-xs font-medium transition {holoTheme === t.id ? 'border-[#0a0a0a] bg-[#0a0a0a] text-white' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                  >
                    {t.label}
                  </button>
                {/each}
              </div>
            </div>

            <!-- Holographic Foil Switch -->
            <div class="flex items-center justify-between border-t border-[#e5e5e5] pt-3">
              <div>
                <span class="font-medium text-[#0a0a0a]">全息彩虹折射箔面</span>
                <p class="text-[11px] text-[#737373]">.holo-foil 虹彩反光与折射</p>
              </div>
              <button
                type="button"
                onclick={() => (enableHoloFoil = !enableHoloFoil)}
                class="relative h-6 w-11 rounded-full transition-colors duration-200 {enableHoloFoil ? 'bg-[#0a0a0a]' : 'bg-[#dee2de]'}"
              >
                <span class="absolute top-1 left-1 h-4 w-4 rounded-full bg-white transition-transform duration-200 {enableHoloFoil ? 'translate-x-5' : 'translate-x-0'}"></span>
              </button>
            </div>

            <!-- Trigger Button -->
            <div class="border-t border-[#e5e5e5] pt-3">
              <button
                type="button"
                onclick={retriggerStagger}
                class="w-full inline-flex items-center justify-center gap-2 rounded-[18px] bg-[#0a0a0a] py-2 text-xs font-medium text-white shadow-xs transition hover:bg-[#2c2c2c] active:scale-95"
              >
                <span>⚡ 重新触发级联进场动画</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="TabCard3D.svelte" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Card & Stagger Tokens" />
  {/if}
</div>
