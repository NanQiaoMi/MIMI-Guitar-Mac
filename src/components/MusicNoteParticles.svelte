<script lang="ts">
  import { subscribeMotionPreference, type MotionMode } from '../lib/ui/motionPreferences.ts';

  let {
    count = 16,
    speed = 0.6,
    color = '#41a1cf',
    symbols = ['♪', '♫', '♩', '♬', '𝄞', '♭', '♯', '✦'],
    interactive = true,
    minOpacity = 0.12,
    maxOpacity = 0.42,
    minSize = 13,
    maxSize = 26,
    className = '',
  }: {
    count?: number;
    speed?: number;
    color?: string;
    symbols?: string[];
    interactive?: boolean;
    minOpacity?: number;
    maxOpacity?: number;
    minSize?: number;
    maxSize?: number;
    className?: string;
  } = $props();

  let canvas: HTMLCanvasElement | null = $state(null);
  interface Particle {
    x: number;
    y: number;
    vx: number;
    vy: number;
    size: number;
    opacity: number;
    baseOpacity: number;
    symbol: string;
    fontStr: string;
    angle: number;
    spinSpeed: number;
    oscillationOffset: number;
    oscillationSpeed: number;
    isOrb: boolean;
  }

  $effect(() => {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animationFrameId: number | null = null;
    let width = (canvas.width = canvas.offsetWidth * (window.devicePixelRatio || 1));
    let height = (canvas.height = canvas.offsetHeight * (window.devicePixelRatio || 1));
    let dpr = window.devicePixelRatio || 1;
    let mode: MotionMode = 'off';
    let inViewport = typeof IntersectionObserver === 'undefined';
    let pointerIsCoarse = true;
    let pointerListenersAttached = false;
    let mouse = { x: -1000, y: -1000, active: false };
    let pointerMedia: MediaQueryList | null = null;
    const parent = canvas.parentElement;

    try {
      pointerMedia = window.matchMedia('(pointer: coarse)');
      pointerIsCoarse = pointerMedia.matches;
    } catch {
      // Without pointer capability information, leave pointer deflection disabled.
    }

    const resizeObserver = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(() => {
      if (!canvas) return;
      width = canvas.width = canvas.offsetWidth * (window.devicePixelRatio || 1);
      height = canvas.height = canvas.offsetHeight * (window.devicePixelRatio || 1);
      dpr = window.devicePixelRatio || 1;
      if (animationFrameId === null) draw(false);
    });
    resizeObserver?.observe(canvas);

    const particles: Particle[] = [];

    function createParticle(initial = false): Particle {
      const isOrb = Math.random() < 0.25;
      const size = Math.round(minSize + Math.random() * (maxSize - minSize));
      const baseOpacity = minOpacity + Math.random() * (maxOpacity - minOpacity);
      return {
        x: Math.random() * (width / dpr),
        y: initial ? Math.random() * (height / dpr) : (height / dpr) + size + Math.random() * 20,
        vx: (Math.random() - 0.5) * 0.3 * speed,
        vy: -(0.35 + Math.random() * 0.65) * speed,
        size,
        opacity: baseOpacity,
        baseOpacity,
        symbol: symbols[Math.floor(Math.random() * symbols.length)] ?? '♪',
        fontStr: `${size}px "Cascadia Code", "Inter", -apple-system, sans-serif`,
        angle: (Math.random() - 0.5) * 0.4,
        spinSpeed: (Math.random() - 0.5) * 0.008,
        oscillationOffset: Math.random() * Math.PI * 2,
        oscillationSpeed: 0.015 + Math.random() * 0.02,
        isOrb,
      };
    }

    for (let i = 0; i < count; i++) {
      particles.push(createParticle(true));
    }

    let lastTime = performance.now();

    function canAnimate() {
      return mode === 'full' && inViewport && !document.hidden;
    }

    function canDeflectPointer() {
      return interactive && canAnimate() && !pointerIsCoarse;
    }

    function draw(advance: boolean, currentTime?: number) {
      if (!ctx || !canvas) return;
      const dt = advance && currentTime !== undefined
        ? Math.min((currentTime - lastTime) / 16.666, 2.5)
        : 0;
      if (advance && currentTime !== undefined) lastTime = currentTime;

      ctx.clearRect(0, 0, width, height);

      const displayW = width / dpr;
      const displayH = height / dpr;

      // Static text setup outside hot loop
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      for (let i = 0; i < particles.length; i++) {
        const p = particles[i];

        if (advance) {
          // Harmonic upward & sinusoidal drift
          p.oscillationOffset += p.oscillationSpeed * dt;
          const driftX = Math.sin(p.oscillationOffset) * 0.45 * speed;
          p.x += (p.vx + driftX) * dt;
          p.y += p.vy * dt;
          p.angle += p.spinSpeed * dt;
        }

        // Pointer proximity deflection is reserved for full motion on fine pointers.
        if (advance && canDeflectPointer() && mouse.active) {
          const dx = p.x - mouse.x;
          const dy = p.y - mouse.y;
          const dist = Math.hypot(dx, dy);
          const maxDist = 110;
          if (dist < maxDist && dist > 0) {
            const force = (1 - dist / maxDist) * 1.2;
            p.x += (dx / dist) * force * 3 * dt;
            p.y += (dy / dist) * force * 3 * dt;
            p.opacity = Math.min(p.baseOpacity * 1.8, 0.85);
          } else {
            p.opacity += (p.baseOpacity - p.opacity) * 0.05 * dt;
          }
        } else if (advance) {
          p.opacity += (p.baseOpacity - p.opacity) * 0.05 * dt;
        }

        // Top boundary wrap around
        if (advance && (p.y < -p.size * 2 || p.x < -40 || p.x > displayW + 40)) {
          particles[i] = createParticle(false);
          continue;
        }

        // Fast matrix transform (no ctx.save/restore overhead)
        const cos = Math.cos(p.angle);
        const sin = Math.sin(p.angle);
        ctx.setTransform(dpr * cos, dpr * sin, -dpr * sin, dpr * cos, dpr * p.x, dpr * p.y);
        ctx.globalAlpha = Math.max(0, Math.min(1, p.opacity));

        if (p.isOrb) {
          // Harmonic glowing micro-orb with fast radial fill
          const gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, p.size * 0.5);
          gradient.addColorStop(0, color);
          gradient.addColorStop(0.6, color);
          gradient.addColorStop(1, 'transparent');
          ctx.fillStyle = gradient;
          ctx.beginPath();
          ctx.arc(0, 0, p.size * 0.5, 0, Math.PI * 2);
          ctx.fill();
        } else {
          // Fast direct fillText without slow shadowBlur
          ctx.fillStyle = color;
          ctx.font = p.fontStr;
          ctx.fillText(p.symbol, 0, 0);
        }
      }

      // Reset transform matrix and alpha
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.globalAlpha = 1.0;

    }

    function render(currentTime: number) {
      animationFrameId = null;
      if (!canAnimate()) {
        draw(false);
        return;
      }
      draw(true, currentTime);
      animationFrameId = requestAnimationFrame(render);
    }

    function handlePointerMove(e: PointerEvent) {
      if (!canvas || !canDeflectPointer()) return;
      const rect = canvas.getBoundingClientRect();
      mouse = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top,
        active: true,
      };
    }

    function handlePointerLeave() {
      mouse = { x: -1000, y: -1000, active: false };
    }

    function syncPointerListeners() {
      const shouldListen = canDeflectPointer() && Boolean(parent);
      if (shouldListen && !pointerListenersAttached && parent) {
        parent.addEventListener('pointermove', handlePointerMove);
        parent.addEventListener('pointerleave', handlePointerLeave);
        pointerListenersAttached = true;
      } else if (!shouldListen && pointerListenersAttached && parent) {
        parent.removeEventListener('pointermove', handlePointerMove);
        parent.removeEventListener('pointerleave', handlePointerLeave);
        pointerListenersAttached = false;
        handlePointerLeave();
      }
    }

    function syncAnimation() {
      syncPointerListeners();
      if (canAnimate()) {
        if (animationFrameId === null) {
          lastTime = performance.now();
          animationFrameId = requestAnimationFrame(render);
        }
        return;
      }

      if (animationFrameId !== null) {
        cancelAnimationFrame(animationFrameId);
        animationFrameId = null;
      }
      for (const particle of particles) particle.opacity = particle.baseOpacity;
      draw(false);
    }

    function handleVisibilityChange() {
      syncAnimation();
    }

    function handleIntersection(entries: IntersectionObserverEntry[]) {
      inViewport = entries.some((entry) => entry.isIntersecting);
      syncAnimation();
    }

    function handlePointerCapabilityChange(event: MediaQueryListEvent) {
      pointerIsCoarse = event.matches;
      syncAnimation();
    }

    const intersectionObserver = typeof IntersectionObserver === 'undefined'
      ? null
      : new IntersectionObserver(handleIntersection);
    intersectionObserver?.observe(canvas);

    const removePointerMediaListener = pointerMedia && typeof pointerMedia.addEventListener === 'function'
      ? (() => {
          pointerMedia?.addEventListener('change', handlePointerCapabilityChange);
          return () => pointerMedia?.removeEventListener('change', handlePointerCapabilityChange);
        })()
      : pointerMedia && typeof pointerMedia.addListener === 'function'
        ? (() => {
            pointerMedia?.addListener(handlePointerCapabilityChange);
            return () => pointerMedia?.removeListener(handlePointerCapabilityChange);
          })()
        : null;

    document.addEventListener('visibilitychange', handleVisibilityChange);
    const unsubscribeMotion = subscribeMotionPreference(({ mode: nextMode }) => {
      mode = nextMode;
      syncAnimation();
    });

    // Draw one stable frame in gentle/off; only full motion schedules animation frames.
    draw(false);

    return () => {
      if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
      resizeObserver?.disconnect();
      intersectionObserver?.disconnect();
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      removePointerMediaListener?.();
      unsubscribeMotion();
      if (pointerListenersAttached && parent) {
        parent.removeEventListener('pointermove', handlePointerMove);
        parent.removeEventListener('pointerleave', handlePointerLeave);
      }
    };
  });
</script>

<canvas
  bind:this={canvas}
  class="pointer-events-none absolute inset-0 h-full w-full overflow-hidden {className}"
  aria-hidden="true"
></canvas>
