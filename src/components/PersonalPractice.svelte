<script lang="ts">
  import { onMount } from 'svelte';
  import ScorePlayer from './player/ScorePlayer.svelte';
  import PracticeReview from './practice/PracticeReview.svelte';
  import { readPersonalData, mutatePersonalData, subscribePersonalData } from '../lib/personal/repository.ts';
  import { isSafeLocalPath } from '../lib/personal/validation.ts';
  import { readPlayableScoreAsset } from '../lib/personal/playableScoreAsset.ts';
  import { createLatestReadCoordinator, isVerifiedCatalogPromotion, matchesCatalogVerificationRecord, normalizePracticeQueue, preferredPracticeScoreId } from '../lib/personal/practiceQueue.ts';
  import { createPracticeLeaveGuardCoordinator } from '../lib/practice/practiceLeaveGuard.ts';
  import type { PersonalData, PersonalScore } from '../lib/personal/types.ts';

  let data = $state<PersonalData | null>(null);
  let selectedId = $state('');
  let selectedScore = $state<PersonalScore | null>(null);
  let playableUrl = $state('');
  let loading = $state(true);
  let error = $state('');
  let currentBlobUrl = '';
  let selectionGeneration = 0;
  let playerSelectionGeneration = $state(0);
  let playerMountKey = $state('');
  let mounted = true;
  let verificationStamp: { selectionGeneration: number; unverified: PersonalScore; verified: PersonalScore } | null = null;
  let pendingTransition = $state<{ key: string; message: string } | null>(null);
  let lastAutomaticTransitionKey = '';
  let explicitRequestSequence = 0;
  let explicitRequestPending = 0;
  let deferredDataReconcile = false;
  const leaveGuards = createPracticeLeaveGuardCoordinator();
  const activePracticeItems = $derived(normalizePracticeQueue(data?.practiceItems ?? []).filter((item) => item.status !== 'archived'));
  const scoreChoices = $derived(activePracticeItems.flatMap((item) => {
    const score = data?.scores.find((entry) => entry.id === item.scoreId);
    return score ? [score] : [];
  }));

  function sameScoreSourceIdentity(a: PersonalScore, b: PersonalScore): boolean {
    return a.id === b.id && a.source === b.source && a.sourceId === b.sourceId
      && a.format === b.format && a.category === b.category && a.scoreUrl === b.scoreUrl && a.assetId === b.assetId;
  }

  function sameScoreLoadIdentity(a: PersonalScore, b: PersonalScore): boolean {
    return sameScoreSourceIdentity(a, b) && a.revision === b.revision && a.category === b.category;
  }

  function verificationStampMatches(record: PersonalScore): boolean {
    const stamp = verificationStamp;
    return stamp !== null
      && stamp.selectionGeneration === selectionGeneration
      && selectedId === stamp.unverified.id
      && selectedScore?.revision === stamp.verified.revision
      && matchesCatalogVerificationRecord(stamp.unverified, stamp.verified, record, selectionGeneration, stamp.selectionGeneration);
  }

  function revokeCurrentUrl() {
    if (currentBlobUrl) URL.revokeObjectURL(currentBlobUrl);
    currentBlobUrl = '';
    playableUrl = '';
  }

  function normalizeScoreParam(raw: string | null): string {
    if (!raw) return '';
    const trimmed = raw.trim();
    if (!trimmed) return '';
    if (trimmed.startsWith('catalog:') || trimmed.startsWith('private:') || trimmed.startsWith('project:')) {
      return trimmed;
    }
    return `catalog:${trimmed}`;
  }

  function isActivePracticeScore(source: PersonalData, scoreId: string): boolean {
    if (!scoreId) return false;
    const normalized = normalizeScoreParam(scoreId);
    return source.practiceItems.some((item) => (item.scoreId === scoreId || item.scoreId === normalized) && item.status !== 'archived');
  }

  function scoreTransitionKey(score: PersonalScore | null, scoreId: string, status: string): string {
    if (!score) return `${scoreId}:missing`;
    return JSON.stringify([
      scoreId, status, score.source, score.sourceId, score.format, score.category,
      score.scoreUrl ?? '', score.assetId ?? '', score.revision,
    ]);
  }

  function restoreUrlToConfirmedSelection() {
    const url = new URL(window.location.href);
    if (selectedId) url.searchParams.set('score', selectedId);
    else url.searchParams.delete('score');
    history.replaceState({}, '', url.pathname + url.search + url.hash);
  }

  function markCurrentTransitionFromData(source: PersonalData): { key: string; message: string; apply: () => void | Promise<void> } | null {
    const currentId = selectedId;
    if (!currentId) return null;
    const score = source.scores.find((item) => item.id === currentId) ?? null;
    const queueItem = source.practiceItems.find((item) => item.scoreId === currentId);
    const active = Boolean(queueItem && queueItem.status !== 'archived');
    if (!score || !active) {
      const archived = Boolean(score && queueItem?.status === 'archived');
      return {
        key: scoreTransitionKey(score, currentId, archived ? 'archived' : 'removed'),
        message: archived
          ? '这首曲谱已归档；当前仍显示原练习版本，待保存或取消当前备注后才会应用变更。'
          : '这首曲谱已从待练或本机资料移除；当前仍显示原练习版本，变更尚未应用。',
        apply: () => clearCurrentSelection(archived ? '这份曲谱已归档，请先从“我的谱”恢复到待练。' : '这份曲谱已从待练队列移除或归档。'),
      };
    }

    if (!selectedScore || !sameScoreLoadIdentity(selectedScore, score)) {
      return {
        key: scoreTransitionKey(score, currentId, 'changed'),
        message: '曲谱来源或版本已更新；当前仍显示原练习版本，变更尚未应用。',
        apply: () => selectScore(currentId, true),
      };
    }
    return null;
  }

  function requestAutomaticTransition(transition: { key: string; message: string; apply: () => void | Promise<void> }, retry = false) {
    if (explicitRequestPending) {
      deferredDataReconcile = true;
      return;
    }
    if (!retry && lastAutomaticTransitionKey === transition.key) return;
    lastAutomaticTransitionKey = transition.key;
    pendingTransition = { key: transition.key, message: transition.message };
    void leaveGuards.requestSelection(transition.apply).then((committed) => {
      if (lastAutomaticTransitionKey !== transition.key) return;
      if (committed) {
        lastAutomaticTransitionKey = '';
        pendingTransition = null;
      } else {
        pendingTransition = { key: transition.key, message: transition.message };
      }
    }).catch((cause) => {
      if (lastAutomaticTransitionKey !== transition.key) return;
      pendingTransition = { key: transition.key, message: transition.message };
      error = cause instanceof Error ? cause.message : String(cause);
    });
  }

  function reconcileCurrentTransition(showOnly = false) {
    if (!data) return;
    const transition = markCurrentTransitionFromData(data);
    if (!transition) {
      pendingTransition = null;
      lastAutomaticTransitionKey = '';
      return;
    }
    if (showOnly) {
      pendingTransition = { key: transition.key, message: transition.message };
      lastAutomaticTransitionKey = transition.key;
      return;
    }
    requestAutomaticTransition(transition);
  }

  async function requestExplicitSelection(scoreId: string, options: { fromHistory?: boolean } = {}) {
    if (scoreId === selectedId) {
      if (explicitRequestPending) {
        explicitRequestSequence++;
        explicitRequestPending = 0;
        leaveGuards.invalidate();
        deferredDataReconcile = false;
        lastAutomaticTransitionKey = '';
        pendingTransition = null;
        error = '';
      }
      return;
    }
    const requestId = ++explicitRequestSequence;
    explicitRequestPending = requestId;
    deferredDataReconcile = false;
    lastAutomaticTransitionKey = '';
    pendingTransition = null;
    error = '';
    const action = scoreId
      ? () => selectScore(scoreId, Boolean(options.fromHistory))
      : () => selectScore('', Boolean(options.fromHistory));
    let committed = false;
    try {
      committed = await leaveGuards.requestSelection(action);
    } catch (cause) {
      error = cause instanceof Error ? cause.message : String(cause);
    }
    if (explicitRequestPending !== requestId) return;
    explicitRequestPending = 0;
    if (!committed) {
      error = '曲谱没有切换，当前播放器和备注仍保留。请先修正或取消备注，再重试。';
      if (options.fromHistory) restoreUrlToConfirmedSelection();
      reconcileCurrentTransition(true);
    } else {
      pendingTransition = null;
      lastAutomaticTransitionKey = '';
      if (deferredDataReconcile) reconcileCurrentTransition();
    }
    deferredDataReconcile = false;
  }

  function handlePracticeScoreSelectionChange(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    const requestedId = select.value;
    select.value = selectedId;
    void requestExplicitSelection(requestedId);
  }

  async function selectScore(scoreId: string, initial = false) {
    const generation = ++selectionGeneration;
    playerSelectionGeneration = generation;
    verificationStamp = null;
    error = '';
    selectedScore = null;
    revokeCurrentUrl();
    playerMountKey = '';
    if (!scoreId) {
      selectedId = '';
      if (!initial) {
        const url = new URL(window.location.href);
        url.searchParams.delete('score');
        history.pushState({}, '', url.pathname + url.search);
      }
      return;
    }
    if (!data?.practiceItems.some((item) => item.scoreId === scoreId && item.status !== 'archived')) {
      selectedId = scoreId;
      error = data?.scores.some((item) => item.id === scoreId)
        ? '这份曲谱已归档，请先从“我的谱”恢复到待练。'
        : '请求的曲谱已从本设备资料移除，或尚未加入待练。';
      return;
    }
    selectedId = scoreId;
    const score = data?.scores.find((item) => item.id === scoreId);
    if (!score) { selectedScore = null; error = '没有找到这份个人曲谱。'; return; }
    selectedScore = score;
    if (score.source !== 'catalog') {
      try {
        const asset = await readPlayableScoreAsset(score, () => generation === selectionGeneration && data?.scores.some((item) => item.id === score.id && item.revision === score.revision && item.assetId === score.assetId) === true);
        if (!asset || generation !== selectionGeneration) return;
        currentBlobUrl = URL.createObjectURL(new Blob([asset.bytes], { type: asset.mimeType }));
        playableUrl = currentBlobUrl;
      } catch (cause) { if (generation === selectionGeneration) error = cause instanceof Error ? cause.message : String(cause); }
    } else {
      if (score.scoreUrl && isSafeLocalPath(score.scoreUrl)) {
        playableUrl = score.scoreUrl;
      } else if (score.format !== 'xhe') {
        playableUrl = `/api/tabs/${encodeURIComponent(score.sourceId)}/download`;
      } else {
        error = '这份曲库曲谱没有可播放的下载文件。';
      }
    }
    if (generation !== selectionGeneration) return;
    playerMountKey = `${generation}:${score.id}:${score.source}:${score.sourceId}:${score.format}:${score.revision}:${score.scoreUrl ?? ''}:${score.assetId ?? ''}:${playableUrl}`;
    if (!initial) {
      const url = new URL(window.location.href);
      url.searchParams.set('score', score.id);
      history.pushState({}, '', url.pathname + url.search);
    }
  }

  function clearCurrentSelection(message: string) {
    selectionGeneration++;
    playerSelectionGeneration = selectionGeneration;
    verificationStamp = null;
    selectedId = '';
    selectedScore = null;
    revokeCurrentUrl();
    playerMountKey = '';
    error = message;
  }

  function applySubscribedData(next: PersonalData, isInitial: boolean) {
    const currentId = selectedId;
    data = next;
    loading = false;
    if (!currentId) {
      const urlParams = new URLSearchParams(location.search);
      const requestedId = normalizeScoreParam(urlParams.get('score') ?? urlParams.get('tabId'));
      if (!isInitial && explicitRequestPending) { deferredDataReconcile = true; return; }
      const requestedIsActive = requestedId && isActivePracticeScore(next, requestedId);
      if (!isInitial && !requestedIsActive) return;
      const preferredId = isInitial ? (requestedIsActive ? requestedId : preferredPracticeScoreId(next.practiceItems, requestedId)) : requestedId;
      if (preferredId) void selectScore(preferredId, true);
      return;
    }
    const selected = currentId ? next.scores.find((item) => item.id === currentId) ?? null : null;
    const stillActive = currentId && next.practiceItems.some((item) => item.scoreId === currentId && item.status !== 'archived');
    if (!selected || !stillActive) {
      if (explicitRequestPending) { deferredDataReconcile = true; return; }
      const transition = markCurrentTransitionFromData(next);
      if (transition) requestAutomaticTransition(transition);
      return;
    }
    if (verificationStampMatches(selected)) {
      const synchronized = { ...selected, revision: verificationStamp!.verified.revision };
      selectedScore = synchronized;
      if (selected.revision === 'unverified') {
        data = { ...next, scores: next.scores.map((score) => score.id === synchronized.id ? synchronized : score) };
      }
      return;
    }
    const previous = selectedScore;
    const changed = !previous || !sameScoreLoadIdentity(previous, selected);
    if (changed) {
      if (explicitRequestPending) { deferredDataReconcile = true; return; }
      const transition = markCurrentTransitionFromData(next);
      if (transition) requestAutomaticTransition(transition);
      return;
    }
    if (!explicitRequestPending && pendingTransition) {
      leaveGuards.invalidate();
      pendingTransition = null;
      lastAutomaticTransitionKey = '';
    }
    selectedScore = selected;
  }

  async function persistVerifiedCatalogScore(verified: PersonalScore, generation: number) {
    let matched = false;
    const persisted = await mutatePersonalData((draft) => {
      if (!mounted || generation !== selectionGeneration || selectedId !== verified.id) return;
      const stored = draft.scores.find((item) => item.id === verified.id);
      if (!stored || !sameScoreSourceIdentity(stored, verified)) return;
      if (stored.revision === verified.revision) { matched = true; return; }
      if (!isVerifiedCatalogPromotion(stored, verified, generation, generation)) return;
      stored.revision = verified.revision;
      stored.updatedAt = Date.now();
      matched = true;
    });
    if (!mounted || generation !== selectionGeneration) return;
    if (matched) return;
    data = persisted;
    const transition = markCurrentTransitionFromData(persisted);
    if (transition) requestAutomaticTransition(transition);
  }

  function handlePracticeScoreVerified(verified: PersonalScore, generation: number) {
    const current = selectedScore;
    const stored = data?.scores.find((score) => score.id === current?.id) ?? null;
    if (!current || pendingTransition || !stored || !sameScoreLoadIdentity(current, stored)
      || !isVerifiedCatalogPromotion(current, verified, selectionGeneration, generation)) return;
    const parentVerified = { ...current, revision: verified.revision };
    verificationStamp = { selectionGeneration: generation, unverified: { ...current }, verified: parentVerified };
    selectedScore = parentVerified;
    if (data) data = { ...data, scores: data.scores.map((score) => score.id === current.id ? parentVerified : score) };
    void persistVerifiedCatalogScore(parentVerified, generation).catch((cause) => {
      if (mounted && generation === selectionGeneration) error = cause instanceof Error ? cause.message : String(cause);
    });
  }

  function practiceScoreVerifiedHandler(generation: number) {
    return (verified: PersonalScore) => handlePracticeScoreVerified(verified, generation);
  }

  const dataReads = createLatestReadCoordinator<PersonalData>(
    readPersonalData,
    (next, isInitial) => applySubscribedData(next, isInitial),
    (cause) => { error = cause instanceof Error ? cause.message : String(cause); loading = false; },
  );

  onMount(() => {
    mounted = true;
    const unsubscribe = subscribePersonalData(() => {
      if (!mounted) return;
      void dataReads.refresh();
    });
    void dataReads.refresh();
    const pop = () => {
      const urlParams = new URLSearchParams(location.search);
      const requestedId = normalizeScoreParam(urlParams.get('score') ?? urlParams.get('tabId'));
      if (requestedId && data && !isActivePracticeScore(data, requestedId)) {
        error = '历史记录中的曲谱当前不在待练列表，已保留当前练习。';
        restoreUrlToConfirmedSelection();
        return;
      }
      if (requestedId !== selectedId) void requestExplicitSelection(requestedId, { fromHistory: true });
    };
    window.addEventListener('popstate', pop);
    return () => {
      mounted = false;
      dataReads.dispose();
      selectionGeneration++;
      playerSelectionGeneration = selectionGeneration;
      verificationStamp = null;
      unsubscribe();
      window.removeEventListener('popstate', pop);
      revokeCurrentUrl();
    };
  });
</script>

<section class="space-y-5">
  {#if error}<p role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</p>{/if}
  {#if loading}<p class="card p-5 text-sm text-ash">正在读取待练曲谱…</p>
  {:else if !data}<p class="card p-5 text-sm text-red-800">本地资料不可用，无法载入练习曲谱。</p>
  {:else}
    <div class="card flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
      <label class="flex min-w-0 flex-1 items-center gap-3 text-sm"><span class="shrink-0 font-medium">选择练习曲谱</span><select value={selectedId} onchange={handlePracticeScoreSelectionChange} class="min-h-[44px] min-w-0 flex-1 rounded-lg border hairline bg-paper px-3 py-2"><option value="">选择一首待练曲谱</option>{#if selectedId && !scoreChoices.some((score) => score.id === selectedId)}<option value={selectedId}>当前曲目待处理</option>{/if}{#each scoreChoices as score (score.id)}<option value={score.id}>{score.title}{score.artist ? ` · ${score.artist}` : ''}</option>{/each}</select></label>
      <a href="/library" class="btn btn-ghost min-h-[44px]">管理我的谱</a>
    </div>
    {#if pendingTransition}<div class="rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-950" role="status"><p>{pendingTransition.message}</p><button class="btn btn-ghost mt-2 min-h-[44px] !px-3" onclick={() => { const transition = data ? markCurrentTransitionFromData(data) : null; if (transition) requestAutomaticTransition(transition, true); }}>应用资料更新</button></div>{/if}
    {#if selectedScore && playableUrl}
      {#key playerMountKey}<ScorePlayer scoreUrl={playableUrl} title={selectedScore.title} artist={selectedScore.artist} category={selectedScore.category} practiceScore={selectedScore} onPracticeScoreVerified={practiceScoreVerifiedHandler(playerSelectionGeneration)} onRegisterPracticeLeaveGuard={leaveGuards.register} />{/key}
    {:else if scoreChoices.length === 0}
      <!-- 琴房启航中心 (空态深度激活) -->
      <div class="space-y-6">
        <!-- 主迎新卡片 -->
        <div class="card space-y-4 p-8 text-center sm:p-10">
          <div class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-[#f4ece0] text-3xl text-[#8c6d38] shadow-inner">
            🎸
          </div>
          <div class="space-y-1">
            <h2 class="font-display text-xl font-semibold text-[#24201d]">琴房已就绪 · 开启你的今日练习</h2>
            <p class="mx-auto max-w-xl text-sm leading-6 text-ash">
              挑选一首心仪的曲谱加入待练，在这里你可以慢速跟弹、圈定小节循环击破卡点，伴奏时段将实时自动沉淀为练习记录。
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-center gap-3 pt-2">
            <a class="btn btn-signal min-h-[42px] px-5" href="/tabs">✨ 探索精选曲库</a>
            <a class="btn btn-ghost min-h-[42px] px-5" href="/library">📥 导入本地吉他谱</a>
            <a class="btn btn-ghost min-h-[42px] px-5" href="/article">📖 阅读指弹技巧</a>
          </div>
        </div>

        <!-- 经典热身与精选练习曲推荐 -->
        <div class="card space-y-4 p-6 sm:p-7">
          <div class="flex flex-wrap items-baseline justify-between gap-2 border-b border-[#ebd8bc]/40 pb-3">
            <div>
              <h3 class="font-display text-base font-semibold text-[#24201d]">⭐ 经典热身与精选练习曲推荐</h3>
              <p class="text-xs text-ash">不知道练什么？试试这几首广受好评的练手曲谱，点击即可直接去曲库开启</p>
            </div>
            <a href="/tabs" class="text-xs font-medium text-[#8c6d38] hover:underline">浏览全部曲库 →</a>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <div class="rounded-xl border hairline bg-[#fcfaf7] p-4 transition-all hover:border-[#c49a45]/50 hover:shadow-sm">
              <div class="flex items-start justify-between">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="rounded bg-[#f0e6d6] px-1.5 py-0.5 text-[10px] font-medium text-[#7d5e2d]">和弦分解</span>
                    <span class="font-mono text-xs text-ash">D大调 · 75 BPM</span>
                  </div>
                  <h4 class="mt-1 font-display text-base font-semibold text-[#24201d]">卡农 (Canon in D)</h4>
                  <p class="text-xs text-ash">帕赫贝尔</p>
                </div>
                <div class="text-xs text-[#c49a45]">★★★☆☆</div>
              </div>
              <p class="mt-2 text-xs leading-5 text-[#584a3b]">黄金和弦走向与右手琶音轮指经典练习，培养双手声部呼吸感。</p>
              <div class="mt-3 flex items-center gap-2">
                <a href="/tabs?q=卡农" class="btn btn-signal min-h-[34px] !px-3 text-xs">去曲库练这首</a>
              </div>
            </div>

            <div class="rounded-xl border hairline bg-[#fcfaf7] p-4 transition-all hover:border-[#c49a45]/50 hover:shadow-sm">
              <div class="flex items-start justify-between">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="rounded bg-[#f0e6d6] px-1.5 py-0.5 text-[10px] font-medium text-[#7d5e2d]">古典指弹</span>
                    <span class="font-mono text-xs text-ash">G大调 · 84 BPM</span>
                  </div>
                  <h4 class="mt-1 font-display text-base font-semibold text-[#24201d]">G大调小步舞曲</h4>
                  <p class="text-xs text-ash">巴赫</p>
                </div>
                <div class="text-xs text-[#c49a45]">★★☆☆☆</div>
              </div>
              <p class="mt-2 text-xs leading-5 text-[#584a3b]">复调独立旋律线条，训练左手指尖独立力量与把位移动平稳性。</p>
              <div class="mt-3 flex items-center gap-2">
                <a href="/tabs?q=小步舞曲" class="btn btn-signal min-h-[34px] !px-3 text-xs">去曲库练这首</a>
              </div>
            </div>

            <div class="rounded-xl border hairline bg-[#fcfaf7] p-4 transition-all hover:border-[#c49a45]/50 hover:shadow-sm">
              <div class="flex items-start justify-between">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="rounded bg-[#f0e6d6] px-1.5 py-0.5 text-[10px] font-medium text-[#7d5e2d]">轮指抒情</span>
                    <span class="font-mono text-xs text-ash">Em调 · 66 BPM</span>
                  </div>
                  <h4 class="mt-1 font-display text-base font-semibold text-[#24201d]">爱的罗曼史 (Romance)</h4>
                  <p class="text-xs text-ash">西班牙名曲</p>
                </div>
                <div class="text-xs text-[#c49a45]">★★☆☆☆</div>
              </div>
              <p class="mt-2 text-xs leading-5 text-[#584a3b]">高低音声部呼应，练习右手连弹的力度层次与圆润温和的音色控制。</p>
              <div class="mt-3 flex items-center gap-2">
                <a href="/tabs?q=爱的罗曼史" class="btn btn-signal min-h-[34px] !px-3 text-xs">去曲库练这首</a>
              </div>
            </div>

            <div class="rounded-xl border hairline bg-[#fcfaf7] p-4 transition-all hover:border-[#c49a45]/50 hover:shadow-sm">
              <div class="flex items-start justify-between">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="rounded bg-[#f0e6d6] px-1.5 py-0.5 text-[10px] font-medium text-[#7d5e2d]">流行指弹</span>
                    <span class="font-mono text-xs text-ash">Am调 · 68 BPM</span>
                  </div>
                  <h4 class="mt-1 font-display text-base font-semibold text-[#24201d]">天空之城 (Carrying You)</h4>
                  <p class="text-xs text-ash">久石让</p>
                </div>
                <div class="text-xs text-[#c49a45]">★★☆☆☆</div>
              </div>
              <p class="mt-2 text-xs leading-5 text-[#584a3b]">优美动听的旋律与基础和弦结合，适合慢弹感受每一个音符的延展。</p>
              <div class="mt-3 flex items-center gap-2">
                <a href="/tabs?q=天空之城" class="btn btn-signal min-h-[34px] !px-3 text-xs">去曲库练这首</a>
              </div>
            </div>
          </div>
        </div>

        <!-- 基础和弦转换热身卡 -->
        <div class="card space-y-4 p-6 sm:p-7">
          <div class="flex items-baseline justify-between gap-2 border-b border-[#ebd8bc]/40 pb-3">
            <div>
              <h3 class="font-display text-base font-semibold text-[#24201d]">🖐️ 开琴 5 分钟 · 基础核心和弦转换热身</h3>
              <p class="text-xs text-ash">每天弹唱与指弹前，顺畅转换这组万能和弦，快速唤醒左手指尖肌肉记忆</p>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-6">
            <div class="rounded-xl border hairline bg-[#faf7f0] p-3 text-left">
              <div class="font-display text-xl font-bold text-[#24201d]">C</div>
              <div class="mt-1 font-mono text-[11px] font-medium text-[#8c6d38]">X 3 2 0 1 0</div>
              <p class="mt-1 text-[11px] text-ash">主和弦 · 明净开阔</p>
            </div>
            <div class="rounded-xl border hairline bg-[#faf7f0] p-3 text-left">
              <div class="font-display text-xl font-bold text-[#24201d]">G</div>
              <div class="mt-1 font-mono text-[11px] font-medium text-[#8c6d38]">3 2 0 0 0 3</div>
              <p class="mt-1 text-[11px] text-ash">属和弦 · 宏亮饱满</p>
            </div>
            <div class="rounded-xl border hairline bg-[#faf7f0] p-3 text-left">
              <div class="font-display text-xl font-bold text-[#24201d]">Am</div>
              <div class="mt-1 font-mono text-[11px] font-medium text-[#8c6d38]">X 0 2 2 1 0</div>
              <p class="mt-1 text-[11px] text-ash">小调柔和 · 抒情灵魂</p>
            </div>
            <div class="rounded-xl border hairline bg-[#faf7f0] p-3 text-left">
              <div class="font-display text-xl font-bold text-[#24201d]">Em</div>
              <div class="mt-1 font-mono text-[11px] font-medium text-[#8c6d38]">0 2 2 0 0 0</div>
              <p class="mt-1 text-[11px] text-ash">空灵低沉 · 指弹基石</p>
            </div>
            <div class="rounded-xl border hairline bg-[#faf7f0] p-3 text-left">
              <div class="font-display text-xl font-bold text-[#24201d]">Fmaj7</div>
              <div class="mt-1 font-mono text-[11px] font-medium text-[#8c6d38]">X X 3 2 1 0</div>
              <p class="mt-1 text-[11px] text-ash">优雅色彩 · 大横按替代</p>
            </div>
            <div class="rounded-xl border hairline bg-[#faf7f0] p-3 text-left">
              <div class="font-display text-xl font-bold text-[#24201d]">Dm</div>
              <div class="mt-1 font-mono text-[11px] font-medium text-[#8c6d38]">X X 0 2 3 1</div>
              <p class="mt-1 text-[11px] text-ash">细腻过渡 · 指距跨越</p>
            </div>
          </div>
        </div>

        <!-- 练琴好搭档与科学方法论 -->
        <div class="grid gap-4 md:grid-cols-2">
          <div class="card space-y-2 p-5">
            <h4 class="font-display text-sm font-semibold text-[#24201d]">⏱ 常见节拍速度参考 (BPM)</h4>
            <p class="text-xs text-ash">选曲或慢练时，根据 BPM 预估律动与按弦难度：</p>
            <div class="flex flex-wrap gap-2 pt-1">
              <span class="rounded-lg bg-[#f5ede0] px-3 py-1.5 text-xs text-[#584a3b]"><strong class="text-[#24201d]">60 BPM</strong> 抒情慢板</span>
              <span class="rounded-lg bg-[#f5ede0] px-3 py-1.5 text-xs text-[#584a3b]"><strong class="text-[#24201d]">80 BPM</strong> 流行中速</span>
              <span class="rounded-lg bg-[#f5ede0] px-3 py-1.5 text-xs text-[#584a3b]"><strong class="text-[#24201d]">100 BPM</strong> 动感扫弦</span>
              <span class="rounded-lg bg-[#f5ede0] px-3 py-1.5 text-xs text-[#584a3b]"><strong class="text-[#24201d]">120 BPM</strong> 快速轻快</span>
            </div>
          </div>
          <div class="card space-y-2 p-5">
            <h4 class="font-display text-sm font-semibold text-[#24201d]">🎯 科学慢练三步法</h4>
            <ul class="space-y-1 text-xs text-[#584a3b]">
              <li><strong>1. 听觉记忆：</strong>先原速完整听一遍伴奏，找准旋律呼吸感</li>
              <li><strong>2. 难点切片：</strong>圈定卡手小节开启 2 节循环慢练跟弹</li>
              <li><strong>3. 梯形提速：</strong>从 50% 速度起步，连弹 3 遍无失误再 +5 BPM</li>
            </ul>
          </div>
        </div>
      </div>
    {/if}
    <PracticeReview {data} />
  {/if}
</section>
