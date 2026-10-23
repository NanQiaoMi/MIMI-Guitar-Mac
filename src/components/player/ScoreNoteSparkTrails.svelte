<script lang="ts">
  import {
    createPaperWatermarkNote,
    createPaperAcousticWaves,
    type ActiveNotePosition,
    type PaperWatermarkNote,
    type PaperAcousticWave,
  } from '../../lib/noteSparks';

  interface Props {
    api?: any;
    scoreContainer?: HTMLElement | null;
    activeNotePositions?: ActiveNotePosition[];
    isPlaying?: boolean;
    enabled?: boolean;
    className?: string;
  }

  let {
    api = null,
    scoreContainer = null,
    activeNotePositions = [],
    isPlaying = false,
    enabled = true,
    className = '',
  }: Props = $props();

  let containerEl: HTMLDivElement | null = $state(null);
  let canvasEl: HTMLCanvasElement | null = $state(null);

  let width = 0;
  let height = 0;
  let animId: number | null = null;
  let isVisible = true;

  let notes: PaperWatermarkNote[] = [];
  let waves: PaperAcousticWave[] = [];

  /**
   * Spawns subtle paper watermark notes & acoustic paper ripples at (x, y)
   */
  export function spawnNoteBurst(x: number, y: number, pitch?: number) {
    if (!enabled || width <= 0 || height <= 0) return;
    if (x < -50 || x > width + 50 || y < -50 || y > height + 50) return;

    // 1. Tactile paper watermark note
    notes.push(createPaperWatermarkNote(x, y, pitch));

    // 2. Subtle acoustic paper ripples
    const newWaves = createPaperAcousticWaves(x, y, pitch);
    waves.push(...newWaves);

    if (notes.length > 40) notes.splice(0, notes.length - 40);
    if (waves.length > 50) waves.splice(0, waves.length - 50);

    startLoop();
  }

  function resizeCanvas() {
    if (!canvasEl || !containerEl) return;
    const rect = containerEl.getBoundingClientRect();
    const w = Math.max(Math.floor(rect.width), 10);
    const h = Math.max(Math.floor(rect.height), 10);

    width = w;
    height = h;

    const dpr = Math.min(typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1, 2);
    canvasEl.width = Math.round(w * dpr);
    canvasEl.height = Math.round(h * dpr);
    canvasEl.style.width = `${w}px`;
    canvasEl.style.height = `${h}px`;

    const ctx = canvasEl.getContext('2d');
    if (ctx) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
    }
  }

  function render() {
    if (!canvasEl || (!isPlaying && notes.length === 0 && waves.length === 0)) {
      animId = null;
      return;
    }

    const ctx = canvasEl.getContext('2d');
    if (!ctx) return;

    ctx.clearRect(0, 0, width, height);

    // 1. Render acoustic paper ripples
    for (let i = waves.length - 1; i >= 0; i--) {
      const w = waves[i];
      w.radius += w.vRadius;
      const progress = w.radius / w.maxRadius;
      w.alpha = w.maxAlpha * (1 - progress);

      if (progress >= 1 || w.alpha <= 0.005) {
        waves.splice(i, 1);
        continue;
      }

      ctx.save();
      ctx.beginPath();
      ctx.arc(w.x, w.y, w.radius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(10, 10, 10, ${w.alpha.toFixed(3)})`;
      ctx.lineWidth = w.lineWidth;
      if (w.isStaveLine) {
        ctx.setLineDash([3, 5]);
      }
      ctx.stroke();
      ctx.restore();
    }

    // 2. Render embossed paper watermark notes
    for (let i = notes.length - 1; i >= 0; i--) {
      const n = notes[i];
      n.life -= n.decay;
      const progress = 1 - n.life;
      n.alpha = n.maxAlpha * Math.sin(Math.PI * n.life);
      n.scale = 0.9 + progress * 0.25;

      if (n.life <= 0 || n.alpha <= 0.005) {
        notes.splice(i, 1);
        continue;
      }

      ctx.save();
      ctx.translate(n.x, n.y);
      ctx.rotate(n.rotation);
      ctx.scale(n.scale, n.scale);

      // Subtle ink wash halo
      const grad = ctx.createRadialGradient(0, 0, 0, 0, 0, n.inkWashRadius);
      grad.addColorStop(0, `rgba(10, 10, 10, ${(n.alpha * 0.3).toFixed(3)})`);
      grad.addColorStop(1, 'rgba(10, 10, 10, 0)');
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(0, 0, n.inkWashRadius, 0, Math.PI * 2);
      ctx.fill();

      // Embossed paper watermark glyph
      ctx.font = `${n.size}px "Source Serif 4", Georgia, serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      // White emboss highlight
      ctx.fillStyle = `rgba(255, 255, 255, ${(n.alpha * 0.7).toFixed(3)})`;
      ctx.fillText(n.glyph, 0.5, 0.5);

      // Charcoal ink watermark
      ctx.fillStyle = `rgba(30, 30, 30, ${n.alpha.toFixed(3)})`;
      ctx.fillText(n.glyph, 0, 0);

      ctx.restore();
    }

    if (notes.length > 0 || waves.length > 0) {
      animId = requestAnimationFrame(render);
    } else {
      animId = null;
    }
  }

  function startLoop() {
    if (!animId && isVisible) {
      animId = requestAnimationFrame(render);
    }
  }

  $effect(() => {
    if (activeNotePositions && activeNotePositions.length > 0 && isPlaying) {
      for (const pos of activeNotePositions) {
        spawnNoteBurst(pos.x, pos.y, pos.pitch);
      }
    }
  });

  $effect(() => {
    if (!api || !enabled) return;

    const onBeatChanged = (beat: any) => {
      if (!isPlaying || !beat || !containerEl) return;

      try {
        const cursorEl = document.querySelector('#score-scroll .at-cursor-beat') as HTMLElement;
        if (!cursorEl || !containerEl) return;

        const contRect = containerEl.getBoundingClientRect();
        const cursorRect = cursorEl.getBoundingClientRect();

        const x = cursorRect.left - contRect.left + cursorRect.width / 2;
        const y = cursorRect.top - contRect.top + cursorRect.height / 2;

        if (x > 0 && x < width && y > 0 && y < height) {
          spawnNoteBurst(x, y);
        }
      } catch (err) {
        // Safe fallback
      }
    };

    api.playedBeatChanged?.on(onBeatChanged);

    return () => {
      try {
        api.playedBeatChanged?.off(onBeatChanged);
      } catch (_) {}
    };
  });

  $effect(() => {
    if (typeof window === 'undefined') return;

    resizeCanvas();
    const ro = new ResizeObserver(() => resizeCanvas());
    if (containerEl) ro.observe(containerEl);

    const onVisibility = () => {
      isVisible = !document.hidden;
      if (isVisible && (notes.length > 0 || waves.length > 0)) {
        startLoop();
      }
    };
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      ro.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      if (animId) cancelAnimationFrame(animId);
    };
  });
</script>

<div
  bind:this={containerEl}
  class="pointer-events-none absolute inset-0 z-0 overflow-hidden {className}"
  aria-hidden="true"
>
  <canvas bind:this={canvasEl} class="block h-full w-full opacity-70"></canvas>
</div>
