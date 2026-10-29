<script lang="ts">
  import { summarizePractice } from '../../lib/practice/practiceSummary.ts';
  import type { PersonalData } from '../../lib/personal/types.ts';

  let { data, error = '' }: { data: PersonalData | null; error?: string } = $props();
  const summary = $derived(data ? summarizePractice(data) : null);

  function durationLabel(durationMs: number): string {
    if (!Number.isFinite(durationMs) || durationMs <= 0) return '0 分钟';
    const totalSeconds = Math.floor(durationMs / 1000);
    if (totalSeconds < 60) return `${totalSeconds} 秒`;
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const parts = [hours ? `${hours} 小时` : '', minutes ? `${minutes} 分钟` : '', seconds ? `${seconds} 秒` : ''].filter(Boolean);
    return parts.join(' ');
  }

  function dayLabel(date: string): string {
    const [year, month, day] = date.split('-');
    return `${month}-${day}${date === summary?.today.date ? ' 今天' : ''}`;
  }

  function timestampLabel(timestamp: number): string {
    if (!timestamp) return '时间未知';
    try { return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short', timeZone: summary?.timeZone }).format(timestamp); }
    catch { return '时间未知'; }
  }
</script>

<section class="card space-y-4 p-4 sm:p-5" aria-labelledby="practice-review-heading">
  <div class="flex flex-wrap items-start justify-between gap-2">
    <div><h2 id="practice-review-heading" class="font-display text-subheading">练习回顾</h2><p class="mt-1 text-xs text-ash">仅统计播放器已记录的伴奏播放时段，不代表实际演奏时长。</p></div>
    {#if summary}<span class="text-xs text-ash">本地时区：{summary.timeZone}</span>{/if}
  </div>

  {#if error}<p role="alert" class="rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-800">练习回顾暂不可用：{error}</p>
  {:else if !summary}<p class="text-sm text-ash">本设备个人资料尚未载入。</p>
  {:else}
    {#if summary.warnings.length}<div role="status" class="rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-950"><p class="font-semibold">部分练习记录未能完整汇总</p><ul class="mt-1 list-disc space-y-1 pl-4">{#each summary.warnings as warning}<li>{warning}</li>{/each}</ul></div>{/if}

    <div class="grid gap-4 lg:grid-cols-[minmax(12rem,0.7fr)_minmax(0,1.3fr)]">
      <div class="rounded-xl border hairline bg-paper p-4">
        <p class="text-xs text-ash">今天 · {dayLabel(summary.today.date)}</p>
        <p class="mt-1 font-display text-2xl">{durationLabel(summary.today.durationMs)}</p>
        <p class="mt-4 text-xs font-medium text-ash">近 7 个本地日</p>
        <ul class="mt-2 space-y-1.5">{#each summary.last7Days as day (day.date)}<li class="flex justify-between gap-3 text-xs"><span class="text-ash">{dayLabel(day.date)}</span><span class="font-medium">{durationLabel(day.durationMs)}</span></li>{/each}</ul>
      </div>

      <div class="min-w-0">
        <h3 class="text-sm font-semibold">最近练习记录</h3>
        {#if summary.recent.length === 0}
          <p class="mt-2 rounded-lg border hairline bg-paper p-4 text-sm text-ash">还没有已保存的练习记录。播放记录在播放器保存后会显示在这里。</p>
        {:else}
          <ol class="mt-2 divide-y divide-[#e8e2d4]">{#each summary.recent as session (session.id)}<li class="py-3 first:pt-1">
            <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1"><p class="min-w-0 truncate text-sm font-medium">{session.title}{session.artist ? ` · ${session.artist}` : ''}</p><span class="shrink-0 rounded-full bg-[#ede5d8] px-2 py-0.5 text-[11px]">{session.state}</span></div>
            <p class="mt-1 text-xs text-ash">已保存伴奏时长：{durationLabel(session.durationMs)} · {timestampLabel(session.updatedAt)}</p>
            {#if session.note}<p class="mt-1 whitespace-pre-wrap text-xs text-ash">备注：{session.note}</p>{/if}
            {#if session.scoreStatus === 'active'}
              <a class="btn btn-ghost mt-2 min-h-[44px] !px-3 text-sm" href={`/practice?score=${encodeURIComponent(session.scoreId)}`}>打开这首曲谱的练习</a>
            {:else if session.scoreStatus === 'archived'}
              <div class="mt-2 flex flex-wrap items-center gap-2"><span class="text-xs text-ash">曲谱已归档。</span><a class="btn btn-ghost min-h-[44px] !px-3 text-sm" href="/library">前往我的谱恢复</a></div>
            {:else if session.scoreStatus === 'not-in-queue'}
              <div class="mt-2 flex flex-wrap items-center gap-2"><span class="text-xs text-ash">曲谱已移出待练。</span><a class="btn btn-ghost min-h-[44px] !px-3 text-sm" href="/library">前往我的谱管理</a></div>
            {:else}
              <p class="mt-2 text-xs text-ash" role="status">这份曲谱已不在本设备资料中，无法从此记录恢复。</p>
            {/if}
          </li>{/each}</ol>
        {/if}
      </div>
    </div>
  {/if}
</section>
