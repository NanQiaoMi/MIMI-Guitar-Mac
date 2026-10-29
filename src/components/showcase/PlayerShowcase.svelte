<script lang="ts">
  import CodeBlock from './CodeBlock.svelte';
  import FluidAudioWaveform from '../player/FluidAudioWaveform.svelte';
  import FloatingPlayerHUD from '../player/FloatingPlayerHUD.svelte';
  import VirtualFretboard, { type ActiveNote } from '../player/VirtualFretboard.svelte';
  import MusicNoteParticles from '../ambient/MusicNoteParticles.svelte';
  import ScoreNoteSparkTrails from '../player/ScoreNoteSparkTrails.svelte';
  import type { ActiveNotePosition } from '../../lib/noteSparks';
  import { playProgramNote, getNoteMidi, getGlobalProgram } from '../../lib/guitarSound.ts';

  // State: Waveform Interactive Sandbox
  let isPlaying = $state(true);
  let bpm = $state(88);
  let color = $state('#0a0a0a');
  let waveWidth = $state(160);
  let waveHeight = $state(36);

  // State: HUD Sandbox
  let hudPlaying = $state(false);
  let hudBpm = $state(80);
  let hudSpeed = $state(80);
  let hudCurTime = $state(42);
  let hudEndTime = $state(216);
  let hudCurTick = $state(2400);
  let hudEndTick = $state(12000);
  let hudTracksCount = $state(4);
  let hudShowTracks = $state(false);

  // State: Virtual Fretboard Sandbox
  let fretboardTheme = $state<'light' | 'dark'>('light');
  let fretboardCapo = $state(0);
  let fretboardShowPitch = $state(false);
  let selectedChord = $state('C');
  let customActiveNotes = $state<ActiveNote[]>([
    { string: 2, fret: 1, finger: 1 },
    { string: 4, fret: 2, finger: 2 },
    { string: 5, fret: 3, finger: 3 },
    { string: 1, fret: 0 },
    { string: 3, fret: 0 },
  ]);

  const CHORD_PRESETS: Record<string, ActiveNote[]> = {
    C: [
      { string: 2, fret: 1, finger: 1 },
      { string: 4, fret: 2, finger: 2 },
      { string: 5, fret: 3, finger: 3 },
      { string: 1, fret: 0 },
      { string: 3, fret: 0 },
    ],
    G: [
      { string: 1, fret: 3, finger: 3 },
      { string: 5, fret: 2, finger: 1 },
      { string: 6, fret: 3, finger: 2 },
      { string: 2, fret: 0 },
      { string: 3, fret: 0 },
      { string: 4, fret: 0 },
    ],
    Am: [
      { string: 2, fret: 1, finger: 1 },
      { string: 3, fret: 2, finger: 3 },
      { string: 4, fret: 2, finger: 2 },
      { string: 1, fret: 0 },
      { string: 5, fret: 0 },
    ],
    F: [
      { string: 1, fret: 1, finger: 1 },
      { string: 2, fret: 1, finger: 1 },
      { string: 3, fret: 2, finger: 2 },
      { string: 4, fret: 3, finger: 4 },
      { string: 5, fret: 3, finger: 3 },
      { string: 6, fret: 1, finger: 1 },
    ],
    Em: [
      { string: 4, fret: 2, finger: 2 },
      { string: 5, fret: 2, finger: 1 },
      { string: 1, fret: 0 },
      { string: 2, fret: 0 },
      { string: 3, fret: 0 },
      { string: 6, fret: 0 },
    ],
    Dm: [
      { string: 1, fret: 1, finger: 1 },
      { string: 2, fret: 3, finger: 3 },
      { string: 3, fret: 2, finger: 2 },
      { string: 4, fret: 0 },
    ],
    Solo12: [
      { string: 1, fret: 12, finger: 3 },
      { string: 2, fret: 12, finger: 2 },
      { string: 3, fret: 12, finger: 1 },
      { string: 4, fret: 14, finger: 4 },
    ],
  };

  function selectChord(chord: string) {
    selectedChord = chord;
    customActiveNotes = [...(CHORD_PRESETS[chord] || [])];
  }

  function handleFretboardClick(note: { string: number; fret: number }) {
    const midi = getNoteMidi(note.string, note.fret);
    playProgramNote(midi, getGlobalProgram());

    const existingIndex = customActiveNotes.findIndex(
      n => (n.string === note.string || (n.string === note.string - 1 && n.string >= 0)) && n.fret === note.fret
    );
    if (existingIndex >= 0) {
      customActiveNotes = customActiveNotes.filter((_, idx) => idx !== existingIndex);
      selectedChord = 'Custom';
    } else {
      customActiveNotes = [...customActiveNotes, { string: note.string, fret: note.fret }];
      selectedChord = 'Custom';
    }
  }

  // State: Ambient Music Note Particles Sandbox
  let particleCount = $state(28);
  let particleSpeed = $state(0.65);
  let particleOpacity = $state(0.25);
  let particleColor = $state('#41a1cf');

  // State: Note Spark Trails Sandbox
  let sparkPositions = $state<ActiveNotePosition[]>([]);
  let testPitch = $state(64); // E4
  let sparkTheme = $state<'light' | 'dark'>('light');
  let autoSpark = $state(false);

  function triggerSpark(e: MouseEvent) {
    const target = e.currentTarget as HTMLElement;
    const rect = target.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    sparkPositions = [{ x, y, pitch: testPitch }];
  }

  $effect(() => {
    let timer: any;
    if (autoSpark) {
      timer = setInterval(() => {
        const x = 50 + Math.random() * 320;
        const y = 30 + Math.random() * 90;
        const pitches = [40, 45, 52, 60, 64, 72, 79, 84];
        const p = pitches[Math.floor(Math.random() * pitches.length)];
        sparkPositions = [{ x, y, pitch: p }];
      }, 350);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  });

  // Timer loop for HUD playback simulation
  $effect(() => {
    let interval: any;
    if (hudPlaying) {
      interval = setInterval(() => {
        hudCurTime = (hudCurTime + 1) % hudEndTime;
        hudCurTick = Math.round((hudCurTime / hudEndTime) * hudEndTick);
      }, 1000);
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  });

  let activeTab = $state<'preview' | 'code' | 'tokens'>('preview');

  const snippetCode = `<!-- 1. MusicNoteParticles 氛围悬浮乐符粒子 (Canvas 2D + Fluid Mouse Deflection) -->
<MusicNoteParticles
  count={24}
  color="#41a1cf"
  opacity={0.18}
  speed={0.6}
  className="absolute inset-0"
/>

<!-- 2. VirtualFretboard 虚拟吉他指板 (Frosted Glass + Animated LED Signal Dots) -->
<VirtualFretboard
  activeNotes={[
    { string: 2, fret: 1, finger: 1 },
    { string: 4, fret: 2, finger: 2 },
    { string: 5, fret: 3, finger: 3 },
  ]}
  tuning={['E4', 'B3', 'G3', 'D3', 'A2', 'E2']}
  capo={0}
  theme="light"
  interactive={true}
  onNoteClick={(note) => console.log('Fret Clicked:', note)}
/>

<!-- 3. FluidAudioWaveform 流体音频声波 (Canvas 2D Dual-layer Sine/Cosine Waves) -->
<FluidAudioWaveform
  isPlaying={isPlaying}
  bpm={bpm}
  color="#0a0a0a"
  height={32}
  width={140}
/>

<!-- 4. FloatingPlayerHUD 底部悬浮磨砂胶囊控制台 -->
<FloatingPlayerHUD
  isPlaying={playing}
  curTime={curTime}
  endTime={endTime}
  curTick={curTick}
  endTick={endTick}
  bpm={baseTempo}
  speed={speed}
  title="晴天"
  artist="周杰伦"
  tracksCount={4}
  showTracksPanel={showTracks}
  onPlayPause={() => (playing = !playing)}
  onChangeSpeed={(v) => (speed = v)}
  onToggleTracks={() => (showTracks = !showTracks)}
/>

<!-- 5. ScoreNoteSparkTrails 乐谱音符微光粒子流 & 同心共鸣环 -->
<ScoreNoteSparkTrails
  {api}
  isPlaying={playing}
  scoreContainer={container}
  activeNotePositions={[{ x: 140, y: 80, pitch: 64 }]}
/>`;

  const tokensSpec = `/* Refero UI Motion & Virtual Fretboard Tokens */
--fretboard-card-radius: 24px;
--fretboard-bg-light: rgba(255, 255, 255, 0.90);
--fretboard-bg-dark: rgba(20, 20, 25, 0.92);
--fretboard-blur: 20px;
--fretboard-wire-light: #d4d4d8;
--fretboard-wire-dark: #404052;
--fretboard-nut-light: #e4e4e7;
--fretboard-nut-dark: #27272f;

/* LED Signal Note Activation */
--led-glow-signal: #41a1cf;
--led-glow-shadow: 0 0 16px rgba(65, 161, 207, 0.95), 0 0 28px rgba(65, 161, 207, 0.55);
--led-spring-ease: cubic-bezier(0.175, 0.885, 0.32, 1.275);
--led-ripple-ease: cubic-bezier(0.16, 1, 0.3, 1);

/* Ambient Floating Particles */
--particle-glyphs: '♪', '♫', '♩', '♬', '𝄞', '𝄢', '✦';
--particle-deflection-radius: 150px;
--particle-spring-damp: 0.92;`;
</script>

<div class="space-y-8">
  <!-- Sub-Header & Switcher -->
  <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-[#e5e5e5] pb-5">
    <div>
      <div class="inline-flex items-center gap-2 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-3 py-1 text-xs font-medium text-[#737373]">
        <span class="h-2 w-2 rounded-full bg-[#41a1cf]"></span>
        MODULE 07 · 播放器组件群 & 虚拟指板 & 乐符粒子
      </div>
      <h2 class="mt-2 font-display text-2xl text-[#0a0a0a]">
        虚拟吉他指板 · 悬浮乐符粒子 · 流体声波 (Virtual Fretboard & Ambient Notes)
      </h2>
      <p class="mt-1 text-sm text-[#737373]">
        严格对齐 <code>refero-styles Ui</code> 单色调系统与 MIMI Signal 蓝；包含 6 弦 15 品现代磨砂吉他指板、双圆点 12 品八度泛音点、LED 脉冲发光微动效与 Canvas 2D 物理光标流体粒子。
      </p>
    </div>

    <!-- View Switcher Tabs -->
    <div class="flex items-center rounded-[18px] border border-[#e5e5e5] bg-[#f5f5f5] p-1 text-xs font-medium">
      <button
        type="button"
        onclick={() => (activeTab = 'preview')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'preview' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        🌟 交互演示
      </button>
      <button
        type="button"
        onclick={() => (activeTab = 'code')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'code' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        💻 示例源码
      </button>
      <button
        type="button"
        onclick={() => (activeTab = 'tokens')}
        class="rounded-[14px] px-3 py-1.5 transition-all {activeTab === 'tokens' ? 'bg-white text-[#0a0a0a] shadow-xs' : 'text-[#737373] hover:text-[#0a0a0a]'}"
      >
        📐 Token 规范
      </button>
    </div>
  </div>

  {#if activeTab === 'preview'}
    <div class="space-y-8">
      <!-- ====================================================================
           1. VIRTUAL FRETBOARD INTERACTIVE PLAYGROUND
           ==================================================================== -->
      <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 sm:p-7 shadow-xs space-y-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div class="flex items-center gap-2">
              <span class="rounded-[12px] bg-[#41a1cf]/10 border border-[#41a1cf]/30 px-2 py-0.5 text-[11px] font-mono font-semibold text-[#41a1cf]">
                NEW FEATURE
              </span>
              <span class="text-[11px] font-mono text-[#737373]">COMPONENT 01</span>
            </div>
            <h3 class="font-display text-lg text-[#0a0a0a] mt-1">
              现代磨砂玻璃虚拟吉他指板 (VirtualFretboard.svelte)
            </h3>
            <p class="text-xs text-[#737373] mt-0.5">
              6 弦 15 品阶梯琴弦、发丝琴品、3/5/7/9/12/15 品位珍珠镶嵌与 Signal 蓝呼吸 LED 发音点。支持直接点击指板点位试音。
            </p>
          </div>

          <!-- Chord Presets Pill Bar -->
          <div class="flex flex-wrap items-center gap-1.5 rounded-[18px] border border-[#e5e5e5] bg-[#f9f9f9] p-1 text-xs">
            <span class="px-2 text-[11px] font-mono text-[#737373]">和弦预设:</span>
            {#each ['C', 'G', 'Am', 'F', 'Em', 'Dm', 'Solo12'] as ch}
              <button
                type="button"
                onclick={() => selectChord(ch)}
                class="rounded-[14px] px-2.5 py-1 font-semibold transition-all {selectedChord === ch ? 'bg-[#0a0a0a] text-white shadow-xs' : 'text-[#444141] hover:bg-[#eaeaea]'}"
              >
                {ch}
              </button>
            {/each}
          </div>
        </div>

        <!-- Fretboard Live Component Stage -->
        <div class="relative">
          <VirtualFretboard
            activeNotes={customActiveNotes}
            tuning={['E4', 'B3', 'G3', 'D3', 'A2', 'E2']}
            capo={fretboardCapo}
            theme={fretboardTheme}
            showNoteNames={fretboardShowPitch}
            interactive={true}
            soundEnabled={false}
            onNoteClick={handleFretboardClick}
          />
        </div>

        <!-- Fretboard Controller Bar -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] p-4 text-xs">
          <!-- Theme Switcher -->
          <div class="flex items-center justify-between sm:flex-col sm:items-start gap-1">
            <span class="font-medium text-[#444141]">指板主题模式:</span>
            <div class="flex items-center gap-1.5">
              <button
                type="button"
                onclick={() => (fretboardTheme = 'light')}
                class="rounded-[14px] border px-3 py-1 font-medium transition {fretboardTheme === 'light' ? 'border-[#0a0a0a] bg-white text-[#0a0a0a] shadow-xs' : 'border-[#e5e5e5] text-[#737373]'}"
              >
                ☀️ 极简白 (Light)
              </button>
              <button
                type="button"
                onclick={() => (fretboardTheme = 'dark')}
                class="rounded-[14px] border px-3 py-1 font-medium transition {fretboardTheme === 'dark' ? 'border-[#41a1cf] bg-[#1a1a24] text-white shadow-xs' : 'border-[#e5e5e5] text-[#737373]'}"
              >
                🌙 暗夜深色 (Dark)
              </button>
            </div>
          </div>

          <!-- Capo Slider -->
          <div class="flex flex-col gap-1">
            <div class="flex justify-between font-medium text-[#444141]">
              <span>变调夹 (Capo):</span>
              <span class="font-mono text-[#41a1cf] font-semibold">{fretboardCapo === 0 ? '无变调夹' : `第 ${fretboardCapo} 品`}</span>
            </div>
            <input
              type="range"
              min="0"
              max="7"
              step="1"
              bind:value={fretboardCapo}
              class="w-full"
            />
          </div>

          <!-- Note Name Toggle -->
          <div class="flex items-center justify-between sm:flex-col sm:items-start gap-1">
            <span class="font-medium text-[#444141]">音符音名显示:</span>
            <button
              type="button"
              onclick={() => (fretboardShowPitch = !fretboardShowPitch)}
              class="inline-flex items-center gap-1.5 rounded-[14px] border px-3 py-1 font-medium transition {fretboardShowPitch ? 'border-[#41a1cf] bg-[#41a1cf]/10 text-[#41a1cf]' : 'border-[#e5e5e5] bg-white text-[#444141]'}"
            >
              <span>{fretboardShowPitch ? '✓ 显示音名 (E4, G3...)' : '✕ 默认品数'}</span>
            </button>
          </div>

          <!-- Clear / Reset Notes -->
          <div class="flex items-center justify-between sm:flex-col sm:items-start gap-1">
            <span class="font-medium text-[#444141]">互动清空:</span>
            <button
              type="button"
              onclick={() => {
                customActiveNotes = [];
                selectedChord = 'None';
              }}
              class="rounded-[14px] border border-[#e5e5e5] bg-white px-3 py-1 text-[#e7000b] hover:bg-[#fff5f5] transition"
            >
              🗑️ 清空所有发音点
            </button>
          </div>
        </div>
      </div>

      <!-- ====================================================================
           2. AMBIENT MUSIC NOTE PARTICLES PLAYGROUND
           ==================================================================== -->
      <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 sm:p-7 shadow-xs space-y-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div class="flex items-center gap-2">
              <span class="rounded-[12px] bg-[#41a1cf]/10 border border-[#41a1cf]/30 px-2 py-0.5 text-[11px] font-mono font-semibold text-[#41a1cf]">
                AMBIENT CANVAS 2D
              </span>
              <span class="text-[11px] font-mono text-[#737373]">COMPONENT 02</span>
            </div>
            <h3 class="font-display text-lg text-[#0a0a0a] mt-1">
              氛围悬浮乐符粒子 (MusicNoteParticles.svelte)
            </h3>
            <p class="text-xs text-[#737373] mt-0.5">
              高帧率 Canvas 2D 乐符（♪, ♫, ♩, ♬, 𝄞, 𝄢, ✦）正弦轻柔摆动与呼吸透光。移动光标即可体验流体磁力排斥微动效。
            </p>
          </div>
        </div>

        <!-- Live Ambient Box with Particle Layer -->
        <div class="relative h-[220px] w-full overflow-hidden rounded-[20px] border border-[#e5e5e5] bg-gradient-to-b from-[#fafafa] to-[#f4f4f6] shadow-inner flex items-center justify-center">
          <!-- Background Floating Note Particles Layer -->
          <MusicNoteParticles
            count={particleCount}
            speed={particleSpeed}
            opacity={particleOpacity}
            color={particleColor}
            className="absolute inset-0"
          />

          <!-- Foreground Interactive Glass Card -->
          <div class="relative z-10 max-w-sm rounded-[18px] border border-white/80 bg-white/70 p-5 text-center shadow-lg backdrop-blur-md">
            <div class="inline-flex items-center gap-1.5 rounded-[18px] bg-[#0a0a0a] px-3 py-0.5 text-xs font-semibold text-white">
              <span class="text-xs">✦</span>
              <span>移动光标试探乐符流体排斥</span>
            </div>
            <p class="mt-2 text-xs text-[#737373] leading-relaxed">
              粒子在接近光标 150px 半径范围内产生平滑加速度偏转，移开后恢复正弦律动上升轨道。
            </p>
          </div>
        </div>

        <!-- Particle Controller Parameters -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] p-4 text-xs">
          <!-- Count Slider -->
          <div class="flex flex-col gap-1">
            <div class="flex justify-between font-medium text-[#444141]">
              <span>粒子密度 (Count):</span>
              <span class="font-mono text-[#0a0a0a] font-semibold">{particleCount} 个</span>
            </div>
            <input
              type="range"
              min="8"
              max="64"
              step="2"
              bind:value={particleCount}
              class="w-full"
            />
          </div>

          <!-- Speed Slider -->
          <div class="flex flex-col gap-1">
            <div class="flex justify-between font-medium text-[#444141]">
              <span>飘移速度 (Speed):</span>
              <span class="font-mono text-[#0a0a0a] font-semibold">{particleSpeed.toFixed(2)}x</span>
            </div>
            <input
              type="range"
              min="0.2"
              max="1.5"
              step="0.05"
              bind:value={particleSpeed}
              class="w-full"
            />
          </div>

          <!-- Opacity Slider -->
          <div class="flex flex-col gap-1">
            <div class="flex justify-between font-medium text-[#444141]">
              <span>基础透明度 (Opacity):</span>
              <span class="font-mono text-[#0a0a0a] font-semibold">{Math.round(particleOpacity * 100)}%</span>
            </div>
            <input
              type="range"
              min="0.08"
              max="0.6"
              step="0.02"
              bind:value={particleOpacity}
              class="w-full"
            />
          </div>

          <!-- Color Buttons -->
          <div class="flex flex-col gap-1">
            <span class="font-medium text-[#444141]">粒子配色:</span>
            <div class="flex gap-1.5">
              {#each [
                { label: 'Signal', val: '#41a1cf' },
                { label: 'Ink', val: '#0a0a0a' },
                { label: 'Ember', val: '#e7000b' },
                { label: 'Emerald', val: '#10b981' }
              ] as pc}
                <button
                  type="button"
                  onclick={() => (particleColor = pc.val)}
                  class="flex-1 rounded-[12px] py-1 text-[10px] font-semibold text-white transition {particleColor === pc.val ? 'ring-2 ring-black/20 scale-105' : 'opacity-80'}"
                  style="background-color: {pc.val};"
                >
                  {pc.label}
                </button>
              {/each}
            </div>
          </div>
        </div>
      </div>

      <!-- ====================================================================
           3. FLUID AUDIO WAVEFORM & FLOATING HUD
           ==================================================================== -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-12">
        <!-- Left: Stage -->
        <div class="lg:col-span-8 space-y-6">
          <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-5">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-[11px] font-mono text-[#737373]">COMPONENT 03</span>
                <h3 class="font-display text-base text-[#0a0a0a] mt-0.5">Canvas 2D 双层正弦/余弦流体声波 (FluidAudioWaveform)</h3>
              </div>
              <span class="rounded-[12px] bg-[#fafafa] border border-[#e5e5e5] px-2.5 py-0.5 text-xs font-mono text-[#41a1cf]">
                60 / 120 FPS GPU Accelerated
              </span>
            </div>

            <!-- Live Waveform Canvas Preview Center -->
            <div class="flex flex-col items-center justify-center rounded-[20px] border border-[#e5e5e5] bg-[#fafafa] p-8 space-y-4">
              <div class="rounded-[18px] border border-[#e5e5e5] bg-white p-4 shadow-sm backdrop-blur-md">
                <FluidAudioWaveform
                  {isPlaying}
                  {bpm}
                  {color}
                  width={waveWidth}
                  height={waveHeight}
                />
              </div>

              <div class="flex items-center gap-3">
                <button
                  type="button"
                  onclick={() => (isPlaying = !isPlaying)}
                  class="btn {isPlaying ? 'btn-primary' : 'btn-ghost'} !rounded-pill !px-4 !py-1.5 text-xs"
                >
                  {isPlaying ? '⏸ 暂停声波 (平滑收拢)' : '▶ 播放声波 (动态律动)'}
                </button>

                <span class="text-xs font-mono text-[#737373]">
                  Tempo: <strong class="text-[#0a0a0a]">{bpm} BPM</strong>
                </span>
              </div>
            </div>
          </div>

          <!-- Floating HUD Stage -->
          <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-4">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-[11px] font-mono text-[#737373]">COMPONENT 04</span>
                <h3 class="font-display text-base text-[#0a0a0a] mt-0.5">底部悬浮磨砂胶囊控制舱 (FloatingPlayerHUD)</h3>
              </div>
              <span class="rounded-[12px] bg-[#fafafa] border border-[#e5e5e5] px-2.5 py-0.5 text-xs font-mono text-[#22c55e]">
                Scroll > 350px Triggered
              </span>
            </div>

            <div class="relative overflow-hidden rounded-[20px] border border-[#e5e5e5] bg-[#f9faf7] p-8 flex items-center justify-center min-h-[140px]">
              <!-- Embedded Mock Capsule -->
              <div class="flex flex-wrap items-center gap-3 rounded-[18px] border border-[#e5e5e5] bg-white/90 p-3 shadow-[0_12px_36px_-4px_rgba(0,0,0,0.12),0_0_0_1px_rgba(0,0,0,0.04)] backdrop-blur-[20px]">
                <button
                  type="button"
                  onclick={() => (hudPlaying = !hudPlaying)}
                  class="flex h-9 w-9 items-center justify-center rounded-full text-white transition active:scale-90 {hudPlaying ? 'bg-[#41a1cf]' : 'bg-[#0a0a0a]'}"
                >
                  {#if hudPlaying}
                    <svg class="h-3.5 w-3.5 fill-current" viewBox="0 0 24 24">
                      <rect x="5" y="3" width="4.5" height="18" rx="1.5" />
                      <rect x="14.5" y="3" width="4.5" height="18" rx="1.5" />
                    </svg>
                  {:else}
                    <svg class="h-3.5 w-3.5 fill-current ml-0.5" viewBox="0 0 24 24">
                      <path d="M6 3.5v17a1 1 0 001.55.83l13-8.5a1 1 0 000-1.66l-13-8.5A1 1 0 006 3.5z" />
                    </svg>
                  {/if}
                </button>

                <div class="flex flex-col pr-1">
                  <span class="text-xs font-semibold text-[#0a0a0a]">晴天</span>
                  <span class="text-[11px] text-[#737373]">周杰伦</span>
                </div>

                <div class="h-5 w-[1px] bg-[#e5e5e5]"></div>

                <FluidAudioWaveform
                  isPlaying={hudPlaying}
                  bpm={hudSpeed}
                  color={hudPlaying ? '#0a0a0a' : '#737373'}
                  height={26}
                  width={100}
                />

                <div class="flex items-center gap-1.5 font-mono text-[11px] text-[#737373]">
                  <span>00:42</span>
                  <div class="h-1.5 w-24 rounded-full bg-[#f0f0f0] overflow-hidden">
                    <div class="h-full bg-[#41a1cf]" style="width: 35%;"></div>
                  </div>
                  <span>03:36</span>
                </div>

                <div class="rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-2.5 py-1 text-xs font-mono font-medium text-[#0a0a0a]">
                  ♩ {hudSpeed}
                </div>

                <button
                  type="button"
                  onclick={() => (hudShowTracks = !hudShowTracks)}
                  class="rounded-[18px] border border-[#e5e5e5] bg-[#fafafa] px-2.5 py-1 text-xs font-medium text-[#444141]"
                >
                  {hudTracksCount} 音轨
                </button>
              </div>
            </div>
          </div>

          <!-- Note Spark Trails & Resonance Art Stage -->
          <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-6 shadow-xs space-y-4">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-[11px] font-mono text-[#737373]">COMPONENT 05</span>
                <h3 class="font-display text-base text-[#0a0a0a] mt-0.5">谱面音符微光粒子流 & 同心共鸣环 (ScoreNoteSparkTrails)</h3>
              </div>
              <span class="rounded-[12px] bg-[#fafafa] border border-[#e5e5e5] px-2.5 py-0.5 text-xs font-mono text-[#41a1cf]">
                Canvas 2D Harmonic Overlay
              </span>
            </div>

            <!-- Clickable Interactive Stave Stage for Spark Emitter -->
            <div
              role="button"
              tabindex="0"
              onclick={triggerSpark}
              onkeydown={(e) => { if (e.key === 'Enter') sparkPositions = [{ x: 180, y: 70, pitch: testPitch }]; }}
              class="relative h-44 w-full cursor-crosshair overflow-hidden rounded-[20px] border border-[#e5e5e5] {sparkTheme === 'dark' ? 'bg-[#141419]' : 'bg-[#fafafa]'} p-4 select-none"
            >
              <!-- Decorative Stave Lines -->
              <div class="pointer-events-none absolute inset-x-8 top-12 flex flex-col gap-2.5 opacity-25">
                <div class="h-[1px] w-full bg-[#737373]"></div>
                <div class="h-[1px] w-full bg-[#737373]"></div>
                <div class="h-[1px] w-full bg-[#737373]"></div>
                <div class="h-[1px] w-full bg-[#737373]"></div>
                <div class="h-[1px] w-full bg-[#737373]"></div>
                <div class="h-[1px] w-full bg-[#737373]"></div>
              </div>

              <!-- Spark Trails Overlay Component -->
              <ScoreNoteSparkTrails
                activeNotePositions={sparkPositions}
                isPlaying={true}
              />

              <div class="pointer-events-none absolute bottom-3 left-4 flex items-center gap-2 text-[11px] text-[#737373]">
                <span class="inline-block h-2 w-2 rounded-full bg-[#41a1cf] animate-pulse"></span>
                <span>轻点五线/六线谱表任意位置触发真实物理喷泉音符微光与谐波共振环</span>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-3 text-xs">
              <div class="flex items-center gap-2">
                <span class="font-medium text-[#444141]">音高色彩测试:</span>
                <button
                  type="button"
                  onclick={() => { testPitch = 40; sparkPositions = [{ x: 120, y: 90, pitch: 40 }]; }}
                  class="rounded-pill border border-[#e5e5e5] px-2.5 py-1 transition {testPitch <= 48 ? 'bg-[#2563eb] text-white font-medium shadow-xs' : 'bg-[#fafafa] text-[#444141]'}"
                >
                  低音 E2 (深蓝靛青)
                </button>
                <button
                  type="button"
                  onclick={() => { testPitch = 60; sparkPositions = [{ x: 200, y: 70, pitch: 60 }]; }}
                  class="rounded-pill border border-[#e5e5e5] px-2.5 py-1 transition {testPitch > 48 && testPitch < 68 ? 'bg-[#41a1cf] text-white font-medium shadow-xs' : 'bg-[#fafafa] text-[#444141]'}"
                >
                  中音 C4 (璀璨天青)
                </button>
                <button
                  type="button"
                  onclick={() => { testPitch = 80; sparkPositions = [{ x: 280, y: 50, pitch: 80 }]; }}
                  class="rounded-pill border border-[#e5e5e5] px-2.5 py-1 transition {testPitch >= 68 ? 'bg-[#f59e0b] text-white font-medium shadow-xs' : 'bg-[#fafafa] text-[#444141]'}"
                >
                  高音 G5 (流金暖阳)
                </button>
              </div>

              <div class="flex items-center gap-2">
                <button
                  type="button"
                  onclick={() => (autoSpark = !autoSpark)}
                  class="btn {autoSpark ? 'btn-primary' : 'btn-ghost'} !rounded-pill !px-3 !py-1 text-xs"
                >
                  {autoSpark ? '⏹ 停止连发' : '✨ 自动连发演示'}
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Right: Parameter Tuning -->
        <div class="lg:col-span-4 space-y-5">
          <div class="rounded-[24px] border border-[#e5e5e5] bg-white p-5 shadow-xs space-y-4">
            <h3 class="font-display text-base text-[#0a0a0a]">🎛️ 声波参数调谐</h3>
            <p class="text-xs text-[#737373]">实时微调正余弦波幅、律动周期与主题色彩。</p>

            <div class="space-y-4 text-xs">
              <div>
                <div class="flex justify-between font-medium text-[#444141]">
                  <span>律动速度 (BPM)</span>
                  <span class="font-mono text-[#0a0a0a]">{bpm} BPM</span>
                </div>
                <input
                  type="range"
                  min="40"
                  max="200"
                  step="1"
                  bind:value={bpm}
                  class="mt-2 w-full"
                />
              </div>

              <div>
                <div class="flex justify-between font-medium text-[#444141]">
                  <span>声波宽度 (Width)</span>
                  <span class="font-mono text-[#0a0a0a]">{waveWidth}px</span>
                </div>
                <input
                  type="range"
                  min="80"
                  max="260"
                  step="10"
                  bind:value={waveWidth}
                  class="mt-2 w-full"
                />
              </div>

              <div>
                <div class="flex justify-between font-medium text-[#444141]">
                  <span>声波高度 (Height)</span>
                  <span class="font-mono text-[#0a0a0a]">{waveHeight}px</span>
                </div>
                <input
                  type="range"
                  min="20"
                  max="60"
                  step="2"
                  bind:value={waveHeight}
                  class="mt-2 w-full"
                />
              </div>

              <div>
                <span class="font-medium text-[#444141]">主波形配色</span>
                <div class="mt-2 flex gap-2">
                  {#each [
                    { label: 'Ink', val: '#0a0a0a' },
                    { label: 'Signal', val: '#41a1cf' },
                    { label: 'Ember', val: '#e7000b' },
                    { label: 'Forest', val: '#10b981' }
                  ] as c}
                    <button
                      type="button"
                      onclick={() => (color = c.val)}
                      class="h-7 flex-1 rounded-[12px] border transition text-[11px] font-medium {color === c.val ? 'border-[#0a0a0a] ring-2 ring-black/10 font-semibold' : 'border-[#e5e5e5]'}"
                      style="background-color: {c.val}; color: #fff;"
                    >
                      {c.label}
                    </button>
                  {/each}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  {:else if activeTab === 'code'}
    <CodeBlock code={snippetCode} language="html" title="VirtualFretboard_AmbientNotes.svelte" />
  {:else if activeTab === 'tokens'}
    <CodeBlock code={tokensSpec} language="css" title="Fretboard & Ambient Particles Design Tokens" />
  {/if}
</div>
