<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import { AlphaTabApi, model, Settings, LayoutMode, TabRhythmMode, StaveProfile, PlayerMode, NotationElement } from '@coderline/alphatab';
  import { installBrowserAr } from '../../lib/ar.browser';
  import { decodeIbeToJsonBrowser } from '../../lib/ibe.browser';
  import { createScoreSettings, installScoreLayoutFixes } from '../../lib/playerSettings';
  import { addLyricsTopSpacer } from '../../lib/scoreLyricsLayout.mjs';
  import { replaceWholeRestsInSecondaryTracks, applyScoreDisplayMode, DEFAULT_SCORE_DISPLAY_MODE } from '../../lib/scoreDisplayMode.mjs';
  import { fetchScoreBytes } from '../../lib/scoreLoadRequest.mjs';
  import { scoreLoadFailurePresentation } from '../../lib/scoreLoadGuard.mjs';
  import { createVectorManuscriptLifecycle } from '../../lib/player/vectorManuscriptLifecycle.mjs';
  import {
    buildManuscriptBeatBarIndex,
    resolveManuscriptBarIndexForBeatGroup,
  } from '../../lib/player/manuscriptBeatBars.mjs';

  let {
    scoreUrl = '',
    title = '',
    artist = '',
    tabKey = 'G',
    capo = 0,
    bpm = 80,
    tabId = '',
  }: {
    scoreUrl?: string;
    title?: string;
    artist?: string;
    tabKey?: string;
    capo?: number;
    bpm?: number;
    tabId?: string;
  } = $props();

  interface PageData {
    pageIndex: number;
    svgHtml: string;
    width: number;
    height: number;
  }

  // Component state
  let offscreenContainer: HTMLDivElement | null = $state(null);
  let galleryContainer: HTMLDivElement | null = $state(null);
  let pageRefs: HTMLElement[] = $state([]);

  let loading = $state(true);
  let error = $state('');
  let pages: PageData[] = $state([]);
  let totalPages = $derived(pages.length);
  let currentPage = $state(1);
  let isZenReader = $state(false);
  let zoomLevel = $state(1.0);
  let activeMeasure = $state<number | null>(null);
  let toastMessage = $state('');
  let toastTimer: any = null;
  let seekRequestSequence = 0;
  let isDestroyed = false;
  let scoreForExtraction: any = null;

  type ManuscriptSeekResult =
    | { ok: true; occurrence: number; occurrenceCount: number }
    | { ok: false; message: string };

  const renderLifecycle = createVectorManuscriptLifecycle();
  let extractedGeneration = -1;
  let observerTimer: ReturnType<typeof setTimeout> | null = null;
  let observer: IntersectionObserver | null = null;

  function showToast(msg: string, durationMs = 2400) {
    toastMessage = msg;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toastMessage = '';
    }, durationMs);
  }

  function zoomIn() {
    zoomLevel = Math.min(2.2, +(zoomLevel + 0.15).toFixed(2));
  }

  function zoomOut() {
    zoomLevel = Math.max(0.5, +(zoomLevel - 0.15).toFixed(2));
  }

  function resetZoom() {
    zoomLevel = 1.0;
  }

  function toggleZenReader() {
    isZenReader = !isZenReader;
    if (typeof document !== 'undefined') {
      document.body.style.overflow = isZenReader ? 'hidden' : '';
    }
  }

  function closeZenReader() {
    if (isZenReader) {
      isZenReader = false;
      if (typeof document !== 'undefined') {
        document.body.style.overflow = '';
      }
    }
  }

  function scrollToPage(pageIndex1Based: number) {
    const targetIdx = Math.max(0, Math.min(pageIndex1Based - 1, totalPages - 1));
    const targetEl = pageRefs[targetIdx];
    if (targetEl) {
      targetEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
      currentPage = targetIdx + 1;
    }
  }

  function handlePrint() {
    if (typeof window !== 'undefined') {
      window.print();
    }
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      if (isZenReader) {
        closeZenReader();
      }
    } else if (isZenReader) {
      if (e.key === 'ArrowRight' || e.key === 'PageDown') {
        e.preventDefault();
        scrollToPage(currentPage + 1);
      } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {
        e.preventDefault();
        scrollToPage(currentPage - 1);
      } else if (e.key === '+' || e.key === '=') {
        e.preventDefault();
        zoomIn();
      } else if (e.key === '-' || e.key === '_') {
        e.preventDefault();
        zoomOut();
      } else if (e.key === '0') {
        e.preventDefault();
        resetZoom();
      }
    }
  }

  function handleSvgClick(event: MouseEvent) {
    const target = event.target as HTMLElement | SVGElement | null;
    if (!target) return;

    // AlphaTab emits `b${beat.id}` groups, not bar-index groups. Only use the
    // model-resolved marker injected during extraction.
    const barEl = target.closest('[data-bar-index]') as HTMLElement | SVGElement | null;
    const rawBarIndex = barEl?.getAttribute('data-bar-index') ?? null;
    const parsedBarIndex = rawBarIndex !== null && /^\d+$/.test(rawBarIndex)
      ? Number(rawBarIndex)
      : Number.NaN;
    const barIndex = Number.isSafeInteger(parsedBarIndex) && parsedBarIndex >= 0
      ? parsedBarIndex
      : null;

    if (barIndex !== null && barIndex >= 0) {
      const measureNumber = barIndex + 1;
      activeMeasure = measureNumber;

      if (typeof window !== 'undefined') {
        const requestId = ++seekRequestSequence;
        let dispatching = true;
        let synchronousResult: ManuscriptSeekResult | null = null;
        const applySeekResult = (result: ManuscriptSeekResult) => {
          if (isDestroyed || requestId !== seekRequestSequence) return;
          if (!result.ok) {
            showToast(result.message);
          } else if (result.occurrenceCount > 1) {
            showToast(`已同步至第 ${measureNumber} 小节（按当前位置选中第 ${result.occurrence}/${result.occurrenceCount} 次演奏）🎵`);
          } else {
            showToast(`已同步至第 ${measureNumber} 小节 🎵`);
          }
        };
        const request = new CustomEvent('mimi:seek-bar', {
          cancelable: true,
          detail: {
            barIndex,
            measure: measureNumber,
            onResult: (result: ManuscriptSeekResult) => {
              if (dispatching) synchronousResult = result;
              else applySeekResult(result);
            },
          },
        });

        window.dispatchEvent(request);
        dispatching = false;
        if (synchronousResult) {
          applySeekResult(synchronousResult);
        } else if (request.defaultPrevented) {
          showToast(`正在定位至第 ${measureNumber} 小节…`, 5000);
        } else {
          showToast(`已选择第 ${measureNumber} 小节；播放器尚未连接。`);
        }
      }
    } else {
      showToast('请点击音符定位所在小节。');
    }
  }

  function setupIntersectionObserver() {
    if (typeof window === 'undefined' || !('IntersectionObserver' in window)) return;
    if (observer) {
      observer.disconnect();
      observer = null;
    }

    observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting && entry.intersectionRatio >= 0.35) {
          const idx = Number(entry.target.getAttribute('data-page-index'));
          if (!isNaN(idx)) {
            currentPage = idx + 1;
          }
        }
      }
    }, {
      rootMargin: '-8% 0px -40% 0px',
      threshold: [0.2, 0.4, 0.6, 0.8],
    });

    pageRefs.forEach((el) => {
      if (el) observer?.observe(el);
    });
  }

  function extractPages(): boolean {
    if (!offscreenContainer) return false;
    if (extractedGeneration === renderLifecycle.generation) return true;

    // Find all rendered SVGs inside offscreen container
    const allSvgs = Array.from(offscreenContainer.querySelectorAll('.at-surface svg, .at-page svg, svg')) as SVGSVGElement[];
    
    // Filter to retain true score content SVGs
    const validSvgs = allSvgs.filter((svg) => {
      const rectCount = svg.querySelectorAll('rect, path, text').length;
      return rectCount > 5;
    });

    if (validSvgs.length === 0) {
      // Fallback: If no nested filtered SVG was found, grab all SVGs with width/height
      const fallbackSvgs = allSvgs.filter((s) => s.clientWidth > 100 || s.getAttribute('viewBox'));
      if (fallbackSvgs.length > 0) {
        validSvgs.push(...fallbackSvgs);
      }
    }

    if (validSvgs.length > 0) {
      const beatToBarIndex = buildManuscriptBeatBarIndex(scoreForExtraction?.tracks);
      const extracted: PageData[] = validSvgs.map((svg, idx) => {
        for (const group of Array.from(svg.querySelectorAll('g[class]'))) {
          const barIndex = resolveManuscriptBarIndexForBeatGroup(
            group.getAttribute('class'),
            beatToBarIndex,
          );
          if (barIndex !== null) {
            group.setAttribute('data-bar-index', String(barIndex));
            (group as SVGGElement).style.cursor = 'pointer';
          }
        }

        let vb = svg.getAttribute('viewBox');
        let w = parseFloat(svg.getAttribute('width') || '1180') || 1180;
        let h = parseFloat(svg.getAttribute('height') || '1660') || 1660;

        if (!vb) {
          vb = `0 0 ${w} ${h}`;
          svg.setAttribute('viewBox', vb);
        }

        // 关键修复：向每一个提取出的 SVG 节点注入完整 @font-face 样式规则，
        // 彻底杜绝 TAB 谱号、简谱附点连音线、三连音括号等符号因字体缺失显示为空白方块 []
        let defs = svg.querySelector('defs');
        if (!defs) {
          defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
          svg.insertBefore(defs, svg.firstChild);
        }
        const style = document.createElementNS('http://www.w3.org/2000/svg', 'style');
        style.textContent = `
          @font-face {
            font-family: 'alphaTab';
            src: url('/font/Bravura.woff2') format('woff2'), url('/font/Bravura.woff') format('woff');
            font-weight: normal;
            font-style: normal;
          }
          @font-face {
            font-family: 'Bravura';
            src: url('/font/Bravura.woff2') format('woff2'), url('/font/Bravura.woff') format('woff');
            font-weight: normal;
            font-style: normal;
          }
          @font-face {
            font-family: '方正小标宋简体';
            src: url('/font/FZXiaoBiaoSong.woff2') format('woff2'), url('/font/FZXiaoBiaoSong.TTF') format('truetype');
            font-weight: normal;
            font-style: normal;
          }
          @font-face {
            font-family: 'Cascadia Code';
            src: url('/font/CascadiaCode.woff2') format('woff2'), url('/font/CascadiaCode.ttf') format('truetype');
            font-weight: normal;
            font-style: normal;
          }
          text {
            font-family: 'alphaTab', 'Bravura', '方正小标宋简体', 'Cascadia Code', -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
          }
        `;
        defs.appendChild(style);

        // Set responsive sizing attributes
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', 'auto');
        svg.style.width = '100%';
        svg.style.height = 'auto';
        svg.style.display = 'block';

        return {
          pageIndex: idx,
          svgHtml: svg.outerHTML,
          width: w,
          height: h,
        };
      });

      pages = extracted;
      extractedGeneration = renderLifecycle.generation;
      loading = false;
      error = '';

      const completedGeneration = renderLifecycle.generation;
      if (observerTimer) clearTimeout(observerTimer);
      observerTimer = setTimeout(() => {
        if (renderLifecycle.isCurrent(completedGeneration)) setupIntersectionObserver();
      }, 100);
      return true;
    } else {
      // AlphaTab may announce render completion before it appends every SVG.
      // Keep the watchdog armed so a later completion event can still extract pages.
      return false;
    }
  }

  async function renderManuscriptScore(retry = false) {
    if (!scoreUrl) {
      error = '未提供乐谱数据源（非矢量格式或曲谱地址为空）';
      loading = false;
      return;
    }

    if (!offscreenContainer) return;

    const attempt = renderLifecycle.begin();
    if (observerTimer) clearTimeout(observerTimer);
    observer?.disconnect();
    const signal = attempt.signal;

    loading = true;
    error = '';
    pages = [];
    extractedGeneration = -1;
    scoreForExtraction = null;

    // Safety watchdog timer (18s)
    const watchdog = setTimeout(() => {
      if (attempt.isCurrent() && loading) {
        if (!extractPages() && loading) {
          loading = false;
          error = '矢量画卷排版超时，请点击重试。';
          attempt.dispose();
        }
      }
    }, 18000);
    attempt.track(() => clearTimeout(watchdog));

    let loadStage = 'fetch';
    try {
      installBrowserAr();
      installScoreLayoutFixes();

      // Configure AlphaTab for pristine Page vector rendering
      const settings = createScoreSettings();
      settings.core.scriptFile = '/alphaTab.js';
      settings.core.fontDirectory = '/font/';
      settings.core.engine = 'svg';
      settings.core.useWorkers = false;
      settings.core.enableLazyLoading = false;

      // Page layout mode with high-density typesetting
      settings.display.layoutMode = LayoutMode.Page;
      settings.display.scale = 0.96;
      settings.display.stretchForce = 0.5;
      settings.display.staveProfile = StaveProfile.Default;

      // 关键修复：收紧谱表垂直间距，消除六线谱与简谱之间过大的垂直空洞
      settings.display.notationStaffPaddingTop = 14;
      settings.display.notationStaffPaddingBottom = 10;
      settings.display.lastNotationStaffPaddingBottom = 18;
      settings.display.effectBandPaddingBottom = 14;
      settings.display.systemPaddingTop = 18;
      settings.display.systemPaddingBottom = 22;
      settings.display.firstSystemPaddingTop = 16;

      // Pure vector rendering pipeline (synthesizer/sound player disabled in offscreen mode)
      settings.player.enablePlayer = false;
      settings.player.playerMode = PlayerMode.Disabled;
      settings.player.enableCursor = false;
      settings.player.enableAnimatedBeatCursor = false;
      settings.player.enableElementHighlighting = false;
      settings.player.enableUserInteraction = false;

      // Essential score display configuration
      settings.notation.rhythmMode = TabRhythmMode.ShowWithBars;
      settings.notation.elements.set(NotationElement.ChordDiagrams, false);
      settings.notation.elements.set(NotationElement.EffectChordNames, true);
      settings.notation.elements.set(NotationElement.EffectLyrics, true);
      settings.notation.elements.set(NotationElement.GuitarTuning, false);
      settings.notation.elements.set(NotationElement.TrackNames, false);
      settings.notation.elements.set(NotationElement.ScoreWords, false);
      settings.notation.elements.set(NotationElement.ScoreMusic, false);

      // Clean offscreen element
      offscreenContainer.innerHTML = '';

      const alphaTabInstance = new AlphaTabApi(offscreenContainer, settings);
      attempt.attach(alphaTabInstance);

      alphaTabInstance.renderFinished.on(() => {
        if (!attempt.isCurrent()) return;
        const extractionTimer = setTimeout(() => {
          if (attempt.isCurrent() && extractPages()) {
            clearTimeout(watchdog);
          }
        }, 60);
        attempt.track(() => clearTimeout(extractionTimer));
      });

      alphaTabInstance.postRenderFinished.on(() => {
        if (!attempt.isCurrent()) return;
        if (extractPages()) clearTimeout(watchdog);
      });

      alphaTabInstance.error.on((err) => {
        if (!attempt.isCurrent()) return;
        console.warn('[VectorManuscriptRoll] alphaTab render notice:', err);
      });

      // Fetch score binary
      const buf = await fetchScoreBytes(scoreUrl, { signal, retry });

      if (!attempt.isCurrent()) return;

      // Decode score JSON
      loadStage = 'decode';
      const json = await decodeIbeToJsonBrowser(buf);
      if (!attempt.isCurrent()) return;

      const renderJson = JSON.parse(JSON.stringify(json));
      replaceWholeRestsInSecondaryTracks(renderJson);
      addLyricsTopSpacer(renderJson);

      loadStage = 'convert';
      const score = model.JsonConverter.jsonToScore(JSON.stringify(renderJson), settings);

      if (title) score.title = title;
      if (artist) score.artist = artist;
      for (const t of score.tracks || []) {
        for (const st of t.staves || []) {
          st.capo = capo;
          st.showStandardNotation = false;
        }
      }

      applyScoreDisplayMode(score, DEFAULT_SCORE_DISPLAY_MODE);

      const visibleTracks = score.tracks.map((_: any, idx: number) => idx);
      scoreForExtraction = score;
      loadStage = 'render';
      alphaTabInstance.renderScore(score, visibleTracks);

    } catch (err: any) {
      if (!attempt.isCurrent()) return;
      clearTimeout(watchdog);
      console.error('[VectorManuscriptRoll] Error rendering vector manuscript:', err);
      error = scoreLoadFailurePresentation(scoreUrl, loadStage, err).message;
      loading = false;
      attempt.dispose();
    }
  }

  let isMounted = false;
  $effect(() => {
    if (isMounted) return;
    if (!offscreenContainer) return;
    isMounted = true;
    untrack(() => {
      void renderManuscriptScore();
    });
  });

  onDestroy(() => {
    isDestroyed = true;
    seekRequestSequence++;
    renderLifecycle.dispose();
    if (observerTimer) clearTimeout(observerTimer);
    if (toastTimer) clearTimeout(toastTimer);
    if (observer) {
      observer.disconnect();
    }
    if (typeof document !== 'undefined') {
      document.body.style.overflow = '';
    }
  });
</script>

<svelte:window onkeydown={handleKeyDown} />

<!-- Offscreen AlphaTab Layout Sandbox (Hidden from DOM flow, precisely sized for A4 Page proportion) -->
<div
  bind:this={offscreenContainer}
  class="vector-offscreen-sandbox"
  aria-hidden="true"
  style="position: absolute; left: -9999px; top: -9999px; width: 1180px; height: 1660px; overflow: hidden; visibility: hidden; pointer-events: none; opacity: 0; z-index: -100;"
></div>

<div class="vector-manuscript-deck relative mt-10 pt-8 border-t border-[#e8dfd2]">
  <!-- Deck Header & Zen Toolbar Trigger -->
  <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-6">
    <div>
      <div class="flex items-center gap-2">
        <span class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45]/40 bg-[#c49a45]/10 px-3 py-0.5 text-xs font-mono font-bold text-[#8a6b29]">
          <span>📜</span>
          <span>VECTOR SCORE ROLL</span>
        </span>
        <span class="h-4 w-[1px] bg-[#e0d6c0] hidden sm:inline-block"></span>
        <h2 class="font-display text-xl sm:text-2xl font-bold text-[#2c2825]">
          出版级多页高保真矢量手稿画卷
        </h2>
      </div>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-1.5 leading-relaxed">
        基于原生矢量排版引擎渲染 · 点击音符定位所在小节并同步试听 · 支持原比例缩放、沉浸阅读与 A4 矢量打印
      </p>
    </div>

    <!-- Quick Tool Actions in Header -->
    <div class="flex items-center gap-2.5 shrink-0">
      <button
        type="button"
        onclick={toggleZenReader}
        class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45]/60 bg-[#fbf9f4] hover:bg-[#c49a45] hover:text-[#1a1816] px-4 py-1.5 text-xs font-serif font-bold text-[#8a6b29] transition-all shadow-2xs hover:shadow-xs active:scale-95 cursor-pointer"
        title="开启全屏沉浸阅读体验"
      >
        <span>🔍</span>
        <span>全屏沉浸画卷</span>
      </button>

      <button
        type="button"
        onclick={handlePrint}
        class="inline-flex items-center gap-1.5 rounded-full border border-[#dfd6c7] bg-[#ffffff] hover:bg-[#f7f3eb] px-3.5 py-1.5 text-xs font-serif text-[#5c4a38] transition-all shadow-2xs cursor-pointer"
        title="标准 A4 纸张矢量打印与另存 PDF"
      >
        <span>🖨️</span>
        <span>A4 打印 / 存PDF</span>
      </button>

      {#if tabId}
        <a
          href={`/studio?cloneFrom=${tabId}`}
          class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45]/40 bg-[#c49a45]/10 hover:bg-[#c49a45] hover:text-[#1a1715] px-3.5 py-1.5 text-xs font-serif font-bold text-[#8a6b29] transition-all shadow-2xs cursor-pointer"
          title="将本曲谱克隆导入制谱工坊进行自由改编与编辑"
        >
          <span>🛠️</span>
          <span>工坊自由改编</span>
        </a>
      {/if}
    </div>
  </div>

  <!-- Loading State: Warm Shimmer Skeleton -->
  {#if loading}
    <div class="relative rounded-3xl border border-[#e2d8c3] bg-gradient-to-b from-[#fbf9f4] via-[#f7f2e7] to-[#f4eee2] p-8 sm:p-14 shadow-[0_12px_36px_rgba(76,59,43,0.06)] overflow-hidden">
      <!-- Animated Shimmer Wave -->
      <div class="pointer-events-none absolute inset-0 bg-gradient-to-r from-transparent via-[#c49a45]/15 to-transparent animate-shimmer"></div>
      
      <!-- Four Gold Corner Accents -->
      <div class="pointer-events-none absolute top-4 left-4 w-4 h-4 border-t-2 border-l-2 border-[#c49a45]/40 rounded-tl-sm"></div>
      <div class="pointer-events-none absolute top-4 right-4 w-4 h-4 border-t-2 border-r-2 border-[#c49a45]/40 rounded-tr-sm"></div>
      <div class="pointer-events-none absolute bottom-4 left-4 w-4 h-4 border-b-2 border-l-2 border-[#c49a45]/40 rounded-bl-sm"></div>
      <div class="pointer-events-none absolute bottom-4 right-4 w-4 h-4 border-b-2 border-r-2 border-[#c49a45]/40 rounded-br-sm"></div>

      <div class="relative z-10 flex flex-col items-center justify-center text-center py-12 space-y-4">
        <div class="relative flex items-center justify-center">
          <div class="w-14 h-14 rounded-full border-2 border-[#c49a45]/30 border-t-[#c49a45] animate-spin"></div>
          <span class="absolute text-xl">📜</span>
        </div>
        <div class="space-y-1">
          <h3 class="text-base sm:text-lg font-serif font-bold text-[#2c2825]">
            正在排版高保真矢量画卷...
          </h3>
          <p class="text-xs sm:text-sm text-[#8c7b68] font-serif">
            AlphaTab 矢量排版引擎正在进行出版级分页与高保真矢量化运算
          </p>
        </div>

        <!-- Faux Notation Staff Lines Simulation -->
        <div class="w-full max-w-md space-y-2 pt-4 opacity-40">
          <div class="h-1.5 bg-[#d4c8b8] rounded-full w-full"></div>
          <div class="h-1.5 bg-[#d4c8b8] rounded-full w-5/6 mx-auto"></div>
          <div class="h-1.5 bg-[#d4c8b8] rounded-full w-4/6 mx-auto"></div>
        </div>
      </div>
    </div>
  {:else if error}
    <!-- Error / Fallback State -->
    <div class="rounded-3xl border border-[#e2d8c3] bg-[#fbf9f4] p-8 sm:p-12 text-center space-y-4 shadow-xs">
      <div class="inline-flex items-center justify-center w-12 h-12 rounded-full bg-[#c84b31]/10 text-[#c84b31] text-2xl mb-1">
        <span>🎼</span>
      </div>
      <h3 class="font-display text-base sm:text-lg font-bold text-[#2c2825]">
        未能在本画卷中渲染矢量手稿
      </h3>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif max-w-md mx-auto leading-relaxed">
        {error}
      </p>
      <div class="flex flex-wrap items-center justify-center gap-3 pt-3">
        <button
          type="button"
          onclick={() => { void renderManuscriptScore(true); }}
          class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45] bg-[#c49a45] text-[#1a1715] px-4 py-2 text-xs font-serif font-bold hover:bg-[#b08836] transition-all shadow-2xs cursor-pointer"
        >
          <span>🔄</span>
          <span>重试排版</span>
        </button>
        {#if tabId}
          <a
            href={`/studio?cloneFrom=${tabId}`}
            class="inline-flex items-center gap-1.5 rounded-full border border-[#dfd6c7] bg-[#ffffff] text-[#5c4a38] px-4 py-2 text-xs font-serif hover:bg-[#f7f3eb] transition-all shadow-2xs cursor-pointer"
          >
            <span>🛠️</span>
            <span>进入工坊查看与改编</span>
          </a>
        {/if}
      </div>
    </div>
  {:else}
    <!-- Floating Glass Capsule Toolbar -->
    <aside
      class="sticky z-40 mx-auto mb-4 w-fit flex items-center gap-1.5 sm:gap-2.5 px-3.5 sm:px-5 py-2 rounded-full bg-[#24201d]/90 backdrop-blur-xl border border-[#c49a45]/40 text-[#fbf9f4] shadow-[0_12px_40px_rgba(0,0,0,0.38)] transition-all max-w-full overflow-x-auto"
      style="top: max(6rem, calc(100dvh - 12rem));"
      aria-label="手稿画卷控制栏"
    >
      <!-- Page Navigation -->
      <div class="flex items-center gap-1 shrink-0">
        <button
          type="button"
          onclick={() => scrollToPage(currentPage - 1)}
          disabled={currentPage <= 1}
          class="w-7 h-7 rounded-full flex items-center justify-center text-xs font-mono bg-[#ffffff]/10 hover:bg-[#c49a45] hover:text-[#1a1715] disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-inherit transition-colors cursor-pointer"
          title="上一页"
        >
          ◀
        </button>
        <span class="text-xs font-mono px-2 text-[#e0d6c0] font-semibold whitespace-nowrap">
          {currentPage} / {totalPages}
        </span>
        <button
          type="button"
          onclick={() => scrollToPage(currentPage + 1)}
          disabled={currentPage >= totalPages}
          class="w-7 h-7 rounded-full flex items-center justify-center text-xs font-mono bg-[#ffffff]/10 hover:bg-[#c49a45] hover:text-[#1a1715] disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-inherit transition-colors cursor-pointer"
          title="下一页"
        >
          ▶
        </button>
      </div>

      <span class="w-[1px] h-4 bg-white/20 shrink-0"></span>

      <!-- Zoom Controls -->
      <div class="flex items-center gap-1 shrink-0">
        <button
          type="button"
          onclick={zoomOut}
          class="w-7 h-7 rounded-full flex items-center justify-center text-xs bg-[#ffffff]/10 hover:bg-[#ffffff]/25 text-[#fbf9f4] transition-colors cursor-pointer"
          title="缩小"
        >
          ➖
        </button>
        <button
          type="button"
          onclick={resetZoom}
          class="text-xs font-mono px-1.5 py-0.5 rounded bg-[#ffffff]/10 hover:bg-[#c49a45] hover:text-[#1a1715] text-[#d4c8b8] transition-colors cursor-pointer"
          title="重置缩放 100%"
        >
          {Math.round(zoomLevel * 100)}%
        </button>
        <button
          type="button"
          onclick={zoomIn}
          class="w-7 h-7 rounded-full flex items-center justify-center text-xs bg-[#ffffff]/10 hover:bg-[#ffffff]/25 text-[#fbf9f4] transition-colors cursor-pointer"
          title="放大"
        >
          ➕
        </button>
      </div>

      <span class="w-[1px] h-4 bg-white/20 shrink-0"></span>

      <!-- Zen Reader Toggle Button -->
      <button
        type="button"
        onclick={toggleZenReader}
        class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#c49a45]/20 hover:bg-[#c49a45] hover:text-[#1a1715] text-xs font-serif font-bold text-[#e6c67c] transition-all cursor-pointer whitespace-nowrap"
        title="开启全屏沉浸模式"
      >
        <span>🔍</span>
        <span class="hidden sm:inline">沉浸模式</span>
      </button>

      <!-- Print Button -->
      <button
        type="button"
        onclick={handlePrint}
        class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#ffffff]/10 hover:bg-[#ffffff]/25 text-xs font-serif text-[#fbf9f4] transition-colors cursor-pointer whitespace-nowrap"
        title="标准 A4 打印与另存 PDF"
      >
        <span>🖨️</span>
        <span class="hidden sm:inline">打印</span>
      </button>

      {#if tabId}
        <a
          href={`/studio?cloneFrom=${tabId}`}
          class="inline-flex items-center gap-1 px-3 py-1 rounded-full bg-[#ffffff]/10 hover:bg-[#c49a45] hover:text-[#1a1715] text-xs font-serif text-[#fbf9f4] transition-colors cursor-pointer whitespace-nowrap"
          title="进入制谱工坊自由改编"
        >
          <span>🛠️</span>
          <span class="hidden sm:inline">改编</span>
        </a>
      {/if}
    </aside>

    <!-- Rendered Vector Pages Gallery Roll -->
    <div
      bind:this={galleryContainer}
      class="vector-gallery-roll relative space-y-8 sm:space-y-12"
      style={`--roll-zoom: ${zoomLevel}; width: 100%;`}
    >
      {#each pages as page, i (page.pageIndex)}
        <article
          bind:this={pageRefs[i]}
          data-page-index={i}
          class="manuscript-page-sheet group relative rounded-3xl border border-[#e2d8c3] bg-gradient-to-b from-[#fbf9f4] via-[#f7f2e7] to-[#f4eee2] p-4 sm:p-8 lg:p-10 shadow-[0_16px_48px_rgba(76,59,43,0.06)] hover:border-[#c49a45]/60 hover:shadow-[0_20px_54px_rgba(196,154,69,0.14)] transition-all duration-300 overflow-hidden"
          style={`transform-origin: top center; width: 100%; max-width: ${Math.round(1140 * zoomLevel)}px; margin-left: auto; margin-right: auto;`}
        >
          <!-- Paper Texture Subtle Background -->
          <div class="pointer-events-none absolute inset-0 opacity-[0.18] bg-[radial-gradient(#8c7b68_1px,transparent_1px)] [background-size:16px_16px]"></div>

          <!-- Antique Gold Corner Accents -->
          <div class="pointer-events-none absolute top-4 left-4 w-5 h-5 border-t-2 border-l-2 border-[#c49a45]/40 rounded-tl-sm"></div>
          <div class="pointer-events-none absolute top-4 right-4 w-5 h-5 border-t-2 border-r-2 border-[#c49a45]/40 rounded-tr-sm"></div>
          <div class="pointer-events-none absolute bottom-4 left-4 w-5 h-5 border-b-2 border-l-2 border-[#c49a45]/40 rounded-bl-sm"></div>
          <div class="pointer-events-none absolute bottom-4 right-4 w-5 h-5 border-b-2 border-r-2 border-[#c49a45]/40 rounded-br-sm"></div>

          <!-- Page Header -->
          <header class="relative z-10 flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 mb-4 border-b border-[#e8dfd2]">
            <div class="flex items-center gap-2.5 flex-wrap">
              <span class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-[#c49a45]/15 border border-[#c49a45]/40 text-[11px] font-serif font-bold text-[#8a6b29]">
                <span>📜</span>
                <span>典藏纸本手稿</span>
              </span>
              <h3 class="font-display font-bold text-base sm:text-lg text-[#2c2825]">
                {title}
              </h3>
              {#if artist}
                <span class="text-xs sm:text-sm text-[#7a6b58] font-serif">
                  · {artist}
                </span>
              {/if}
            </div>

            <!-- Page Meta & Jumper Tag -->
            <div class="flex items-center gap-2 shrink-0">
              <span class="px-2.5 py-0.5 rounded-full bg-[#ffffff]/90 border border-[#dfd6c7] text-[11px] font-mono text-[#7a6b58]">
                {tabKey} 调 {capo > 0 ? `· 夹 ${capo} 品` : ''} {bpm ? `· ♩=${bpm}` : ''}
              </span>
              <span class="px-3 py-0.5 rounded-full bg-[#f4eee2] border border-[#c49a45]/40 text-xs font-mono font-bold text-[#8a6b29]">
                第 {i + 1} 页 / 共 {totalPages} 页
              </span>
            </div>
          </header>

          <!-- Score Page SVG Body -->
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="score-svg-viewport relative rounded-2xl bg-[#ffffff] border border-[#e8e0d0] p-2 sm:p-4 shadow-inner overflow-hidden"
            onclick={handleSvgClick}
            title="点击音符定位所在小节并同步试听；空白处不可定位"
          >
            {@html page.svgHtml}
          </div>

          <!-- Page Footer: Authenticity Seal & Copyright -->
          <footer class="relative z-10 flex flex-col sm:flex-row sm:items-center justify-between gap-2 pt-4 mt-4 border-t border-[#e8dfd2] text-xs font-serif text-[#8c7b68]">
            <div>
              <span class="font-medium text-[#5c4a38]">MIMI Guitar 官方认证精校版面 · 出版级高保真矢量手稿</span>
              <span class="text-[10px] text-[#a0907d] block font-mono">MASTER VECTOR MANUSCRIPT · ARCHIVAL QUALITY</span>
            </div>

            <!-- Red Cinnabar Seal Stamp -->
            <div class="flex items-center gap-2 self-end sm:self-auto">
              <div class="inline-flex items-center gap-1 px-2.5 py-0.5 border border-[#c84b31] bg-[#c84b31]/5 text-[#c84b31] rounded-xs font-serif font-bold text-[11px] transform -rotate-1 select-none shadow-2xs">
                <span class="text-xs">印</span>
                <span class="tracking-widest">典藏真迹</span>
              </div>
            </div>
          </footer>
        </article>
      {/each}
    </div>

  {/if}
</div>

<!-- Zen Reader Fullscreen Overlay (全屏沉浸模式) -->
{#if isZenReader}
  <div
    class="fixed inset-0 z-50 bg-[#141210]/95 backdrop-blur-2xl overflow-y-auto flex flex-col items-center py-6 px-3 sm:px-8"
    role="dialog"
    aria-modal="true"
    aria-label="全屏沉浸乐谱画卷"
  >
    <!-- Zen Reader Top Bar -->
    <header class="sticky top-0 z-50 w-full max-w-5xl flex items-center justify-between px-4 py-3 rounded-2xl bg-[#24201d]/90 backdrop-blur-xl border border-[#c49a45]/40 text-[#fbf9f4] mb-6 shadow-2xl">
      <div class="flex items-center gap-3">
        <span class="text-lg">📜</span>
        <div>
          <h3 class="text-sm sm:text-base font-display font-bold text-[#fbf9f4]">
            {title}
          </h3>
          <p class="text-[11px] text-[#c49a45] font-serif">
            {artist || '精校手稿'} · 第 {currentPage} / {totalPages} 页 · 沉浸阅读中 (ESC 退出)
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <button
          type="button"
          onclick={zoomOut}
          class="w-8 h-8 rounded-full bg-[#ffffff]/10 hover:bg-[#ffffff]/25 text-xs text-center cursor-pointer"
          title="缩小"
        >
          ➖
        </button>
        <span class="text-xs font-mono text-[#d4c8b8] px-1">
          {Math.round(zoomLevel * 100)}%
        </span>
        <button
          type="button"
          onclick={zoomIn}
          class="w-8 h-8 rounded-full bg-[#ffffff]/10 hover:bg-[#ffffff]/25 text-xs text-center cursor-pointer"
          title="放大"
        >
          ➕
        </button>

        <span class="w-[1px] h-4 bg-white/20 mx-1"></span>

        <button
          type="button"
          onclick={closeZenReader}
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-[#c84b31]/20 hover:bg-[#c84b31] text-[#ffffff] text-xs font-serif font-bold transition-colors cursor-pointer"
        >
          <span>✕</span>
          <span>退出沉浸</span>
        </button>
      </div>
    </header>

    <!-- Zen Manuscript Roll Body -->
    <main class="w-full flex flex-col items-center space-y-8 sm:space-y-12 pb-24">
      {#each pages as page, i (page.pageIndex)}
        <article
          class="zen-page-card relative rounded-3xl border border-[#c49a45]/50 bg-gradient-to-b from-[#faf8f5] via-[#f7f2e7] to-[#f4eee2] p-4 sm:p-8 lg:p-10 shadow-[0_24px_64px_rgba(0,0,0,0.5)] overflow-hidden"
          style={`width: 100%; max-width: ${Math.round(1120 * zoomLevel)}px;`}
        >
          <!-- Corner Accents -->
          <div class="pointer-events-none absolute top-4 left-4 w-5 h-5 border-t-2 border-l-2 border-[#c49a45]/60 rounded-tl-sm"></div>
          <div class="pointer-events-none absolute top-4 right-4 w-5 h-5 border-t-2 border-r-2 border-[#c49a45]/60 rounded-tr-sm"></div>
          <div class="pointer-events-none absolute bottom-4 left-4 w-5 h-5 border-b-2 border-l-2 border-[#c49a45]/60 rounded-bl-sm"></div>
          <div class="pointer-events-none absolute bottom-4 right-4 w-5 h-5 border-b-2 border-r-2 border-[#c49a45]/60 rounded-br-sm"></div>

          <header class="flex items-center justify-between pb-3 mb-3 border-b border-[#e8dfd2]">
            <div class="flex items-center gap-2">
              <span class="text-xs font-serif font-bold text-[#8a6b29]">📜 典藏纸本手稿 · {title}</span>
            </div>
            <span class="text-xs font-mono font-bold text-[#8a6b29] bg-[#f4eee2] px-2.5 py-0.5 rounded-full border border-[#c49a45]/30">
              第 {i + 1} 页 / 共 {totalPages} 页
            </span>
          </header>

          <!-- Score SVG -->
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="score-svg-viewport rounded-2xl bg-[#ffffff] border border-[#e8e0d0] p-2 sm:p-4 shadow-inner overflow-hidden"
            onclick={handleSvgClick}
            title="点击音符定位所在小节并同步试听；空白处不可定位"
          >
            {@html page.svgHtml}
          </div>

          <footer class="flex items-center justify-between pt-3 mt-3 border-t border-[#e8dfd2] text-xs font-serif text-[#8c7b68]">
            <span>MIMI Guitar 官方认证精校版面 · 出版级高保真矢量手稿</span>
            <span class="text-[#c84b31] font-medium">印 · 典藏真迹</span>
          </footer>
        </article>
      {/each}
    </main>
  </div>
{/if}

<!-- Toast Feedback Bubble -->
{#if toastMessage}
  <div
    class="fixed top-8 left-1/2 -translate-x-1/2 z-50 inline-flex items-center gap-2 px-4 py-2 rounded-full bg-[#24201d]/95 backdrop-blur-xl border border-[#c49a45] text-[#fbf9f4] text-xs font-serif font-bold shadow-2xl animate-fade-in"
    role="status"
    aria-live="polite"
  >
    <span class="text-[#c49a45]">✨</span>
    <span>{toastMessage}</span>
  </div>
{/if}

<style>
  @keyframes shimmer {
    0% { transform: translateX(-100%); }
    100% { transform: translateX(100%); }
  }

  @keyframes fadeIn {
    from { opacity: 0; transform: translate(-50%, -10px); }
    to { opacity: 1; transform: translate(-50%, 0); }
  }

  .animate-shimmer {
    animation: shimmer 2.2s infinite ease-in-out;
  }

  .animate-fade-in {
    animation: fadeIn 0.25s cubic-bezier(0.16, 1, 0.3, 1) forwards;
  }

  :global(.score-svg-viewport svg) {
    display: block;
    width: 100% !important;
    height: auto !important;
    font-family: 'Cascadia Code', '方正小标宋简体', 'Microsoft YaHei', sans-serif !important;
  }

  :global(.score-svg-viewport svg text) {
    text-rendering: geometricPrecision;
  }

  :global(.score-svg-viewport svg g[class*='b']) {
    cursor: pointer;
    transition: opacity 0.15s ease, filter 0.15s ease;
  }

  :global(.score-svg-viewport svg g[class*='b']:hover) {
    filter: drop-shadow(0 0 4px rgba(196, 154, 69, 0.45));
    opacity: 0.85;
  }

  /* Dedicated Publication-Grade A4 Print Styling */
  @media print {
    :global(body *) {
      visibility: hidden;
    }

    :global(body) {
      background: #ffffff !important;
      margin: 0 !important;
      padding: 0 !important;
    }

    .vector-manuscript-deck,
    .vector-manuscript-deck *,
    .manuscript-page-sheet,
    .manuscript-page-sheet * {
      visibility: visible !important;
    }

    .vector-manuscript-deck {
      position: absolute !important;
      left: 0 !important;
      top: 0 !important;
      width: 100% !important;
      margin: 0 !important;
      padding: 0 !important;
      border: none !important;
    }

    .manuscript-page-sheet {
      page-break-after: always !important;
      break-after: page !important;
      break-inside: avoid !important;
      margin: 0 0 20mm 0 !important;
      padding: 10mm !important;
      border: 1px solid #d4c8b8 !important;
      box-shadow: none !important;
      background: #ffffff !important;
      max-width: 100% !important;
      width: 100% !important;
      transform: none !important;
    }

    .score-svg-viewport {
      border: none !important;
      box-shadow: none !important;
      padding: 0 !important;
      background: transparent !important;
    }

    aside,
    button,
    a,
    .vector-offscreen-sandbox {
      display: none !important;
    }
  }
</style>
