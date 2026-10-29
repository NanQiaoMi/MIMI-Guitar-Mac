<script lang="ts">
  import CodeBlock from './CodeBlock.svelte';

  // Navigation Items
  const navItems = [
    { id: 'home', label: '首页', href: '#home' },
    { id: 'guitar', label: '吉他谱', href: '#guitar' },
    { id: 'ukulele', label: '尤克里里', href: '#ukulele' },
    { id: 'articles', label: '文章专栏', href: '#articles' },
    { id: 'library', label: '曲谱库', href: '#library', hasMenu: true },
  ];

  let activeItem = $state('home');
  let hoveredItem = $state<string | null>(null);
  let indicatorStyle = $state({ left: 0, width: 0, opacity: 0 });
  let navContainerRef = $state<HTMLElement | null>(null);

  // Controls
  let blurAmount = $state(16);
  let bgOpacity = $state(78);
  let enableBorderGlow = $state(true);
  let indicatorTheme = $state<'dark' | 'signal' | 'frosted'>('dark');
  let isMobileDrawerOpen = $state(false);
  let isAccountMenuOpen = $state(false);
  let isUploadMenuOpen = $state(false);
  let searchQuery = $state('');
  let isSearchFocused = $state(false);
  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  // Update sliding indicator position
  function updateIndicator(targetId: string | null) {
    if (!navContainerRef) return;
    const currentId = targetId || activeItem;
    const targetEl = navContainerRef.querySelector(`[data-nav-id="${currentId}"]`) as HTMLElement | null;
    if (targetEl) {
      const containerRect = navContainerRef.getBoundingClientRect();
      const targetRect = targetEl.getBoundingClientRect();
      indicatorStyle = {
        left: targetRect.left - containerRect.left,
        width: targetRect.width,
        opacity: 1,
      };
    }
  }

  function handleMouseEnter(id: string) {
    hoveredItem = id;
    updateIndicator(id);
  }

  function handleMouseLeave() {
    hoveredItem = null;
    updateIndicator(null);
  }

  function handleItemClick(id: string) {
    activeItem = id;
    updateIndicator(id);
  }

  $effect(() => {
    // Initialize indicator on mount / state change
    updateIndicator(activeItem);
  });

  const snippetCode = `<!-- MIMI Guitar 悬浮磨砂胶囊导航栏 (Floating Frosted Pill Navbar) -->
<header class="flex justify-center px-4 pt-4 sm:pt-6 sticky top-0 z-50">
  <nav class="nav-pill flex w-full max-w-[1200px] items-center gap-2 sm:gap-5 px-4 sm:px-8 py-2.5 backdrop-blur-[16px] bg-white/80 border border-[#e5e5e5]">
    <!-- Brand Logo -->
    <a href="/" class="font-display text-xl tracking-tight text-[#0a0a0a]">MIMI Guitar</a>
    
    <!-- Sliding Magnetic Active Indicator Pill -->
    <div class="relative hidden sm:flex items-center gap-1 p-1 bg-[#f5f5f5]/60 rounded-[18px] border border-[#e5e5e5]/60">
      <div 
        class="absolute top-1 bottom-1 rounded-[14px] bg-[#0a0a0a] transition-all duration-300 ease-[cubic-bezier(0.16,1,0.3,1)]"
        style="left: \${indicatorStyle.left}px; width: \${indicatorStyle.width}px;"
      />
      {#each navItems as item}
        <button 
          data-nav-id={item.id}
          class="relative z-10 px-3.5 py-1.5 text-sm font-medium transition-colors \${activeItem === item.id ? 'text-white' : 'text-[#444141] hover:text-[#0a0a0a]'}"
          onclick={() => selectItem(item.id)}
        >
          {item.label}
        </button>
      {/each}
    </div>
  </nav>
</header>`;

  const tokensSpec = `/* Refero UI Design System - Floating Pill Tokens */
--radius-nav: 50px;             /* 浮动导航大胶囊圆角 */
--radius-pill: 18px;            /* 内部项与下拉菜单圆角 */
--backdrop-blur: 16px;          /* 玻璃态高斯模糊核心阈值 */
--bg-glass: rgba(255, 255, 255, 0.78); /* 78% 透光发丝白 */
--border-hairline: #e5e5e5;     /* 1px 精细发丝边框 */
--shadow-nav: 0 4px 20px -2px rgba(0, 0, 0, 0.05), 0 0 0 1px rgba(23, 23, 23, 0.03);
--motion-spring: cubic-bezier(0.16, 1, 0.3, 1); /* 高阶缓动吸附曲线 */`;
</script>

<div class="space-y-8">
  <!-- Sub-Header & Controls Header -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#41a1cf]"></span>
        MODULE 01 · 导航架构与磁吸指示器
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">悬浮磨砂胶囊导航 (Floating Pill Navbar)</h2>
      <p class="mt-1 text-sm text-[#737373]">
        严格对齐 Refero 50px 大胶囊几何外壳，支持高阶 Spring 物理滑动吸附、模糊度实时调谐与多级下拉弹窗。
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
    <!-- Interactive Canvas & Playground -->
    <div class="grid grid-cols-1 gap-6 lg:grid-cols-12">
      <!-- Left / Top: Interactive Live Demo Canvas -->
      <div class="lg:col-span-8 space-y-6">
        <div class="relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-gradient-to-b from-[#fafafa] to-[#f0f0f0] p-6 sm:p-10 min-h-[380px] flex flex-col justify-between shadow-xs">
          <!-- Background Grid Texture Pattern -->
          <div class="absolute inset-0 bg-[radial-gradient(#e5e5e5_1px,transparent_1px)] [background-size:16px_16px] opacity-70 pointer-events-none"></div>

          <!-- Top Stage Label -->
          <div class="relative z-10 flex items-center justify-between text-xs text-[#737373]">
            <span class="flex items-center gap-1.5 font-mono">
              <span class="h-2 w-2 rounded-full bg-[#22c55e]"></span>
              LIVE INTERACTIVE STAGE
            </span>
            <span class="font-mono">Viewport: 100% · Responsive</span>
          </div>

          <!-- FLOATING PILL NAVBAR SIMULATOR -->
          <div class="relative z-20 my-auto w-full">
            <div
              class="mx-auto flex w-full max-w-[840px] items-center justify-between gap-3 rounded-[50px] border px-4 sm:px-6 py-2.5 transition-all duration-300"
              style="
                background-color: rgba(255, 255, 255, {bgOpacity / 100});
                backdrop-filter: blur({blurAmount}px);
                -webkit-backdrop-filter: blur({blurAmount}px);
                border-color: {enableBorderGlow ? 'rgba(65, 161, 207, 0.4)' : '#e5e5e5'};
                box-shadow: {enableBorderGlow ? '0 8px 32px -4px rgba(65, 161, 207, 0.15), 0 0 0 1px rgba(65, 161, 207, 0.2)' : '0 4px 20px -2px rgba(0, 0, 0, 0.05), 0 0 0 1px rgba(23, 23, 23, 0.03)'};
              "
            >
              <!-- Brand Logo -->
              <div class="flex items-center gap-2">
                <div class="flex h-8 w-8 items-center justify-center rounded-[12px] bg-[#0a0a0a] text-white">
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                  </svg>
                </div>
                <span class="font-display text-lg tracking-tight text-[#0a0a0a] hidden sm:inline-block">MIMI Guitar</span>
              </div>

              <!-- Sliding Magnetic Tab Group -->
              <div
                bind:this={navContainerRef}
                onmouseleave={handleMouseLeave}
                class="relative hidden md:flex items-center rounded-[20px] border border-[#e5e5e5]/80 bg-[#f5f5f5]/70 p-1"
              >
                <!-- Active Sliding Background Capsule -->
                <div
                  class="absolute top-1 bottom-1 rounded-[16px] transition-all duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] pointer-events-none"
                  style="
                    left: {indicatorStyle.left}px;
                    width: {indicatorStyle.width}px;
                    opacity: {indicatorStyle.opacity};
                    background-color: {indicatorTheme === 'dark' ? '#0a0a0a' : indicatorTheme === 'signal' ? '#41a1cf' : '#ffffff'};
                    box-shadow: {indicatorTheme === 'frosted' ? '0 2px 8px rgba(0,0,0,0.08)' : '0 2px 10px rgba(0,0,0,0.15)'};
                  "
                ></div>

                {#each navItems as item}
                  <button
                    type="button"
                    data-nav-id={item.id}
                    onmouseenter={() => handleMouseEnter(item.id)}
                    onclick={() => handleItemClick(item.id)}
                    class="relative z-10 px-3.5 py-1 text-xs font-medium transition-colors duration-200 select-none {
                      (hoveredItem === item.id || activeItem === item.id)
                        ? (indicatorTheme === 'frosted' ? 'text-[#0a0a0a]' : 'text-white')
                        : 'text-[#444141] hover:text-[#0a0a0a]'
                    }"
                  >
                    {item.label}
                  </button>
                {/each}
              </div>

              <!-- Action Controls / Search / Dropdown -->
              <div class="flex items-center gap-2">
                <!-- Search Input with focus transition -->
                <div class="relative hidden sm:block">
                  <input
                    type="text"
                    bind:value={searchQuery}
                    onfocus={() => (isSearchFocused = true)}
                    onblur={() => (isSearchFocused = false)}
                    placeholder="搜索谱库..."
                    class="rounded-[18px] border border-[#e5e5e5] bg-white/90 px-3 py-1.5 text-xs text-[#0a0a0a] outline-none transition-all duration-200 {isSearchFocused ? 'w-44 border-[#41a1cf] shadow-xs' : 'w-28 focus:w-44'}"
                  />
                  <div class="absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none text-[10px] text-[#737373]">
                    ⌘K
                  </div>
                </div>

                <!-- Upload Dropdown Trigger -->
                <div class="relative">
                  <button
                    type="button"
                    onclick={() => (isUploadMenuOpen = !isUploadMenuOpen)}
                    class="inline-flex items-center gap-1 rounded-[18px] border border-[#e5e5e5] bg-white px-3 py-1.5 text-xs font-medium text-[#0a0a0a] shadow-xs transition hover:bg-[#fafafa]"
                  >
                    <span>上传</span>
                    <svg class="h-3 w-3 text-[#737373] transition-transform {isUploadMenuOpen ? 'rotate-180' : ''}" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>

                  {#if isUploadMenuOpen}
                    <div class="absolute right-0 top-full mt-2 w-36 overflow-hidden rounded-[18px] border border-[#e5e5e5] bg-white/95 p-1.5 shadow-lg backdrop-blur-md animate-stagger-in z-50">
                      <a href="#upload-guitar" class="block rounded-[12px] px-3 py-1.5 text-xs text-[#0a0a0a] hover:bg-[#f5f5f5]">🎸 吉他曲谱</a>
                      <a href="#upload-ukulele" class="block rounded-[12px] px-3 py-1.5 text-xs text-[#0a0a0a] hover:bg-[#f5f5f5]">🌴 尤克里里谱</a>
                      <a href="#upload-xhe" class="block rounded-[12px] px-3 py-1.5 text-xs text-[#0a0a0a] hover:bg-[#f5f5f5]">⚡ XHE 格式谱</a>
                    </div>
                  {/if}
                </div>

                <!-- Primary CTA Pill -->
                <button
                  type="button"
                  class="rounded-[18px] bg-[#0a0a0a] px-3.5 py-1.5 text-xs font-medium text-white transition hover:bg-[#2c2c2c] active:scale-95"
                >
                  登录
                </button>

                <!-- Mobile Hamburger Toggle -->
                <button
                  type="button"
                  onclick={() => (isMobileDrawerOpen = !isMobileDrawerOpen)}
                  class="flex h-8 w-8 items-center justify-center rounded-[14px] border border-[#e5e5e5] bg-white text-[#0a0a0a] md:hidden"
                  aria-label="打开移动端菜单"
                >
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-7 6h7" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <!-- Bottom Status & Hint -->
          <div class="relative z-10 flex flex-wrap items-center justify-between gap-2 text-xs text-[#737373]">
            <span>💡 提示：鼠标在导航项间移动可体验 Spring 物理磁吸滑动条效果</span>
            <span class="rounded-[12px] bg-white/80 px-2 py-0.5 font-mono text-[11px] border border-[#e5e5e5]">
              Active: {activeItem} · Blur: {blurAmount}px
            </span>
          </div>

          <!-- Simulated Mobile Drawer Modal Backdrop -->
          {#if isMobileDrawerOpen}
            <div class="absolute inset-0 z-40 flex justify-end bg-black/30 backdrop-blur-xs transition-opacity">
              <div class="h-full w-64 border-l border-[#e5e5e5] bg-white/95 p-6 shadow-2xl backdrop-blur-xl animate-stagger-in flex flex-col justify-between">
                <div>
                  <div class="flex items-center justify-between border-b border-[#e5e5e5] pb-4">
                    <span class="font-display text-base text-[#0a0a0a]">移动端抽屉导航</span>
                    <button
                      type="button"
                      onclick={() => (isMobileDrawerOpen = false)}
                      class="rounded-full p-1 text-[#737373] hover:bg-[#f5f5f5]"
                    >
                      ✕
                    </button>
                  </div>
                  <div class="mt-4 space-y-2">
                    {#each navItems as item}
                      <button
                        type="button"
                        onclick={() => {
                          activeItem = item.id;
                          isMobileDrawerOpen = false;
                        }}
                        class="flex w-full items-center justify-between rounded-[14px] px-3 py-2 text-left text-xs font-medium {activeItem === item.id ? 'bg-[#0a0a0a] text-white' : 'text-[#444141] hover:bg-[#f5f5f5]'}"
                      >
                        <span>{item.label}</span>
                        {#if activeItem === item.id}
                          <span>●</span>
                        {/if}
                      </button>
                    {/each}
                  </div>
                </div>
                <div class="border-t border-[#e5e5e5] pt-4 text-xs text-[#737373]">
                  MIMI Mobile Glass Drawer v2.0
                </div>
              </div>
            </div>
          {/if}
        </div>
      </div>

      <!-- Right: Live Parameter Controller -->
      <div class="lg:col-span-4 space-y-5">
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs">
          <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 导航动效与材质调谐</h3>
          <p class="mt-1 text-xs text-[#737373]">实时微调磨砂背景、发光边框与磁吸滑块风格。</p>

          <div class="mt-5 space-y-4 text-xs">
            <!-- Blur Amount Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>毛玻璃模糊度 (Backdrop Blur)</span>
                <span class="font-mono text-[#0a0a0a]">{blurAmount}px</span>
              </div>
              <input
                type="range"
                min="0"
                max="40"
                step="2"
                bind:value={blurAmount}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
              <div class="flex justify-between text-[10px] text-[#a3a3a3]">
                <span>0px (清晰)</span>
                <span>16px (标准)</span>
                <span>40px (重度)</span>
              </div>
            </div>

            <!-- Background Opacity Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>背景透明度 (Glass Opacity)</span>
                <span class="font-mono text-[#0a0a0a]">{bgOpacity}%</span>
              </div>
              <input
                type="range"
                min="30"
                max="100"
                step="2"
                bind:value={bgOpacity}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
              <div class="flex justify-between text-[10px] text-[#a3a3a3]">
                <span>30% (透视)</span>
                <span>78% (推荐)</span>
                <span>100% (纯色)</span>
              </div>
            </div>

            <!-- Sliding Indicator Theme -->
            <div>
              <span class="font-medium text-[#444141]">磁吸滑块色彩风格</span>
              <div class="mt-2 grid grid-cols-3 gap-2">
                <button
                  type="button"
                  onclick={() => (indicatorTheme = 'dark')}
                  class="rounded-[14px] border p-2 text-center text-xs font-medium transition {indicatorTheme === 'dark' ? 'border-[#0a0a0a] bg-[#0a0a0a] text-white' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  经典 Ink
                </button>
                <button
                  type="button"
                  onclick={() => (indicatorTheme = 'signal')}
                  class="rounded-[14px] border p-2 text-center text-xs font-medium transition {indicatorTheme === 'signal' ? 'border-[#41a1cf] bg-[#41a1cf] text-white' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  蔚蓝 Signal
                </button>
                <button
                  type="button"
                  onclick={() => (indicatorTheme = 'frosted')}
                  class="rounded-[14px] border p-2 text-center text-xs font-medium transition {indicatorTheme === 'frosted' ? 'border-[#0a0a0a] bg-white text-[#0a0a0a] shadow-xs' : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141]'}"
                >
                  反白 Paper
                </button>
              </div>
            </div>

            <!-- Border Glow Switch -->
            <div class="flex items-center justify-between border-t border-[#e5e5e5] pt-3">
              <div>
                <span class="font-medium text-[#0a0a0a]">微光发丝光晕 (Border Glow)</span>
                <p class="text-[11px] text-[#737373]">开启边缘 Subtle Signal 荧光反射</p>
              </div>
              <button
                type="button"
                onclick={() => (enableBorderGlow = !enableBorderGlow)}
                class="relative h-6 w-11 rounded-full transition-colors duration-200 {enableBorderGlow ? 'bg-[#0a0a0a]' : 'bg-[#dee2de]'}"
              >
                <span class="absolute top-1 left-1 h-4 w-4 rounded-full bg-white transition-transform duration-200 {enableBorderGlow ? 'translate-x-5' : 'translate-x-0'}"></span>
              </button>
            </div>

            <!-- Mobile Drawer Preview Trigger -->
            <div class="border-t border-[#e5e5e5] pt-3">
              <button
                type="button"
                onclick={() => (isMobileDrawerOpen = true)}
                class="w-full rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] py-2 text-center text-xs font-medium text-[#0a0a0a] hover:bg-[#f5f5f5]"
              >
                📱 模拟打开移动端侧边抽屉
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="NavbarPill.svelte (Astro + Svelte 5)" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Navbar CSS Design Tokens" />
  {/if}
</div>
