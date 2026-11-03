<script lang="ts">
  import { onMount } from 'svelte';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import { addCatalogFavorite, addCatalogPractice, type CatalogScoreInput } from '../lib/personal/catalog.ts';
  import { readPersonalData, mutatePersonalData, subscribePersonalData, hashBytes } from '../lib/personal/repository.ts';
  import { prepareLocalScore } from '../lib/personal/importLocalScore.ts';
  import { loadStudioProject, saveStudioProjectForPractice } from '../lib/personal/studioPersistence.ts';
  import { appendPracticeQueueItem, createGenerationGuard, movePracticeQueueItem, normalizePracticeQueue, setPracticeQueueStatus } from '../lib/personal/practiceQueue.ts';
  import type { PersonalData, PersonalScore, PracticeStatus } from '../lib/personal/types.ts';
  import { fadeMotion, registerMotionSurface, surfaceMotion } from '../lib/ui/motion.ts';
  import { getMotionPreferenceSnapshot, subscribeMotionPreference, type MotionMode } from '../lib/ui/motionPreferences.ts';

  type SearchRow = CatalogScoreInput & { heat?: number; source: 'catalog' | 'demo' | 'unavailable' };
  type PersonalLibraryTab = 'queue' | 'favorites' | 'imported' | 'projects' | 'archived' | 'recent' | 'search';

  const TABS: { id: PersonalLibraryTab; label: string; icon: string }[] = [
    { id: 'queue', label: '待练队列', icon: '📋' },
    { id: 'favorites', label: '我的收藏', icon: '♥' },
    { id: 'imported', label: '本地导入', icon: '📥' },
    { id: 'projects', label: '工坊工程', icon: '🎼' },
    { id: 'archived', label: '已归档', icon: '📦' },
    { id: 'recent', label: '最近浏览', icon: '🕒' },
    { id: 'search', label: '曲库查找', icon: '🔍' },
  ];

  let selectedTab = $state<PersonalLibraryTab>('queue');
  let localFilterText = $state('');

  let data = $state<PersonalData | null>(null);
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let notice = $state('');
  let query = $state('');
  let results = $state<SearchRow[]>([]);
  let resultSource = $state<'catalog' | 'demo' | 'unavailable' | ''>('');
  let searchCategory = $state<'guitar' | 'ukulele'>('guitar');
  let importCategory = $state<'guitar' | 'ukulele' | 'bass'>('guitar');
  let selectedFile = $state<File | null>(null);
  const reloadGeneration = createGenerationGuard();
  let mounted = true;
  let searchGeneration = 0;
  let searchController: AbortController | null = null;
  let searchBusy = $state(false);
  let searchError = $state('');
  let motionMode = $state<MotionMode>(getMotionPreferenceSnapshot().mode);
  let noteDrafts = $state<Record<string, string>>({});
  let noteDraftBases = $state<Record<string, string>>({});
  let noteSaveStates = $state<Record<string, 'dirty' | 'saving' | 'saved' | 'error' | 'conflict'>>({});
  let noteSaveErrors = $state<Record<string, string>>({});

  function arrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const copy = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(copy).set(bytes);
    return copy;
  }

  const scores = $derived(data?.scores ?? []);
  const favorites = $derived(scores.filter((score) => data?.favorites.includes(score.id)));
  const orderedPracticeItems = $derived(normalizePracticeQueue(data?.practiceItems ?? []));
  const practice = $derived(orderedPracticeItems.filter((item) => item.status !== 'archived').flatMap((item) => {
    const score = scores.find((entry) => entry.id === item.scoreId);
    return score ? [{ item, score }] : [];
  }));
  const archivedPractice = $derived(orderedPracticeItems.filter((item) => item.status === 'archived').flatMap((item) => {
    const score = scores.find((entry) => entry.id === item.scoreId);
    return score ? [{ item, score }] : [];
  }));
  const privateScores = $derived(scores.filter((score) => score.source === 'private'));
  const studioProjects = $derived((data?.projects ?? []).slice().sort((a, b) => b.updatedAt - a.updatedAt));
  const recentHistory = $derived((data?.history ?? []).slice().sort((a, b) => b.time - a.time));

  function matchesLocalFilter(title: string, artist: string, category = ''): boolean {
    const q = localFilterText.trim().toLowerCase();
    if (!q) return true;
    return (
      title.toLowerCase().includes(q) ||
      artist.toLowerCase().includes(q) ||
      category.toLowerCase().includes(q)
    );
  }

  const filteredPractice = $derived(practice.filter((entry) => matchesLocalFilter(entry.score.title, entry.score.artist, entry.score.category)));
  const filteredFavorites = $derived(favorites.filter((score) => matchesLocalFilter(score.title, score.artist, score.category)));
  const filteredPrivate = $derived(privateScores.filter((score) => matchesLocalFilter(score.title, score.artist, score.category)));
  const filteredProjects = $derived(studioProjects.filter((project) => matchesLocalFilter(project.title || '未命名乐谱', project.artist || '原创作者')));
  const filteredArchived = $derived(archivedPractice.filter((entry) => matchesLocalFilter(entry.score.title, entry.score.artist, entry.score.category)));
  const filteredHistory = $derived(recentHistory.filter((item) => matchesLocalFilter(item.title, item.artist || '', item.category || '')));

  function getTabCount(tabId: PersonalLibraryTab): number | null {
    switch (tabId) {
      case 'queue': return practice.length;
      case 'favorites': return favorites.length;
      case 'imported': return privateScores.length;
      case 'projects': return studioProjects.length;
      case 'archived': return archivedPractice.length;
      case 'recent': return recentHistory.length;
      case 'search': return null;
    }
  }

  async function reload() {
    const generation = reloadGeneration.next();
    try {
      const next = await readPersonalData();
      if (!mounted || !reloadGeneration.isCurrent(generation)) return;
      data = next;
      loading = false;
    } catch (cause) {
      if (!mounted || !reloadGeneration.isCurrent(generation)) return;
      error = cause instanceof Error ? cause.message : String(cause);
      loading = false;
    }
  }

  function preventLosingPracticeNoteDraft(event: BeforeUnloadEvent) {
    const hasUnsavedDraft = Object.entries(noteDrafts).some(([scoreId, note]) =>
      note !== noteDraftBases[scoreId] && ['dirty', 'saving', 'error', 'conflict'].includes(noteSaveStates[scoreId] ?? ''),
    );
    if (!hasUnsavedDraft) return;
    event.preventDefault();
    event.returnValue = '';
  }

  onMount(() => {
    mounted = true;
    const unsubscribeMotion = subscribeMotionPreference((snapshot) => { motionMode = snapshot.mode; });
    const unsubscribe = subscribePersonalData(() => { if (mounted) void reload(); });
    window.addEventListener('beforeunload', preventLosingPracticeNoteDraft);

    // Deep link support via URL parameters and hash
    const params = new URLSearchParams(window.location.search);
    const requestedTab = params.get('tab') as PersonalLibraryTab | null;
    if (requestedTab && TABS.some((t) => t.id === requestedTab)) {
      selectedTab = requestedTab;
    } else if (window.location.hash) {
      const hash = window.location.hash.toLowerCase();
      if (hash.includes('search') || hash.includes('catalog')) selectedTab = 'search';
      else if (hash.includes('import')) selectedTab = 'imported';
      else if (hash.includes('fav')) selectedTab = 'favorites';
      else if (hash.includes('proj')) selectedTab = 'projects';
      else if (hash.includes('arch')) selectedTab = 'archived';
      else if (hash.includes('rec')) selectedTab = 'recent';
    }

    void reload();
    return () => {
      mounted = false;
      reloadGeneration.invalidate();
      searchGeneration += 1;
      searchController?.abort();
      searchController = null;
      unsubscribe();
      unsubscribeMotion();
      window.removeEventListener('beforeunload', preventLosingPracticeNoteDraft);
    };
  });

  async function searchCatalog(event: SubmitEvent) {
    event.preventDefault();
    searchController?.abort();
    const generation = ++searchGeneration;
    const controller = new AbortController();
    searchController = controller;
    const searchText = query.trim();
    const categoryAtSubmit = searchCategory;
    searchError = ''; results = []; resultSource = '';
    if (!searchText) { searchBusy = false; searchController = null; return; }
    searchBusy = true;
    try {
      const response = await fetch(`/api/search?q=${encodeURIComponent(searchText)}&category=${categoryAtSubmit}&limit=20`, { signal: controller.signal });
      const payload = await response.json();
      if (!mounted || controller.signal.aborted || generation !== searchGeneration) return;
      resultSource = payload.source ?? 'unavailable';
      if (!response.ok || payload.ok !== true) throw new Error('在线曲库不可用，未能完成搜索。');
      results = (payload.tabs as any[]).map((tab) => ({ id: tab.id, title: tab.title, artist: tab.artist, category: tab.category, format: tab.format, scoreUrl: tab.scoreUrl, source: resultSource as 'catalog' | 'demo' | 'unavailable', heat: tab.heat }));
    } catch (cause) {
      if (!mounted || controller.signal.aborted || generation !== searchGeneration) return;
      resultSource = 'unavailable';
      searchError = cause instanceof Error ? cause.message : String(cause);
    } finally {
      if (generation === searchGeneration) { searchBusy = false; searchController = null; }
    }
  }

  function invalidateCatalogSearch() {
    searchGeneration += 1;
    searchController?.abort();
    searchController = null;
    searchBusy = false;
    searchError = '';
    results = [];
    resultSource = '';
  }

  async function saveCatalog(row: SearchRow, kind: 'favorite' | 'practice') {
    busy = true; error = ''; notice = '';
    try {
      if (row.source !== 'catalog') throw new Error('当前结果来自演示数据，不能保存为真实曲库引用。');
      if (kind === 'practice' && (row.format === 'xhe' || !row.scoreUrl)) throw new Error('这份曲谱没有可播放的下载资源；可以从曲库打开文本谱查看。');
      if (kind === 'favorite') await addCatalogFavorite(row, true);
      else await addCatalogPractice(row);
      notice = kind === 'favorite' ? '已保存到本设备收藏。' : '已加入本设备待练。';
      await reload();
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function updatePractice(scoreId: string, patch: Partial<{ status: PracticeStatus; note: string }>) {
    if (!data) return;
    busy = true; error = ''; notice = '';
    try {
      await mutatePersonalData((draft) => {
        const item = draft.practiceItems.find((entry) => entry.scoreId === scoreId);
        if (!item) throw new Error('待练条目已被移除，请刷新后重试。');
        if (patch.status) draft.practiceItems = setPracticeQueueStatus(draft.practiceItems, scoreId, patch.status);
        const nextItem = draft.practiceItems.find((entry) => entry.scoreId === scoreId);
        if (!nextItem) throw new Error('待练条目已被移除，请刷新后重试。');
        if (patch.note !== undefined) nextItem.note = patch.note;
        nextItem.updatedAt = Date.now();
      });
      await reload();
      if (patch.status === 'archived') notice = '已归档到“已归档”，可随时恢复到待练。';
      else if (patch.status) notice = patch.status === 'todo' ? '已恢复到待练队列末尾。' : '练习状态已更新。';
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function removePractice(scoreId: string) {
    const removedScore = scores.find((score) => score.id === scoreId);
    busy = true; error = '';
    try {
      await mutatePersonalData((draft) => { draft.practiceItems = normalizePracticeQueue(draft.practiceItems.filter((item) => item.scoreId !== scoreId)); });
      await reload();
      notice = `已将《${removedScore?.title || '这份曲谱'}》移出待练；曲谱与练习记录仍保留在本设备。`;
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function movePractice(scoreId: string, direction: -1 | 1) {
    busy = true; error = '';
    try {
      const next = await mutatePersonalData((draft) => { draft.practiceItems = movePracticeQueueItem(draft.practiceItems, scoreId, direction); });
      const active = normalizePracticeQueue(next.practiceItems).filter((item) => item.status !== 'archived');
      const position = active.findIndex((item) => item.scoreId === scoreId) + 1;
      const score = next.scores.find((item) => item.id === scoreId);
      await reload();
      if (position > 0) notice = `已将《${score?.title || '曲谱'}》移到第 ${position} 位。`;
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function toggleFavorite(scoreId: string) {
    if (!data) return;
    busy = true; error = '';
    try {
      await mutatePersonalData((draft) => { draft.favorites = draft.favorites.filter((id) => id !== scoreId); });
      await reload();
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function addPracticeFromScore(score: PersonalScore) {
    const existingPractice = data?.practiceItems.find((item) => item.scoreId === score.id);
    if (existingPractice && existingPractice.status !== 'archived') {
      notice = `《${score.title}》已在待练中。`;
      return;
    }
    busy = true; error = '';
    try {
      if (score.source === 'catalog' && (score.format === 'xhe' || !score.scoreUrl)) throw new Error('这份曲谱没有可播放下载资源；请从曲库打开文本谱查看。');
      await mutatePersonalData((draft) => {
        const existing = draft.practiceItems.find((item) => item.scoreId === score.id);
        if (!existing) draft.practiceItems = appendPracticeQueueItem(draft.practiceItems, { scoreId: score.id, status: 'todo', note: '', order: 0, updatedAt: Date.now() });
        else if (existing.status === 'archived') {
          draft.practiceItems = setPracticeQueueStatus(draft.practiceItems, score.id, 'todo')
            .map((item) => item.scoreId === score.id ? { ...item, updatedAt: Date.now() } : item);
        }
      });
      await reload();
      notice = existingPractice?.status === 'archived' ? `《${score.title}》已恢复到待练队列末尾。` : `《${score.title}》已加入待练队列。`;
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  function editPracticeNote(scoreId: string, currentNote: string, value: string) {
    if (!(scoreId in noteDrafts)) noteDraftBases[scoreId] = currentNote;
    if (value === noteDraftBases[scoreId]) {
      delete noteDrafts[scoreId];
      delete noteDraftBases[scoreId];
      delete noteSaveErrors[scoreId];
      delete noteSaveStates[scoreId];
      return;
    }
    noteDrafts[scoreId] = value;
    if (noteSaveStates[scoreId] !== 'conflict') noteSaveStates[scoreId] = 'dirty';
    delete noteSaveErrors[scoreId];
  }

  async function savePracticeNote(scoreId: string) {
    const note = noteDrafts[scoreId];
    if (note === undefined || !data || noteSaveStates[scoreId] === 'conflict') return;
    const expectedNote = noteDraftBases[scoreId] ?? '';
    let baseConflict = false;
    noteSaveStates[scoreId] = 'saving';
    delete noteSaveErrors[scoreId];
    busy = true;
    error = '';
    try {
      await mutatePersonalData((draft) => {
        const item = draft.practiceItems.find((entry) => entry.scoreId === scoreId);
        if (!item) throw new Error('待练条目已被移除，请刷新后重试。');
        if (item.note !== expectedNote) {
          baseConflict = true;
          throw new Error('备注已在其他页面更新。请取消这份草稿后重新编辑。');
        }
        item.note = note;
        item.updatedAt = Date.now();
      });
      await reload();
      delete noteDrafts[scoreId];
      delete noteDraftBases[scoreId];
      noteSaveStates[scoreId] = 'saved';
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : String(cause);
      if (baseConflict) {
        await reload();
        noteSaveStates[scoreId] = 'conflict';
        delete noteSaveErrors[scoreId];
      } else {
        error = message;
        noteSaveStates[scoreId] = 'error';
        noteSaveErrors[scoreId] = message;
      }
    } finally { busy = false; }
  }

  function cancelPracticeNote(scoreId: string) {
    delete noteDrafts[scoreId];
    delete noteDraftBases[scoreId];
    delete noteSaveErrors[scoreId];
    delete noteSaveStates[scoreId];
  }

  async function addProjectToPractice(projectId: string) {
    busy = true; error = ''; notice = '';
    try {
      const project = await loadStudioProject(projectId);
      if (!project) throw new Error('这份工坊工程已被删除，请刷新我的谱。');
      await saveStudioProjectForPractice(project);
      notice = `《${project.title || '未命名乐谱'}》已转换为可播放 IBE 并加入待练；原始文件保持独立。`;
      await reload();
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function importFile() {
    if (!selectedFile) return;
    const sourceFile = selectedFile;
    busy = true; error = ''; notice = '';
    try {
      const prepared = await prepareLocalScore(sourceFile);
      if (prepared.playableBytes.byteLength > 30 * 1024 * 1024) throw new Error('转换后的可播放谱超过 30 MiB，没有写入任何资料。');
      const originalId = await hashBytes(prepared.originalBytes);
      const playbackId = await hashBytes(prepared.playableBytes);
      const now = Date.now();
      const scoreId = `private:${originalId}`;
      const score: PersonalScore = {
        id: scoreId, source: 'private', sourceId: originalId, revision: playbackId,
        title: prepared.title, artist: prepared.artist, category: importCategory, format: prepared.sourceFormat,
        assetId: playbackId, originalAssetId: originalId, createdAt: now, updatedAt: now,
      };
      const assetMap = new Map<string, { id: string; mimeType: string; bytes: ArrayBuffer }>();
      assetMap.set(originalId, { id: originalId, mimeType: sourceFile.type || 'application/octet-stream', bytes: arrayBuffer(prepared.originalBytes) });
      if (!assetMap.has(playbackId)) assetMap.set(playbackId, { id: playbackId, mimeType: 'application/vnd.mimi.score', bytes: arrayBuffer(prepared.playableBytes) });
      await mutatePersonalData((draft) => {
        const existing = draft.scores.findIndex((entry) => entry.id === scoreId);
        if (existing < 0) draft.scores.push(score);
        else draft.scores[existing] = { ...draft.scores[existing], ...score, createdAt: draft.scores[existing].createdAt };
        if (!draft.originals.some((entry) => entry.id === originalId)) draft.originals.push({ id: originalId, fileName: sourceFile.name, mimeType: sourceFile.type || 'application/octet-stream', assetId: originalId, savedAt: now });
        const practiceItem = draft.practiceItems.find((item) => item.scoreId === scoreId);
        if (!practiceItem) draft.practiceItems = appendPracticeQueueItem(draft.practiceItems, { scoreId, status: 'todo', note: '', order: 0, updatedAt: now });
        else if (practiceItem.status === 'archived') {
          draft.practiceItems = setPracticeQueueStatus(draft.practiceItems, scoreId, 'todo')
            .map((item) => item.scoreId === scoreId ? { ...item, updatedAt: now } : item);
        }
      }, { assets: [...assetMap.values()] });
      selectedFile = null;
      notice = `《${score.title}》及原始文件已保存到本设备，并已加入待练。`;
      await reload();
      selectedTab = 'queue';
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function clearHistory() {
    if (!confirm('确定清空本机的最近浏览记录吗？这不会影响收藏与待练。')) return;
    busy = true; error = '';
    try {
      await mutatePersonalData((draft) => { draft.history = []; });
      await reload();
      notice = '已清空最近浏览记录。';
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }
</script>

<section class="personal-library space-y-6">
  {#if error}
    <p use:registerMotionSurface transition:surfaceMotion={{ kind: 'notice' }} role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800 shadow-2xs">{error}</p>
  {/if}
  {#if notice}
    <p use:registerMotionSurface transition:surfaceMotion={{ kind: 'notice' }} role="status" class="rounded-xl border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-900 shadow-2xs">{notice}</p>
  {/if}

  {#if loading}
    <div class="card p-8 text-center text-sm text-ash shadow-xs">
      <div class="mx-auto mb-2 h-6 w-6 animate-spin rounded-full border-2 border-[#8c6d46] border-t-transparent"></div>
      <p>正在读取本设备个人资料…</p>
    </div>
  {:else if !data}
    <div class="card p-6 text-sm text-red-800 shadow-xs">
      无法读取本地资料。请刷新或检查浏览器存储权限；本页未使用临时内存代替真实本地保存。
    </div>
  {:else}
    <!-- 顶部四项指标快捷看板 (同步 native macOS PersonalLibraryView metricPill 体验) -->
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
      <button
        type="button"
        onclick={() => { selectedTab = 'queue'; }}
        class="card group flex items-center justify-between rounded-2xl border p-4 text-left transition-all hover:border-[#8c6d46] hover:shadow-xs {selectedTab === 'queue' ? 'border-[#8c6d46] bg-[#fbf9f5]' : 'bg-white'}"
      >
        <div class="space-y-0.5">
          <span class="text-xs font-medium text-ash">待练队列</span>
          <div class="font-display text-2xl font-bold text-[#8c6d46]">{practice.length}</div>
        </div>
        <span class="rounded-xl bg-[#8c6d46]/10 p-2.5 text-lg text-[#8c6d46] group-hover:scale-105 transition-transform">📋</span>
      </button>

      <button
        type="button"
        onclick={() => { selectedTab = 'favorites'; }}
        class="card group flex items-center justify-between rounded-2xl border p-4 text-left transition-all hover:border-[#c84b31] hover:shadow-xs {selectedTab === 'favorites' ? 'border-[#c84b31] bg-[#fbf9f5]' : 'bg-white'}"
      >
        <div class="space-y-0.5">
          <span class="text-xs font-medium text-ash">我的收藏</span>
          <div class="font-display text-2xl font-bold text-[#c84b31]">{favorites.length}</div>
        </div>
        <span class="rounded-xl bg-[#c84b31]/10 p-2.5 text-lg text-[#c84b31] group-hover:scale-105 transition-transform">♥</span>
      </button>

      <button
        type="button"
        onclick={() => { selectedTab = 'imported'; }}
        class="card group flex items-center justify-between rounded-2xl border p-4 text-left transition-all hover:border-[#286a8e] hover:shadow-xs {selectedTab === 'imported' ? 'border-[#286a8e] bg-[#fbf9f5]' : 'bg-white'}"
      >
        <div class="space-y-0.5">
          <span class="text-xs font-medium text-ash">本地导入</span>
          <div class="font-display text-2xl font-bold text-[#286a8e]">{privateScores.length}</div>
        </div>
        <span class="rounded-xl bg-[#286a8e]/10 p-2.5 text-lg text-[#286a8e] group-hover:scale-105 transition-transform">📥</span>
      </button>

      <button
        type="button"
        onclick={() => { selectedTab = 'projects'; }}
        class="card group flex items-center justify-between rounded-2xl border p-4 text-left transition-all hover:border-[#5d4836] hover:shadow-xs {selectedTab === 'projects' ? 'border-[#5d4836] bg-[#fbf9f5]' : 'bg-white'}"
      >
        <div class="space-y-0.5">
          <span class="text-xs font-medium text-ash">工坊工程</span>
          <div class="font-display text-2xl font-bold text-[#5d4836]">{studioProjects.length}</div>
        </div>
        <span class="rounded-xl bg-[#5d4836]/10 p-2.5 text-lg text-[#5d4836] group-hover:scale-105 transition-transform">🎼</span>
      </button>
    </div>

    <!-- 七标签分段控制器与列表内即时检索栏 (完全对齐 native macOS PersonalLibraryView TabBar) -->
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between border-b border-[#e8e2d4] pb-3">
      <!-- 标签滑动胶囊 -->
      <nav aria-label="个人资料分类" class="flex flex-wrap items-center gap-1.5 overflow-x-auto py-1">
        {#each TABS as tab (tab.id)}
          {@const isSelected = selectedTab === tab.id}
          {@const count = getTabCount(tab.id)}
          <button
            type="button"
            onclick={() => { selectedTab = tab.id; }}
            class="inline-flex h-9 items-center gap-1.5 rounded-full px-3.5 text-xs font-medium transition-all {isSelected ? 'bg-[#1a1816] text-white shadow-2xs' : 'border border-[#e8e2d4] bg-white text-[#584a3b] hover:bg-[#faf7f2]'}"
            aria-selected={isSelected}
          >
            <span>{tab.icon}</span>
            <span>{tab.label}</span>
            {#if count !== null && count > 0}
              <span class="ml-0.5 rounded-full px-1.5 py-0.2 text-[10px] font-bold {isSelected ? 'bg-white/20 text-white' : 'bg-[#f0eae0] text-[#705c42]'}">
                {count}
              </span>
            {/if}
          </button>
        {/each}
      </nav>

      <!-- 列表内即时筛选 (search 标签除外) -->
      {#if selectedTab !== 'search'}
        <div class="relative flex items-center">
          <input
            type="search"
            bind:value={localFilterText}
            placeholder="在此列表中筛选…"
            class="h-9 w-full rounded-full border border-[#e8e2d4] bg-white px-3.5 pr-8 text-xs text-[#1a1816] placeholder-[#8c7b68] shadow-2xs focus:border-[#8c6d46] focus:outline-none sm:w-56"
          />
          {#if localFilterText}
            <button
              type="button"
              onclick={() => { localFilterText = ''; }}
              class="absolute right-2.5 text-xs text-[#8c7b68] hover:text-[#1a1816]"
              aria-label="清空筛选内容"
            >
              ✕
            </button>
          {/if}
        </div>
      {/if}
    </div>

    <!-- 标签内容区 -->
    <div class="min-h-[360px]">
      <!-- 1. 待练队列 -->
      {#if selectedTab === 'queue'}
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="font-display text-base font-semibold text-[#1a1816]">待练队列 ({filteredPractice.length})</h2>
            <a href="/practice" class="btn btn-signal h-8 !px-3 text-xs">进入琴房练习 →</a>
          </div>

          {#if practice.length === 0}
            <div class="card space-y-3 p-8 text-center text-ash shadow-xs">
              <div class="text-3xl">🎸</div>
              <p class="font-medium text-[#1a1816]">待练队列目前为空</p>
              <p class="text-xs">可从“曲库查找”中搜索喜欢的曲目加入待练，或导入自己的吉他谱。</p>
              <div class="flex justify-center gap-2 pt-2">
                <button type="button" class="btn btn-signal h-9 text-xs" onclick={() => { selectedTab = 'search'; }}>前往曲库查找</button>
                <button type="button" class="btn btn-ghost h-9 text-xs" onclick={() => { selectedTab = 'imported'; }}>导入本地曲谱</button>
              </div>
            </div>
          {:else if filteredPractice.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              没有匹配“{localFilterText}”的待练曲谱。
            </div>
          {:else}
            <div class="space-y-3">
              {#each filteredPractice as entry (entry.score.id)}
                {@const practiceIndex = practice.findIndex((candidate) => candidate.score.id === entry.score.id)}
                <article
                  use:registerMotionSurface
                  animate:flip={{ duration: motionMode === 'full' ? 180 : 0, easing: cubicOut }}
                  in:surfaceMotion={{ kind: 'menu' }}
                  out:fadeMotion={{ kind: 'menu' }}
                  class="card rounded-2xl border border-[#e8e2d4] bg-white p-4 shadow-2xs hover:shadow-xs transition-shadow"
                >
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="min-w-0">
                      <div class="flex items-center gap-2">
                        <span class="rounded bg-[#f0eae0] px-1.5 py-0.5 text-[10px] font-bold text-[#705c42]">#{practiceIndex + 1}</span>
                        <h3 class="truncate font-display text-base font-semibold text-[#1a1816]">{entry.score.title}</h3>
                        <span class="rounded px-1.5 py-0.5 text-[10px] font-medium {entry.score.category === 'ukulele' ? 'bg-[#c84b31]/10 text-[#c84b31]' : 'bg-[#8c6d46]/10 text-[#8c6d46]'}">
                          {entry.score.category === 'ukulele' ? '尤克里里' : '吉他'}
                        </span>
                      </div>
                      <p class="mt-1 text-xs text-[#705c42]">
                        {entry.score.artist || '未知艺人'} · {entry.score.source === 'private' ? '个人导入' : entry.score.source === 'project' ? '工坊练习谱' : '曲库引用'}
                      </p>
                    </div>

                    <div class="flex flex-wrap items-center gap-1.5">
                      <button
                        type="button"
                        class="btn btn-ghost h-8 !px-2.5 text-xs"
                        aria-label={`将《${entry.score.title}》上移`}
                        disabled={busy || practiceIndex === 0}
                        onclick={() => movePractice(entry.score.id, -1)}
                      >
                        ↑ 上移
                      </button>
                      <button
                        type="button"
                        class="btn btn-ghost h-8 !px-2.5 text-xs"
                        aria-label={`将《${entry.score.title}》下移`}
                        disabled={busy || practiceIndex === practice.length - 1}
                        onclick={() => movePractice(entry.score.id, 1)}
                      >
                        ↓ 下移
                      </button>
                      {#if entry.score.source !== 'catalog' || (entry.score.format !== 'xhe' && entry.score.scoreUrl)}
                        <a class="btn btn-signal h-8 !px-3 text-xs font-semibold" href={`/practice?score=${encodeURIComponent(entry.score.id)}`}>
                          ⏱️ 开始练习
                        </a>
                      {:else}
                        <a class="btn btn-ghost h-8 !px-3 text-xs" href={`/${entry.score.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(entry.score.sourceId)}`}>
                          阅读文本谱
                        </a>
                      {/if}
                      <button type="button" class="btn btn-ghost h-8 !px-2 text-xs" disabled={busy} onclick={() => updatePractice(entry.score.id, { status: 'archived' })}>
                        归档
                      </button>
                      <button type="button" class="btn btn-ghost h-8 !px-2 text-xs text-red-700 hover:bg-red-50" disabled={busy} onclick={() => removePractice(entry.score.id)}>
                        移出
                      </button>
                    </div>
                  </div>

                  <div class="mt-3 grid gap-2 sm:grid-cols-[10rem_1fr]">
                    <select
                      aria-label={`${entry.score.title}练习状态`}
                      value={entry.item.status}
                      disabled={busy}
                      onchange={(event) => updatePractice(entry.score.id, { status: event.currentTarget.value as PracticeStatus })}
                      class="h-8 rounded-lg border border-[#e2dacd] bg-[#fbf9f5] px-2 text-xs"
                    >
                      <option value="todo">待练 (未开启)</option>
                      <option value="practicing">在练 (攻坚中)</option>
                      <option value="mastered">已掌握 (顺畅弹奏)</option>
                    </select>
                    <input
                      aria-label={`${entry.score.title}备注`}
                      value={noteDrafts[entry.score.id] ?? entry.item.note}
                      disabled={busy}
                      oninput={(event) => editPracticeNote(entry.score.id, entry.item.note, event.currentTarget.value)}
                      placeholder="练习目标、卡点小节或指法备忘…"
                      class="h-8 rounded-lg border border-[#e2dacd] bg-[#fbf9f5] px-2.5 text-xs placeholder-[#8c7b68]"
                    />
                  </div>

                  {#if noteDrafts[entry.score.id] !== undefined && (noteDrafts[entry.score.id] !== entry.item.note || noteSaveStates[entry.score.id] === 'conflict')}
                    <div class="mt-2 flex flex-wrap items-center gap-2">
                      <p role="status" class="text-xs text-ash">
                        {noteSaveStates[entry.score.id] === 'saving'
                          ? '正在保存备注…'
                          : noteSaveStates[entry.score.id] === 'conflict'
                            ? '备注已在其他页面更新。草稿仍保留，可复制；请取消草稿后再按当前备注重新编辑。'
                            : noteSaveStates[entry.score.id] === 'error'
                              ? `保存失败：${noteSaveErrors[entry.score.id] || '请重试。'}`
                              : '备注尚未保存。'}
                      </p>
                      {#if noteSaveStates[entry.score.id] !== 'conflict'}
                        <button type="button" class="btn btn-signal h-7 !px-2.5 text-xs" disabled={busy} onclick={() => savePracticeNote(entry.score.id)}>
                          {noteSaveStates[entry.score.id] === 'error' ? '重试保存' : '保存备注'}
                        </button>
                      {/if}
                      <button type="button" class="btn btn-ghost h-7 !px-2.5 text-xs" disabled={busy} onclick={() => cancelPracticeNote(entry.score.id)}>
                        {noteSaveStates[entry.score.id] === 'conflict' ? '取消草稿' : '取消更改'}
                      </button>
                    </div>
                  {:else if noteSaveStates[entry.score.id] === 'saved'}
                    <p role="status" class="mt-1 text-[11px] text-[#2E6B47]">备注已保存到本地。</p>
                  {/if}
                </article>
              {/each}
            </div>
          {/if}
        </div>

      <!-- 2. 我的收藏 -->
      {:else if selectedTab === 'favorites'}
        <div class="space-y-4">
          <h2 class="font-display text-base font-semibold text-[#1a1816]">我的收藏 ({filteredFavorites.length})</h2>
          {#if favorites.length === 0}
            <div class="card space-y-3 p-8 text-center text-ash shadow-xs">
              <div class="text-3xl text-red-500">♥</div>
              <p class="font-medium text-[#1a1816]">还没有收藏任何曲谱</p>
              <p class="text-xs">在曲谱页面点击“收藏”按钮，或者在下方“曲库查找”中搜索喜欢的歌曲。</p>
              <button type="button" class="btn btn-signal h-9 text-xs" onclick={() => { selectedTab = 'search'; }}>前往曲库查找</button>
            </div>
          {:else if filteredFavorites.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              没有匹配“{localFilterText}”的收藏曲谱。
            </div>
          {:else}
            <div class="grid gap-3 sm:grid-cols-2">
              {#each filteredFavorites as score (score.id)}
                {@const practiceItem = data.practiceItems.find((item) => item.scoreId === score.id)}
                <article class="card flex flex-col justify-between rounded-2xl border border-[#e8e2d4] bg-white p-4 shadow-2xs hover:shadow-xs transition-shadow">
                  <div>
                    <div class="flex items-center justify-between gap-2">
                      <h3 class="truncate font-display text-base font-semibold text-[#1a1816]">{score.title}</h3>
                      <span class="rounded bg-[#f0eae0] px-1.5 font-mono text-[10px] text-[#705c42]">{score.format.toUpperCase()}</span>
                    </div>
                    <p class="mt-1 text-xs text-[#705c42]">{score.artist || '未知艺人'} · {score.category === 'ukulele' ? '尤克里里' : '吉他'}</p>
                  </div>

                  <div class="mt-4 flex flex-wrap items-center gap-2 border-t border-[#f2ede4] pt-3">
                    {#if score.source === 'catalog'}
                      <a class="btn btn-ghost h-8 !px-2.5 text-xs" href={`/${score.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(score.sourceId)}`}>
                        打开谱面
                      </a>
                    {/if}
                    {#if practiceItem && practiceItem.status !== 'archived'}
                      <a class="btn btn-signal h-8 !px-3 text-xs" href={`/practice?score=${encodeURIComponent(score.id)}`}>
                        已在待练 · 开始练习
                      </a>
                    {:else}
                      <button
                        type="button"
                        class="btn btn-ghost h-8 !px-2.5 text-xs text-[#8c6d46]"
                        disabled={busy || (score.source === 'catalog' && (score.format === 'xhe' || !score.scoreUrl))}
                        onclick={() => addPracticeFromScore(score)}
                      >
                        {practiceItem?.status === 'archived' ? '恢复到待练' : '加入待练'}
                      </button>
                    {/if}
                    <button type="button" class="btn btn-ghost h-8 !px-2 text-xs text-red-700 hover:bg-red-50" disabled={busy} onclick={() => toggleFavorite(score.id)}>
                      取消收藏
                    </button>
                  </div>
                </article>
              {/each}
            </div>
          {/if}
        </div>

      <!-- 3. 本地导入 -->
      {:else if selectedTab === 'imported'}
        <div class="space-y-6">
          <!-- 导入操作面板 -->
          <div class="card rounded-2xl border border-[#e8e2d4] bg-white p-5 shadow-xs">
            <h2 class="font-display text-base font-semibold text-[#1a1816]">导入本地个人谱</h2>
            <p class="mt-1 text-xs text-[#705c42]">
              支持 Guitar Pro (.gp, .gp3, .gp4, .gp5, .gpx) 与 IBE 格式。文件解析与指弹时值完全在本机完成，并以 SHA-256 独立指纹安全归档。
            </p>
            <div class="mt-4 flex flex-wrap items-center gap-2">
              <select bind:value={importCategory} aria-label="个人谱导入分类" class="h-9 rounded-lg border border-[#e2dacd] bg-[#fbf9f5] px-2.5 text-xs">
                <option value="guitar">吉他 (Guitar)</option>
                <option value="ukulele">尤克里里 (Ukulele)</option>
                <option value="bass">贝斯 (Bass)</option>
              </select>
              <input
                type="file"
                accept=".ibe,.gp,.gp3,.gp4,.gp5,.gpx"
                disabled={busy}
                onchange={(event) => { selectedFile = event.currentTarget.files?.[0] ?? null; }}
                class="min-w-0 flex-1 text-xs"
              />
              <button
                type="button"
                class="btn btn-signal h-9 !px-4 text-xs font-semibold"
                disabled={busy || !selectedFile}
                onclick={importFile}
              >
                {busy ? '正在安全保存…' : '保存到我的谱'}
              </button>
            </div>
          </div>

          <!-- 已导入曲谱列表 -->
          <div class="space-y-4">
            <h3 class="font-display text-base font-semibold text-[#1a1816]">已导入曲谱 ({filteredPrivate.length})</h3>
            {#if privateScores.length === 0}
              <div class="card p-8 text-center text-sm text-ash shadow-xs">
                暂无本地导入的曲谱。在上方选择文件即可一键导入。
              </div>
            {:else if filteredPrivate.length === 0}
              <div class="card p-8 text-center text-sm text-ash shadow-xs">
                没有匹配“{localFilterText}”的导入曲谱。
              </div>
            {:else}
              <div class="grid gap-3 sm:grid-cols-2">
                {#each filteredPrivate as score (score.id)}
                  {@const practiceItem = data.practiceItems.find((item) => item.scoreId === score.id)}
                  <article class="card flex flex-col justify-between rounded-2xl border border-[#e8e2d4] bg-white p-4 shadow-2xs hover:shadow-xs transition-shadow">
                    <div>
                      <div class="flex items-center justify-between gap-2">
                        <h4 class="truncate font-display text-base font-semibold text-[#1a1816]">{score.title}</h4>
                        <span class="rounded bg-[#f0eae0] px-1.5 font-mono text-[10px] font-bold text-[#705c42]">{score.format.toUpperCase()}</span>
                      </div>
                      <p class="mt-1 text-xs text-[#705c42]">
                        {score.artist || '未知艺人'} · {score.category === 'ukulele' ? '尤克里里' : score.category === 'bass' ? '贝斯' : '吉他'} · 本机原件已持久化
                      </p>
                    </div>

                    <div class="mt-4 flex flex-wrap items-center gap-2 border-t border-[#f2ede4] pt-3">
                      {#if practiceItem && practiceItem.status !== 'archived'}
                        <a class="btn btn-signal h-8 !px-3 text-xs" href={`/practice?score=${encodeURIComponent(score.id)}`}>
                          打开练习
                        </a>
                      {:else}
                        <button type="button" class="btn btn-ghost h-8 !px-2.5 text-xs text-[#8c6d46]" disabled={busy} onclick={() => addPracticeFromScore(score)}>
                          {practiceItem?.status === 'archived' ? '恢复到待练' : '加入待练'}
                        </button>
                      {/if}
                    </div>
                  </article>
                {/each}
              </div>
            {/if}
          </div>
        </div>

      <!-- 4. 工坊工程 -->
      {:else if selectedTab === 'projects'}
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="font-display text-base font-semibold text-[#1a1816]">制谱工坊个人工程 ({filteredProjects.length})</h2>
              <p class="text-xs text-[#705c42]">在制谱工坊创作、改编的曲谱草稿，随时可生成可跟弹练习谱进入琴房。</p>
            </div>
            <a href="/studio" class="btn btn-signal h-8 !px-3 text-xs font-semibold">新建工坊谱 +</a>
          </div>

          {#if studioProjects.length === 0}
            <div class="card space-y-3 p-8 text-center text-ash shadow-xs">
              <div class="text-3xl">🎼</div>
              <p class="font-medium text-[#1a1816]">草稿箱中暂无个人工坊工程</p>
              <p class="text-xs">你可以在制谱工坊自由编配、改编曲谱，或从曲库点击“基于此谱改编”。</p>
              <a href="/studio" class="btn btn-signal h-9 text-xs">前往制谱工坊</a>
            </div>
          {:else if filteredProjects.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              没有匹配“{localFilterText}”的工坊工程。
            </div>
          {:else}
            <div class="grid gap-3 sm:grid-cols-2">
              {#each filteredProjects as project (project.id)}
                {@const scoreId = `project:${project.id}`}
                {@const practiceScore = scores.find((score) => score.id === scoreId)}
                {@const practiceItem = data.practiceItems.find((item) => item.scoreId === scoreId)}
                {@const isPractice = Boolean(practiceItem && practiceItem.status !== 'archived')}
                <article class="card flex flex-col justify-between rounded-2xl border border-[#e8e2d4] bg-white p-4 shadow-2xs hover:shadow-xs transition-shadow">
                  <div>
                    <div class="flex items-center justify-between gap-2">
                      <h3 class="truncate font-display text-base font-semibold text-[#1a1816]">{project.title || '未命名乐谱'}</h3>
                      <span class="rounded bg-[#f0eae0] px-1.5 font-mono text-[10px] text-[#705c42]">STUDIO</span>
                    </div>
                    <p class="mt-1 text-xs text-[#705c42]">
                      {project.artist || '原创作者'} · {project.tracks.length} 音轨 · {project.bars.length} 小节 · 本机工程
                    </p>
                  </div>

                  <div class="mt-4 flex flex-wrap items-center gap-2 border-t border-[#f2ede4] pt-3">
                    <a class="btn btn-ghost h-8 !px-2.5 text-xs" href={`/studio?project=${encodeURIComponent(project.id)}`}>
                      打开工坊编辑
                    </a>
                    {#if practiceScore && isPractice}
                      <a class="btn btn-ghost h-8 !px-2.5 text-xs" href={`/practice?score=${encodeURIComponent(scoreId)}`}>
                        打开练习
                      </a>
                    {/if}
                    <button
                      type="button"
                      class="btn btn-signal h-8 !px-3 text-xs"
                      disabled={busy}
                      onclick={() => addProjectToPractice(project.id)}
                    >
                      {isPractice ? '更新练习谱' : practiceItem?.status === 'archived' ? '恢复到待练' : '加入待练'}
                    </button>
                  </div>
                </article>
              {/each}
            </div>
          {/if}
        </div>

      <!-- 5. 已归档 -->
      {:else if selectedTab === 'archived'}
        <div class="space-y-4">
          <h2 class="font-display text-base font-semibold text-[#1a1816]">已归档曲谱 ({filteredArchived.length})</h2>
          {#if archivedPractice.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              暂无已归档曲谱。已掌握或暂时暂停的曲谱归档后会保留在这里，可随时一键恢复到待练队列。
            </div>
          {:else if filteredArchived.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              没有匹配“{localFilterText}”的归档曲谱。
            </div>
          {:else}
            <div class="divide-y divide-[#e8e2d4] card rounded-2xl border bg-white shadow-2xs">
              {#each filteredArchived as entry (entry.score.id)}
                <article class="flex flex-wrap items-center justify-between gap-3 p-4">
                  <div class="min-w-0">
                    <p class="truncate font-display font-medium text-[#1a1816]">{entry.score.title}</p>
                    <p class="text-xs text-[#705c42]">
                      {entry.score.artist || '未知艺人'} · {entry.item.note ? `备忘：${entry.item.note}` : '无备注'}
                    </p>
                  </div>
                  <div class="flex gap-2">
                    <button type="button" class="btn btn-ghost h-8 !px-3 text-xs font-medium text-[#2E6B47]" disabled={busy} onclick={() => updatePractice(entry.score.id, { status: 'todo' })}>
                      恢复到待练
                    </button>
                    <button type="button" class="btn btn-ghost h-8 !px-3 text-xs text-red-700 hover:bg-red-50" disabled={busy} onclick={() => removePractice(entry.score.id)}>
                      彻底移出
                    </button>
                  </div>
                </article>
              {/each}
            </div>
          {/if}
        </div>

      <!-- 6. 最近浏览 -->
      {:else if selectedTab === 'recent'}
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="font-display text-base font-semibold text-[#1a1816]">最近浏览历史 ({filteredHistory.length})</h2>
            {#if recentHistory.length > 0}
              <button type="button" class="btn btn-ghost h-8 !px-2.5 text-xs text-red-700 hover:bg-red-50" onclick={clearHistory}>
                清空浏览历史
              </button>
            {/if}
          </div>

          {#if recentHistory.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              暂无曲谱浏览记录。在曲库中打开曲谱后会自动记录于此。
            </div>
          {:else if filteredHistory.length === 0}
            <div class="card p-8 text-center text-sm text-ash shadow-xs">
              没有匹配“{localFilterText}”的历史记录。
            </div>
          {:else}
            <div class="grid gap-3 sm:grid-cols-2">
              {#each filteredHistory as item (item.url + '-' + item.time)}
                <a
                  href={item.url}
                  class="card group flex items-center justify-between rounded-2xl border border-[#e8e2d4] bg-white p-4 shadow-2xs hover:border-[#8c6d46] hover:shadow-xs transition-all"
                >
                  <div class="min-w-0 pr-3">
                    <h3 class="truncate font-display text-sm font-semibold text-[#1a1816] group-hover:text-[#8c6d46] transition-colors">{item.title}</h3>
                    <p class="mt-0.5 text-xs text-ash">{item.artist || '未知艺人'} · {new Date(item.time).toLocaleDateString()}</p>
                  </div>
                  <span class="text-xs text-[#8c6d46] group-hover:translate-x-0.5 transition-transform">→</span>
                </a>
              {/each}
            </div>
          {/if}
        </div>

      <!-- 7. 曲库查找 -->
      {:else if selectedTab === 'search'}
        <div class="space-y-4">
          <div class="card space-y-4 rounded-2xl border border-[#e8e2d4] bg-white p-5 sm:p-6 shadow-xs">
            <div>
              <h2 class="font-display text-base font-semibold text-[#1a1816]">曲库在线搜索与收藏</h2>
              <p class="mt-1 text-xs text-[#705c42]">
                从吉他与尤克里里曲库中实时检索曲目，可一键加入本设备收藏或直接加入待练队列。
              </p>
            </div>
            <form onsubmit={searchCatalog} class="flex flex-wrap gap-2">
              <select
                value={searchCategory}
                onchange={(event) => { searchCategory = event.currentTarget.value as typeof searchCategory; invalidateCatalogSearch(); }}
                aria-label="曲库搜索乐器"
                class="h-10 rounded-xl border border-[#e2dacd] bg-[#fbf9f5] px-3 text-xs"
              >
                <option value="guitar">吉他曲库</option>
                <option value="ukulele">尤克里里曲库</option>
              </select>
              <input
                value={query}
                oninput={(event) => { query = event.currentTarget.value; invalidateCatalogSearch(); }}
                type="search"
                placeholder="搜索曲谱名称、乐队或演奏歌手…"
                class="h-10 min-w-0 flex-1 rounded-xl border border-[#e2dacd] bg-[#fbf9f5] px-3.5 text-xs text-[#1a1816] placeholder-[#8c7b68]"
              />
              <button class="btn btn-signal h-10 !px-5 text-xs font-semibold" disabled={busy || searchBusy || !query.trim()}>
                {searchBusy ? '正在搜索…' : '搜索曲库'}
              </button>
            </form>

            {#if searchBusy}
              <p role="status" class="text-xs text-ash">正在曲库中检索“{query.trim()}”…</p>
            {/if}
            {#if searchError}
              <p role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-2.5 text-xs text-red-800">{searchError}</p>
            {/if}
            {#if resultSource === 'demo'}
              <p class="text-xs text-amber-800">当前曲库服务离线，显示内置演示曲目。</p>
            {/if}

            {#if results.length > 0}
              <div class="pt-2">
                <p role="status" class="mb-2 text-xs font-medium text-ash">找到 {results.length} 个结果：</p>
                <ul class="divide-y divide-[#e8e2d4] border-t border-[#e8e2d4]">
                  {#each results as row (row.id)}
                    <li class="flex flex-wrap items-center justify-between gap-3 py-3">
                      <div class="min-w-0">
                        <p class="truncate font-display font-medium text-[#1a1816]">{row.title}</p>
                        <p class="text-xs text-[#705c42]">
                          {row.artist || '未知艺人'} · {row.category === 'ukulele' ? '尤克里里' : '吉他'}
                          {row.format === 'xhe' || !row.scoreUrl ? ' · 仅可阅读' : ''}
                        </p>
                      </div>
                      <div class="flex items-center gap-2">
                        {#if row.source === 'catalog'}
                          <a class="btn btn-ghost h-8 !px-2.5 text-xs" href={`/${row.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(row.id)}`}>
                            打开曲谱
                          </a>
                        {/if}
                        <button type="button" class="btn btn-ghost h-8 !px-2.5 text-xs" disabled={busy || row.source !== 'catalog'} onclick={() => saveCatalog(row, 'favorite')}>
                          收藏
                        </button>
                        <button type="button" class="btn btn-signal h-8 !px-3 text-xs" disabled={busy || row.source !== 'catalog' || row.format === 'xhe' || !row.scoreUrl} onclick={() => saveCatalog(row, 'practice')}>
                          加入待练
                        </button>
                      </div>
                    </li>
                  {/each}
                </ul>
              </div>
            {/if}
          </div>
        </div>
      {/if}
    </div>
  {/if}
</section>
