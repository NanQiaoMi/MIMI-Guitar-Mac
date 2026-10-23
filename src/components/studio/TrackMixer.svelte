<script lang="ts">
  import type { StudioTrack, StudioProject } from '../../lib/studio/studioScoreModel';
  import { generateUid } from '../../lib/studio/studioScoreModel';

  let {
    project,
    selectedTrackIndex = 0,
    onSelectTrack,
    onUpdateProject,
  }: {
    project: StudioProject;
    selectedTrackIndex: number;
    onSelectTrack?: (index: number) => void;
    onUpdateProject?: (updated: StudioProject) => void;
  } = $props();

  const INSTRUMENT_OPTIONS = [
    { program: 25, name: '原声钢弦木吉他' },
    { program: 24, name: '古典尼龙弦吉他' },
    { program: 27, name: '清音电吉他' },
    { program: 29, name: '过载/失真主音吉他' },
    { program: 33, name: '电贝斯 (Finger Bass)' },
    { program: 0, name: '大钢琴 (Grand Piano)' },
    { program: 128, name: '标准架子鼓组 (Drums)' },
  ];

  function handleVolumeChange(trackIdx: number, val: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.tracks[trackIdx].volume = val;
    onUpdateProject?.(next);
  }

  function handlePanChange(trackIdx: number, val: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.tracks[trackIdx].pan = val;
    onUpdateProject?.(next);
  }

  function toggleMute(trackIdx: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.tracks[trackIdx].mute = !next.tracks[trackIdx].mute;
    onUpdateProject?.(next);
  }

  function toggleSolo(trackIdx: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.tracks[trackIdx].solo = !next.tracks[trackIdx].solo;
    onUpdateProject?.(next);
  }

  function handleInstrumentChange(trackIdx: number, prog: number) {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    next.tracks[trackIdx].program = prog;
    const opt = INSTRUMENT_OPTIONS.find((o) => o.program === prog);
    if (opt) next.tracks[trackIdx].name = opt.name;
    onUpdateProject?.(next);
  }

  function addNewTrack() {
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    const newTrk: StudioTrack = {
      id: generateUid('trk'),
      name: `伴奏吉他 ${next.tracks.length + 1}`,
      program: 25,
      tuning: [64, 59, 55, 50, 45, 40],
      tuningName: '标准吉他调弦',
      capo: 0,
      volume: 0.85,
      pan: 0,
      mute: false,
      solo: false,
    };
    next.tracks.push(newTrk);

    // 为每个小节补齐新轨的空白 Beat
    next.bars.forEach((bar) => {
      bar.trackBeats[newTrk.id] = Array.from({ length: bar.timeSignatureNumerator }, () => ({
        id: generateUid('beat'),
        duration: 4,
        isRest: true,
        dot: false,
        triplet: false,
        notes: [],
        chordName: null,
        lyrics: null,
      }));
    });

    onUpdateProject?.(next);
    onSelectTrack?.(next.tracks.length - 1);
  }

  function deleteTrack(trackIdx: number) {
    if (project.tracks.length <= 1) return;
    const next = JSON.parse(JSON.stringify(project)) as StudioProject;
    const removedId = next.tracks[trackIdx].id;
    next.tracks.splice(trackIdx, 1);

    // 移除小节中对应的音轨数据
    next.bars.forEach((bar) => {
      delete bar.trackBeats[removedId];
    });

    onUpdateProject?.(next);
    onSelectTrack?.(Math.max(0, trackIdx - 1));
  }
</script>

<div class="w-full bg-[#f8f5ee] text-[#2c2825] rounded-3xl p-4 sm:p-5 border border-[#e4dbcc] shadow-sm flex flex-col gap-3">
  <div class="flex items-center justify-between border-b border-[#e2d7c5] pb-3">
    <div class="flex items-center gap-2">
      <span class="font-serif font-bold text-[#966b1a] text-sm">🎛️ 多音轨调音台 (Track Mixer)</span>
      <span class="text-xs text-[#8c7b68] font-serif">共 {project.tracks.length} 个独立音轨</span>
    </div>

    <button
      type="button"
      onclick={addNewTrack}
      class="min-h-[44px] px-4 py-2 bg-[#2c2825] text-[#fbfaf7] font-serif font-bold text-xs rounded-xl hover:bg-[#403b37] transition-colors flex items-center gap-1 shadow-xs focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
    >
      <span>+ 新增音轨</span>
    </button>
  </div>

  <!-- 音轨列表 -->
  <div class="flex flex-col gap-2">
    {#each project.tracks as trk, idx}
      {@const isSelected = selectedTrackIndex === idx}
      <div
        class="flex flex-wrap items-center justify-between gap-3 p-3 rounded-2xl border transition-colors {isSelected ? 'bg-[#ffffff] border-[#c49a45] shadow-sm ring-1 ring-[#c49a45]/30' : 'bg-[#ffffff]/70 border-[#e2d7c5] hover:bg-[#ffffff]'}"
      >
        <!-- 音轨选择与名称 -->
        <button
          type="button"
          onclick={() => onSelectTrack?.(idx)}
          aria-pressed={isSelected}
          class="min-h-[44px] min-w-[44px] flex items-center gap-2.5 rounded-lg text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        >
          <div class="w-2.5 h-2.5 rounded-full {isSelected ? 'bg-[#c49a45]' : 'bg-[#dfd6c7]'}"></div>
          <div>
            <div class="text-xs font-serif font-bold text-[#2c2825]">{trk.name}</div>
            <div class="text-[10px] font-mono text-[#8c7b68]">{trk.tuningName}</div>
          </div>
        </button>

        <!-- 乐器下拉菜单 -->
        <select
          value={trk.program}
          onchange={(e) => handleInstrumentChange(idx, Number((e.currentTarget as HTMLSelectElement).value))}
          aria-label={`乐器：${trk.name}`}
          class="min-h-[44px] bg-[#ede5d8]/80 text-[#2c2825] text-[11px] px-2.5 py-2 rounded-xl border border-[#dfd6c7] focus:border-[#c49a45] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] font-serif"
        >
          {#each INSTRUMENT_OPTIONS as opt}
            <option value={opt.program}>{opt.name}</option>
          {/each}
        </select>

        <!-- Solo / Mute 按钮 -->
        <div class="flex items-center gap-1">
          <button
            type="button"
            onclick={() => toggleSolo(idx)}
            aria-label={`独奏：${trk.name}`}
            aria-pressed={trk.solo}
            class="min-h-[44px] min-w-[44px] rounded-lg text-xs font-bold font-mono transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {trk.solo ? 'bg-[#966b1a] text-[#ffffff] shadow-xs' : 'bg-[#ede5d8] text-[#705c42] hover:text-[#2c2825]'}"
          >
            S
          </button>
          <button
            type="button"
            onclick={() => toggleMute(idx)}
            aria-label={`静音：${trk.name}`}
            aria-pressed={trk.mute}
            class="min-h-[44px] min-w-[44px] rounded-lg text-xs font-bold font-mono transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {trk.mute ? 'bg-[#c84b31] text-[#ffffff] shadow-xs' : 'bg-[#ede5d8] text-[#705c42] hover:text-[#2c2825]'}"
          >
            M
          </button>
        </div>

        <!-- 音量推子 -->
        <div class="flex items-center gap-1.5 w-28">
          <span class="text-[10px] font-mono text-[#705c42] font-semibold">Vol</span>
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            value={trk.volume}
            aria-label={`音量：${trk.name}`}
            aria-valuetext={`${Math.round(trk.volume * 100)}%`}
            oninput={(e) => handleVolumeChange(idx, Number((e.currentTarget as HTMLInputElement).value))}
            class="track-mixer-range w-full h-11 bg-transparent rounded-lg appearance-none cursor-pointer accent-[#2c2825] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
          />
        </div>

        <!-- 声相滑块 -->
        <div class="flex items-center gap-1.5 w-24">
          <span class="text-[10px] font-mono text-[#705c42] font-semibold">Pan</span>
          <input
            type="range"
            min="-1"
            max="1"
            step="0.1"
            value={trk.pan}
            aria-label={`声相：${trk.name}`}
            aria-valuetext={trk.pan === 0 ? '居中' : trk.pan < 0 ? `左 ${Math.round(Math.abs(trk.pan) * 100)}%` : `右 ${Math.round(trk.pan * 100)}%`}
            oninput={(e) => handlePanChange(idx, Number((e.currentTarget as HTMLInputElement).value))}
            class="track-mixer-range w-full h-11 bg-transparent rounded-lg appearance-none cursor-pointer accent-[#2c2825] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
          />
        </div>

        <!-- 删除轨按钮 -->
        {#if project.tracks.length > 1}
          <button
            type="button"
            onclick={() => deleteTrack(idx)}
            aria-label={`删除音轨：${trk.name}`}
            class="min-h-[44px] min-w-[44px] rounded-lg text-[#8c7b68] hover:text-[#c84b31] text-xs transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
          >
            ✕
          </button>
        {/if}
      </div>
    {/each}
  </div>
</div>

<style>
  .track-mixer-range::-webkit-slider-runnable-track {
    height: 6px;
    border-radius: 999px;
    background: #ede5d8;
  }

  .track-mixer-range::-webkit-slider-thumb {
    width: 20px;
    height: 20px;
    margin-top: -7px;
    -webkit-appearance: none;
    appearance: none;
    border: 2px solid #fbfaf7;
    border-radius: 999px;
    background: #2c2825;
    box-shadow: 0 1px 3px rgb(44 40 37 / 24%);
  }

  .track-mixer-range::-moz-range-track {
    height: 6px;
    border: 0;
    border-radius: 999px;
    background: #ede5d8;
  }

  .track-mixer-range::-moz-range-thumb {
    width: 16px;
    height: 16px;
    border: 2px solid #fbfaf7;
    border-radius: 999px;
    background: #2c2825;
    box-shadow: 0 1px 3px rgb(44 40 37 / 24%);
  }
</style>
