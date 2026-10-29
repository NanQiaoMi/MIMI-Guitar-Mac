<script lang="ts">
  let {
    isPlaying = false,
    bpm = 72,
    color = '#0a0a0a',
    height = 32,
    width = 140,
  }: {
    isPlaying?: boolean;
    bpm?: number;
    color?: string;
    height?: number;
    width?: number;
  } = $props();

  let canvas: HTMLCanvasElement | null = $state(null);

  // Animation & Physics State
  let animId: number | null = null;
  let currentAmp = 0;
  let phase1 = 0;
  let phase2 = 0;
  let lastTimestamp = 0;
  let isVisible = true;

  function resizeCanvas() {
    if (!canvas) return;
    const dpr = Math.min(typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1, 2.5);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
    }
  }

  function drawFrame(ctx: CanvasRenderingContext2D, dt: number) {
    ctx.clearRect(0, 0, width, height);

    const midY = height / 2;
    // Target amplitude: when playing ~36% of height, otherwise 0
    const targetAmp = isPlaying ? (height * 0.36) : 0;
    
    // Smooth amplitude interpolation (lerp)
    currentAmp += (targetAmp - currentAmp) * 0.085;

    // Tempo factor drives undulating phase speed
    const tempoFactor = Math.max(0.4, Math.min(2.8, (bpm || 72) / 72));
    const speed = (dt / 16.667) * 0.045 * tempoFactor;

    phase1 += speed;
    phase2 += speed * 0.73;

    // Always render subtle datum baseline underneath
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.globalAlpha = 0.12;
    ctx.lineWidth = 1;
    ctx.moveTo(0, midY);
    ctx.lineTo(width, midY);
    ctx.stroke();

    // If completely flat, avoid computing curves
    if (currentAmp < 0.001 && !isPlaying) {
      currentAmp = 0;
      return false; // loop can pause
    }

    const step = 2; // pixel step for smooth curve rendering
    const k1 = (Math.PI * 2) / (width * 0.46);
    const k2 = (Math.PI * 2) / (width * 0.88);
    const k3 = (Math.PI * 2) / (width * 0.62);
    const k4 = (Math.PI * 2) / (width * 0.34);

    // --- Layer 2: Secondary Harmonic Wave (Fluid Counter-Wave) ---
    ctx.beginPath();
    // Use accent signal blue if primary color is monochrome dark, otherwise matching tint with alpha
    const isDark = color === '#0a0a0a' || color === '#000000' || color === '#171717' || color === '#2c2c2c';
    ctx.strokeStyle = isDark ? '#41a1cf' : color;
    ctx.globalAlpha = isPlaying ? 0.45 : 0.15;
    ctx.lineWidth = 1.4;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    for (let x = 0; x <= width; x += step) {
      const normX = x / width;
      // Smooth sinusoidal envelope windowing so waves taper to 0 at left & right borders
      const envelope = Math.sin(normX * Math.PI);
      const wave2 = (Math.cos(x * k3 - phase1 * 1.2) * 0.65 + Math.sin(x * k4 + phase2 * 1.1) * 0.35);
      const y = midY + wave2 * envelope * (currentAmp * 0.72);

      if (x === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // --- Layer 1: Primary Fluid Sine/Cosine Wave ---
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.globalAlpha = isPlaying ? 0.92 : 0.3;
    ctx.lineWidth = 1.8;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    for (let x = 0; x <= width; x += step) {
      const normX = x / width;
      const envelope = Math.sin(normX * Math.PI);
      const wave1 = (Math.sin(x * k1 + phase1) * 0.72 + Math.cos(x * k2 - phase2 * 0.85) * 0.28);
      const y = midY + wave1 * envelope * currentAmp;

      if (x === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    return true; // continue running
  }

  function startLoop() {
    if (animId !== null) return;
    lastTimestamp = performance.now();

    function render(timestamp: number) {
      if (!isVisible || !canvas) {
        animId = null;
        return;
      }

      const dt = Math.min(timestamp - lastTimestamp, 50);
      lastTimestamp = timestamp;

      const ctx = canvas.getContext('2d');
      if (ctx) {
        const shouldContinue = drawFrame(ctx, dt);
        if (shouldContinue || isPlaying) {
          animId = requestAnimationFrame(render);
        } else {
          animId = null;
        }
      } else {
        animId = null;
      }
    }

    animId = requestAnimationFrame(render);
  }

  function stopLoop() {
    if (animId !== null) {
      cancelAnimationFrame(animId);
      animId = null;
    }
  }

  $effect(() => {
    // React to size / color / isPlaying / bpm changes
    if (canvas) {
      resizeCanvas();
      startLoop();
    }
  });

  $effect(() => {
    // Visibility API listener to save CPU/battery when browser tab is inactive
    function handleVisibilityChange() {
      if (typeof document === 'undefined') return;
      if (document.hidden) {
        isVisible = false;
        stopLoop();
      } else {
        isVisible = true;
        lastTimestamp = performance.now();
        startLoop();
      }
    }

    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', handleVisibilityChange);
    }

    return () => {
      if (typeof document !== 'undefined') {
        document.removeEventListener('visibilitychange', handleVisibilityChange);
      }
      stopLoop();
    };
  });
</script>

<div
  class="relative inline-flex items-center justify-center overflow-hidden rounded-pill select-none"
  style="width: {width}px; height: {height}px;"
  title={isPlaying ? `声波律动 · ♩= ${bpm}` : '未播放'}
>
  <canvas
    bind:this={canvas}
    class="block pointer-events-none"
    style="width: {width}px; height: {height}px;"
    aria-hidden="true"
  ></canvas>
</div>
