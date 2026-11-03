<script lang="ts">
  import { onMount } from 'svelte';
  import { addCatalogFavorite, addCatalogPractice, type CatalogScoreInput } from '../lib/personal/catalog.ts';
  import { readPersonalData, subscribePersonalData, mutatePersonalData } from '../lib/personal/repository.ts';
  import { normalizePracticeQueue } from '../lib/personal/practiceQueue.ts';

  let {
    tabId = '', initialCount = 0, title = '', artist = '', category = 'guitar', scoreUrl = '', format = 'ibe', catalogAvailable = true,
  }: {
    tabId?: string; initialCount?: number; title?: string; artist?: string; category?: string; scoreUrl?: string; format?: string; catalogAvailable?: boolean;
  } = $props();

  let favorited = $state(false);
  let queued = $state(false);
  let busy = $state(false);
  let error = $state('');
  let notice = $state('');
  let ready = $state(false);
  const metadataReady = $derived(Boolean(tabId && title.trim()));
  const practiceAvailable = $derived(catalogAvailable && format.toLowerCase() !== 'xhe' && Boolean(scoreUrl));
  const input = $derived<CatalogScoreInput>({ id: tabId, title, artist, category, format, scoreUrl: scoreUrl || undefined });

  async function refresh() {
    if (!metadataReady) return;
    try {
      const data = await readPersonalData();
      favorited = data.favorites.includes(`catalog:${tabId}`);
      queued = data.practiceItems.some((item) => item.scoreId === `catalog:${tabId}` && item.status !== 'archived');
      ready = true;
    } catch {
      ready = true;
    }
  }

  onMount(() => {
    let active = true;
    const unsubscribe = subscribePersonalData(() => {
      if (active) void refresh().catch((cause) => { error = cause instanceof Error ? cause.message : String(cause); });
    });
    void refresh().catch((cause) => { error = cause instanceof Error ? cause.message : String(cause); ready = true; });
    return () => { active = false; unsubscribe(); };
  });

  async function toggleFavorite() {
    if (busy || !metadataReady) return;
    if (!favorited && !catalogAvailable) { error = '演示结果不能保存为真实曲库引用。'; return; }
    busy = true; error = ''; notice = '';
    try {
      await addCatalogFavorite(input, !favorited);
      favorited = !favorited;
      notice = favorited ? '已保存到本设备收藏' : '已从本设备收藏移除';
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function togglePractice() {
    if (busy || !metadataReady || !practiceAvailable) return;
    busy = true; error = ''; notice = '';
    try {
      if (queued) {
        await mutatePersonalData((draft) => {
          draft.practiceItems = normalizePracticeQueue(draft.practiceItems.filter((item) => item.scoreId !== `catalog:${tabId}`));
        });
        queued = false;
        notice = '已移出待练列表';
      } else {
        await addCatalogPractice(input);
        queued = true;
        notice = '已加入本设备待练';
      }
    } catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }

  async function startPractice() {
    if (busy || !metadataReady) return;
    busy = true; error = ''; notice = '';
    try {
      if (!queued && practiceAvailable) {
        await addCatalogPractice(input);
        queued = true;
      }
      window.location.href = `/practice?score=${encodeURIComponent('catalog:' + tabId)}`;
    } catch (cause) {
      error = cause instanceof Error ? cause.message : String(cause);
      busy = false;
    }
  }
</script>

<div class="flex flex-wrap items-center gap-2">
  <!-- 收藏按钮 -->
  <button
    type="button"
    onclick={toggleFavorite}
    disabled={busy || !metadataReady || !ready}
    class="btn group inline-flex h-9 items-center gap-1.5 rounded-full border px-3.5 text-xs font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 {favorited ? 'border-red-300 bg-red-50 text-red-700 shadow-2xs' : 'border-[#e2dacd] bg-white text-[#584a3b] hover:border-[#c49a45] hover:bg-[#faf7f2]'}"
    aria-pressed={favorited}
    aria-label={favorited ? '已收藏到本设备' : '收藏这首曲谱'}
    title={!metadataReady ? '曲谱元数据暂不可用' : favorited ? '已收藏到本设备，点击取消' : '收藏保存在本设备'}
  >
    <span aria-hidden="true" class="text-sm {favorited ? 'text-red-600' : 'text-[#8c7b68]'}">{favorited ? '♥' : '♡'}</span>
    <span>{favorited ? '已收藏' : '收藏'}</span>
  </button>

  <!-- 待练开关按钮 -->
  <button
    type="button"
    onclick={togglePractice}
    disabled={busy || !metadataReady || !ready || !practiceAvailable}
    class="btn inline-flex h-9 items-center gap-1.5 rounded-full border px-3.5 text-xs font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 {queued ? 'border-[#3E885B]/40 bg-[#3E885B]/10 text-[#2D7D62] font-semibold' : 'border-[#c49a45]/40 bg-[#c49a45]/10 text-[#70541e] hover:bg-[#c49a45]/20'}"
    title={practiceAvailable ? (queued ? '点击移出待练列表' : '加入本设备待练列表') : '该曲谱格式不可在琴房内播放，支持直接阅读文本谱'}
  >
    <span aria-hidden="true" class="text-xs">{queued ? '✓' : '＋'}</span>
    <span>{queued ? '已在待练' : '加入待练'}</span>
  </button>

  <!-- 开始练习核心直达按钮 (同步 native macOS ScoreDetailView 体验) -->
  {#if practiceAvailable}
    <button
      type="button"
      onclick={startPractice}
      disabled={busy || !metadataReady || !ready}
      class="btn inline-flex h-9 items-center gap-1.5 rounded-full border border-[#8a6b29] bg-[#8a6b29] px-4 text-xs font-semibold text-white shadow-2xs transition-all hover:bg-[#735820] hover:shadow-sm active:scale-95 disabled:cursor-not-allowed disabled:opacity-50"
      title="进入琴房进行实时跟弹、圈段慢练与时长沉淀"
    >
      <span aria-hidden="true">⏱️</span>
      <span>开始练习</span>
    </button>
  {/if}

  {#if notice}
    <span role="status" class="inline-flex items-center text-xs font-medium text-[#2E6B47]">{notice}</span>
  {/if}
  {#if error}
    <span role="alert" class="inline-flex items-center text-xs font-medium text-red-700">{error}</span>
  {/if}
</div>
