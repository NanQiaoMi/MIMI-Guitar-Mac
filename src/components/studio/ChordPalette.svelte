<script lang="ts">
  import { playProgramChordStrum, getNoteMidi } from '../../lib/guitarSound';
  import type { StudioTrack } from '../../lib/studio/studioScoreModel';

  let {
    track = null,
    onChordSelect,
  }: {
    track: StudioTrack | null;
    onChordSelect?: (chordName: string, frets: Array<{ string: number; fret: number }>) => void;
  } = $props();

  // 经典流行/民谣吉他和弦指法库 (从 6 弦到 1 弦的品位，-1 代表静音 X)
  const GUITAR_CHORD_LIBRARY: Array<{ name: string; root: string; frets: number[]; desc: string }> = [
    // C Key
    { name: 'C', root: 'C', frets: [-1, 3, 2, 0, 1, 0], desc: 'C大调主和弦' },
    { name: 'Cmaj7', root: 'C', frets: [-1, 3, 2, 0, 0, 0], desc: 'C大七和弦' },
    { name: 'Cadd9', root: 'C', frets: [-1, 3, 2, 0, 3, 0], desc: '流行常用加九和弦' },
    { name: 'Csus4', root: 'C', frets: [-1, 3, 3, 0, 1, 0], desc: 'C挂四和弦' },
    
    // D Key
    { name: 'D', root: 'D', frets: [-1, -1, 0, 2, 3, 2], desc: 'D大三和弦' },
    { name: 'Dm', root: 'D', frets: [-1, -1, 0, 2, 3, 1], desc: 'D小三和弦' },
    { name: 'D7', root: 'D', frets: [-1, -1, 0, 2, 1, 2], desc: 'D属七和弦' },
    { name: 'Dsus4', root: 'D', frets: [-1, -1, 0, 2, 3, 3], desc: 'D挂四和弦' },
    { name: 'D/F#', root: 'D', frets: [2, 0, 0, 2, 3, 2], desc: 'D转位斜杠和弦' },

    // E Key
    { name: 'E', root: 'E', frets: [0, 2, 2, 1, 0, 0], desc: 'E大三和弦' },
    { name: 'Em', root: 'E', frets: [0, 2, 2, 0, 0, 0], desc: 'Em小三和弦' },
    { name: 'Em7', root: 'E', frets: [0, 2, 2, 0, 3, 0], desc: 'Em7小七和弦' },
    { name: 'E7', root: 'E', frets: [0, 2, 0, 1, 0, 0], desc: 'E属七和弦' },

    // F Key
    { name: 'F', root: 'F', frets: [1, 3, 3, 2, 1, 1], desc: 'F大横按和弦' },
    { name: 'Fmaj7', root: 'F', frets: [-1, -1, 3, 2, 1, 0], desc: 'F大七和弦(小横按)' },
    { name: 'Fm', root: 'F', frets: [1, 3, 3, 1, 1, 1], desc: 'F小三和弦' },

    // G Key
    { name: 'G', root: 'G', frets: [3, 2, 0, 0, 0, 3], desc: 'G大三和弦' },
    { name: 'G/B', root: 'G', frets: [-1, 2, 0, 0, 3, 3], desc: 'G转位斜杠和弦' },
    { name: 'G7', root: 'G', frets: [3, 2, 0, 0, 0, 1], desc: 'G属七和弦' },
    { name: 'Gsus4', root: 'G', frets: [3, 2, 0, 0, 1, 3], desc: 'G挂四和弦' },

    // A Key
    { name: 'A', root: 'A', frets: [-1, 0, 2, 2, 2, 0], desc: 'A大三和弦' },
    { name: 'Am', root: 'A', frets: [-1, 0, 2, 2, 1, 0], desc: 'Am小三和弦' },
    { name: 'Am7', root: 'A', frets: [-1, 0, 2, 0, 1, 0], desc: 'Am7小七和弦' },
    { name: 'A7', root: 'A', frets: [-1, 0, 2, 0, 2, 0], desc: 'A属七和弦' },
    { name: 'Asus2', root: 'A', frets: [-1, 0, 2, 2, 0, 0], desc: 'A挂二和弦' },

    // B Key
    { name: 'Bm', root: 'B', frets: [-1, 2, 4, 4, 3, 2], desc: 'Bm小三和弦' },
    { name: 'Bm7', root: 'B', frets: [-1, 2, 4, 2, 3, 2], desc: 'Bm7小七和弦' },
    { name: 'B7', root: 'B', frets: [-1, 2, 1, 2, 0, 2], desc: 'B属七和弦' },
  ];

  // 标准 4 弦尤克里里和弦库 (从 4 弦 G 到 1 弦 A)
  const UKULELE_CHORD_LIBRARY: Array<{ name: string; root: string; frets: number[]; desc: string }> = [
    { name: 'C', root: 'C', frets: [0, 0, 0, 3], desc: 'C大三和弦' },
    { name: 'Cmaj7', root: 'C', frets: [0, 0, 0, 2], desc: 'C大七和弦' },
    { name: 'C7', root: 'C', frets: [0, 0, 0, 1], desc: 'C属七和弦' },
    { name: 'D', root: 'D', frets: [2, 2, 2, 0], desc: 'D大三和弦' },
    { name: 'Dm', root: 'D', frets: [2, 2, 1, 0], desc: 'D小三和弦' },
    { name: 'D7', root: 'D', frets: [2, 0, 2, 0], desc: 'D属七和弦' },
    { name: 'Em', root: 'E', frets: [0, 4, 3, 2], desc: 'Em小三和弦' },
    { name: 'Em7', root: 'E', frets: [0, 2, 0, 2], desc: 'Em7小七和弦' },
    { name: 'E7', root: 'E', frets: [1, 2, 0, 2], desc: 'E属七和弦' },
    { name: 'F', root: 'F', frets: [2, 0, 1, 0], desc: 'F大三和弦' },
    { name: 'Fm', root: 'F', frets: [1, 0, 1, 3], desc: 'F小三和弦' },
    { name: 'G', root: 'G', frets: [0, 2, 3, 2], desc: 'G大三和弦' },
    { name: 'G7', root: 'G', frets: [0, 2, 1, 2], desc: 'G属七和弦' },
    { name: 'A', root: 'A', frets: [2, 1, 0, 0], desc: 'A大三和弦' },
    { name: 'Am', root: 'A', frets: [2, 0, 0, 0], desc: 'Am小三和弦' },
    { name: 'Am7', root: 'A', frets: [0, 0, 0, 0], desc: 'Am7小七和弦' },
    { name: 'A7', root: 'A', frets: [0, 1, 0, 0], desc: 'A属七和弦' },
    { name: 'Bm', root: 'B', frets: [4, 2, 2, 2], desc: 'Bm小三和弦' },
    { name: 'B7', root: 'B', frets: [2, 3, 2, 2], desc: 'B属七和弦' },
  ];

  let isBass = $derived(track?.program === 33);
  let isUkulele = $derived(track?.program === 24);
  let activeChordLibrary = $derived(isBass ? [] : isUkulele ? UKULELE_CHORD_LIBRARY : GUITAR_CHORD_LIBRARY);

  const QUICK_CHORD_NAMES = ['C', 'Am', 'F', 'G', 'Dm', 'Em'];
  let quickChords = $derived(
    QUICK_CHORD_NAMES.map((name) => activeChordLibrary.find((c) => c.name === name)!).filter(Boolean)
  );

  let selectedRoot = $state('ALL');
  let searchQuery = $state('');

  let filteredChords = $derived(
    activeChordLibrary.filter((c) => {
      if (selectedRoot !== 'ALL' && c.root !== selectedRoot) return false;
      if (searchQuery.trim()) {
        const q = searchQuery.trim().toLowerCase();
        return c.name.toLowerCase().includes(q) || c.desc.toLowerCase().includes(q);
      }
      return true;
    })
  );

  function handleChordClick(chord: { name: string; root: string; frets: number[]; desc: string }) {
    // 1. 发声试听扫弦
    const prog = track?.program ?? 25;
    const tuning = track?.tuning ?? (isUkulele ? [69, 64, 60, 67] : [64, 59, 55, 50, 45, 40]);
    const stringCount = tuning.length;
    const notes: Array<{ string: number; fret: number }> = [];
    const midiNotes: number[] = [];

    // chord.frets 数组对应从最粗弦到最细弦
    chord.frets.forEach((fret, idx) => {
      const stringNum = stringCount - idx;
      if (fret >= 0) {
        notes.push({ string: stringNum, fret });
        midiNotes.push(getNoteMidi(stringNum, fret, tuning));
      }
    });

    if (midiNotes.length > 0) {
      playProgramChordStrum(midiNotes, 'down', prog);
    }

    // 2. 触发填入乐谱
    onChordSelect?.(chord.name, notes);
  }
</script>

<div class="w-full bg-[#FAF8F5] text-[#2c2825] rounded-3xl p-3.5 sm:p-4 border border-[#e8e2d4] shadow-sm flex flex-col gap-2.5">
  {#if isBass}
    <div class="rounded-2xl border border-[#e2d7c5] bg-[#f5efe6] p-4 text-center">
      <div class="font-serif font-bold text-[#966b1a]">贝斯以单音录入为主</div>
      <p class="text-xs leading-relaxed text-[#705c42] mt-2">当前和弦指法库针对吉他和尤克里里。请在指板选择弦与品位，或在画布定位后用键盘输入音符。</p>
    </div>
  {:else}
  <!-- 常用一键快速注入和弦 (C, Am, F, G, Dm, Em) -->
  <div class="flex flex-col gap-1.5 bg-[#f5efe6] p-2.5 rounded-2xl border border-[#e2d7c5]">
    <div class="flex items-center justify-between text-[11px] font-serif text-[#705c42]">
      <span class="font-bold text-[#966b1a]">⚡ 常用和弦速选 (C, Am, F, G, Dm, Em):</span>
      <span class="text-[10px] text-[#8c7b68]">点选即注入当前拍</span>
    </div>
    <div class="grid grid-cols-3 sm:grid-cols-6 gap-1.5">
      {#each quickChords as qc}
        <button
          type="button"
          onclick={() => handleChordClick(qc)}
          class="flex flex-col items-center justify-center py-1.5 px-2 rounded-xl bg-[#ffffff] border border-[#dfd6c7] hover:border-[#c84b31] hover:bg-[#c84b31]/5 transition-all shadow-2xs group"
          title={`快速填入 ${qc.name} 和弦`}
        >
          <span class="font-serif font-bold text-sm text-[#2c2825] group-hover:text-[#c84b31] transition-colors">{qc.name}</span>
          <span class="text-[9px] font-mono text-[#8c7b68]">{qc.root}调</span>
        </button>
      {/each}
    </div>
  </div>

  <!-- 标题与和弦过滤栏 -->
  <div class="flex flex-wrap items-center justify-between gap-2 border-b border-[#e2d7c5] pb-2">
    <div class="flex items-center gap-1.5">
      <span class="font-serif font-bold text-[#966b1a] text-xs">🎼 和弦库检索</span>
    </div>

    <!-- 搜索框 -->
    <div class="relative w-36 sm:w-44">
      <input
        type="text"
        bind:value={searchQuery}
        placeholder="搜和弦 (如 Em7)..."
        class="w-full bg-[#ffffff] text-[#2c2825] text-xs px-2.5 py-1 rounded-xl border border-[#dfd6c7] focus:border-[#c49a45] focus:outline-hidden placeholder-[#a89b8a] shadow-2xs font-serif"
      />
    </div>
  </div>

  <!-- 根音快速切换标签 (ALL, C, D, E, F, G, A, B) -->
  <div class="flex items-center gap-1 overflow-x-auto pb-0.5 text-xs font-serif scrollbar-none">
    {#each ['ALL', 'C', 'D', 'E', 'F', 'G', 'A', 'B'] as root}
      <button
        type="button"
        onclick={() => (selectedRoot = root)}
        class="px-2.5 py-0.5 rounded-lg text-[11px] transition-all {selectedRoot === root ? 'bg-[#2c2825] text-[#fbfaf7] font-bold shadow-xs' : 'bg-[#ede5d8]/80 text-[#5c4a38] hover:bg-[#ede5d8]'}"
      >
        {root === 'ALL' ? '全部' : `${root}调`}
      </button>
    {/each}
  </div>

  <!-- 和弦列表网格 -->
  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2 max-h-36 overflow-y-auto pr-1 scrollbar-thin scrollbar-thumb-[#d6caba]">
    {#each filteredChords as chord}
      <button
        type="button"
        onclick={() => handleChordClick(chord)}
        class="flex flex-col items-center justify-between p-2 rounded-xl bg-[#ffffff] border border-[#dfd6c7] hover:border-[#c49a45] hover:shadow-xs transition-all duration-150 group text-center shadow-2xs"
      >
        <span class="font-serif font-bold text-xs text-[#966b1a] group-hover:scale-105 transition-transform">
          {chord.name}
        </span>
        <span class="text-[9px] font-mono text-[#8c7b68] mt-0.5">
          {chord.frets.map(f => (f < 0 ? 'x' : f)).join(' ')}
        </span>
      </button>
    {/each}
  </div>
  {/if}
</div>
