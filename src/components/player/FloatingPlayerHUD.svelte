<script lang="ts">
  import { onDestroy } from 'svelte';
  import FluidAudioWaveform from './FluidAudioWaveform.svelte';
  import { formatMilliseconds, clampTick } from '../../lib/playbackSpeed.mjs';

  let {
    isPlaying = false,
    curTime = 0,
    endTime = 0,
    curTick = 0,
    endTick = 0,
    bpm = 80,
    speed = 80,
    playbackRatio,
    title = '',
    artist = '',
    tracksCount = 0,
    showTracksPanel = false,
    tracksPanelId,
    disabled = false,
    forceVisible = false,
    scrollThreshold = 350,
    onPlayPause,
    onSeekStart,
    onSeekInput,
    onSeekEnd,
    onSeekCancel,
    seekGeneration = 0,
    pendingSeekTick = null,
    onChangeSpeed,
    onToggleTracks,
  }: {
    isPlaying?: boolean;
    curTime?: number;
    endTime?: number;
    curTick?: number;
    endTick?: number;
    bpm?: number;
    speed?: number;
    playbackRatio?: number;
    title?: string;
    artist?: string;
    tracksCount?: number;
    showTracksPanel?: boolean;
    tracksPanelId?: string;
    disabled?: boolean;
    forceVisible?: boolean;
    scrollThreshold?: number;
    onPlayPause?: () => void;
    onSeekStart?: (e: Event) => void;
    onSeekInput?: (e: Event) => void;
    onSeekEnd?: () => void;
    onSeekCancel?: () => void;
    seekGeneration?: number;
    pendingSeekTick?: number | null;
    onChangeSpeed?: (speed: number) => void;
    onToggleTracks?: (event: MouseEvent) => void;
  } = $props();

  let isScrollVisible = $state(false);
  let isVisible = $derived(forceVisible || isScrollVisible);
  let isSpeedMenuOpen = $state(false);
  let isSeeking = $state(false);
  let seekVal = $state(0);
  let observedSeekGeneration = $state<number | null>(null);
  let hudRoot: HTMLDivElement;

  // Progress percentage
  let progressPercent = $derived(
    endTick > 0 ? Math.min(100, Math.max(0, (((isSeeking ? seekVal : pendingSeekTick ?? curTick)) / endTick) * 100)) : 0
  );

  let speedMultiplier = $derived(
    playbackRatio !== undefined
      ? playbackRatio.toFixed(2).replace(/\.00$/, '') + 'x'
      : bpm > 0 ? (speed / bpm).toFixed(2).replace(/\.00$/, '') + 'x' : '1.0x'
  );

  function presetTargetBpm(multiplier: number): number {
    return Math.round((bpm || 80) * multiplier);
  }

  function presetReachable(multiplier: number): boolean {
    const target = presetTargetBpm(multiplier);
    const ratio = target / (bpm || 80);
    return target >= 20 && target <= 300 && ratio >= 0.125 && ratio <= 8;
  }

  function handleSeekStart(e: Event) {
    isSeeking = true;
    seekVal = clampTick(Number((e.currentTarget as HTMLInputElement).value), endTick);
    onSeekStart?.(e);
  }

  function handleSeekInput(e: Event) {
    const val = clampTick(Number((e.currentTarget as HTMLInputElement).value), endTick);
    seekVal = val;
    onSeekInput?.(e);
  }

  function handleSeekEnd() {
    if (!isSeeking) return;
    isSeeking = false;
    onSeekEnd?.();
  }

  function handleSeekCancel() {
    if (!isSeeking) return;
    isSeeking = false;
    seekVal = clampTick(curTick, endTick);
    onSeekCancel?.();
  }

  $effect(() => {
    const generation = seekGeneration;
    if (observedSeekGeneration === null) {
      observedSeekGeneration = generation;
      return;
    }
    if (generation === observedSeekGeneration) return;
    observedSeekGeneration = generation;
    handleSeekCancel();
    seekVal = clampTick(curTick, endTick);
  });

  $effect(() => {
    if ((disabled || !isVisible) && isSeeking) handleSeekCancel();
  });

  $effect(() => {
    if (isVisible || typeof document === 'undefined' || !hudRoot) return;
    const active = document.activeElement;
    if (!(active instanceof HTMLElement) || !hudRoot.contains(active)) return;
    const mainPlayTrigger = document.getElementById('btn-play');
    if (mainPlayTrigger instanceof HTMLButtonElement && !mainPlayTrigger.disabled && mainPlayTrigger.getClientRects().length > 0) {
      mainPlayTrigger.focus();
    } else {
      active.blur();
    }
  });

  onDestroy(handleSeekCancel);

  function selectSpeedPreset(multiplier: number) {
    if (!presetReachable(multiplier)) return;
    const target = presetTargetBpm(multiplier);
    onChangeSpeed?.(target);
    isSpeedMenuOpen = false;
  }

  function scrollToTop() {
    if (typeof window !== 'undefined') {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
    const scoreScroll = document.getElementById('score-scroll');
    if (scoreScroll) {
      scoreScroll.scrollTo({ top: 0, behavior: 'smooth' });
    }
  }

  $effect(() => {
    let ticking = false;
    let pendingFrame: number | null = null;
    function checkScroll() {
      if (typeof window === 'undefined') return;
      const windowY = window.scrollY || document.documentElement.scrollTop || 0;
      const scoreScrollEl = document.getElementById('score-scroll');
      const scoreScrollY = scoreScrollEl ? scoreScrollEl.scrollTop : 0;
      const maxScroll = Math.max(windowY, scoreScrollY);
      isScrollVisible = maxScroll > scrollThreshold;
      ticking = false;
      pendingFrame = null;
    }
    function onScroll() {
      if (!ticking) {
        pendingFrame = requestAnimationFrame(checkScroll);
        ticking = true;
      }
    }

    if (typeof window !== 'undefined') {
      window.addEventListener('scroll', onScroll, { passive: true });
      const scoreScrollEl = document.getElementById('score-scroll');
      if (scoreScrollEl) {
        scoreScrollEl.addEventListener('scroll', onScroll, { passive: true });
      }
      checkScroll();
    }

    return () => {
      if (typeof window !== 'undefined') {
        window.removeEventListener('scroll', onScroll);
        if (pendingFrame !== null) cancelAnimationFrame(pendingFrame);
        const scoreScrollEl = document.getElementById('score-scroll');
        if (scoreScrollEl) {
          scoreScrollEl.removeEventListener('scroll', onScroll);
        }
      }
    };
  });
</script>

<!-- Floating Frosted Capsule HUD Container -->
<div
  bind:this={hudRoot}
  class="fixed bottom-4 sm:bottom-6 left-1/2 z-50 w-[calc(100vw-1rem)] sm:w-auto max-w-[94vw] -translate-x-1/2 transition-all duration-400 ease-[cubic-bezier(0.16,1,0.3,1)] select-none {
    isVisible
      ? 'translate-y-0 opacity-100 pointer-events-auto'
      : 'translate-y-[130%] opacity-0 pointer-events-none'
  }"
  role="region"
  aria-label="悬浮迷你播放控制台"
  aria-hidden={!isVisible}
  inert={!isVisible}
>
  <div
    class="relative flex w-full min-w-0 items-center justify-between gap-1 sm:gap-3.5 rounded-[18px] border border-[#e5e5e5] bg-white/88 p-1.5 sm:px-4 sm:py-2.5 shadow-[0_12px_36px_-4px_rgba(0,0,0,0.14),0_0_0_1px_rgba(0,0,0,0.04)] backdrop-blur-[20px]"
  >
    <!-- 1. Play / Pause 18px Circular Button with Morphing Icon -->
    <button
      type="button"
      onclick={onPlayPause}
      disabled={disabled}
      class="group relative flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-full transition-all duration-200 active:scale-92 disabled:opacity-50 disabled:pointer-events-none {
        isPlaying
          ? 'bg-[#41a1cf] text-white shadow-[0_2px_10px_rgba(65,161,207,0.35)] hover:bg-[#3492be]'
          : 'bg-[#0a0a0a] text-white shadow-[0_2px_8px_rgba(0,0,0,0.15)] hover:bg-[#262626]'
      }"
      aria-label={isPlaying ? '暂停播放' : '继续播放'}
      aria-pressed={isPlaying}
    >
      <span class="relative flex h-4 w-4 items-center justify-center">
        {#if isPlaying}
          <!-- Smooth Pause Dual Bars -->
          <svg class="h-3.5 w-3.5 fill-current transition-transform duration-200" viewBox="0 0 24 24">
            <rect x="5" y="3" width="4.5" height="18" rx="1.5" />
            <rect x="14.5" y="3" width="4.5" height="18" rx="1.5" />
          </svg>
        {:else}
          <!-- Smooth Play Triangle -->
          <svg class="h-3.5 w-3.5 fill-current ml-0.5 transition-transform duration-200" viewBox="0 0 24 24">
            <path d="M6 3.5v17a1 1 0 001.55.83l13-8.5a1 1 0 000-1.66l-13-8.5A1 1 0 006 3.5z" />
          </svg>
        {/if}
      </span>
    </button>

    <!-- 2. Track & Artist Info (Desktop/Tablet Compact View) -->
    {#if title}
      <div class="hidden md:flex flex-col max-w-[120px] lg:max-w-[160px] truncate leading-tight pr-1">
        <span class="text-xs font-semibold text-[#0a0a0a] truncate" title={title}>{title}</span>
        {#if artist}
          <span class="text-[11px] text-[#737373] truncate" title={artist}>{artist}</span>
        {/if}
      </div>
      <div class="hidden md:block h-5 w-[1px] bg-[#e5e5e5]"></div>
    {/if}

    <!-- 3. Embedded FluidAudioWaveform Component -->
    <div class="hidden sm:flex items-center shrink-0">
      <FluidAudioWaveform
        {isPlaying}
        bpm={speed || bpm || 72}
        color={isPlaying ? '#0a0a0a' : '#737373'}
        height={26}
        width={105}
      />
    </div>

    <!-- 4. Mini Progress Bar & Time Indicators -->
    <div class="flex min-w-0 items-center gap-1 min-[360px]:gap-2">
      <span class="hidden min-[360px]:inline-block font-mono text-[10px] sm:text-[11px] tabular-nums text-[#737373] w-9 sm:w-10 text-right shrink-0">
        {formatMilliseconds(curTime)}
      </span>

      <!-- Interactive Progress Rail -->
      <div class="group seek-rail relative flex h-[44px] w-16 sm:h-5 sm:w-28 md:w-36 items-center">
        <!-- Background Track -->
        <div class="h-1.5 w-full rounded-full bg-[#f0f0f0] overflow-hidden transition-all group-hover:h-2">
          <!-- Active Played Bar -->
          <div
            class="h-full rounded-full transition-all {isPlaying ? 'bg-[#41a1cf]' : 'bg-[#0a0a0a]'}"
            style="width: {progressPercent}%;"
          ></div>
        </div>

        <!-- Seeker Input Range Overlay -->
        <input
          type="range"
          min="0"
          max={endTick > 0 ? endTick : 100}
          step="1"
          value={isSeeking ? seekVal : pendingSeekTick ?? clampTick(curTick, endTick)}
          onpointerdown={handleSeekStart}
          oninput={handleSeekInput}
          onpointerup={handleSeekEnd}
          onpointercancel={handleSeekCancel}
          onlostpointercapture={handleSeekCancel}
          onblur={handleSeekCancel}
          onkeyup={handleSeekEnd}
          disabled={disabled || endTick <= 0}
          class="absolute inset-0 z-10 min-h-[44px] w-full opacity-0 cursor-pointer disabled:cursor-not-allowed sm:min-h-0"
          aria-label="悬浮控制台播放进度"
        />
      </div>

      <span class="hidden min-[360px]:inline-block font-mono text-[10px] sm:text-[11px] tabular-nums text-[#737373] w-9 sm:w-10 shrink-0">
        {formatMilliseconds(endTime)}
      </span>
    </div>

    <div class="h-5 w-[1px] bg-[#e5e5e5]"></div>

    <!-- 5. Speed Chip & Preset Popover -->
    <div class="relative">
      <button
        type="button"
        onclick={() => (isSpeedMenuOpen = !isSpeedMenuOpen)}
        disabled={disabled}
        class="inline-flex min-h-[44px] min-w-[44px] shrink-0 items-center gap-1 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-2.5 py-1 text-xs font-mono font-medium text-[#0a0a0a] transition hover:bg-white hover:border-[#b4b8b4] active:scale-95 disabled:opacity-50"
        aria-label="调整播放速度"
        aria-expanded={isSpeedMenuOpen}
      >
        <span class="text-[#737373] text-[10px]">♩</span>
        <span>{speed}</span>
        <span class="hidden min-[360px]:inline text-[10px] text-[#41a1cf]">({speedMultiplier})</span>
      </button>

      {#if isSpeedMenuOpen}
        <div
          class="animate-stagger-in absolute bottom-full left-1/2 -translate-x-1/2 mb-2 w-40 rounded-[18px] border border-[#e5e5e5] bg-white/95 p-2 shadow-xl backdrop-blur-xl z-50 space-y-1.5"
        >
          <div class="px-2 py-1 text-[11px] font-medium text-[#737373] flex justify-between items-center border-b border-[#e5e5e5] pb-1.5">
            <span>倍速调节</span>
            <span class="font-mono text-[#0a0a0a] font-semibold">{speed} BPM</span>
          </div>

          <div class="grid grid-cols-4 gap-1 pt-1">
            {#each [0.75, 0.9, 1.0, 1.25] as m}
              {@const target = presetTargetBpm(m)}
              {@const reachable = presetReachable(m)}
              <button
                type="button"
                onclick={() => selectSpeedPreset(m)}
                disabled={disabled || !reachable}
                class="min-h-[44px] rounded-[12px] py-1 text-[11px] font-mono transition text-center disabled:cursor-not-allowed disabled:opacity-40 {
                  Math.abs(speed - target) < 2
                    ? 'bg-[#0a0a0a] text-white font-bold'
                    : 'bg-[#f5f5f5] text-[#444141] hover:bg-[#e5e5e5]'
                }"
                title={reachable ? `${target} BPM` : '该预设超出 20–300 BPM 或 AlphaTab 倍率范围'}
              >
                {m}x
              </button>
            {/each}
          </div>

          <div class="pt-1 px-1">
            <input
              type="range"
              min="20"
              max="300"
              step="1"
              value={speed}
              oninput={(e) => onChangeSpeed?.(Number((e.currentTarget as HTMLInputElement).value))}
              class="min-h-[44px] w-full"
              disabled={disabled}
              aria-label="目标播放速度 BPM"
            />
          </div>
        </div>
      {/if}
    </div>

    <!-- 6. Track Drawer Toggle Button -->
    {#if tracksCount > 0}
      <button
        type="button"
        onclick={onToggleTracks}
        disabled={disabled}
        class="inline-flex min-h-[44px] min-w-[44px] shrink-0 items-center justify-center gap-1.5 rounded-[18px] border px-2.5 py-1 text-xs font-medium transition active:scale-95 disabled:opacity-50 {
          showTracksPanel
            ? 'border-[#41a1cf]/40 bg-[#41a1cf]/10 text-[#41a1cf]'
            : 'border-[#e5e5e5] bg-[#fafafa] text-[#444141] hover:bg-white hover:border-[#b4b8b4]'
        }"
        aria-label="音轨分层控制"
        aria-controls={tracksPanelId}
        aria-expanded={showTracksPanel}
        title="展开/收起音轨控制"
      >
        <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polygon points="12 2 2 7 12 12 22 7 12 2" />
          <polyline points="2 17 12 22 22 17" />
          <polyline points="2 12 12 17 22 12" />
        </svg>
        <span class="hidden sm:inline font-mono">{tracksCount} 音轨</span>
      </button>
    {/if}

    <!-- 7. Return to Top Quick Action -->
    <button
      type="button"
      onclick={scrollToTop}
      class="hidden h-[44px] w-[44px] shrink-0 items-center justify-center rounded-full text-[#737373] hover:text-[#0a0a0a] hover:bg-[#f5f5f5] transition active:scale-90 sm:flex"
      title="回到顶部"
      aria-label="回到顶部"
    >
      <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="18 15 12 9 6 15" />
      </svg>
    </button>
  </div>
</div>

<style>
  .seek-rail:has(input:focus-visible) {
    outline: 2px solid #41a1cf;
    outline-offset: 2px;
    border-radius: 9999px;
  }
</style>
