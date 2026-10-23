<script lang="ts">
  import { onMount } from 'svelte';

  export let screenshotUrl: string;
  export let title: string;
  export let artist: string = '';
  export let tabKey: string = 'G';
  export let capo: number = 0;
  export let bpm: number = 80;
  export let tabId: string = '';

  let isLightboxOpen = false;
  let zoomLevel = 1;
  let isHovered = false;

  function openLightbox() {
    isLightboxOpen = true;
    zoomLevel = 1;
    if (typeof document !== 'undefined') {
      document.body.style.overflow = 'hidden';
    }
  }

  function closeLightbox() {
    isLightboxOpen = false;
    zoomLevel = 1;
    if (typeof document !== 'undefined') {
      document.body.style.overflow = '';
    }
  }

  function zoomIn(e?: MouseEvent) {
    e?.stopPropagation();
    zoomLevel = Math.min(zoomLevel + 0.25, 3);
  }

  function zoomOut(e?: MouseEvent) {
    e?.stopPropagation();
    zoomLevel = Math.max(zoomLevel - 0.25, 0.5);
  }

  function resetZoom(e?: MouseEvent) {
    e?.stopPropagation();
    zoomLevel = 1;
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Escape' && isLightboxOpen) {
      closeLightbox();
    }
  }
</script>

<svelte:window on:keydown={handleKeyDown} />

<div class="mt-10 pt-8 border-t border-[#e8dfd2] manuscript-gallery-deck">
  <!-- Section Title & Actions Header -->
  <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-6">
    <div>
      <div class="flex items-center gap-2">
        <span class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45]/30 bg-[#c49a45]/10 px-3 py-0.5 text-xs font-mono font-bold text-[#8a6b29]">
          <span>📜</span>
          <span>MANUSCRIPT ARCHIVE</span>
        </span>
        <span class="h-4 w-[1px] bg-[#e0d6c0] hidden sm:inline-block"></span>
        <h2 class="font-display text-xl sm:text-2xl font-bold text-[#2c2825]">
          谱面高清原稿与实体手稿展台
        </h2>
      </div>
      <p class="text-xs sm:text-sm text-[#8c7b68] font-serif mt-1.5 leading-relaxed">
        收录自母带级实体纸本原版排版扫描件 · 支持原比例高清检视与全屏沉浸缩放
      </p>
    </div>

    <!-- Quick Tool Actions -->
    <div class="flex items-center gap-2.5 shrink-0">
      <button
        type="button"
        on:click={openLightbox}
        class="inline-flex items-center gap-1.5 rounded-full border border-[#c49a45]/50 bg-[#fbf9f4] hover:bg-[#c49a45] hover:text-[#1a1816] px-4 py-1.5 text-xs font-serif font-bold text-[#8a6b29] transition-all shadow-2xs hover:shadow-xs active:scale-95 cursor-pointer"
      >
        <span>🔍</span>
        <span>全屏检视</span>
      </button>
      <a
        href={screenshotUrl}
        target="_blank"
        rel="noopener noreferrer"
        download={`${title}-${artist}-原版谱.jpg`}
        class="inline-flex items-center gap-1.5 rounded-full border border-[#dfd6c7] bg-[#ffffff] hover:bg-[#f7f3eb] px-3.5 py-1.5 text-xs font-serif text-[#5c4a38] transition-all shadow-2xs cursor-pointer"
        title="在新窗口打开原图"
      >
        <span>⬇️</span>
        <span>另存原图</span>
      </a>
    </div>
  </div>

  <!-- Showcase Split Layout (Left: Paper Exhibition Frame, Right: Curated Archival Deck) -->
  <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8 items-start">
    <!-- Left: Manuscript Exhibition Card (7 Cols) -->
    <div class="lg:col-span-7">
      <div
        class="group relative rounded-3xl border border-[#e2d8c3] bg-gradient-to-b from-[#fbf9f4] via-[#f7f2e7] to-[#f4eee2] p-3.5 sm:p-5 shadow-[0_12px_36px_rgba(76,59,43,0.06)] hover:border-[#c49a45]/70 hover:shadow-[0_16px_48px_rgba(196,154,69,0.16)] transition-all duration-300 overflow-hidden cursor-zoom-in"
        on:click={openLightbox}
        on:mouseenter={() => isHovered = true}
        on:mouseleave={() => isHovered = false}
        role="button"
        tabindex="0"
        aria-label="点击开启全屏检视原版手稿"
      >
        <!-- Paper Texture Background -->
        <div class="pointer-events-none absolute inset-0 opacity-25 bg-[radial-gradient(#8c7b68_1px,transparent_1px)] [background-size:16px_16px]"></div>

        <!-- Gold Corner Accents -->
        <div class="pointer-events-none absolute top-3 left-3 w-4 h-4 border-t-2 border-l-2 border-[#c49a45]/40 rounded-tl-lg"></div>
        <div class="pointer-events-none absolute top-3 right-3 w-4 h-4 border-t-2 border-r-2 border-[#c49a45]/40 rounded-tr-lg"></div>
        <div class="pointer-events-none absolute bottom-3 left-3 w-4 h-4 border-b-2 border-l-2 border-[#c49a45]/40 rounded-bl-lg"></div>
        <div class="pointer-events-none absolute bottom-3 right-3 w-4 h-4 border-b-2 border-r-2 border-[#c49a45]/40 rounded-br-lg"></div>

        <!-- Top Status Bar in Card -->
        <div class="flex items-center justify-between px-2 pb-3 border-b border-[#e8dfd2] text-xs font-serif text-[#8c7b68] z-10 relative">
          <div class="flex items-center gap-2">
            <span class="w-2 h-2 rounded-full bg-[#c49a45] animate-pulse"></span>
            <span class="font-bold text-[#2c2825]">{title}</span>
            <span class="text-[#a0907d]">· {artist || '原版手稿'}</span>
          </div>
          <span class="font-mono text-[11px] text-[#966b26] bg-[#ffffff]/80 px-2 py-0.5 rounded-full border border-[#e0d6c0]">
            100% 原始扫描件
          </span>
        </div>

        <!-- High-Res Score Image Container -->
        <div class="relative mt-3 rounded-2xl overflow-hidden border border-[#dfd6c7] bg-[#ffffff] shadow-inner max-h-[520px] flex items-center justify-center">
          <img
            src={screenshotUrl}
            alt={`${title} - 谱面高清预览`}
            class="w-full h-auto object-contain transition-transform duration-500 ease-out group-hover:scale-[1.02]"
            loading="lazy"
          />

          <!-- Floating Hover Lens Indicator -->
          <div
            class="absolute inset-0 bg-[#2c2825]/20 backdrop-blur-[2px] opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center"
          >
            <span class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-[#ffffff]/95 border border-[#c49a45] text-xs font-serif font-bold text-[#2c2825] shadow-xl transform -translate-y-2 group-hover:translate-y-0 transition-transform duration-300">
              <span>🔍</span>
              <span>点击开启全屏高清检视</span>
            </span>
          </div>
        </div>

        <!-- Bottom Card Tagline -->
        <div class="flex items-center justify-between pt-3 px-2 text-[11px] text-[#8c7b68] font-serif z-10 relative">
          <span>印制规格: 矢量和弦图 / 简六双排 / 独奏完整采谱</span>
          <span class="text-[#c84b31] font-medium flex items-center gap-1">
            <span>印</span>
            <span>MIMI 工坊校对</span>
          </span>
        </div>
      </div>
    </div>

    <!-- Right: Curated Archival Deck & Practice Notes (5 Cols) -->
    <div class="lg:col-span-5 space-y-4">
      <!-- Card 1: 采编规格与记谱规范 -->
      <div class="rounded-3xl border border-[#e2d8c3] bg-[#fbf9f4] p-5 shadow-xs space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="font-display text-sm font-bold text-[#2c2825] flex items-center gap-2">
            <span class="text-[#c49a45]">🎼</span>
            <span>乐谱采编与记谱规范</span>
          </h3>
          <span class="text-[10px] font-mono text-[#966b26] bg-[#f7f2e7] px-2 py-0.5 rounded-full border border-[#e2d8c3]">
            精校原版
          </span>
        </div>
        <p class="text-xs text-[#705c42] font-serif leading-relaxed">
          本曲谱手稿采用标准吉他六线谱排版，前奏、主歌、副歌与尾奏指法均经原声音轨逐音对齐校正，包含完整低音走向与内声部旋律线条。
        </p>
      </div>

      <!-- Card 2: 演奏与调弦指引 -->
      <div class="rounded-3xl border border-[#e2d8c3] bg-[#fbf9f4] p-5 shadow-xs space-y-3">
        <h3 class="font-display text-sm font-bold text-[#2d2926] flex items-center gap-2">
          <span class="text-[#c49a45]">🎸</span>
          <span>调性与演奏指引</span>
        </h3>
        <div class="grid grid-cols-2 gap-2 text-xs font-serif">
          <div class="p-2.5 rounded-2xl bg-[#ffffff] border border-[#e8e0d0]">
            <span class="text-[#8c7b68] block text-[10px]">原曲调性</span>
            <span class="font-bold text-[#2c2825] text-sm font-mono mt-0.5 block">{tabKey} 调</span>
          </div>
          <div class="p-2.5 rounded-2xl bg-[#ffffff] border border-[#e8e0d0]">
            <span class="text-[#8c7b68] block text-[10px]">变调夹推荐</span>
            <span class="font-bold text-[#2c2825] text-sm font-mono mt-0.5 block">{capo > 0 ? `夹 ${capo} 品` : '原调 (不夹)'}</span>
          </div>
          <div class="p-2.5 rounded-2xl bg-[#ffffff] border border-[#e8e0d0]">
            <span class="text-[#8c7b68] block text-[10px]">演奏速度</span>
            <span class="font-bold text-[#2c2825] text-sm font-mono mt-0.5 block">{bpm ? `♩ = ${bpm}` : '中速抒情'}</span>
          </div>
          <div class="p-2.5 rounded-2xl bg-[#ffffff] border border-[#e8e0d0]">
            <span class="text-[#8c7b68] block text-[10px]">推荐琴型</span>
            <span class="font-bold text-[#2c2825] text-sm mt-0.5 block">民谣/古典吉他</span>
          </div>
        </div>
      </div>

      <!-- Card 3: 工坊改编与二次创作 -->
      <div class="rounded-3xl border border-[#c49a45]/35 bg-gradient-to-br from-[#fbf9f4] to-[#f5eedf] p-5 shadow-xs space-y-3">
        <div class="flex items-center gap-2">
          <span class="text-base">🛠️</span>
          <h3 class="font-display text-sm font-bold text-[#2c2825]">在制谱工坊中自由改编</h3>
        </div>
        <p class="text-xs text-[#705c42] font-serif leading-relaxed">
          想针对此谱调整和弦、重配指法或移调？可一键将其克隆至制谱工坊进行专业级数字重构与导出。
        </p>
        <a
          href={`/studio?cloneFrom=${tabId}`}
          class="inline-flex items-center justify-center gap-2 w-full rounded-2xl bg-[#2c2825] hover:bg-[#966b26] text-[#faf8f5] px-4 py-2.5 text-xs font-serif font-bold transition-all shadow-xs active:scale-98"
        >
          <span>✨ 导入工坊开始自由改编</span>
          <span>→</span>
        </a>
      </div>
    </div>
  </div>
</div>

<!-- Immersive Fullscreen Lightbox Modal (沉浸式全屏手稿检视器) -->
{#if isLightboxOpen}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-[#181513]/90 backdrop-blur-xl p-4 sm:p-8 animate-fade-in select-none"
    on:click={closeLightbox}
    role="dialog"
    aria-modal="true"
    aria-label="手稿高清全屏检视"
  >
    <!-- Lightbox Toolbar -->
    <div
      class="fixed top-4 sm:top-6 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2 bg-[#2c2825]/95 border border-[#dfd6c7]/30 px-4 py-2 rounded-full shadow-2xl backdrop-blur-md text-xs font-serif text-[#fbfaf7]"
      on:click|stopPropagation
    >
      <span class="font-bold font-display text-[#c49a45] pr-2 border-r border-[#dfd6c7]/20">
        {title} · 原版手稿
      </span>
      <button
        type="button"
        on:click={zoomIn}
        class="w-7 h-7 rounded-full bg-[#ffffff]/10 hover:bg-[#ffffff]/20 flex items-center justify-center text-sm transition cursor-pointer"
        title="放大 (+25%)"
      >
        ＋
      </button>
      <span class="font-mono text-[11px] px-1 text-[#dfd6c7]">{Math.round(zoomLevel * 100)}%</span>
      <button
        type="button"
        on:click={zoomOut}
        class="w-7 h-7 rounded-full bg-[#ffffff]/10 hover:bg-[#ffffff]/20 flex items-center justify-center text-sm transition cursor-pointer"
        title="缩小 (-25%)"
      >
        －
      </button>
      <button
        type="button"
        on:click={resetZoom}
        class="px-2.5 py-1 rounded-full bg-[#ffffff]/10 hover:bg-[#ffffff]/20 text-[11px] transition cursor-pointer"
        title="重置缩放"
      >
        1:1
      </button>
      <span class="h-4 w-[1px] bg-[#dfd6c7]/20 mx-1"></span>
      <button
        type="button"
        on:click={closeLightbox}
        class="w-7 h-7 rounded-full bg-[#c84b31]/80 hover:bg-[#c84b31] flex items-center justify-center text-xs font-bold transition cursor-pointer"
        title="关闭 (Esc)"
      >
        ✕
      </button>
    </div>

    <!-- Lightbox Image Viewport with Dynamic Zoom & Pan -->
    <div
      class="max-w-5xl max-h-[88vh] overflow-auto rounded-3xl p-2 flex items-center justify-center transition-all"
      on:click|stopPropagation
    >
      <img
        src={screenshotUrl}
        alt={title}
        style="transform: scale({zoomLevel}); transform-origin: center center; transition: transform 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);"
        class="max-w-full max-h-[82vh] object-contain rounded-2xl shadow-2xl bg-[#ffffff]"
      />
    </div>

    <!-- Keyboard Esc Hint -->
    <div class="fixed bottom-4 left-1/2 -translate-x-1/2 text-center text-xs text-[#a0907d] font-serif pointer-events-none">
      按 <kbd class="px-1.5 py-0.5 bg-[#ffffff]/10 rounded border border-[#ffffff]/20 font-mono text-[10px]">Esc</kbd> 或点击空白处退出全屏
    </div>
  </div>
{/if}
