<script lang="ts">
  import { onMount } from 'svelte';
  import { motionTokens } from '../lib/ui/motion';
import { getMotionPreferenceSnapshot, subscribeMotionPreference, type MotionMode } from '../lib/ui/motionPreferences.ts';
  import { createFolioFlipController, shouldRunFolioFlip } from '../lib/ui/folioMotion';

  interface TabItem {
    id: string;
    title: string;
    artist?: string | null;
    category?: string;
    difficulty?: number;
    sheetForm?: number | string;
    key?: string | null;
    heat?: number;
    screenshotUrl?: string | null;
    publishDate?: string | Date | null;
  }

  let {
    tabs = [],
    title = '最新曲谱',
    allHref = '#',
    accent = 'guitar',
  }: {
    tabs?: TabItem[];
    title?: string;
    allHref?: string;
    accent?: 'guitar' | 'ukulele';
  } = $props();

  let pageIndex = $state(0);
  let flipDirection = $state<-1 | 1>(1); // 1 = next (flip right-to-left), -1 = prev
  let isFlipping = $state(false);
  let motionMode = $state<MotionMode>(getMotionPreferenceSnapshot().mode);
  let currentScreenshotFit = $state<'cover' | 'contain'>('cover');
  let screenshotFailed = $state(false);
  const flipController = createFolioFlipController({
    duration: motionTokens.duration.folio,
    fallbackPadding: 100,
    onActiveChange: (active) => {
      isFlipping = active;
    },
  });
  // 翻页切换卡片时重置截图降级状态
  $effect(() => {
    const _t = current;
    screenshotFailed = false;
    currentScreenshotFit = 'cover';
  });

  // Audio Context for tactile paper rustle
  let audioCtx: AudioContext | null = null;

  onMount(() => {
    const unsubscribeMotionPreference = subscribeMotionPreference((value) => {
      motionMode = value.mode;
      if (value.mode !== 'full') flipController.settle();
    });
    const handleVisibility = () => {
      if (document.hidden) flipController.settle();
    };

    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      unsubscribeMotionPreference();
      flipController.destroy();
      document.removeEventListener('visibilitychange', handleVisibility);
      if (audioCtx && audioCtx.state !== 'closed') {
        try { audioCtx.close(); } catch (_) {}
      }
    };
  });
  function playPaperRustle() {
    try {
      const AC = window.AudioContext || (window as any).webkitAudioContext;
      if (!AC) return;
      if (!audioCtx || audioCtx.state === 'closed') {
        audioCtx = new AC();
      }
      if (audioCtx.state === 'suspended') {
        audioCtx.resume().catch(() => {});
      }
      const now = audioCtx.currentTime;
      const dur = 0.48;
      const buffer = audioCtx.createBuffer(1, Math.floor(audioCtx.sampleRate * dur), audioCtx.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) {
        const progress = i / data.length;
        // Bionic paper friction envelope: quick swell, textured drag, soft decay
        const envelope = Math.sin(progress * Math.PI) * Math.exp(-progress * 1.8);
        data[i] = (Math.random() * 2 - 1) * envelope;
      }
      const src = audioCtx.createBufferSource();
      src.buffer = buffer;
      const filter = audioCtx.createBiquadFilter();
      filter.type = 'bandpass';
      filter.frequency.setValueAtTime(1350, now);
      filter.frequency.exponentialRampToValueAtTime(900, now + dur); // Natural frequency sweep as paper settles
      filter.Q.setValueAtTime(1.1, now);
      const gain = audioCtx.createGain();
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(0.045, now + 0.04);
      gain.gain.exponentialRampToValueAtTime(0.00001, now + dur);
      src.connect(filter);
      filter.connect(gain);
      gain.connect(audioCtx.destination);
      src.start(now);
      src.stop(now + dur);
    } catch (_) {}
  }

  const diffMap = [null, '零基础', '初级', '中级', '高级', '专业'];
  const formMap: Record<number, string> = {
    1: '弹唱谱',
    2: '指弹谱',
    3: '和弦谱',
    4: '六线谱',
    7: '六线谱',
  };

  function diffLabel(t: TabItem): string | null {
    return diffMap[t.difficulty ?? 0] ?? null;
  }
  function formLabel(t: TabItem): string {
    return formMap[Number(t.sheetForm)] ?? (accent === 'ukulele' ? '四线谱' : '六线谱');
  }
  function heatStr(t: TabItem): string {
    const h = t.heat ?? 0;
    return h >= 10000 ? (h / 10000).toFixed(1) + '万' : String(h);
  }

  function go(dir: -1 | 1) {
    if (tabs.length <= 1 || isFlipping) return;
    const target = pageIndex + dir;
    if (target < 0 || target >= tabs.length) return;

    flipDirection = dir;
    pageIndex = target;
    if (shouldRunFolioFlip(motionMode)) {
      playPaperRustle();
      flipController.start(dir === 1 ? 'flip-page-next' : 'flip-page-prev');
    }
  }

  function goToPage(idx: number) {
    if (idx === pageIndex || isFlipping || idx < 0 || idx >= tabs.length) return;
    const direction: -1 | 1 = idx > pageIndex ? 1 : -1;
    flipDirection = direction;
    pageIndex = idx;
    if (shouldRunFolioFlip(motionMode)) {
      playPaperRustle();
      flipController.start(direction === 1 ? 'flip-page-next' : 'flip-page-prev');
    }
  }

  function hasRunningFlipAnimation(target: EventTarget | null, animationName: string): boolean {
    if (!target || typeof (target as Element).getAnimations !== 'function') return false;
    try {
      return (target as Element).getAnimations({ subtree: false }).some((animation) => {
        const cssAnimation = animation as CSSAnimation;
        return cssAnimation.animationName === animationName &&
          (animation.playState === 'running' || animation.pending === true);
      });
    } catch {
      return false;
    }
  }

  function handleFlipAnimation(event: AnimationEvent) {
    if (event.type !== 'animationend' && event.type !== 'animationcancel') return;
    flipController.handleAnimationEvent({
      type: event.type as 'animationend' | 'animationcancel',
      target: event.target,
      currentTarget: event.currentTarget,
      animationName: event.animationName,
    }, (name) => hasRunningFlipAnimation(event.currentTarget, name));
  }

  function listenFlipAnimation(node: HTMLAnchorElement) {
    node.addEventListener('animationend', handleFlipAnimation);
    node.addEventListener('animationcancel', handleFlipAnimation);
    return {
      destroy() {
        node.removeEventListener('animationend', handleFlipAnimation);
        node.removeEventListener('animationcancel', handleFlipAnimation);
      },
    };
  }
  // Touch Swipe Gesture Handling
  let touchStartX = 0;
  let touchStartY = 0;

  function handleTouchStart(e: TouchEvent) {
    touchStartX = e.touches[0].clientX;
    touchStartY = e.touches[0].clientY;
  }

  function handleTouchEnd(e: TouchEvent) {
    const deltaX = e.changedTouches[0].clientX - touchStartX;
    const deltaY = e.changedTouches[0].clientY - touchStartY;
    if (Math.abs(deltaX) > 45 && Math.abs(deltaX) > Math.abs(deltaY)) {
      if (deltaX < 0) go(1);
      else go(-1);
    }
  }

  let current = $derived(tabs[pageIndex] ?? tabs[0]);
  let cat = $derived(current?.category === 'ukulele' || accent === 'ukulele' ? 'ukulele' : 'tabs');
  let isFirst = $derived(tabs.length === 0 || pageIndex <= 0);
  let isLast = $derived(tabs.length <= 1 || pageIndex >= tabs.length - 1);
  let visiblePageIndices = $derived.by(() => {
    const visibleCount = Math.min(tabs.length, 3);
    const start = Math.max(0, Math.min(pageIndex - 1, tabs.length - visibleCount));
    return Array.from({ length: visibleCount }, (_, offset) => start + offset);
  });

  // Generate deterministic decorative manuscript details for each tab
  function getTabSeed(t: TabItem) {
    let hash = 0;
    const str = (t.id || '') + (t.title || '');
    for (let i = 0; i < str.length; i++) {
      hash = (hash << 5) - hash + str.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }

  // Chord symbols to display in manuscript preview
  const CHORD_PRESETS = [
    ['G', 'Em', 'C', 'D7'],
    ['C', 'G/B', 'Am', 'F'],
    ['D', 'A', 'Bm', 'G'],
    ['Am', 'F', 'C', 'G'],
    ['Fmaj7', 'Em7', 'Dm7', 'Cmaj7'],
    ['E', 'B', 'C#m', 'A'],
  ];

  function getChordsForTab(t: TabItem): string[] {
    const seed = getTabSeed(t);
    return CHORD_PRESETS[seed % CHORD_PRESETS.length];
  }

  function getSealChar(t: TabItem): string {
    const title = t.title || '乐';
    return title.charAt(0) || '谱';
  }
</script>

<div
  class="folio-container relative w-full render-contain-content"
  style="contain: content; content-visibility: auto; contain-intrinsic-size: 1px 480px;"
>
  <!-- Section Header with Craftsmanship Calligraphy & Edition Stamp -->
  <div class="flex items-center justify-between pb-3">
    <div class="flex items-center gap-2.5">
      <!-- Instrument Badge Icon -->
      <span class="flex h-7 w-7 items-center justify-center rounded-full bg-[#f4ecd8] border border-[#d8cba8] text-sm shadow-2xs">
        {#if accent === 'ukulele'}
          🪕
        {:else}
          🎸
        {/if}
      </span>
      <div>
        <h2 class="font-display text-xl sm:text-2xl font-medium tracking-tight text-ink">
          {title}
        </h2>
        <span class="block font-mono text-[9px] sm:text-[10px] tracking-[0.18em] uppercase text-[#8a7a60] -mt-0.5">
          {accent === 'ukulele' ? '4-STRING FOLIO · 尤克里里工坊' : '6-STRING FOLIO · 声学吉他谱集'}
        </span>
      </div>
    </div>

    <!-- More Link with Pill Hover -->
    <a
      href={allHref}
      class="folio-all-link group inline-flex items-center gap-1.5 rounded-pill border border-[#d8cba8]/80 bg-[#faf7ef] px-3 py-1 text-xs font-medium text-[#5a4a35] shadow-2xs hover:border-signal/50 hover:bg-[#fffdf9] hover:text-ink"
    >
      <span>全部曲谱</span>
      <span class="folio-all-arrow group-hover:translate-x-0.5 text-signal">→</span>
    </a>
  </div>

  <!-- Main Folio Display Area -->
  <div class="folio-stage relative mt-3 select-none">
    <!-- Stacked Layer 3: Deepest under-paper with organic skew & warm drop shadow -->
    <div
      class="paper-layer paper-layer-bottom absolute inset-x-2 sm:inset-x-3 rounded-[16px] pointer-events-none"
      style="top: 14px; bottom: -14px; transform: rotate(-1.5deg);"
      aria-hidden="true"
    ></div>

    <!-- Stacked Layer 2: Middle under-paper with subtle counter rotation -->
    <div
      class="paper-layer paper-layer-mid absolute inset-x-1 sm:inset-x-1.5 rounded-[16px] pointer-events-none"
      style="top: 7px; bottom: -7px; transform: rotate(1.2deg);"
      aria-hidden="true"
    ></div>

    <!-- Top Main Interactive Folio Sheet -->
    {#if current}
      <div
        class="folio-sheet-wrapper relative"
        ontouchstart={handleTouchStart}
        ontouchend={handleTouchEnd}
        role="region"
        aria-label={`${title}：${current.title}`}
      >
        <a
          href={`/${cat}/${current.id}`}
          class="folio-card group relative block overflow-hidden rounded-[16px] border border-[#d8cba8] bg-[#fbf9f4] shadow-md hover:shadow-lg hover:border-[#c9a45f]/70"
          class:is-flipping-next={isFlipping && flipDirection === 1}
          class:is-flipping-prev={isFlipping && flipDirection === -1}
          use:listenFlipAnimation
        >
          <!-- 1. Authentic Paper Noise & Fiber Texture (0 GPU Overhead 64x64 Tiled) -->
          <div class="paper-texture pointer-events-none absolute inset-0 z-0 opacity-40 mix-blend-multiply" aria-hidden="true"></div>

          <!-- 2. Subtle Aged Paper Blotches -->
          <div
            class="pointer-events-none absolute inset-0 z-0 opacity-25"
            style="background: radial-gradient(ellipse at 85% 15%, rgba(196, 172, 128, 0.25) 0%, transparent 50%), radial-gradient(ellipse at 15% 85%, rgba(188, 164, 122, 0.2) 0%, transparent 45%);"
            aria-hidden="true"
          ></div>

          <!-- 3. Dynamic Spine Crease & Diffuse Reflection Shadow on Page Turn -->
          <div
            class="spine-shadow pointer-events-none absolute inset-y-0 z-25 opacity-0"
            class:spine-shadow-next={isFlipping && flipDirection === 1}
            class:spine-shadow-prev={isFlipping && flipDirection === -1}
            aria-hidden="true"
          ></div>

          {#key pageIndex}
          <div class="folio-page-content">
          <!-- 4. Vintage Brass Header Clip (Top Center) -->
          <div class="brass-clip absolute top-0 left-1/2 -translate-x-1/2 z-30 pointer-events-none" aria-hidden="true">
            <div class="h-1.5 w-12 rounded-b-md bg-gradient-to-r from-[#9a7b45] via-[#dfbe78] to-[#9a7b45] shadow-xs border-b border-[#73582a]"></div>
            <div class="mx-auto h-0.5 w-8 bg-[#5e451b] opacity-40"></div>
          </div>

          <!-- 5. Vintage Vermilion Seal (Top Right Cinnabar Stamp) -->
          <div
            class="folio-seal vermilion-seal absolute top-3 right-4 z-20 pointer-events-none flex items-center justify-center font-serif text-xs font-bold text-[#a63426] border border-[#b93829]/70 rounded-[4px] px-1.5 py-0.5 opacity-80 rotate-3 group-hover:rotate-0 group-hover:scale-105"
            aria-hidden="true"
          >
            <span class="tracking-widest">{getSealChar(current)}印</span>
          </div>

          <!-- 6. Card Main Content -->
          <div class="relative z-10 p-5 sm:p-6">
            <!-- Top Tagline & Pagination Index -->
            <div class="flex items-center justify-between text-xs pr-14">
              <span class="inline-flex items-center gap-1.5 rounded-pill border border-[#d8cba8] bg-[#f4ecd8]/70 px-2.5 py-0.5 font-medium text-[#4a3d2c]">
                <span class="h-1.5 w-1.5 rounded-full {accent === 'ukulele' ? 'bg-signal' : 'bg-[#b08d57]'}"></span>
                {formLabel(current)}
              </span>
              <span class="font-mono text-[11px] text-[#8a7a60] tabular-nums font-semibold tracking-wider">
                — {pageIndex + 1} / {tabs.length} —
              </span>
            </div>

            <!-- Title & Artist -->
            <div class="mt-3.5">
              <h3 class="folio-title font-display text-2xl sm:text-3xl font-medium tracking-tight text-ink letterpress-ink group-hover:text-[#8f6828]">
                {current.title}
              </h3>
              <p class="mt-1 font-serif text-sm text-[#73634e] flex items-center gap-1.5">
                <span class="inline-block h-1 w-1 rounded-full bg-[#b08d57]/60"></span>
                {current.artist || '未知歌手'}
              </p>
            </div>

            <!-- Procedural Sheet Music Preview & Engraving Canvas -->
            <div class="manuscript-preview relative mt-4 overflow-hidden rounded-[10px] border border-[#d8cba8] bg-[#f8f5eb] p-3 shadow-inner">
              {#if current.screenshotUrl && !screenshotFailed}
                <!-- Real Screenshot with Fine-Art Paper Wash Filter -->
                <div class="relative aspect-[16/9] w-full overflow-hidden rounded-[6px] bg-[#f8f5eb]">
                  <img
                    src={current.screenshotUrl}
                    alt={current.title}
                    class="h-full w-full filter contrast-[1.03] sepia-[0.08] folio-preview-image group-hover:scale-105"
                    style="object-fit: {currentScreenshotFit}"
                    onload={(e) => {
                      const imgEl = e.currentTarget as HTMLImageElement;
                      screenshotFailed = false;
                      currentScreenshotFit = imgEl.naturalWidth / imgEl.naturalHeight > 3 ? 'contain' : 'cover';
                    }}
                    onerror={() => {
                      screenshotFailed = true;
                    }}
                    loading="lazy"
                  />
                  <div class="absolute inset-0 bg-gradient-to-t from-[#2c2214]/25 via-transparent to-transparent pointer-events-none"></div>
                </div>
              {:else}
                <!-- High-Craftsmanship Procedural Tablature & Chords -->
                <div class="relative aspect-[16/9] w-full flex flex-col justify-between py-1 px-2 select-none">
                  <!-- Faint Background Staff Staves -->
                  <div class="absolute inset-x-2 inset-y-2 flex flex-col justify-around opacity-25 pointer-events-none">
                    {#each Array(accent === 'ukulele' ? 4 : 6) as _, lineIdx}
                      <div class="h-px w-full bg-[#5a4832]"></div>
                    {/each}
                  </div>

                  <!-- Floating Harmonic Chord Tabs Header -->
                  <div class="relative z-10 flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class="font-display text-xs font-bold text-[#73582a] tracking-widest uppercase">TAB</span>
                      <span class="h-3 w-px bg-[#d8cba8]"></span>
                      <span class="font-mono text-[10px] text-[#8a7a60]">{current.key ? `${current.key} 调` : '1=G'}</span>
                      <span class="font-mono text-[10px] text-[#8a7a60]">4/4</span>
                    </div>
                    <!-- Mini Chords Row -->
                    <div class="flex items-center gap-1.5">
                      {#each getChordsForTab(current) as chord}
                        <span class="rounded-[4px] border border-[#d8cba8]/80 bg-[#ede4ce] px-1.5 py-0.2 text-[9px] font-mono font-semibold text-[#5a452a]">
                          {chord}
                        </span>
                      {/each}
                    </div>
                  </div>

                  <!-- Center Tablature Notation Simulation -->
                  <div class="relative z-10 my-auto flex items-center justify-around py-2">
                    <div class="flex flex-col items-center">
                      <span class="font-serif text-lg leading-none text-[#5a452a]/80">𝄞</span>
                    </div>
                    <!-- Notation Bars -->
                    <div class="flex items-center gap-3 sm:gap-4 text-[#4a3822]">
                      <span class="font-mono text-sm font-bold tracking-widest">0·2·3</span>
                      <span class="text-xs text-[#b08d57]">♫</span>
                      <span class="font-mono text-sm font-bold tracking-widest">3·2·0</span>
                      <span class="text-xs text-signal">♪</span>
                      <span class="font-mono text-sm font-bold tracking-widest">1·0·2</span>
                    </div>
                    <!-- Vintage Musical Rest/End Marker -->
                    <div class="font-serif text-sm text-[#73582a]/70">𝄇</div>
                  </div>

                  <!-- Bottom Manuscript Watermark Info -->
                  <div class="relative z-10 flex items-center justify-between text-[9px] font-mono text-[#8a7a60]">
                    <span>{accent === 'ukulele' ? '4-LINE TABS' : '6-LINE TABS'} · ACCURATE NOTATION</span>
                    <span class="flex items-center gap-1 text-[#b08d57]">
                      <span class="inline-block h-1.5 w-1.5 rounded-full bg-[#b08d57]"></span>
                      可试听互动
                    </span>
                  </div>
                </div>
              {/if}

              <!-- Hover "Open Score" Quick Action Pill -->
              <div class="absolute inset-0 z-20 flex items-center justify-center bg-[#2c2214]/30 backdrop-blur-[2px] opacity-0 folio-open-overlay group-hover:opacity-100">
                <span class="inline-flex items-center gap-2 rounded-pill border border-[#f4ecd8] bg-[#fbf9f4] px-4 py-1.5 text-xs font-semibold text-[#3a2d1c] shadow-lg transform translate-y-2 folio-open-action group-hover:translate-y-0">
                  <span>📖 打开全篇乐谱</span>
                  <span class="text-signal">→</span>
                </span>
              </div>
            </div>

            <!-- Bottom Badges & Heat Meter -->
            <div class="mt-4 flex flex-wrap items-center justify-between gap-2 text-xs">
              <div class="flex items-center gap-1.5">
                <span class="inline-flex items-center rounded-pill border border-[#d8cba8] bg-[#f4ecd8]/60 px-2.5 py-0.5 font-medium text-[#4a3d2c]">
                  {current.key ? `${current.key} 调` : '原调'}
                </span>
                {#if diffLabel(current)}
                  <span class="inline-flex items-center gap-1 rounded-pill border border-[#d8cba8] bg-[#f4ecd8]/60 px-2.5 py-0.5 font-medium text-[#4a3d2c]">
                    <span class="h-1.5 w-1.5 rounded-full bg-[#b08d57]"></span>
                    {diffLabel(current)}
                  </span>
                {/if}
              </div>

              <!-- Heat Flame -->
              <div class="inline-flex items-center gap-1 font-mono text-xs font-semibold text-[#8a6828] bg-[#f7ecd2] px-2.5 py-0.5 rounded-pill border border-[#e5d5ae]">
                <svg class="h-3.5 w-3.5 text-amber-600" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 2c1.5 3 4 5 4 9 0 3.3-2.7 6-6 6s-6-2.7-6-6c0-3.5 2-6 4-8-.5 2 1 4 2 4s2-2 2-5z" />
                </svg>
                <span>{heatStr(current)}</span>
              </div>
            </div>
          </div>
          </div>
          {/key}
        </a>
      </div>
    {/if}

    <nav class="folio-pagination mt-4" aria-label="曲谱页码">
      <button
        type="button"
        onclick={() => go(-1)}
        disabled={isFirst || isFlipping}
        class="folio-nav-btn"
        aria-label="上一页"
      >
        <svg aria-hidden="true" class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
      </button>

      <div class="folio-page-nav">
        {#each visiblePageIndices as idx (tabs[idx]?.id ?? idx)}
          <button
            type="button"
            onclick={() => goToPage(idx)}
            class="folio-dot"
            aria-label={`第 ${idx + 1} 页`}
            aria-current={idx === pageIndex ? 'page' : undefined}
          >
            <span aria-hidden="true"></span>
          </button>
        {/each}
      </div>

      <button
        type="button"
        onclick={() => go(1)}
        disabled={isLast || isFlipping}
        class="folio-nav-btn"
        aria-label="下一页"
      >
        <svg aria-hidden="true" class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <polyline points="9 18 15 12 9 6"></polyline>
        </svg>
      </button>
    </nav>
  </div>
</div>

<style>
  .folio-container {
    contain: content;
  }

  .folio-stage {
    perspective: 1200px;
    perspective-origin: center center;
  }

  .folio-sheet-wrapper {
    transform-style: preserve-3d;
  }

  /* --- Stacked Paper Deck Layers --- */
  .paper-layer {
    background: #f5f0e3;
    border: 1px solid rgba(216, 203, 168, 0.7);
    box-shadow: 0 4px 12px -2px rgba(90, 74, 50, 0.08);
    backface-visibility: hidden;
  }
  .paper-layer-mid {
    background: #f8f4ea;
    border-color: rgba(216, 203, 168, 0.85);
  }

  /* --- Paper Texture Overlay (0 GPU Overhead 64x64 Tiled) --- */
  .paper-texture {
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 64 64' width='64' height='64' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='pn'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='1' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='64' height='64' filter='url(%23pn)'/%3E%3C/svg%3E");
    background-size: 64px 64px;
    background-repeat: repeat;
  }

  .folio-all-link {
    transition-property: border-color, background-color, color;
    transition-duration: var(--motion-duration-micro, 120ms);
    transition-timing-function: var(--motion-ease-standard, cubic-bezier(0.2, 0, 0, 1));
  }

  .folio-all-arrow,
  .folio-seal,
  .folio-title,
  .folio-preview-image,
  .folio-open-action {
    transition-timing-function: var(--motion-ease-standard, cubic-bezier(0.2, 0, 0, 1));
  }

  .folio-all-arrow,
  .folio-seal,
  .folio-open-action {
    transition-property: transform;
    transition-duration: var(--motion-duration-micro, 120ms);
  }

  .folio-title {
    transition-property: color;
    transition-duration: var(--motion-duration-micro, 120ms);
  }

  .folio-preview-image {
    transition-property: transform;
    transition-duration: var(--motion-duration-control, 200ms);
  }

  .folio-open-overlay {
    transition-property: opacity;
    transition-duration: var(--motion-duration-micro, 120ms);
    transition-timing-function: var(--motion-ease-standard, cubic-bezier(0.2, 0, 0, 1));
  }

  .folio-card {
    transform-origin: center center;
    transform-style: preserve-3d;
    backface-visibility: hidden;
    transition-property: border-color, box-shadow;
    transition-duration: var(--motion-duration-micro, 120ms);
    transition-timing-function: var(--motion-ease-standard, cubic-bezier(0.2, 0, 0, 1));
  }

  :global(html[data-motion='gentle']) .folio-page-content {
    animation: folio-gentle-page-in var(--motion-duration-micro, 120ms) var(--motion-ease-standard, cubic-bezier(0.2, 0, 0, 1)) both;
  }

  @keyframes folio-gentle-page-in {
    from { opacity: 0.72; }
    to { opacity: 1; }
  }

  .is-flipping-next {
    animation: flip-page-next var(--motion-duration-folio, 360ms) var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1)) both;
  }

  @keyframes flip-page-next {
    0% {
      transform: translateX(16px) rotateY(-8deg) scale(0.985);
      opacity: 0.2;
    }
    100% {
      transform: translateX(0) rotateY(0deg) scale(1);
      opacity: 1;
    }
  }

  .is-flipping-prev {
    animation: flip-page-prev var(--motion-duration-folio, 360ms) var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1)) both;
  }

  @keyframes flip-page-prev {
    0% {
      transform: translateX(-16px) rotateY(8deg) scale(0.985);
      opacity: 0.2;
    }
    100% {
      transform: translateX(0) rotateY(0deg) scale(1);
      opacity: 1;
    }
  }

  .spine-shadow-next {
    left: 0;
    width: 48px;
    background: linear-gradient(90deg, rgba(74, 55, 25, 0.22) 0%, rgba(74, 55, 25, 0.05) 60%, transparent 100%);
    animation: spine-fade var(--motion-duration-folio, 360ms) var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1)) both;
  }

  .spine-shadow-prev {
    right: 0;
    width: 48px;
    background: linear-gradient(270deg, rgba(74, 55, 25, 0.22) 0%, rgba(74, 55, 25, 0.05) 60%, transparent 100%);
    animation: spine-fade var(--motion-duration-folio, 360ms) var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1)) both;
  }

  @keyframes spine-fade {
    0% { opacity: 0.85; }
    100% { opacity: 0; }
  }

  .folio-pagination {
    position: relative;
    z-index: 1;
    display: flex;
    max-width: 100%;
    align-items: center;
    justify-content: center;
    gap: 4px;
  }

  .folio-page-nav {
    display: flex;
    min-width: 0;
    align-items: center;
    justify-content: center;
    gap: 0;
    border: 1px solid rgba(216, 203, 168, 0.6);
    border-radius: 9999px;
    background: rgb(243 236 219 / 85%);
    box-shadow: 0 1px 2px rgb(74 55 30 / 8%);
  }

  .folio-nav-btn,
  .folio-dot {
    display: inline-flex;
    width: 44px;
    min-width: 44px;
    height: 44px;
    min-height: 44px;
    flex: 0 0 44px;
    align-items: center;
    justify-content: center;
    border: 1px solid #d8cba8;
    border-radius: 9999px;
    background: #faf7ef;
    color: #5a4832;
    cursor: pointer;
    transition-property: transform, border-color, background-color, color, opacity;
    transition-duration: var(--motion-duration-micro, 120ms);
    transition-timing-function: var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1));
  }

  .folio-nav-btn:hover:not(:disabled) {
    transform: scale(1.03);
    border-color: rgb(176 141 87 / 60%);
    background: #fffdf8;
    color: #382d1e;
  }

  .folio-nav-btn:active:not(:disabled) {
    transform: scale(0.96);
  }

  .folio-nav-btn:disabled {
    cursor: not-allowed;
    opacity: 0.38;
  }

  .folio-nav-btn:focus-visible,
  .folio-dot:focus-visible {
    outline: 2px solid #3988ad;
    outline-offset: 1px;
  }

  .folio-dot {
    border-color: transparent;
    background: transparent;
  }

  .folio-dot > span {
    width: 8px;
    height: 8px;
    border-radius: 9999px;
    background: #d8cba8;
    transition-property: width, background-color, transform;
    transition-duration: var(--motion-duration-control, 200ms);
    transition-timing-function: var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1));
  }

  .folio-dot:hover:not([aria-current='page']) > span {
    background: #bfae87;
  }

  .folio-dot[aria-current='page'] > span {
    width: 20px;
    transform: scale(1.05);
    background: #b08d57;
  }

  /* Letterpress text shadow */
  .letterpress-ink {
    text-shadow:
      0 1px 0 rgba(255, 252, 240, 0.8),
      0 -0.5px 0 rgba(70, 50, 25, 0.15);
  }

  @media (prefers-reduced-motion: reduce) {
    .is-flipping-next,
    .is-flipping-prev,
    .spine-shadow-next,
    .spine-shadow-prev {
      animation: none !important;
      transition: none !important;
    }

    .folio-dot,
    .folio-dot > span,
    .folio-nav-btn,
    .folio-all-arrow,
    .folio-seal,
    .folio-title,
    .folio-preview-image,
    .folio-open-overlay,
    .folio-open-action {
      transition: none !important;
      transform: none !important;
    }
  }
</style>
