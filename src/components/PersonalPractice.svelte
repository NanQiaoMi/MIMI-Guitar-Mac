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

  function isActivePracticeScore(source: PersonalData, scoreId: string): boolean {
    return source.practiceItems.some((item) => item.scoreId === scoreId && item.status !== 'archived');
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
      const requestedId = new URLSearchParams(location.search).get('score') ?? '';
      if (!isInitial && explicitRequestPending) { deferredDataReconcile = true; return; }
      const requestedIsActive = requestedId && isActivePracticeScore(next, requestedId);
      if (!isInitial && !requestedIsActive) return;
      const preferredId = isInitial ? preferredPracticeScoreId(next.practiceItems, requestedId) : requestedId;
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
      const requestedId = new URLSearchParams(location.search).get('score') ?? '';
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
      <div class="card space-y-3 p-8 text-center"><p class="font-medium">待练列表还是空的</p><p class="text-sm text-ash">先从曲库收藏或导入一份谱，随后加入待练。</p><a class="btn btn-signal" href="/library">打开我的谱</a></div>
    {/if}
    <PracticeReview {data} />
  {/if}
</section>
