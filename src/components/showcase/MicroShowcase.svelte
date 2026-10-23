<script lang="ts">
  import { onMount } from 'svelte';
  import CodeBlock from './CodeBlock.svelte';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences';

  // State: Magnetic Button
  let magneticOffset = $state({ x: 0, y: 0 });
  let magneticStrength = $state(0.35);
  let fullMagneticMotionEnabled = $state(false);

  const demoTimeouts = new Set<ReturnType<typeof setTimeout>>();
  const demoIntervals = new Set<ReturnType<typeof setInterval>>();

  function scheduleDemoTimeout(callback: () => void, delay: number) {
    const timeout = setTimeout(() => {
      demoTimeouts.delete(timeout);
      callback();
    }, delay);
    demoTimeouts.add(timeout);
    return timeout;
  }

  function scheduleDemoInterval(callback: () => void, delay: number) {
    const interval = setInterval(callback, delay);
    demoIntervals.add(interval);
    return interval;
  }

  function clearDemoInterval(interval: ReturnType<typeof setInterval>) {
    clearInterval(interval);
    demoIntervals.delete(interval);
  }

  onMount(() => {
    const pointerQuery = window.matchMedia('(hover: hover) and (pointer: fine)');
    let fullMotionPreference = false;

    const syncMagneticAvailability = () => {
      fullMagneticMotionEnabled = fullMotionPreference && pointerQuery.matches;
      if (!fullMagneticMotionEnabled) magneticOffset = { x: 0, y: 0 };
    };

    pointerQuery.addEventListener('change', syncMagneticAvailability);
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      fullMotionPreference = mode === 'full';
      syncMagneticAvailability();
    });

    return () => {
      unsubscribeMotion();
      pointerQuery.removeEventListener('change', syncMagneticAvailability);
      fullMagneticMotionEnabled = false;
      magneticOffset = { x: 0, y: 0 };
      for (const timeout of demoTimeouts) clearTimeout(timeout);
      for (const interval of demoIntervals) clearInterval(interval);
      demoTimeouts.clear();
      demoIntervals.clear();
    };
  });

  function handleMagneticMouseMove(e: MouseEvent) {
    if (!fullMagneticMotionEnabled) return;

    const btn = e.currentTarget as HTMLElement;
    const rect = btn.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;

    const dx = e.clientX - centerX;
    const dy = e.clientY - centerY;

    magneticOffset = {
      x: dx * magneticStrength,
      y: dy * magneticStrength,
    };
  }

  function handleMagneticMouseLeave() {
    if (!fullMagneticMotionEnabled) return;
    magneticOffset = { x: 0, y: 0 };
  }

  // State: Heart Burst & Favorite
  let isFavorited = $state(false);
  let favoriteCount = $state(128);
  let isHeartPopping = $state(false);
  let particles = $state<Array<{ id: number; angle: number; color: string }>>([]);

  function triggerFavorite() {
    isFavorited = !isFavorited;
    favoriteCount += isFavorited ? 1 : -1;
    isHeartPopping = true;

    if (isFavorited) {
      // Spawn 8 particle explosion dots
      const colors = ['#e7000b', '#41a1cf', '#f59e0b', '#ec4899', '#8b5cf6', '#e7000b'];
      particles = Array.from({ length: 8 }, (_, i) => ({
        id: Date.now() + i,
        angle: (i * 360) / 8,
        color: colors[i % colors.length],
      }));

      scheduleDemoTimeout(() => {
        particles = [];
      }, 700);
    }

    scheduleDemoTimeout(() => {
      isHeartPopping = false;
    }, 450);
  }

  // State: Toast Alerts
  interface Toast {
    id: number;
    type: 'success' | 'info' | 'error';
    message: string;
    sub: string;
  }
  let toasts = $state<Toast[]>([]);

  function showToast(type: 'success' | 'info' | 'error', message: string, sub = '') {
    const id = Date.now();
    toasts = [...toasts, { id, type, message, sub }];
    scheduleDemoTimeout(() => {
      toasts = toasts.filter((t) => t.id !== id);
    }, 3200);
  }

  // State: Download State Machine
  let downloadState = $state<'idle' | 'downloading' | 'completed'>('idle');
  let downloadProgress = $state(0);

  function startDownloadDemo() {
    if (downloadState !== 'idle') return;
    downloadState = 'downloading';
    downloadProgress = 0;

    const interval = scheduleDemoInterval(() => {
      downloadProgress += 15;
      if (downloadProgress >= 100) {
        clearDemoInterval(interval);
        downloadState = 'completed';
        showToast('success', '曲谱已成功打包导出', 'PDF 矢量乐谱 (3.4 MB) 已保存至本地');
        scheduleDemoTimeout(() => {
          downloadState = 'idle';
          downloadProgress = 0;
        }, 3000);
      }
    }, 180);
  }

  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  const snippetCode = `<!-- 磁吸吸附按钮 (Magnetic Spring Button) -->
<button
  class="btn btn-primary transition-transform duration-200 ease-out"
  style="transform: translate3d(\${magnetic.x}px, \${magnetic.y}px, 0);"
  onmousemove={handleMagneticMouseMove}
  onmouseleave={handleMagneticMouseLeave}
>
  磁吸按钮
</button>

<!-- 红心微粒子爆炸 (Heart Particle Burst) -->
<button onclick={triggerFavorite} class="relative inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] px-4 py-2">
  <svg class="h-5 w-5 \${isFavorited ? 'text-[#e7000b] fill-[#e7000b]' : 'text-[#737373]'} \${isPopping ? 'animate-heart-pop' : ''}">
    <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
  </svg>
  {#if isFavorited}
    <!-- 8 粒子环形散开 -->
    {#each particles as p}
      <span class="particle" style="--angle: \${p.angle}deg; --color: \${p.color};" />
    {/each}
  {/if}
</button>`;

  const tokensSpec = `/* Refero UI Micro-Interactions & Particle Tokens */
--magnetic-radius: 40px;
--magnetic-spring: cubic-bezier(0.16, 1, 0.3, 1);
--heart-pop-scale: 1.35;
--toast-radius: 18px;
--toast-shadow: 0 12px 32px -4px rgba(0, 0, 0, 0.12), 0 0 0 1px rgba(23, 23, 23, 0.04);
--toast-blur: 16px;`;
</script>

<div class="space-y-8">
  <!-- Sub-Header & Switcher -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#e7000b]"></span>
        MODULE 05 · 物理吸附与微交互反馈
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">按钮与微交互体系 (Magnetic, Heart Burst & Toast)</h2>
      <p class="mt-1 text-sm text-[#737373]">
        磁吸力场微位移、收藏红心 8 粒子环形爆炸、18px 胶囊 Toast 消息队列与下载状态机。
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
      <!-- Main Interactive Stage -->
      <div class="lg:col-span-8 space-y-6">
        <!-- 1. MAGNETIC BUTTON & HEART BURST PLAYGROUND -->
        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
          <!-- Magnetic Button Card -->
          <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs flex flex-col justify-between min-h-[220px]">
            <div>
              <span class="text-[11px] font-mono text-[#737373]">INTERACTION A</span>
              <h3 class="font-display text-base text-[#0a0a0a] mt-1">磁吸吸附按钮 (Magnetic Attraction)</h3>
              <p class="text-xs text-[#737373] mt-1">将光标移近按钮，体验引力物理微位移与弹性回位。</p>
            </div>

            <div class="my-auto flex items-center justify-center p-4">
              <button
                type="button"
                onmousemove={handleMagneticMouseMove}
                onmouseleave={handleMagneticMouseLeave}
                style="transform: translate3d({fullMagneticMotionEnabled ? magneticOffset.x : 0}px, {fullMagneticMotionEnabled ? magneticOffset.y : 0}px, 0);"
                class="btn btn-primary px-6 py-2.5 shadow-md transition-transform duration-100 ease-out active:scale-90 select-none"
              >
                <span>🧲 磁吸体验键</span>
              </button>
            </div>

            <div class="text-[11px] text-[#737373] font-mono flex justify-between border-t border-[#e5e5e5] pt-2">
              <span>Offset X: {Math.round(magneticOffset.x)}px</span>
              <span>Offset Y: {Math.round(magneticOffset.y)}px</span>
            </div>
          </div>

          <!-- Heart Burst Card -->
          <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs flex flex-col justify-between min-h-[220px]">
            <div>
              <span class="text-[11px] font-mono text-[#737373]">INTERACTION B</span>
              <h3 class="font-display text-base text-[#0a0a0a] mt-1">红心粒子爆炸 (Heart Burst)</h3>
              <p class="text-xs text-[#737373] mt-1">点击收藏触发心形弹性微形变与 8 粒子溅射反馈。</p>
            </div>

            <div class="my-auto flex items-center justify-center p-4">
              <div class="relative">
                <button
                  type="button"
                  onclick={triggerFavorite}
                  class="btn relative z-10 px-5 py-2.5 shadow-xs transition hover:scale-105 active:scale-95 {isFavorited ? 'border-[#e7000b]/40 bg-[#e7000b]/5 text-[#e7000b]' : ''}"
                >
                  <svg
                    class="h-5 w-5 transition-all {isFavorited ? 'fill-[#e7000b] text-[#e7000b]' : 'text-[#737373]'} {isHeartPopping ? 'animate-heart-pop' : ''}"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                    fill={isFavorited ? '#e7000b' : 'none'}
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
                  </svg>
                  <span class="font-mono text-xs font-semibold">{favoriteCount}</span>
                </button>

                <!-- 8 Radial Particle Explosion -->
                {#if particles.length > 0}
                  <div class="pointer-events-none absolute inset-0 flex items-center justify-center">
                    {#each particles as p}
                      <span
                        class="absolute h-2 w-2 rounded-full animate-particle-burst"
                        style="
                          --particle-angle: {p.angle}deg;
                          background-color: {p.color};
                        "
                      ></span>
                    {/each}
                  </div>
                {/if}
              </div>
            </div>

            <div class="text-[11px] text-[#737373] font-mono flex justify-between border-t border-[#e5e5e5] pt-2">
              <span>状态: {isFavorited ? '已收藏 ★' : '未收藏 ☆'}</span>
              <span>粒子数: 8 Dots</span>
            </div>
          </div>
        </div>

        <!-- 2. DOWNLOAD BUTTON STATE MACHINE -->
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <span class="text-[11px] font-mono text-[#737373]">INTERACTION C</span>
              <h3 class="font-display text-base text-[#0a0a0a] mt-0.5">下载曲谱状态机 (Progress & Success Pill)</h3>
            </div>
            <span class="rounded-[12px] bg-[#fafafa] border border-[#e5e5e5] px-2.5 py-0.5 text-xs font-mono text-[#737373]">
              State: {downloadState.toUpperCase()}
            </span>
          </div>

          <div class="flex flex-wrap items-center gap-4 rounded-[20px] border border-[#e5e5e5] bg-[#fafafa] p-4">
            <button
              type="button"
              onclick={startDownloadDemo}
              disabled={downloadState !== 'idle'}
              class="relative overflow-hidden inline-flex items-center gap-2 rounded-[18px] px-6 py-2.5 text-xs font-medium transition shadow-sm {
                downloadState === 'idle'
                  ? 'bg-[#0a0a0a] text-white hover:bg-[#2c2c2c] active:scale-95'
                  : downloadState === 'downloading'
                  ? 'bg-[#41a1cf] text-white'
                  : 'bg-[#22c55e] text-white'
              }"
            >
              <!-- Progress Background Bar -->
              {#if downloadState === 'downloading'}
                <div
                  class="absolute inset-0 bg-white/20 transition-all duration-200"
                  style="width: {downloadProgress}%;"
                ></div>
              {/if}

              <span class="relative z-10 flex items-center gap-2">
                {#if downloadState === 'idle'}
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                  </svg>
                  <span>下载矢量曲谱 (PDF / GP5)</span>
                {:else if downloadState === 'downloading'}
                  <svg class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  <span>正在导出乐谱 ({downloadProgress}%)...</span>
                {:else}
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                  </svg>
                  <span>导出完成！已下载</span>
                {/if}
              </span>
            </button>

            <span class="text-xs text-[#737373]">
              点击按钮体验 3 阶段状态机（就绪 ➔ 渲染打包进度 ➔ 成功微脉冲 ➔ 触发全局 Toast）
            </span>
          </div>
        </div>

        <!-- 3. TOAST TRIGGERS & TACTILE BUTTONS MATRIX -->
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-4">
          <div class="flex items-center justify-between">
            <h3 class="font-display text-base text-[#0a0a0a]">3. 胶囊 Toast 触发器与全站按键家族</h3>
            <span class="text-xs text-[#737373]">18px 几何倒角阶梯</span>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <button
              type="button"
              onclick={() => showToast('success', '链接已复制到剪贴板', 'https://mimi-guitar.local/tabs/142')}
              class="btn btn-primary"
            >
              📋 触发复制 Toast
            </button>
            <button
              type="button"
              onclick={() => showToast('info', '曲谱已加入离线缓存', '可在无网络环境下继续练习')}
              class="btn btn-signal"
            >
              ℹ️ 触发信息 Toast
            </button>
            <button
              type="button"
              onclick={() => showToast('error', '音频引擎加载超时', '请检查浏览器 WebAudio 权限')}
              class="btn text-[#e7000b] border-[#e7000b]/30 hover:bg-[#e7000b]/5"
            >
              ⚠️ 触发警告 Toast
            </button>
            <button
              type="button"
              class="btn btn-ghost"
            >
              👻 幽灵次级按钮
            </button>
          </div>
        </div>
      </div>

      <!-- Right: Toast Floating Preview & Parameter Controller -->
      <div class="lg:col-span-4 space-y-5">
        <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs">
          <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 微交互力场调谐</h3>
          <p class="mt-1 text-xs text-[#737373]">实时微调磁吸引力系数与粒子反馈。</p>

          <div class="mt-5 space-y-4 text-xs">
            <!-- Magnetic Strength Slider -->
            <div>
              <div class="flex justify-between font-medium text-[#444141]">
                <span>磁吸引力阻尼 (Magnetic Pull)</span>
                <span class="font-mono text-[#0a0a0a]">{(magneticStrength * 100).toFixed(0)}%</span>
              </div>
              <input
                type="range"
                min="0.1"
                max="0.8"
                step="0.05"
                bind:value={magneticStrength}
                class="mt-2 w-full accent-[#0a0a0a]"
              />
            </div>

            <!-- Toast Simulator Status -->
            <div class="border-t border-[#e5e5e5] pt-3">
              <span class="font-medium text-[#444141]">当前活跃 Toast 队列 ({toasts.length})</span>
              <div class="mt-2 min-h-[100px] rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] p-2 space-y-2">
                {#if toasts.length === 0}
                  <div class="flex h-20 items-center justify-center text-xs text-[#a3a3a3]">
                    暂无活动 Toast（点击左侧按钮触发）
                  </div>
                {:else}
                  {#each toasts as t}
                    <div class="flex items-center justify-between rounded-[14px] border border-[#e5e5e5] bg-white p-2 text-xs shadow-xs animate-stagger-in">
                      <div class="flex items-center gap-2 truncate">
                        <span class="h-2 w-2 rounded-full {t.type === 'success' ? 'bg-[#22c55e]' : t.type === 'info' ? 'bg-[#41a1cf]' : 'bg-[#e7000b]'}"></span>
                        <span class="font-medium text-[#0a0a0a] truncate">{t.message}</span>
                      </div>
                      <span class="text-[10px] text-[#737373] font-mono">3s</span>
                    </div>
                  {/each}
                {/if}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Floating Global Toast Notifications Floating Overlay -->
    {#if toasts.length > 0}
      <div class="fixed top-6 right-6 z-50 flex flex-col gap-2 max-w-sm w-full pointer-events-none">
        {#each toasts as toast (toast.id)}
          <div class="pointer-events-auto flex items-start gap-3 rounded-[18px] border border-[#e5e5e5] bg-white/95 p-3.5 shadow-xl backdrop-blur-xl animate-stagger-in">
            <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full {toast.type === 'success' ? 'bg-[#22c55e]/10 text-[#22c55e]' : toast.type === 'info' ? 'bg-[#41a1cf]/10 text-[#41a1cf]' : 'bg-[#e7000b]/10 text-[#e7000b]'}">
              {#if toast.type === 'success'}
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              {:else if toast.type === 'info'}
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              {:else}
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              {/if}
            </div>

            <div class="min-w-0 flex-1">
              <h4 class="text-xs font-semibold text-[#0a0a0a]">{toast.message}</h4>
              {#if toast.sub}
                <p class="text-[11px] text-[#737373] mt-0.5 truncate">{toast.sub}</p>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="MicroInteractions.svelte" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Micro-interaction Tokens" />
  {/if}
</div>

<style>
  @keyframes particle-burst {
    0% {
      transform: rotate(var(--particle-angle)) translateY(0) scale(1);
      opacity: 1;
    }
    100% {
      transform: rotate(var(--particle-angle)) translateY(-28px) scale(0);
      opacity: 0;
    }
  }
  .animate-particle-burst {
    animation: particle-burst 0.65s cubic-bezier(0.16, 1, 0.3, 1) forwards;
  }
</style>
