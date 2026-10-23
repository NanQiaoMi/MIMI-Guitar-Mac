<script lang="ts">
  import { tick } from 'svelte';
  import { CatalogSearchClient, type CatalogSearchSource } from '../lib/catalogSearch.ts';
  import { DEMO_TABS } from '../lib/demoData.ts';
  import MotionDialog from './ui/MotionDialog.svelte';
  import MotionSegmentedControl from './ui/MotionSegmentedControl.svelte';

  // --- Props ---
  let {
    defaultOpen = false,
  }: {
    defaultOpen?: boolean;
  } = $props();

  // --- Svelte 5 Runes State ---
  let isOpen = $state(defaultOpen);
  let query = $state('');
  let activeCategory = $state<'all' | 'guitar' | 'ukulele'>('all');
  let activeIndex = $state(0);
  let isLoading = $state(false);
  let searchResults = $state<any[]>([]);
  let searchSource = $state<CatalogSearchSource | ''>('');
  let searchError = $state('');
  let recentSearches = $state<string[]>([]);
  let inputElement = $state<HTMLInputElement | null>(null);
  let listContainerElement = $state<HTMLDivElement | null>(null);
  let focusRequest = 0;
  const catalogSearch = new CatalogSearchClient();

  // Quick Action Shortcuts (as specified in requirements)
  const quickActions = [
    {
      id: 'qa-intro',
      title: '📖 纸质书卷开卷 (Living Paper Folio)',
      subtitle: '重新播放温润棉纸书卷与墨韵展开开场仪式',
      href: '#intro',
      category: 'action',
      badge: 'FOLIO',
    },
    {
      id: 'qa-hot',
      title: '🔥 热门曲谱',
      subtitle: '浏览全站热度最高的吉他与尤克里里精选谱',
      href: '/tabs?sort=1',
      category: 'action',
      badge: '曲库',
    },
    {
      id: 'qa-fingerstyle',
      title: '🎸 吉他指弹谱',
      subtitle: '独奏原声与指弹曲谱专区 (独奏/双吉他)',
      href: '/tabs?sheetForm=2',
      category: 'action',
      badge: 'SOLO',
    },
    {
      id: 'qa-ukulele',
      title: '🌴 尤克里里谱',
      subtitle: '4 弦轻快乐谱、弹唱与简易和弦谱',
      href: '/ukulele',
      category: 'action',
      badge: 'UKU',
    },
    {
      id: 'qa-showcase',
      title: '✨ 交互体验预览',
      subtitle: '体验暖纸主题下的菜单、页签与弹层交互',
      href: '/motion',
      category: 'action',
      badge: 'UI LAB',
    },
  ];

  // Navigation Links
  const navLinks = [
    { id: 'nav-home', title: '🏠 平台首页', subtitle: '回到 MIMI Guitar 主页', href: '/' },
    { id: 'nav-tabs', title: '🎸 全部吉他谱', subtitle: '浏览曲库与六线谱', href: '/tabs' },
    { id: 'nav-article', title: '📝 专栏文章', subtitle: '演奏技巧与乐理教学', href: '/article' },
    { id: 'nav-upload', title: '🚀 乐谱创作上传', subtitle: '上传 Guitar Pro 或 MusicXML', href: '/upload' },
    { id: 'nav-favs', title: '⭐ 我的收藏夹', subtitle: '查看本设备收藏的曲谱', href: '/account/0' },
  ];

  // Empty-query examples use real demo identifiers; they are not live rankings.
  const defaultPopularTabs = DEMO_TABS.slice(0, 4);

  // Form label mapping
  function getFormLabel(form: number | string | undefined): string {
    const map: Record<string, string> = { '1': '弹唱谱', '2': '指弹谱', '3': '和弦谱', '4': '六线谱' };
    return map[String(form)] ?? '曲谱';
  }

  // Difficulty badge label
  function getDiffLabel(diff: number | undefined): string {
    const map = ['', '零基础', '初级', '中级', '高级', '专业'];
    return diff ? map[diff] || '' : '';
  }

  // Difficulty badge styling
  function getDiffColor(diff: number | undefined): string {
    if (!diff) return 'text-mid-gray bg-surface-alt border-hairline';
    if (diff === 1) return 'text-emerald-600 bg-emerald-500/10 border-emerald-500/20';
    if (diff === 2) return 'text-cyan-600 bg-cyan-500/10 border-cyan-500/20';
    if (diff === 3) return 'text-blue-600 bg-blue-500/10 border-blue-500/20';
    if (diff === 4) return 'text-amber-600 bg-amber-500/10 border-amber-500/20';
    return 'text-red-600 bg-red-500/10 border-red-500/20';
  }

  // Load / Save Recents from localStorage
  function loadRecentSearches() {
    try {
      const stored = localStorage.getItem('mimi_recent_searches');
      if (stored) {
        recentSearches = JSON.parse(stored).slice(0, 6);
      }
    } catch {
      recentSearches = [];
    }
  }

  function saveRecentSearch(term: string) {
    const t = term.trim();
    if (!t) return;
    const next = [t, ...recentSearches.filter((s) => s !== t)].slice(0, 6);
    recentSearches = next;
    try {
      localStorage.setItem('mimi_recent_searches', JSON.stringify(next));
    } catch {
      // ignore
    }
  }

  function removeRecentSearch(term: string) {
    const next = recentSearches.filter((s) => s !== term);
    recentSearches = next;
    try {
      localStorage.setItem('mimi_recent_searches', JSON.stringify(next));
    } catch {
      // ignore
    }
  }

  function clearAllRecents() {
    recentSearches = [];
    try {
      localStorage.removeItem('mimi_recent_searches');
    } catch {
      // ignore
    }
  }

  function useRecentSearch(term: string) {
    query = term;
    activeIndex = 0;
    inputElement?.focus();
  }

  // --- Search Fetch with Debounce ---
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  async function performSearch(searchTerm: string, category: 'all' | 'guitar' | 'ukulele') {
    const q = searchTerm.trim();
    if (!q) {
      searchResults = [];
      searchSource = '';
      searchError = '';
      isLoading = false;
      return;
    }

    isLoading = true;
    const result = await catalogSearch.search(q, category, 12);
    if (!result) return;
    if (query.trim() !== q || activeCategory !== category) return;
    searchResults = result.tabs;
    searchSource = result.source;
    searchError = result.error ?? '';
    if (searchError) searchResults = [];
    if (query.trim() === q && activeCategory === category) {
      isLoading = false;
      activeIndex = 0;
    }
  }

  function retrySearch() {
    if (!query.trim()) return;
    searchError = '';
    searchSource = '';
    isLoading = true;
    void performSearch(query, activeCategory);
  }

  // Reactive search trigger on query or category change
  $effect(() => {
    const currentQuery = query;
    const currentCat = activeCategory;

    if (debounceTimer) clearTimeout(debounceTimer);
    catalogSearch.cancel();
    searchResults = [];
    searchSource = '';
    searchError = '';
    activeIndex = 0;

    if (currentQuery.trim()) {
      isLoading = true;
      debounceTimer = setTimeout(() => {
        void performSearch(currentQuery, currentCat);
      }, 160);
    } else {
      isLoading = false;
    }

    return () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      catalogSearch.cancel();
    };
  });

  // --- Flattened Selectable Items for Keyboard Navigation ---
  type SelectableItem = {
    id: string;
    type: 'action' | 'tab' | 'nav' | 'popular';
    title: string;
    subtitle?: string;
    href: string;
    badge?: string;
    key?: string;
    difficulty?: number;
    sheetForm?: number | string;
    heat?: number;
  };

  let selectableItems = $derived.by<SelectableItem[]>(() => {
    const items: SelectableItem[] = [];

    // If there is an active search query
    if (query.trim()) {
      // 1. Direct Search Result Tabs
      for (const tab of searchResults) {
        const cat = tab.category === 'ukulele' ? 'ukulele' : 'tabs';
        items.push({
          id: `tab-${tab.id}`,
          type: 'tab',
          title: tab.title,
          subtitle: tab.artist || '未知歌手',
          href: `/${cat}/${tab.id}`,
          badge: tab.category === 'ukulele' ? '尤克里里' : '吉他谱',
          key: tab.key,
          difficulty: tab.difficulty,
          sheetForm: tab.sheetForm,
          heat: tab.heat,
        });
      }

      // 2. Matching Quick Actions
      const qLower = query.toLowerCase();
      for (const qa of quickActions) {
        if (qa.title.toLowerCase().includes(qLower) || qa.subtitle.toLowerCase().includes(qLower)) {
          items.push({
            id: qa.id,
            type: 'action',
            title: qa.title,
            subtitle: qa.subtitle,
            href: qa.href,
            badge: qa.badge,
          });
        }
      }

      // 3. Fallback "Search all for query" action if results exist or not
      items.push({
        id: 'qa-search-all',
        type: 'action',
        title: `🔍 在全站检索 "${query.trim()}"`,
        subtitle: `跳转至完整曲谱搜索结果页查看所有相关谱子`,
        href: `/searchResults?searchValue=${encodeURIComponent(query.trim())}`,
        badge: 'SEARCH',
      });
    } else {
      // When query is empty:
      // 1. Quick Actions (always top)
      for (const qa of quickActions) {
        items.push({
          id: qa.id,
          type: 'action',
          title: qa.title,
          subtitle: qa.subtitle,
          href: qa.href,
          badge: qa.badge,
        });
      }

      // 2. Popular Recommendations
      for (const tab of defaultPopularTabs) {
        const cat = tab.category === 'ukulele' ? 'ukulele' : 'tabs';
        items.push({
          id: `pop-${tab.id}`,
          type: 'popular',
          title: tab.title,
          subtitle: tab.artist,
          href: `/${cat}/${tab.id}`,
          badge: tab.category === 'ukulele' ? '演示 · 尤克里里' : '演示 · 吉他',
          key: tab.key,
          difficulty: tab.difficulty,
          sheetForm: tab.sheetForm,
          heat: tab.heat,
        });
      }

      // 3. Quick Navigation Links
      for (const nav of navLinks) {
        items.push({
          id: nav.id,
          type: 'nav',
          title: nav.title,
          subtitle: nav.subtitle,
          href: nav.href,
          badge: '页面',
        });
      }
    }

    return items;
  });

  // Clamp active index whenever selectableItems length changes
  $effect(() => {
    if (activeIndex >= selectableItems.length) {
      activeIndex = Math.max(0, selectableItems.length - 1);
    }
  });

  // Scroll active item into view
  $effect(() => {
    if (isOpen && listContainerElement) {
      const activeEl = listContainerElement.querySelector(`[data-index="${activeIndex}"]`);
      if (activeEl) {
        activeEl.scrollIntoView({ block: 'nearest', behavior: 'auto' });
      }
    }
  });

  // Open & Close Handlers
  export function openPalette() {
    isOpen = true;
    activeIndex = 0;
    loadRecentSearches();
    const request = ++focusRequest;
    tick().then(() => {
      if (!isOpen || request !== focusRequest) return;
      inputElement?.focus();
      inputElement?.select();
    });
  }

  export function closePalette() {
    focusRequest += 1;
    isOpen = false;
    catalogSearch.cancel();
    query = '';
  }

  export function togglePalette() {
    if (isOpen) {
      closePalette();
    } else {
      openPalette();
    }
  }

  function handleSelect(item: SelectableItem) {
    if (item.id === 'qa-intro' || item.href === '#intro') {
      closePalette();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new CustomEvent('mimi:play-intro'));
      }
      return;
    }

    if (query.trim()) {
      saveRecentSearch(query.trim());
    }

    closePalette();
    window.location.href = item.href;
  }

  // Keep list navigation on the input only; native dialog owns Tab and Escape.
  function handleKeyDown(e: KeyboardEvent) {
    if (!isOpen) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (selectableItems.length > 0) {
        activeIndex = (activeIndex + 1) % selectableItems.length;
      }
      return;
    }

    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (selectableItems.length > 0) {
        activeIndex = (activeIndex - 1 + selectableItems.length) % selectableItems.length;
      }
      return;
    }

    if (e.key === 'Enter') {
      e.preventDefault();
      const current = selectableItems[activeIndex];
      if (current) {
        handleSelect(current);
      }
      return;
    }

  }

  function handleCategoryChange(value: string) {
    if (value === 'all' || value === 'guitar' || value === 'ukulele') activeCategory = value;
  }

  // Global window keyboard listener for ⌘K / Ctrl+K / '/'
  function handleGlobalKeyDown(e: KeyboardEvent) {
    // ⌘K or Ctrl+K toggle
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      togglePalette();
      return;
    }

    // '/' to open search when not typing in an input
    if (e.key === '/' && !isOpen) {
      const activeTag = document.activeElement?.tagName?.toLowerCase();
      const isEditable = (document.activeElement as HTMLElement)?.isContentEditable;
      if (activeTag !== 'input' && activeTag !== 'textarea' && !isEditable) {
        e.preventDefault();
        openPalette();
        return;
      }
    }
  }

  // Setup client-side event listeners and initial load
  $effect(() => {
    loadRecentSearches();

    window.addEventListener('keydown', handleGlobalKeyDown);

    const handleCustomOpen = () => openPalette();
    const handleCustomToggle = () => togglePalette();
    window.addEventListener('open-command-palette', handleCustomOpen);
    window.addEventListener('toggle-command-palette', handleCustomToggle);

    return () => {
      window.removeEventListener('keydown', handleGlobalKeyDown);
      window.removeEventListener('open-command-palette', handleCustomOpen);
      window.removeEventListener('toggle-command-palette', handleCustomToggle);
    };
  });
</script>

<!-- Native modal owns focus trapping, Escape, scroll lock and reversible close lifecycle. -->
<MotionDialog
  open={isOpen}
  labelledBy="command-palette-title"
  align="top"
  closeOnBackdrop={true}
  fallbackFocusSelector="#nav-search-trigger"
  onCloseRequest={closePalette}
  backdropClass="items-start px-3 pt-[8vh] pb-3 sm:px-6 sm:pt-[12vh] sm:pb-6 md:px-10 bg-black/35 backdrop-blur-[12px]"
  panelClass="relative flex w-full max-w-2xl max-h-[82dvh] flex-col overflow-hidden rounded-3xl border hairline bg-paper/95 shadow-2xl backdrop-blur-2xl select-none"
>
      <h2 id="command-palette-title" class="sr-only">命令面板与曲谱快速搜索</h2>
      <!-- Top Search Header & 18px Search Pill Container -->
      <div class="p-3.5 sm:p-4 border-b hairline bg-surface-alt/50">
        <div
          class="relative flex items-center rounded-pill border hairline bg-paper px-3.5 py-2 shadow-xs transition-all focus-within:border-signal focus-within:ring-2 focus-within:ring-signal/15"
        >
          <!-- Search Icon / Loading Spinner -->
          {#if isLoading}
            <svg class="h-4 w-4 shrink-0 text-signal animate-spin mr-2" viewBox="0 0 24 24" fill="none">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"></path>
            </svg>
          {:else}
            <svg
              class="h-4 w-4 shrink-0 text-mid-gray mr-2"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <circle cx="11" cy="11" r="8"></circle>
              <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
            </svg>
          {/if}

          <!-- Search Input: 18px radius aesthetic -->
          <input
            bind:this={inputElement}
            data-dialog-initial-focus
            type="text"
            bind:value={query}
            placeholder="搜索曲谱、歌手、吉他指弹、或输入指令..."
            class="min-h-[44px] w-full bg-transparent text-sm text-ink outline-none placeholder:text-mid-gray"
            aria-label="曲谱搜索输入框"
            role="combobox"
            aria-autocomplete="list"
            aria-haspopup="listbox"
            aria-expanded={isOpen}
            aria-controls={selectableItems.length ? 'command-palette-results' : undefined}
            aria-activedescendant={selectableItems.length ? `command-option-${activeIndex}` : undefined}
            onkeydown={handleKeyDown}
          />

          <!-- Clear Query Button -->
          {#if query}
            <button
              type="button"
              onclick={() => {
                query = '';
                inputElement?.focus();
              }}
              class="mr-1 flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-full bg-surface-alt text-mid-gray transition-colors hover:bg-canvas hover:text-ink"
              aria-label="清空搜索内容"
            >
              <svg class="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                <line x1="18" y1="6" x2="6" y2="18"></line>
                <line x1="6" y1="6" x2="18" y2="18"></line>
              </svg>
            </button>
          {/if}

          <button
            type="button"
            onclick={closePalette}
            class="ml-1 flex min-h-[44px] min-w-[44px] shrink-0 items-center justify-center rounded-full border hairline bg-surface-alt text-mid-gray transition-colors hover:bg-canvas hover:text-ink"
            aria-label="关闭命令面板"
            title="关闭命令面板（Esc）"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
          </button>
        </div>

        <div class="mt-2.5 flex flex-wrap items-center justify-between gap-2 px-1">
          <MotionSegmentedControl
            id="command-palette-categories"
            value={activeCategory}
            options={[
              { value: 'all', label: '全部类型' },
              { value: 'guitar', label: '🎸 吉他谱' },
              { value: 'ukulele', label: '🌴 尤克里里' },
            ]}
            onChange={handleCategoryChange}
            label="曲谱类别"
          />

          {#if query.trim() && searchResults.length > 0}
            <span class="text-[11px] font-mono text-mid-gray">
              {searchSource === 'demo' ? '演示结果' : '找到'} <strong class="text-ink font-semibold">{searchResults.length}</strong> 份
            </span>
          {/if}
        </div>
      </div>

      <!-- Result List Body (Scrollable, Keyboard Navigateable) -->
      <div
        bind:this={listContainerElement}
        class="min-h-0 flex-1 space-y-1 divide-y divide-transparent overflow-y-auto p-2 focus:outline-none sm:p-3"
        style="scroll-behavior: auto"
        tabindex="-1"
      >
        {#if !query.trim() && recentSearches.length > 0}
          <div class="space-y-1 border-b hairline px-1 py-1">
            <div class="flex items-center justify-between gap-2">
              <span class="text-[11px] font-semibold uppercase tracking-wider text-mid-gray">最近搜索历史</span>
              <button
                type="button"
                onclick={clearAllRecents}
                class="min-h-[44px] min-w-[44px] rounded-pill px-3 text-xs text-mid-gray transition-colors hover:bg-canvas hover:text-danger"
              >
                清空历史
              </button>
            </div>
            <div role="group" aria-label="最近搜索历史" class="flex flex-wrap gap-1.5 pb-1">
              {#each recentSearches as term (term)}
                <div class="flex min-h-[44px] items-center rounded-pill border hairline bg-paper shadow-2xs">
                  <button
                    type="button"
                    onclick={() => useRecentSearch(term)}
                    class="min-h-[44px] max-w-48 truncate rounded-l-pill px-3 text-left text-xs text-charcoal transition-colors hover:bg-surface-alt hover:text-ink"
                    title={`搜索：${term}`}
                  >
                    {term}
                  </button>
                  <button
                    type="button"
                    onclick={() => removeRecentSearch(term)}
                    class="flex min-h-[44px] min-w-[44px] items-center justify-center rounded-r-pill text-mid-gray transition-colors hover:bg-surface-alt hover:text-danger"
                    aria-label={`删除最近搜索：${term}`}
                    title="删除此条历史"
                  >
                    <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <line x1="18" y1="6" x2="6" y2="18"></line>
                      <line x1="6" y1="6" x2="18" y2="18"></line>
                    </svg>
                  </button>
                </div>
              {/each}
            </div>
          </div>
        {/if}
        {#if query.trim() && searchSource === 'demo' && !searchError}
          <p role="status" class="mx-2 mb-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            当前结果来自内置演示数据；在线曲库暂不可用，这些结果不代表完整曲库。
          </p>
        {/if}
        {#if query.trim() && isLoading && searchResults.length === 0}
          <p role="status" class="mx-2 mb-2 rounded-lg bg-surface-alt px-3 py-2 text-xs text-mid-gray">正在搜索曲库…</p>
        {:else if query.trim() && searchError}
          <div role="alert" class="mx-2 mb-2 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-xs text-red-800">
            <span>{searchError}</span>
            <button type="button" class="btn min-h-[44px] !px-3 !py-1 text-xs" onclick={retrySearch}>重试</button>
          </div>
        {:else if query.trim() && searchSource && searchResults.length === 0}
          <p role="status" class="mx-2 mb-2 rounded-lg bg-surface-alt px-3 py-2 text-xs text-mid-gray">曲库搜索已完成，没有找到直接匹配的曲谱；仍可前往全站搜索。</p>
        {/if}
        {#if selectableItems.length === 0}
          <!-- Empty State -->
          <div class="space-y-3 py-12 text-center text-mid-gray">
            <div class="inline-flex h-12 w-12 items-center justify-center rounded-2xl border hairline bg-surface-alt text-2xl">
              🔍
            </div>
            <p class="text-sm font-medium text-ink">未找到与 "{query}" 匹配的曲谱</p>
            <p class="text-xs text-mid-gray max-w-xs mx-auto">
              建议尝试简短关键词、歌手原名，或直接在专栏与标签库中检索。
            </p>
            <div class="pt-2">
              <a
                href={`/searchResults?searchValue=${encodeURIComponent(query)}`}
                class="btn btn-primary min-h-[44px] !py-1.5 text-xs shadow-xs"
                onclick={closePalette}
              >
                前往全站搜索页查看深度结果 →
              </a>
            </div>
          </div>
        {:else}
          <!-- Grouped Sections Header Label Helpers -->
          <div id="command-palette-results" role="listbox" aria-label="搜索结果与快捷入口" class="space-y-1">
          {#each selectableItems as item, index (item.id)}
            {@const isActive = index === activeIndex}

            <!-- Group Header Separators for clarity -->
            {#if index === 0 && !query.trim()}
              <div role="presentation" aria-hidden="true" class="px-2 pt-1 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-mid-gray">
                ⚡ 快捷指令与入口 (Quick Actions)
              </div>
            {:else if !query.trim() && item.type === 'popular' && (index === 0 || selectableItems[index - 1]?.type !== 'popular')}
              <div role="presentation" aria-hidden="true" class="px-2 pt-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-mid-gray">
                🎼 内置演示示例 · 资源可用性以打开后的提示为准
              </div>
            {:else if !query.trim() && item.type === 'nav' && (index === 0 || selectableItems[index - 1]?.type !== 'nav')}
              <div role="presentation" aria-hidden="true" class="px-2 pt-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-mid-gray">
                🧭 全站导航 (Navigation)
              </div>
            {:else if query.trim() && item.type === 'tab' && index === 0}
              <div role="presentation" aria-hidden="true" class="px-2 pt-1 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-mid-gray">
                🎼 乐谱搜索匹配 (Search Results)
              </div>
            {/if}

            <!-- Individual Result Item (18px Pill Geometry on Hover / Active) -->
            <div role="group" aria-label={item.title} class="flex items-stretch gap-1">
              <button
                id={`command-option-${index}`}
                data-index={index}
                type="button"
                role="option"
                aria-selected={isActive}
                tabindex="-1"
                onclick={() => handleSelect(item)}
                onmouseenter={() => (activeIndex = index)}
                class="group relative flex min-h-[44px] min-w-0 flex-1 items-center justify-between gap-3 rounded-2xl border px-3 py-2.5 text-left transition-all duration-150 {isActive ? 'border-signal/25 bg-surface-alt text-ink shadow-xs hairline' : 'border-transparent text-charcoal hover:bg-surface-alt/70'}"
              >
              <!-- Left Content & Icon -->
              <div class="flex items-center gap-3 min-w-0 flex-1">
                <!-- Type Icon Badge -->
                <div
                  class="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl text-xs transition-colors {isActive ? 'bg-ink text-paper shadow-2xs' : 'bg-surface-alt text-mid-gray group-hover:bg-canvas'}"
                >
                  {#if item.type === 'action'}
                    ⚡
                  {:else if item.type === 'nav'}
                    🧭
                  {:else if item.badge === '尤克里里'}
                    🌴
                  {:else}
                    🎸
                  {/if}
                </div>

                <!-- Title & Subtitle -->
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2">
                    <span class="truncate font-medium text-xs sm:text-sm text-ink group-hover:text-signal transition-colors">
                      {item.title}
                    </span>

                    {#if item.badge}
                      <span class="shrink-0 rounded-pill border hairline bg-paper px-2 py-0.5 text-[10px] font-mono font-medium text-charcoal shadow-2xs">
                        {item.badge}
                      </span>
                    {/if}
                  </div>

                  {#if item.subtitle}
                    <p class="truncate text-[11px] text-mid-gray mt-0.5">
                      {item.subtitle}
                    </p>
                  {/if}
                </div>
              </div>

              <!-- Right Metas & Action Indicators -->
              <div class="flex items-center gap-2 shrink-0 text-xs">
                <!-- Difficulty Pill -->
                {#if item.difficulty}
                  {@const diffLabel = getDiffLabel(item.difficulty)}
                  {#if diffLabel}
                    <span class="hidden sm:inline-flex items-center rounded-pill border px-2 py-0.5 text-[10px] font-medium {getDiffColor(item.difficulty)}">
                      {diffLabel}
                    </span>
                  {/if}
                {/if}

                <!-- Sheet Form / Key -->
                {#if item.sheetForm}
                  <span class="hidden sm:inline-block rounded-pill border hairline bg-paper px-2 py-0.5 text-[10px] font-medium text-mid-gray">
                    {getFormLabel(item.sheetForm)}
                  </span>
                {/if}

                {#if item.key}
                  <span class="hidden sm:inline-block rounded-pill bg-canvas px-2 py-0.5 text-[10px] font-mono text-signal">
                    {item.key} 调
                  </span>
                {/if}

                <!-- Heat Number -->
                {#if item.heat}
                  <span class="hidden md:inline-flex items-center gap-0.5 font-mono text-[10px] text-mid-gray">
                    <svg class="h-2.5 w-2.5 text-amber-500" viewBox="0 0 24 24" fill="currentColor">
                      <path d="M12 2c1.5 3 4 5 4 9 0 3.3-2.7 6-6 6s-6-2.7-6-6c0-3.5 2-6 4-8-.5 2 1 4 2 4s2-2 2-5z"/>
                    </svg>
                    {item.heat >= 10000 ? (item.heat / 10000).toFixed(1) + 'w' : item.heat}
                  </span>
                {/if}

                <!-- Active Arrow Jump Indicator -->
                <span
                  class="flex h-6 w-6 items-center justify-center rounded-lg text-mid-gray transition-transform {isActive ? 'translate-x-0 opacity-100 text-ink bg-paper shadow-2xs' : 'opacity-0 -translate-x-1'}"
                >
                  <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <polyline points="9 18 15 12 9 6"></polyline>
                  </svg>
                </span>
              </div>
              </button>
            </div>
          {/each}
          </div>
        {/if}
      </div>

      <!-- Bottom Status & Keyboard Shortcut Hints Footer Bar -->
      <div class="px-4 py-2.5 border-t hairline bg-surface-alt/70 flex flex-wrap items-center justify-between gap-2 text-[11px] text-mid-gray">
        <div class="flex items-center gap-3">
          <span class="flex items-center gap-1">
            <kbd class="rounded border hairline bg-paper px-1 py-0.2 text-[10px] font-mono text-ink shadow-2xs">↑</kbd>
            <kbd class="rounded border hairline bg-paper px-1 py-0.2 text-[10px] font-mono text-ink shadow-2xs">↓</kbd>
            <span>导航</span>
          </span>
          <span class="flex items-center gap-1">
            <kbd class="rounded border hairline bg-paper px-1.5 py-0.2 text-[10px] font-mono text-ink shadow-2xs">↵</kbd>
            <span>打开</span>
          </span>
          <span class="flex items-center gap-1">
            <kbd class="rounded border hairline bg-paper px-1 py-0.2 text-[10px] font-mono text-ink shadow-2xs">TAB</kbd>
            <span>移动焦点</span>
          </span>
          <span class="hidden sm:flex items-center gap-1">
            <kbd class="rounded border hairline bg-paper px-1 py-0.2 text-[10px] font-mono text-ink shadow-2xs">ESC</kbd>
            <span>关闭</span>
          </span>
        </div>

        <div class="flex items-center gap-1.5 font-mono text-[10px] text-mid-gray">
          <span class="h-1.5 w-1.5 rounded-full bg-signal"></span>
          <span>MIMI ⌘K Engine</span>
        </div>
      </div>
</MotionDialog>
