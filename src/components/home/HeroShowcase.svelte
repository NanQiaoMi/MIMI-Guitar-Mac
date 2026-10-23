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

  export interface HeroProps {
    totalTabs?: number;
  }

  let { totalTabs = 0 }: HeroProps = $props();

  // Typewriter search placeholder
  const searchPlaceholders = [
    '搜索曲谱、歌手名、或输入和弦（如 G Em7 Cadd9）...',
    '试试搜索：周杰伦《晴天》指弹独奏谱...',
    '试试搜索：筷子兄弟《老男孩》原版吉他谱...',
    '试试搜索：赵雷《我记得》民谣弹唱谱...',
    '试试搜索：古典名作《卡农》专业级总谱...',
    '试试搜索：蔡健雅《Letting Go》原版吉他谱...',
  ];
  let currentPlaceholderIndex = $state(0);
  let displayedPlaceholder = $state(searchPlaceholders[0]);
  let isDeleting = $state(false);
  let typewriterTimer: ReturnType<typeof setTimeout> | null = null;
  let heroElement: HTMLDivElement | null = $state(null);
  let spatialAllowed = $state(false);
  let syncTypewriter = () => {};

  // Search input state
  let searchQuery = $state('');
  let searchFocused = $state(false);

  // Spotlight mouse coordinates
  let spotlightX = $state(50);
  let spotlightY = $state(50);

  // 3D Card tilt coordinates
  let cardRx = $state(0);
  let cardRy = $state(0);
  let cardShineX = $state(50);
  let cardShineY = $state(50);

  // Real score audition state
  let audition = $state<AuditionState>(scoreAuditionEngine.getState());

  // --- Curated Masterpiece Catalog ---
  interface MasterpieceItem {
    id: string;
    title: string;
    artist: string;
    seal: string;
    sealColor: string;
    key: string;
    keyDesc: string;
    difficulty: number;
    levelText: string;
    levelColor: string;
    bpm: number;
    timeSig: string;
    chords: string[];
    scoreUrl: string;
    sheetForm: number;
    // 4 Columns of real guitar 6-line TAB notes (String 1 to 6)
    tabColumns: Array<{
      chordName: string;
      notes: Array<{ string: number; fret: string | number; isRoot?: boolean }>;
    }>;
  }

  const MASTERPIECE_COLLECTION: MasterpieceItem[] = [
    {
      id: '1sdc49P3eKm',
      title: '晴天',
      artist: '周杰伦',
      seal: '晴',
      sealColor: '#c84b31',
      key: 'G',
      keyDesc: 'G 调 · 原版指弹',
      difficulty: 2,
      levelText: 'L2 初级',
      levelColor: '#2e7d32',
      bpm: 80,
      timeSig: '4/4 拍',
      chords: ['G', 'Em7', 'Cadd9', 'D'],
      scoreUrl: '/storage/scores/1sdc49P3eKm.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'G',
          notes: [
            { string: 6, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 3 },
            { string: 1, fret: 3 },
          ],
        },
        {
          chordName: 'Em7',
          notes: [
            { string: 6, fret: 0, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 3 },
            { string: 1, fret: 3 },
          ],
        },
        {
          chordName: 'Cadd9',
          notes: [
            { string: 5, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 3 },
            { string: 1, fret: 3 },
          ],
        },
        {
          chordName: 'D',
          notes: [
            { string: 4, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
      ],
    },
    {
      id: '1sdiivPR3YW',
      title: '老男孩',
      artist: '筷子兄弟',
      seal: '老',
      sealColor: '#a86a3d',
      key: 'C',
      keyDesc: 'C 调 · 原版民谣',
      difficulty: 1,
      levelText: 'L1 入门',
      levelColor: '#1976d2',
      bpm: 80,
      timeSig: '4/4 拍',
      chords: ['C', 'G', 'Am', 'Em'],
      scoreUrl: '/storage/scores/1sdiivPR3YW.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'C',
          notes: [
            { string: 5, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 1 },
            { string: 1, fret: 0 },
          ],
        },
        {
          chordName: 'G',
          notes: [
            { string: 6, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 0 },
            { string: 1, fret: 3 },
          ],
        },
        {
          chordName: 'Am',
          notes: [
            { string: 5, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 1 },
            { string: 1, fret: 0 },
          ],
        },
        {
          chordName: 'Em',
          notes: [
            { string: 6, fret: 0, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 0 },
            { string: 1, fret: 0 },
          ],
        },
      ],
    },
    {
      id: '1sdjKw3nhA0',
      title: '反方向的钟',
      artist: '周杰伦',
      seal: '钟',
      sealColor: '#795548',
      key: 'B',
      keyDesc: 'B 调 · 专业指弹',
      difficulty: 3,
      levelText: 'L3 进阶',
      levelColor: '#e65100',
      bpm: 86,
      timeSig: '4/4 拍',
      chords: ['B', 'G#m', 'E', 'F#'],
      scoreUrl: '/storage/scores/1sdjKw3nhA0.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'B',
          notes: [
            { string: 5, fret: 2, isRoot: true },
            { string: 4, fret: 4 },
            { string: 3, fret: 4 },
            { string: 2, fret: 4 },
          ],
        },
        {
          chordName: 'G#m',
          notes: [
            { string: 6, fret: 4, isRoot: true },
            { string: 4, fret: 6 },
            { string: 3, fret: 4 },
            { string: 2, fret: 4 },
          ],
        },
        {
          chordName: 'E',
          notes: [
            { string: 6, fret: 0, isRoot: true },
            { string: 5, fret: 2 },
            { string: 4, fret: 2 },
            { string: 3, fret: 1 },
          ],
        },
        {
          chordName: 'F#',
          notes: [
            { string: 6, fret: 2, isRoot: true },
            { string: 5, fret: 4 },
            { string: 4, fret: 4 },
            { string: 3, fret: 3 },
          ],
        },
      ],
    },
    {
      id: '1yDFAg9Z3mU',
      title: '后来',
      artist: '刘若英',
      seal: '后',
      sealColor: '#00897b',
      key: 'Eb',
      keyDesc: 'Eb 调 · 经典独奏',
      difficulty: 2,
      levelText: 'L2 初级',
      levelColor: '#2e7d32',
      bpm: 75,
      timeSig: '4/4 拍',
      chords: ['Eb', 'Cm', 'Ab', 'Bb'],
      scoreUrl: '/storage/scores/1yDFAg9Z3mU.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'Eb',
          notes: [
            { string: 5, fret: 6, isRoot: true },
            { string: 4, fret: 5 },
            { string: 3, fret: 3 },
            { string: 2, fret: 4 },
          ],
        },
        {
          chordName: 'Cm',
          notes: [
            { string: 5, fret: 3, isRoot: true },
            { string: 4, fret: 5 },
            { string: 3, fret: 5 },
            { string: 2, fret: 4 },
          ],
        },
        {
          chordName: 'Ab',
          notes: [
            { string: 6, fret: 4, isRoot: true },
            { string: 4, fret: 6 },
            { string: 3, fret: 5 },
            { string: 2, fret: 4 },
          ],
        },
        {
          chordName: 'Bb',
          notes: [
            { string: 5, fret: 1, isRoot: true },
            { string: 4, fret: 3 },
            { string: 3, fret: 3 },
            { string: 2, fret: 3 },
          ],
        },
      ],
    },
    {
      id: '1sdikNKaVJg',
      title: '成都',
      artist: '赵雷',
      seal: '都',
      sealColor: '#5d4037',
      key: 'D',
      keyDesc: 'D 调 · 民谣原版',
      difficulty: 2,
      levelText: 'L2 初级',
      levelColor: '#2e7d32',
      bpm: 76,
      timeSig: '4/4 拍',
      chords: ['D', 'Bm7', 'G', 'A'],
      scoreUrl: '/storage/scores/1sdikNKaVJg.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'D',
          notes: [
            { string: 4, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
        {
          chordName: 'Bm7',
          notes: [
            { string: 5, fret: 2, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
        {
          chordName: 'G',
          notes: [
            { string: 6, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 0 },
            { string: 1, fret: 3 },
          ],
        },
        {
          chordName: 'A',
          notes: [
            { string: 5, fret: 0, isRoot: true },
            { string: 4, fret: 2 },
            { string: 3, fret: 2 },
            { string: 2, fret: 2 },
          ],
        },
      ],
    },
    {
      id: '1sdixfUd4Vc',
      title: '卡农',
      artist: 'Johann Pachelbel',
      seal: '卡',
      sealColor: '#303f9f',
      key: 'D',
      keyDesc: 'D 调 · 古典大作',
      difficulty: 4,
      levelText: 'L4 大师',
      levelColor: '#6a1b9a',
      bpm: 80,
      timeSig: '4/4 拍',
      chords: ['D', 'A', 'Bm', 'F#m'],
      scoreUrl: '/storage/scores/1sdixfUd4Vc.ibe',
      sheetForm: 2,
      tabColumns: [
        {
          chordName: 'D',
          notes: [
            { string: 4, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
        {
          chordName: 'A',
          notes: [
            { string: 5, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 2 },
            { string: 1, fret: 0 },
          ],
        },
        {
          chordName: 'Bm',
          notes: [
            { string: 5, fret: 2, isRoot: true },
            { string: 3, fret: 4 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
        {
          chordName: 'F#m',
          notes: [
            { string: 6, fret: 2, isRoot: true },
            { string: 4, fret: 4 },
            { string: 3, fret: 2 },
            { string: 2, fret: 2 },
          ],
        },
      ],
    },
    {
      id: '20oEfH3di0w',
      title: '稻香',
      artist: '周杰伦',
      seal: '稻',
      sealColor: '#e65100',
      key: 'G',
      keyDesc: 'G 调 · 流行经典',
      difficulty: 1,
      levelText: 'L1 入门',
      levelColor: '#1976d2',
      bpm: 70,
      timeSig: '4/4 拍',
      chords: ['G', 'D', 'Em', 'C'],
      scoreUrl: '/storage/scores/20oEfH3di0w.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'G',
          notes: [
            { string: 6, fret: 3, isRoot: true },
            { string: 4, fret: 0 },
            { string: 3, fret: 0 },
            { string: 2, fret: 3 },
          ],
        },
        {
          chordName: 'D',
          notes: [
            { string: 4, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
        {
          chordName: 'Em',
          notes: [
            { string: 6, fret: 0, isRoot: true },
            { string: 4, fret: 2 },
            { string: 3, fret: 0 },
            { string: 2, fret: 0 },
          ],
        },
        {
          chordName: 'C',
          notes: [
            { string: 5, fret: 3, isRoot: true },
            { string: 4, fret: 2 },
            { string: 3, fret: 0 },
            { string: 2, fret: 1 },
          ],
        },
      ],
    },
    {
      id: '1sdcWsfNEe0',
      title: '斑马斑马',
      artist: '宋冬野',
      seal: '斑',
      sealColor: '#455a64',
      key: 'G',
      keyDesc: 'G 调 · 民谣指弹',
      difficulty: 2,
      levelText: 'L2 初级',
      levelColor: '#2e7d32',
      bpm: 65,
      timeSig: '4/4 拍',
      chords: ['G', 'D', 'Em', 'C'],
      scoreUrl: '/storage/scores/1sdcWsfNEe0.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'G',
          notes: [
            { string: 6, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 0 },
            { string: 1, fret: 3 },
          ],
        },
        {
          chordName: 'D',
          notes: [
            { string: 4, fret: 0, isRoot: true },
            { string: 3, fret: 2 },
            { string: 2, fret: 3 },
            { string: 1, fret: 2 },
          ],
        },
        {
          chordName: 'Em',
          notes: [
            { string: 6, fret: 0, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 0 },
            { string: 1, fret: 0 },
          ],
        },
        {
          chordName: 'C',
          notes: [
            { string: 5, fret: 3, isRoot: true },
            { string: 3, fret: 0 },
            { string: 2, fret: 1 },
            { string: 1, fret: 0 },
          ],
        },
      ],
    },
    {
      id: '1yDFB6u7GnQ',
      title: '达尔文',
      artist: '林俊杰',
      seal: '达',
      sealColor: '#c2185b',
      key: 'Gb',
      keyDesc: 'Gb 调 · 原版编曲',
      difficulty: 2,
      levelText: 'L2 初级',
      levelColor: '#2e7d32',
      bpm: 68,
      timeSig: '4/4 拍',
      chords: ['Gb', 'Db', 'Ebm', 'B'],
      scoreUrl: '/storage/scores/1yDFB6u7GnQ.ibe',
      sheetForm: 4,
      tabColumns: [
        {
          chordName: 'Gb',
          notes: [
            { string: 6, fret: 2, isRoot: true },
            { string: 4, fret: 4 },
            { string: 3, fret: 3 },
            { string: 2, fret: 2 },
          ],
        },
        {
          chordName: 'Db',
          notes: [
            { string: 5, fret: 4, isRoot: true },
            { string: 4, fret: 3 },
            { string: 3, fret: 1 },
            { string: 2, fret: 2 },
          ],
        },
        {
          chordName: 'Ebm',
          notes: [
            { string: 5, fret: 6, isRoot: true },
            { string: 4, fret: 4 },
            { string: 3, fret: 3 },
            { string: 2, fret: 4 },
          ],
        },
        {
          chordName: 'B',
          notes: [
            { string: 5, fret: 2, isRoot: true },
            { string: 4, fret: 4 },
            { string: 3, fret: 4 },
            { string: 2, fret: 4 },
          ],
        },
      ],
    },
  ];

  // Dynamic Selected Tab Index
  let currentMasterpieceIndex = $state(0);

  // Derived current tab object
  let featuredTab = $derived(MASTERPIECE_COLLECTION[currentMasterpieceIndex] || MASTERPIECE_COLLECTION[0]);

  const chordPreviewTooltipId = 'home-hero-chord-preview-tooltip';
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

  function shuffleNextMasterpiece(e?: MouseEvent) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    currentMasterpieceIndex = (currentMasterpieceIndex + 1) % MASTERPIECE_COLLECTION.length;
    updateChordPreview({ type: 'dismiss' });
  }

  onMount(() => {
    // 每次刷新随机选取不同的今日典藏名作
    currentMasterpieceIndex = Math.floor(Math.random() * MASTERPIECE_COLLECTION.length);

    // Typewriter engine
    let charIndex = 0;
    let fullMotion = false;
    let inView = false;
    const pointerQuery = window.matchMedia('(hover: hover) and (pointer: fine)');
    function typeLoop() {
      typewriterTimer = null;
      if (!fullMotion || !inView || document.hidden || searchFocused) return;
      const fullText = searchPlaceholders[currentPlaceholderIndex];
      if (isDeleting) {
        displayedPlaceholder = fullText.substring(0, charIndex - 1);
        charIndex--;
        if (charIndex <= 0) {
          isDeleting = false;
          currentPlaceholderIndex = (currentPlaceholderIndex + 1) % searchPlaceholders.length;
          typewriterTimer = setTimeout(typeLoop, 400);
          return;
        }
        typewriterTimer = setTimeout(typeLoop, 30);
      } else {
        displayedPlaceholder = fullText.substring(0, charIndex + 1);
        charIndex++;
        if (charIndex >= fullText.length) {
          isDeleting = true;
          typewriterTimer = setTimeout(typeLoop, 2600);
          return;
        }
        typewriterTimer = setTimeout(typeLoop, 75);
      }
    }
    const syncActivity = () => {
      spatialAllowed = fullMotion && inView && !document.hidden && pointerQuery.matches;
      if (!spatialAllowed) { handleCardMouseLeave(); spotlightX = 50; spotlightY = 50; }
      if (typewriterTimer !== null) clearTimeout(typewriterTimer);
      typewriterTimer = null;
      if (fullMotion && inView && !document.hidden && !searchFocused) {
        typewriterTimer = setTimeout(typeLoop, 750);
      } else {
        displayedPlaceholder = searchPlaceholders[0];
        charIndex = 0;
        isDeleting = false;
      }
    };
    syncTypewriter = syncActivity;
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => { fullMotion = mode === 'full'; syncActivity(); });
    const observer = new IntersectionObserver((entries) => { inView = entries[0]?.isIntersecting ?? false; syncActivity(); });
    if (heroElement) observer.observe(heroElement);
    document.addEventListener('visibilitychange', syncActivity);
    pointerQuery.addEventListener('change', syncActivity);

    const unsub = scoreAuditionEngine.subscribe((st) => {
      audition = st;
    });

    return () => {
      if (typewriterTimer) clearTimeout(typewriterTimer);
      observer.disconnect();
      unsubscribeMotion();
      document.removeEventListener('visibilitychange', syncActivity);
      pointerQuery.removeEventListener('change', syncActivity);
      syncTypewriter = () => {};
      unsub();
    };
  });

  function handleMouseMove(e: MouseEvent) {
    if (!spatialAllowed) return;
    const target = e.currentTarget as HTMLElement;
    if (!target) return;
    const rect = target.getBoundingClientRect();
    spotlightX = ((e.clientX - rect.left) / rect.width) * 100;
    spotlightY = ((e.clientY - rect.top) / rect.height) * 100;
  }

  function handleCardMouseMove(e: MouseEvent) {
    if (!spatialAllowed) return;
    const card = e.currentTarget as HTMLElement;
    if (!card) return;
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const cx = rect.width / 2;
    const cy = rect.height / 2;
    cardRx = ((y - cy) / cy) * -6;
    cardRy = ((x - cx) / cx) * 6;
    cardShineX = (x / rect.width) * 100;
    cardShineY = (y / rect.height) * 100;
  }

  function handleCardMouseLeave() {
    cardRx = 0;
    cardRy = 0;
    cardShineX = 50;
    cardShineY = 50;
  }

  function handleSearchSubmit(e: SubmitEvent) {
    e.preventDefault();
    if (!searchQuery.trim()) {
      window.location.href = '/tabs';
      return;
    }
    window.location.href = `/tabs?keyword=${encodeURIComponent(searchQuery.trim())}`;
  }

  async function toggleHeroAudition(e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    await scoreAuditionEngine.togglePlayTab(featuredTab);
  }

  // Helper: Get Y coordinate for 6 strings (1 = top line y:12, 6 = bottom line y:62)
  function getStringY(strNum: number) {
    return 12 + (strNum - 1) * 10;
  }
</script>

<div
  bind:this={heroElement}
  use:paperReveal
  onmousemove={handleMouseMove}
  class="relative overflow-hidden rounded-3xl border border-[#e8e2d4] bg-[#ffffff]/90 p-6 sm:p-8 lg:p-12 shadow-[0_12px_48px_rgba(76,59,43,0.06)] backdrop-blur-md"
>
  <!-- Cursor Tracking Ambient Gold Ray Background -->
  <div
    class="pointer-events-none absolute inset-0 opacity-60 transition-opacity duration-500"
    style="background: radial-gradient(600px circle at {spotlightX}% {spotlightY}%, rgba(196, 154, 69, 0.12), transparent 70%);"
  ></div>

  <!-- Procedural Xuan Paper Grain & Traditional Watermark -->
  <div class="pointer-events-none absolute inset-0 opacity-20 bg-[radial-gradient(#8c7b68_1px,transparent_1px)] [background-size:16px_16px]"></div>

  <div class="relative z-10 grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center">
    <!-- Left Hero Typography & Spotlight Search (7 Cols) -->
    <div class="lg:col-span-7 space-y-6">
      <!-- Animated Shimmering Badge Capsule -->
      <div class="inline-flex flex-wrap sm:flex-nowrap items-center gap-2 rounded-full border border-[#c49a45]/45 bg-gradient-to-r from-[#fbf9f4] via-[#f7f2e7] to-[#fbf9f4] px-4 py-1.5 text-xs shadow-[0_2px_12px_rgba(196,154,69,0.08)] backdrop-blur-md transition-all hover:border-[#c49a45]/80 hover:shadow-xs group">
        <!-- Glowing Pulse Dot -->
        <span class="flex h-2 w-2 relative shrink-0">
          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-[#c49a45] opacity-75"></span>
          <span class="relative inline-flex rounded-full h-2 w-2 bg-[#966b26]"></span>
        </span>

        <!-- Engine Tag -->
        <span class="font-mono text-[11px] font-semibold text-[#8f6d2b] tracking-wider uppercase whitespace-nowrap">
          MIMI GUITAR v2.0
        </span>

        <span class="hidden sm:inline-block text-[#d5c7b0] select-none">|</span>

        <!-- Current catalog result count -->
        <div class="flex items-center gap-1.5 text-[12px] text-[#5c4a38] whitespace-nowrap">
          <span>当前曲库</span>
          <span class="rounded bg-[#c84b31]/10 px-1.5 py-0.2 font-mono font-bold text-[#c84b31]">{totalTabs.toLocaleString()}</span>
          <span>首</span>
        </div>

        <span class="hidden sm:inline-block text-[#966b26] transition-transform group-hover:translate-x-0.5 text-xs font-mono">→</span>
      </div>

      <!-- Main Headline -->
      <div class="space-y-2">
        <h1 class="font-display text-3xl sm:text-4xl lg:text-5xl font-bold tracking-tight text-[#2d2926] leading-tight">
          把每一份乐谱，<br class="hidden sm:inline" />
          <span class="relative inline-block text-[#966b26]">
            都当作一页书来对待
            <span class="absolute -bottom-1 left-0 right-0 h-[3px] bg-gradient-to-r from-[#c49a45] via-[#e2c078] to-transparent rounded-full"></span>
          </span>
        </h1>
        <p class="text-sm sm:text-base text-[#705c42] font-serif max-w-xl leading-relaxed pt-1">
          吉他与尤克里里乐谱浏览和个人练习工具，提供六线谱显示、播放控制、本地导入与练习记录。
        </p>
      </div>

      <!-- Spotlight Search Box with Typewriter -->
      <form
        onsubmit={handleSearchSubmit}
        class="relative max-w-xl group/search"
      >
        <div
          class="relative flex items-center rounded-2xl border transition-all duration-300 bg-[#fbf9f4] shadow-xs {searchFocused ? 'border-[#c49a45] ring-4 ring-[#c49a45]/15 shadow-md' : 'border-[#dfd7c5] hover:border-[#c49a45]/60'}"
        >
          <span class="pl-4 text-[#8c7b68] text-base">🔍</span>
          <input
            type="text"
            bind:value={searchQuery}
            onfocus={() => { searchFocused = true; syncTypewriter(); }}
            onblur={() => { searchFocused = false; syncTypewriter(); }}
            placeholder={displayedPlaceholder || '搜索曲谱、歌手名、或输入和弦...'}
            class="w-full bg-transparent px-3 py-3.5 text-sm font-serif text-[#2d2926] placeholder:text-[#a89b8a] focus:outline-hidden"
          />
          <button
            type="submit"
            class="mr-2 flex items-center gap-1.5 rounded-xl bg-[#2d2926] px-4 py-2 text-xs font-serif font-medium text-[#faf8f5] shadow-xs hover:bg-[#966b26] active:scale-95 transition-all cursor-pointer whitespace-nowrap shrink-0"
          >
            <span class="whitespace-nowrap">检索</span>
            <span class="font-mono text-[10px] text-[#c49a45] whitespace-nowrap">⌘K</span>
          </button>
        </div>
      </form>

      <!-- Hot Search Chips -->
      <div class="flex flex-wrap items-center gap-2 text-xs font-serif pt-1">
        <span class="text-[#8c7b68] flex items-center gap-1">
          <span>🔥</span>
          <span>热门搜索:</span>
        </span>
        {#each ['周杰伦', '陶喆', '赵雷', '痛仰', '押尾桑', '岸部真明', '蔡健雅'] as tag}
          <a
            href={`/tabs?q=${encodeURIComponent(tag)}`}
            class="rounded-full border border-[#e0d6c0] bg-[#ffffff]/80 px-2.5 py-0.5 text-[#5c4a38] hover:border-[#c49a45] hover:bg-[#c49a45]/10 hover:text-[#966b26] transition-all"
          >
            {tag}
          </a>
        {/each}
      </div>
    </div>

    <!-- Right 3D Floating Masterpiece Card (5 Cols) -->
    <div class="lg:col-span-5 flex justify-center perspective-[1000px]">
      <div
        onmousemove={handleCardMouseMove}
        onmouseleave={handleCardMouseLeave}
        class="hero-paper-card relative w-full max-w-sm rounded-3xl border border-[#e2d8c3] bg-gradient-to-br from-[#faf7f0] via-[#ffffff] to-[#faf6ee] p-6 shadow-[0_16px_40px_rgba(76,59,43,0.1)] hover:border-[#c49a45] hover:shadow-[0_24px_56px_rgba(196,154,69,0.22)] overflow-hidden"
        style="transform: rotateX({cardRx}deg) rotateY({cardRy}deg); transform-style: preserve-3d;"
      >
        <!-- 3D Specular Light -->
        <div
          class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 hover:opacity-100"
          style="background: radial-gradient(300px circle at {cardShineX}% {cardShineY}%, rgba(255, 255, 255, 0.7), transparent 60%);"
        ></div>

        <!-- Card Header: Seal, Heat & Interactive Shuffle Button -->
        <div class="flex flex-wrap gap-2 items-center justify-between z-10 relative">
          <div class="flex items-center gap-2">
            <span
              class="flex h-6 w-6 items-center justify-center rounded-lg border font-serif text-xs font-bold shadow-3xs transition-all"
              style="border-color: {featuredTab.sealColor}88; background-color: {featuredTab.sealColor}18; color: {featuredTab.sealColor};"
            >
              {featuredTab.seal}
            </span>
            <span class="text-xs font-mono font-bold tracking-widest text-[#8c7b68]">今日典藏焦点</span>
          </div>

          <div class="flex items-center gap-1.5">
            <!-- Shuffle / Rotate Button -->
            <button
              type="button"
              onclick={shuffleNextMasterpiece}
              title="换一首典藏名作"
              class="flex min-h-[44px] items-center gap-1 rounded-full border border-[#e2d8c3] bg-[#fbf9f4] hover:bg-[#c49a45]/15 hover:border-[#c49a45] px-2 py-0.5 text-[11px] font-serif text-[#705c42] hover:text-[#966b26] transition-colors cursor-pointer shadow-3xs"
            >
              <span>🎲</span>
              <span>换一曲</span>
            </button>

            <span class="rounded-full border border-[#e8e2d4] bg-[#ffffff] px-2.5 py-0.5 font-mono text-[11px] text-[#c84b31] shadow-3xs flex items-center gap-1">
              <span>精选展示</span>
            </span>
          </div>
        </div>

        <!-- Title & Artist -->
        {#key featuredTab.id}
        <div class="mt-4 z-10 relative" use:registerMotionSurface in:surfaceMotion={{ kind: 'menu', y: 5, scale: 1 }}>
          <div class="flex flex-wrap gap-2 items-baseline justify-between">
            <h3 class="font-display text-2xl font-bold text-[#2d2926]">
              {featuredTab.title}
            </h3>
            <span class="rounded-full bg-[#c49a45]/15 border border-[#c49a45]/30 px-2.5 py-0.5 font-serif text-xs text-[#8f6d2b] font-medium">
              {featuredTab.keyDesc}
            </span>
          </div>
          <p class="text-xs font-serif text-[#8c7b68] mt-1">
            {featuredTab.artist} · 速度 J={featuredTab.bpm} · {featuredTab.timeSig}
          </p>
        </div>
        {/key}

        <!-- Vector 6-Line Guitar TAB Staff Preview (Dynamic & Matching Song TAB Notes) -->
        <div class="mt-4 rounded-2xl border border-[#e2d8c3] bg-[#faf8f4] p-4 relative overflow-hidden z-10 shadow-inner">
          <div class="flex items-center justify-between text-[11px] font-mono text-[#8c7b68] mb-2.5">
            <span class="font-bold text-[#5c4a38] flex items-center gap-1.5">
              <span>🎼</span>
              <span>ORIGINAL TAB MANUSCRIPT</span>
            </span>
            <span
              class="border px-2 py-0.5 rounded-full text-[10px] font-semibold"
              style="color: {featuredTab.levelColor}; border-color: {featuredTab.levelColor}44; background-color: {featuredTab.levelColor}15;"
            >
              {featuredTab.levelText}
            </span>
          </div>

          <!-- Pristine 6-Line Vector SVG TAB Staff -->
          <div class="relative py-1 select-none">
            <svg viewBox="0 0 300 74" class="w-full h-[74px] overflow-visible">
              <!-- TAB Clef Label on Left -->
              <text x="6" y="23" font-size="9" font-family="monospace" font-weight="bold" fill="#8c7b68">T</text>
              <text x="6" y="41" font-size="9" font-family="monospace" font-weight="bold" fill="#8c7b68">A</text>
              <text x="6" y="59" font-size="9" font-family="monospace" font-weight="bold" fill="#8c7b68">B</text>

              <!-- Left & Right Staff Bar Dividers -->
              <line x1="20" y1="12" x2="20" y2="62" stroke="#d5c7b0" stroke-width="1.5" />
              <line x1="292" y1="12" x2="292" y2="62" stroke="#d5c7b0" stroke-width="1.5" />

              <!-- 6 Parallel TAB Lines (10px Spacing) -->
              <line x1="20" y1="12" x2="292" y2="12" stroke="#e0d6c0" stroke-width="1" />
              <line x1="20" y1="22" x2="292" y2="22" stroke="#e0d6c0" stroke-width="1" />
              <line x1="20" y1="32" x2="292" y2="32" stroke="#e0d6c0" stroke-width="1" />
              <line x1="20" y1="42" x2="292" y2="42" stroke="#e0d6c0" stroke-width="1" />
              <line x1="20" y1="52" x2="292" y2="52" stroke="#e0d6c0" stroke-width="1" />
              <line x1="20" y1="62" x2="292" y2="62" stroke="#e0d6c0" stroke-width="1" />

              <!-- Dynamic Real Note Columns (x = 60, 125, 190, 255) -->
              {#each featuredTab.tabColumns as col, colIdx}
                {@const colX = 60 + colIdx * 65}
                {#each col.notes as n}
                  {@const lineY = getStringY(n.string)}
                  <!-- Fret note background cutout -->
                  <rect x={colX - 7} y={lineY - 6} width="14" height="12" fill="#faf8f4" />
                  <!-- Fret number text -->
                  <text
                    x={colX}
                    y={lineY + 4}
                    text-anchor="middle"
                    font-size="11"
                    font-family="monospace"
                    font-weight="bold"
                    fill={n.isRoot ? '#c84b31' : '#2d2926'}
                  >
                    {n.fret}
                  </text>
                {/each}
              {/each}

              <!-- Dynamic Playhead Needle when playing -->
              {#if audition.isPlaying && audition.currentTabId === featuredTab.id}
                <line
                  x1={35 + (audition.progress * 245)}
                  y1="4"
                  x2={35 + (audition.progress * 245)}
                  y2="70"
                  stroke="#c84b31"
                  stroke-width="2"
                  stroke-linecap="round"
                  opacity="0.9"
                />
              {/if}
            </svg>
          </div>

          <!-- Luxury Play / Audition Button -->
          <button
            type="button"
            onclick={toggleHeroAudition}
            class="mt-3.5 min-h-[44px] w-full flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-[#2d2926] via-[#3d3833] to-[#2d2926] hover:from-[#c49a45] hover:to-[#dfb55a] hover:text-[#2d2926] py-2.5 px-4 text-xs font-serif font-medium text-[#faf8f5] shadow-md active:scale-98 transition-all cursor-pointer outline-none focus:outline-hidden ring-0 border border-[#5c4a38]/40"
          >
            {#if audition.isLoading && audition.currentTabId === featuredTab.id}
              <div class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-white border-t-transparent"></div>
              <span>加载曲谱…</span>
            {:else if audition.isPlaying && audition.currentTabId === featuredTab.id}
              <span class="flex items-center gap-1.5">
                <span class="flex items-end gap-0.5 h-3">
                  <span class="w-0.5 h-full bg-current animate-bounce"></span>
                  <span class="w-0.5 h-2/3 bg-current animate-bounce delay-75"></span>
                  <span class="w-0.5 h-full bg-current animate-bounce delay-150"></span>
                </span>
                <span>⏸ 暂停播放</span>
              </span>
            {:else}
              <span class="flex items-center gap-1.5">
                <span>▶</span>
                <span>播放曲谱</span>
              </span>
            {/if}
          </button>
          {#if audition.currentTabId === featuredTab.id && audition.error}
            <div role="alert" class="mt-2 flex flex-wrap items-center justify-center gap-x-2 gap-y-1 text-xs text-[#9b3328]">
              <span>曲谱播放失败：{audition.error}</span>
              <a class="font-semibold underline underline-offset-2" href={'/tabs/' + featuredTab.id}>打开《{featuredTab.title}》曲谱</a>
            </div>
          {/if}
        </div>

        <!-- Core Chords Badges -->
        <div class="mt-4 flex flex-wrap items-center justify-between gap-x-3 gap-y-2 text-xs font-serif z-10 relative">
          <div class="flex min-w-0 flex-1 flex-wrap items-center gap-x-1.5 gap-y-1">
            <span class="shrink-0 text-[11px] text-[#8c7b68]">核心和弦:</span>
            {#each featuredTab.chords as chord}
              <button
                type="button"
                onmouseenter={(e) => handleChordPreview(e, chord, 'hover')}
                onmouseleave={(e) => handleChordPreviewEnd(e, 'leave')}
                onfocus={(e) => handleChordPreview(e, chord, 'focus')}
                onblur={(e) => handleChordPreviewEnd(e, 'blur')}
                onclick={(e) => handleChordPreview(e, chord, 'activate')}
                aria-label={chordPreviewAccessibleName(chord, Boolean(GUITAR_CHORDS[chord]))}
                aria-describedby={chordPreviewTooltipId}
                class="min-h-[44px] min-w-[44px] rounded-lg border border-[#dfd7c5] bg-[#ffffff] px-2 py-0.5 text-xs font-mono font-semibold text-[#5c4a38] hover:border-[#c49a45] hover:text-[#966b26] transition-colors cursor-pointer shadow-3xs"
              >
                {chord}
              </button>
            {/each}
          </div>
          <a
            href={`/tabs/${featuredTab.id}`}
            class="inline-flex basis-full shrink-0 items-center justify-end gap-0.5 text-xs font-semibold text-[#966b26] hover:underline sm:basis-auto"
          >
            <span>研习</span>
            <span>→</span>
          </a>
        </div>
      </div>
    </div>
  </div>

</div>

<!-- Chord Peek Floating Tooltip -->
{#if activeChordPeek}
  <div
    bind:this={chordPreviewElement}
    use:registerMotionSurface
    id={chordPreviewTooltipId}
    role="tooltip"
    class="fixed z-50 pointer-events-none overflow-auto pb-2"
    style={`left:${chordPreviewPosition?.left ?? 0}px;top:${chordPreviewPosition?.top ?? 0}px;max-height:calc(100dvh - 16px);visibility:${chordPreviewPosition ? 'visible' : 'hidden'}`}
    transition:surfaceMotion={{ kind: 'menu' }}
  >
    <div class="bg-[#2d2926] text-white p-2.5 rounded-xl shadow-xl border border-[#4a4035] flex flex-col items-center">
      <div class="font-mono text-xs font-bold text-[#e2c078] mb-1">
        {activeChordPeek.hasDiagram ? `${activeChordPeek.name} 和弦指法图` : `${activeChordPeek.name} 和弦`}
      </div>
      <div class="w-24 h-24 bg-white/95 rounded-lg p-1 flex items-center justify-center">
        {#if activeChordPeek.svg}
          {@html activeChordPeek.svg}
        {:else}
          <p class="max-w-full px-1 text-center text-[10px] leading-relaxed text-[#5c4a38]">{activeChordPeek.unavailableMessage}</p>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .hero-paper-card { transition: transform var(--motion-duration-control) var(--motion-ease-settle), border-color var(--motion-duration-micro), box-shadow var(--motion-duration-control); }
  .hero-paper-card button { min-height: 44px; }
  .hero-paper-card button:focus-visible, .hero-paper-card a:focus-visible { outline: 2px solid var(--color-signal); outline-offset: 3px; }
</style>
