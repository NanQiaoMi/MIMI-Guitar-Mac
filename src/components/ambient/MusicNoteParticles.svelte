<script lang="ts">
  import { onMount } from 'svelte';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences';

  interface Props {
    count?: number;
    color?: string;
    opacity?: number;
    speed?: number;
    className?: string;
  }

  let {
    count = 16,
    color = '#41a1cf',
    opacity = 0.18,
    speed = 0.6,
    className = '',
  }: Props = $props();

  const NOTE_GLYPHS = ['♪', '♫', '♩', '♬', '𝄞', '𝄢', '✦'] as const;

  // 压印水印调色板：暖墨（主）-> 淡金 -> 深褐 -> 信号蓝点缀（少量）
  const NOTE_PALETTE = [
    { color: '#4a4036', weight: 0.42 }, // 暖墨 主
    { color: '#6b5f4d', weight: 0.2 },  // 灰褐
    { color: '#b89a5e', weight: 0.18 }, // 淡金
    { color: '#8a6f48', weight: 0.12 }, // 古铜
    { color: '#41a1cf', weight: 0.08 }, // 信号蓝 点缀
  ];

  function pickPalette(): string {
    let r = Math.random();
    for (const c of NOTE_PALETTE) {
      if (r < c.weight) return c.color;
      r -= c.weight;
    }
    return NOTE_PALETTE[0].color;
  }

  interface Particle {
    x: number;
    y: number;
    baseX: number;
    vx: number;
    vy: number;
    deflectX: number;
    deflectY: number;
    size: number;
    glyph: string;
    color: string;
    fontStr: string;
    sizeTier: number; // 0=远(小/淡) 1=中 2=近(大/略深)
    rotation: number;
    vRot: number;
    swayPhase: number;
    swaySpeed: number;
    swayAmp: number;
    alphaPhase: number;
    alphaSpeed: number;
    baseAlpha: number;
  }

  let containerEl: HTMLDivElement | null = $state(null);
  let canvasEl: HTMLCanvasElement | null = $state(null);

  // Runtime animation & dormancy state
  let animId: number | null = null;
  let lastTime = 0;
  let isIntersecting = false;
  let isPageVisible = true;
  let motionAllowed = false;
  let width = 0;
  let height = 0;
  let particles: Particle[] = [];

  // Mouse deflection state
  let mouseX = -9999;
  let mouseY = -9999;
  let mouseActive = false;

  function createParticle(w: number, h: number, randomizeY = true): Particle {
    const glyph = NOTE_GLYPHS[Math.floor(Math.random() * NOTE_GLYPHS.length)];
    const baseX = Math.random() * (w || 400);
    const y = randomizeY ? Math.random() * (h || 400) : (h || 400) + 15 + Math.random() * 40;
    // 景深分层：远（小/淡）68% · 中（中）22% · 近（大/略深）10%
    const tierRand = Math.random();
    const sizeTier = tierRand < 0.68 ? 0 : tierRand < 0.9 ? 1 : 2;
    const size = sizeTier === 0
      ? Math.floor(9 + Math.random() * 9)   // 9~18px 远
      : sizeTier === 1
        ? Math.floor(15 + Math.random() * 10) // 15~25px 中
        : Math.floor(22 + Math.random() * 12); // 22~34px 近
    const baseSpeed = (0.18 + Math.random() * 0.3) * Math.max(0.1, speed);

    return {
      x: baseX,
      y,
      baseX,
      vx: 0,
      vy: -baseSpeed,
      deflectX: 0,
      deflectY: 0,
      size,
      glyph,
      color: pickPalette(),
      fontStr: `${size}px "Inter", "Segoe UI Symbol", "Apple Color Emoji", -apple-system, sans-serif`,
      sizeTier,
      // 更安静：旋转幅度减半、摆动更缓
      rotation: (Math.random() - 0.5) * 0.24,
      vRot: (Math.random() - 0.5) * 0.005,
      swayPhase: Math.random() * Math.PI * 2,
      swaySpeed: 0.008 + Math.random() * 0.012,
      swayAmp: 22 + Math.random() * 26,
      alphaPhase: Math.random() * Math.PI * 2,
      alphaSpeed: 0.015 + Math.random() * 0.018,
      // 深度透明度：近略深、远更淡
      baseAlpha: sizeTier === 0 ? 0.35 + Math.random() * 0.3 : sizeTier === 1 ? 0.5 + Math.random() * 0.3 : 0.6 + Math.random() * 0.32,
    };
  }

  function initParticles() {
    if (width <= 0 || height <= 0) return;
    const targetCount = Math.max(1, Math.min(count, 80));
    const newParticles: Particle[] = [];
    for (let i = 0; i < targetCount; i++) {
      newParticles.push(createParticle(width, height, true));
    }
    particles = newParticles;
  }

  function resizeCanvas() {
    if (!canvasEl || !containerEl) return;
    const rect = containerEl.getBoundingClientRect();
    const w = Math.max(Math.floor(rect.width), 10);
    const h = Math.max(Math.floor(rect.height), 10);

    const prevW = width;
    const prevH = height;
    width = w;
    height = h;

    const dpr = Math.min(typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1, 2.0);
    canvasEl.width = Math.round(w * dpr);
    canvasEl.height = Math.round(h * dpr);
    canvasEl.style.width = `${w}px`;
    canvasEl.style.height = `${h}px`;

    const ctx = canvasEl.getContext('2d');
    if (ctx) {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    if (particles.length === 0 || Math.abs(prevW - w) > 80 || Math.abs(prevH - h) > 80) {
      initParticles();
    }
  }

  function updateAndDraw(ctx: CanvasRenderingContext2D, dt: number) {
    ctx.clearRect(0, 0, width, height);

    const timeScale = Math.min(dt / 16.667, 3.0);
    const mouseRadius = 150;
    const mouseRadiusSq = mouseRadius * mouseRadius;
    const dpr = Math.min(typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1, 2.0);

    // Static text baseline and alignment outside the hot loop
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];

      // 1. Upward motion
      p.y += p.vy * timeScale * (speed / 0.6);

      // 2. Sinusoidal sway
      p.swayPhase += p.swaySpeed * timeScale;
      const swayOffset = Math.sin(p.swayPhase) * p.swayAmp;

      // 3. Rotation
      p.rotation += p.vRot * timeScale;

      // 4. Alpha pulse
      p.alphaPhase += p.alphaSpeed * timeScale;

      // 5. Mouse fluid deflection physics
      if (mouseActive) {
        const curX = p.baseX + swayOffset + p.deflectX;
        const curY = p.y + p.deflectY;
        const dx = curX - mouseX;
        const dy = curY - mouseY;
        const distSq = dx * dx + dy * dy;

        if (distSq < mouseRadiusSq && distSq > 1) {
          const dist = Math.sqrt(distSq);
          const force = (1 - dist / mouseRadius) * 2.2;
          const angle = Math.atan2(dy, dx);
          p.deflectX += Math.cos(angle) * force * timeScale;
          p.deflectY += Math.sin(angle) * force * 0.7 * timeScale;
        }
      }

      // Smooth decay of deflection back to neutral trajectory
      p.deflectX *= Math.pow(0.92, timeScale);
      p.deflectY *= Math.pow(0.92, timeScale);

      p.x = p.baseX + swayOffset + p.deflectX;
      const finalY = p.y + p.deflectY;

      // 6. Respawn when floating past top boundary
      if (finalY < -50) {
        const recycled = createParticle(width, height, false);
        particles[i] = recycled;
        continue;
      }

      // 7. Windowing fade at bottom and top edges for natural appearance
      let edgeFactor = 1.0;
      if (finalY < 70) {
        edgeFactor = Math.max(0, (finalY + 30) / 100);
      } else if (finalY > height - 60) {
        edgeFactor = Math.max(0, (height - finalY) / 60);
      }

      const pulseAlpha = 0.65 + 0.35 * Math.sin(p.alphaPhase);
      const computedAlpha = Math.max(
        0,
        Math.min(1, opacity * p.baseAlpha * pulseAlpha * edgeFactor)
      );

      if (computedAlpha <= 0.005) continue;

      // 8. 极速单次 fillText 绘制（无 strokeText 矢量轮廓开销，<0.05ms 超低耗时）
      const cos = Math.cos(p.rotation);
      const sin = Math.sin(p.rotation);
      ctx.setTransform(dpr * cos, dpr * sin, -dpr * sin, dpr * cos, dpr * p.x, dpr * finalY);

      ctx.font = p.fontStr;
      const tierAlpha = computedAlpha * (p.sizeTier === 0 ? 0.62 : p.sizeTier === 1 ? 0.82 : 1);
      ctx.globalAlpha = Math.max(0, Math.min(1, tierAlpha));

      // 单次实心/半透明水墨压印绘制
      ctx.fillStyle = p.color;
      ctx.fillText(p.glyph, 0, 0);
    }

    // 重置变换矩阵与 globalAlpha
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.globalAlpha = 1.0;
  }

  function startLoop() {
    if (animId !== null) return;
    lastTime = performance.now();

    function frame(timestamp: number) {
      if (!motionAllowed || !isIntersecting || !isPageVisible || !canvasEl) {
        animId = null;
        return;
      }

      const dt = Math.max(1, Math.min(timestamp - lastTime, 50));
      lastTime = timestamp;

      const ctx = canvasEl.getContext('2d');
      if (ctx && width > 0 && height > 0) {
        updateAndDraw(ctx, dt);
      }

      animId = requestAnimationFrame(frame);
    }

    animId = requestAnimationFrame(frame);
  }

  function stopLoop() {
    if (animId !== null) {
      cancelAnimationFrame(animId);
      animId = null;
    }
  }

  function updateRunningState() {
    if (motionAllowed && isIntersecting && isPageVisible && width > 0 && height > 0) {
      startLoop();
    } else {
      stopLoop();
    }
  }

  // Reactivity for count / speed / color / opacity
  $effect(() => {
    // When count changes, rebalance particle array
    if (width > 0 && height > 0) {
      if (particles.length !== count) {
        initParticles();
      }
    }
  });

  onMount(() => {
    if (!containerEl || !canvasEl) return;

    isPageVisible = !document.hidden;
    resizeCanvas();
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      motionAllowed = mode === 'full';
      mouseActive = false;
      updateRunningState();
      if (!motionAllowed) canvasEl?.getContext('2d')?.clearRect(0, 0, width, height);
    });

    const resizeObserver = new ResizeObserver(() => {
      resizeCanvas();
    });
    resizeObserver.observe(containerEl);

    // Viewport IntersectionObserver to hibernate when scrolled out of view
    const intersectionObserver = new IntersectionObserver((entries) => {
      const entry = entries[0];
      isIntersecting = entry ? entry.isIntersecting : false;
      updateRunningState();
    }, { threshold: 0 });
    intersectionObserver.observe(containerEl);

    // Mouse move listeners on window / container for fluid deflection
    function handleMouseMove(e: MouseEvent) {
      if (!motionAllowed || !isIntersecting || !isPageVisible || !containerEl || !window.matchMedia('(hover: hover) and (pointer: fine)').matches) return;
      const rect = containerEl.getBoundingClientRect();
      const clientX = e.clientX;
      const clientY = e.clientY;

      if (
        clientX >= rect.left - 60 &&
        clientX <= rect.right + 60 &&
        clientY >= rect.top - 60 &&
        clientY <= rect.bottom + 60
      ) {
        mouseX = clientX - rect.left;
        mouseY = clientY - rect.top;
        mouseActive = true;
      } else {
        mouseActive = false;
      }
    }

    function handleMouseLeave() {
      mouseActive = false;
      mouseX = -9999;
      mouseY = -9999;
    }

    window.addEventListener('mousemove', handleMouseMove, { passive: true });
    document.addEventListener('mouseleave', handleMouseLeave);

    // Visibility API listener to save CPU/battery when browser tab is inactive
    function handleVisibilityChange() {
      if (typeof document === 'undefined') return;
      isPageVisible = !document.hidden;
      updateRunningState();
    }

    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      window.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseleave', handleMouseLeave);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      unsubscribeMotion();
      stopLoop();
    };
  });
</script>

<div
  bind:this={containerEl}
  class="ambient-note-particles pointer-events-none absolute inset-0 overflow-hidden select-none {className}"
  aria-hidden="true"
>
  <canvas
    bind:this={canvasEl}
    class="motion-ambient block h-full w-full pointer-events-none"
  ></canvas>
</div>

<style>
  .ambient-note-particles {
    contain: strict;
  }
</style>

