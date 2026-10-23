<script lang="ts">
  import { onDestroy } from 'svelte';
  import { GUITAR_CHORDS, type FretMap } from '../lib/chords';
  import {
    acquireGuitarAudioSession,
    playProgramChordStrum,
    playProgramNote,
    type GuitarAudioSession,
  } from '../lib/guitarSound.ts';

  let {
    initialChord = 'C',
    fretsCount = 15,
    instrument = 'guitar', // 'guitar' | 'ukulele'
    showNoteNames = true,
  }: {
    initialChord?: string;
    fretsCount?: number;
    instrument?: 'guitar' | 'ukulele';
    showNoteNames?: boolean;
  } = $props();

  let currentInstrument = $state<'guitar' | 'ukulele'>(instrument);
  let selectedChord = $state(initialChord);
  let isStrumming = $state(false);
  let audioError = $state('');
  let activeAudioSession: GuitarAudioSession | null = null;
  let audioGeneration = 0;
  let activeNotesDisplay = $state<'notes' | 'intervals' | 'fingerings'>('notes');
  let selectedScale = $state<'none' | 'c-major' | 'a-minor-pentatonic' | 'e-blues'>('none');

  // Guitar tuning (string 6 to 1: low E to high e)
  const GUITAR_STRINGS = [
    { note: 'E', octave: 2, name: '6弦 (E2)' },
    { note: 'A', octave: 2, name: '5弦 (A2)' },
    { note: 'D', octave: 3, name: '4弦 (D3)' },
    { note: 'G', octave: 3, name: '3弦 (G3)' },
    { note: 'B', octave: 3, name: '2弦 (B3)' },
    { note: 'E', octave: 4, name: '1弦 (e4)' },
  ];

  // Ukulele tuning (string 4 to 1: G C E A)
  const UKULELE_STRINGS = [
    { note: 'G', octave: 4, name: '4弦 (G4)' },
    { note: 'C', octave: 4, name: '3弦 (C4)' },
    { note: 'E', octave: 4, name: '2弦 (E4)' },
    { note: 'A', octave: 4, name: '1弦 (A4)' },
  ];

  const CHROMATIC_SCALE = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  // Ukulele chords map
  const UKULELE_CHORDS: Record<string, (string | number)[]> = {
    C: [0, 0, 0, 3],
    G: [0, 2, 3, 2],
    Am: [2, 0, 0, 0],
    F: [2, 0, 1, 0],
    Em: [0, 4, 3, 2],
    Dm: [2, 2, 1, 0],
    A: [2, 1, 0, 0],
    D: [2, 2, 2, 0],
    E: [4, 4, 4, 2],
    Cmaj7: [0, 0, 0, 2],
  };

  const chordPresets = [
    { name: 'C', label: 'C 大三和弦' },
    { name: 'G', label: 'G 大三和弦' },
    { name: 'Am', label: 'Am 小三和弦' },
    { name: 'Em', label: 'Em 小三和弦' },
    { name: 'F', label: 'F 大和弦 (大横按)' },
    { name: 'D', label: 'D 大三和弦' },
    { name: 'Dm', label: 'Dm 小三和弦' },
    { name: 'Cmaj7', label: 'Cmaj7 大七和弦' },
    { name: 'Bm', label: 'Bm 小三和弦' },
    { name: 'F#m', label: 'F#m 小和弦' },
    { name: 'Asus4', label: 'Asus4 挂四和弦' },
    { name: 'G7', label: 'G7 属七和弦' },
  ];

  // Active finger positions: stringIndex -> fretNumber (or 'x' for muted)
  let activeFingering = $state<(number | 'x')[]>([ 'x', 3, 2, 0, 1, 0 ]);

  $effect(() => {
    if (currentInstrument === 'guitar') {
      const chord = GUITAR_CHORDS[selectedChord];
      if (chord) {
        activeFingering = chord.map((v) => (v === 'x' || v === 'X' ? 'x' : Number(v)));
      }
    } else {
      const chord = UKULELE_CHORDS[selectedChord];
      if (chord) {
        activeFingering = chord.map((v) => (v === 'x' || v === 'X' ? 'x' : Number(v)));
      } else {
        activeFingering = [0, 0, 0, 3];
      }
    }
  });

  const strings = $derived(currentInstrument === 'guitar' ? GUITAR_STRINGS : UKULELE_STRINGS);

  function cancelCurrentAudio(): void {
    audioGeneration++;
    activeAudioSession?.release();
    activeAudioSession = null;
    isStrumming = false;
  }

  onDestroy(() => cancelCurrentAudio());

  async function playSamplePreview(
    render: (session: GuitarAudioSession, program: number, flavor: 'gm' | 'ukulele') => Promise<void>,
    options: { strumming?: boolean } = {},
  ): Promise<void> {
    cancelCurrentAudio();
    const generation = audioGeneration;
    isStrumming = options.strumming === true;
    const program = 25;
    const flavor = currentInstrument === 'ukulele' ? 'ukulele' : 'gm';
    let session: GuitarAudioSession | null = null;
    try {
      audioError = '';
      session = await acquireGuitarAudioSession();
      if (generation !== audioGeneration || !session.active) {
        session.release();
        return;
      }
      activeAudioSession = session;
      await render(session, program, flavor);
    } catch (error) {
      if (generation === audioGeneration && !(error instanceof DOMException && error.name === 'AbortError')) {
        audioError = error instanceof Error ? error.message : '指板试听音源加载失败。';
      }
    } finally {
      if (activeAudioSession === session) activeAudioSession = null;
      session?.release();
      if (generation === audioGeneration) isStrumming = false;
    }
  }

  function getFretNote(stringBaseNote: string, fret: number): string {
    const baseIdx = CHROMATIC_SCALE.indexOf(stringBaseNote);
    if (baseIdx === -1) return '';
    return CHROMATIC_SCALE[(baseIdx + fret) % 12];
  }

  function getFretMidi(stringIdx: number, fret: number): number {
    const string = strings[stringIdx];
    const pitchClass = CHROMATIC_SCALE.indexOf(string.note);
    return (string.octave + 1) * 12 + pitchClass + fret;
  }

  function setCurrentInstrument(next: 'guitar' | 'ukulele'): void {
    cancelCurrentAudio();
    audioError = '';
    currentInstrument = next;
    selectedChord = 'C';
  }

  function handleCellClick(stringIdx: number, fret: number) {
    // If already active, mute or clear; else set
    const cur = activeFingering[stringIdx];
    const next = [...activeFingering];
    if (cur === fret) {
      next[stringIdx] = cur === 0 ? 'x' : 0;
    } else {
      next[stringIdx] = fret;
      const midi = getFretMidi(stringIdx, fret);
      void playSamplePreview((session, program, flavor) => playProgramNote(midi, program, 1.4, session, flavor));
    }
    activeFingering = next;
  }

  // Strum with realistic 40ms arpeggiation delay
  async function strumChord() {
    if (isStrumming) return;
    const activeList = activeFingering
      .map((fret, stringIdx) => ({ fret, stringIdx }))
      .filter((item) => item.fret !== 'x');
    const notes = activeList.map(({ fret, stringIdx }) => getFretMidi(stringIdx, Number(fret)));
    if (notes.length === 0) return;
    await playSamplePreview(
      (session, program, flavor) => playProgramChordStrum(notes, 'down', program, session, flavor),
      { strumming: true },
    );
  }

  function isScaleNote(note: string): boolean {
    if (selectedScale === 'c-major') {
      return ['C', 'D', 'E', 'F', 'G', 'A', 'B'].includes(note);
    }
    if (selectedScale === 'a-minor-pentatonic') {
      return ['A', 'C', 'D', 'E', 'G'].includes(note);
    }
    if (selectedScale === 'e-blues') {
      return ['E', 'G', 'A', 'A#', 'B', 'D'].includes(note);
    }
    return false;
  }

  const markerFrets = [3, 5, 7, 9, 12, 15, 17, 19, 21];
</script>

<div class="space-y-6">
  <!-- Fretboard Header & Toolbars -->
  <div class="flex flex-wrap items-center justify-between gap-4 border-b hairline pb-4">
    <div>
      <div class="inline-flex items-center gap-2 rounded-pill border hairline bg-surface-alt px-3 py-0.5 text-caption font-medium text-charcoal">
        <span class="h-2 w-2 rounded-full bg-signal"></span>
        <span>Interactive Virtual Fretboard · 物理吉他指板与音序模拟器</span>
      </div>
      <h3 class="mt-1.5 font-display text-xl sm:text-2xl text-ink">
        {currentInstrument === 'guitar' ? '6 弦原声吉他指板 (Standard E Tuning)' : '4 弦尤克里里指板 (GCEA Tuning)'}
      </h3>
    </div>

    <!-- Quick Instrument Switcher & Strum Button -->
    <div class="flex items-center gap-2.5">
      <div class="flex items-center rounded-pill border hairline bg-surface-alt p-0.5 text-xs font-medium">
        <button
          type="button"
          onclick={() => setCurrentInstrument('guitar')}
          class="rounded-pill px-3 py-1 transition-all {currentInstrument === 'guitar' ? 'bg-ink text-paper shadow-xs' : 'text-mid-gray hover:text-ink'}"
        >
          🎸 6弦吉他
        </button>
        <button
          type="button"
          onclick={() => setCurrentInstrument('ukulele')}
          class="rounded-pill px-3 py-1 transition-all {currentInstrument === 'ukulele' ? 'bg-ink text-paper shadow-xs' : 'text-mid-gray hover:text-ink'}"
        >
          🌴 尤克里里
        </button>
      </div>

      <button
        type="button"
        onclick={strumChord}
        disabled={isStrumming}
        class="btn btn-primary !rounded-pill !px-4 !py-1.5 text-xs font-semibold shadow-xs flex items-center gap-1.5 {isStrumming ? 'animate-pulse !bg-signal !border-signal' : ''}"
      >
        <span>{isStrumming ? '🎶 正在扫弦...' : '⚡ 真实扫弦试听 (Strum)'}</span>
      </button>
    </div>
  </div>

  {#if audioError}
    <div role="alert" class="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-800">{audioError}</div>
  {/if}

  <!-- Chord Presets Quick Bar -->
  <div class="space-y-2">
    <div class="flex items-center justify-between text-caption text-mid-gray">
      <span class="font-medium text-charcoal">经典常用和弦指位预设 (点击即可高亮指板)：</span>
      <span class="font-mono text-xs">当前和弦: <strong class="text-ink font-semibold">{selectedChord}</strong></span>
    </div>

    <div class="flex flex-wrap gap-1.5">
      {#each chordPresets as cp}
        <button
          type="button"
          onclick={() => (selectedChord = cp.name)}
          class="chip !py-1 !px-3 text-xs transition-all {selectedChord === cp.name ? 'chip-active !bg-signal !border-signal !text-paper font-semibold shadow-xs' : 'hover:border-signal/40'}"
        >
          {cp.name}
        </button>
      {/each}
    </div>
  </div>

  <!-- MAIN FRETBOARD CANVAS CONTAINER (24px Rounded Card) -->
  <div class="relative overflow-x-auto rounded-card border hairline bg-[#171717] p-4 sm:p-6 shadow-md text-paper select-none">
    <!-- Nut & Strings Grid -->
    <div class="min-w-[760px]">
      <!-- Fret Numbers Header -->
      <div class="grid grid-cols-[60px_repeat(15,1fr)] gap-0 text-center font-mono text-[11px] text-fog/70 pb-2 border-b border-[#2c2c2c]">
        <div class="font-sans font-medium text-paper">空弦 (0)</div>
        {#each Array(fretsCount) as _, f}
          <div class="relative flex items-center justify-center font-medium {markerFrets.includes(f + 1) ? 'text-signal font-semibold' : ''}">
            {f + 1}
            {#if (f + 1) === 12}
              <span class="absolute -top-1 text-[8px] text-signal font-bold">●●</span>
            {:else if markerFrets.includes(f + 1)}
              <span class="absolute -top-1 text-[8px] text-signal font-bold">●</span>
            {/if}
          </div>
        {/each}
      </div>

      <!-- Strings & Frets Body -->
      <div class="relative mt-2 space-y-3 sm:space-y-4">
        {#each strings as str, stringIdx}
          {@const activeFret = activeFingering[stringIdx]}
          <div class="grid grid-cols-[60px_repeat(15,1fr)] gap-0 items-center relative group">
            <!-- String Label & Nut Control -->
            <button
              type="button"
              onclick={() => handleCellClick(stringIdx, 0)}
              class="flex items-center justify-between pr-2 text-xs font-mono transition-colors hover:text-signal text-left"
              title={`点击切换 ${str.name} 空弦/静音`}
            >
              <span class="font-semibold">{str.note}</span>
              {#if activeFret === 0}
                <span class="h-4 w-4 rounded-full bg-signal text-paper flex items-center justify-center text-[10px] font-bold shadow-xs">
                  0
                </span>
              {:else if activeFret === 'x'}
                <span class="h-4 w-4 rounded-full bg-danger/80 text-paper flex items-center justify-center text-[10px] font-bold">
                  ✕
                </span>
              {:else}
                <span class="text-fog/40 text-[10px]">·</span>
              {/if}
            </button>

            <!-- 1 to 15 Frets -->
            {#each Array(fretsCount) as _, fIdx}
              {@const fretNumber = fIdx + 1}
              {@const noteName = getFretNote(str.note, fretNumber)}
              {@const isActive = activeFret === fretNumber}
              {@const inScale = isScaleNote(noteName)}

              <button
                type="button"
                onclick={() => handleCellClick(stringIdx, fretNumber)}
                class="relative h-10 sm:h-12 border-r border-[#383838] flex items-center justify-center transition hover:bg-white/5 active:bg-white/10"
                title={`${str.name} 第 ${fretNumber} 品: ${noteName}`}
              >
                <!-- Horizontal Metallic String Wire -->
                <div
                  class="pointer-events-none absolute left-0 right-0 top-1/2 -translate-y-1/2 transition-all"
                  style="
                    height: {currentInstrument === 'guitar' ? `${1.2 + (5 - stringIdx) * 0.4}px` : `${1.2 + (3 - stringIdx) * 0.4}px`};
                    background: {isActive ? '#41a1cf' : '#646464'};
                    box-shadow: {isActive ? '0 0 8px #41a1cf' : 'none'};
                  "
                ></div>

                <!-- Active Note Marker with Pulse Halo -->
                {#if isActive}
                  <div class="relative z-10 flex h-7 w-7 sm:h-8 sm:w-8 items-center justify-center rounded-full bg-signal text-paper font-bold text-xs shadow-md note-pulse-halo animate-heart-pop">
                    <span>{noteName}</span>
                  </div>
                {:else if inScale}
                  <!-- Scale Guide Indicator -->
                  <div class="relative z-10 flex h-5 w-5 items-center justify-center rounded-full bg-paper/15 text-fog text-[10px] font-medium border border-paper/20">
                    <span>{noteName}</span>
                  </div>
                {:else}
                  <!-- Subtle Hover Ghost -->
                  <span class="relative z-10 opacity-0 transition-opacity group-hover:opacity-30 text-[10px] font-mono text-fog">
                    {noteName}
                  </span>
                {/if}
              </button>
            {/each}
          </div>
        {/each}
      </div>
    </div>
  </div>

  <!-- Fretboard Controls & Scale Overlay Selectors -->
  <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 rounded-card border hairline bg-surface-alt p-4 sm:p-5">
    <div>
      <span class="text-caption font-medium text-charcoal">音阶模式辅助高亮 (Scale Overlay)：</span>
      <div class="mt-2 flex flex-wrap gap-2">
        <button
          type="button"
          onclick={() => (selectedScale = 'none')}
          class="chip !py-1 !px-2.5 text-xs {selectedScale === 'none' ? 'chip-active' : ''}"
        >
          无音阶
        </button>
        <button
          type="button"
          onclick={() => (selectedScale = 'c-major')}
          class="chip !py-1 !px-2.5 text-xs {selectedScale === 'c-major' ? 'chip-active' : ''}"
        >
          C 大调自然音阶 (C D E F G A B)
        </button>
        <button
          type="button"
          onclick={() => (selectedScale = 'a-minor-pentatonic')}
          class="chip !py-1 !px-2.5 text-xs {selectedScale === 'a-minor-pentatonic' ? 'chip-active' : ''}"
        >
          A 小调五声音阶 (A C D E G)
        </button>
        <button
          type="button"
          onclick={() => (selectedScale = 'e-blues')}
          class="chip !py-1 !px-2.5 text-xs {selectedScale === 'e-blues' ? 'chip-active' : ''}"
        >
          E 布鲁斯音阶 (E G A Bb B D)
        </button>
      </div>
    </div>

    <div class="flex flex-col justify-center sm:items-end text-caption text-mid-gray space-y-1">
      <div class="flex items-center gap-2">
        <span class="h-2.5 w-2.5 rounded-full bg-signal"></span>
        <span class="text-charcoal font-medium">蓝色光晕：当前和弦按弦点 (Pulse Halo)</span>
      </div>
      <div class="flex items-center gap-2">
        <span class="h-2.5 w-2.5 rounded-full bg-fog/30"></span>
        <span>灰色微圈：当前选定音阶指位辅助</span>
      </div>
      <p class="text-xs text-fog">提示：点击指板任意品格即可自定指位并触发高精度物理合成音效</p>
    </div>
  </div>
</div>
