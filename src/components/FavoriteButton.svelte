<script lang="ts">
  import { onMount } from 'svelte';
  import { addCatalogFavorite, addCatalogPractice, type CatalogScoreInput } from '../lib/personal/catalog.ts';
  import { readPersonalData, subscribePersonalData } from '../lib/personal/repository.ts';

  let {
    tabId = '', initialCount = 0, title = '', artist = '', category = 'guitar', scoreUrl = '', format = 'ibe', catalogAvailable = true,
  }: {
    tabId?: string; initialCount?: number; title?: string; artist?: string; category?: string; scoreUrl?: string; format?: string; catalogAvailable?: boolean;
  } = $props();

  let favorited = $state(false);
  let busy = $state(false);
  let error = $state('');
  let notice = $state('');
  let ready = $state(false);
  const metadataReady = $derived(Boolean(tabId && title.trim()));
  const practiceAvailable = $derived(catalogAvailable && format.toLowerCase() !== 'xhe' && Boolean(scoreUrl));
  const input = $derived<CatalogScoreInput>({ id: tabId, title, artist, category, format, scoreUrl: scoreUrl || undefined });

  async function refresh() {
    if (!metadataReady) return;
    const data = await readPersonalData();
    favorited = data.favorites.includes(`catalog:${tabId}`);
    ready = true;
  }

  onMount(() => {
    let active = true;
    const unsubscribe = subscribePersonalData(() => { if (active) void refresh().catch((cause) => { error = cause instanceof Error ? cause.message : String(cause); }); });
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

  async function addToPractice() {
    if (busy || !metadataReady || !practiceAvailable) return;
    busy = true; error = ''; notice = '';
    try { await addCatalogPractice(input); notice = '已加入本设备待练'; }
    catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { busy = false; }
  }
</script>

<div class="flex flex-wrap items-center gap-2">
  <button type="button" onclick={toggleFavorite} disabled={busy || !metadataReady || !ready} class="btn group inline-flex items-center gap-2 rounded-pill border hairline px-4 py-2 text-body-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 {favorited ? 'bg-red-50/70 border-red-200 text-red-700' : 'bg-paper text-ink hover:bg-canvas'}" aria-pressed={favorited} aria-label={favorited ? '取消本地收藏' : '收藏到本设备'} title={!metadataReady ? '曲谱元数据暂不可用，无法安全保存引用' : '收藏保存在本设备'}>
    <span aria-hidden="true">{favorited ? '♥' : '♡'}</span><span>{favorited ? '已收藏' : '收藏'}</span>
  </button>
  <button type="button" onclick={addToPractice} disabled={busy || !metadataReady || !ready || !practiceAvailable} class="btn inline-flex items-center gap-2 rounded-pill border border-[#c49a45]/40 bg-[#c49a45]/10 px-4 py-2 text-body-sm font-medium text-[#70541e] hover:bg-[#c49a45]/20 disabled:cursor-not-allowed disabled:opacity-50" title={practiceAvailable ? '加入本设备待练' : '这份谱没有可播放的下载资源，可阅读文本谱'}>＋ 待练</button>
  {#if error}<span role="alert" class="w-full text-xs text-red-700">{error}</span>{:else if notice}<span role="status" class="w-full text-xs text-[#70541e]">{notice}</span>{/if}
</div>
