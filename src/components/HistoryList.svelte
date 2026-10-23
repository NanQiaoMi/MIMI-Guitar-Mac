<script lang="ts">
  import { onMount } from 'svelte';
  import { mutatePersonalData, readPersonalData, subscribePersonalData } from '../lib/personal/repository.ts';
  import type { PersonalData } from '../lib/personal/types.ts';
  let items = $state<PersonalData['history']>([]);
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let cleared = $state<PersonalData['history']>([]);
  onMount(() => {
    let active = true;
    const refresh = async () => {
      try { const data = await readPersonalData(); if (active) items = data.history.slice().sort((a, b) => b.time - a.time); }
      catch (cause) { if (active) error = cause instanceof Error ? cause.message : '无法读取本地记录'; }
      finally { if (active) loading = false; }
    };
    void refresh();
    const unsubscribe = subscribePersonalData(() => void refresh());
    return () => { active = false; unsubscribe(); };
  });
  async function clearAll() {
    busy = true; error = '';
    try {
      let removed: PersonalData['history'] = [];
      await mutatePersonalData((draft) => { removed = draft.history; draft.history = []; });
      cleared = removed;
    } catch (cause) { error = cause instanceof Error ? cause.message : '清空未完成'; }
    finally { busy = false; }
  }
  async function undoClear() {
    busy = true; error = '';
    try {
      await mutatePersonalData((draft) => {
        const entries = new Map([...cleared, ...draft.history].map((entry) => [entry.url, entry]));
        draft.history = [...entries.values()].sort((a, b) => b.time - a.time).slice(0, 500);
      });
      cleared = [];
    } catch (cause) { error = cause instanceof Error ? cause.message : '撤销未完成'; }
    finally { busy = false; }
  }
</script>

<div>
  {#if error}<p role="alert" class="mb-3 text-sm text-red-800">{error}</p>{/if}
  {#if cleared.length}<p role="status" class="mb-3 text-sm">已清空 {cleared.length} 条记录。<button type="button" class="underline" disabled={busy} onclick={undoClear}>撤销清空</button></p>{/if}
  {#if loading}<p class="card p-5 text-ash">正在读取浏览记录…</p>
  {:else if items.length > 0}
    <div class="mb-4 flex items-center justify-between gap-3">
      <p class="text-caption text-ash">共 {items.length} 条记录 · 每首保留最近一次，最多500条 · 已纳入个人备份</p>
      <button type="button" onclick={clearAll} disabled={busy} class="btn">清空记录</button>
    </div>
    <ul class="grid grid-cols-1 gap-3 md:grid-cols-2">
      {#each items as item (item.url + '-' + item.time)}
        <li><a href={item.url} class="card block p-4 transition hover:opacity-75"><p class="font-medium">{item.title} <span class="font-normal text-ash">{item.artist ? `- ${item.artist}` : ''}</span></p><p class="mt-1 text-caption text-ash">{new Date(item.time).toLocaleString()}</p></a></li>
      {/each}
    </ul>
  {:else}<div class="card flex h-40 items-center justify-center text-ash">暂无浏览记录</div>{/if}
</div>
