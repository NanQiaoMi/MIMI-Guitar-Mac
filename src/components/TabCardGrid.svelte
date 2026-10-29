<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import MotionSegmentedControl from './ui/MotionSegmentedControl.svelte';
  import { scoreAuditionEngine, type AuditionState } from '../lib/scoreAuditionEngine.ts';
  import type { ScoreAuditionPreviewHandle } from '../lib/scoreAuditionTypes.ts';
  import { resolveScoreAuditionSource } from '../lib/player/scoreAuditionResources.ts';
  import { DEFAULT_SCORE_PREVIEW_SECONDS, SCORE_PREVIEW_DURATIONS } from '../lib/player/scorePreviewDuration.ts';
  import { GUITAR_CHORDS, chordSvg } from '../lib/chords.ts';
  import { buildCatalogCategoryHref, buildTabQueryHref, KEY_OPTIONS, STYLE_OPTIONS, TUNING_OPTIONS } from '../lib/tabQuery.ts';
  import { addCatalogFavorite, type CatalogScoreInput } from '../lib/personal/catalog.ts';
  import { readPersonalData, subscribePersonalData } from '../lib/personal/repository.ts';
  import { fadeMotion, registerMotionSurface, surfaceMotion, type MotionTransitionConfig, type MotionTransitionOptions } from '../lib/ui/motion.ts';
  import { getMotionPreferenceSnapshot, subscribeMotionPreference, type MotionMode } from '../lib/ui/motionPreferences.ts';
  import {
    attachChordPreviewListeners,
    chordPreviewAccessibleName,
    createChordPreviewState,
    createChordPreviewTarget as buildChordPreviewTarget,
    positionChordPopover,
    reconcileChordPreviewContext,
    resolveChordPreview,
    updateChordPreviewState,
    type ChordPreviewAction,
    type ChordPopoverPosition,
    type ChordPreviewTarget,
  } from '../lib/ui/chordPreview.ts';

  // --- Types ---
  export interface TabItem {
    id: string;
    title: string;
    artist?: string | null;
    category?: string;
    difficulty?: number;
    sheetForm?: number | string;
    key?: string | null;
    tuning?: string | null;
    heat?: number;
    screenshotUrl?: string | null;
    bpm?: number | null;
    format?: string;
    scoreUrl?: string | null;
    xheUrl?: string | null;
    publishDate?: string | Date | null;
    tags?: string;
    description?: string | null;
  }

  // --- Props (Svelte 5 Runes) ---
  let {
    tabs = [],
    totalCount = 0,
    currentPage = 1,
    pageCount = 1,
    initialCategory = 'all',
    initialDifficulty = 0,
    initialStyle = 0,
    initialSheetForm = 0,
    initialKey = '',
    initialTuning = '',
    initialKeyword = '',
    initialSort = 'heat',
    dataSource = 'catalog',
    initialQuery = '',
    showFilters = true,
    showSearch = true,
    showStats = true,
    staggerDelay = 40,
    emptyMessage = '该分类下暂无曲谱，请尝试调整筛选条件',
    basePath = '/tabs',
  }: {
    tabs?: TabItem[];
    totalCount?: number;
    currentPage?: number;
    pageCount?: number;
    initialCategory?: string;
    initialDifficulty?: number;
    initialStyle?: number;
    initialSheetForm?: number;
    initialKey?: string;
    initialTuning?: string;
    initialKeyword?: string;
    initialSort?: string;
    dataSource?: 'catalog' | 'demo' | 'unavailable';
    initialQuery?: string;
    showFilters?: boolean;
    showSearch?: boolean;
    showStats?: boolean;
    staggerDelay?: number;
    emptyMessage?: string;
    basePath?: string;
  } = $props();

  // --- Reactive States ---
  let selectedCategory = $state<'all' | 'guitar' | 'ukulele'>(
    initialCategory === 'guitar' || initialCategory === 'ukulele' ? initialCategory : 'all'
  );
  let selectedDifficulty = $state<number>(initialDifficulty);
  let selectedStyle = $state<number>(initialStyle);
  let selectedSheetForm = $state<number>(initialSheetForm);
  let selectedKey = $state<string>(initialKey);
  let selectedTuning = $state<string>(initialTuning);
  let searchKeyword = $state<string>(initialKeyword);
  let sortBy = $state<'heat' | 'newest' | 'difficulty'>((initialSort as any) || 'heat');
  
  // 3-Way Layout View Mode: 'gallery' (大卡手稿画廊) | 'compact' (紧凑工坊列表) | 'folio' (典藏书卷折页)
  let viewMode = $state<'gallery' | 'compact' | 'folio'>('gallery');
  let layoutCols = $state<2 | 3>(2);

  // Audio Preview State
  let previewTabId = $state<string | null>(null);
  let auditionState = $state<AuditionState>(scoreAuditionEngine.getState());
  let previewHandle: ScoreAuditionPreviewHandle | null = null;
  let previewError = $state<{ title: string; href: string; message: string } | null>(null);
  let previewDurationSeconds = $state<number>(DEFAULT_SCORE_PREVIEW_SECONDS);
  let playingTabId = $derived(
    auditionState.currentTabId === previewTabId && auditionState.isPlaying ? previewTabId : null
  );
  let loadingTabId = $derived(
    auditionState.currentTabId === previewTabId && auditionState.isLoading ? previewTabId : null
  );
  let auditionGeneration = 0;
  let motionMode = $state<MotionMode>(getMotionPreferenceSnapshot().mode);

  const chordPreviewTooltipId = 'tab-grid-chord-preview-tooltip';
  let chordPreviewState = $state(createChordPreviewState());
  let activeChordPeek = $derived(resolveChordPreview(chordPreviewState));
  let chordPreviewElement = $state<HTMLDivElement | null>(null);
  let chordPreviewPosition = $state<ChordPopoverPosition | null>(null);
  let chordPreviewPositionRevision = 0;

  // Card 3D Tilt & Pointer Tracking
  let cardRotations = $state<Record<string, { rx: number; ry: number; shineX: number; shineY: number }>>({});
  let hoveredCardId = $state<string | null>(null);

  // Quick Action Notification Toast
  let toastMsg = $state<string | null>(null);
  let toastIsError = $state(false);
  let toastTimer: any = null;
  let localFavoriteIds = $state<string[]>([]);
  let favoritesReady = $state(false);
  let favoriteLoadError = $state('');
  let favoriteBusy = $state(false);
  let favoriteReadGeneration = 0;

  function showToast(msg: string, isError = false) {
    toastMsg = msg;
    toastIsError = isError;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toastMsg = null; }, 2200);
  }

  onMount(() => {
    let active = true;
    const refreshFavorites = async () => {
      const generation = ++favoriteReadGeneration;
      try {
        const data = await readPersonalData();
        if (!active || generation !== favoriteReadGeneration) return;
        localFavoriteIds = data.favorites.slice();
        favoriteLoadError = '';
        favoritesReady = true;
      } catch (cause) {
        if (!active || generation !== favoriteReadGeneration) return;
        favoriteLoadError = cause instanceof Error ? cause.message : '本设备收藏暂不可用';
        favoritesReady = false;
      }
    };
    const unsubscribe = subscribePersonalData(() => { void refreshFavorites(); });
    const unsubscribeMotion = subscribeMotionPreference((snapshot) => {
      motionMode = snapshot.mode;
      if (snapshot.mode !== 'full') {
        cardRotations = {};
        hoveredCardId = null;
      }
    });
    const unsubscribeAudition = scoreAuditionEngine.subscribe((snapshot) => {
      auditionState = snapshot;
    });
    void refreshFavorites();
    return () => {
      active = false;
      favoriteReadGeneration++;
      unsubscribe();
      unsubscribeMotion();
      unsubscribeAudition();
      stopAudition();
      clearTimeout(toastTimer);
    };
  });

  // --- Constants & Mappings ---
  const difficultyOptions = [
    { value: 0, label: '全部难度' },
    { value: 1, label: '零基础 (L1)' },
    { value: 2, label: '初级 (L2)' },
    { value: 3, label: '中级 (L3)' },
    { value: 4, label: '高级 (L4)' },
    { value: 5, label: '专业 (L5)' },
  ];

  const formOptions = [
    { value: 0, label: '全部谱型' },
    { value: 1, label: '🎸 弹唱谱' },
    { value: 2, label: '🎼 指弹谱' },
    { value: 3, label: '🎹 和弦谱' },
    { value: 4, label: '📑 六线谱' },
  ];

  const categoryOptions = [
    { value: 'all', label: '全部典藏' },
    { value: 'guitar', label: '吉他谱' },
    { value: 'ukulele', label: '尤克里里' },
  ];
  const viewOptions = [
    { value: 'gallery', label: '画廊' },
    { value: 'compact', label: '列表' },
    { value: 'folio', label: '展卷' },
  ];
  const sortOptions = [
    { value: 'heat', label: '研习热度' },
    { value: 'newest', label: '最新上传' },
    { value: 'difficulty', label: '演奏难度' },
  ];

  const keyOptions = ['', 'C', 'D', 'E', 'F', 'G', 'A', 'B', 'Em', 'Am', 'Dm'];

  function getDiffLabel(diff?: number | null): string {
    const map = [null, '零基础', '初级', '中级', '高级', '专业'];
    return diff ? map[diff] || '初级' : '初级';
  }

  function getDiffBadgeStyle(diff?: number | null): string {
    if (!diff || diff <= 1) return 'text-[#2e7d32] bg-[#2e7d32]/10 border-[#2e7d32]/25';
    if (diff === 2) return 'text-[#00838f] bg-[#00838f]/10 border-[#00838f]/25';
    if (diff === 3) return 'text-[#1565c0] bg-[#1565c0]/10 border-[#1565c0]/25';
    if (diff === 4) return 'text-[#e65100] bg-[#e65100]/10 border-[#e65100]/25';
    return 'text-[#b71c1c] bg-[#b71c1c]/10 border-[#b71c1c]/25';
  }

  function getFormLabel(f?: number | string | null): string {
    const num = Number(f);
    const map: Record<number, string> = { 1: '弹唱谱', 2: '指弹谱', 3: '和弦谱', 4: '六线谱', 7: '六线谱' };
    return map[num] || '六线谱';
  }

  function formatHeat(heat?: number | null): string {
    const h = heat ?? 0;
    if (h >= 10000) return (h / 10000).toFixed(1) + '万';
    return String(h);
  }

  // Key reference diagrams only; these are never used as a song's audio preview.
  const KEY_PROGRESSIONS: Record<string, string[]> = {
    C: ['C', 'Am', 'F', 'G'],
    G: ['G', 'Em7', 'Cadd9', 'D'],
    D: ['D', 'Bm', 'G', 'A'],
    A: ['A', 'F#m', 'D', 'E'],
    E: ['E', 'C#m', 'A', 'B'],
    F: ['F', 'Dm', 'Bb', 'C'],
    B: ['B', 'G#m', 'E', 'F#'],
    Em: ['Em', 'C', 'G', 'D'],
    Am: ['Am', 'F', 'C', 'G'],
    Dm: ['Dm', 'Bb', 'F', 'C'],
  };

  function stopAudition() {
    auditionGeneration += 1;
    previewTabId = null;
    const handle = previewHandle;
    previewHandle = null;
    handle?.cancel();
  }

  function previewUnavailableReason(tab: TabItem): string {
    const source = resolveScoreAuditionSource(tab);
    if (source.ok) return '';
    if (source.reason === 'unsupported-format') return '阅读谱暂不支持声音试听';
    if (source.reason === 'missing-score') return '暂无可播放的原谱文件';
    return '原谱资源信息需要核对，请打开曲谱';
  }

  function previewLabel(tab: TabItem): string {
    if (loadingTabId === tab.id) return `取消加载《${tab.title}》试听`;
    if (playingTabId === tab.id) return `停止《${tab.title}》试听`;
    const reason = previewUnavailableReason(tab);
    return reason ? `《${tab.title}》${reason}` : `试听《${tab.title}》原谱合成片段，最多 ${previewDurationSeconds} 秒`;
  }

  function changePreviewDuration(event: Event) {
    const duration = Number((event.currentTarget as HTMLSelectElement).value);
    if (!SCORE_PREVIEW_DURATIONS.some((option) => option === duration)) return;
    stopAudition();
    previewError = null;
    previewDurationSeconds = duration;
  }

  async function triggerScorePreview(e: MouseEvent, tab: TabItem) {
    e.preventDefault();
    e.stopPropagation();

    if (playingTabId === tab.id || loadingTabId === tab.id) {
      stopAudition();
      return;
    }

    stopAudition();
    previewError = null;
    if (previewUnavailableReason(tab)) return;
    const generation = auditionGeneration;
    previewTabId = tab.id;
    const handle = scoreAuditionEngine.previewTab(tab, previewDurationSeconds);
    previewHandle = handle;
    const result = await handle.promise;
    if (generation !== auditionGeneration || previewHandle !== handle) return;
    if (result.status === 'failed') {
      previewError = {
        title: tab.title,
        href: `/${tab.category === 'ukulele' ? 'ukulele' : 'tabs'}/${tab.id}`,
        message: result.error,
      };
      previewTabId = null;
      previewHandle = null;
    }
  }

  // --- 3D Card Magnetic Tilt Handlers ---
  function handleCardMouseMove(e: MouseEvent, tabId: string) {
    if (
      motionMode !== 'full' ||
      typeof window === 'undefined' ||
      !window.matchMedia('(hover: hover) and (pointer: fine)').matches
    ) return;
    const card = e.currentTarget as HTMLElement;
    if (!card) return;
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const centerX = rect.width / 2;
    const centerY = rect.height / 2;
    const rx = ((y - centerY) / centerY) * -5.5;
    const ry = ((x - centerX) / centerX) * 5.5;
    const shineX = (x / rect.width) * 100;
    const shineY = (y / rect.height) * 100;

    cardRotations[tabId] = { rx, ry, shineX, shineY };
    hoveredCardId = tabId;
  }

  function handleCardMouseLeave(tabId: string) {
    cardRotations[tabId] = { rx: 0, ry: 0, shineX: 50, shineY: 50 };
    if (hoveredCardId === tabId) hoveredCardId = null;
  }

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
    const context = { viewMode, visibleItemsSignature: chordPreviewItemsSignature };
    const reconciledState = reconcileChordPreviewContext(
      chordPreviewState,
      context,
      context,
      (candidate) => candidate.anchor.isConnected !== false,
    );
    if (reconciledState !== chordPreviewState) {
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

  function cardEntryMotion(node: Element, params: { index: number }, transition: MotionTransitionOptions = {}): MotionTransitionConfig {
    const config = surfaceMotion(node, { kind: 'panel' }, transition);
    const delayStep = Math.min(3, Math.max(0, staggerDelay));
    return { ...config, delay: motionMode === 'full' ? Math.min(Math.max(0, params.index) * delayStep, 20) : 0 };
  }

  // Quick Action Handlers
  function copyShareLink(e: MouseEvent, tab: TabItem) {
    e.preventDefault();
    e.stopPropagation();
    const url = `${window.location.origin}/${tab.category === 'ukulele' ? 'ukulele' : 'tabs'}/${tab.id}`;
    navigator.clipboard.writeText(url).then(() => {
      showToast(`已复制《${tab.title}》的链接`);
    });
  }

  async function toggleFavorite(e: MouseEvent, tab: TabItem) {
    e.preventDefault();
    e.stopPropagation();
    if (favoriteBusy) return;
    if (!favoritesReady) {
      showToast(favoriteLoadError || '本设备收藏仍在读取，请稍后重试。', true);
      return;
    }
    const scoreId = `catalog:${tab.id}`;
    const willFavorite = !localFavoriteIds.includes(scoreId);
    if (willFavorite && dataSource !== 'catalog') {
      showToast('当前为演示结果，在线曲库恢复后才能保存真实曲库引用。', true);
      return;
    }
    const input: CatalogScoreInput = {
      id: tab.id,
      title: tab.title,
      artist: tab.artist,
      category: tab.category ?? (selectedCategory === 'ukulele' ? 'ukulele' : 'guitar'),
      format: tab.format,
      scoreUrl: tab.scoreUrl ?? undefined,
    };
    favoriteBusy = true;
    try {
      await addCatalogFavorite(input, willFavorite);
      localFavoriteIds = willFavorite
        ? [...localFavoriteIds, scoreId]
        : localFavoriteIds.filter((id) => id !== scoreId);
      showToast(willFavorite ? `已将《${tab.title}》保存到本设备收藏` : `已从本设备收藏移除《${tab.title}》`);
    } catch (cause) {
      showToast(`收藏未保存：${cause instanceof Error ? cause.message : String(cause)}`, true);
    } finally {
      favoriteBusy = false;
    }
  }

  // --- Derived Filtered & Sorted Tab List ---
  // This is already the server-filtered page. Re-filtering it here would make
  // the page and total disagree, especially on later pages.
  let filteredTabs = $derived<TabItem[]>(tabs);
  let chordPreviewItemsSignature = $derived(filteredTabs
    .map((tab) => `${tab.id}\u0000${tab.key ?? ''}`)
    .join('\u0001'));
  let previousChordPreviewItemsSignature: string | null = null;
  let previousChordPreviewViewMode: typeof viewMode | null = null;

  // A pinned tooltip is anchored inside the gallery branch. Close it after a
  // view switch or visible-item replacement so keyboard-only layout changes
  // cannot leave a floating preview behind after its trigger is unmounted.
  $effect(() => {
    const currentSignature = chordPreviewItemsSignature;
    const currentViewMode = viewMode;
    if (previousChordPreviewItemsSignature === null || previousChordPreviewViewMode === null) {
      previousChordPreviewItemsSignature = currentSignature;
      previousChordPreviewViewMode = currentViewMode;
      return;
    }
    const previousContext = {
      viewMode: previousChordPreviewViewMode,
      visibleItemsSignature: previousChordPreviewItemsSignature,
    };
    const currentContext = {
      viewMode: currentViewMode,
      visibleItemsSignature: currentSignature,
    };
    const changed = previousContext.viewMode !== currentContext.viewMode
      || previousContext.visibleItemsSignature !== currentContext.visibleItemsSignature;
    previousChordPreviewItemsSignature = currentSignature;
    previousChordPreviewViewMode = currentViewMode;
    if (!changed) return;

    const reconciledState = reconcileChordPreviewContext(
      chordPreviewState,
      previousContext,
      currentContext,
      (candidate) => currentViewMode === 'gallery' && candidate.anchor.isConnected !== false,
    );
    if (reconciledState !== chordPreviewState) updateChordPreview({ type: 'dismiss' });
  });

  let activeFilterCount = $derived.by<number>(() => {
    let c = 0;
    if (selectedDifficulty > 0) c++;
    if (selectedStyle > 0) c++;
    if (selectedSheetForm > 0) c++;
    if (selectedKey) c++;
    if (selectedTuning) c++;
    if (searchKeyword.trim()) c++;
    if (sortBy !== 'heat') c++;
    return c;
  });

  function updateQuery(overrides: Record<string, string | number | undefined>) {
    window.location.assign(buildTabQueryHref(window.location.href, overrides));
  }
  function chooseCategory(category: 'all' | 'guitar' | 'ukulele') {
    window.location.assign(buildCatalogCategoryHref(window.location.href, category));
  }
  function setSort(sort: 'heat' | 'newest' | 'difficulty') {
    updateQuery({ sort: sort === 'newest' ? 0 : sort === 'difficulty' ? 2 : 1 });
  }
  function pageHref(page: number) {
    const query = new URLSearchParams(initialQuery);
    query.delete('page');
    query.set('no', String(page));
    return `${basePath}?${query.toString()}`;
  }

  function resetFilters() {
    updateQuery({ difficulty: undefined, style: undefined, key: undefined, tuning: undefined, sheetForm: undefined, sort: undefined, keyword: undefined, searchValue: undefined, field: undefined });
  }

  const seals = ['谱', '音', '琴', '吉', '韵', '和'];
</script>

<!-- Global Chord Peek Floating Popover -->
{#if activeChordPeek}
  <div
    bind:this={chordPreviewElement}
    use:registerMotionSurface
    id={chordPreviewTooltipId}
    role="tooltip"
    class="pointer-events-none fixed z-50 overflow-auto rounded-2xl border border-[#c49a45]/40 bg-[#fffdfa]/95 p-2.5 shadow-[0_12px_32px_rgba(76,59,43,0.18)] backdrop-blur-md"
    style={`left:${chordPreviewPosition?.left ?? 0}px;top:${chordPreviewPosition?.top ?? 0}px;max-height:calc(100dvh - 16px);visibility:${chordPreviewPosition ? 'visible' : 'hidden'}`}
    transition:surfaceMotion={{ kind: 'menu' }}
  >
    <div class="text-center font-display text-xs font-semibold text-[#8c6d46]">
      {activeChordPeek.hasDiagram ? `${activeChordPeek.name} 和弦指法` : `${activeChordPeek.name} 和弦`}
    </div>
    <div class="mt-1 flex h-24 w-24 items-center justify-center overflow-hidden">
      {#if activeChordPeek.svg}
        {@html activeChordPeek.svg}
      {:else}
        <p class="max-w-full px-1 text-center text-[10px] leading-relaxed text-[#5c4a38]">{activeChordPeek.unavailableMessage}</p>
      {/if}
    </div>
    <div
      class={`absolute h-2 w-2 rotate-45 border-[#c49a45]/40 bg-[#fffdfa] ${chordPreviewPosition?.side === 'below' ? 'border-l border-t' : 'border-r border-b'}`}
      style={`left:${chordPreviewPosition?.arrowLeft ?? 0}px;${chordPreviewPosition?.side === 'below' ? 'top:-4px' : 'bottom:-4px'}`}
      aria-hidden="true"
    ></div>
  </div>
{/if}

<!-- Toast Notification -->
{#if toastMsg}
  <div
    use:registerMotionSurface
      role={toastIsError ? 'alert' : 'status'}
    class="fixed bottom-8 left-1/2 z-50 flex -translate-x-1/2 items-center gap-2 rounded-full border border-[#c49a45]/40 bg-[#2d2926]/90 px-4 py-2 text-xs font-medium text-[#fbf9f4] shadow-[0_8px_24px_rgba(0,0,0,0.25)] backdrop-blur-md"
    transition:surfaceMotion={{ kind: 'notice' }}
  >
      <span class={toastIsError ? 'text-red-300' : 'text-amber-400'}>{toastIsError ? '!' : '✨'}</span>
    <span>{toastMsg}</span>
  </div>
{/if}

  {#if favoriteLoadError}
    <p role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
      本设备收藏暂不可用：{favoriteLoadError}。请检查浏览器存储权限后刷新；列表收藏未写入。
    </p>
  {/if}

<div class="space-y-6 select-none">
  <!-- 悬浮毛玻璃工坊控制台 (Frosted Glass Workshop Master Deck) -->
  {#if showFilters}
    <div
      class="relative overflow-hidden rounded-3xl border border-[#e8e2d4] bg-[#fbf9f4]/90 p-4 sm:p-5 shadow-[0_4px_20px_rgba(76,59,43,0.04)] backdrop-blur-md transition-all space-y-4.5"
    >
      <!-- Background Foil Shimmer Watermark -->
      <div class="pointer-events-none absolute -right-8 -top-8 h-40 w-40 rounded-full bg-[radial-gradient(#c49a45_1px,transparent_1px)] [background-size:12px_12px] opacity-25"></div>

      <!-- Row 1: Category Switcher + Live Search + 3-Way Layout Switcher -->
      <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-3 relative z-10">
        <!-- Instrument Segmented Pill Switcher -->
        <MotionSegmentedControl
          value={selectedCategory}
          options={categoryOptions}
          label="曲谱分类"
          onChange={(value) => chooseCategory(value as 'all' | 'guitar' | 'ukulele')}
        />

        <!-- Right Side: In-Grid Search + 3-Way Layout Switcher -->
        <div class="flex items-center gap-3">
          {#if showSearch}
            <div class="relative flex items-center min-w-[200px] sm:min-w-[240px]">
              <svg
                class="pointer-events-none absolute left-3.5 h-3.5 w-3.5 text-[#8c7b68]"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
              >
                <circle cx="11" cy="11" r="8"></circle>
                <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
              </svg>
              <input
                type="text"
                bind:value={searchKeyword}
                aria-label="按曲名、原唱或调式搜索曲谱"
                onkeydown={(event) => { if (event.key === 'Enter') updateQuery({ keyword: searchKeyword.trim() || undefined }); }}
                placeholder="搜索曲目、原唱、调式..."
                class="min-h-11 w-full rounded-full border border-[#e0d6c0] bg-[#fdfaf5] pl-9 pr-11 py-2 text-xs font-serif text-[#2d2926] placeholder:text-[#a89b8a] transition-all focus:border-[#c49a45] focus:bg-[#ffffff] focus:outline-none focus:shadow-[0_0_0_3px_rgba(196,154,69,0.15)]"
              />
              {#if searchKeyword}
                <button
                  type="button"
                  onclick={() => { searchKeyword = ''; updateQuery({ keyword: undefined }); }}
                  class="absolute right-1 inline-flex h-11 w-11 items-center justify-center rounded-full text-[#a89b8a] hover:text-[#2d2926]"
                  aria-label="清除"
                >
                  ✕
                </button>
              {/if}
            </div>
          {/if}

          <!-- 3-Way View Mode Switcher (画廊 / 紧凑列表 / 书卷册页) -->
          <MotionSegmentedControl
            value={viewMode}
            options={viewOptions}
            label="曲谱视图"
            onChange={(value) => viewMode = value as typeof viewMode}
          />
        </div>
      </div>

      <!-- Row 2: Secondary Filter Pills (Difficulty, Sheet Form, Key & Sorters) -->
      <div class="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-[#e8e2d4]/70 text-xs">
        <div class="flex flex-wrap items-center gap-2 sm:gap-3">
          <!-- Difficulty Pills -->
          <div class="flex items-center gap-1.5" role="group" aria-label="按难度筛选">
            <span class="font-serif font-medium text-[#8c7b68]">难度:</span>
            <div class="flex items-center rounded-full border border-[#e0d6c0] bg-[#fdfaf5] p-0.5">
              {#each difficultyOptions as opt}
                <button
                  type="button"
                  onclick={() => updateQuery({ difficulty: opt.value || undefined })}
                  aria-pressed={selectedDifficulty === opt.value}
                  class="min-h-11 min-w-11 rounded-full px-2.5 py-1 text-[11px] font-serif transition-all {selectedDifficulty === opt.value ? 'bg-[#8c6d46] text-[#ffffff] font-semibold shadow-2xs' : 'text-[#705c42] hover:text-[#2d2926]'}"
                >
                  {opt.label.split(' ')[0]}
                </button>
              {/each}
            </div>
          </div>

          <!-- Sheet Form Selector -->
          <div class="flex items-center gap-1.5" role="group" aria-label="按谱型筛选">
            <span class="font-serif font-medium text-[#8c7b68]">谱型:</span>
            <div class="flex items-center rounded-full border border-[#e0d6c0] bg-[#fdfaf5] p-0.5">
              {#each formOptions as f}
                <button
                  type="button"
                  onclick={() => updateQuery({ sheetForm: f.value || undefined })}
                  aria-pressed={selectedSheetForm === f.value}
                  class="min-h-11 min-w-11 rounded-full px-2.5 py-1 text-[11px] font-serif transition-all {selectedSheetForm === f.value ? 'bg-[#8c6d46] text-[#ffffff] font-semibold shadow-2xs' : 'text-[#705c42] hover:text-[#2d2926]'}"
                >
                  {f.label}
                </button>
              {/each}
            </div>
          </div>
        </div>

        <label class="flex items-center gap-1.5 text-[#8c7b68]">
          曲风:
          <select value={selectedStyle} onchange={(event) => updateQuery({ style: Number(event.currentTarget.value) || undefined })} class="min-h-11 rounded-full border border-[#e0d6c0] bg-[#fdfaf5] px-3 py-2 text-[11px] text-[#705c42]">
            {#each STYLE_OPTIONS as option}<option value={option.value}>{option.label}</option>{/each}
          </select>
        </label>
        <label class="flex items-center gap-1.5 text-[#8c7b68]">
          调性:
          <select value={selectedKey} onchange={(event) => updateQuery({ key: event.currentTarget.value || undefined })} class="min-h-11 rounded-full border border-[#e0d6c0] bg-[#fdfaf5] px-3 py-2 text-[11px] text-[#705c42]">
            <option value="">全部</option>
            {#each KEY_OPTIONS.filter((key) => key !== '全部') as key}<option value={key}>{key}</option>{/each}
          </select>
        </label>
        <label class="flex items-center gap-1.5 text-[#8c7b68]">
          调弦:
          <select value={selectedTuning} onchange={(event) => updateQuery({ tuning: event.currentTarget.value || undefined })} class="min-h-11 rounded-full border border-[#e0d6c0] bg-[#fdfaf5] px-3 py-2 text-[11px] text-[#705c42]">
            <option value="">全部</option>
            {#each TUNING_OPTIONS.filter((tuning) => tuning !== '全部') as tuning}<option value={tuning}>{tuning}</option>{/each}
          </select>
        </label>

        <!-- Sort & Columns -->
        <div class="flex items-center gap-2 ml-auto">
          <!-- Sort Options -->
          <MotionSegmentedControl
            value={sortBy}
            options={sortOptions}
            label="曲谱排序"
            onChange={(value) => setSort(value as 'heat' | 'newest' | 'difficulty')}
          />

          {#if activeFilterCount > 0}
            <button
              type="button"
              onclick={resetFilters}
              class="min-h-11 rounded-full border border-[#c84b31]/40 bg-[#c84b31]/10 px-3 py-2 text-[11px] font-serif font-medium text-[#c84b31] hover:bg-[#c84b31]/20 transition-colors"
            >
              重置 ({activeFilterCount})
            </button>
          {/if}
        </div>
      </div>
    </div>
  {/if}

  <!-- Stats & Audio Preview Indicator -->
  {#if showStats || filteredTabs.length > 0}
    <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-1 text-xs font-serif text-[#8c7b68]">
      {#if showStats}
      <span>
        {#if dataSource === 'demo'}
          <span class="mr-2 rounded-full bg-amber-100 px-2 py-1 text-amber-900">演示数据 · 曲库暂不可用</span>
        {:else if dataSource === 'unavailable'}
          <span class="mr-2 rounded-full bg-red-100 px-2 py-1 text-red-800">曲库暂不可用</span>
        {/if}
        共找到 <strong class="text-[#2d2926] font-semibold">{totalCount}</strong> 份曲谱
      </span>
      {/if}

      {#if filteredTabs.length > 0}
        <label class="ml-auto inline-flex min-h-11 items-center gap-2 whitespace-nowrap">
          试听时长
          <select
            aria-label="原谱试听时长"
            value={previewDurationSeconds}
            onchange={changePreviewDuration}
            class="min-h-11 rounded-full border border-[#e0d6c0] bg-[#fdfaf5] px-3 py-2 text-[#705c42] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b26]"
          >
            {#each SCORE_PREVIEW_DURATIONS as duration}
              <option value={duration}>{duration} 秒</option>
            {/each}
          </select>
        </label>
      {/if}

      {#if playingTabId || loadingTabId}
        <span role="status" class="inline-flex flex-wrap items-center gap-1.5 text-[#966b26]" class:animate-pulse={motionMode === 'full'}>
          <span class="inline-flex items-end gap-[2px] h-3">
            <span class="wave-bar !h-3"></span>
            <span class="wave-bar !h-2"></span>
            <span class="wave-bar !h-3.5"></span>
          </span>
          <span>{loadingTabId ? '正在准备原谱与音源，准备时间不计入试听…' : `原谱合成试听 · ${Math.min(previewDurationSeconds, Math.floor(auditionState.currentTime / 1000))} / ${previewDurationSeconds} 秒`}</span>
          {#if previewTabId}
            {@const activeTab = tabs.find((tab) => tab.id === previewTabId)}
            {#if activeTab}
              <a class="inline-flex min-h-11 items-center underline underline-offset-4" href={`/${activeTab.category === 'ukulele' ? 'ukulele' : 'tabs'}/${activeTab.id}`}>打开完整乐谱</a>
            {/if}
          {/if}
          <button type="button" class="inline-flex min-h-11 items-center rounded-full border border-[#e0d6c0] px-3" onclick={stopAudition}>停止试听</button>
        </span>
      {/if}
    </div>
  {/if}

  {#if previewError}
    <div role="alert" class="flex flex-wrap items-center gap-2 rounded-2xl border border-[#c84b31]/25 bg-[#fff6f1] px-4 py-3 text-sm text-[#8c3a29]">
      <span>《{previewError.title}》试听失败：{previewError.message}</span>
      <a href={previewError.href} class="inline-flex min-h-11 items-center underline underline-offset-4">打开曲谱检查资源</a>
      <button type="button" class="ml-auto min-h-11 min-w-11 rounded-full px-3" onclick={() => { previewError = null; }} aria-label="关闭试听错误提示">关闭</button>
    </div>
  {/if}

  <!-- ================= VIEW 1: GALLERY VIEW (大卡手稿画廊) ================= -->
  {#if viewMode === 'gallery' && filteredTabs.length > 0}
    <ul class="grid grid-cols-1 gap-4.5 sm:gap-5 md:grid-cols-2">
      {#each filteredTabs as tab, index (tab.id)}
        {@const cat = tab.category === 'ukulele' ? 'ukulele' : 'tabs'}
        {@const isFavorite = localFavoriteIds.includes(`catalog:${tab.id}`)}
        {@const diff = getDiffLabel(tab.difficulty)}
        {@const diffBadge = getDiffBadgeStyle(tab.difficulty)}
        {@const form = getFormLabel(tab.sheetForm)}
        {@const heatStr = formatHeat(tab.heat)}
        {@const isPlaying = playingTabId === tab.id}
        {@const isLoading = loadingTabId === tab.id}
        {@const previewUnavailable = previewUnavailableReason(tab)}
        {@const rot = cardRotations[tab.id] || { rx: 0, ry: 0, shineX: 50, shineY: 50 }}
        {@const sealChar = seals[(tab.title.charCodeAt(0) || 0) % seals.length]}
        {@const keyName = tab.key || 'G'}
        {@const defaultChords = KEY_PROGRESSIONS[keyName.replace(/调/g, '').trim()] || ['G', 'Em7', 'Cadd9', 'D']}

        <li
          use:registerMotionSurface
          animate:flip={{ duration: motionMode === 'full' ? 180 : 0, easing: cubicOut }}
          in:cardEntryMotion={{ index }}
          out:fadeMotion={{ kind: 'panel' }}
          class="relative perspective-[1000px]"
        >
          <div
            onmousemove={(e) => handleCardMouseMove(e, tab.id)}
            onmouseleave={() => handleCardMouseLeave(tab.id)}
            class="group relative flex flex-col sm:flex-row items-start sm:items-center gap-4 sm:gap-5 p-4 sm:p-4.5 rounded-3xl border border-[#e8e2d4] bg-[#ffffff] shadow-[0_4px_16px_rgba(76,59,43,0.04)] overflow-hidden {motionMode === 'full' ? 'transition-all duration-200 hover:border-[#c49a45]/60 hover:shadow-[0_12px_36px_rgba(196,154,69,0.14)]' : ''}"
            style={motionMode === 'full' ? `transform: rotateX(${rot.rx}deg) rotateY(${rot.ry}deg) translateZ(${hoveredCardId === tab.id ? '6px' : '0px'}); transform-style: preserve-3d;` : undefined}
          >
            <!-- Aceternity UI: Cursor Tracking Ambient Gold Ray & Specular Highlight -->
            <div
              class="pointer-events-none absolute inset-0 rounded-3xl opacity-0 transition-opacity duration-100 group-hover:opacity-100"
              style="background: radial-gradient(400px circle at {rot.shineX}% {rot.shineY}%, rgba(196, 154, 69, 0.08), transparent 70%);"
            ></div>

            <!-- Left Cover Art & Procedural Tab Manuscript Miniature -->
            <div class="relative shrink-0 w-full sm:w-28 sm:h-28 h-40 rounded-2xl overflow-hidden border border-[#e2d8c3] bg-[#f5efe3] shadow-2xs group-hover:border-[#c49a45]/50 transition-colors">
              {#if tab.screenshotUrl}
                <img
                  src={tab.screenshotUrl}
                  alt={tab.title}
                  class="h-full w-full object-cover {motionMode === 'full' ? 'transition-transform duration-200 ease-out group-hover:scale-105' : ''}"
                  loading="lazy"
                  onerror={(e) => {
                    const target = e.currentTarget as HTMLImageElement;
                    target.style.display = 'none';
                    if (target.nextElementSibling) {
                      (target.nextElementSibling as HTMLElement).style.display = 'flex';
                    }
                  }}
                />
                <div class="h-full w-full p-2.5 hidden flex-col justify-between relative bg-[#faf6ee]">
                  <div class="pointer-events-none absolute inset-0 opacity-15 bg-[radial-gradient(#8c7b68_1px,transparent_1px)] [background-size:8px_8px]"></div>
                  
                  <div class="flex items-center justify-between z-10">
                    <span class="text-[9px] font-mono font-bold tracking-widest text-[#8c7b68]">TAB</span>
                    <span class="text-[10px] font-serif font-semibold text-[#a88942] bg-[#ffffff] px-1.5 py-0.2 rounded border border-[#e0d6c0]">
                      {keyName}调
                    </span>
                  </div>

                  <div class="space-y-1 my-auto z-10 opacity-70">
                    <div class="h-[1px] w-full bg-[#8c7b68]/40 flex justify-around text-[7px] font-mono text-[#5c4a38]">
                      <span>0</span><span>2</span><span>3</span>
                    </div>
                    <div class="h-[1px] w-full bg-[#8c7b68]/30 flex justify-around text-[7px] font-mono text-[#5c4a38]">
                      <span>0</span><span>2</span><span>0</span>
                    </div>
                    <div class="h-[1px] w-full bg-[#8c7b68]/40 flex justify-around text-[7px] font-mono text-[#5c4a38]">
                      <span>3</span><span>0</span><span>2</span>
                    </div>
                  </div>

                  <div class="flex items-center justify-between z-10">
                    <span class="text-[8px] font-serif text-[#8c7b68]">{form}</span>
                    <div class="w-4 h-4 rounded-sm border border-[#c84b31]/50 bg-[#c84b31]/10 flex items-center justify-center text-[#c84b31] text-[8px] font-serif font-bold">
                      {sealChar}
                    </div>
                  </div>
                </div>
              {:else}
                <!-- Procedural Manuscript Score Art -->
                <div class="h-full w-full p-2.5 flex flex-col justify-between relative bg-[#faf6ee]">
                  <div class="pointer-events-none absolute inset-0 opacity-15 bg-[radial-gradient(#8c7b68_1px,transparent_1px)] [background-size:8px_8px]"></div>
                  
                  <div class="flex items-center justify-between z-10">
                    <span class="text-[9px] font-mono font-bold tracking-widest text-[#8c7b68]">TAB</span>
                    <span class="text-[10px] font-serif font-semibold text-[#a88942] bg-[#ffffff] px-1.5 py-0.2 rounded border border-[#e0d6c0]">
                      {keyName}调
                    </span>
                  </div>

                  <div class="space-y-1 my-auto z-10 opacity-70">
                    <div class="h-[1px] w-full bg-[#8c7b68]/40 flex justify-around text-[7px] font-mono text-[#5c4a38]">
                      <span>0</span><span>2</span><span>3</span>
                    </div>
                    <div class="h-[1px] w-full bg-[#8c7b68]/30 flex justify-around text-[7px] font-mono text-[#5c4a38]">
                      <span>0</span><span>2</span><span>0</span>
                    </div>
                    <div class="h-[1px] w-full bg-[#8c7b68]/40 flex justify-around text-[7px] font-mono text-[#5c4a38]">
                      <span>3</span><span>0</span><span>2</span>
                    </div>
                  </div>

                  <div class="flex items-center justify-between z-10">
                    <span class="text-[8px] font-serif text-[#8c7b68]">{form}</span>
                    <div class="w-4 h-4 rounded-sm border border-[#c84b31]/50 bg-[#c84b31]/10 flex items-center justify-center text-[#c84b31] text-[8px] font-serif font-bold">
                      {sealChar}
                    </div>
                  </div>
                </div>
              {/if}

              <!-- Short preview of the actual score, including its original rhythm. -->
              <button
                type="button"
                onclick={(e) => triggerScorePreview(e, tab)}
                disabled={Boolean(previewUnavailable)}
                class="absolute bottom-2 right-2 flex h-11 w-11 items-center justify-center rounded-full bg-[#2d2926]/90 text-[#fbf9f4] shadow-md backdrop-blur-sm hover:bg-[#c49a45] disabled:cursor-not-allowed disabled:opacity-50 z-20 {motionMode === 'full' ? 'transition-transform duration-150 hover:scale-105 active:scale-95' : ''}"
                aria-label={previewLabel(tab)}
                title={previewLabel(tab)}
                aria-pressed={isPlaying || isLoading}
              >
                {#if isLoading}
                  <span class="text-xs">✕</span>
                {:else if isPlaying}
                  <span class="text-xs">⏸</span>
                {:else}
                  <span class="text-xs ml-0.5">▶</span>
                {/if}
              </button>

              <!-- Playing Wave Glow Bar on Cover -->
              {#if isPlaying}
                <div class="absolute inset-x-0 bottom-0 h-1 bg-gradient-to-r from-amber-400 via-amber-500 to-amber-300" class:animate-pulse={motionMode === 'full'}></div>
              {/if}
            </div>

            <!-- Right Content Body -->
            <div class="min-w-0 flex-1 w-full relative z-10 flex flex-col justify-between">
              <div>
                <!-- Row: Title & Heat Indicator -->
                <div class="flex items-start justify-between gap-2">
                  <a
                    href={`/${cat}/${tab.id}`}
                    class="inline-flex min-h-11 truncate font-display text-base sm:text-lg font-semibold text-[#2c241b] transition-colors duration-200 hover:text-[#966b26]"
                  >
                    {tab.title}
                  </a>
                  
                  <span class="inline-flex shrink-0 items-center gap-1 rounded-full border border-[#e8e2d4] bg-[#fbf9f4] px-2 py-0.5 text-xs font-mono font-medium text-[#705c42] shadow-3xs">
                    <span class="text-[#c84b31] text-[10px]">🔥</span>
                    {heatStr}
                  </span>
                </div>

                <!-- Artist Name -->
                <p class="mt-0.5 truncate text-xs text-[#8c7b68] font-serif">
                  {tab.artist || '未知歌手'}
                </p>
                {#if previewUnavailable}
                  <p class="mt-1 text-[11px] text-[#8c7b68]">{previewUnavailable} · 可打开曲谱阅读</p>
                {/if}

                <!-- Core Chord Badges with Hover Popover Peek -->
                <div class="mt-2.5 flex items-center gap-1.5">
                  <span class="text-[10px] font-serif text-[#a89b8a]" title="按调性提供的指法参考，实际和弦以原谱为准">调性参考:</span>
                  <div class="flex items-center gap-1">
                    {#each defaultChords.slice(0, 3) as chord}
                      <button
                        type="button"
                        onmouseenter={(e) => handleChordPreview(e, chord, 'hover')}
                        onmouseleave={(e) => handleChordPreviewEnd(e, 'leave')}
                        onfocus={(e) => handleChordPreview(e, chord, 'focus')}
                        onblur={(e) => handleChordPreviewEnd(e, 'blur')}
                        onclick={(e) => handleChordPreview(e, chord, 'activate')}
                        aria-label={chordPreviewAccessibleName(chord, Boolean(GUITAR_CHORDS[chord]))}
                        aria-describedby={chordPreviewTooltipId}
                        class="min-h-[44px] min-w-[44px] rounded-md border border-[#e2d8c3] bg-[#fcfaf6] px-2 py-1 text-[10px] font-mono font-medium text-[#5c4a38] transition-colors hover:border-[#c49a45] hover:bg-[#fffdfa] hover:text-[#966b26]"
                      >
                        {chord}
                      </button>
                    {/each}
                  </div>
                </div>
              </div>

              <!-- Bottom Tags & Quick Action Pill Group -->
              <div class="mt-3 flex items-center justify-between gap-2 pt-2 border-t border-[#f0eae0] text-xs">
                <div class="flex flex-wrap items-center gap-1.5">
                  <!-- Key Tag -->
                  <span class="inline-flex items-center rounded-full border border-[#e2d8c3] bg-[#fbf9f4] px-2 py-0.5 text-[11px] text-[#5c4a38] font-serif">
                    {keyName} 调
                  </span>

                  <!-- Sheet Form -->
                  <span class="inline-flex items-center rounded-full border border-[#e2d8c3] bg-[#fbf9f4] px-2 py-0.5 text-[11px] text-[#5c4a38] font-serif">
                    {form}
                  </span>

                  <!-- Difficulty Level -->
                  <span class={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-serif font-medium ${diffBadge}`}>
                    <span class="h-1.5 w-1.5 rounded-full bg-current"></span>
                    {diff}
                  </span>
                </div>

                <!-- Quick Action Pill Group (Hover Reveal) -->
                <div class="flex items-center gap-1 opacity-100 transition-opacity duration-100 sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
                  <button
                    type="button"
                    onclick={(e) => toggleFavorite(e, tab)}
                    disabled={!favoritesReady || favoriteBusy || (dataSource !== 'catalog' && !isFavorite)}
                    aria-pressed={isFavorite}
                    aria-label={isFavorite ? '从本设备收藏移除' : '收藏到本设备'}
                    class="flex h-11 w-11 items-center justify-center rounded-full border border-[#e0d6c0] bg-[#ffffff] text-[#705c42] shadow-2xs hover:border-[#c49a45] hover:text-[#c84b31] transition-colors disabled:cursor-not-allowed disabled:opacity-50"
                    title={isFavorite ? '从本设备收藏移除' : dataSource !== 'catalog' ? '演示结果不能保存为真实曲库引用' : favoritesReady ? '收藏到本设备' : '本设备收藏不可用'}
                  >
                    {isFavorite ? '♥' : '♡'}
                  </button>
                  <button
                    type="button"
                    onclick={(e) => copyShareLink(e, tab)}
                    class="flex h-11 w-11 items-center justify-center rounded-full border border-[#e0d6c0] bg-[#ffffff] text-[#705c42] shadow-2xs hover:border-[#c49a45] hover:text-[#966b26] transition-colors"
                    title="复制分享链接"
                  >
                    ↗
                  </button>
                  <a
                    href={`/${cat}/${tab.id}`}
                    class="inline-flex min-h-11 items-center gap-1 rounded-full bg-[#2d2926] px-3 py-2 text-[11px] font-serif font-medium text-[#faf8f5] shadow-xs hover:bg-[#966b26] transition-colors"
                  >
                    <span>研习</span>
                    <span>→</span>
                  </a>
                </div>
              </div>
            </div>
          </div>
        </li>
      {/each}
    </ul>

  <!-- ================= VIEW 2: COMPACT TABLE VIEW (紧凑工坊列表) ================= -->
  {:else if viewMode === 'compact' && filteredTabs.length > 0}
    <div class="overflow-hidden rounded-3xl border border-[#e8e2d4] bg-[#ffffff] shadow-[0_4px_16px_rgba(76,59,43,0.04)]">
      <table class="w-full text-left border-collapse font-serif text-xs">
        <thead>
          <tr class="border-b border-[#e8e2d4] bg-[#fbf9f4] text-[#8c7b68] font-medium text-[11px]">
            <th class="py-3 px-4 w-12 text-center">试听</th>
            <th class="py-3 px-4">曲目 / 歌手</th>
            <th class="py-3 px-3">调性</th>
            <th class="py-3 px-3">谱型</th>
            <th class="py-3 px-3">难度</th>
            <th class="py-3 px-3">研习热度</th>
            <th class="py-3 px-4 text-right">操作</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-[#f0eae0]">
          {#each filteredTabs as tab, index (tab.id)}
            {@const cat = tab.category === 'ukulele' ? 'ukulele' : 'tabs'}
            {@const isFavorite = localFavoriteIds.includes(`catalog:${tab.id}`)}
            {@const diff = getDiffLabel(tab.difficulty)}
            {@const diffBadge = getDiffBadgeStyle(tab.difficulty)}
            {@const form = getFormLabel(tab.sheetForm)}
            {@const heatStr = formatHeat(tab.heat)}
            {@const isPlaying = playingTabId === tab.id}
            {@const isLoading = loadingTabId === tab.id}
            {@const previewUnavailable = previewUnavailableReason(tab)}

            <tr
              use:registerMotionSurface
              animate:flip={{ duration: motionMode === 'full' ? 180 : 0, easing: cubicOut }}
              in:cardEntryMotion={{ index }}
              out:fadeMotion={{ kind: 'menu' }}
              class="group hover:bg-[#fcfaf6] transition-colors"
            >
              <!-- Play Button -->
              <td class="py-2.5 px-4 text-center">
                <button
                  type="button"
                  onclick={(e) => triggerScorePreview(e, tab)}
                  disabled={Boolean(previewUnavailable)}
                  class="inline-flex h-11 w-11 items-center justify-center rounded-full border border-[#e2d8c3] bg-[#ffffff] text-[#2d2926] shadow-2xs hover:bg-[#c49a45] hover:text-[#ffffff] disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
                  aria-label={previewLabel(tab)}
                  title={previewLabel(tab)}
                  aria-pressed={isPlaying || isLoading}
                >
                  {#if isLoading}
                    <span class="text-[10px]">✕</span>
                  {:else if isPlaying}
                    <span class="text-[10px]">⏸</span>
                  {:else}
                    <span class="text-[10px] ml-0.5">▶</span>
                  {/if}
                </button>
              </td>

              <!-- Title & Artist -->
              <td class="py-2.5 px-4 min-w-[180px]">
                <a href={`/${cat}/${tab.id}`} class="inline-flex min-h-11 items-center font-display font-semibold text-[#2c241b] hover:text-[#966b26] transition-colors">
                  {tab.title}
                </a>
                <div class="text-[11px] text-[#8c7b68]">{tab.artist || '未知歌手'}</div>
                {#if previewUnavailable}
                  <p class="mt-1 text-[11px] text-[#8c7b68]">{previewUnavailable}</p>
                {/if}
              </td>

              <!-- Key -->
              <td class="py-2.5 px-3">
                <span class="inline-flex items-center rounded-full border border-[#e2d8c3] bg-[#fbf9f4] px-2 py-0.5 text-[11px] text-[#5c4a38]">
                  {tab.key || 'G'} 调
                </span>
              </td>

              <!-- Form -->
              <td class="py-2.5 px-3 text-[#5c4a38]">
                {form}
              </td>

              <!-- Difficulty -->
              <td class="py-2.5 px-3">
                <span class={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium ${diffBadge}`}>
                  <span class="h-1.5 w-1.5 rounded-full bg-current"></span>
                  {diff}
                </span>
              </td>

              <!-- Heat -->
              <td class="py-2.5 px-3 font-mono text-[#705c42]">
                🔥 {heatStr}
              </td>

              <!-- Action -->
              <td class="py-2.5 px-4 text-right space-x-1.5">
                <button
                  type="button"
                  onclick={(e) => toggleFavorite(e, tab)}
                  disabled={!favoritesReady || favoriteBusy || (dataSource !== 'catalog' && !isFavorite)}
                  aria-pressed={isFavorite}
                  aria-label={isFavorite ? '从本设备收藏移除' : '收藏到本设备'}
                  class="inline-flex h-11 w-11 items-center justify-center rounded-full border border-[#e0d6c0] bg-[#ffffff] text-[#705c42] hover:text-[#c84b31] disabled:cursor-not-allowed disabled:opacity-50"
                  title={isFavorite ? '从本设备收藏移除' : dataSource !== 'catalog' ? '演示结果不能保存为真实曲库引用' : favoritesReady ? '收藏到本设备' : '本设备收藏不可用'}
                >
                  {isFavorite ? '♥' : '♡'}
                </button>
                <a
                  href={`/${cat}/${tab.id}`}
                  class="inline-flex min-h-11 items-center rounded-full bg-[#2d2926] px-3 py-2 text-[11px] font-serif font-medium text-[#faf8f5] hover:bg-[#966b26] transition-colors"
                >
                  研习
                </a>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

  <!-- ================= VIEW 3: FOLIO SPREAD VIEW (典藏书卷折页) ================= -->
  {:else if viewMode === 'folio' && filteredTabs.length > 0}
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      {#each filteredTabs as tab, index (tab.id)}
        {@const cat = tab.category === 'ukulele' ? 'ukulele' : 'tabs'}
        {@const diff = getDiffLabel(tab.difficulty)}
        {@const form = getFormLabel(tab.sheetForm)}
        {@const heatStr = formatHeat(tab.heat)}
        {@const isPlaying = playingTabId === tab.id}
        {@const isLoading = loadingTabId === tab.id}
        {@const previewUnavailable = previewUnavailableReason(tab)}

        <div
          use:registerMotionSurface
          animate:flip={{ duration: motionMode === 'full' ? 180 : 0, easing: cubicOut }}
          in:cardEntryMotion={{ index }}
          out:fadeMotion={{ kind: 'panel' }}
          class="relative rounded-3xl border border-[#e0d6c0] bg-[#fbf9f4] p-5 shadow-[0_6px_24px_rgba(76,59,43,0.06)] group overflow-hidden {motionMode === 'full' ? 'transition-[box-shadow,border-color] duration-200 hover:shadow-[0_12px_36px_rgba(196,154,69,0.15)]' : ''}"
        >
          <div class="absolute left-0 inset-y-0 w-1.5 bg-[#d8ccb8] border-r border-[#c49a45]/30"></div>

          <div class="pl-2 space-y-3">
            <div class="flex items-center justify-between text-xs text-[#8c7b68] font-serif">
              <span class="tracking-widest font-mono">FOLIO NO. {tab.id.slice(0, 6).toUpperCase()}</span>
              <span class="text-[#c84b31] font-mono">🔥 {heatStr}</span>
            </div>

            <div>
              <a href={`/${cat}/${tab.id}`} class="flex min-h-11 items-center font-display text-lg font-bold text-[#2c241b] group-hover:text-[#966b26] transition-colors">
                {tab.title}
              </a>
              <p class="text-xs font-serif text-[#8c7b68] mt-0.5">{tab.artist || '未知歌手'} · {tab.key || 'G'} 调 {form}</p>
            </div>

            <div class="h-32 rounded-2xl overflow-hidden border border-[#e2d8c3] bg-[#fdfaf6] relative p-3 flex flex-col justify-between">
              {#if tab.screenshotUrl}
                <img src={tab.screenshotUrl} alt={tab.title} class="absolute inset-0 h-full w-full object-cover opacity-90 {motionMode === 'full' ? 'transition-transform duration-200 group-hover:scale-105' : ''}" />
              {:else}
                <div class="space-y-1.5 opacity-60">
                  <div class="h-[1px] bg-[#8c7b68]/40 flex justify-around text-[8px] font-mono text-[#5c4a38]">
                    <span>0</span><span>2</span><span>3</span><span>2</span>
                  </div>
                  <div class="h-[1px] bg-[#8c7b68]/40 flex justify-around text-[8px] font-mono text-[#5c4a38]">
                    <span>0</span><span>0</span><span>2</span><span>0</span>
                  </div>
                </div>
              {/if}

              <button
                type="button"
                onclick={(e) => triggerScorePreview(e, tab)}
                disabled={Boolean(previewUnavailable)}
                aria-label={previewLabel(tab)}
                title={previewLabel(tab)}
                aria-pressed={isPlaying || isLoading}
                class="absolute bottom-2.5 right-2.5 inline-flex min-h-11 items-center rounded-full bg-[#2d2926]/90 px-3 py-2 text-[11px] font-serif text-[#ffffff] shadow-md backdrop-blur-sm hover:bg-[#c49a45] disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
              >
                {isLoading ? '✕ 取消加载' : isPlaying ? '⏸ 停止' : '▶ 试听原谱'}
              </button>
            </div>

            {#if previewUnavailable}
              <p class="text-[11px] text-[#8c7b68]">{previewUnavailable} · 可打开曲谱阅读</p>
            {/if}

            <div class="flex items-center justify-between pt-2 border-t border-[#e8e2d4] text-xs font-serif">
              <span class="text-[#8c6d46]">难度: {diff}</span>
              <a href={`/${cat}/${tab.id}`} class="flex min-h-11 items-center gap-1 text-[#2d2926] font-semibold hover:text-[#966b26]">
                <span>开启全屏乐谱</span>
                <span>→</span>
              </a>
            </div>
          </div>
        </div>
      {/each}
    </div>

  <!-- ================= EMPTY STATE ================= -->
  {:else}
    <div
      class="rounded-3xl border border-[#e8e2d4] bg-[#ffffff] p-12 text-center text-[#8c7b68] shadow-xs space-y-3"
    >
      <div class="inline-flex h-14 w-14 items-center justify-center rounded-2xl border border-[#e0d6c0] bg-[#fbf9f4] text-3xl">
        🎸
      </div>
      <p class="text-base font-serif font-semibold text-[#2d2926]">{dataSource === 'unavailable' ? '曲库服务当前不可用' : emptyMessage}</p>
      <p class="text-xs font-serif text-[#8c7b68] max-w-sm mx-auto">
        {dataSource === 'unavailable' ? '本次没有取得曲库结果；这不代表曲库为空。请稍后重试。' : '当前条件下暂无对应曲谱，您可以尝试清除筛选或在上方控制台中搜索其他关键词。'}
      </p>
      <div class="pt-2">
        <button
          type="button"
          onclick={resetFilters}
          class="min-h-11 rounded-full bg-[#2d2926] px-5 py-2 text-xs font-serif font-medium text-[#faf8f5] shadow-xs hover:bg-[#966b26] transition-colors"
        >
          🔄 清除全部筛选条件
        </button>
      </div>
    </div>
  {/if}

  <!-- ================= RETRO BOOK PAGE JUMPING PAGINATION (复古书卷翻页分页器) ================= -->
  {#if pageCount > 1}
            <nav aria-label="曲库分页" class="mt-10 flex flex-wrap items-center justify-center gap-2 font-serif text-xs select-none">
      {#if currentPage > 1}
        <a
          href={pageHref(currentPage - 1)}
          class="inline-flex min-h-11 items-center rounded-full border border-[#e0d6c0] bg-[#ffffff] px-4 py-2 text-[#5c4a38] shadow-2xs hover:border-[#c49a45] hover:text-[#966b26] transition-all"
        >
          ← 上一卷
        </a>
      {/if}

      <div class="flex items-center gap-1 rounded-full border border-[#e0d6c0] bg-[#fbf9f4] p-1 shadow-inner">
        {#each Array.from({ length: Math.min(7, pageCount) }, (_, i) => i + 1) as p}
          <a
            href={pageHref(p)}
            aria-current={p === currentPage ? 'page' : undefined}
            class="flex h-11 min-w-11 items-center justify-center rounded-full px-2 text-xs font-medium transition-all {p === currentPage ? 'bg-[#2d2926] text-[#faf8f5] shadow-2xs' : 'text-[#705c42] hover:bg-[#ffffff] hover:text-[#2d2926]'}"
          >
            {p}
          </a>
        {/each}
      </div>

      {#if currentPage < pageCount}
        <a
          href={pageHref(currentPage + 1)}
          class="inline-flex min-h-11 items-center rounded-full border border-[#e0d6c0] bg-[#ffffff] px-4 py-2 text-[#5c4a38] shadow-2xs hover:border-[#c49a45] hover:text-[#966b26] transition-all"
        >
          下一卷 →
        </a>
      {/if}

      <span class="text-[#a89b8a] ml-2 text-[11px]">
        第 {currentPage} / {pageCount} 卷
      </span>
    </nav>
  {/if}
</div>
