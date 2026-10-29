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
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

</script>

<section class="personal-library space-y-8">
  {#if error}<p use:registerMotionSurface transition:surfaceMotion={{ kind: 'notice' }} role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</p>{/if}
  {#if notice}<p use:registerMotionSurface transition:surfaceMotion={{ kind: 'notice' }} role="status" class="rounded-xl border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">{notice}</p>{/if}
  {#if loading}<p class="card p-5 text-sm text-ash">正在读取本设备个人资料…</p>
  {:else if !data}<p class="card p-5 text-sm text-red-800">无法读取本地资料。刷新或检查浏览器存储权限；本页未使用临时内存代替保存。</p>
  {:else}
    <section class="card space-y-4 p-5 sm:p-6">
      <div><h2 class="font-display text-subheading">添加曲库曲谱</h2><p class="mt-1 text-sm text-ash">曲库搜索支持吉他与尤克里里；个人谱导入的乐器分类独立设置，仍可选择贝斯。搜索结果可保存为本设备上的真实曲库引用。</p></div>
      <form onsubmit={searchCatalog} class="flex flex-wrap gap-2">
        <select value={searchCategory} onchange={(event) => { searchCategory = event.currentTarget.value as typeof searchCategory; invalidateCatalogSearch(); }} aria-label="曲库搜索乐器" class="min-h-11 rounded-lg border hairline bg-paper px-3 py-2 text-sm"><option value="guitar">吉他曲库</option><option value="ukulele">尤克里里曲库</option></select>
        <input value={query} oninput={(event) => { query = event.currentTarget.value; invalidateCatalogSearch(); }} type="search" placeholder="曲名或艺人" class="min-h-11 min-w-0 flex-1 rounded-lg border hairline bg-paper px-3 py-2 text-sm" />
        <button class="btn btn-signal min-h-11" disabled={busy || searchBusy || !query.trim()}>{searchBusy ? '正在搜索…' : '搜索曲库'}</button>
      </form>
      {#if searchBusy}<p role="status" class="text-sm text-ash">正在搜索“{query.trim()}”…</p>{/if}
      {#if searchError}<p role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{searchError}</p>{/if}
      {#if resultSource === 'demo'}<p class="text-sm text-amber-800">当前为演示结果，无法保存为完整曲库引用。</p>{/if}
      {#if results.length}<p role="status" class="text-xs text-ash">显示 {results.length} 个搜索结果</p><ul class="divide-y divide-[#e8e2d4]">{#each results as row (row.id)}<li class="flex flex-wrap items-center justify-between gap-3 py-3"><div class="min-w-0"><p class="truncate font-medium">{row.title}</p><p class="text-xs text-ash">{row.artist || '未知艺人'} · {row.category}{row.format === 'xhe' || !row.scoreUrl ? ' · 仅可阅读' : ''}</p></div><div class="flex gap-2">{#if row.source === 'catalog'}<a class="btn btn-ghost min-h-11" href={`/${row.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(row.id)}`}>打开曲谱</a>{/if}<button type="button" class="btn btn-ghost min-h-11" disabled={busy || row.source !== 'catalog'} onclick={() => saveCatalog(row, 'favorite')}>收藏</button><button type="button" class="btn btn-ghost min-h-11" disabled={busy || row.source !== 'catalog' || row.format === 'xhe' || !row.scoreUrl} onclick={() => saveCatalog(row, 'practice')}>加入待练</button></div></li>{/each}</ul>{/if}
    </section>

    <section class="card space-y-4 p-5 sm:p-6">
      <div><h2 class="font-display text-subheading">导入个人谱</h2><p class="mt-1 text-sm text-ash">原始文件和可播放谱分别按 SHA-256 保存；解析或事务失败时不会替换现有资料。</p></div>
      <div class="flex flex-wrap gap-2">
        <select bind:value={importCategory} aria-label="个人谱导入分类" class="min-h-11 rounded-lg border hairline bg-paper px-3 py-2 text-sm"><option value="guitar">吉他</option><option value="ukulele">尤克里里</option><option value="bass">贝斯</option></select>
        <input type="file" accept=".ibe,.gp,.gp3,.gp4,.gp5,.gpx" disabled={busy} onchange={(event) => selectedFile = event.currentTarget.files?.[0] ?? null} class="min-w-0 flex-1 text-sm" />
        <button type="button" class="btn btn-signal min-h-11" disabled={busy || !selectedFile} onclick={importFile}>保存到我的谱</button>
      </div>
    </section>

    <section class="card space-y-3 p-5 sm:p-6">
      <h2 class="font-display text-subheading">待练</h2>
      {#if practice.length === 0}<p class="text-sm text-ash">还没有待练曲谱。可从上方搜索添加，或导入个人谱。</p>{/if}
      {#each practice as entry (entry.score.id)}
        {@const practiceIndex = practice.findIndex((candidate) => candidate.score.id === entry.score.id)}
        <article
          use:registerMotionSurface
          animate:flip={{ duration: motionMode === 'full' ? 180 : 0, easing: cubicOut }}
          in:surfaceMotion={{ kind: 'menu' }}
          out:fadeMotion={{ kind: 'menu' }}
          class="rounded-xl border hairline bg-paper p-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-3"><div><h3 class="font-medium">{entry.score.title}</h3><p class="mt-1 text-xs text-ash">{entry.score.artist || '未知艺人'} · {entry.score.source === 'private' ? '个人导入' : entry.score.source === 'project' ? '工坊练习谱' : '曲库引用'} · 顺序 {practiceIndex + 1}</p></div><div class="flex flex-wrap gap-2"><button type="button" class="btn btn-ghost min-h-[44px]" aria-label={`将《${entry.score.title}》上移`} disabled={busy || practiceIndex === 0} onclick={() => movePractice(entry.score.id, -1)}>上移</button><button type="button" class="btn btn-ghost min-h-[44px]" aria-label={`将《${entry.score.title}》下移`} disabled={busy || practiceIndex === practice.length - 1} onclick={() => movePractice(entry.score.id, 1)}>下移</button>{#if entry.score.source !== 'catalog' || (entry.score.format !== 'xhe' && entry.score.scoreUrl)}<a class="btn btn-signal min-h-[44px]" href={`/practice?score=${encodeURIComponent(entry.score.id)}`}>开始练习</a>{:else}<a class="btn btn-ghost min-h-[44px]" href={`/${entry.score.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(entry.score.sourceId)}`}>阅读文本谱</a>{/if}<button type="button" class="btn btn-ghost min-h-[44px]" disabled={busy} onclick={() => updatePractice(entry.score.id, { status: 'archived' })}>归档</button><button type="button" class="btn btn-ghost min-h-[44px]" disabled={busy} onclick={() => removePractice(entry.score.id)}>移出待练</button></div></div>
          <div class="mt-3 grid gap-2 sm:grid-cols-[12rem_1fr]">
            <select aria-label={`${entry.score.title}练习状态`} value={entry.item.status} disabled={busy} onchange={(event) => updatePractice(entry.score.id, { status: event.currentTarget.value as PracticeStatus })} class="min-h-[44px] rounded-lg border hairline bg-paper px-3 py-2 text-sm"><option value="todo">待练</option><option value="practicing">在练</option><option value="mastered">已掌握</option></select>
            <input aria-label={`${entry.score.title}备注`} value={noteDrafts[entry.score.id] ?? entry.item.note} disabled={busy} oninput={(event) => editPracticeNote(entry.score.id, entry.item.note, event.currentTarget.value)} placeholder="练习目标或难点" class="min-h-[44px] rounded-lg border hairline bg-paper px-3 py-2 text-sm" />
          </div>
          {#if noteDrafts[entry.score.id] !== undefined && (noteDrafts[entry.score.id] !== entry.item.note || noteSaveStates[entry.score.id] === 'conflict')}
            <div class="mt-2 flex flex-wrap items-center gap-2">
              <p role="status" class="min-h-11 flex items-center text-xs text-ash">
                {noteSaveStates[entry.score.id] === 'saving'
                  ? '正在保存备注…'
                  : noteSaveStates[entry.score.id] === 'conflict'
                    ? '备注已在其他页面更新。草稿仍保留，可复制；请取消草稿后再按当前备注重新编辑。'
                    : noteSaveStates[entry.score.id] === 'error'
                      ? `保存失败：${noteSaveErrors[entry.score.id] || '请重试。'}`
                      : '备注尚未保存。'}
              </p>
              {#if noteSaveStates[entry.score.id] !== 'conflict'}
                <button type="button" class="btn btn-signal min-h-11" disabled={busy} onclick={() => savePracticeNote(entry.score.id)}>{noteSaveStates[entry.score.id] === 'error' ? '重试保存' : '保存备注'}</button>
              {/if}
              <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={() => cancelPracticeNote(entry.score.id)}>{noteSaveStates[entry.score.id] === 'conflict' ? '取消草稿' : '取消更改'}</button>
            </div>
          {:else if noteSaveStates[entry.score.id] === 'saved'}
            <p role="status" class="mt-2 min-h-6 flex items-center text-xs text-ash">备注已保存。</p>
          {/if}
        </article>
      {/each}
    </section>

    <section class="card space-y-3 p-5 sm:p-6">
      <h2 class="font-display text-subheading">已归档</h2>
      {#if archivedPractice.length === 0}<p class="text-sm text-ash">归档的曲谱会保留在这里，可随时恢复到待练。</p>{/if}
      {#each archivedPractice as entry (entry.score.id)}
        <article use:registerMotionSurface in:surfaceMotion={{ kind: 'menu' }} out:fadeMotion={{ kind: 'menu' }} class="flex flex-wrap items-center justify-between gap-3 border-b border-[#e8e2d4] py-3 last:border-0">
          <div class="min-w-0"><p class="truncate font-medium">{entry.score.title}</p><p class="text-xs text-ash">{entry.score.artist || '未知艺人'} · {entry.item.note || '没有备注'}</p></div>
          <div class="flex gap-2"><button type="button" class="btn btn-ghost min-h-[44px]" disabled={busy} onclick={() => updatePractice(entry.score.id, { status: 'todo' })}>恢复到待练</button><button type="button" class="btn btn-ghost min-h-[44px]" disabled={busy} onclick={() => removePractice(entry.score.id)}>移出待练</button></div>
        </article>
      {/each}
    </section>

    <section class="card space-y-3 p-5 sm:p-6"><h2 class="font-display text-subheading">收藏</h2>
      {#if favorites.length === 0}<p class="text-sm text-ash">还没有收藏的曲谱。</p>{/if}
      {#each favorites as score (score.id)}
        {@const practiceItem = data.practiceItems.find((item) => item.scoreId === score.id)}
        <article use:registerMotionSurface in:surfaceMotion={{ kind: 'menu' }} out:fadeMotion={{ kind: 'menu' }} class="flex flex-wrap items-center justify-between gap-3 border-b border-[#e8e2d4] py-3 last:border-0">
          <div class="min-w-0"><p class="truncate font-medium">{score.title}</p><p class="text-xs text-ash">{score.artist || '未知艺人'}</p></div>
          <div class="flex flex-wrap gap-2">
            {#if score.source === 'catalog'}<a class="btn btn-ghost min-h-11" href={`/${score.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(score.sourceId)}`}>打开曲谱</a>{/if}
            {#if practiceItem && practiceItem.status !== 'archived'}
              <a class="btn btn-signal min-h-11" href={`/practice?score=${encodeURIComponent(score.id)}`}>已在待练 · 开始练习</a>
            {:else}
              <button type="button" class="btn btn-ghost min-h-11" disabled={busy || (score.source === 'catalog' && (score.format === 'xhe' || !score.scoreUrl))} onclick={() => addPracticeFromScore(score)}>{practiceItem?.status === 'archived' ? '恢复到待练' : '加入待练'}</button>
            {/if}
            <button type="button" class="btn btn-ghost min-h-11" disabled={busy} onclick={() => toggleFavorite(score.id)}>取消收藏</button>
          </div>
        </article>
      {/each}
    </section>

    <section class="card space-y-3 p-5 sm:p-6"><h2 class="font-display text-subheading">个人导入</h2>
      {#if privateScores.length === 0}<p class="text-sm text-ash">导入的个人谱将保存在这里。</p>{/if}
      {#each privateScores as score (score.id)}{@const practiceItem = data.practiceItems.find((item) => item.scoreId === score.id)}<article class="flex flex-wrap items-center justify-between gap-3 border-b border-[#e8e2d4] py-3 last:border-0"><div><p class="font-medium">{score.title}</p><p class="text-xs text-ash">{score.artist || '未知艺人'} · {score.format.toUpperCase()} · 原件与播放版本已保存</p></div><div class="flex gap-2">{#if practiceItem && practiceItem.status !== 'archived'}<a class="btn btn-ghost" href={`/practice?score=${encodeURIComponent(score.id)}`}>打开练习</a>{:else}<button type="button" class="btn btn-ghost" disabled={busy} onclick={() => addPracticeFromScore(score)}>{practiceItem?.status === 'archived' ? '恢复到待练' : '加入待练'}</button>{/if}</div></article>{/each}
    </section>

    <section class="card space-y-3 p-5 sm:p-6"><div><h2 class="font-display text-subheading">个人工坊工程</h2><p class="mt-1 text-sm text-ash">从这里继续编辑，或把保存版本转换为待练谱。导入原件单独保管。</p></div>
      {#if studioProjects.length === 0}<p class="text-sm text-ash">草稿箱中的个人工程会显示在这里。</p>{/if}
      {#each studioProjects as project (project.id)}
        {@const scoreId = `project:${project.id}`}
        {@const practiceScore = scores.find((score) => score.id === scoreId)}
        {@const practiceItem = data.practiceItems.find((item) => item.scoreId === scoreId)}
        {@const isPractice = Boolean(practiceItem && practiceItem.status !== 'archived')}
        <article class="flex flex-wrap items-center justify-between gap-3 border-b border-[#e8e2d4] py-3 last:border-0">
          <div class="min-w-0"><p class="truncate font-medium">{project.title || '未命名乐谱'}</p><p class="text-xs text-ash">{project.artist || '原创作者'} · {project.tracks.length} 条音轨 · {project.bars.length} 小节 · 本机个人工程</p></div>
          <div class="flex flex-wrap gap-2"><a class="btn btn-ghost" href={`/studio?project=${encodeURIComponent(project.id)}`}>打开工坊编辑</a>
            {#if practiceScore && isPractice}<a class="btn btn-ghost" href={`/practice?score=${encodeURIComponent(scoreId)}`}>打开练习</a>{/if}
            <button type="button" class="btn btn-signal" disabled={busy} onclick={() => addProjectToPractice(project.id)}>{isPractice ? '更新练习谱' : practiceItem?.status === 'archived' ? '恢复到待练' : '加入待练'}</button>
          </div>
        </article>
      {/each}
    </section>
  {/if}
</section>

<style>
  :global(.personal-library .btn),
  :global(.personal-library select),
  :global(.personal-library input:not([type='file'])) {
    min-height: 44px;
  }

  :global(.personal-library input[type='file']) {
    min-height: 44px;
  }
</style>
