<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { isApiFailureResponse, readApiErrorMessage } from '../lib/errorBoundary.ts';
  import { mutatePersonalData, readPersonalData, subscribePersonalData } from '../lib/personal/repository.ts';
  import type { PersonalData, PersonalScore } from '../lib/personal/types.ts';

  type LegacyTab = { id: string; title: string; artist?: string | null; category?: string; key?: string | null; heat?: number | null };
  let {
    initial = [], legacyEnabled = false, legacyUnavailable = false,
  }: { initial?: LegacyTab[]; legacyEnabled?: boolean; legacyUnavailable?: boolean } = $props();

  let data = $state<PersonalData | null>(null);
  let loading = $state(true);
  let busyId = $state('');
  let error = $state('');
  let notice = $state('');
  let legacyItems = $state<LegacyTab[]>(untrack(() => initial));
  const favorites = $derived((data?.scores ?? []).filter((score) => data?.favorites.includes(score.id)));

  onMount(() => {
    let active = true;
    const refresh = async () => {
      try {
        const next = await readPersonalData();
        if (active) { data = next; error = ''; }
      } catch (cause) {
        if (active) error = cause instanceof Error ? cause.message : '无法读取本设备收藏';
      } finally {
        if (active) loading = false;
      }
    };
    const unsubscribe = subscribePersonalData(() => { void refresh(); });
    void refresh();
    return () => { active = false; unsubscribe(); };
  });

  function scoreHref(score: PersonalScore): string {
    if (score.source !== 'catalog') return '/library';
    return `/${score.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(score.sourceId)}`;
  }

  async function removeLocal(scoreId: string) {
    if (busyId) return;
    busyId = scoreId; error = ''; notice = '';
    try {
      await mutatePersonalData((draft) => { draft.favorites = draft.favorites.filter((id) => id !== scoreId); });
      notice = '已从本设备收藏移除。';
    } catch (cause) {
      error = cause instanceof Error ? cause.message : '取消收藏未完成；本设备资料没有更改。';
    } finally { busyId = ''; }
  }

  async function removeLegacy(id: string) {
    if (busyId) return;
    busyId = `legacy:${id}`; error = ''; notice = '';
    try {
      const response = await fetch(`/api/favorites/${encodeURIComponent(id)}`, { method: 'DELETE', credentials: 'same-origin' });
      const payload = await response.json().catch(() => null);
      if (!response.ok || isApiFailureResponse(payload)) {
        throw new Error(readApiErrorMessage(payload, '旧版云端收藏未能取消，请稍后重试。'));
      }
      legacyItems = legacyItems.filter((item) => item.id !== id);
      notice = '已从旧版云端收藏移除；本设备收藏保持不变。';
    } catch (cause) {
      error = cause instanceof Error ? cause.message : '旧版云端收藏未能取消。';
    } finally { busyId = ''; }
  }
</script>

<div class="space-y-6">
  {#if error}<p role="alert" class="rounded-xl border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</p>{/if}
  {#if notice}<p role="status" class="rounded-xl border border-emerald-300 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">{notice}</p>{/if}

  <section id="favorites" class="space-y-3">
    <div><h2 class="font-display text-subheading">本设备收藏</h2><p class="mt-1 text-xs text-ash">与“我的谱”使用同一份本地个人资料，并包含在个人备份中。</p></div>
    {#if loading}<p class="card p-5 text-ash">正在读取本设备收藏…</p>
    {:else if !data}<p role="alert" class="card p-5 text-red-800">本设备资料不可用，收藏没有被临时替代保存。</p>
    {:else if favorites.length > 0}
      <ul class="grid grid-cols-1 gap-3 md:grid-cols-2">
        {#each favorites as score (score.id)}
          <li class="card flex items-center gap-4 p-4">
            <a href={scoreHref(score)} class="min-w-0 flex-1 transition hover:opacity-75">
              <p class="truncate font-medium">{score.title} <span class="text-ash font-normal">{score.artist ? `- ${score.artist}` : ''}</span></p>
              <p class="mt-1 text-caption text-ash">{score.source === 'catalog' ? `${score.category === 'ukulele' ? '尤克里里' : '曲库'} · 本设备引用` : '个人谱 · 本设备'}</p>
            </a>
            <button type="button" disabled={Boolean(busyId)} onclick={() => removeLocal(score.id)} class="btn shrink-0 disabled:opacity-50">取消收藏</button>
          </li>
        {/each}
      </ul>
    {:else}<div class="card flex h-32 items-center justify-center text-ash">还没有本设备收藏的曲谱</div>{/if}
  </section>

  {#if legacyEnabled}
    <section class="space-y-3 border-t hairline pt-5">
      <div><h2 class="font-display text-subheading">旧版云端收藏</h2><p class="mt-1 text-xs text-ash">这些条目仍保存在账号数据库中，没有自动迁入本设备收藏。两类收藏可以分别管理。</p></div>
      {#if legacyUnavailable}<p role="alert" class="rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">旧版云端收藏暂时无法读取；原有账号数据未更改。</p>
      {:else if legacyItems.length > 0}
        <ul class="grid grid-cols-1 gap-3 md:grid-cols-2">
          {#each legacyItems as tab (tab.id)}
            <li class="card flex items-center gap-4 p-4">
              <a href={`/${tab.category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(tab.id)}`} class="min-w-0 flex-1 transition hover:opacity-75">
                <p class="truncate font-medium">{tab.title} <span class="text-ash font-normal">{tab.artist ? `- ${tab.artist}` : ''}</span></p>
                <p class="mt-1 text-caption text-ash">{tab.key ?? '-'} 调 · {tab.heat ?? 0} 热度</p>
              </a>
              <button type="button" disabled={Boolean(busyId)} onclick={() => removeLegacy(tab.id)} class="btn shrink-0 disabled:opacity-50">取消旧版收藏</button>
            </li>
          {/each}
        </ul>
      {:else}<div class="card flex h-28 items-center justify-center text-ash">没有旧版云端收藏；本设备收藏见上方。</div>{/if}
    </section>
  {/if}
</div>
