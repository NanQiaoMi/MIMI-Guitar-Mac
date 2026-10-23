<script lang="ts">
  import { onMount } from 'svelte';
  import { initAudioUnlocker } from '../../lib/audioUnlocker';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences';

  // 1. Audio and Beat state
  let isPlaying = $state(false);
  let isBeatPulsing = $state(false);
  let animateDecorations = $state(false);

  // Pointer feedback is batched into one pending frame and disabled when unnecessary.
  let wingsContainer: HTMLElement | null = $state(null);

  onMount(() => {
    if (typeof window === 'undefined') return;
    try {
      initAudioUnlocker();
    } catch {}

    // A. Audio playback state sync
    const handlePlaybackState = (e: any) => {
      isPlaying = !!e.detail?.isPlaying;
    };

    // B. Beat pulse synchronization
    let pulseTimer: ReturnType<typeof setTimeout> | null = null;
    const handleBeatPulse = () => {
      if (!animateDecorations) return;
      isBeatPulsing = true;
      if (pulseTimer) clearTimeout(pulseTimer);
      pulseTimer = setTimeout(() => {
        isBeatPulsing = false;
      }, 190);
    };

    // C. Bounded parallax for visible, full-motion desktop surfaces only.
    let rafId: number | null = null;
    let targetNormX = 0;
    let targetNormY = 0;

    const updateParallax = () => {
      if (wingsContainer) {
        // Shift left and right staves by 4px to 6px
        const shiftX = targetNormX * 5.2; // ~ -5.2px to +5.2px
        const shiftY = targetNormY * 4.8; // ~ -4.8px to +4.8px
        wingsContainer.style.setProperty('--shift-x', `${shiftX.toFixed(2)}px`);
        wingsContainer.style.setProperty('--shift-y', `${shiftY.toFixed(2)}px`);
      }
      rafId = null;
    };

    const handleMouseMove = (e: MouseEvent) => {
      if (!animateDecorations || !pointerQuery.matches) return;
      // Normalized coordinate from -1 to 1 centered on screen
      targetNormX = (e.clientX / window.innerWidth - 0.5) * 2;
      targetNormY = (e.clientY / window.innerHeight - 0.5) * 2;
      if (rafId === null) {
        rafId = requestAnimationFrame(updateParallax);
      }
    };

    const pointerQuery = window.matchMedia('(min-width: 768px) and (hover: hover) and (pointer: fine)');
    let fullMotion = false;
    const updateActivity = () => {
      animateDecorations = fullMotion && !document.hidden && pointerQuery.matches;
      if (!animateDecorations) {
        if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
        }
        if (pulseTimer) clearTimeout(pulseTimer);
        pulseTimer = null;
        isBeatPulsing = false;
        targetNormX = 0;
        targetNormY = 0;
        wingsContainer?.style.setProperty('--shift-x', '0px');
        wingsContainer?.style.setProperty('--shift-y', '0px');
      }
    };
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      fullMotion = mode === 'full';
      updateActivity();
    });
    pointerQuery.addEventListener('change', updateActivity);

    window.addEventListener('mimi:playback-state', handlePlaybackState);
    window.addEventListener('mimi:beat-pulse', handleBeatPulse);
    window.addEventListener('mousemove', handleMouseMove, { passive: true });
    document.addEventListener('visibilitychange', updateActivity);

    return () => {
      if (rafId !== null) cancelAnimationFrame(rafId);
      if (pulseTimer) clearTimeout(pulseTimer);
      window.removeEventListener('mimi:playback-state', handlePlaybackState);
      window.removeEventListener('mimi:beat-pulse', handleBeatPulse);
      window.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('visibilitychange', updateActivity);
      pointerQuery.removeEventListener('change', updateActivity);
      unsubscribeMotion();
    };
  });
</script>

<div
  class="pointer-events-none fixed inset-0 z-0 overflow-hidden select-none isolate"
  style="contain: strict;"
  aria-hidden="true"
>
  <!-- Layer 1: Base Tactile Parchment Paper Grain (Procedural SVG Turbulence, 0 requests, 3.5% opacity) -->
  <div class="paper-grain-texture pointer-events-none" aria-hidden="true"></div>

  <!-- Layer 2 & 3: Left and Right Wings Staves System with Mouse Parallax and Audio Resonance -->
  <div
    bind:this={wingsContainer}
    class="stave-wings-container motion-ambient pointer-events-none"
    class:is-playing={isPlaying && animateDecorations}
    class:beat-pulse={isBeatPulsing}
  >
    <!-- Left Wing Staves -->
    <div class="stave-wing stave-wing-left" aria-hidden="true">
      <div class="stave-lines"></div>
      <div class="stave-acoustic-glow" aria-hidden="true"></div>
    </div>

    <!-- Right Wing Staves -->
    <div class="stave-wing stave-wing-right" aria-hidden="true">
      <div class="stave-lines"></div>
      <div class="stave-acoustic-glow" aria-hidden="true"></div>
    </div>
  </div>
</div>

<style>
  /* ==========================================================================
     Layer 1: Base Tactile Parchment Paper Grain
     Ultra-fine procedural SVG fractal noise fiber at 3.5% opacity,
     0 network latency, 0 image requests, hardware GPU tiled rasterization.
     ========================================================================== */
  .paper-grain-texture {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0.035; /* 3.5% opacity matching 3%-4% specification */
    mix-blend-mode: multiply;
    background-repeat: repeat;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='paperNoise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.82' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix type='matrix' values='0 0 0 0 0.17 0 0 0 0 0.14 0 0 0 0 0.09 0 0 0 0.9 0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23paperNoise)'/%3E%3C/svg%3E");
    contain: strict;
  }

  /* ==========================================================================
     Layer 2 & 3: Artisanal Staves Wings & Resonance System
     ========================================================================== */
  .stave-wings-container {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    contain: strict;
    --shift-x: 0px;
    --shift-y: 0px;
    --stave-shadow-color: rgba(196, 154, 69, 0.14);
    --stave-glow-opacity: 0;
    transition: opacity 300ms ease;
  }

  /* Playing state: golden staves gain warm breathing acoustic resonance */
  .stave-wings-container.is-playing {
    --stave-shadow-color: rgba(196, 154, 69, 0.28);
    --stave-glow-opacity: 0.45;
  }

  /* Beat pulse: momentary energetic pulse resonance */
  .stave-wings-container.beat-pulse {
    --stave-shadow-color: rgba(196, 154, 69, 0.42);
    --stave-glow-opacity: 0.85;
  }

  /* Wing containers positioned strictly at outer left & right margins */
  .stave-wing {
    position: absolute;
    top: 0;
    bottom: 0;
    width: clamp(190px, 17vw, 240px);
    contain: strict;
    pointer-events: none;
  }

  /* 
   * Left Wing:
   * Masks out lines towards the center of viewport across 180px-240px fade width.
   * Mouse parallax shifts subtly by 4px-6px via GPU transform.
   */
  .stave-wing-left {
    left: 0;
    transform: translate3d(var(--shift-x, 0px), var(--shift-y, 0px), 0);
    mask-image: linear-gradient(to right, rgba(0, 0, 0, 1) 0%, rgba(0, 0, 0, 0.75) 40%, rgba(0, 0, 0, 0) 100%);
    -webkit-mask-image: linear-gradient(to right, rgba(0, 0, 0, 1) 0%, rgba(0, 0, 0, 0.75) 40%, rgba(0, 0, 0, 0) 100%);
  }

  /* 
   * Right Wing:
   * Symmetrically masks out lines towards the center of viewport.
   * Parallax subtly counter-shifts for depth.
   */
  .stave-wing-right {
    right: 0;
    transform: translate3d(calc(-0.85 * var(--shift-x, 0px)), var(--shift-y, 0px), 0);
    mask-image: linear-gradient(to left, rgba(0, 0, 0, 1) 0%, rgba(0, 0, 0, 0.75) 40%, rgba(0, 0, 0, 0) 100%);
    -webkit-mask-image: linear-gradient(to left, rgba(0, 0, 0, 1) 0%, rgba(0, 0, 0, 0.75) 40%, rgba(0, 0, 0, 0) 100%);
  }

  /* 
   * Stave System Rhythm:
   * Standard 5-line groupings (line spacing 3.2px, group spacing ~68px), repeated vertically.
   * Dual-tone intaglio debossed effect:
   * 1px top highlight rgba(255, 255, 255, 0.75)
   * 1px bottom warm antique gold shadow var(--stave-shadow-color)
   */
  .stave-lines {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    background-image: repeating-linear-gradient(
      to bottom,
      /* Line 1 (0px to 2px) */
      rgba(255, 255, 255, 0.75) 0px,
      rgba(255, 255, 255, 0.75) 1px,
      var(--stave-shadow-color) 1px,
      var(--stave-shadow-color) 2px,
      transparent 2px,
      transparent 5.2px,

      /* Line 2 (5.2px to 7.2px, spacing 3.2px) */
      rgba(255, 255, 255, 0.75) 5.2px,
      rgba(255, 255, 255, 0.75) 6.2px,
      var(--stave-shadow-color) 6.2px,
      var(--stave-shadow-color) 7.2px,
      transparent 7.2px,
      transparent 10.4px,

      /* Line 3 (10.4px to 12.4px, spacing 3.2px) */
      rgba(255, 255, 255, 0.75) 10.4px,
      rgba(255, 255, 255, 0.75) 11.4px,
      var(--stave-shadow-color) 11.4px,
      var(--stave-shadow-color) 12.4px,
      transparent 12.4px,
      transparent 15.6px,

      /* Line 4 (15.6px to 17.6px, spacing 3.2px) */
      rgba(255, 255, 255, 0.75) 15.6px,
      rgba(255, 255, 255, 0.75) 16.6px,
      var(--stave-shadow-color) 16.6px,
      var(--stave-shadow-color) 17.6px,
      transparent 17.6px,
      transparent 20.8px,

      /* Line 5 (20.8px to 22.8px, spacing 3.2px) */
      rgba(255, 255, 255, 0.75) 20.8px,
      rgba(255, 255, 255, 0.75) 21.8px,
      var(--stave-shadow-color) 21.8px,
      var(--stave-shadow-color) 22.8px,
      transparent 22.8px,

      /* Inter-group spacing ~68px (22.8px + 68px = 90.8px cycle) */
      transparent 90.8px
    );
    transition: filter 300ms ease;
  }

  /* 
   * Warm Breathing Acoustic Glow
   * Soft ambient aura that breathes gently during playback and pulses on beat
   */
  .stave-acoustic-glow {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: var(--stave-glow-opacity);
    background: radial-gradient(
      ellipse 80% 60% at 50% 50%,
      rgba(196, 154, 69, 0.28) 0%,
      rgba(196, 154, 69, 0.10) 45%,
      transparent 100%
    );
    mix-blend-mode: color-burn;
    pointer-events: none;
    transition: opacity 220ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  .stave-wings-container.is-playing .stave-acoustic-glow {
    animation: acoustic-breathe 4s ease-in-out infinite alternate;
  }

  @keyframes acoustic-breathe {
    0% {
      opacity: 0.30;
      transform: scale(0.98);
    }
    100% {
      opacity: 0.55;
      transform: scale(1.02);
    }
  }

  .stave-wings-container.beat-pulse .stave-acoustic-glow {
    opacity: 0.90;
    filter: brightness(1.25);
    transition: opacity 80ms ease-out, filter 80ms ease-out;
  }

  /* ==========================================================================
     Responsive Design:
     On screens < 768px (mobile phones), smoothly fade out staves wings to
     preserve pure paper texture and warm ambient glow for unobstructed mobile reading.
     ========================================================================== */
  @media (max-width: 767px) {
    .stave-wings-container {
      opacity: 0 !important;
      visibility: hidden;
      pointer-events: none;
    }
  }
</style>
