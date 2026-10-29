<script lang="ts">
  let {
    today = [],
    week = [],
    month = [],
  }: {
    today?: any[];
    week?: any[];
    month?: any[];
  } = $props();

  let active = $state<'today' | 'week' | 'month'>('today');
  const tabs = [
    { key: 'today', label: '🔥 今日热门' },
    { key: 'week', label: '📅 本周飙升' },
    { key: 'month', label: '🏆 本月总榜' },
  ] as const;

  let items = $derived(active === 'today' ? today : active === 'week' ? week : month);
</script>

<div>
  <!-- Tab Range Switcher (18px Pill Segmented Control) -->
  <div class="inline-flex items-center rounded-pill border hairline bg-surface-alt p-1 shadow-2xs" role="tablist" aria-label="热门时间范围">
    {#each tabs as t}
      <button
        type="button"
        role="tab"
        aria-selected={active === t.key}
        class="rounded-pill px-4 py-1.5 text-xs font-medium transition-all {active === t.key ? 'bg-ink text-paper shadow-xs' : 'text-mid-gray hover:text-ink'}"
        onclick={() => (active = t.key)}
      >
        {t.label}
      </button>
    {/each}
  </div>

  <!-- Cards Grid -->
  <ul class="mt-4 grid grid-cols-1 gap-3.5 md:grid-cols-2">
    {#each items as tab, index (tab.id)}
      {@const cat = tab.category === 'ukulele' ? 'ukulele' : 'tabs'}
      {@const heat = tab.heat >= 10000 ? (tab.heat / 10000).toFixed(1) + '万' : String(tab.heat ?? 0)}
      <li class="animate-stagger-in" style="animation-delay: {Math.min(index * 35, 300)}ms;">
        <a
          href={`/${cat}/${tab.id}`}
          class="card-interactive group flex items-center gap-3.5 rounded-card border hairline bg-paper p-3.5 shadow-2xs transition-all hover:shadow-xs hover:border-signal/40"
        >
          <!-- Ranking Badge -->
          <span
            class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-mono font-bold {index < 3 ? 'bg-amber-500/10 text-amber-600 border border-amber-500/20' : 'bg-surface-alt text-mid-gray'}"
          >
            {index + 1}
          </span>

          <div class="min-w-0 flex-1">
            <h3 class="truncate font-display text-body-sm font-medium text-ink transition-colors group-hover:text-signal">
              {tab.title}
            </h3>
            <p class="mt-0.5 truncate text-caption text-mid-gray">
              {tab.artist || '未知歌手'}
            </p>
          </div>

          <div class="shrink-0 text-right">
            <span class="inline-flex items-center gap-1 rounded-pill border hairline bg-surface-alt px-2 py-0.5 text-caption font-medium tabular-nums text-charcoal">
              <svg class="h-3 w-3 text-amber-500" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 2c1.5 3 4 5 4 9 0 3.3-2.7 6-6 6s-6-2.7-6-6c0-3.5 2-6 4-8-.5 2 1 4 2 4s2-2 2-5z"/>
              </svg>
              {heat}
            </span>
          </div>
        </a>
      </li>
    {/each}
  </ul>
</div>
