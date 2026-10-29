<script lang="ts">
  import CodeBlock from './CodeBlock.svelte';
  import MusicNoteParticles from '../MusicNoteParticles.svelte';
  import VirtualFretboard from '../player/VirtualFretboard.svelte';

  // Sub-tab: 'intro' | 'paper-acoustics' | 'fretboard' | 'particles'
  let activeSection = $state<'intro' | 'paper-acoustics' | 'fretboard' | 'particles'>('intro');
  let activeView = $state<'preview' | 'code' | 'tokens'>('preview');

  // 1. PAPER INTRO CONTROLS
  let introTriggerCount = $state(0);
  let introToastMsg = $state<string | null>(null);

  function triggerMasterpieceIntro() {
    if (typeof window !== 'undefined') {
      sessionStorage.removeItem('mimi_paper_intro_played');
      window.dispatchEvent(new CustomEvent('mimi:play-intro'));
      introTriggerCount += 1;
      showToast('📖 已发送 mimi:play-intro 事件，纸质书卷开卷仪式已启动！');
    }
  }

  function resetIntroSession() {
    if (typeof window !== 'undefined') {
      sessionStorage.removeItem('mimi_paper_intro_played');
      showToast('🔄 已重置 sessionStorage 状态，下次刷新首页将自动开卷！');
    }
  }

  function showToast(msg: string) {
    introToastMsg = msg;
    setTimeout(() => {
      if (introToastMsg === msg) introToastMsg = null;
    }, 3200);
  }

  // 2. PAPER ACOUSTICS & WATERMARKS
  interface WatermarkNoteItem {
    id: number;
    x: number;
    y: number;
    symbol: string;
  }

  let activeWatermarks = $state<WatermarkNoteItem[]>([]);
  let wmCounter = 0;

  function triggerWatermarkWave(e: MouseEvent) {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const glyphs = ['♪', '♫', '♩', '♬', '𝄞', '𝄢'];
    const symbol = glyphs[Math.floor(Math.random() * glyphs.length)];

    const id = ++wmCounter;
    activeWatermarks.push({ id, x, y, symbol });

    setTimeout(() => {
      activeWatermarks = activeWatermarks.filter((w) => w.id !== id);
    }, 1800);
  }

  // 3. VIRTUAL FRETBOARD DEMO
  let fretboardCapo = $state(0);
  let fretboardActiveNotes = $state([
    { string: 5, fret: 3 },
    { string: 4, fret: 2 },
    { string: 2, fret: 1 },
  ]);

  function playChord(chord: 'C' | 'G' | 'Am' | 'Em') {
    switch (chord) {
      case 'C':
        fretboardActiveNotes = [
          { string: 5, fret: 3 },
          { string: 4, fret: 2 },
          { string: 2, fret: 1 },
        ];
        break;
      case 'G':
        fretboardActiveNotes = [
          { string: 6, fret: 3 },
          { string: 5, fret: 2 },
          { string: 1, fret: 3 },
        ];
        break;
      case 'Am':
        fretboardActiveNotes = [
          { string: 4, fret: 2 },
          { string: 3, fret: 2 },
          { string: 2, fret: 1 },
        ];
        break;
      case 'Em':
        fretboardActiveNotes = [
          { string: 5, fret: 2 },
          { string: 4, fret: 2 },
        ];
        break;
    }
  }

  const codeSnippets = {
    intro: `<script>
  import MasterpieceIntro from './components/ambient/MasterpieceIntro.svelte';
<\/script>

<!-- 在布局中全局挂载 -->
<MasterpieceIntro client:load />

<!-- 随时通过自定义事件重新触发开卷 -->
<button onclick={() => window.dispatchEvent(new CustomEvent('mimi:play-intro'))}>
  📖 重温书卷开卷
</button>`,

    paperAcoustics: `<script>
  import ScoreNoteSparkTrails from './components/player/ScoreNoteSparkTrails.svelte';
<\/script>

<!-- 纸质声学共振水印层（贴合在乐谱背面） -->
<ScoreNoteSparkTrails {api} isPlaying={playing} scoreContainer={container} />`,

    fretboard: `<script>
  import VirtualFretboard from './components/player/VirtualFretboard.svelte';
<\/script>

<VirtualFretboard
  activeNotes={[{ string: 5, fret: 3 }, { string: 4, fret: 2 }, { string: 2, fret: 1 }]}
  capo={0}
/>`,

    particles: `<script>
  import MusicNoteParticles from './components/ambient/MusicNoteParticles.svelte';
<\/script>

<MusicNoteParticles count={24} color="#737373" opacity={0.15} speed={0.6} />`,
  };
</script>

<div class="space-y-8">
  <!-- Toast Message -->
  {#if introToastMsg}
    <div class="fixed top-6 right-6 z-[9999] rounded-pill border hairline bg-paper/95 px-4 py-2 text-xs font-medium text-ink shadow-lg backdrop-blur-md animate-blur-up">
      {introToastMsg}
    </div>
  {/if}

  <!-- Section Header -->
  <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between border-b hairline pb-6">
    <div>
      <h2 class="font-display text-heading-md font-medium text-ink flex items-center gap-2">
        <span>📖</span>
        <span>纸质书卷与墨韵动效实验室</span>
      </h2>
      <p class="mt-1 text-body-sm text-mid-gray">
        以“把每一份乐谱，都当作一页书来对待”为核心灵魂，纯净、温润的手作纸质与声学共鸣微交互。
      </p>
    </div>

    <!-- View Mode Switcher -->
    <div class="flex items-center gap-1 rounded-pill border hairline bg-surface-alt p-1 self-start sm:self-auto">
      <button
        onclick={() => (activeView = 'preview')}
        class="rounded-pill px-3 py-1 text-caption font-medium transition cursor-pointer {activeView === 'preview' ? 'bg-paper text-ink shadow-xs' : 'text-mid-gray hover:text-ink'}"
      >
        交互演示
      </button>
      <button
        onclick={() => (activeView = 'code')}
        class="rounded-pill px-3 py-1 text-caption font-medium transition cursor-pointer {activeView === 'code' ? 'bg-paper text-ink shadow-xs' : 'text-mid-gray hover:text-ink'}"
      >
        代码范式
      </button>
    </div>
  </div>

  <!-- Sub-Navigation Navigation Chips -->
  <div class="flex flex-wrap gap-2">
    <button
      onclick={() => (activeSection = 'intro')}
      class="rounded-pill border px-4 py-1.5 text-caption font-medium transition cursor-pointer {activeSection === 'intro' ? 'border-ink bg-ink text-white shadow-xs' : 'border-hairline bg-surface-alt text-mid-gray hover:border-mid-gray hover:text-ink'}"
    >
      📖 1. 纸质书卷开卷大片
    </button>
    <button
      onclick={() => (activeSection = 'paper-acoustics')}
      class="rounded-pill border px-4 py-1.5 text-caption font-medium transition cursor-pointer {activeSection === 'paper-acoustics' ? 'border-ink bg-ink text-white shadow-xs' : 'border-hairline bg-surface-alt text-mid-gray hover:border-mid-gray hover:text-ink'}"
    >
      📜 2. 谱面声学纸质水印
    </button>
    <button
      onclick={() => (activeSection = 'fretboard')}
      class="rounded-pill border px-4 py-1.5 text-caption font-medium transition cursor-pointer {activeSection === 'fretboard' ? 'border-ink bg-ink text-white shadow-xs' : 'border-hairline bg-surface-alt text-mid-gray hover:border-mid-gray hover:text-ink'}"
    >
      🎸 3. 极简原声指板
    </button>
    <button
      onclick={() => (activeSection = 'particles')}
      class="rounded-pill border px-4 py-1.5 text-caption font-medium transition cursor-pointer {activeSection === 'particles' ? 'border-ink bg-ink text-white shadow-xs' : 'border-hairline bg-surface-alt text-mid-gray hover:border-mid-gray hover:text-ink'}"
    >
      ✨ 4. 浮动乐理微粒场
    </button>
  </div>

  <!-- SECTION 1: MASTERPIECE INTRO -->
  {#if activeSection === 'intro'}
    <div class="space-y-6">
      {#if activeView === 'preview'}
        <div class="rounded-card border hairline bg-paper p-6 sm:p-10 space-y-6">
          <div class="flex items-start justify-between">
            <div>
              <h3 class="font-display text-subheading font-medium text-ink">温润棉纸书卷·墨韵开卷大片 (Living Paper Folio)</h3>
              <p class="text-body-sm text-mid-gray mt-1">
                以真实手工纸张纹理为幕，双页典籍徐徐翻开，墨线浸润成谱，伴随原声尼龙弦共鸣和弦轻柔启幕。
              </p>
            </div>
            <span class="rounded-pill border hairline bg-surface-alt px-3 py-1 text-caption font-mono text-mid-gray">
              WEB AUDIO + SVELTE 5
            </span>
          </div>

          <!-- Trigger Showcase Sandbox -->
          <div class="rounded-inner border hairline bg-canvas p-8 sm:p-12 text-center flex flex-col items-center justify-center gap-6">
            <div class="h-16 w-16 rounded-full border hairline bg-paper flex items-center justify-center text-3xl shadow-xs">
              📖
            </div>
            <div class="max-w-md space-y-1">
              <h4 class="font-display text-body font-medium text-ink">亲身体验纸质书卷开卷仪式</h4>
              <p class="text-caption text-mid-gray">
                点击下方按钮即可立即唤起全屏开卷大片。支持按下 ESC 键或右上角胶囊快速跳过。
              </p>
            </div>
            <div class="flex flex-wrap items-center justify-center gap-3">
              <button
                onclick={triggerMasterpieceIntro}
                class="btn btn-primary !py-2.5 !px-6 text-body-sm shadow-sm hover:shadow-md cursor-pointer flex items-center gap-2"
              >
                <span>立即启动开卷大片</span>
                <span class="rounded bg-white/20 px-1.5 py-0.5 text-[10px] font-mono">⌘K</span>
              </button>
              <button
                onclick={resetIntroSession}
                class="btn btn-secondary !py-2.5 !px-4 text-body-sm cursor-pointer"
              >
                重置首访记忆
              </button>
            </div>
          </div>
        </div>
      {:else}
        <CodeBlock code={codeSnippets.intro} language="html" title="MasterpieceIntro.svelte" />
      {/if}
    </div>
  {/if}

  <!-- SECTION 2: PAPER ACOUSTICS -->
  {#if activeSection === 'paper-acoustics'}
    <div class="space-y-6">
      {#if activeView === 'preview'}
        <div class="rounded-card border hairline bg-paper p-6 sm:p-10 space-y-6">
          <div>
            <h3 class="font-display text-subheading font-medium text-ink">谱面声学纸质水印 (Tactile Paper Watermarks)</h3>
            <p class="text-body-sm text-mid-gray mt-1">
              在乐谱演奏时，背景如棉纸浸水般浮现出若隐若现的五线谱声波与浮雕音符水印，克制而富有呼吸感。
            </p>
          </div>

          <!-- Interactive Click Sandbox -->
          <div
            onclick={triggerWatermarkWave}
            class="relative h-64 rounded-inner border hairline bg-[#fbfaf7] overflow-hidden cursor-crosshair flex items-center justify-center select-none"
            role="button"
            tabindex="0"
            onkeydown={(e) => { if (e.key === ' ') triggerWatermarkWave(e as any); }}
          >
            <!-- Watermarks -->
            {#each activeWatermarks as wm (wm.id)}
              <div
                class="absolute pointer-events-none -translate-x-1/2 -translate-y-1/2"
                style="left: {wm.x}px; top: {wm.y}px;"
              >
                <div class="h-16 w-16 rounded-full border border-black/10 acoustic-ripple"></div>
                <span class="absolute inset-0 flex items-center justify-center font-serif text-2xl text-black/40 paper-emboss">
                  {wm.symbol}
                </span>
              </div>
            {/each}

            <div class="text-center pointer-events-none">
              <span class="font-serif text-3xl text-mid-gray/40 block mb-2">𝄞</span>
              <p class="text-caption font-medium text-mid-gray">在区域内任意点击，体验棉纸声学水波纹与水印浮雕浮现</p>
            </div>
          </div>
        </div>
      {:else}
        <CodeBlock code={codeSnippets.paperAcoustics} language="html" title="ScoreNoteSparkTrails.svelte" />
      {/if}
    </div>
  {/if}

  <!-- SECTION 3: FRETBOARD -->
  {#if activeSection === 'fretboard'}
    <div class="space-y-6">
      {#if activeView === 'preview'}
        <div class="rounded-card border hairline bg-paper p-6 sm:p-10 space-y-6">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h3 class="font-display text-subheading font-medium text-ink">极简原声吉他虚拟指板</h3>
              <p class="text-body-sm text-mid-gray mt-1">
                高精细 15 品现代指板，真实弦径与双泛音点，实时点亮极简 LED 脉冲光环。
              </p>
            </div>
            <div class="flex items-center gap-2">
              <button onclick={() => playChord('C')} class="btn btn-secondary !py-1 !px-3 text-caption cursor-pointer">C 和弦</button>
              <button onclick={() => playChord('G')} class="btn btn-secondary !py-1 !px-3 text-caption cursor-pointer">G 和弦</button>
              <button onclick={() => playChord('Am')} class="btn btn-secondary !py-1 !px-3 text-caption cursor-pointer">Am 和弦</button>
              <button onclick={() => playChord('Em')} class="btn btn-secondary !py-1 !px-3 text-caption cursor-pointer">Em 和弦</button>
            </div>
          </div>

          <div class="rounded-inner border hairline bg-canvas p-4 sm:p-6 overflow-x-auto">
            <VirtualFretboard activeNotes={fretboardActiveNotes} capo={fretboardCapo} />
          </div>
        </div>
      {:else}
        <CodeBlock code={codeSnippets.fretboard} language="html" title="VirtualFretboard.svelte" />
      {/if}
    </div>
  {/if}

  <!-- SECTION 4: PARTICLES -->
  {#if activeSection === 'particles'}
    <div class="space-y-6">
      {#if activeView === 'preview'}
        <div class="rounded-card border hairline bg-paper p-6 sm:p-10 space-y-6">
          <div>
            <h3 class="font-display text-subheading font-medium text-ink">浮动乐理微粒场 (Canvas 2D)</h3>
            <p class="text-body-sm text-mid-gray mt-1">
              极轻量级 60FPS 音符环境微粒，正弦漂浮并响应鼠标排斥流体动量。
            </p>
          </div>

          <div class="relative h-64 rounded-inner border hairline bg-canvas overflow-hidden">
            <MusicNoteParticles count={28} color="#737373" minOpacity={0.25} maxOpacity={0.25} />
            <div class="absolute inset-0 flex items-center justify-center text-caption text-mid-gray pointer-events-none">
              在区域内移动鼠标观察微粒流体排斥
            </div>
          </div>
        </div>
      {:else}
        <CodeBlock code={codeSnippets.particles} language="html" title="MusicNoteParticles.svelte" />
      {/if}
    </div>
  {/if}
</div>
