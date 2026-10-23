<script lang="ts">
  import { onMount } from 'svelte';
  import CodeBlock from './CodeBlock.svelte';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences.ts';

  // State
  let mousePos = $state({ x: 300, y: 150 });
  let spotlightRadius = $state(450);
  let spotlightOpacity = $state(12);
  let spotlightColor = $state<'signal' | 'ink' | 'ember'>('signal');
  let isHovering = $state(false);
  let isDarkMode = $state(false);
  let fullMotion = $state(false);
  let finePointerAvailable = $state(false);
  let hasPointerPosition = $state(false);

  function clearSpotlightTracking() {
    mousePos = { x: 0, y: 0 };
    isHovering = false;
    hasPointerPosition = false;
  }

  // Search Box State
  let searchQuery = $state('');
  let isSearchFocused = $state(false);
  let searchInputRef = $state<HTMLInputElement | null>(null);

  // CountUp Animated Numbers
  let countTabs = $state(0);
  let countArtists = $state(0);
  let countFidelity = $state(0);
  let isCounting = $state(false);
  let replayCountUpAction: (() => void) | null = null;

  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  const demoSuggestions = [
    { title: '晴天', artist: '周杰伦', type: '吉他弹唱', key: 'G 调', heat: '12.4万' },
    { title: '海阔天空', artist: 'Beyond', type: '六线电吉他', key: 'F 调', heat: '18.9万' },
    { title: '加州旅馆 (Hotel California)', artist: 'Eagles', type: '双吉他指弹', key: 'Bm 调', heat: '24.1万' },
    { title: '小手拉大手', artist: '梁静茹', type: '尤克里里弹唱', key: 'C 调', heat: '8.7万' },
    { title: '卡农 (Canon in D)', artist: 'Johann Pachelbel', type: '指弹独奏', key: 'D 调', heat: '31.2万' },
  ];

  let filteredSuggestions = $derived(
    searchQuery.trim()
      ? demoSuggestions.filter(
          (s) =>
            s.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
            s.artist.toLowerCase().includes(searchQuery.toLowerCase())
        )
      : demoSuggestions
  );

  // Mouse Move Handler
  function handleMouseMove(e: MouseEvent) {
    if (!fullMotion || !finePointerAvailable) return;
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    mousePos = {
      x: e.clientX - rect.left,
      y: e.clientY - rect.top,
    };
    isHovering = true;
    hasPointerPosition = true;
  }

  function handleMouseLeave() {
    isHovering = false;
  }

  // Count-up runs once only when full motion is allowed and the showcase is visible.
  let showcaseElement = $state<HTMLDivElement | null>(null);

  // Keyboard shortcut listener
  function handleKeydown(e: KeyboardEvent) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      searchInputRef?.focus();
    }
  }

  function startCountUp() {
    replayCountUpAction?.();
  }

  onMount(() => {
    const duration = 1500;
    const targetTabs = 12840;
    const targetArtists = 3520;
    const targetFidelity = 99.98;
    let animationFrameId: number | null = null;
    let startTime: number | null = null;
    let finished = false;
    let visibilityKnown = typeof IntersectionObserver === 'undefined';
    let inViewport = visibilityKnown;
    let observer: IntersectionObserver | null = null;
    let pointerQuery: MediaQueryList | null = null;

    function finishCountUp() {
      if (finished) return;
      finished = true;
      if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
      countTabs = targetTabs;
      countArtists = targetArtists;
      countFidelity = targetFidelity;
      isCounting = false;
    }

    function step(currentTime: number) {
      animationFrameId = null;
      if (finished) return;
      if (!fullMotion || document.hidden || !inViewport) {
        finishCountUp();
        return;
      }
      if (startTime === null) startTime = currentTime;
      const progress = Math.min((currentTime - startTime) / duration, 1);
      const ease = 1 - Math.pow(1 - progress, 3);
      countTabs = Math.floor(ease * targetTabs);
      countArtists = Math.floor(ease * targetArtists);
      countFidelity = Number((ease * targetFidelity).toFixed(2));
      if (progress < 1) animationFrameId = requestAnimationFrame(step);
      else finishCountUp();
    }

    function startCountUpOnce() {
      if (finished || animationFrameId !== null || !fullMotion || document.hidden || !visibilityKnown || !inViewport) return;
      startTime = null;
      isCounting = true;
      countTabs = 0;
      countArtists = 0;
      countFidelity = 0;
      animationFrameId = requestAnimationFrame(step);
    }

    function syncMotion() {
      if (!fullMotion || document.hidden) {
        finishCountUp();
        return;
      }
      startCountUpOnce();
    }

    function replayCountUp() {
      if (!fullMotion || document.hidden) {
        finishCountUp();
        return;
      }
      if (!visibilityKnown) {
        finished = false;
        startTime = null;
        return;
      }
      if (!inViewport) {
        finishCountUp();
        return;
      }
      if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
      finished = false;
      startTime = null;
      startCountUpOnce();
    }

    replayCountUpAction = replayCountUp;

    if (showcaseElement && typeof IntersectionObserver !== 'undefined') {
      visibilityKnown = false;
      inViewport = false;
      observer = new IntersectionObserver((entries) => {
        visibilityKnown = true;
        inViewport = entries[0]?.isIntersecting ?? false;
        if (!inViewport) {
          clearSpotlightTracking();
          finishCountUp();
        }
        else syncMotion();
      }, { threshold: 0.1 });
      observer.observe(showcaseElement);
    }

    try {
      pointerQuery = window.matchMedia('(pointer: fine)');
      finePointerAvailable = pointerQuery.matches;
    } catch {
      finePointerAvailable = false;
    }
    const handlePointerCapabilityChange = (event: MediaQueryListEvent) => {
      finePointerAvailable = event.matches;
      if (!finePointerAvailable) clearSpotlightTracking();
    };
    if (typeof pointerQuery?.addEventListener === 'function') {
      pointerQuery.addEventListener('change', handlePointerCapabilityChange);
    } else {
      pointerQuery?.addListener(handlePointerCapabilityChange);
    }

    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      fullMotion = mode === 'full';
      if (!fullMotion) clearSpotlightTracking();
      syncMotion();
    });

    const handleVisibilityChange = () => {
      if (document.hidden) {
        clearSpotlightTracking();
        finishCountUp();
      }
      else syncMotion();
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('keydown', handleKeydown);
    return () => {
      if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
      observer?.disconnect();
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('keydown', handleKeydown);
      if (typeof pointerQuery?.removeEventListener === 'function') {
        pointerQuery.removeEventListener('change', handlePointerCapabilityChange);
      } else {
        pointerQuery?.removeListener(handlePointerCapabilityChange);
      }
      unsubscribeMotion();
      replayCountUpAction = null;
    };
  });

  const spotlightColorRgb = $derived(
    spotlightColor === 'signal'
      ? '65, 161, 207'
      : spotlightColor === 'ember'
      ? '231, 0, 11'
      : '10, 10, 10'
  );

  const snippetCode = `<!-- Spotlight 光标跟随与 ⌘K 极速检索中心 -->
<div 
  class="spotlight-hero relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-[#fafafa] p-10"
  onmousemove={handleMouseMove}
>
  <!-- 光标跟随聚光灯渐变 (GPU 硬件加速) -->
  <div 
    class="pointer-events-none absolute inset-0 transition-opacity duration-300"
    style="
      background: radial-gradient(\${radius}px circle at \${mouseX}px \${mouseY}px, rgba(65, 161, 207, 0.08), transparent 60%);
      opacity: \${isHovering ? 1 : 0};
    "
  />

  <!-- 18px 胶囊极速搜索框 -->
  <div class="relative max-w-lg mx-auto">
    <input 
      type="search" 
      placeholder="搜索曲谱、歌手、吉他指弹..." 
      class="w-full rounded-[18px] border border-[#e5e5e5] bg-white px-4 py-3 pl-11 pr-14 text-sm outline-none focus:border-[#41a1cf] focus:ring-2 focus:ring-[#41a1cf]/20 transition-all"
    />
    <kbd class="absolute right-3 top-1/2 -translate-y-1/2 rounded-[8px] border border-[#e5e5e5] bg-[#f5f5f5] px-2 py-0.5 font-mono text-xs text-[#737373]">
      ⌘K
    </kbd>
  </div>
</div>`;

  const tokensSpec = `/* Refero UI Spotlight & Hero Tokens */
--spotlight-radius: 450px;
--spotlight-opacity: 0.08;
--spotlight-color: rgba(65, 161, 207, var(--spotlight-opacity));
--hero-padding: 2.5rem;
--radius-search: 18px;
--ease-count-up: cubic-bezier(0.16, 1, 0.3, 1);`;
</script>

<div bind:this={showcaseElement} class="space-y-8">
  <!-- Sub-Header & Switcher -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#41a1cf]"></span>
        MODULE 02 · 聚光灯与交互搜索中心
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">Hero Spotlight & 极速搜索 (Spotlight Mouse Follow)</h2>
      <p class="mt-1 text-sm text-[#737373]">
        毫秒级光标坐标追踪、18px 胶囊几何搜索聚焦、全局 <code>⌘K</code> 键盘唤醒与缓动数据翻牌。
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
      <!-- Main Spotlight Interactive Stage -->
      <div class="lg:col-span-8 space-y-6">
        <!-- Interactive Spotlight Hero Canvas -->
        <div
          role="region"
          aria-label="Spotlight 交互体验区"
          onmousemove={handleMouseMove}
          onmouseleave={handleMouseLeave}
          class="relative overflow-hidden rounded-[24px] border transition-all duration-300 p-8 sm:p-12 text-center select-none {isDarkMode ? 'bg-[#0a0a0a] border-[#2c2c2c] text-white' : 'bg-gradient-to-b from-[#ffffff] to-[#fafafa] border-[#e5e5e5] text-[#0a0a0a]'}"
        >
          <!-- Dynamic Cursor Radial Gradient -->
          <div
            class="pointer-events-none absolute inset-0 transition-opacity duration-300"
            style="
              background: radial-gradient(
                {spotlightRadius}px circle at {mousePos.x}px {mousePos.y}px,
                rgba({spotlightColorRgb}, {spotlightOpacity / 100}),
                transparent 65%
              );
              opacity: {fullMotion && finePointerAvailable && hasPointerPosition ? (isHovering ? 1 : 0.4) : 0};
            "
          ></div>

          <!-- Top Stage Tag -->
          <div class="relative z-10 mx-auto inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5]/80 bg-white/70 px-3.5 py-1 text-xs font-medium text-[#444141] shadow-xs backdrop-blur-md">
            <span class="h-2 w-2 rounded-full bg-[#41a1cf] animate-pulse"></span>
            <span>MIMI Spotlight Engine · 动态光标追踪</span>
            <span class="font-mono text-[11px] text-[#737373]">({Math.round(mousePos.x)}px, {Math.round(mousePos.y)}px)</span>
          </div>

          <!-- Hero Headline -->
          <h1 class="relative z-10 mt-6 font-display text-3xl sm:text-4xl lg:text-5xl tracking-tight leading-tight {isDarkMode ? 'text-white' : 'text-[#0a0a0a]'}">
            把每一份乐谱，<br class="hidden sm:inline" />
            都当作一页书来对待
          </h1>
          <p class="relative z-10 mx-auto mt-3 max-w-xl text-sm sm:text-base {isDarkMode ? 'text-[#a3a3a3]' : 'text-[#737373]'}">
            高保真矢量乐谱库 · 毫秒级即时检索 · WebAudio 智能伴奏内核
          </p>

          <!-- Interactive Search Box Center -->
          <div class="relative z-20 mx-auto mt-8 max-w-lg">
            <div class="relative">
              <div class="absolute left-3.5 top-1/2 -translate-y-1/2 text-[#737373] pointer-events-none">
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </div>

              <input
                bind:this={searchInputRef}
                type="search"
                bind:value={searchQuery}
                onfocus={() => (isSearchFocused = true)}
                onblur={() => setTimeout(() => (isSearchFocused = false), 200)}
                placeholder="搜索曲谱、歌手（支持拼音/首字母）..."
                class="w-full rounded-[18px] border bg-white/95 px-4 py-3 pl-10 pr-20 text-xs sm:text-sm text-[#0a0a0a] outline-none transition-all duration-300 {isSearchFocused ? 'border-[#41a1cf] ring-4 ring-[#41a1cf]/15 shadow-md' : 'border-[#e5e5e5] hover:border-[#b4b8b4] shadow-xs'}"
              />

              <button
                type="button"
                onclick={() => searchInputRef?.focus()}
                class="absolute right-2.5 top-1/2 -translate-y-1/2 inline-flex items-center gap-1 rounded-[10px] border border-[#e5e5e5] bg-[#f5f5f5] px-2 py-1 text-[11px] font-mono text-[#737373] hover:bg-[#e5e5e5]"
                title="按下 ⌘K 或 Ctrl+K 聚焦"
              >
                <span>⌘K</span>
              </button>
            </div>

            <!-- Instant Suggestions Dropdown -->
            {#if isSearchFocused || searchQuery.trim()}
              <div class="absolute left-0 right-0 top-full mt-2 overflow-hidden rounded-[20px] border border-[#e5e5e5] bg-white/98 p-2 text-left shadow-xl backdrop-blur-xl animate-stagger-in z-30">
                <div class="px-3 py-1.5 text-[11px] font-medium text-[#737373] flex justify-between">
                  <span>实时匹配曲谱 ({filteredSuggestions.length})</span>
                  <span>按回车进入详情</span>
                </div>
                <div class="space-y-1 mt-1">
                  {#each filteredSuggestions as item}
                    <div
                      class="flex items-center justify-between rounded-[14px] px-3 py-2 text-xs transition hover:bg-[#f5f5f5] cursor-pointer"
                    >
                      <div class="flex items-center gap-2.5 min-w-0">
                        <span class="flex h-6 w-6 items-center justify-center rounded-[8px] bg-[#f5f5f5] text-[11px]">🎸</span>
                        <div class="truncate">
                          <span class="font-medium text-[#0a0a0a]">{item.title}</span>
                          <span class="text-[#737373] ml-1.5">- {item.artist}</span>
                        </div>
                      </div>
                      <div class="flex items-center gap-2 shrink-0">
                        <span class="rounded-[8px] bg-[#f5f5f5] px-2 py-0.5 text-[10px] text-[#444141]">{item.type}</span>
                        <span class="text-[10px] text-[#41a1cf]">{item.key}</span>
                        <span class="text-[10px] text-[#737373] font-mono">{item.heat}</span>
                      </div>
                    </div>
                  {/each}
                </div>
              </div>
            {/if}
          </div>

          <!-- Metric CountUp Counters Grid -->
          <div class="relative z-10 mt-12 grid grid-cols-1 gap-4 sm:grid-cols-3 border-t border-[#e5e5e5]/80 pt-8">
            <div class="rounded-[18px] border border-[#e5e5e5]/60 bg-white/60 p-4 backdrop-blur-xs">
              <div class="font-mono text-2xl sm:text-3xl font-bold tracking-tight text-[#0a0a0a]">
                {countTabs.toLocaleString()}<span class="text-[#41a1cf] text-xl font-normal">+</span>
              </div>
              <p class="mt-1 text-xs text-[#737373]">已收录高清多轨吉他谱</p>
            </div>

            <div class="rounded-[18px] border border-[#e5e5e5]/60 bg-white/60 p-4 backdrop-blur-xs">
              <div class="font-mono text-2xl sm:text-3xl font-bold tracking-tight text-[#0a0a0a]">
                {countArtists.toLocaleString()}<span class="text-[#0a0a0a] text-xl font-normal">位</span>
              </div>
              <p class="mt-1 text-xs text-[#737373]">原创创作者与制谱师入驻</p>
            </div>

            <div class="rounded-[18px] border border-[#e5e5e5]/60 bg-white/60 p-4 backdrop-blur-xs">
              <div class="font-mono text-2xl sm:text-3xl font-bold tracking-tight text-[#0a0a0a]">
                {countFidelity}%
              </div>
              <p class="mt-1 text-xs text-[#737373]">AlphaTab 矢量乐谱渲染率</p>
            </div>
          </div>
        </div>
      </div>

      <!-- Right: Parameter Controller -->
      <div class="lg:col-span-4 space-y-5">
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs">
          <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 聚光灯与搜索参数</h3>
          <p class="mt-1 text-xs text-[#737373]">控制鼠标光斑半径、透明度与色调体系。</p>

          <div class="mt-5 space-y-4 text-xs">
            <!-- Radius Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>聚光灯半径 (Spotlight Radius)</span>
                <span class="font-mono text-[#0a0a0a]">{spotlightRadius}px</span>
              </div>
              <input
                type="range"
                min="200"
                max="700"
                step="25"
                bind:value={spotlightRadius}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
              <div class="flex justify-between text-[10px] text-[#a3a3a3]">
                <span>200px (聚拢)</span>
                <span>450px (柔和)</span>
                <span>700px (漫反射)</span>
              </div>
            </div>

            <!-- Opacity Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>光晕强度 (Spotlight Opacity)</span>
                <span class="font-mono text-[#0a0a0a]">{spotlightOpacity}%</span>
              </div>
              <input
                type="range"
                min="3"
                max="30"
                step="1"
                bind:value={spotlightOpacity}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
              <div class="flex justify-between text-[10px] text-[#a3a3a3]">
                <span>3% (极微)</span>
                <span>12% (标准)</span>
                <span>30% (明亮)</span>
              </div>
            </div>

            <!-- Color Palette Selector -->
            <div>
              <span class="font-medium text-[#444141]">光晕基调颜色</span>
              <div class="mt-2 grid grid-cols-3 gap-2">
                <button
                  type="button"
                  onclick={() => (spotlightColor = 'signal')}
                  class="flex items-center justify-center gap-1.5 rounded-[14px] border p-2 text-center text-xs font-medium transition {spotlightColor === 'signal' ? 'border-[#41a1cf] bg-[#41a1cf]/10 text-[#0081c0]' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  <span class="h-2.5 w-2.5 rounded-full bg-[#41a1cf]"></span>
                  <span>Signal</span>
                </button>
                <button
                  type="button"
                  onclick={() => (spotlightColor = 'ink')}
                  class="flex items-center justify-center gap-1.5 rounded-[14px] border p-2 text-center text-xs font-medium transition {spotlightColor === 'ink' ? 'border-[#0a0a0a] bg-[#0a0a0a]/10 text-[#0a0a0a]' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  <span class="h-2.5 w-2.5 rounded-full bg-[#0a0a0a]"></span>
                  <span>Ink</span>
                </button>
                <button
                  type="button"
                  onclick={() => (spotlightColor = 'ember')}
                  class="flex items-center justify-center gap-1.5 rounded-[14px] border p-2 text-center text-xs font-medium transition {spotlightColor === 'ember' ? 'border-[#e7000b] bg-[#e7000b]/10 text-[#e7000b]' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  <span class="h-2.5 w-2.5 rounded-full bg-[#e7000b]"></span>
                  <span>Ember</span>
                </button>
              </div>
            </div>

            <!-- Replay CountUp Button -->
            <div class="border-t border-[#e5e5e5] pt-3 space-y-2">
              <button
                type="button"
                onclick={startCountUp}
                disabled={isCounting}
                class="w-full inline-flex items-center justify-center gap-2 rounded-[18px] bg-[#0a0a0a] py-2 text-xs font-medium text-white shadow-xs transition hover:bg-[#2c2c2c] active:scale-95 disabled:opacity-50"
              >
                <svg class="h-3.5 w-3.5 {isCounting ? 'animate-spin' : ''}" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                <span>{isCounting ? '正在平滑计算...' : '重新触发数字翻牌 (Replay CountUp)'}</span>
              </button>

              <button
                type="button"
                onclick={() => searchInputRef?.focus()}
                class="w-full rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] py-2 text-xs font-medium text-[#0a0a0a] hover:bg-[#f5f5f5]"
              >
                🔍 测试 ⌘K 快捷聚焦检索
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="HeroSpotlight.svelte (Spotlight Mouse Tracking)" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Hero & Search Tokens" />
  {/if}
</div>
