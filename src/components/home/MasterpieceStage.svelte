<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { scoreAuditionEngine, type AuditionState } from '../../lib/scoreAuditionEngine';
  import { GUITAR_CHORDS, chordSvg } from '../../lib/chords';
  import {
    attachChordPreviewListeners,
    chordPreviewAccessibleName,
    createChordPreviewState,
    createChordPreviewTarget as buildChordPreviewTarget,
    positionChordPopover,
    resolveChordPreview,
    updateChordPreviewState,
    type ChordPreviewAction,
    type ChordPopoverPosition,
    type ChordPreviewTarget,
  } from '../../lib/ui/chordPreview.ts';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences';
  import { registerMotionSurface, surfaceMotion } from '../../lib/ui/motion';
  import { paperReveal } from '../../lib/ui/paperReveal';

  interface MasterpieceItem {
    id: string;
    title: string;
    artist: string;
    key: string;
    difficulty: number;
    sheetForm: string;
    seal: string;
    chords: string[];
    scoreUrl: string;
    description: string;
  }

  const masterpieces: MasterpieceItem[] = [
    {
      id: '1sdc49P3eKm',
      title: '晴天',
      artist: '周杰伦',
      key: 'G',
      difficulty: 2,
      sheetForm: '指弹谱',
      seal: '晴',
      chords: ['G', 'Em7', 'Cadd9', 'D'],
      scoreUrl: '/storage/scores/1sdc49P3eKm.ibe',
      description: '华语乐坛青春图腾，经典前奏原版指弹，前奏滑音与和弦分解极其优美。',
    },
    {
      id: '1sdiivPR3YW',
      title: '老男孩',
      artist: '筷子兄弟',
      key: 'C',
      difficulty: 1,
      sheetForm: '指弹谱',
      seal: '老',
      chords: ['C', 'G', 'Am', 'F'],
      scoreUrl: '/storage/scores/1sdiivPR3YW.ibe',
      description: '指弹经典入门圣经，旋律线条深情动人，适合新手第一首完整攻克的指弹金曲。',
    },
    {
      id: '1sdjKw3nhA0',
      title: '反方向的钟',
      artist: '周杰伦',
      key: 'B',
      difficulty: 3,
      sheetForm: '专业弹唱',
      seal: '钟',
      chords: ['B', 'G#m', 'E', 'F#'],
      scoreUrl: '/storage/scores/1sdjKw3nhA0.ibe',
      description: '时空倒流感编曲，经典吉他分解和弦与切音节奏，高级吉他手进阶必练。',
    },
    {
      id: '1yDFAg9Z3mU',
      title: '后来',
      artist: '刘若英',
      key: 'Eb',
      difficulty: 2,
      sheetForm: '指弹独奏',
      seal: '后',
      chords: ['Eb', 'Cm', 'Ab', 'Bb'],
      scoreUrl: '/storage/scores/1yDFAg9Z3mU.ibe',
      description: '温暖治愈的经典旋律，高音区泛音与琶音交织，细腻触弦质感拉满。',
    },
  ];

  let cardRotations = $state<Record<string, { rx: number; ry: number; shineX: number; shineY: number }>>({});
  let hoveredCardId = $state<string | null>(null);
  let spatialAllowed = $state(false);

  // Audition state
  let audition = $state<AuditionState>(scoreAuditionEngine.getState());

  const chordPreviewTooltipId = 'home-stage-chord-preview-tooltip';
  let chordPreviewState = $state(createChordPreviewState());
  let activeChordPeek = $derived(resolveChordPreview(chordPreviewState));
  let chordPreviewElement = $state<HTMLDivElement | null>(null);
  let chordPreviewPosition = $state<ChordPopoverPosition | null>(null);
  let chordPreviewPositionRevision = 0;

  function createChordPreviewTarget(event: Event, chordName: string): ChordPreviewTarget | null {
    const anchor = event.currentTarget;
    const frets = GUITAR_CHORDS[chordName];
    if (!(anchor instanceof HTMLElement)) return null;
    return buildChordPreviewTarget(anchor, chordName, frets ? chordSvg(chordName, frets) : null);
  }

  function updateChordPreview(action: ChordPreviewAction) {
    const previous = resolveChordPreview(chordPreviewState);
    chordPreviewState = updateChordPreviewState(chordPreviewState, action);
    const active = resolveChordPreview(chordPreviewState);
    if (!active) {
      // Keep the last measured style through Svelte's outro transition.
      chordPreviewPositionRevision += 1;
      return;
    }
    if (previous?.anchor !== active.anchor) chordPreviewPosition = null;
    void positionActiveChordPreview();
  }

  function handleChordPreview(event: Event, chordName: string, type: 'hover' | 'focus' | 'activate') {
    const target = createChordPreviewTarget(event, chordName);
    if (target) updateChordPreview({ type, target });
  }

  function handleChordPreviewEnd(event: Event, type: 'leave' | 'blur') {
    const anchor = event.currentTarget;
    if (anchor instanceof HTMLElement) updateChordPreview({ type, anchor });
  }

  async function positionActiveChordPreview() {
    const target = resolveChordPreview(chordPreviewState);
    if (!target) return;
    const revision = ++chordPreviewPositionRevision;
    await tick();
    if (revision !== chordPreviewPositionRevision) return;
    const current = resolveChordPreview(chordPreviewState);
    const popover = chordPreviewElement;
    if (!current || current.anchor !== target.anchor || !popover) return;
    if (target.anchor.isConnected === false) {
      updateChordPreview({ type: 'dismiss' });
      return;
    }

    const rect = target.anchor.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    if (rect.bottom <= 0 || rect.top >= viewportHeight || rect.right <= 0 || rect.left >= viewportWidth) {
      if (chordPreviewPosition) updateChordPreview({ type: 'dismiss' });
      return;
    }
    chordPreviewPosition = positionChordPopover(
      rect,
      { width: popover.offsetWidth, height: popover.offsetHeight },
      { width: viewportWidth, height: viewportHeight },
    );
  }

  $effect(() => {
    if (!resolveChordPreview(chordPreviewState)) return;
    return attachChordPreviewListeners({
      getActive: () => resolveChordPreview(chordPreviewState),
      getPopover: () => chordPreviewElement,
      dismiss: () => updateChordPreview({ type: 'dismiss' }),
      reposition: () => { void positionActiveChordPreview(); },
    });
  });
  onMount(() => () => {
    chordPreviewPositionRevision += 1;
  });

  function handleCardMouseMove(e: MouseEvent, id: string) {
    if (!spatialAllowed || document.hidden || !window.matchMedia('(hover: hover) and (pointer: fine)').matches) return;
    const card = e.currentTarget as HTMLElement;
    if (!card) return;
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const cx = rect.width / 2;
    const cy = rect.height / 2;
    const rx = ((y - cy) / cy) * -6;
    const ry = ((x - cx) / cx) * 6;
    const shineX = (x / rect.width) * 100;
    const shineY = (y / rect.height) * 100;
    cardRotations[id] = { rx, ry, shineX, shineY };
    hoveredCardId = id;
  }

  function handleCardMouseLeave(id: string) {
    cardRotations[id] = { rx: 0, ry: 0, shineX: 50, shineY: 50 };
    if (hoveredCardId === id) hoveredCardId = null;
  }

  onMount(() => {
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => {
      spatialAllowed = mode === 'full';
      if (!spatialAllowed) { cardRotations = {}; hoveredCardId = null; }
    });
    const unsub = scoreAuditionEngine.subscribe((st) => {
      audition = st;
    });
    return () => {
      unsub();
      unsubscribeMotion();
    };
  });

  async function triggerAudition(e: MouseEvent, tab: MasterpieceItem) {
    e.preventDefault();
    e.stopPropagation();
    await scoreAuditionEngine.togglePlayTab(tab);
  }
</script>

<section class="mt-14">
  <!-- Section Title Header -->
  <div class="flex items-end justify-between mb-6">
    <div>
      <div class="flex items-center gap-2">
        <span class="h-4 w-1 bg-[#c49a45] rounded-full"></span>
        <h2 class="font-display text-2xl sm:text-3xl font-bold text-[#2d2926]">
          精选曲目展示
        </h2>
      </div>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-1 pl-6">
        示例曲目展示，查看卡片排版并尝试打开曲谱或试听
      </p>
    </div>
    <a
      href="/tabs?sort=1"
      class="hidden sm:inline-flex items-center gap-1 text-xs font-serif font-medium text-[#966b26] hover:text-[#c49a45] transition-colors"
    >
      <span>浏览全部曲谱</span>
      <span>→</span>
    </a>
  </div>

  <!-- 4-Card 3D Magnetic Grid -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5">
    {#each masterpieces as tab, index (tab.id)}
      {@const rot = cardRotations[tab.id] || { rx: 0, ry: 0, shineX: 50, shineY: 50 }}
      {@const isPlaying = audition.isPlaying && audition.currentTabId === tab.id}
      {@const isLoading = audition.isLoading && audition.currentTabId === tab.id}

      <div class="perspective-[1000px]" use:paperReveal={{ delay: index * 20 }}>
        <div
          onmousemove={(e) => handleCardMouseMove(e, tab.id)}
          onmouseleave={() => handleCardMouseLeave(tab.id)}
          class="manuscript-card group relative flex flex-col justify-between rounded-3xl border border-[#e2d8c3] bg-[#ffffff] p-5 shadow-[0_8px_24px_rgba(76,59,43,0.06)] hover:border-[#c49a45] hover:shadow-[0_16px_40px_rgba(196,154,69,0.18)] overflow-hidden h-full"
          style="transform: rotateX({rot.rx}deg) rotateY({rot.ry}deg) translateZ({hoveredCardId === tab.id ? '8px' : '0px'}); transform-style: preserve-3d;"
        >
          <!-- Specular Light Reflection -->
          <div
            class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 group-hover:opacity-100"
            style="background: radial-gradient(300px circle at {rot.shineX}% {rot.shineY}%, rgba(196, 154, 69, 0.1), transparent 70%);"
          ></div>

          <div>
            <!-- Top Row: Seal & Heat -->
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="flex h-6 w-6 items-center justify-center rounded-lg border border-[#c84b31]/50 bg-[#c84b31]/10 font-serif text-xs font-bold text-[#c84b31]">
                  {tab.seal}
                </span>
                <span class="font-mono text-[11px] font-semibold text-[#8c7b68]">NO. {tab.id.slice(0, 4).toUpperCase()}</span>
              </div>
              <span class="rounded-full border border-[#e8e2d4] bg-[#fbf9f4] px-2 py-0.5 font-mono text-[11px] text-[#c84b31] shadow-3xs">
                精选展示
              </span>
            </div>

            <!-- Title & Artist -->
            <div class="mt-4">
              <a
                href={`/tabs/${tab.id}`}
                class="block font-display text-xl font-bold text-[#2d2926] group-hover:text-[#966b26] transition-colors truncate"
              >
                {tab.title}
              </a>
              <div class="flex items-center gap-2 text-xs font-serif text-[#8c7b68] mt-1">
                <span>{tab.artist}</span>
                <span class="text-[#d8ccb8]">·</span>
                <span class="text-[#8f6d2b] font-medium">{tab.key} 调 {tab.sheetForm}</span>
              </div>
            </div>

            <!-- Description -->
            <p class="mt-3 text-xs font-serif text-[#705c42] line-clamp-2 leading-relaxed opacity-90">
              {tab.description}
            </p>

            <!-- Manuscript Mini Graphic & Real Score Play Button -->
            <div class="mt-4 relative rounded-2xl border border-[#e2d8c3] bg-[#faf8f4] p-3.5 overflow-hidden shadow-inner">
              <div class="flex items-center justify-between text-[10px] font-mono text-[#8c7b68] mb-2">
                <span class="font-bold text-[#5c4a38]">TAB SCORE PREVIEW</span>
                <span class="text-[#2e7d32] bg-[#2e7d32]/10 border border-[#2e7d32]/30 px-1.5 py-0.2 rounded text-[9px] font-semibold">示例排版</span>
              </div>

              <!-- Clean Vector SVG TAB Staff -->
              <div class="relative py-1 select-none">
                <svg viewBox="0 0 240 56" class="w-full h-[56px] overflow-visible">
                  <!-- Bar Lines -->
                  <line x1="10" y1="8" x2="10" y2="48" stroke="#d5c7b0" stroke-width="1.2" />
                  <line x1="230" y1="8" x2="230" y2="48" stroke="#d5c7b0" stroke-width="1.2" />

                  <!-- 4 Parallel Staff Lines -->
                  <line x1="10" y1="8" x2="230" y2="8" stroke="#e0d6c0" stroke-width="1" />
                  <line x1="10" y1="21" x2="230" y2="21" stroke="#e0d6c0" stroke-width="1" />
                  <line x1="10" y1="34" x2="230" y2="34" stroke="#e0d6c0" stroke-width="1" />
                  <line x1="10" y1="48" x2="230" y2="48" stroke="#e0d6c0" stroke-width="1" />

                  <!-- Column 1 (x=45) -->
                  <rect x="38" y="2" width="14" height="12" fill="#faf8f4" />
                  <text x="45" y="12" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#c84b31">0</text>

                  <rect x="38" y="15" width="14" height="12" fill="#faf8f4" />
                  <text x="45" y="25" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#c84b31">0</text>

                  <rect x="38" y="28" width="14" height="12" fill="#faf8f4" />
                  <text x="45" y="38" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#c84b31">3</text>

                  <!-- Column 2 (x=100) -->
                  <rect x="93" y="2" width="14" height="12" fill="#faf8f4" />
                  <text x="100" y="12" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">2</text>

                  <rect x="93" y="15" width="14" height="12" fill="#faf8f4" />
                  <text x="100" y="25" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">0</text>

                  <rect x="93" y="28" width="14" height="12" fill="#faf8f4" />
                  <text x="100" y="38" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">0</text>

                  <!-- Column 3 (x=155) -->
                  <rect x="148" y="2" width="14" height="12" fill="#faf8f4" />
                  <text x="155" y="12" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">3</text>

                  <rect x="148" y="15" width="14" height="12" fill="#faf8f4" />
                  <text x="155" y="25" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">2</text>

                  <rect x="148" y="28" width="14" height="12" fill="#faf8f4" />
                  <text x="155" y="38" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">0</text>

                  <!-- Column 4 (x=205) -->
                  <rect x="198" y="2" width="14" height="12" fill="#faf8f4" />
                  <text x="205" y="12" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">2</text>

                  <rect x="198" y="15" width="14" height="12" fill="#faf8f4" />
                  <text x="205" y="25" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">0</text>

                  <rect x="198" y="28" width="14" height="12" fill="#faf8f4" />
                  <text x="205" y="38" text-anchor="middle" font-size="10" font-family="monospace" font-weight="bold" fill="#2d2926">2</text>
                </svg>
              </div>

              <!-- Play / Audition Button -->
              <button
                type="button"
                onclick={(e) => triggerAudition(e, tab)}
                class="mt-3.5 min-h-[44px] w-full flex items-center justify-center gap-1.5 rounded-xl bg-gradient-to-r from-[#2d2926] via-[#3d3833] to-[#2d2926] hover:from-[#c49a45] hover:to-[#dfb55a] hover:text-[#2d2926] py-2 px-3 text-xs font-serif text-[#faf8f5] shadow-xs active:scale-95 transition-all cursor-pointer outline-none focus:outline-hidden ring-0 border border-[#5c4a38]/40"
              >
                {#if isLoading}
                  <div class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-white border-t-transparent"></div>
                  <span>加载曲谱…</span>
                {:else if isPlaying}
                  <span class="flex items-center gap-1">
                    <span class="h-2 w-2 rounded-full bg-[#c84b31] animate-ping"></span>
                    <span>⏸ 暂停播放</span>
                  </span>
                {:else}
                  <span>▶ 播放曲谱</span>
                {/if}
              </button>
              {#if audition.currentTabId === tab.id && audition.error}
                <div role="alert" class="mt-2 flex flex-wrap items-center justify-center gap-x-2 gap-y-1 text-xs text-[#9b3328]">
                  <span>曲谱播放失败：{audition.error}</span>
                  <a class="font-semibold underline underline-offset-2" href={'/tabs/' + tab.id}>打开《{tab.title}》曲谱</a>
                </div>
              {/if}
            </div>
          </div>

          <!-- Bottom: Chords & Enter Study Link -->
          <div class="mt-4 pt-3 border-t border-[#f0eae0] flex items-center justify-between text-xs font-serif">
            <div class="flex items-center gap-1">
              {#each tab.chords.slice(0, 3) as chord}
                <button
                  type="button"
                  onmouseenter={(e) => handleChordPreview(e, chord, 'hover')}
                  onmouseleave={(e) => handleChordPreviewEnd(e, 'leave')}
                  onfocus={(e) => handleChordPreview(e, chord, 'focus')}
                  onblur={(e) => handleChordPreviewEnd(e, 'blur')}
                  onclick={(e) => handleChordPreview(e, chord, 'activate')}
                  aria-label={chordPreviewAccessibleName(chord, Boolean(GUITAR_CHORDS[chord]))}
                  aria-describedby={chordPreviewTooltipId}
                  class="min-h-[44px] min-w-[44px] rounded-md border border-[#dfd7c5] bg-[#fbf9f4] px-1.5 py-0.5 text-[10px] font-mono font-medium text-[#5c4a38] hover:border-[#c49a45] hover:text-[#966b26] transition-colors"
                >
                  {chord}
                </button>
              {/each}
            </div>

            <a
              href={`/tabs/${tab.id}`}
              class="inline-flex items-center gap-1 text-[11px] font-medium text-[#2d2926] hover:text-[#966b26] transition-colors"
            >
              <span>研习</span>
              <span>→</span>
            </a>
          </div>
        </div>
      </div>
    {/each}
  </div>
</section>

<!-- Floating Chord Peek -->
{#if activeChordPeek}
  <div
    bind:this={chordPreviewElement}
    use:registerMotionSurface
    id={chordPreviewTooltipId}
    role="tooltip"
    class="fixed pointer-events-none z-50 overflow-auto rounded-xl border border-[#c49a45]/40 bg-[#ffffff] p-2.5 shadow-[0_12px_28px_rgba(76,59,43,0.18)]"
    style={`left:${chordPreviewPosition?.left ?? 0}px;top:${chordPreviewPosition?.top ?? 0}px;max-height:calc(100dvh - 16px);visibility:${chordPreviewPosition ? 'visible' : 'hidden'}`}
    transition:surfaceMotion={{ kind: 'menu' }}
  >
    <div class="text-center font-mono text-xs font-bold text-[#2d2926] mb-1">
      {activeChordPeek.hasDiagram ? `${activeChordPeek.name} 和弦图` : `${activeChordPeek.name} 和弦`}
    </div>
    <div class="flex h-24 w-24 items-center justify-center">
      {#if activeChordPeek.svg}
        {@html activeChordPeek.svg}
      {:else}
        <p class="max-w-full px-1 text-center text-[10px] leading-relaxed text-[#5c4a38]">{activeChordPeek.unavailableMessage}</p>
      {/if}
    </div>
  </div>
{/if}

<style>
  .manuscript-card { transition: transform var(--motion-duration-control) var(--motion-ease-settle), border-color var(--motion-duration-micro), box-shadow var(--motion-duration-control); }
  .manuscript-card button { min-height: 44px; }
  .manuscript-card button:focus-visible, .manuscript-card a:focus-visible { outline: 2px solid var(--color-signal); outline-offset: 3px; }
</style>
