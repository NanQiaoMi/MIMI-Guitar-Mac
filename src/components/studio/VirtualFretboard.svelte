<script lang="ts">
  import type { StudioTrack, StudioNote } from '../../lib/studio/studioScoreModel';

  let {
    track = null,
    activeNotes = [],
    onFretClick,
  }: {
    track: StudioTrack | null;
    activeNotes: StudioNote[];
    onFretClick?: (stringNum: number, fret: number) => void;
  } = $props();

  const numFrets = 24;
  const fretArray = Array.from({ length: numFrets + 1 }, (_, i) => i);
  // 单双品记标记品位 (3, 5, 7, 9, 12双品, 15, 17, 19, 21, 24双品)
  const singleDotFrets = [3, 5, 7, 9, 15, 17, 19, 21];
  const doubleDotFrets = [12, 24];

  // 琴弦从上到下：1弦到6弦 (或者尤克里里1弦到4弦)
  let stringCount = $derived(track?.tuning?.length || 6);
  let stringIndexes = $derived(Array.from({ length: stringCount }, (_, i) => i + 1));

  const NOTE_NAMES = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];

  function getStringLabel(strNum: number): string {
    const midi = track?.tuning?.[strNum - 1];
    const name = Number.isInteger(midi) ? `${NOTE_NAMES[((midi as number) % 12 + 12) % 12]}${Math.floor((midi as number) / 12) - 1}` : '自定义';
    return `${strNum}弦 (${name})`;
  }

  function handleCellClick(stringNum: number, fret: number) {
    // 父层统一负责写入音符与即时试听，避免同一次点击播放两次。
    onFretClick?.(stringNum, fret);
  }

  function isNoteActive(stringNum: number, fret: number): boolean {
    return activeNotes.some((n) => n.string === stringNum && n.fret === fret);
  }
</script>

<div class="w-full bg-[#FAF8F5] text-[#2c2825] rounded-3xl p-3.5 sm:p-4 border border-[#e8e2d4] shadow-sm flex flex-col gap-2 select-none overflow-hidden">
  <!-- 顶部指板信息与品位数字 -->
  <div class="flex items-center justify-between px-2 text-xs font-mono text-[#705c42]">
    <div class="flex items-center gap-2">
      <span class="font-serif font-bold text-[#966b1a] text-sm">🎸 {track?.name || '原声吉他'} 24品实况指板</span>
      <span class="text-[11px] bg-[#ede5d8] px-2 py-0.5 rounded-full text-[#5c4a38] font-sans border border-[#dfd6c7]">{track?.tuningName || '标准调弦'}</span>
      {#if track?.capo}
        <span class="text-[11px] bg-[#c49a45]/15 text-[#966b1a] px-2 py-0.5 rounded-full border border-[#c49a45]/30 font-bold">Capo {track.capo} 品</span>
      {/if}
    </div>
    <span class="text-[11px] text-[#8c7b68] font-serif hidden sm:inline">点击品位即时发声并填入当前拍位</span>
  </div>

  <!-- 横向滚动指板本体 -->
  <div class="overflow-x-auto overflow-y-hidden pb-1 scrollbar-thin scrollbar-thumb-[#d6caba]">
    <div class="min-w-[1180px] bg-[#ffffff] rounded-2xl border border-[#dfd6c7] relative py-2.5 shadow-2xs">
      <!-- 品位上方数字标尺 -->
      <div class="flex border-b border-[#eee7db] pb-1.5 mb-1.5 text-[11px] font-mono text-[#8c7b68]">
        <div class="w-16 text-center shrink-0 font-serif font-semibold text-[#5c4a38]">弦 / 品</div>
        {#each fretArray as fret}
          <div class="flex-1 text-center font-bold {fret === 0 ? 'text-[#c49a45]' : doubleDotFrets.includes(fret) ? 'text-[#2c2825]' : singleDotFrets.includes(fret) ? 'text-[#5c4a38]' : 'text-[#a89b8a]'}">
            {fret === 0 ? '空弦' : fret}
          </div>
        {/each}
      </div>

      <!-- 琴弦行 (1 弦最细在最上方，6 弦最粗在最下方) -->
      <div class="flex flex-col gap-1 relative">
        {#each stringIndexes as strNum}
          {@const stringThickness = Math.max(1, (stringCount - strNum + 1) * 0.75)}
          <div class="flex items-center relative h-11">
            <!-- 琴弦名标签 -->
            <div class="w-16 shrink-0 flex items-center justify-center text-[11px] font-mono font-bold text-[#8a6b29] z-10 px-1">
              {getStringLabel(strNum)}
            </div>

            <!-- 金属琴弦横线 -->
            <div
              class="absolute left-16 right-0 pointer-events-none bg-gradient-to-r from-[#b8a892] via-[#5c4a38] to-[#b8a892] opacity-75 z-0"
              style="height: {stringThickness}px; top: calc(50% - {stringThickness / 2}px);"
            ></div>

            <!-- 各品位点击格子 -->
            {#each fretArray as fret}
              {@const active = isNoteActive(strNum, fret)}
              <button
                type="button"
                onclick={() => handleCellClick(strNum, fret)}
                aria-label={`${getStringLabel(strNum)}，${fret === 0 ? '空弦' : `${fret} 品`}，${active ? '已录入' : '试听并录入'}`}
                class="min-h-[44px] min-w-[44px] flex-1 h-full border-r border-[#eee7db] flex items-center justify-center relative z-10 transition-colors hover:bg-[#c49a45]/20 group focus-visible:outline-2 focus-visible:outline-[#966b1a]"
                title={`${strNum}弦 ${fret}品`}
              >
                {#if active}
                  <div class="w-5 h-5 rounded-full bg-[#2c2825] text-[#fbfaf7] font-mono font-bold text-[10px] flex items-center justify-center shadow-md ring-2 ring-[#c49a45]">
                    {fret}
                  </div>
                {:else}
                  <div class="w-4 h-4 rounded-full opacity-0 group-hover:opacity-75 group-focus-visible:opacity-75 bg-[#c49a45] text-[#ffffff] font-mono text-[9px] flex items-center justify-center transition-opacity shadow-xs font-bold">
                    {fret}
                  </div>
                {/if}
              </button>
            {/each}
          </div>
        {/each}
      </div>

      <!-- 品位指板记号点 (Inlay Dots: 3, 5, 7, 9, 12双点, 15, 17, 19, 21) -->
      <div class="flex absolute bottom-1 right-0 left-16 pointer-events-none text-center">
        {#each fretArray as fret}
          <div class="flex-1 flex justify-center items-center h-2">
            {#if doubleDotFrets.includes(fret)}
              <div class="flex gap-1">
                <div class="w-1.5 h-1.5 rounded-full bg-[#c49a45]/60"></div>
                <div class="w-1.5 h-1.5 rounded-full bg-[#c49a45]/60"></div>
              </div>
            {:else if singleDotFrets.includes(fret)}
              <div class="w-1.5 h-1.5 rounded-full bg-[#c49a45]/40"></div>
            {/if}
          </div>
        {/each}
      </div>
    </div>
  </div>
</div>
