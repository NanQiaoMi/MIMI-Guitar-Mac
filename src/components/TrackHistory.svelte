<script lang="ts">
  import { onMount } from 'svelte';
  import { mutatePersonalData } from '../lib/personal/repository.ts';
  let { id = '', title = '', artist = '', category = 'guitar' }: { id?: string; title?: string; artist?: string; category?: string } = $props();
  let error = $state('');
  onMount(() => {
    if (!id || !title) return;
    const entry = {
      id, title, artist, category,
      url: `/${category === 'ukulele' ? 'ukulele' : 'tabs'}/${encodeURIComponent(id)}`,
      time: Date.now(),
    };
    void mutatePersonalData((draft) => {
      draft.history = [entry, ...draft.history.filter((item) => item.url !== entry.url)]
        .sort((a, b) => b.time - a.time).slice(0, 500);
    }).catch((cause) => { error = cause instanceof Error ? cause.message : '本地存储不可用'; });
  });
</script>

{#if error}<p role="status" class="mt-3 text-xs text-amber-800">本次浏览记录未保存：{error}</p>{/if}
