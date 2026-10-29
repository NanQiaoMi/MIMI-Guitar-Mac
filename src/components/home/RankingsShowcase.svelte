<script lang="ts">
  import { onMount } from 'svelte';
  import { scoreAuditionEngine, type AuditionState } from '../../lib/scoreAuditionEngine';
  import MotionSegmentedControl from '../ui/MotionSegmentedControl.svelte';
  import { fadeMotion, registerMotionSurface } from '../../lib/ui/motion';
  import { subscribeMotionPreference } from '../../lib/ui/motionPreferences';
  import { paperReveal } from '../../lib/ui/paperReveal';

  export interface TabRow {
    id: string;
    title: string;
    artist?: string | null;
    heat?: number;
    difficulty?: number;
    sheetForm?: number | string;
    key?: string | null;
    scoreUrl?: string | null;
    xheUrl?: string | null;
  }

  export interface RankingsProps {
    today?: TabRow[];
    week?: TabRow[];
    month?: TabRow[];
  }

  let { today = [], week = [], month = [] }: RankingsProps = $props();

  let activeTab = $state<'today' | 'week' | 'month'>('today');
  let sectionElement: HTMLElement | null = $state(null);
  let animateDecorations = $state(false);
  const periods = [{ value: 'today', label: '今日热门' }, { value: 'week', label: '本周飙升' }, { value: 'month', label: '本月总榜' }];

  let currentList = $derived.by<TabRow[]>(() => {
    if (activeTab === 'week') return week.length > 0 ? week : today;
    if (activeTab === 'month') return month.length > 0 ? month : today;
    return today;
  });

  let audition = $state<AuditionState>(scoreAuditionEngine.getState());

  onMount(() => {
    let fullMotion = false;
    let inView = false;
    const updateActivity = () => { animateDecorations = fullMotion && inView && !document.hidden; };
    const unsubscribeMotion = subscribeMotionPreference(({ mode }) => { fullMotion = mode === 'full'; updateActivity(); });
    const observer = new IntersectionObserver((entries) => { inView = entries[0]?.isIntersecting ?? false; updateActivity(); });
    if (sectionElement) observer.observe(sectionElement);
    document.addEventListener('visibilitychange', updateActivity);
    const unsub = scoreAuditionEngine.subscribe((st) => {
      audition = st;
    });
    return () => {
      unsub();
      unsubscribeMotion();
      observer.disconnect();
      document.removeEventListener('visibilitychange', updateActivity);
    };
  });

  function formatHeat(heat?: number | null): string {
    const h = heat ?? 0;
    if (h >= 10000) return (h / 10000).toFixed(1) + '万';
    return String(h);
  }

  function getDiffBadge(diff?: number | null): { text: string; class: string } {
    if (!diff || diff <= 1) return { text: '零基础', class: 'text-[#2e7d32] bg-[#2e7d32]/8 border-[#2e7d32]/20' };
    if (diff === 2) return { text: '初级', class: 'text-[#00838f] bg-[#00838f]/8 border-[#00838f]/20' };
    if (diff === 3) return { text: '中级', class: 'text-[#1565c0] bg-[#1565c0]/8 border-[#1565c0]/20' };
    if (diff === 4) return { text: '高级', class: 'text-[#d85a00] bg-[#d85a00]/8 border-[#d85a00]/20' };
    return { text: '专业', class: 'text-[#b71c1c] bg-[#b71c1c]/8 border-[#b71c1c]/20' };
  }

  async function triggerAudition(e: MouseEvent, tab: TabRow) {
    e.preventDefault();
    e.stopPropagation();
    await scoreAuditionEngine.togglePlayTab(tab);
  }
</script>

<section bind:this={sectionElement} use:paperReveal class="mt-16 sm:mt-20" class:decorations-active={animateDecorations}>
  <!-- Header: Title & Time Tabs -->
  <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-6">
    <div>
      <div class="flex items-center gap-2.5">
        <span class="h-4 w-1.5 bg-gradient-to-b from-[#c49a45] to-[#8f6d2b] rounded-full shadow-2xs"></span>
        <h2 class="font-serif text-2xl sm:text-3xl font-bold tracking-tight text-[#2d2417]">
          全站研习热门排行榜
        </h2>
      </div>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-1 pl-4">
        按曲库收录的热度浏览，找到下一首想练的曲子
      </p>
    </div>

    <!-- Time Period Switcher & View All -->
    <div class="flex items-center gap-3">
      <MotionSegmentedControl value={activeTab} options={periods} label="热门榜单时间范围" onChange={(value) => { if (value === 'today' || value === 'week' || value === 'month') activeTab = value; }} />

      <a
        href="/tabs?sort=1"
        class="hidden sm:inline-flex items-center gap-1 text-xs font-serif text-[#966b26] hover:text-[#6b4a15] transition-colors shrink-0 group"
      >
        <span>查看完整榜单</span>
        <span class="transition-transform group-hover:translate-x-0.5">→</span>
      </a>
    </div>
  </div>

  <!-- Rankings 2-Column Calligraphy Bookmark List -->
  {#key activeTab}
  <div class="grid grid-cols-1 md:grid-cols-2 gap-3.5 sm:gap-4" use:registerMotionSurface in:fadeMotion={{ kind: 'panel', duration: 180 }}>
    {#each currentList.slice(0, 10) as tab, index (tab.id)}
      {@const rank = index + 1}
      {@const diff = getDiffBadge(tab.difficulty)}
      {@const isPlaying = audition.isPlaying && audition.currentTabId === tab.id}
      {@const isLoading = audition.isLoading && audition.currentTabId === tab.id}
      {@const hasPlayableScore = typeof tab.scoreUrl === 'string' && tab.scoreUrl.trim().length > 0}
      {@const auditionError = audition.currentTabId === tab.id ? audition.error : null}

      <article
        class="bookmark-card group relative flex flex-wrap items-center justify-between rounded-2xl border p-3 sm:p-3.5 bg-[#ffffff] shadow-[0_2px_10px_rgba(76,59,43,0.04)] hover:shadow-[0_8px_24px_rgba(140,105,50,0.12)] {rank <= 3 ? 'border-[#dfc99b] bg-gradient-to-r from-[#ffffff] via-[#fffdf9] to-[#faf5eb]' : 'border-[#e8e2d4]'}"
      >
        <!-- Left: Bookmark Rank Ribbon & Title/Metadata -->
        <div class="flex items-center gap-3 min-w-0">
          <!-- Traditional Debossed Bookmark Ribbon Tag -->
          <div
            class="bookmark-ribbon flex h-9 w-9 shrink-0 items-center justify-center rounded-xl font-mono text-sm font-bold shadow-2xs transition-transform group-hover:scale-105 {rank === 1 ? 'ribbon-gold' : rank === 2 ? 'ribbon-silver' : rank === 3 ? 'ribbon-bronze' : 'ribbon-default'}"
          >
            {rank < 10 ? '0' + rank : rank}
          </div>

          <!-- Song Title & Metadata -->
          <div class="min-w-0">
            <h3
              class="truncate font-serif text-base font-bold text-[#2d2417] group-hover:text-[#966b26] transition-colors"
            >
              <a class="after:absolute after:inset-0 after:rounded-2xl" href={`/tabs/${tab.id}`}>{tab.title}</a>
            </h3>
            <div class="flex items-center gap-2 text-[11px] font-serif text-[#8c7b68] mt-0.5">
              <span class="truncate max-w-[100px] sm:max-w-[130px]">{tab.artist || '未知歌手'}</span>
              <span class="text-[#ded4be]">·</span>
              <span class="rounded bg-[#fbf9f4] border border-[#e8e2d4] px-1.5 py-0.2 font-mono text-[10px] text-[#5c4a38]">
                {tab.key || 'G'} 调
              </span>
            </div>
          </div>
        </div>

        <!-- Right: Heat, Difficulty & Interactive Audio Waveform Trigger -->
        <div class="flex items-center gap-2.5 sm:gap-3 shrink-0">
          <!-- Difficulty Tag -->
          <span class="hidden sm:inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium {diff.class}">
            {diff.text}
          </span>

          <!-- Heat Score -->
          <span class="font-mono text-xs text-[#705c42] flex items-center gap-0.5">
            <span class="text-[#c84b31] text-[10px]">🔥</span>
            {formatHeat(tab.heat)}
          </span>

          <!-- Interactive Live Waveform / Audition Probe Button -->
          {#if hasPlayableScore}
            <button
              type="button"
              onclick={(e) => triggerAudition(e, tab)}
              class="waveform-trigger relative z-10 flex min-h-[44px] min-w-[44px] px-2.5 items-center justify-center gap-1.5 rounded-full border border-[#ded4be] bg-[#fbf9f4] text-[#2d2417] shadow-2xs hover:border-[#c49a45] hover:bg-[#ffffff] hover:text-[#966b26] transition-colors"
              aria-label={isPlaying ? '暂停播放曲谱' : '播放曲谱'}
              title={isPlaying ? '暂停播放曲谱' : '播放曲谱'}
            >
              {#if isLoading}
                <div class="h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent"></div>
              {:else if isPlaying}
                <!-- 4-Bar Dancing Audio Spectrum Equalizer -->
                <div class="flex items-end gap-[2px] h-3.5 w-4">
                  <span class="spectrum-bar bar-1"></span>
                  <span class="spectrum-bar bar-2"></span>
                  <span class="spectrum-bar bar-3"></span>
                  <span class="spectrum-bar bar-4"></span>
                </div>
                <span class="text-[10px] font-serif font-medium text-[#966b26] hidden sm:inline">播放中</span>
              {:else}
                <span class="text-[10px]">▶</span>
                <span class="text-[10px] font-serif text-[#705c42] hidden sm:inline">播放</span>
              {/if}
            </button>
          {:else}
            <a
              href={'/tabs/' + tab.id}
              class="relative z-10 inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-full border border-[#ded4be] bg-[#fbf9f4] px-2.5 text-[10px] font-serif text-[#705c42] hover:border-[#c49a45] hover:text-[#966b26]"
            >
              {tab.xheUrl ? '阅读曲谱' : '打开曲谱'}
            </a>
          {/if}

          <!-- Subtle Enter Arrow -->
          <span class="hidden sm:inline-flex text-[#ded4be] group-hover:text-[#966b26] group-hover:translate-x-0.5 transition-all text-sm">
            →
          </span>
        </div>
        {#if auditionError}
          <p role="alert" class="relative z-20 basis-full pt-2 text-xs text-[#9b3328]">
            曲谱播放失败：{auditionError}
            <a class="ml-1 font-semibold underline underline-offset-2" href={'/tabs/' + tab.id}>打开《{tab.title}》曲谱</a>
          </p>
        {/if}
      </article>
    {/each}
  </div>
  {/key}
</section>

<style>
  /* ============================================================
     RANKINGS SHOWCASE — 经典文人雅集书签长条榜
     ============================================================ */

  .bookmark-card {
    cursor: pointer;
    text-decoration: none;
    transform: translateX(0);
    transition: transform 200ms cubic-bezier(0.16, 1, 0.3, 1), box-shadow 200ms ease, border-color 200ms ease;
  }
  .bookmark-card:hover {
    transform: translateX(4px);
  }
  .bookmark-card:focus-within { outline: 2px solid var(--color-signal); outline-offset: 3px; }
  :global(html[data-motion="gentle"]) .bookmark-card:hover,
  :global(html[data-motion="off"]) .bookmark-card:hover { transform: none; }

  /* Rank Badges (Silk Ribbons & Paper Deboss) */
  .ribbon-gold {
    background: linear-gradient(135deg, #f0ca76 0%, #b88a38 100%);
    color: #ffffff;
    border: 1px solid rgba(255, 255, 255, 0.6);
    box-shadow: 0 2px 6px rgba(184, 138, 56, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.6);
    text-shadow: 0 1px 2px rgba(100, 70, 20, 0.4);
  }

  .ribbon-silver {
    background: linear-gradient(135deg, #e4e9ed 0%, #9aa8b2 100%);
    color: #ffffff;
    border: 1px solid rgba(255, 255, 255, 0.7);
    box-shadow: 0 2px 6px rgba(154, 168, 178, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.7);
    text-shadow: 0 1px 2px rgba(70, 80, 90, 0.4);
  }

  .ribbon-bronze {
    background: linear-gradient(135deg, #debca6 0%, #a47657 100%);
    color: #ffffff;
    border: 1px solid rgba(255, 255, 255, 0.6);
    box-shadow: 0 2px 6px rgba(164, 118, 87, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.6);
    text-shadow: 0 1px 2px rgba(90, 60, 40, 0.4);
  }

  .ribbon-default {
    background: #fbf9f4;
    color: #8c7b68;
    border: 1px solid #e2d8c3;
    box-shadow: inset 0 1px 1px rgba(70, 52, 30, 0.06);
  }

  /* --- 4-Bar Dancing Audio Spectrum Equalizer --- */
  .spectrum-bar {
    display: inline-block;
    width: 2px;
    border-radius: 1px;
    background: #b88a38;
    animation: spectrumBounce 0.8s ease-in-out infinite alternate;
    animation-play-state: paused;
    transform-origin: bottom;
  }
  .decorations-active .spectrum-bar { animation-play-state: running; }
  .bar-1 { height: 40%; animation-delay: 0.1s; }
  .bar-2 { height: 90%; animation-delay: 0.3s; }
  .bar-3 { height: 60%; animation-delay: 0.2s; }
  .bar-4 { height: 75%; animation-delay: 0.4s; }

  @keyframes spectrumBounce {
    0% { transform: scaleY(0.3); }
    50% { transform: scaleY(1); }
    100% { transform: scaleY(0.45); }
  }
</style>
