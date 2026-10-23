<script lang="ts">
  let {
    guitar = {},
    ukulele = {},
  }: {
    guitar?: Record<string, number>;
    ukulele?: Record<string, number>;
  } = $props();

  let cat = $state<'guitar' | 'ukulele'>('guitar');
  let hoveredCell = $state<string | null>(null);

  const difficulties = [
    { value: 1, label: '零基础', color: 'bg-emerald-500', glow: 'shadow-[0_0_8px_rgba(16,185,129,0.5)]', badge: 'text-emerald-600 bg-emerald-50' },
    { value: 2, label: '初级', color: 'bg-cyan-500', glow: 'shadow-[0_0_8px_rgba(6,182,212,0.5)]', badge: 'text-cyan-600 bg-cyan-50' },
    { value: 3, label: '中级', color: 'bg-blue-500', glow: 'shadow-[0_0_8px_rgba(59,130,246,0.5)]', badge: 'text-blue-600 bg-blue-50' },
    { value: 4, label: '高级', color: 'bg-amber-500', glow: 'shadow-[0_0_8px_rgba(245,158,11,0.5)]', badge: 'text-amber-600 bg-amber-50' },
    { value: 5, label: '专业', color: 'bg-red-500', glow: 'shadow-[0_0_8px_rgba(239,68,68,0.5)]', badge: 'text-red-600 bg-red-50' },
  ];

  const forms = [
    { value: 1, label: '弹唱谱', icon: '🎤' },
    { value: 2, label: '指弹谱', icon: '🎸' },
    { value: 3, label: '和弦谱', icon: '🎼' },
    { value: 4, label: '六线谱', icon: '📜' },
  ];

  let matrix = $derived(cat === 'guitar' ? guitar : ukulele);
  let listPath = $derived(cat === 'guitar' ? 'tabs' : 'ukulele');
</script>

<div class="card rounded-card border hairline bg-paper p-6 shadow-xs transition-all">
  <!-- Matrix Header & Instrument Switcher -->
  <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b hairline">
    <div class="flex items-center gap-3">
      <div class="flex h-8 w-8 items-center justify-center rounded-full bg-surface-alt border hairline text-ink">
        <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <rect x="3" y="3" width="7" height="7"></rect>
          <rect x="14" y="3" width="7" height="7"></rect>
          <rect x="14" y="14" width="7" height="7"></rect>
          <rect x="3" y="14" width="7" height="7"></rect>
        </svg>
      </div>
      <div>
        <h3 class="font-display text-subheading text-ink font-semibold">曲谱难度 × 谱型分布矩阵</h3>
        <p class="text-caption text-mid-gray">20 个专业细分维度，精准匹配您的演奏水平</p>
      </div>
    </div>

    <!-- 18px Pill Instrument Toggle -->
    <div class="inline-flex items-center rounded-pill border hairline bg-surface-alt p-1 self-start sm:self-auto shadow-2xs" role="tablist">
      <button
        type="button"
        role="tab"
        aria-selected={cat === 'guitar'}
        class="rounded-pill px-4 py-1 text-xs font-medium transition-all {cat === 'guitar' ? 'bg-ink text-paper shadow-xs' : 'text-mid-gray hover:text-ink'}"
        onclick={() => (cat = 'guitar')}
      >
        🎸 吉他 (Guitar)
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={cat === 'ukulele'}
        class="rounded-pill px-4 py-1 text-xs font-medium transition-all {cat === 'ukulele' ? 'bg-ink text-paper shadow-xs' : 'text-mid-gray hover:text-ink'}"
        onclick={() => (cat = 'ukulele')}
      >
        🌴 尤克里里 (Ukulele)
      </button>
    </div>
  </div>

  <!-- Matrix Grid Table -->
  <div class="mt-4 overflow-x-auto">
    <table class="w-full min-w-[580px] border-collapse text-left">
      <thead>
        <tr class="text-caption font-semibold tracking-wider text-mid-gray uppercase border-b hairline">
          <th class="py-3 px-4 w-44">难度阶梯 / 等级</th>
          {#each forms as f}
            <th class="py-3 px-4 text-center font-medium">
              <span class="mr-1 inline-block">{f.icon}</span>
              {f.label}
            </th>
          {/each}
        </tr>
      </thead>
      <tbody class="divide-y hairline">
        {#each difficulties as d}
          <tr class="group transition-colors hover:bg-surface-alt/50">
            <!-- Difficulty Level with 5-Segment Glow Pips -->
            <td class="py-3.5 px-4">
              <div class="flex items-center gap-3">
                <!-- 5-Segment Progressive Glowing Pips -->
                <div class="flex items-center gap-1" title={`${d.label} (难度 ${d.value}/5)`}>
                  {#each [1, 2, 3, 4, 5] as pipIndex}
                    <span
                      class="h-2 w-2 rounded-full transition-all duration-300 {pipIndex <= d.value ? `${d.color} ${d.glow} scale-100` : 'bg-hairline scale-75 opacity-40'}"
                    ></span>
                  {/each}
                </div>
                <span class="text-body-sm font-medium text-ink">{d.label}</span>
              </div>
            </td>

            <!-- Counts Per Form -->
            {#each forms as f}
              {@const key = `${d.value}:${f.value}`}
              {@const count = (matrix[key] ?? 0) + (f.value === 4 ? (matrix[`${d.value}:7`] ?? 0) : 0)}
              {@const cellId = `${cat}-${d.value}-${f.value}`}
              <td
                class="py-2.5 px-3 text-center"
                onpointerenter={() => (hoveredCell = cellId)}
                onpointerleave={() => (hoveredCell = null)}
              >
                <a
                  href={`/${listPath}?difficulty=${d.value}&sheetForm=${f.value}`}
                  class="group/btn relative inline-flex items-center justify-center min-w-[5.5rem] rounded-pill border hairline bg-paper py-1.5 px-3 text-body-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-signal/40 hover:bg-paper hover:shadow-xs active:scale-95"
                  title={`${d.label} · ${f.label}：共 ${count} 首曲谱`}
                >
                  <span class="tabular-nums font-semibold text-ink transition-colors group-hover/btn:text-signal">{count}</span>
                  <span class="ml-1 text-caption text-mid-gray">首</span>

                  <!-- Micro Hover Pulse Indicator -->
                  {#if count > 0}
                    <span class="absolute -top-0.5 -right-0.5 h-1.5 w-1.5 rounded-full {d.color} opacity-0 transition-opacity group-hover/btn:opacity-100"></span>
                  {/if}
                </a>
              </td>
            {/each}
          </tr>
        {/each}
      </tbody>
    </table>
  </div>

  <!-- Bottom Matrix Legend & Stats Summary -->
  <div class="mt-4 flex flex-wrap items-center justify-between gap-3 border-t hairline pt-3 text-caption text-mid-gray">
    <div class="flex items-center gap-4">
      <span class="flex items-center gap-1.5">
        <span class="h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_6px_rgba(16,185,129,0.5)]"></span>
        零基础~初级
      </span>
      <span class="flex items-center gap-1.5">
        <span class="h-2 w-2 rounded-full bg-blue-500 shadow-[0_0_6px_rgba(59,130,246,0.5)]"></span>
        中级进阶
      </span>
      <span class="flex items-center gap-1.5">
        <span class="h-2 w-2 rounded-full bg-red-500 shadow-[0_0_6px_rgba(239,68,68,0.5)]"></span>
        高级~专业
      </span>
    </div>
    <span class="font-mono text-xs">点击单元格直达精准筛选结果</span>
  </div>
</div>
