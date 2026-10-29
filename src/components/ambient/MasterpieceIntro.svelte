<script lang="ts">
  import { onMount } from 'svelte';
  import { getMotionPreferenceSnapshot, subscribeMotionPreference } from '../../lib/ui/motionPreferences';

  // Props - autoPlay controls whether the intro plays on mount
  let { autoPlay = true }: { autoPlay?: boolean } = $props();

  // --- Svelte 5 Runes State ---
  let isShowing = $state(false);
  let isExiting = $state(false);
  let phase = $state<'idle' | 'unveil' | 'ink_bloom' | 'title_emerge' | 'motto' | 'exit'>('idle');

  // Fine-grained animation phase triggers
  let inkRevealed = $state(false);
  let borderDrawn = $state(false);
  let titleVisible = $state(false);
  let subtitleVisible = $state(false);
  let mottoVisible = $state(false);
  let progressPercent = $state(0);
  let particlesReady = $state(false);

  let containerEl = $state<HTMLDivElement | null>(null);
  let canvasEl = $state<HTMLCanvasElement | null>(null);

  // Audio
  let audioCtx: AudioContext | null = null;
  let animFrameId: number | null = null;
  let timers: ReturnType<typeof setTimeout>[] = [];
  let progressInterval: ReturnType<typeof setInterval>[] = [];

  // --- Particle Systems ---
  interface InkParticle {
    x: number; y: number;
    size: number;
    opacity: number;
    rotation: number;
    rotSpeed: number;
    vx: number; vy: number;
    char: string;
    color: string;
    fontStr: string;
    fadeIn: number;
    life: number;
    maxLife: number;
  }

  interface PaperFiber {
    x: number; y: number;
    length: number;
    angle: number;
    opacity: number;
    drift: number;
  }

  interface GoldenDust {
    x: number; y: number;
    size: number;
    opacity: number;
    twinkleSpeed: number;
    twinklePhase: number;
    vx: number; vy: number;
  }

  let inkParticles: InkParticle[] = [];
  let paperFibers: PaperFiber[] = [];
  let goldenDust: GoldenDust[] = [];

  // Ink reveal progress (0 to 1)
  let inkProgress = 0;
  let inkTargetProgress = 0;

  // Music notation characters for floating particles
  const MUSIC_CHARS = ['♩', '♪', '♫', '♬', '♭', '♮', '♯', '𝄞', '𝄢', '𝅘𝅥', '𝅘𝅥𝅮', '𝅗𝅥', '◆', '✦', '❋'];
  const WARM_PALETTE = [
    'rgba(176, 141, 87,',   // amber gold
    'rgba(162, 128, 78,',   // antique bronze
    'rgba(142, 112, 68,',   // warm umber
    'rgba(120, 96, 58,',    // deep sienna
    'rgba(86, 70, 48,',     // dark walnut
    'rgba(65, 161, 207,',   // signal blue (accent)
  ];

  function clearAllTimers() {
    timers.forEach((t) => clearTimeout(t));
    timers = [];
    progressInterval.forEach((i) => clearInterval(i));
    progressInterval = [];
  }

  // --- Web Audio ---
  let audioUnlockBound = false;
  let unbindAudioUnlock: (() => void) | null = null;
  function bindAudioUnlock() {
    if (audioUnlockBound || typeof window === 'undefined') return;
    audioUnlockBound = true;
    const unlock = () => {
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume().catch(() => {});
      }
    };
    window.addEventListener('pointerdown', unlock, { passive: true });
    window.addEventListener('touchstart', unlock, { passive: true });
    window.addEventListener('keydown', unlock, { passive: true });
    unbindAudioUnlock = () => {
      window.removeEventListener('pointerdown', unlock);
      window.removeEventListener('touchstart', unlock);
      window.removeEventListener('keydown', unlock);
      audioUnlockBound = false;
    };
  }

  function getOrCreateAudioContext(): AudioContext | null {
    try {
      const AC = window.AudioContext || (window as any).webkitAudioContext;
      if (!AC) return null;
      if (!audioCtx || audioCtx.state === 'closed') {
        audioCtx = new AC({ latencyHint: 'interactive' });
      }
      if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {});
      return audioCtx;
    } catch (_) { return null; }
  }

  // Warm ambient room tone (paper rustling, soft air)
  function playAmbientAtmosphere() {
    const ctx = getOrCreateAudioContext();
    if (!ctx) return;
    try {
      const now = ctx.currentTime;
      const duration = 2.8;
      const bufferSize = Math.floor(ctx.sampleRate * duration);
      const noiseBuffer = ctx.createBuffer(2, bufferSize, ctx.sampleRate);
      const left = noiseBuffer.getChannelData(0);
      const right = noiseBuffer.getChannelData(1);

      let b0L = 0, b1L = 0, b2L = 0;
      let b0R = 0, b1R = 0, b2R = 0;
      for (let i = 0; i < bufferSize; i++) {
        const wL = Math.random() * 2 - 1;
        b0L = 0.99886 * b0L + wL * 0.0555179;
        b1L = 0.99332 * b1L + wL * 0.0750759;
        b2L = 0.96900 * b2L + wL * 0.1538520;
        left[i] = (b0L + b1L + b2L + wL * 0.5362) * 0.008;

        const wR = Math.random() * 2 - 1;
        b0R = 0.99886 * b0R + wR * 0.0555179;
        b1R = 0.99332 * b1R + wR * 0.0750759;
        b2R = 0.96900 * b2R + wR * 0.1538520;
        right[i] = (b0R + b1R + b2R + wR * 0.5362) * 0.008;
      }

      const src = ctx.createBufferSource();
      src.buffer = noiseBuffer;
      const filter = ctx.createBiquadFilter();
      filter.type = 'bandpass';
      filter.frequency.setValueAtTime(600, now);
      filter.Q.setValueAtTime(0.6, now);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.linearRampToValueAtTime(0.035, now + 0.5);
      gain.gain.setValueAtTime(0.035, now + 1.8);
      gain.gain.exponentialRampToValueAtTime(0.00001, now + duration);
      src.connect(filter);
      filter.connect(gain);
      gain.connect(ctx.destination);
      src.start(now);
      src.stop(now + duration);
    } catch (_) {}
  }

  // Gentle guitar chord: A warm open Am7 arpeggio
  function playOpeningChord() {
    const ctx = getOrCreateAudioContext();
    if (!ctx || ctx.state === 'suspended') return;
    try {
      const now = ctx.currentTime;
      const notes = [
        { freq: 110.00, delay: 0, amp: 0.16, decay: 2.2 },   // A2
        { freq: 164.81, delay: 0.09, amp: 0.14, decay: 2.0 }, // E3
        { freq: 220.00, delay: 0.18, amp: 0.13, decay: 1.8 }, // A3
        { freq: 261.63, delay: 0.26, amp: 0.11, decay: 1.6 }, // C4
        { freq: 329.63, delay: 0.33, amp: 0.10, decay: 1.5 }, // E4
        { freq: 392.00, delay: 0.39, amp: 0.09, decay: 1.4 }, // G4
      ];

      // Shared reverb
      const delay = ctx.createDelay(1.0);
      delay.delayTime.value = 0.12;
      const fb = ctx.createGain();
      fb.gain.value = 0.24;
      const damp = ctx.createBiquadFilter();
      damp.type = 'lowpass';
      damp.frequency.value = 1600;
      const wet = ctx.createGain();
      wet.gain.value = 0.08;
      delay.connect(damp);
      damp.connect(fb);
      fb.connect(delay);
      damp.connect(wet);
      wet.connect(ctx.destination);

      notes.forEach(({ freq, delay: d, amp, decay }) => {
        const startTime = now + d;

        // Click transient
        const clickBuf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.012), ctx.sampleRate);
        const clickData = clickBuf.getChannelData(0);
        for (let i = 0; i < clickData.length; i++) {
          clickData[i] = (Math.random() * 2 - 1) * Math.exp(-i / (clickData.length * 0.18));
        }
        const clickSrc = ctx.createBufferSource();
        clickSrc.buffer = clickBuf;
        const clickGain = ctx.createGain();
        clickGain.gain.setValueAtTime(0.025, startTime);
        clickGain.gain.exponentialRampToValueAtTime(0.0001, startTime + 0.012);
        clickSrc.connect(clickGain);
        clickGain.connect(ctx.destination);
        clickSrc.start(startTime);

        // Harmonics
        const harmonics = [
          { mult: 1, type: 'triangle' as OscillatorType, w: 1.0, dec: decay },
          { mult: 2, type: 'sine' as OscillatorType, w: 0.35, dec: decay * 0.65 },
          { mult: 3, type: 'sine' as OscillatorType, w: 0.15, dec: decay * 0.4 },
        ];

        const bodyFilter = ctx.createBiquadFilter();
        bodyFilter.type = 'lowpass';
        bodyFilter.frequency.setValueAtTime(Math.min(3200, freq * 6), startTime);
        bodyFilter.frequency.exponentialRampToValueAtTime(freq * 1.4, startTime + decay * 0.7);
        bodyFilter.Q.setValueAtTime(1.8, startTime);

        const noteGain = ctx.createGain();
        noteGain.gain.setValueAtTime(0.0001, startTime);
        noteGain.gain.linearRampToValueAtTime(amp, startTime + 0.01);
        noteGain.gain.exponentialRampToValueAtTime(0.00001, startTime + decay);

        harmonics.forEach(({ mult, type, w, dec }) => {
          const osc = ctx.createOscillator();
          osc.type = type;
          osc.frequency.setValueAtTime(freq * mult, startTime);
          osc.detune.setValueAtTime((Math.random() * 5 - 2.5), startTime);
          const g = ctx.createGain();
          g.gain.setValueAtTime(0.0001, startTime);
          g.gain.linearRampToValueAtTime(w, startTime + 0.008);
          g.gain.exponentialRampToValueAtTime(0.00001, startTime + dec);
          osc.connect(g);
          g.connect(bodyFilter);
          osc.start(startTime);
          osc.stop(startTime + dec + 0.1);
        });

        bodyFilter.connect(noteGain);
        noteGain.connect(ctx.destination);
        noteGain.connect(delay); // reverb
      });
    } catch (_) {}
  }

  // Soft closing chord
  function playClosingChord() {
    const ctx = getOrCreateAudioContext();
    if (!ctx || ctx.state === 'suspended') return;
    try {
      const now = ctx.currentTime;
      [220, 329.63, 440].forEach((freq, i) => {
        const osc = ctx.createOscillator();
        osc.type = 'triangle';
        osc.frequency.value = freq;
        const g = ctx.createGain();
        g.gain.setValueAtTime(0.0001, now + i * 0.04);
        g.gain.linearRampToValueAtTime(0.05, now + i * 0.04 + 0.01);
        g.gain.exponentialRampToValueAtTime(0.00001, now + i * 0.04 + 0.8);
        osc.connect(g);
        g.connect(ctx.destination);
        osc.start(now + i * 0.04);
        osc.stop(now + i * 0.04 + 0.85);
      });
    } catch (_) {}
  }

  // --- Canvas Particle System ---
  function initParticles(w: number, h: number) {
    inkParticles = [];
    paperFibers = [];
    goldenDust = [];

    // Music notation particles
    const noteCount = Math.min(28, Math.floor((w * h) / 28000));
    for (let i = 0; i < noteCount; i++) {
      const size = 12 + Math.random() * 20;
      inkParticles.push({
        x: Math.random() * w,
        y: Math.random() * h,
        size,
        opacity: 0,
        rotation: Math.random() * Math.PI * 2,
        rotSpeed: (Math.random() - 0.5) * 0.012,
        vx: (Math.random() - 0.5) * 0.3,
        vy: -0.25 - Math.random() * 0.5,
        char: MUSIC_CHARS[Math.floor(Math.random() * MUSIC_CHARS.length)],
        color: WARM_PALETTE[Math.floor(Math.random() * WARM_PALETTE.length)],
        fontStr: `${Math.round(size)}px 'Georgia', serif`,
        fadeIn: Math.random(),
        life: 0,
        maxLife: 300 + Math.random() * 250,
      });
    }

    // Paper fiber particles
    const fiberCount = Math.min(60, Math.floor((w * h) / 16000));
    for (let i = 0; i < fiberCount; i++) {
      paperFibers.push({
        x: Math.random() * w,
        y: Math.random() * h,
        length: 8 + Math.random() * 24,
        angle: Math.random() * Math.PI,
        opacity: 0.02 + Math.random() * 0.05,
        drift: (Math.random() - 0.5) * 0.1,
      });
    }

    // Golden dust motes
    const dustCount = Math.min(35, Math.floor((w * h) / 22000));
    for (let i = 0; i < dustCount; i++) {
      goldenDust.push({
        x: Math.random() * w,
        y: Math.random() * h,
        size: 0.8 + Math.random() * 2.0,
        opacity: 0.1 + Math.random() * 0.45,
        twinkleSpeed: 0.03 + Math.random() * 0.05,
        twinklePhase: Math.random() * Math.PI * 2,
        vx: (Math.random() - 0.5) * 0.18,
        vy: (Math.random() - 0.5) * 0.12,
      });
    }
  }

  function resizeCanvas() {
    if (!canvasEl) return;
    const dpr = Math.min(typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1, 2);
    const rect = canvasEl.getBoundingClientRect();
    canvasEl.width = Math.round(rect.width * dpr);
    canvasEl.height = Math.round(rect.height * dpr);
    canvasEl.style.width = `${rect.width}px`;
    canvasEl.style.height = `${rect.height}px`;
    const ctx = canvasEl.getContext('2d');
    if (ctx) {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    initParticles(rect.width, rect.height);
  }

  function renderParticles(timestamp: number) {
    if (!canvasEl || !isShowing) return;
    const ctx = canvasEl.getContext('2d');
    if (!ctx) return;

    const w = canvasEl.clientWidth;
    const h = canvasEl.clientHeight;
    ctx.clearRect(0, 0, w, h);

    const dpr = Math.min(typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1, 2);

    // Fast smooth ink progress (converges within 0.5s)
    inkProgress += (inkTargetProgress - inkProgress) * 0.06;

    // 1. Render paper fibers
    if (inkProgress > 0.05 && paperFibers.length > 0) {
      const fiberAlpha = Math.min(1, inkProgress * 2);
      ctx.strokeStyle = `rgba(140, 118, 82, ${0.045 * fiberAlpha})`;
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      for (let i = 0; i < paperFibers.length; i++) {
        const f = paperFibers[i];
        f.x += f.drift;
        if (f.x < -40) f.x = w + 40;
        if (f.x > w + 40) f.x = -40;

        const dx = (f.length * 0.5) * Math.cos(f.angle);
        const dy = (f.length * 0.5) * Math.sin(f.angle);
        ctx.moveTo(f.x - dx, f.y - dy);
        ctx.lineTo(f.x + dx, f.y + dy);
      }
      ctx.stroke();
    }

    // 2. Golden dust motes
    if (goldenDust.length > 0) {
      const dustBase = Math.min(1, inkProgress * 3);
      if (dustBase > 0.01) {
        for (let i = 0; i < goldenDust.length; i++) {
          const d = goldenDust[i];
          d.x += d.vx;
          d.y += d.vy;
          d.twinklePhase += d.twinkleSpeed;

          if (d.x < -10) d.x = w + 10;
          if (d.x > w + 10) d.x = -10;
          if (d.y < -10) d.y = h + 10;
          if (d.y > h + 10) d.y = -10;
        }

        // Outer halo
        ctx.beginPath();
        for (let i = 0; i < goldenDust.length; i++) {
          const d = goldenDust[i];
          const rHalo = d.size * 2.0;
          ctx.moveTo(d.x + rHalo, d.y);
          ctx.arc(d.x, d.y, rHalo, 0, Math.PI * 2);
        }
        ctx.fillStyle = `rgba(212, 180, 120, ${0.12 * dustBase})`;
        ctx.fill();

        // Inner core
        ctx.beginPath();
        for (let i = 0; i < goldenDust.length; i++) {
          const d = goldenDust[i];
          const rCore = d.size * 0.8;
          ctx.moveTo(d.x + rCore, d.y);
          ctx.arc(d.x, d.y, rCore, 0, Math.PI * 2);
        }
        ctx.fillStyle = `rgba(255, 235, 180, ${0.52 * dustBase})`;
        ctx.fill();
      }
    }

    // 3. Music notation particles
    if (particlesReady && inkParticles.length > 0) {
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      for (let i = 0; i < inkParticles.length; i++) {
        const p = inkParticles[i];
        p.life++;
        p.x += p.vx;
        p.y += p.vy;
        p.rotation += p.rotSpeed;

        p.x += Math.sin(p.life * 0.02 + p.fadeIn * 10) * 0.25;

        if (p.y < -50) { p.y = h + 50; p.x = Math.random() * w; p.life = 0; }
        if (p.x < -50) p.x = w + 50;
        if (p.x > w + 50) p.x = -50;

        const fadeInDur = 40;
        const fadeOutStart = p.maxLife - 50;
        let alpha = 1;
        if (p.life < fadeInDur) alpha = p.life / fadeInDur;
        else if (p.life > fadeOutStart) alpha = (p.maxLife - p.life) / 50;
        alpha = Math.max(0, Math.min(1, alpha)) * (0.15 + p.fadeIn * 0.2);

        if (alpha <= 0.005) continue;

        const cos = Math.cos(p.rotation);
        const sin = Math.sin(p.rotation);
        ctx.setTransform(dpr * cos, dpr * sin, -dpr * sin, dpr * cos, dpr * p.x, dpr * p.y);
        ctx.font = p.fontStr;
        ctx.fillStyle = `${p.color} ${alpha})`;
        ctx.fillText(p.char, 0, 0);
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    // 4. Ink wash bloom effect
    if (inkProgress > 0 && inkProgress < 1.0) {
      const radius = Math.max(w, h) * inkProgress * 0.85;
      const grad = ctx.createRadialGradient(w * 0.5, h * 0.48, radius * 0.3, w * 0.5, h * 0.48, radius);
      grad.addColorStop(0, `rgba(236, 228, 209, 0)`);
      grad.addColorStop(0.6, `rgba(214, 196, 160, ${0.04 * (1 - inkProgress)})`);
      grad.addColorStop(1, `rgba(196, 172, 128, ${0.08 * (1 - inkProgress)})`);
      ctx.beginPath();
      ctx.arc(w * 0.5, h * 0.48, radius, 0, Math.PI * 2);
      ctx.fillStyle = grad;
      ctx.fill();
    }

    // 5. Warm central glow
    const breathe = 0.5 + 0.5 * Math.sin(timestamp * 0.0012);
    const glowAlpha = 0.06 + breathe * 0.04;
    if (inkProgress > 0.2) {
      const glowR = Math.min(w, h) * 0.45;
      const glow = ctx.createRadialGradient(w * 0.5, h * 0.45, 10, w * 0.5, h * 0.45, glowR);
      glow.addColorStop(0, `rgba(240, 218, 170, ${glowAlpha * Math.min(1, (inkProgress - 0.2) * 3)})`);
      glow.addColorStop(1, 'rgba(240, 218, 170, 0)');
      ctx.beginPath();
      ctx.arc(w * 0.5, h * 0.45, glowR, 0, Math.PI * 2);
      ctx.fillStyle = glow;
      ctx.fill();
    }

    if (isShowing && typeof document !== 'undefined' && !document.hidden) {
      animFrameId = requestAnimationFrame(renderParticles);
    } else {
      animFrameId = null;
    }
  }

  // --- Compressed 2.4s Rhythmic Timeline ---
  export function playIntro() {
    if (typeof document === 'undefined' || document.hidden || getMotionPreferenceSnapshot().mode !== 'full') return;
    clearAllTimers();
    bindAudioUnlock();

    isShowing = true;
    isExiting = false;
    phase = 'idle';
    progressPercent = 0;
    inkProgress = 0;
    inkTargetProgress = 0;
    particlesReady = false;
    inkRevealed = false;
    borderDrawn = false;
    titleVisible = false;
    subtitleVisible = false;
    mottoVisible = false;

    if (typeof window !== 'undefined') {
      timers.push(setTimeout(() => {
        resizeCanvas();
        if (!animFrameId && !document.hidden) animFrameId = requestAnimationFrame(renderParticles);
      }, 20));
    }

    // Progress bar (2.2s total active time)
    const startTime = Date.now();
    const totalDuration = 2200;
    const pTimer = setInterval(() => {
      const elapsed = Date.now() - startTime;
      progressPercent = Math.min(100, (elapsed / totalDuration) * 100);
      if (progressPercent >= 100) clearInterval(pTimer);
    }, 25);
    progressInterval.push(pTimer);

    // T+0.0s: Stage 1 - 水墨绽放 (0.0s - 0.6s)
    timers.push(setTimeout(() => {
      phase = 'unveil';
      playAmbientAtmosphere();
      inkTargetProgress = 1.0;
      inkRevealed = true;
    }, 20));

    // T+0.15s: Border & particles ready
    timers.push(setTimeout(() => {
      borderDrawn = true;
      particlesReady = true;
    }, 150));

    // T+0.25s: Guitar arpeggio starts
    timers.push(setTimeout(() => {
      playOpeningChord();
    }, 250));

    // T+0.5s: Stage 2 - 标题浮现 (0.6s - 1.2s)
    timers.push(setTimeout(() => {
      phase = 'title_emerge';
      titleVisible = true;
    }, 500));

    // T+0.75s: Subtitle & technical specifications
    timers.push(setTimeout(() => {
      subtitleVisible = true;
    }, 750));

    // T+1.0s: Motto calligraphy reveals
    timers.push(setTimeout(() => {
      phase = 'motto';
      mottoVisible = true;
    }, 1000));

    // T+2.2s: Stage 3 - 优雅淡出 (到达 2.4s 完成自然过渡)
    timers.push(setTimeout(() => {
      skipIntro();
    }, 2200));
  }

  // --- Instant Skip Handler (200ms Smooth Fade-out) ---
  export function skipIntro() {
    if (!isShowing || isExiting) return;
    isExiting = true;
    phase = 'exit';
    playClosingChord();

    try {
      sessionStorage.setItem('mimi_intro_seen', 'true');
      sessionStorage.setItem('mimi_paper_intro_played', 'true');
    } catch (_) {}

    clearAllTimers();

    // 200ms ultra-smooth hardware-accelerated fade out
    timers.push(setTimeout(() => {
      isShowing = false;
      isExiting = false;
      unbindAudioUnlock?.();
      unbindAudioUnlock = null;
      if (animFrameId) {
        cancelAnimationFrame(animFrameId);
        animFrameId = null;
      }
      if (audioCtx && audioCtx.state !== 'closed') {
        try { audioCtx.close(); } catch (_) {}
        audioCtx = null;
      }
    }, 200));
  }

  function settleIntro() {
    clearAllTimers();
    unbindAudioUnlock?.();
    unbindAudioUnlock = null;
    isShowing = false;
    isExiting = false;
    if (animFrameId !== null) cancelAnimationFrame(animFrameId);
    animFrameId = null;
    if (audioCtx && audioCtx.state !== 'closed') audioCtx.close().catch(() => {});
    audioCtx = null;
  }

  function handleRootClick(e: MouseEvent) {
    if (!isShowing || isExiting) return;
    skipIntro();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (!isShowing || isExiting) return;
    // Any keypress (ESC, Space, Enter, or any typing) immediately skips intro!
    e.preventDefault();
    skipIntro();
  }

  function handleWindowResize() {
    if (isShowing && canvasEl) resizeCanvas();
  }

  onMount(() => {
    if (typeof window === 'undefined') return;

    let played = false;
    try {
      played = sessionStorage.getItem('mimi_intro_seen') === 'true' ||
               sessionStorage.getItem('mimi_paper_intro_played') === 'true';
    } catch (_) {}

    const handleCustomPlay = () => playIntro();
    window.addEventListener('mimi:play-intro', handleCustomPlay);
    window.addEventListener('keydown', handleKeydown);
    window.addEventListener('resize', handleWindowResize);

    const handleVisibility = () => {
      if (typeof document === 'undefined') return;
      if (document.hidden) {
        settleIntro();
      }
    };
    document.addEventListener('visibilitychange', handleVisibility);
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      if (mode !== 'full') settleIntro();
    });

    // Only auto-play if user has not seen intro in current session
    if (autoPlay && !played) {
      playIntro();
    }

    return () => {
      window.removeEventListener('mimi:play-intro', handleCustomPlay);
      window.removeEventListener('keydown', handleKeydown);
      window.removeEventListener('resize', handleWindowResize);
      document.removeEventListener('visibilitychange', handleVisibility);
      unsubscribeMotion();
      unbindAudioUnlock?.();
      settleIntro();
    };
  });
</script>

{#if isShowing}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div
    bind:this={containerEl}
    class="intro-root"
    class:is-exiting={isExiting}
    onclick={handleRootClick}
    role="dialog"
    aria-modal="true"
    aria-label="MIMI Guitar 书卷开场（点击或按任意键跳过）"
  >
    <!-- Layer 0: Deep aged paper base with rich texture -->
    <div class="paper-base" aria-hidden="true"></div>

    <!-- Layer 0b: Paper fiber noise overlay (Single-octave lightweight GPU layer) -->
    <div class="paper-noise" aria-hidden="true"></div>

    <!-- Layer 0c: Warm discoloration blotches for aged paper feel -->
    <div class="paper-blotches" aria-hidden="true"></div>

    <!-- Layer 1: Central ink bloom reveal — paper opens like a scroll -->
    <div
      class="ink-bloom"
      class:ink-bloom-active={inkRevealed}
      aria-hidden="true"
    ></div>

    <!-- Layer 2: Canvas for particles, dust, fibers -->
    <canvas
      bind:this={canvasEl}
      class="particle-canvas"
    ></canvas>

    <!-- Layer 3: Warm ambient light sweep -->
    <div class="light-sweep-container" class:active={inkRevealed} aria-hidden="true">
      <div class="light-sweep"></div>
    </div>

    <!-- Layer 4: Vignette edges -->
    <div class="vignette" aria-hidden="true"></div>

    <!-- Layer 5: Self-drawing ornamental border -->
    <div class="border-frame" class:border-drawn={borderDrawn} aria-hidden="true">
      <svg class="border-svg" viewBox="0 0 1000 600" preserveAspectRatio="none">
        <rect
          x="20" y="20" width="960" height="560"
          rx="8" ry="8"
          fill="none"
          stroke="rgba(176, 141, 87, 0.35)"
          stroke-width="0.8"
          class="border-outer"
        />
        <rect
          x="28" y="28" width="944" height="544"
          rx="5" ry="5"
          fill="none"
          stroke="rgba(201, 164, 95, 0.2)"
          stroke-width="0.5"
          class="border-inner"
        />
      </svg>
      <!-- Corner ornaments -->
      <span class="corner-ornament corner-tl">✦</span>
      <span class="corner-ornament corner-tr">✦</span>
      <span class="corner-ornament corner-bl">✦</span>
      <span class="corner-ornament corner-br">✦</span>
      <!-- Top/Bottom center musical ornament -->
      <span class="edge-ornament edge-top">♫</span>
      <span class="edge-ornament edge-bottom">♫</span>
    </div>

    <!-- Layer 5b: Faint staff lines — printed score texture -->
    <div class="staff-lines staff-top" class:visible={inkRevealed} aria-hidden="true"></div>
    <div class="staff-lines staff-bottom" class:visible={inkRevealed} aria-hidden="true"></div>

    <!-- Layer 5c: Watermark emboss behind content -->
    <div class="watermark" class:visible={inkRevealed} aria-hidden="true">
      <span class="watermark-text">MIMI</span>
    </div>

    <!-- Layer 6: Skip button -->
    <div class="skip-area">
      <button onclick={(e) => { e.stopPropagation(); skipIntro(); }} class="skip-btn" type="button">
        <span class="skip-label">跳过开场</span>
        <kbd class="skip-kbd">任意键 / 点击</kbd>
        <span class="skip-dot">
          <span class="skip-dot-ping"></span>
          <span class="skip-dot-core"></span>
        </span>
      </button>
    </div>

    <!-- Layer 7: Main Title Sequence -->
    <div class="title-stage">
      <!-- Eyebrow tag -->
      <div class="eyebrow" class:visible={inkRevealed}>
        <span class="eyebrow-dot gold"></span>
        <span class="eyebrow-text">FOLIO MASTERPIECE · SCORE EDITION</span>
        <span class="eyebrow-dot blue"></span>
      </div>

      <!-- Main Title with ink-drip calligraphy reveal -->
      <div class="title-container">
        <!-- Warm glow behind title -->
        <div class="title-glow" class:visible={titleVisible}></div>

        <h1 class="main-title" class:visible={titleVisible}>
          <span class="title-char" style="--i: 0">M</span><span class="title-char" style="--i: 1">I</span><span class="title-char" style="--i: 2">M</span><span class="title-char" style="--i: 3">I</span>
          <span class="title-space"></span>
          <span class="title-char" style="--i: 4">G</span><span class="title-char" style="--i: 5">U</span><span class="title-char" style="--i: 6">I</span><span class="title-char" style="--i: 7">T</span><span class="title-char" style="--i: 8">A</span><span class="title-char" style="--i: 9">R</span>
        </h1>

        <!-- Ink flourish underline -->
        <svg
          viewBox="0 0 300 24"
          class="flourish"
          class:visible={titleVisible}
          aria-hidden="true"
        >
          <path
            d="M10 12 C 70 4, 110 20, 150 12 C 190 4, 230 20, 290 12"
            fill="none"
            stroke="rgba(201, 164, 95, 0.6)"
            stroke-width="1.2"
            stroke-linecap="round"
            class="flourish-path"
          />
          <circle cx="150" cy="12" r="2" fill="rgba(201, 164, 95, 0.7)" class="flourish-dot" />
        </svg>
      </div>

      <!-- Subtitle -->
      <p class="subtitle" class:visible={subtitleVisible}>
        — &nbsp; ACOUSTIC &nbsp; SCORE &nbsp; WORKSHOP &nbsp; —
      </p>

      <!-- Ornamental divider -->
      <div class="ornament-divider" class:visible={mottoVisible}>
        <span class="divider-line left"></span>
        <span class="divider-diamond"></span>
        <span class="divider-note">♪</span>
        <span class="divider-diamond"></span>
        <span class="divider-line right"></span>
      </div>

      <!-- Chinese Motto -->
      <blockquote class="motto" class:visible={mottoVisible}>
        "把每一份乐谱，都当作一页书来对待"
      </blockquote>

      <!-- Technical info & progress -->
      <div class="tech-info" class:visible={subtitleVisible}>
        <div class="tech-specs">
          <span>A4 SCORE FOLIO</span>
          <span class="tech-dot">✦</span>
          <span>48kHz ACOUSTICS</span>
          <span class="tech-dot">✦</span>
          <span>MMXXVI</span>
        </div>
        <div class="progress-track">
          <div class="progress-fill" style="width: {progressPercent}%"></div>
          <span class="progress-diamond" style="left: calc({progressPercent}% - 4px)"></span>
        </div>
      </div>
    </div>

    <!-- Interactive hint -->
    <div class="hint" class:visible={titleVisible}>
      <span class="hint-dot"></span>
      <span class="hint-text">点击任意位置或按任意键即刻进入</span>
    </div>
  </div>
{/if}

<style>
  /* ============================================================
     REDESIGNED MasterpieceIntro — "墨韵书卷 · 极速轻量秒开版"
     ============================================================ */

  /* --- Root Container --- */
  .intro-root {
    position: fixed;
    inset: 0;
    z-index: 99999;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    user-select: none;
    cursor: pointer;
    color: #2b241c;
    contain: strict;
    transform: translateZ(0);
    will-change: opacity, transform;
    transition: opacity 200ms cubic-bezier(0.16, 1, 0.3, 1), transform 200ms ease-out, filter 200ms ease-out;
  }
  .intro-root.is-exiting {
    opacity: 0;
    transform: scale(1.02);
    filter: blur(4px);
    pointer-events: none;
  }

  /* --- Paper Base --- */
  .paper-base {
    position: absolute;
    inset: 0;
    z-index: 0;
    background:
      radial-gradient(ellipse at 50% 40%, #f7f1e3 0%, #ede5d2 40%, #e4dac4 70%, #d8cdb4 100%),
      linear-gradient(170deg, #f2ead6 0%, #e8dfc8 50%, #ddd2b8 100%);
  }

  /* --- Paper Fiber Noise (Lightweight numOctaves=1) --- */
  .paper-noise {
    position: absolute;
    inset: 0;
    z-index: 1;
    opacity: 0.05;
    mix-blend-mode: multiply;
    background-image:
      url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='1' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
    pointer-events: none;
  }

  /* --- Aged Paper Blotches --- */
  .paper-blotches {
    position: absolute;
    inset: 0;
    z-index: 1;
    pointer-events: none;
    background:
      radial-gradient(ellipse at 15% 25%, rgba(196, 172, 128, 0.12) 0%, transparent 45%),
      radial-gradient(ellipse at 80% 65%, rgba(188, 164, 122, 0.10) 0%, transparent 50%),
      radial-gradient(ellipse at 65% 18%, rgba(202, 178, 134, 0.08) 0%, transparent 40%),
      radial-gradient(ellipse at 25% 80%, rgba(182, 158, 118, 0.09) 0%, transparent 42%),
      radial-gradient(ellipse at 50% 50%, rgba(168, 146, 108, 0.05) 0%, transparent 60%);
  }

  /* --- Ink Bloom Reveal --- */
  .ink-bloom {
    position: absolute;
    inset: 0;
    z-index: 2;
    background: radial-gradient(
      circle at 50% 48%,
      transparent 0%,
      rgba(228, 218, 196, 0.3) 20%,
      rgba(214, 200, 168, 0.5) 40%,
      #e4dac4 55%,
      #ddd2b8 100%
    );
    opacity: 1;
    transition: opacity 600ms cubic-bezier(0.16, 1, 0.3, 1);
    pointer-events: none;
  }
  .ink-bloom.ink-bloom-active {
    opacity: 0;
  }

  /* --- Particle Canvas --- */
  .particle-canvas {
    position: absolute;
    inset: 0;
    z-index: 10;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }

  /* --- Light Sweep --- */
  .light-sweep-container {
    position: absolute;
    inset: 0;
    z-index: 5;
    overflow: hidden;
    opacity: 0;
    transition: opacity 800ms ease-out;
    pointer-events: none;
  }
  .light-sweep-container.active {
    opacity: 1;
  }
  .light-sweep {
    position: absolute;
    top: -10%;
    bottom: -10%;
    width: 45%;
    background: linear-gradient(
      to right,
      transparent,
      rgba(255, 247, 224, 0.15),
      rgba(255, 250, 235, 0.22),
      rgba(255, 247, 224, 0.15),
      transparent
    );
    animation: sweep 4s cubic-bezier(0.45, 0, 0.55, 1) infinite;
    will-change: transform;
  }
  @keyframes sweep {
    0% { transform: translateX(-140%) skewX(-12deg); }
    100% { transform: translateX(380%) skewX(-12deg); }
  }

  /* --- Vignette --- */
  .vignette {
    position: absolute;
    inset: 0;
    z-index: 8;
    pointer-events: none;
    background: radial-gradient(
      ellipse at 50% 45%,
      rgba(255, 255, 255, 0) 0%,
      rgba(255, 252, 245, 0.2) 45%,
      rgba(196, 172, 128, 0.15) 75%,
      rgba(150, 126, 90, 0.28) 100%
    );
  }

  /* --- Self-Drawing Border --- */
  .border-frame {
    position: absolute;
    inset: 16px;
    z-index: 15;
    pointer-events: none;
    opacity: 0;
    transition: opacity 600ms ease-out;
  }
  .border-frame.border-drawn {
    opacity: 1;
  }
  .border-svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }
  .border-outer,
  .border-inner {
    stroke-dasharray: 3040;
    stroke-dashoffset: 3040;
    transition: stroke-dashoffset 1200ms cubic-bezier(0.16, 1, 0.3, 1);
  }
  .border-drawn .border-outer {
    stroke-dashoffset: 0;
    transition-delay: 0ms;
  }
  .border-drawn .border-inner {
    stroke-dashoffset: 0;
    transition-delay: 150ms;
  }

  /* Corner ornaments */
  .corner-ornament {
    position: absolute;
    font-size: 10px;
    color: rgba(176, 141, 87, 0.6);
    opacity: 0;
    transition: opacity 400ms ease-out;
    transition-delay: 400ms;
  }
  .border-drawn .corner-ornament { opacity: 1; }
  .corner-tl { top: 8px; left: 10px; }
  .corner-tr { top: 8px; right: 10px; }
  .corner-bl { bottom: 8px; left: 10px; }
  .corner-br { bottom: 8px; right: 10px; }

  .edge-ornament {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    font-family: serif;
    font-size: 13px;
    color: rgba(176, 141, 87, 0.45);
    opacity: 0;
    transition: opacity 400ms ease-out;
    transition-delay: 500ms;
  }
  .border-drawn .edge-ornament { opacity: 1; }
  .edge-top { top: 5px; }
  .edge-bottom { bottom: 5px; }

  /* --- Staff Lines --- */
  .staff-lines {
    position: absolute;
    left: 0;
    right: 0;
    z-index: 3;
    pointer-events: none;
    opacity: 0;
    transition: opacity 600ms ease-out;
    transition-delay: 200ms;
    background-image: repeating-linear-gradient(
      to bottom,
      rgba(140, 118, 82, 0.08) 0 1px,
      transparent 1px 9px,
      rgba(140, 118, 82, 0.08) 9px 10px,
      transparent 10px 18px,
      rgba(140, 118, 82, 0.08) 18px 19px,
      transparent 19px 27px,
      rgba(140, 118, 82, 0.08) 27px 28px,
      transparent 28px 36px,
      rgba(140, 118, 82, 0.08) 36px 37px,
      transparent 37px 72px
    );
  }
  .staff-lines.visible { opacity: 1; }
  .staff-top {
    top: 12vh;
    height: 20vh;
    mask-image: linear-gradient(to bottom, rgba(0,0,0,0.7), transparent);
    -webkit-mask-image: linear-gradient(to bottom, rgba(0,0,0,0.7), transparent);
  }
  .staff-bottom {
    bottom: 12vh;
    height: 18vh;
    mask-image: linear-gradient(to top, rgba(0,0,0,0.6), transparent);
    -webkit-mask-image: linear-gradient(to top, rgba(0,0,0,0.6), transparent);
  }

  /* --- Watermark --- */
  .watermark {
    position: absolute;
    inset: 0;
    z-index: 3;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    opacity: 0;
    transition: opacity 800ms ease-out;
    transition-delay: 200ms;
  }
  .watermark.visible { opacity: 1; }
  .watermark-text {
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-weight: 600;
    font-size: min(18vw, 240px);
    letter-spacing: 0.16em;
    line-height: 1;
    color: rgba(188, 174, 141, 0.06);
    transform: rotate(-5deg);
    text-shadow:
      1px 1px 0 rgba(255, 252, 240, 0.3),
      -1px -1px 0 rgba(140, 118, 82, 0.04);
  }

  /* --- Skip Button --- */
  .skip-area {
    position: absolute;
    top: 20px;
    right: 24px;
    z-index: 50;
  }
  @media (min-width: 640px) {
    .skip-area { top: 24px; right: 32px; }
  }
  .skip-btn {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 16px;
    border-radius: 18px;
    border: 1px solid rgba(216, 203, 168, 0.7);
    background: rgba(244, 238, 224, 0.85);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-size: 12px;
    font-weight: 500;
    color: #3a3126;
    cursor: pointer;
    transition: all 200ms ease;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
  }
  .skip-btn:hover {
    border-color: rgba(65, 161, 207, 0.6);
    background: rgba(244, 238, 224, 0.98);
    color: #1a1612;
    transform: scale(1.02);
  }
  .skip-btn:active {
    transform: scale(0.96);
  }
  .skip-label {
    letter-spacing: 0.06em;
  }
  .skip-kbd {
    padding: 2px 6px;
    border-radius: 6px;
    border: 1px solid rgba(216, 203, 168, 0.7);
    background: rgba(246, 241, 230, 0.95);
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-size: 10px;
    color: #8a6a3a;
    box-shadow: 0 1px 0 rgba(0, 0, 0, 0.04);
  }
  .skip-dot {
    position: relative;
    display: flex;
    width: 8px;
    height: 8px;
  }
  .skip-dot-ping {
    position: absolute;
    inset: 0;
    border-radius: 50%;
    background: rgba(65, 161, 207, 0.5);
    animation: ping 1.5s cubic-bezier(0, 0, 0.2, 1) infinite;
  }
  .skip-dot-core {
    position: relative;
    display: block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: rgba(65, 161, 207, 0.9);
  }
  @keyframes ping {
    75%, 100% { transform: scale(2); opacity: 0; }
  }

  /* --- Title Stage --- */
  .title-stage {
    position: relative;
    z-index: 20;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    max-width: 900px;
    padding: 0 24px;
    text-align: center;
    pointer-events: none;
  }

  /* Eyebrow */
  .eyebrow {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 12px;
    opacity: 0;
    transform: translateY(-8px);
    transition: all 500ms cubic-bezier(0.16, 1, 0.3, 1);
  }
  .eyebrow.visible {
    opacity: 1;
    transform: translateY(0);
  }
  .eyebrow-text {
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-size: 11px;
    font-weight: 500;
    letter-spacing: 0.28em;
    text-transform: uppercase;
    color: #8a6a3a;
  }
  .eyebrow-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }
  .eyebrow-dot.gold {
    background: #b08d57;
    box-shadow: 0 0 8px rgba(176, 141, 87, 0.55);
  }
  .eyebrow-dot.blue {
    background: #41a1cf;
    box-shadow: 0 0 8px rgba(65, 161, 207, 0.5);
  }

  /* Title Container */
  .title-container {
    position: relative;
    padding: 6px 0;
  }

  .title-glow {
    position: absolute;
    inset: -20px;
    z-index: -1;
    background: radial-gradient(ellipse at center, rgba(214, 184, 120, 0.2) 0%, transparent 70%);
    filter: blur(20px);
    opacity: 0;
    transition: opacity 600ms ease-out;
  }
  .title-glow.visible { opacity: 1; }

  .main-title {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 0;
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-weight: 700;
    font-size: clamp(2.2rem, 7.5vw, 5.5rem);
    line-height: 1.1;
    letter-spacing: 0.18em;
    color: transparent;
    margin: 0;
  }

  .title-char {
    display: inline-block;
    background: linear-gradient(140deg, #2f281e 0%, #6b5536 35%, #a3762f 68%, #c9a45f 100%);
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    opacity: 0;
    transform: translateY(20px) scale(0.94);
    filter: blur(6px);
    transition:
      opacity 350ms cubic-bezier(0.16, 1, 0.3, 1),
      transform 450ms cubic-bezier(0.16, 1, 0.3, 1),
      filter 400ms cubic-bezier(0.16, 1, 0.3, 1);
    transition-delay: calc(var(--i) * 35ms + 40ms);
  }
  .main-title.visible .title-char {
    opacity: 1;
    transform: translateY(0) scale(1);
    filter: blur(0) drop-shadow(0 3px 16px rgba(176, 141, 87, 0.35));
  }

  .title-space {
    display: inline-block;
    width: 0.35em;
  }

  /* Flourish */
  .flourish {
    display: block;
    margin: 10px auto 0;
    width: 220px;
    height: 24px;
    opacity: 0;
    transform: scaleX(0.3);
    transform-origin: center;
    transition: all 600ms cubic-bezier(0.16, 1, 0.3, 1);
    transition-delay: 250ms;
  }
  .flourish.visible {
    opacity: 1;
    transform: scaleX(1);
  }
  @media (min-width: 640px) {
    .flourish { width: 280px; }
  }
  .flourish-path {
    stroke-dasharray: 400;
    stroke-dashoffset: 400;
    transition: stroke-dashoffset 800ms cubic-bezier(0.16, 1, 0.3, 1);
    transition-delay: 250ms;
  }
  .flourish.visible .flourish-path {
    stroke-dashoffset: 0;
  }
  .flourish-dot {
    opacity: 0;
    transition: opacity 400ms ease-out;
    transition-delay: 500ms;
  }
  .flourish.visible .flourish-dot {
    opacity: 1;
  }

  /* Subtitle */
  .subtitle {
    margin-top: 8px;
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-size: 12px;
    font-weight: 500;
    letter-spacing: 0.32em;
    text-transform: uppercase;
    color: #9a7436;
    opacity: 0;
    transform: translateY(10px);
    transition: all 600ms cubic-bezier(0.16, 1, 0.3, 1);
    filter: drop-shadow(0 1px 8px rgba(176, 141, 87, 0.25));
  }
  .subtitle.visible {
    opacity: 1;
    transform: translateY(0);
  }
  @media (min-width: 640px) {
    .subtitle { font-size: 13px; margin-top: 12px; }
  }

  /* Ornamental Divider */
  .ornament-divider {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 20px;
    color: rgba(176, 141, 87, 0.65);
    opacity: 0;
    transform: translateY(8px);
    transition: all 500ms cubic-bezier(0.16, 1, 0.3, 1);
  }
  .ornament-divider.visible {
    opacity: 1;
    transform: translateY(0);
  }
  .divider-line {
    display: block;
    height: 1px;
    width: 40px;
  }
  .divider-line.left {
    background: linear-gradient(to right, transparent, rgba(201, 164, 95, 0.5));
  }
  .divider-line.right {
    background: linear-gradient(to left, transparent, rgba(201, 164, 95, 0.5));
  }
  @media (min-width: 640px) {
    .divider-line { width: 64px; }
    .ornament-divider { margin-top: 26px; }
  }
  .divider-diamond {
    display: inline-block;
    width: 6px;
    height: 6px;
    transform: rotate(45deg);
    border: 1px solid rgba(201, 164, 95, 0.65);
    background: rgba(201, 164, 95, 0.12);
  }
  .divider-note {
    font-family: serif;
    font-size: 14px;
    color: rgba(176, 141, 87, 0.75);
  }

  /* Chinese Motto */
  .motto {
    margin-top: 12px;
    font-family: '方正小标宋简体', 'Source Han Serif SC', 'Songti SC', SimSun, serif;
    font-size: 16px;
    letter-spacing: 0.18em;
    color: #3a3126;
    opacity: 0;
    transform: translateY(10px);
    transition: all 600ms cubic-bezier(0.16, 1, 0.3, 1);
    text-shadow:
      0 1px 0 rgba(255, 252, 240, 0.6),
      0 -0.5px 0 rgba(80, 60, 30, 0.12);
  }
  .motto.visible {
    opacity: 1;
    transform: translateY(0);
  }
  @media (min-width: 640px) {
    .motto { font-size: 20px; margin-top: 16px; }
  }
  @media (min-width: 768px) {
    .motto { font-size: 24px; }
  }

  /* Tech Info & Progress */
  .tech-info {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    margin-top: 24px;
    opacity: 0;
    transform: translateY(6px);
    transition: all 600ms cubic-bezier(0.16, 1, 0.3, 1);
    transition-delay: 150ms;
  }
  .tech-info.visible {
    opacity: 0.65;
    transform: translateY(0);
  }
  @media (min-width: 640px) {
    .tech-info { margin-top: 30px; }
  }
  .tech-specs {
    display: flex;
    align-items: center;
    gap: 12px;
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-size: 9px;
    font-weight: 500;
    letter-spacing: 0.22em;
    text-transform: uppercase;
    color: #8a7f6d;
  }
  @media (min-width: 640px) {
    .tech-specs { font-size: 10px; }
  }
  .tech-dot {
    color: rgba(176, 141, 87, 0.65);
  }
  .progress-track {
    position: relative;
    width: 144px;
    height: 2px;
    border-radius: 2px;
    background: rgba(231, 221, 200, 0.8);
    margin-top: 4px;
  }
  .progress-fill {
    height: 100%;
    border-radius: 2px;
    background: linear-gradient(to right, #c9a45f, #41a1cf);
    transition: width 25ms linear;
  }
  .progress-diamond {
    position: absolute;
    top: 50%;
    width: 8px;
    height: 8px;
    transform: translateY(-50%) rotate(45deg);
    border: 1px solid rgba(247, 236, 212, 0.8);
    background: #b08d57;
    box-shadow: 0 0 6px rgba(176, 141, 87, 0.65);
    transition: left 25ms linear;
  }

  /* Hint */
  .hint {
    position: absolute;
    bottom: 40px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 20;
    pointer-events: none;
    display: flex;
    align-items: center;
    gap: 6px;
    opacity: 0;
    transition: opacity 600ms ease-out;
    transition-delay: 300ms;
  }
  .hint.visible { opacity: 0.55; }
  @media (min-width: 640px) {
    .hint { bottom: 50px; }
  }
  .hint-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: rgba(65, 161, 207, 0.7);
    animation: pulse-hint 1.5s ease-in-out infinite;
  }
  @keyframes pulse-hint {
    0%, 100% { opacity: 0.5; transform: scale(1); }
    50% { opacity: 1; transform: scale(1.3); }
  }
  .hint-text {
    font-family: 'Cascadia Mono', 'Cascadia Code', ui-monospace, SFMono-Regular, monospace;
    font-size: 10px;
    letter-spacing: 0.12em;
    color: #8a7f6d;
    text-transform: uppercase;
  }

  /* --- Reduced Motion --- */
  @media (prefers-reduced-motion: reduce) {
    .intro-root,
    .ink-bloom,
    .border-outer,
    .border-inner,
    .title-char,
    .flourish,
    .subtitle,
    .motto,
    .eyebrow,
    .ornament-divider,
    .tech-info {
      transition-duration: 0ms !important;
    }
    .light-sweep,
    .paper-noise,
    .skip-dot-ping,
    .hint-dot {
      animation: none !important;
    }
  }

  /* --- Font rendering --- */
  :global(.font-display) {
    font-feature-settings: "kern" 1, "liga" 1;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }
</style>
