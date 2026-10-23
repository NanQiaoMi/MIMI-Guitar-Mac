<script lang="ts">
  import { onMount } from 'svelte';
  import { readPersonalData, subscribePersonalData } from '../../lib/personal/repository';
  import { createLatestReadCoordinator } from '../../lib/personal/practiceQueue';
  import type { PersonalData } from '../../lib/personal/types';

  let data = $state<PersonalData | null>(null);
  let error = $state('');
  let loading = $state(true);
  const recent = $derived(data?.sessions.slice().sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 3) ?? []);
  const waiting = $derived(data?.practiceItems.filter((item) => item.status === 'todo' || item.status === 'practicing').length ?? 0);

  const dataReads = createLatestReadCoordinator<PersonalData>(
    readPersonalData,
    (next) => { data = next; error = ''; loading = false; },
    (cause, isInitial) => {
      error = cause instanceof Error ? cause.message : '本地资料暂时不可用';
      if (isInitial) loading = false;
    },
  );

  onMount(() => {
    const unsubscribe = subscribePersonalData(() => { void dataReads.refresh(); });
    void dataReads.refresh();
    return () => { unsubscribe(); dataReads.dispose(); };
  });
</script>

<section class="mt-16 rounded-3xl border border-[#e2d8c3] bg-[#fffdfa] p-6 sm:p-8">
  <div class="flex flex-wrap items-end justify-between gap-4">
    <div>
      <h2 class="font-display text-2xl font-bold text-[#2d2926]">我的练习手记</h2>
      <p class="mt-2 text-sm text-[#7b6b5a]">收藏、待练与练习记录保存在当前浏览器，可在数据设置中备份。</p>
    </div>
    <a href="/practice" class="rounded-xl bg-[#3d5947] px-4 py-2 text-sm font-semibold text-white">进入练习工作台 →</a>
  </div>
  {#if error}
    <p role="alert" class="mt-5 text-sm text-red-700">{error}</p>
  {:else if loading}
    <p role="status" class="mt-5 text-sm text-[#7b6b5a]">读取本地练习记录…</p>
  {:else}
    <p class="mt-5 text-sm text-[#7b6b5a]">待练与在练 {waiting} 首 · 已保存 {data?.sessions.length ?? 0} 次练习</p>
    {#if recent.length}
      <div class="mt-4 grid gap-4 md:grid-cols-3">
        {#each recent as session (session.id)}
          {@const score = data?.scores.find((entry) => entry.id === session.scoreId)}
          {@const practiceItem = data?.practiceItems.find((entry) => entry.scoreId === session.scoreId)}
          {@const canContinue = Boolean(score && practiceItem && practiceItem.status !== 'archived')}
          {@const actionText = !score
            ? '曲谱已缺失 · 去我的曲库查看或重新导入'
            : !practiceItem
              ? '已移出待练 · 去我的曲库重新加入'
              : practiceItem.status === 'archived'
                ? '已归档 · 去我的曲库恢复到待练'
                : '继续练习 →'}
          <a href={canContinue ? `/practice?score=${encodeURIComponent(session.scoreId)}` : '/library'} class="block min-h-[44px] rounded-2xl border border-[#e2d8c3] bg-white p-5 hover:border-[#c49a45]">
            <h3 class="font-semibold text-[#2d2926]">{score?.title ?? '曲谱未找到'}</h3>
            <p class="mt-2 text-sm text-[#7b6b5a]">有效练习 {Math.floor(session.slices.reduce((sum, slice) => sum + slice.durationMs, 0) / 60000)} 分钟</p>
            <p class="mt-2 text-sm text-[#5c4a38]">{session.note || '下次继续练习，随手记下需要攻克的小节。'}</p>
            <span class="mt-3 inline-flex min-h-[44px] items-center font-semibold text-[#3d5947]">{actionText}</span>
          </a>
        {/each}
      </div>
    {:else}
      <p class="mt-4 text-sm leading-6 text-[#5c4a38]">先在曲库中加入待练，或到“我的曲库”导入自己的谱。在播放器中开始练习后，进度与笔记会出现在这里。</p>
    {/if}
  {/if}
</section>
