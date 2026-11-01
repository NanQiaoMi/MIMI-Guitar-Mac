<script lang="ts">
  import { summarizePractice } from '../../lib/practice/practiceSummary.ts';
  import type { PersonalData } from '../../lib/personal/types.ts';

  let { data, error = '' }: { data: PersonalData | null; error?: string } = $props();
  const summary = $derived(data ? summarizePractice(data) : null);

  const weeklyTotalMs = $derived(
    summary ? summary.last7Days.reduce((acc, cur) => acc + cur.durationMs, 0) : 0
  );
  const weeklyAverageMs = $derived(
    summary && summary.last7Days.length > 0 ? weeklyTotalMs / summary.last7Days.length : 0
  );
  const maxDayDuration = $derived(
    Math.max(1800000, ...(summary?.last7Days.map((d) => d.durationMs) ?? [0]))
  );

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

  function durationShortLabel(durationMs: number): string {
    if (!Number.isFinite(durationMs) || durationMs <= 0) return '0';
    const minutes = Math.ceil(durationMs / 60000);
    return `${minutes}m`;
  }

  function dayLabel(date: string): string {
    const [year, month, day] = date.split('-');
    return `${month}-${day}${date === summary?.today.date ? ' 今天' : ''}`;
  }

  function dayShortLabel(date: string): string {
    const [year, month, day] = date.split('-');
    return `${month}-${day}`;
  }

  function timestampLabel(timestamp: number): string {
    if (!timestamp) return '时间未知';
    try { return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short', timeZone: summary?.timeZone }).format(timestamp); }
    catch { return '时间未知'; }
  }
</script>

<section class="card space-y-4 p-4 sm:p-6" aria-labelledby="practice-review-heading">
  <div class="flex flex-wrap items-start justify-between gap-2 border-b border-[#ebd8bc]/40 pb-3">
    <div>
      <h2 id="practice-review-heading" class="font-display text-subheading text-[#24201d]">练习回顾</h2>
      <p class="mt-1 text-xs text-ash">仅统计播放器已记录的伴奏播放时段，不代表实际演奏时长。</p>
    </div>
    {#if summary}<span class="text-xs text-ash">本地时区：{summary.timeZone}</span>{/if}
  </div>

  {#if error}<p role="alert" class="rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-800">练习回顾暂不可用：{error}</p>
  {:else if !summary}<p class="text-sm text-ash">本设备个人资料尚未载入。</p>
  {:else}
    {#if summary.warnings.length}<div role="status" class="rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-950"><p class="font-semibold">部分练习记录未能完整汇总</p><ul class="mt-1 list-disc space-y-1 pl-4">{#each summary.warnings as warning}<li>{warning}</li>{/each}</ul></div>{/if}

    <div class="grid gap-5 lg:grid-cols-[minmax(18rem,0.9fr)_minmax(0,1.1fr)]">
      <!-- 左侧：7天柱状可视化律动图表 -->
      <div class="rounded-xl border hairline bg-[#fcfaf7] p-4 sm:p-5 flex flex-col justify-between space-y-4">
        <div>
          <div class="flex items-baseline justify-between">
            <span class="text-xs font-semibold text-[#8c6d38] uppercase tracking-wider">近 7 天练习律动</span>
            <span class="rounded-full bg-[#f4ece0] px-2 py-0.5 font-mono text-[11px] text-[#7d5e2d]">目标 20m/天</span>
          </div>
          <div class="mt-2 flex items-baseline justify-between">
            <div>
              <p class="text-[11px] text-ash">本周累计伴奏练习</p>
              <p class="font-display text-2xl font-bold text-[#24201d]">{durationLabel(weeklyTotalMs)}</p>
            </div>
            <div class="text-right">
              <p class="text-[11px] text-ash">日均练习</p>
              <p class="text-sm font-semibold text-[#584a3b]">{durationLabel(weeklyAverageMs)}</p>
            </div>
          </div>
        </div>

        <!-- 柱状图 -->
        <div class="rounded-xl bg-paper p-3 border hairline">
          <div class="grid grid-cols-7 gap-1.5 items-end h-24">
            {#each summary.last7Days as day (day.date)}
              {@const isToday = day.date === summary.today.date}
              {@const ratio = Math.min(1.0, Math.max(0.06, day.durationMs / maxDayDuration))}
              <div class="flex flex-col items-center h-full justify-end group">
                <span class="text-[10px] font-mono leading-none mb-1 text-ash {day.durationMs > 0 ? 'font-bold text-[#24201d]' : 'opacity-40'}">
                  {durationShortLabel(day.durationMs)}
                </span>
                <div class="w-full max-w-[28px] h-14 bg-[#ede7dc]/60 rounded-md flex items-end justify-center overflow-hidden {isToday ? 'ring-1 ring-[#c49a45]' : ''}">
                  <div
                    class="w-full rounded-md transition-all duration-500 {day.durationMs > 0 ? 'bg-gradient-to-t from-[#996515] to-[#d4af37]' : 'bg-[#e2dacd]'}"
                    style="height: {Math.max(6, ratio * 56)}px"
                  ></div>
                </div>
                <span class="mt-1.5 text-[10px] font-mono {isToday ? 'font-bold text-[#8c6d38]' : 'text-ash'}">
                  {isToday ? '今天' : dayShortLabel(day.date)}
                </span>
              </div>
            {/each}
          </div>
        </div>

        <!-- 今日目标完成进度条 -->
        {@const todayProgress = Math.min(1.0, (summary.today.durationMs) / (20 * 60 * 1000))}
        <div class="space-y-1.5 pt-1">
          <div class="flex items-center justify-between text-xs">
            <span class="text-[#584a3b] font-medium flex items-center gap-1.5">
              <span>{summary.today.durationMs >= 20 * 60 * 1000 ? '🎉' : '✨'}</span>
              <span>今日练琴进度</span>
            </span>
            <span class="font-mono text-ash">{summary.today.durationMs > 0 ? `${Math.round(todayProgress * 100)}%` : '今日未开始'}</span>
          </div>
          <div class="h-2 w-full rounded-full bg-[#ede5d8] overflow-hidden">
            <div
              class="h-full rounded-full bg-gradient-to-r from-[#d4af37] to-[#8f6b28] transition-all duration-500"
              style="width: {Math.max(todayProgress > 0 ? 5 : 0, todayProgress * 100)}%"
            ></div>
          </div>
        </div>
      </div>

      <!-- 右侧：最近练习记录 -->
      <div class="min-w-0 flex flex-col justify-between">
        <div>
          <h3 class="text-sm font-semibold text-[#24201d]">最近练习记录</h3>
          {#if summary.recent.length === 0}
            <div class="mt-3 rounded-xl border hairline bg-[#fcfaf7] p-6 text-center space-y-2">
              <div class="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-[#f4ece0] text-lg text-[#8c6d38]">
                🎼
              </div>
              <h4 class="text-sm font-semibold text-[#24201d]">练习记录静待开启</h4>
              <p class="mx-auto max-w-sm text-xs leading-5 text-ash">
                在曲谱播放器中跟随伴奏练习、慢速调速或开启小节循环时，系统会自动记录伴奏时段并生成节奏突破档案。
              </p>
              <div class="pt-2">
                <a href="/tabs" class="btn btn-ghost min-h-[34px] !px-3 text-xs">从曲库精选挑一首练习</a>
              </div>
            </div>
          {:else}
            <ol class="mt-2 divide-y divide-[#e8e2d4]">
              {#each summary.recent as session (session.id)}
                <li class="py-3 first:pt-1">
                  <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                    <p class="min-w-0 truncate text-sm font-medium text-[#24201d]">{session.title}{session.artist ? ` · ${session.artist}` : ''}</p>
                    <span class="shrink-0 rounded-full bg-[#ede5d8] px-2 py-0.5 text-[11px] font-medium text-[#7d5e2d]">{session.state}</span>
                  </div>
                  <p class="mt-1 text-xs text-ash">已保存伴奏时长：<strong class="text-[#584a3b]">{durationLabel(session.durationMs)}</strong> · {timestampLabel(session.updatedAt)}</p>
                  {#if session.note}<p class="mt-1 whitespace-pre-wrap text-xs text-ash">备注：{session.note}</p>{/if}
                  {#if session.scoreStatus === 'active'}
                    <a class="btn btn-ghost mt-2 min-h-[36px] !px-3 text-xs" href={`/practice?score=${encodeURIComponent(session.scoreId)}`}>打开这首曲谱的练习</a>
                  {:else if session.scoreStatus === 'archived'}
                    <div class="mt-2 flex flex-wrap items-center gap-2"><span class="text-xs text-ash">曲谱已归档。</span><a class="btn btn-ghost min-h-[36px] !px-3 text-xs" href="/library">前往我的谱恢复</a></div>
                  {:else if session.scoreStatus === 'not-in-queue'}
                    <div class="mt-2 flex flex-wrap items-center gap-2"><span class="text-xs text-ash">曲谱已移出待练。</span><a class="btn btn-ghost min-h-[36px] !px-3 text-xs" href="/library">前往我的谱管理</a></div>
                  {:else}
                    <p class="mt-2 text-xs text-ash" role="status">这份曲谱已不在本设备资料中，无法从此记录恢复。</p>
                  {/if}
                </li>
              {/each}
            </ol>
          {/if}
        </div>
      </div>
    </div>
  {/if}
</section>
