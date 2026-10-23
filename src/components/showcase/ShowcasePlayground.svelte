<script lang="ts">
  import { onMount } from 'svelte';
  import {
    getMotionPreferenceSnapshot,
    subscribeMotionPreference,
    type MotionMode,
  } from '../../lib/ui/motionPreferences';
  import MotionShowcase from './MotionShowcase.svelte';
  import NavShowcase from './NavShowcase.svelte';
  import HeroShowcase from './HeroShowcase.svelte';
  import CardShowcase from './CardShowcase.svelte';
  import FilterShowcase from './FilterShowcase.svelte';
  import MicroShowcase from './MicroShowcase.svelte';
  import FooterShowcase from './FooterShowcase.svelte';
  import PlayerShowcase from './PlayerShowcase.svelte';

  const modules = [
    { id: 'motion', icon: '🎬', title: '0. Cinema & Holo Motion', subtitle: '全息卡片 · 开场幕帘 · 音符微光' },
    { id: 'nav', icon: '🌟', title: '1. Navbar & Header', subtitle: '浮动胶囊 · 磁吸指示器' },
    { id: 'hero', icon: '🔍', title: '2. Hero & Spotlight', subtitle: '光标追踪 · ⌘K 极速检索' },
    { id: 'card', icon: '🎴', title: '3. TabCard & Holo-Foil', subtitle: '3D 全息反射 · 发光边框 · Bento' },
    { id: 'filter', icon: '🎛️', title: '4. Filter & Matrix', subtitle: 'Spring 胶囊 · 5段难度律动' },
    { id: 'micro', icon: '💖', title: '5. Micro-Interactions', subtitle: '磁吸按钮 · 红心爆炸 · Toast' },
    { id: 'footer', icon: '🎵', title: '6. Mega Footer', subtitle: '声波均衡器 · 运行状态微脉冲' },
    { id: 'player', icon: '🌊', title: '7. Player & Fluid HUD', subtitle: 'Canvas 流体声波 · 磨砂胶囊' },
  ];

  let currentModule = $state('motion');
  let motionMode = $state<MotionMode>(getMotionPreferenceSnapshot().mode);
  let motionReady = $state(false);

  const motionModeLabel = $derived.by(() => {
    if (!motionReady) return '读取中';
    if (motionMode === 'full') return '完整';
    if (motionMode === 'gentle') return '轻柔';
    return '静止';
  });

  function switchModule(id: string) {
    currentModule = id;
  }

  onMount(() => subscribeMotionPreference(({ mode }) => {
    motionMode = mode;
    motionReady = true;
  }));
</script>

<div class="w-full space-y-8">
  <!-- HERO HEADER BANNER -->
  <div class="relative overflow-hidden rounded-[24px] border border-[#e5e5e5] bg-gradient-to-b from-[#ffffff] to-[#fafafa] p-6 sm:p-10 shadow-xs">
    <div class="absolute top-0 right-0 p-8 opacity-10 pointer-events-none font-display text-8xl text-[#0a0a0a] select-none hidden lg:block">
      MIMI
    </div>

    <div class="relative z-10 max-w-3xl space-y-4">
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-white px-3.5 py-1 text-xs font-mono font-medium text-[#444141] shadow-xs">
        <span class="h-2 w-2 rounded-full bg-[#22c55e]"></span>
        <span>MIMI GUITAR · 可操作界面示例</span>
      </div>

      <h1 class="font-display text-3xl sm:text-4xl lg:text-5xl text-[#0a0a0a] tracking-tight leading-tight">
        MIMI Guitar 动效与交互体验展台
      </h1>

      <p class="text-sm sm:text-base text-[#737373] leading-relaxed">
        这里汇集八组可操作的界面交互示例，涵盖导航、卡片、筛选、微交互、页脚与播放器；动效遵循全站偏好。
      </p>

      <!-- Global Motion Status and Intro Replay -->
      <div class="flex flex-wrap items-center gap-3 pt-2">
        <span class="inline-flex min-h-[44px] items-center rounded-[18px] border border-[#e5e5e5] bg-white px-3.5 py-2 text-xs font-medium text-[#444141]" aria-live="polite">
          当前全站动效：{motionModeLabel}
        </span>

        <a
          href="/motion"
          class="inline-flex min-h-[44px] items-center rounded-[18px] border border-[#e5e5e5] bg-white px-3.5 py-2 text-xs font-medium text-[#444141] transition hover:bg-[#fafafa] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        >
          动效设置
        </a>

        <button
          type="button"
          disabled={!motionReady || motionMode !== 'full'}
          aria-describedby="intro-motion-note"
          onclick={() => {
            sessionStorage.removeItem('mimi_intro_played');
            window.dispatchEvent(new CustomEvent('mimi:play-intro'));
          }}
          class="inline-flex min-h-[44px] items-center gap-1.5 rounded-[18px] border border-[#f5c07b]/40 bg-[#f5c07b]/10 px-3.5 py-2 text-xs font-medium text-[#b47a28] transition shadow-xs focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:cursor-not-allowed disabled:opacity-50"
          title={motionReady && motionMode === 'full' ? '按当前全站偏好回放开场' : '请在全站动效设置中启用完整模式后回放'}
        >
          <span>🎬 回放开场</span>
        </button>

        <p id="intro-motion-note" class="basis-full text-xs text-[#737373]">
          开场回放遵循全站动效偏好；当前实际模式为{motionModeLabel}。回放按钮不会更改系统偏好。
        </p>
      </div>
    </div>
  </div>

  <!-- 8-MODULE NAVIGATION TABS -->
  <div class="sticky top-4 z-40">
    <div class="rounded-[22px] border border-[#e5e5e5]/90 bg-white/85 p-2 shadow-md backdrop-blur-xl">
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-7 gap-1.5">
        {#each modules as m}
          <button
            type="button"
            onclick={() => switchModule(m.id)}
            aria-pressed={currentModule === m.id}
            class="group flex min-h-[44px] flex-col items-start rounded-[16px] p-2.5 text-left transition-all duration-200 select-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {
              currentModule === m.id
                ? 'bg-[#0a0a0a] text-white shadow-sm ring-1 ring-black'
                : 'hover:bg-[#f5f5f5] text-[#444141]'
            }"
          >
            <div class="flex items-center gap-1.5">
              <span class="text-sm">{m.icon}</span>
              <span class="text-xs font-semibold {currentModule === m.id ? 'text-white' : 'text-[#0a0a0a]'}">
                {m.title}
              </span>
            </div>
            <span class="mt-0.5 text-[10px] {currentModule === m.id ? 'text-[#dee2de]' : 'text-[#737373]'} line-clamp-1">
              {m.subtitle}
            </span>
          </button>
        {/each}
      </div>
    </div>
  </div>

  <!-- ACTIVE MODULE STAGE -->
  <main class="min-h-[500px]">
    {#if currentModule === 'motion'}
      <MotionShowcase />
    {:else if currentModule === 'nav'}
      <NavShowcase />
    {:else if currentModule === 'hero'}
      <HeroShowcase />
    {:else if currentModule === 'card'}
      <CardShowcase />
    {:else if currentModule === 'filter'}
      <FilterShowcase />
    {:else if currentModule === 'micro'}
      <MicroShowcase />
    {:else if currentModule === 'footer'}
      <FooterShowcase />
    {:else if currentModule === 'player'}
      <PlayerShowcase />
    {/if}
  </main>
</div>
