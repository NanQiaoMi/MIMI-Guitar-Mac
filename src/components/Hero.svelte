<script lang="ts">
  import { onMount } from 'svelte';
  import MusicNoteParticles from './ambient/MusicNoteParticles.svelte';
  import { subscribeMotionPreference } from '../lib/ui/motionPreferences.ts';

  let { totalTabs = 2860, hotArtists = ['周杰伦', '陶喆', '赵雷', '痛仰', '押尾桑', '岸部真明'] }: { totalTabs?: number; hotArtists?: string[] } = $props();

  let animatedCount = $state(0);
  let cardElement: HTMLDivElement | null = $state(null);
  let isFocused = $state(false);
  let isInViewport = $state(true);
  let fullMotion = false;
  let finePointerAvailable = false;

  function resetSpotlightTracking() {
    cardElement?.style.setProperty('--mouse-x', '50%');
    cardElement?.style.setProperty('--mouse-y', '50%');
  }

  // Easing function for smooth count-up animation
  function easeOutExpo(t: number): number {
    return t === 1 ? 1 : 1 - Math.pow(2, -10 * t);
  }

  onMount(() => {
    let startTimestamp: number | null = null;
    const duration = 1200; // 1.2s snappy count-up
    const target = totalTabs;
    let animationFrameId: number | null = null;
    let countUpFinished = false;
    let visibilityKnown = typeof IntersectionObserver === 'undefined';
    let inViewport = visibilityKnown;
    let observer: IntersectionObserver | null = null;
    let pointerQuery: MediaQueryList | null = null;

    function finishCountUp() {
      if (countUpFinished) return;
      countUpFinished = true;
      if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
      animatedCount = target;
    }

    function startCountUpOnce() {
      if (countUpFinished || animationFrameId !== null || !fullMotion || document.hidden || !inViewport) return;
      startTimestamp = null;
      animationFrameId = requestAnimationFrame(step);
    }

    function syncMotion() {
      if (!fullMotion || document.hidden) {
        finishCountUp();
        return;
      }
      if (visibilityKnown && inViewport) startCountUpOnce();
    }

    function step(timestamp: number) {
      animationFrameId = null;
      if (countUpFinished) return;
      if (!fullMotion || document.hidden || !inViewport) {
        finishCountUp();
        return;
      }
      if (!startTimestamp) startTimestamp = timestamp;
      const progress = Math.min((timestamp - startTimestamp) / duration, 1);
      const easedProgress = easeOutExpo(progress);
      animatedCount = Math.floor(easedProgress * target);

      if (progress < 1) {
        animationFrameId = requestAnimationFrame(step);
      } else {
        finishCountUp();
      }
    }

    if (cardElement && typeof IntersectionObserver !== 'undefined') {
      observer = new IntersectionObserver(
        (entries) => {
          const entry = entries[0];
          visibilityKnown = true;
          inViewport = entry ? entry.isIntersecting : false;
          isInViewport = inViewport;
          if (!inViewport) {
            resetSpotlightTracking();
            finishCountUp();
          }
          else syncMotion();
        },
        { threshold: 0.1 }
      );
      visibilityKnown = false;
      inViewport = false;
      isInViewport = false;
      observer.observe(cardElement);
    }

    try {
      pointerQuery = window.matchMedia('(pointer: fine)');
      finePointerAvailable = pointerQuery.matches;
    } catch {
      finePointerAvailable = false;
    }
    const handlePointerCapabilityChange = (event: MediaQueryListEvent) => {
      finePointerAvailable = event.matches;
      if (!finePointerAvailable) resetSpotlightTracking();
    };
    if (typeof pointerQuery?.addEventListener === 'function') {
      pointerQuery.addEventListener('change', handlePointerCapabilityChange);
    } else {
      pointerQuery?.addListener(handlePointerCapabilityChange);
    }

    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      fullMotion = mode === 'full';
      if (!fullMotion) resetSpotlightTracking();
      syncMotion();
    });

    const handleVisibility = () => {
      if (document.hidden) {
        resetSpotlightTracking();
        finishCountUp();
      }
      else syncMotion();
    };
    document.addEventListener('visibilitychange', handleVisibility);
    syncMotion();

    return () => {
      if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
      observer?.disconnect();
      document.removeEventListener('visibilitychange', handleVisibility);
      if (typeof pointerQuery?.removeEventListener === 'function') {
        pointerQuery.removeEventListener('change', handlePointerCapabilityChange);
      } else {
        pointerQuery?.removeListener(handlePointerCapabilityChange);
      }
      unsubscribeMotion();
    };
  });

  // Spotlight mousemove tracker (only active when in viewport)
  function handlePointerMove(e: PointerEvent) {
    if (!cardElement || !fullMotion || !finePointerAvailable || !isInViewport || document.hidden) return;
    const rect = cardElement.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    cardElement.style.setProperty('--mouse-x', `${x}px`);
    cardElement.style.setProperty('--mouse-y', `${y}px`);
  }
</script>

<div
  bind:this={cardElement}
  onpointermove={handlePointerMove}
  role="region"
  aria-label="曲谱搜索与聚光灯展示"
  class="spotlight-card render-contain-content gpu-layer relative overflow-hidden rounded-3xl border hairline bg-paper p-8 sm:p-12 lg:p-16 text-center shadow-sm"
  style="contain: content; transform: translateZ(0); --mouse-x: 50%; --mouse-y: 50%;"
>
  <!-- Background Glow & Grid Accent -->
  <div class="pointer-events-none absolute inset-0 bg-radial from-signal/5 via-transparent to-transparent opacity-60"></div>

  <!-- Music Note Particles Aura (Has built-in viewport dormancy) -->
  <MusicNoteParticles count={20} speed={0.42} opacity={0.15} className="absolute inset-0" />

  <div class="relative z-10 mx-auto max-w-3xl">
    <!-- Top Engineering Pill Badge -->
    <div class="animate-blur-up inline-flex items-center gap-2 rounded-pill border hairline bg-surface-alt/90 backdrop-blur-xs px-3.5 py-1 text-caption text-charcoal shadow-xs mb-6">
      <span class="flex h-2 w-2 rounded-full bg-signal"></span>
      <span class="font-mono font-medium uppercase tracking-wider text-ink">MIMI Guitar · Score Engine v2.0</span>
      <span class="text-mid-gray">|</span>
      <span class="font-medium text-signal">
        已收录 <strong class="tabular-nums font-semibold">{animatedCount.toLocaleString()}</strong> 份精选乐谱
      </span>
    </div>

    <!-- Main Headline with Tight Engineered Tracking & Cinematic Entrance -->
    <h1 class="animate-blur-up animate-blur-up-delay-1 font-display text-heading-lg sm:text-display text-ink leading-[1.08] tracking-tight">
      把每一份乐谱，<br class="hidden sm:inline" />
      都当作一页书来对待
    </h1>

    <p class="animate-blur-up animate-blur-up-delay-2 mx-auto mt-5 max-w-xl text-body-sm sm:text-subheading text-mid-gray leading-relaxed">
      吉他与尤克里里数字乐谱浏览器，支持六线谱与简谱并排渲染，并提供音频伴奏试听。
    </p>

    <!-- 18px Pill Search Form with ⌘K Badge and Focus Glow & Blur-Up Entrance -->
    <form
      action="/searchResults"
      method="get"
      class="animate-blur-up animate-blur-up-delay-3 mx-auto mt-8 max-w-lg transition-transform duration-150"
      class:scale-[1.01]={isFocused}
    >
      <div
        class="group relative flex items-center rounded-pill border hairline bg-surface-alt/95 backdrop-blur-xs p-1.5 shadow-sm transition-all duration-150 focus-within:border-signal focus-within:bg-paper focus-within:ring-2 focus-within:ring-signal/20"
      >
        <svg
          class="ml-3 h-4 w-4 shrink-0 text-mid-gray transition-colors duration-150 group-focus-within:text-signal"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="2"
        >
          <circle cx="11" cy="11" r="8"></circle>
          <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
        </svg>

        <input
          id="hero-search-input"
          type="search"
          name="searchValue"
          placeholder="搜索曲谱、歌手名、或和弦配音..."
          aria-label="搜索曲谱"
          onfocus={() => (isFocused = true)}
          onblur={() => (isFocused = false)}
          class="w-full bg-transparent px-3 py-2 text-body-sm text-ink outline-none placeholder:text-mid-gray"
        />

        <div class="mr-2 flex items-center gap-1.5 shrink-0">
          <kbd class="hidden sm:inline-block rounded-md border hairline bg-paper px-2 py-1 text-[11px] font-mono text-mid-gray shadow-xs">
            ⌘K
          </kbd>
          <button type="submit" class="btn btn-primary !py-2 !px-4 text-xs font-medium shadow-xs">
            检索
          </button>
        </div>
      </div>
    </form>

    <!-- Hot Search Chips (18px Pill Geometry) -->
    <div class="animate-blur-up animate-blur-up-delay-4 mt-6 flex flex-wrap items-center justify-center gap-2 text-caption">
      <span class="text-mid-gray font-medium">热门搜索：</span>
      {#each hotArtists as artist}
        <a
          href={`/searchResults?searchValue=${encodeURIComponent(artist)}`}
          class="chip !py-1 !px-3 text-xs text-charcoal hover:text-ink hover:border-signal/40 hover:bg-paper"
        >
          {artist}
        </a>
      {/each}
    </div>
  </div>
</div>
