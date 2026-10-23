<script lang="ts">
  import { playProgramNote, playProgramChordStrum } from '../../lib/guitarSound';
  import { GUITAR_CHORDS, UKULELE_CHORDS, lookupChord, normalizeChord } from '../../lib/chords';

  export interface ActiveNote {
    string: number; // 1..6 (or 1..4 in ukulele) or 0..5 / 0..3
    fret: number; // 0..15 (0=open string)
    finger?: number | string; // 1, 2, 3, 4, 'T'
  }

  export type WoodFinish = 'rosewood' | 'ebony' | 'maple' | 'parchment';
  export type DisplayMode = 'pitch' | 'numbered' | 'finger' | 'fret';

  interface Props {
    activeNotes?: ActiveNote[];
    tuning?: string[];
    capo?: number;
    theme?: 'light' | 'dark';
    className?: string;
    showNoteNames?: boolean;
    interactive?: boolean;
    woodFinish?: WoodFinish;
    currentChord?: string;
    scoreKey?: string;
    displayMode?: DisplayMode;
    soundEnabled?: boolean;
    program?: number;
    soundfontFlavor?: 'gm' | 'ukulele';
    onNoteClick?: (note: { string: number; fret: number; midi?: number; pitch?: string }) => void;
    onWoodFinishChange?: (finish: WoodFinish) => void;
    onDisplayModeChange?: (mode: DisplayMode) => void;
  }

  let {
    activeNotes = [],
    tuning = ['E4', 'B3', 'G3', 'D3', 'A2', 'E2'],
    capo = 0,
    theme = 'light',
    className = '',
    showNoteNames = false,
    interactive = true,
    woodFinish = 'rosewood',
    currentChord = '',
    scoreKey = 'C',
    displayMode: propDisplayMode,
    soundEnabled = true,
    program,
    soundfontFlavor = 'gm',
    onNoteClick,
    onWoodFinishChange,
    onDisplayModeChange,
  }: Props = $props();

  // Local state for UI controls & Finish / Mode selections
  let activeFinish = $state<WoodFinish>(woodFinish);
  let activeMode = $state<DisplayMode>(
    propDisplayMode ?? (showNoteNames ? 'pitch' : 'pitch')
  );
  // Chord selection: 'FOLLOW' = follow score live chord, or explicit chord like 'C', 'G', 'Am', 'Em', 'F', 'D'
  let chordSelection = $state<string>('FOLLOW');
  let hoveredPos = $state<{ string: number; fret: number } | null>(null);
  let lastPluckedPos = $state<{ string: number; fret: number; id: number } | null>(null);
  let isStrumming = $state(false);

  // Sync woodFinish prop if passed from parent
  $effect(() => {
    if (woodFinish) {
      activeFinish = woodFinish;
    }
  });

  // Sync displayMode prop if passed from parent
  $effect(() => {
    if (propDisplayMode) {
      activeMode = propDisplayMode;
    }
  });

  // 4-string ukulele detection
  const isFourString = $derived(tuning.length === 4);

  // Active effective chord (either user-selected or live score chord)
  const effectiveChord = $derived.by(() => {
    if (chordSelection === 'FOLLOW') {
      return currentChord ? currentChord.trim() : '';
    }
    if (chordSelection === 'NONE') {
      return '';
    }
    return chordSelection;
  });

  // String Vibration State: maps string 1..6 (or 1..4) to animation timestamp
  let vibratingStrings = $state<Record<number, number>>({});

  // Fretboard physical geometry: 15 frets + Nut (0)
  const TOTAL_FRETS = 15;
  const FRET_NUMBERS = Array.from({ length: TOTAL_FRETS + 1 }, (_, i) => i);
  // Ukulele standard fret dots: 5, 7, 10, 12, 15; Guitar: 3, 5, 7, 9, 12, 15
  const markedFrets = $derived(isFourString ? [5, 7, 10, 12, 15] : [3, 5, 7, 9, 12, 15]);

  // Chromatic scale for pitch & Jianpu calculations
  const CHROMATIC = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  // Standard ukulele string configs (String 1 = A4, String 2 = E4, String 3 = C4, String 4 = G4 High-G)
  const UKULELE_STRINGS_CONFIG = [
    { num: 1, defaultNote: 'A4', defaultMidi: 69, thickness: 1.2, isWound: false, label: '1弦 (A4)' },
    { num: 2, defaultNote: 'E4', defaultMidi: 64, thickness: 1.5, isWound: false, label: '2弦 (E4)' },
    { num: 3, defaultNote: 'C4', defaultMidi: 60, thickness: 1.9, isWound: false, label: '3弦 (C4)' },
    { num: 4, defaultNote: 'G4', defaultMidi: 67, thickness: 1.3, isWound: false, label: '4弦 (G4 High-G)' },
  ];

  // Standard guitar string configs (String 1 = High E, String 6 = Low E)
  const GUITAR_STRINGS_CONFIG = [
    { num: 1, defaultNote: 'E4', defaultMidi: 64, thickness: 1.1, isWound: false, label: '1弦 (High E)' },
    { num: 2, defaultNote: 'B3', defaultMidi: 59, thickness: 1.4, isWound: false, label: '2弦 (B)' },
    { num: 3, defaultNote: 'G3', defaultMidi: 55, thickness: 1.9, isWound: false, label: '3弦 (G)' },
    { num: 4, defaultNote: 'D3', defaultMidi: 50, thickness: 2.7, isWound: true, label: '4弦 (D)' },
    { num: 5, defaultNote: 'A2', defaultMidi: 45, thickness: 3.4, isWound: true, label: '5弦 (A)' },
    { num: 6, defaultNote: 'E2', defaultMidi: 40, thickness: 4.2, isWound: true, label: '6弦 (Low E)' },
  ];

  const stringsConfig = $derived(isFourString ? UKULELE_STRINGS_CONFIG : GUITAR_STRINGS_CONFIG);

  // Realistic logarithmic-like fret widths (Tapering from Fret 1 to Fret 15)
  const FRET_WEIGHTS = [
    8.8, 8.4, 7.9, 7.5, 7.1, 6.7, 6.4, 6.0, 5.7, 5.4, 5.1, 4.8, 4.6, 4.3, 4.1
  ];
  const TOTAL_WEIGHT = FRET_WEIGHTS.reduce((a, b) => a + b, 0);
  const FRET_WIDTH_PCTS = FRET_WEIGHTS.map((w) => (w / TOTAL_WEIGHT) * 100);

  // Common guitar chords presets for quick exploration
  const COMMON_CHORD_OPTIONS = [
    { value: 'FOLLOW', label: '🎵 跟随乐谱 (实时)' },
    { value: 'C', label: 'C 大和弦' },
    { value: 'G', label: 'G 大和弦' },
    { value: 'Am', label: 'Am 小和弦' },
    { value: 'Em', label: 'Em 小和弦' },
    { value: 'F', label: 'F 大和弦' },
    { value: 'D', label: 'D 大和弦' },
    { value: 'Dm', label: 'Dm 小和弦' },
    { value: 'E', label: 'E 大和弦' },
    { value: 'A', label: 'A 大和弦' },
    { value: 'Bm', label: 'Bm 小和弦' },
    { value: 'Cmaj7', label: 'Cmaj7 大七和弦' },
    { value: 'G7', label: 'G7 属七和弦' },
    { value: 'E7', label: 'E7 属七和弦' },
    { value: 'A7', label: 'A7 属七和弦' },
    { value: 'D7', label: 'D7 属七和弦' },
    { value: 'Fmaj7', label: 'Fmaj7 大七和弦' },
    { value: 'Dsus4', label: 'Dsus4 挂四和弦' },
    { value: 'Asus4', label: 'Asus4 挂四和弦' },
    { value: 'Cadd9', label: 'Cadd9 九和弦' },
    { value: 'F#m', label: 'F#m 小和弦' },
    { value: 'NONE', label: '✨ 全板自由探索' },
  ];

  // Standard finger assignments for common chords [6弦, 5弦, 4弦, 3弦, 2弦, 1弦]
  const CHORD_DEFAULT_FINGERS: Record<string, (number | string | null)[]> = {
    C: [null, 3, 2, null, 1, null],
    C7: [null, 3, 2, 4, 1, null],
    Cmaj7: [null, 3, 2, null, null, null],
    Cadd9: [null, 3, 2, null, 4, null],
    D: [null, null, null, 1, 3, 2],
    Dm: [null, null, null, 2, 3, 1],
    Dm7: [null, null, null, 2, 1, 1],
    D7: [null, null, null, 2, 3, 1],
    Dsus4: [null, null, null, 1, 3, 4],
    Dsus2: [null, null, null, 1, 3, null],
    A: [null, null, 1, 2, 3, null],
    Am: [null, null, 2, 3, 1, null],
    Am7: [null, null, 2, null, 1, null],
    A7: [null, null, 2, null, 3, null],
    Asus4: [null, null, 1, 2, 4, null],
    E: [null, 2, 3, 1, null, null],
    Em: [null, 2, 3, null, null, null],
    Em7: [null, 2, null, null, null, null],
    E7: [null, 2, null, 1, null, null],
    F: [1, 3, 4, 2, 1, 1],
    Fm: [1, 3, 4, 1, 1, 1],
    Fmaj7: [null, null, 3, 2, 1, null],
    G: [3, 2, null, null, null, 4],
    G7: [3, 2, null, null, null, 1],
    Gsus4: [3, 2, null, null, 1, 4],
    B: [null, 1, 3, 3, 3, 1],
    Bm: [null, 1, 3, 4, 2, 1],
    Bm7: [null, 1, 3, 1, 2, 1],
    B7: [null, 2, 1, 3, null, 4],
    'F#m': [1, 3, 4, 1, 1, 1],
  };

  /** Trigger a physics sine-wave harmonic vibration on string 1..6 */
  function triggerStringVibration(stringNum: number) {
    vibratingStrings[stringNum] = Date.now();
    setTimeout(() => {
      if (Date.now() - (vibratingStrings[stringNum] || 0) >= 340) {
        delete vibratingStrings[stringNum];
        vibratingStrings = { ...vibratingStrings };
      }
    }, 380);
  }

  // Trigger string vibrations whenever activeNotes changes during playback
  $effect(() => {
    if (activeNotes && activeNotes.length > 0) {
      const maxStr = stringsConfig.length;
      activeNotes.forEach((n) => {
        let stringNum = n.string;
        if (stringNum >= 0 && stringNum < maxStr && !activeNotes.some((x) => x.string === maxStr)) {
          stringNum = n.string + 1;
        }
        if (stringNum >= 1 && stringNum <= maxStr) {
          triggerStringVibration(stringNum);
        }
      });
    }
  });

  /** Calculate absolute MIDI pitch for string and fret with capo */
  function getMidiPitch(stringNum: number, fretNum: number): number {
    const cfg = stringsConfig[stringNum - 1] || stringsConfig[0];
    const rawTune = tuning[stringNum - 1] || cfg.defaultNote;
    const match = rawTune.match(/^([A-G][#b]?)(-?\d+)?$/);
    let baseMidi = cfg.defaultMidi;

    if (match) {
      let noteName = match[1];
      const octave = match[2] ? parseInt(match[2], 10) : 3;
      const flatMap: Record<string, string> = { Db: 'C#', Eb: 'D#', Gb: 'F#', Ab: 'G#', Bb: 'A#' };
      if (flatMap[noteName]) noteName = flatMap[noteName];
      const noteIdx = CHROMATIC.indexOf(noteName);
      if (noteIdx !== -1) {
        baseMidi = (octave + 1) * 12 + noteIdx;
      }
    }

    const effectiveFret = fretNum + (fretNum > 0 ? capo : 0);
    return baseMidi + effectiveFret;
  }

  /** Calculate pitch name from base string note and fret position */
  function getPitch(stringNum: number, fretNum: number, withOctave = false): string {
    const midi = getMidiPitch(stringNum, fretNum);
    const noteName = CHROMATIC[midi % 12];
    if (!withOctave) return noteName;
    const octave = Math.floor(midi / 12) - 1;
    return `${noteName}${octave}`;
  }

  /**
   * Chinese Jianpu (简谱) converter:
   * Returns degree (1..7), accidental (#/b), and dots above/below based on scale key and octave.
   */
  function getJianpu(stringNum: number, fretNum: number, key = 'C') {
    const midi = getMidiPitch(stringNum, fretNum);
    const noteChromaticIdx = midi % 12;

    let cleanKey = key.replace(/^1=/, '').trim();
    const flatMap: Record<string, string> = { Db: 'C#', Eb: 'D#', Gb: 'F#', Ab: 'G#', Bb: 'A#' };
    if (flatMap[cleanKey]) cleanKey = flatMap[cleanKey];
    let keyIdx = CHROMATIC.indexOf(cleanKey);
    if (keyIdx === -1) keyIdx = 0; // Default C

    const semitone = (noteChromaticIdx - keyIdx + 12) % 12;

    const DEGREE_MAP: Record<number, { num: string; acc: string }> = {
      0: { num: '1', acc: '' },
      1: { num: '1', acc: '♯' },
      2: { num: '2', acc: '' },
      3: { num: '3', acc: '♭' },
      4: { num: '3', acc: '' },
      5: { num: '4', acc: '' },
      6: { num: '4', acc: '♯' },
      7: { num: '5', acc: '' },
      8: { num: '6', acc: '♭' },
      9: { num: '6', acc: '' },
      10: { num: '7', acc: '♭' },
      11: { num: '7', acc: '' },
    };

    const info = DEGREE_MAP[semitone] || { num: '1', acc: '' };
    const refMidi = 60 + (keyIdx > 6 ? keyIdx - 12 : keyIdx);
    const octaveOffset = Math.floor((midi - refMidi) / 12);

    let dotsAbove = 0;
    let dotsBelow = 0;
    if (octaveOffset > 0) {
      dotsAbove = Math.min(2, octaveOffset);
    } else if (octaveOffset < 0) {
      dotsBelow = Math.min(2, Math.abs(octaveOffset));
    }

    return {
      degree: info.num,
      accidental: info.acc,
      dotsAbove,
      dotsBelow,
      display: `${info.acc}${info.num}`,
    };
  }

  /**
   * Parse root note and chord tones intervals
   */
  function parseChordTones(chordName: string): { rootIdx: number; intervals: number[]; chordClean: string } {
    const clean = normalizeChord(chordName) || 'C';
    const match = clean.match(/^([A-G][#b]?)(.*)$/);
    if (!match) return { rootIdx: 0, intervals: [0, 4, 7], chordClean: clean };

    let root = match[1];
    const quality = match[2] || '';
    const flatMap: Record<string, string> = { Db: 'C#', Eb: 'D#', Gb: 'F#', Ab: 'G#', Bb: 'A#' };
    if (flatMap[root]) root = flatMap[root];
    let rootIdx = CHROMATIC.indexOf(root);
    if (rootIdx === -1) rootIdx = 0;

    let intervals = [0, 4, 7]; // Major triad default

    if (quality.startsWith('m7') || quality.startsWith('-7')) {
      intervals = [0, 3, 7, 10]; // Minor 7th
    } else if (quality.startsWith('maj7') || quality.startsWith('M7')) {
      intervals = [0, 4, 7, 11]; // Major 7th
    } else if (quality.startsWith('7')) {
      intervals = [0, 4, 7, 10]; // Dominant 7th
    } else if (quality.startsWith('m') || quality.startsWith('min')) {
      intervals = [0, 3, 7]; // Minor triad
    } else if (quality.startsWith('sus4')) {
      intervals = [0, 5, 7]; // Sus4
    } else if (quality.startsWith('sus2') || quality === '2') {
      intervals = [0, 2, 7]; // Sus2
    } else if (quality.startsWith('add9')) {
      intervals = [0, 2, 4, 7]; // Add9
    } else if (quality.startsWith('dim')) {
      intervals = [0, 3, 6]; // Dim
    } else if (quality.startsWith('aug') || quality === '+') {
      intervals = [0, 4, 8]; // Aug
    } else if (quality.startsWith('6')) {
      intervals = [0, 4, 7, 9]; // 6th
    }

    return { rootIdx, intervals, chordClean: clean };
  }

  /**
   * Check chord tone role for a specific string & fret position
   */
  function getChordToneInfo(stringNum: number, fretNum: number, chordName: string) {
    if (!chordName) return null;
    const { rootIdx, intervals } = parseChordTones(chordName);
    const cfg = stringsConfig[stringNum - 1] || stringsConfig[0];
    const baseMidi = cfg.defaultMidi;
    const nominalMidi = baseMidi + fretNum;
    const noteIdx = nominalMidi % 12;
    const interval = (noteIdx - rootIdx + 12) % 12;

    if (!intervals.includes(interval)) return null;

    let role = '音';
    let roleType: 'root' | 'third' | 'fifth' | 'seventh' | 'other' = 'other';
    if (interval === 0) {
      role = 'R';
      roleType = 'root';
    } else if (interval === 4 || interval === 3) {
      role = interval === 4 ? '3' : '♭3';
      roleType = 'third';
    } else if (interval === 7) {
      role = '5';
      roleType = 'fifth';
    } else if (interval === 11 || interval === 10) {
      role = interval === 11 ? '7' : '♭7';
      roleType = 'seventh';
    }

    return {
      interval,
      role,
      roleType,
      pitchName: CHROMATIC[noteIdx],
    };
  }

  /**
   * Precise Chord Fingering Map (String 1 to String 4 or 6)
   * Adapts dynamically between 4-string Ukulele and 6-string Guitar.
   */
  const activeChordFingering = $derived.by(() => {
    if (!effectiveChord) return null;
    if (isFourString) {
      const norm = normalizeChord(effectiveChord);
      const fingering = UKULELE_CHORDS[effectiveChord] || UKULELE_CHORDS[norm];
      if (!fingering) return null;
      return {
        1: { fret: fingering[3], finger: null },
        2: { fret: fingering[2], finger: null },
        3: { fret: fingering[1], finger: null },
        4: { fret: fingering[0], finger: null },
      };
    }
    const fingering = lookupChord(effectiveChord) || GUITAR_CHORDS[effectiveChord];
    if (!fingering) return null;
    const norm = normalizeChord(effectiveChord);
    const defaultFingers = CHORD_DEFAULT_FINGERS[norm] || [null, null, null, null, null, null];

    return {
      1: { fret: fingering[5], finger: defaultFingers[5] },
      2: { fret: fingering[4], finger: defaultFingers[4] },
      3: { fret: fingering[3], finger: defaultFingers[3] },
      4: { fret: fingering[2], finger: defaultFingers[2] },
      5: { fret: fingering[1], finger: defaultFingers[1] },
      6: { fret: fingering[0], finger: defaultFingers[0] },
    };
  });

  /** Find active note on a given string and fret (handles 1-based and 0-based string index) */
  function findActiveNote(stringNum: number, fretNum: number): ActiveNote | undefined {
    return activeNotes.find((n) => {
      const matchString =
        n.string === stringNum ||
        (n.string === stringNum - 1 && n.string >= 0 && n.string < stringsConfig.length);
      return matchString && n.fret === fretNum;
    });
  }

  /** Handle cell click with harmonic vibration, visual pulse & audio play */
  function handleCellClick(stringNum: number, fretNum: number) {
    if (!interactive) return;

    triggerStringVibration(stringNum);
    lastPluckedPos = { string: stringNum, fret: fretNum, id: Date.now() };

    const midi = getMidiPitch(stringNum, fretNum);
    const pitch = getPitch(stringNum, fretNum, true);

    if (soundEnabled) {
      playProgramNote(midi, program, undefined, undefined, soundfontFlavor).catch(() => {});
    }

    if (onNoteClick) {
      onNoteClick({ string: stringNum, fret: fretNum, midi, pitch });
    }
  }

  /** Play whole chord strum arpeggio */
  async function strumCurrentChord() {
    if (isStrumming) return;
    const targetChord = effectiveChord || 'C';
    isStrumming = true;
    const midiNotes: number[] = [];

    if (isFourString) {
      const norm = normalizeChord(targetChord);
      const fingering = UKULELE_CHORDS[targetChord] || UKULELE_CHORDS[norm];
      if (fingering) {
        // String 4 down to String 1 (G, C, E, A)
        for (let sIdx = 0; sIdx < 4; sIdx++) {
          const val = fingering[sIdx];
          const stringNum = 4 - sIdx;
          if (val !== 'x' && val !== 'X') {
            const fretNum = Number(val);
            midiNotes.push(getMidiPitch(stringNum, fretNum));
            triggerStringVibration(stringNum);
          }
        }
      }
    } else {
      const fingering = lookupChord(targetChord) || GUITAR_CHORDS[targetChord];
      if (fingering) {
        // String 6 (Low E) down to String 1 (High E)
        for (let sIdx = 0; sIdx < 6; sIdx++) {
          const val = fingering[sIdx];
          const stringNum = 6 - sIdx;
          if (val !== 'x' && val !== 'X') {
            const fretNum = Number(val);
            midiNotes.push(getMidiPitch(stringNum, fretNum));
            triggerStringVibration(stringNum);
          }
        }
      }
    }
    if (midiNotes.length > 0) {
      await playProgramChordStrum(midiNotes, 'down', program, undefined, soundfontFlavor);
    }
    setTimeout(() => {
      isStrumming = false;
    }, 550);
  }

  function handleFinishSelect(finish: WoodFinish) {
    activeFinish = finish;
    if (onWoodFinishChange) onWoodFinishChange(finish);
  }

  function handleModeSelect(mode: DisplayMode) {
    activeMode = mode;
    if (onDisplayModeChange) onDisplayModeChange(mode);
  }

  const isDark = $derived(theme === 'dark');
</script>

<div
  class="virtual-fretboard-card relative w-full overflow-hidden rounded-2xl border transition-all duration-300 select-none {isDark
    ? 'border-[#2d2b38] bg-[#14141a]/95 text-[#fafafa] shadow-[0_12px_40px_rgba(0,0,0,0.5)]'
    : 'border-[#e6dfd5] bg-[#faf8f5]/98 text-[#1a1816] shadow-[0_4px_20px_rgba(30,20,10,0.06),0_0_0_1px_rgba(30,20,10,0.02)]'} backdrop-blur-xl {className}"
>
  <!-- ====================================================================
       1. REFINED SINGLE-ROW TOOLBAR (Clean Single-Row Header)
       ==================================================================== -->
  <div
    class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-b px-3.5 py-2.5 sm:px-5 {isDark
      ? 'border-[#252430] bg-[#171620]/85'
      : 'border-[#ede7dc] bg-[#fbf9f4]/90'} backdrop-blur-md"
  >
    <!-- Left: Brand Title + Tuning/Capo/Key Badges -->
    <div class="flex items-center gap-2 sm:gap-2.5 flex-wrap">
      <div class="flex items-center gap-1.5">
        <span class="text-sm sm:text-base leading-none">{isFourString ? '🪵' : '🎸'}</span>
        <span
          class="font-display text-xs sm:text-sm font-bold tracking-tight {isDark
            ? 'text-white'
            : 'text-[#1c1917]'}"
        >
          {isFourString ? '尤克里里指板' : '虚拟指板'}
        </span>
      </div>

      <!-- Tuning Badge -->
      <div
        class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] sm:text-[11px] font-mono font-medium {isDark
          ? 'border-[#333142] bg-[#1d1c28] text-[#cbd5e1]'
          : 'border-[#e2dcce] bg-white text-[#57534e]'}"
        title={isFourString ? "标准定弦: 1弦(A4) ~ 4弦(G4)" : "标准定弦: 1弦(E) ~ 6弦(E)"}
      >
        <span class="text-[9px] sm:text-[10px] text-[#8c857b] font-sans">调弦</span>
        <span class="font-bold text-[#41a1cf]">
          {tuning.map((t) => t.replace(/\d+$/, '')).join('·')}
        </span>
      </div>

      <!-- Capo Badge -->
      {#if capo > 0}
        <div
          class="inline-flex items-center gap-1 rounded-full border border-[#41a1cf]/40 bg-[#41a1cf]/10 px-2 py-0.5 text-[10px] sm:text-[11px] font-medium text-[#41a1cf]"
          title={`当前变调夹夹在第 ${capo} 品`}
        >
          <span class="h-1.5 w-1.5 rounded-full bg-[#41a1cf]"></span>
          <span>变调夹 {capo} 品</span>
        </div>
      {/if}

      <!-- Score Key Badge -->
      {#if scoreKey}
        <div
          class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] sm:text-[11px] font-mono {isDark
            ? 'border-[#333142] bg-[#1d1c28] text-[#d6d3d1]'
            : 'border-[#e2dcce] bg-white text-[#57534e]'}"
          title="曲谱原调"
        >
          <span class="text-[9px] sm:text-[10px] text-[#8c857b] font-sans">调号</span>
          <span class="font-bold text-amber-500">{scoreKey}</span>
        </div>
      {/if}

      <!-- Current Active Chord Pill if following score -->
      {#if effectiveChord}
        <div
          class="inline-flex items-center gap-1 rounded-full border border-amber-500/40 bg-amber-500/10 px-2 py-0.5 text-[10px] sm:text-[11px] font-mono font-bold text-amber-600 dark:text-amber-400 shadow-2xs"
          title="当前指板对焦和弦"
        >
          <span>和弦</span>
          <span class="text-amber-500">{effectiveChord}</span>
        </div>
      {/if}
    </div>

    <!-- Right: Material Switcher + Display Mode Segmenter + Chord Selector + Strum Button -->
    <div class="flex items-center gap-1.5 sm:gap-2 flex-wrap ml-auto">
      <!-- 1.1 Wood Material Micro-Switcher -->
      <div
        class="flex items-center rounded-full border p-0.5 text-[11px] font-medium {isDark
          ? 'border-[#2c2a38] bg-[#161520]'
          : 'border-[#e4ded2] bg-[#ede7da]'}"
        title="指板木质材质切换"
      >
        <button
          type="button"
          onclick={() => handleFinishSelect('rosewood')}
          class="flex items-center gap-1 rounded-full px-2 py-0.5 transition-all {activeFinish === 'rosewood'
            ? 'bg-[#3b2014] text-[#fcd34d] font-bold shadow-xs'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="玫瑰木 (Rosewood · 温暖巧克力红褐)"
        >
          <span>🌹</span>
          <span class="hidden sm:inline">玫瑰木</span>
        </button>

        <button
          type="button"
          onclick={() => handleFinishSelect('ebony')}
          class="flex items-center gap-1 rounded-full px-2 py-0.5 transition-all {activeFinish === 'ebony'
            ? 'bg-[#18171c] text-[#38bdf8] font-bold shadow-xs'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="黑檀木 (Ebony · 沉稳深色细密木纹)"
        >
          <span>🪵</span>
          <span class="hidden sm:inline">黑檀木</span>
        </button>

        <button
          type="button"
          onclick={() => handleFinishSelect('maple')}
          class="flex items-center gap-1 rounded-full px-2 py-0.5 transition-all {activeFinish === 'maple'
            ? 'bg-[#c68e4a] text-white font-bold shadow-xs'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="枫木 (Maple · 琥珀暖金枫木)"
        >
          <span>🍁</span>
          <span class="hidden sm:inline">枫木</span>
        </button>

        <button
          type="button"
          onclick={() => handleFinishSelect('parchment')}
          class="flex items-center gap-1 rounded-full px-2 py-0.5 transition-all {activeFinish === 'parchment'
            ? 'bg-[#f5efe6] text-[#292524] font-bold shadow-xs'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="宣纸 (Parchment · 极简雅致宣纸)"
        >
          <span>📜</span>
          <span class="hidden sm:inline">宣纸</span>
        </button>
      </div>

      <!-- 1.2 Display Mode Segmented Control (音名 | 简谱 | 指法 | 品数) -->
      <div
        class="flex items-center rounded-full border p-0.5 text-[11px] font-medium {isDark
          ? 'border-[#2c2a38] bg-[#161520]'
          : 'border-[#e4ded2] bg-[#ede7da]'}"
        title="指板显示模式"
      >
        <button
          type="button"
          onclick={() => handleModeSelect('pitch')}
          class="rounded-full px-2 sm:px-2.5 py-0.5 transition-all {activeMode === 'pitch'
            ? isDark
              ? 'bg-[#2a283a] text-white shadow-xs font-bold'
              : 'bg-white text-[#1c1917] shadow-xs font-bold'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="音名模式 (C, D, E, F, G, A, B)"
        >
          音名
        </button>

        <button
          type="button"
          onclick={() => handleModeSelect('numbered')}
          class="rounded-full px-2 sm:px-2.5 py-0.5 transition-all {activeMode === 'numbered'
            ? isDark
              ? 'bg-[#2a283a] text-[#38bdf8] shadow-xs font-bold'
              : 'bg-white text-[#0284c7] shadow-xs font-bold'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="简谱模式 (1, 2, 3, 4, 5, 6, 7)"
        >
          简谱
        </button>

        <button
          type="button"
          onclick={() => handleModeSelect('finger')}
          class="rounded-full px-2 sm:px-2.5 py-0.5 transition-all {activeMode === 'finger'
            ? isDark
              ? 'bg-[#2a283a] text-white shadow-xs font-bold'
              : 'bg-white text-[#1c1917] shadow-xs font-bold'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="指法模式 (1食, 2中, 3无名, 4小指)"
        >
          指法
        </button>

        <button
          type="button"
          onclick={() => handleModeSelect('fret')}
          class="rounded-full px-2 sm:px-2.5 py-0.5 transition-all {activeMode === 'fret'
            ? isDark
              ? 'bg-[#2a283a] text-white shadow-xs font-bold'
              : 'bg-white text-[#1c1917] shadow-xs font-bold'
            : isDark
              ? 'text-[#9ca3af] hover:text-white'
              : 'text-[#6b7280] hover:text-[#111827]'}"
          title="品数模式 (0, 1, 2, 3...)"
        >
          品数
        </button>
      </div>

      <!-- 1.3 Chord Shape Micro-Selector Dropdown -->
      <div class="relative flex items-center">
        <select
          bind:value={chordSelection}
          class="fretboard-chord-select rounded-full border pl-2.5 pr-6 py-0.5 text-[11px] font-mono font-medium outline-none cursor-pointer transition-all {isDark
            ? 'border-[#333142] bg-[#1a1926] text-white hover:border-[#4c4960]'
            : 'border-[#e2dcce] bg-white text-[#292524] hover:border-[#b8b0a2]'}"
          title="和弦指型聚焦选择 (精准高亮 4~6 个标准发音品位)"
        >
          {#each COMMON_CHORD_OPTIONS as opt}
            <option value={opt.value} class="font-sans text-xs">
              {opt.label}
            </option>
          {/each}
        </select>
        <span class="pointer-events-none absolute right-2 text-[9px] text-[#8c857b]">▾</span>
      </div>

      <!-- 1.4 Quick Strum Button (⚡ 扫弦) -->
      <button
        type="button"
        onclick={strumCurrentChord}
        disabled={isStrumming}
        class="inline-flex items-center gap-1 rounded-full border border-amber-500/40 bg-amber-500/10 px-2.5 py-0.5 text-[11px] font-semibold text-amber-600 dark:text-amber-400 hover:bg-amber-500/20 active:scale-95 transition-all shadow-2xs disabled:opacity-50"
        title="试听当前和弦扫弦"
      >
        <span class="{isStrumming ? 'animate-spin' : ''}">⚡</span>
        <span>{isStrumming ? '扫弦中' : '扫弦'}</span>
      </button>
    </div>
  </div>

  <!-- ====================================================================
       2. FRETBOARD MAIN STAGE (Scrollable with Silk Wood Bed & Refined Frets)
       ==================================================================== -->
  <div class="fretboard-viewport w-full overflow-x-auto px-3 py-3.5 sm:px-5 sm:py-4">
    <div class="fretboard-container relative mx-auto min-w-[760px] max-w-full">
      <!-- 2.1 FRET NUMBERS TOP RULER -->
      <div class="mb-1.5 flex w-full items-center text-[10px] font-mono select-none">
        <!-- Nut header -->
        <div class="w-[52px] shrink-0 text-center font-bold text-[#8c857b]">
          NUT · 0
        </div>
        <!-- Fret columns headers -->
        <div class="flex flex-1 items-center">
          {#each FRET_NUMBERS.slice(1) as fret, idx}
            {@const isMarked = markedFrets.includes(fret)}
            {@const isCapoFret = capo > 0 && capo === fret}
            <div
              style="width: {FRET_WIDTH_PCTS[idx]}%;"
              class="flex shrink-0 items-center justify-center"
            >
              <div
                class="flex h-4 w-4 items-center justify-center rounded-full text-[10px] font-medium transition-all {isCapoFret
                  ? 'bg-[#41a1cf] text-white font-bold shadow-[0_0_6px_#41a1cf]'
                  : isMarked
                    ? isDark
                      ? 'border border-[#444256] bg-[#222130] text-[#38bdf8]'
                      : 'border border-[#d6cfc2] bg-white text-[#1c1917] shadow-2xs'
                    : isDark
                      ? 'text-[#6b7280]'
                      : 'text-[#a8a29e]'}"
              >
                {fret}
              </div>
            </div>
          {/each}
        </div>
      </div>

      <!-- 2.2 WOOD FINISH NECK BED & HARDWARE -->
      <div
        class="fretboard-neck relative flex w-full rounded-xl border finish-{activeFinish} shadow-inner transition-colors duration-300"
        style="height: {isFourString ? '138px' : '180px'};"
      >
        <!-- LEFT: IVORY / BONE NUT WITH OPEN STRING TARGETS (Fret 0) -->
        <div
          class="relative flex w-[52px] shrink-0 flex-col justify-between py-2.5 px-1 border-r {activeFinish === 'maple' || activeFinish === 'parchment'
            ? 'border-[#c6bba5] bg-[#eae3d5]/50'
            : 'border-[#1b1714] bg-[#0f0d0b]/70'}"
        >
          <!-- 3D BONE NUT BAR with string notch slots -->
          <div
            class="nut-bone-block absolute top-0 bottom-0 right-0 w-[5px] z-10 flex flex-col justify-between py-2.5 pointer-events-none"
          >
            {#each stringsConfig as stringCfg}
              <div class="relative flex h-6 items-center justify-center">
                <div
                  style="height: {Math.max(1, stringCfg.thickness * 0.6)}px;"
                  class="w-full bg-[#3d3326]/70"
                ></div>
              </div>
            {/each}
          </div>

          <!-- Open String Hit Targets & Precise Badges -->
          {#each stringsConfig as stringCfg}
            {@const stringNum = stringCfg.num}
            {@const openActive = findActiveNote(stringNum, 0)}
            {@const chordEntry = activeChordFingering ? activeChordFingering[stringNum as 1|2|3|4|5|6] : null}
            {@const isChordOpen = chordEntry && (chordEntry.fret === 0 || chordEntry.fret === '0')}
            {@const isChordMuted = chordEntry && (chordEntry.fret === 'x' || chordEntry.fret === 'X')}
            {@const openChordTone = isChordOpen && effectiveChord ? getChordToneInfo(stringNum, 0, effectiveChord) : null}
            {@const isRoot = openChordTone?.roleType === 'root'}
            {@const isHovered = hoveredPos?.string === stringNum && hoveredPos?.fret === 0}
            {@const isPlucked = lastPluckedPos?.string === stringNum && lastPluckedPos?.fret === 0}

            <div
              class="relative z-20 flex h-6 items-center justify-center {interactive ? 'cursor-pointer' : ''}"
              onclick={() => handleCellClick(stringNum, 0)}
              onmouseenter={() => (hoveredPos = { string: stringNum, fret: 0 })}
              onmouseleave={() => (hoveredPos = null)}
              role={interactive ? 'button' : 'presentation'}
              tabindex={interactive ? 0 : -1}
              onkeydown={(e) => {
                if (interactive && (e.key === 'Enter' || e.key === ' ')) {
                  handleCellClick(stringNum, 0);
                }
              }}
              title={`${stringCfg.label} 空弦 (0品)`}
            >
              {#if openActive}
                <!-- Live Playing Note from Score -->
                <div class="relative flex items-center justify-center">
                  {#if isPlucked}
                    <div class="fret-shockwave absolute h-8 w-8 rounded-full border border-amber-400 opacity-90"></div>
                  {/if}
                  <div
                    class="fret-spring-pop relative flex h-5 min-w-5 items-center justify-center rounded-full bg-gradient-to-br from-amber-400 via-amber-500 to-amber-600 px-1 text-[10px] font-bold text-white shadow-[0_2px_8px_rgba(223,168,73,0.5)] ring-1 ring-white"
                  >
                    {#if activeMode === 'numbered'}
                      {getJianpu(stringNum, 0, scoreKey).display}
                    {:else if activeMode === 'pitch'}
                      {getPitch(stringNum, 0)}
                    {:else if activeMode === 'finger' && openActive.finger != null}
                      {openActive.finger}
                    {:else}
                      0
                    {/if}
                  </div>
                </div>
              {:else if isChordOpen}
                <!-- Chord Shape Open String Indicator (Root in Matte Gold, Tone in Pearl White) -->
                <div
                  class="fret-spring-pop relative flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold {isRoot
                    ? 'fret-badge-root'
                    : 'fret-badge-tone'}"
                  title={`${stringCfg.label} 空弦发音: ${getPitch(stringNum, 0)} (${isRoot ? '根音 Root' : '内音'})`}
                >
                  {#if activeMode === 'numbered'}
                    {getJianpu(stringNum, 0, scoreKey).display}
                  {:else if activeMode === 'pitch'}
                    {getPitch(stringNum, 0)}
                  {:else if activeMode === 'finger'}
                    0
                  {:else}
                    0
                  {/if}
                </div>
              {:else if isChordMuted}
                <!-- Chord Shape Muted String -->
                <div class="text-[10px] font-mono font-bold text-[#8c857b]/70" title="闷音 (不发声)">
                  ✕
                </div>
              {:else}
                <!-- Standard Tuning Base String Label -->
                <div
                  class="flex h-4 w-4 items-center justify-center rounded-full text-[9px] font-mono font-semibold transition-all {isHovered
                    ? 'bg-[#41a1cf]/20 text-[#41a1cf] scale-110'
                    : activeFinish === 'maple' || activeFinish === 'parchment'
                      ? 'text-[#57534e]'
                      : 'text-[#a8a29e]'}"
                >
                  {(tuning[stringNum - 1] || stringCfg.defaultNote).replace(/\d+$/, '')}
                </div>
              {/if}
            </div>
          {/each}
        </div>

        <!-- RIGHT: FRETTED ZONE (Frets 1..15) -->
        <div class="relative flex flex-1 overflow-hidden">
          <!-- 2.3 SUBTLE MOTHER-OF-PEARL POSITION INLAYS (3, 5, 7, 9, 12, 15) -->
          <div class="pointer-events-none absolute inset-0 flex h-full w-full">
            {#each FRET_NUMBERS.slice(1) as fret, idx}
              <div
                style="width: {FRET_WIDTH_PCTS[idx]}%;"
                class="relative h-full shrink-0"
              >
                {#if markedFrets.filter((f) => f !== 12).includes(fret)}
                  <div class="absolute inset-0 flex items-center justify-center">
                    <div class="pearl-inlay-dot h-2.5 w-2.5 rounded-full"></div>
                  </div>
                {/if}

                {#if fret === 12}
                  <div class="absolute inset-0 flex flex-col justify-between py-10 items-center">
                    <div class="pearl-inlay-dot h-2 w-2 rounded-full"></div>
                    <div class="pearl-inlay-dot h-2 w-2 rounded-full"></div>
                  </div>
                {/if}
              </div>
            {/each}
          </div>

          <!-- 2.4 NICKEL-SILVER 1.5px SLIM FRET WIRES -->
          <div class="pointer-events-none absolute inset-0 flex h-full w-full">
            {#each FRET_NUMBERS.slice(1) as fret, idx}
              <div
                style="width: {FRET_WIDTH_PCTS[idx]}%;"
                class="relative h-full shrink-0"
              >
                <div class="fret-wire-nickel absolute top-0 bottom-0 right-0 w-[1.5px]"></div>
              </div>
            {/each}
          </div>

          <!-- 2.5 SLIM ALUMINUM CAPO CLAMP BAR (Rendered if capo > 0) -->
          {#if capo > 0 && capo <= TOTAL_FRETS}
            {@const capoIdx = capo - 1}
            {@const leftOffsetPct =
              FRET_WIDTH_PCTS.slice(0, capoIdx).reduce((a, b) => a + b, 0) +
              FRET_WIDTH_PCTS[capoIdx] * 0.76}
            <div
              style="left: {leftOffsetPct}%;"
              class="pointer-events-none absolute top-[-6px] bottom-[-6px] z-30 flex -translate-x-1/2 flex-col items-center"
            >
              <!-- Capo Top Compact Fastener -->
              <div
                class="h-2 w-5 rounded-t-sm bg-gradient-to-b from-[#475569] to-[#1e293b] border border-[#64748b] shadow-xs"
              ></div>
              <!-- Capo Slim Clamp Bar -->
              <div
                class="w-1.5 flex-1 rounded-xs bg-gradient-to-r from-[#334155] via-[#64748b] to-[#1e293b] shadow-[0_2px_8px_rgba(0,0,0,0.5)]"
              ></div>
              <!-- Capo Bottom Cushion -->
              <div
                class="h-1.5 w-4 rounded-b-sm bg-[#0f172a] border-t border-[#475569]"
              ></div>
            </div>
          {/if}

          <!-- 2.6 REAL GUITAR/UKULELE STRINGS WITH SINE-WAVE VIBRATION ANIMATION -->
          <div class="pointer-events-none absolute inset-0 flex flex-col justify-between py-2.5">
            {#each stringsConfig as stringCfg}
              {@const isVibrating = !!vibratingStrings[stringCfg.num]}
              <div
                class="relative flex h-6 items-center {isVibrating ? 'string-vibrating' : ''}"
              >
                <div
                  style="height: {stringCfg.thickness}px;"
                  class="w-full transition-all {stringCfg.isWound
                    ? 'string-wound-bronze'
                    : 'string-plain-steel'}"
                ></div>
              </div>
            {/each}
          </div>

          <!-- 2.7 INTERACTIVE FRET CELLS & SMART-FOCUSED CHORD FRET POSITIONS -->
          <div class="relative flex h-full w-full">
            {#each FRET_NUMBERS.slice(1) as fret, idx}
              <div
                style="width: {FRET_WIDTH_PCTS[idx]}%;"
                class="relative flex h-full shrink-0 flex-col justify-between py-2.5"
              >
                {#each stringsConfig as stringCfg}
                  {@const stringNum = stringCfg.num}
                  {@const activeNote = findActiveNote(stringNum, fret)}
                  {@const chordEntry = activeChordFingering ? activeChordFingering[stringNum as 1|2|3|4|5|6] : null}
                  {@const isChordFret = chordEntry && typeof chordEntry.fret !== 'undefined' && Number(chordEntry.fret) === fret}
                  {@const chordTone = isChordFret && effectiveChord ? getChordToneInfo(stringNum, fret, effectiveChord) : null}
                  {@const isRoot = chordTone?.roleType === 'root'}
                  {@const isHovered = hoveredPos?.string === stringNum && hoveredPos?.fret === fret}
                  {@const isPlucked = lastPluckedPos?.string === stringNum && lastPluckedPos?.fret === fret}

                  <div
                    class="relative z-20 flex h-6 items-center justify-center {interactive
                      ? 'cursor-pointer'
                      : ''}"
                    onclick={() => handleCellClick(stringNum, fret)}
                    onmouseenter={() => (hoveredPos = { string: stringNum, fret })}
                    onmouseleave={() => (hoveredPos = null)}
                    role={interactive ? 'button' : 'presentation'}
                    tabindex={interactive ? 0 : -1}
                    onkeydown={(e) => {
                      if (interactive && (e.key === 'Enter' || e.key === ' ')) {
                        handleCellClick(stringNum, fret);
                      }
                    }}
                    title={`${stringCfg.label} · 第 ${fret} 品 (${getPitch(stringNum, fret, true)})`}
                  >
                    {#if activeNote}
                      <!-- Active Note Plucked or Played from Live Score -->
                      <div class="relative flex items-center justify-center">
                        {#if isPlucked}
                          <div class="fret-shockwave absolute h-9 w-9 rounded-full border border-amber-400 opacity-90"></div>
                        {/if}
                        <div
                          class="fret-spring-pop relative flex h-5 min-w-5 items-center justify-center rounded-full bg-gradient-to-br from-amber-400 via-amber-500 to-amber-600 px-1 text-[10px] font-bold text-white shadow-[0_2px_8px_rgba(223,168,73,0.5)] ring-1 ring-white"
                        >
                          {#if activeMode === 'numbered'}
                            {@const jp = getJianpu(stringNum, fret, scoreKey)}
                            <span class="leading-none">{jp.display}</span>
                          {:else if activeMode === 'pitch'}
                            {getPitch(stringNum, fret)}
                          {:else if activeMode === 'finger' && activeNote.finger != null}
                            {activeNote.finger}
                          {:else}
                            {fret}
                          {/if}
                        </div>
                      </div>
                    {:else if isChordFret}
                      <!-- Smart Chord Fingering Position (Root in Matte Gold, Chord Tone in Pearl White) -->
                      <div class="relative flex items-center justify-center">
                        <div
                          class="fret-spring-pop relative flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold {isRoot
                            ? 'fret-badge-root'
                            : 'fret-badge-tone'}"
                          title={`${getPitch(stringNum, fret)} (${isRoot ? '根音 Root' : '内音'})`}
                        >
                          {#if activeMode === 'numbered'}
                            {@const jp = getJianpu(stringNum, fret, scoreKey)}
                            <span class="leading-none">{jp.display}</span>
                          {:else if activeMode === 'pitch'}
                            {getPitch(stringNum, fret)}
                          {:else if activeMode === 'finger'}
                            {chordEntry?.finger ?? (isRoot ? 'R' : '●')}
                          {:else}
                            {fret}
                          {/if}
                        </div>
                      </div>
                    {:else if isHovered && interactive}
                      <!-- Sleek Frosted Ghost Hover Guide -->
                      <div
                        class="flex h-4 w-4 items-center justify-center rounded-full border border-white/60 bg-white/20 text-[9px] font-mono font-medium text-white backdrop-blur-xs transition-all scale-105 shadow-xs"
                      >
                        {#if activeMode === 'numbered'}
                          {getJianpu(stringNum, fret, scoreKey).degree}
                        {:else if activeMode === 'pitch'}
                          {getPitch(stringNum, fret)}
                        {:else}
                          {fret}
                        {/if}
                      </div>
                    {/if}
                  </div>
                {/each}
              </div>
            {/each}
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  /* ==========================================================================
     SILKY WOOD FINISH TEXTURES (Refined Deep Diffuse Pores & Subtle Lustre)
     ========================================================================== */

  /* 1. Rosewood (🌹 玫瑰木 / 温暖巧克力红褐微木纹) */
  .finish-rosewood {
    background-color: #24140e;
    background-image:
      linear-gradient(180deg, rgba(255, 255, 255, 0.06) 0%, rgba(255, 255, 255, 0.01) 30%, rgba(0, 0, 0, 0.35) 100%),
      repeating-linear-gradient(
        90deg,
        rgba(30, 16, 11, 0.96) 0px,
        rgba(42, 23, 16, 0.98) 6px,
        rgba(26, 14, 9, 0.96) 12px,
        rgba(38, 21, 14, 0.98) 18px,
        rgba(22, 12, 8, 0.96) 24px
      );
    border-color: #3d2217;
    box-shadow: inset 0 1px 4px rgba(0, 0, 0, 0.6), inset 0 -1px 4px rgba(0, 0, 0, 0.6), 0 4px 16px rgba(0, 0, 0, 0.3);
  }

  /* 2. Ebony (🪵 黑檀木 / 沉稳细密深油木纹) */
  .finish-ebony {
    background-color: #121114;
    background-image:
      linear-gradient(180deg, rgba(255, 255, 255, 0.07) 0%, rgba(255, 255, 255, 0.01) 25%, rgba(0, 0, 0, 0.45) 100%),
      repeating-linear-gradient(
        90deg,
        rgba(16, 15, 18, 1) 0px,
        rgba(22, 21, 25, 0.96) 5px,
        rgba(14, 13, 16, 1) 10px,
        rgba(19, 18, 22, 0.96) 16px
      );
    border-color: #22202a;
    box-shadow: inset 0 1px 4px rgba(0, 0, 0, 0.7), inset 0 -1px 4px rgba(0, 0, 0, 0.7), 0 4px 16px rgba(0, 0, 0, 0.4);
  }

  /* 3. Golden Maple (🍁 琥珀金枫木 / 柔和水波暗纹) */
  .finish-maple {
    background-color: #d49a55;
    background-image:
      linear-gradient(180deg, rgba(255, 255, 255, 0.35) 0%, rgba(255, 255, 255, 0.05) 38%, rgba(130, 75, 18, 0.18) 100%),
      repeating-linear-gradient(
        90deg,
        rgba(222, 178, 118, 0.98) 0px,
        rgba(230, 192, 138, 0.95) 7px,
        rgba(212, 165, 102, 0.98) 14px,
        rgba(235, 202, 150, 0.95) 21px
      );
    border-color: #b87e38;
    box-shadow: inset 0 1px 4px rgba(70, 38, 10, 0.2), inset 0 -1px 4px rgba(70, 38, 10, 0.25), 0 4px 14px rgba(90, 50, 14, 0.12);
  }

  /* 4. Parchment (📜 极简雅致宣纸) */
  .finish-parchment {
    background-color: #f7f4ed;
    background-image:
      linear-gradient(180deg, rgba(255, 255, 255, 0.92) 0%, rgba(250, 246, 237, 0.95) 50%, rgba(240, 233, 220, 0.98) 100%),
      repeating-linear-gradient(
        90deg,
        rgba(244, 238, 228, 0.9) 0px,
        rgba(250, 247, 240, 0.95) 8px,
        rgba(240, 233, 220, 0.9) 16px
      );
    border-color: #ded6c6;
    box-shadow: inset 0 1px 3px rgba(40, 30, 10, 0.04), 0 2px 10px rgba(0, 0, 0, 0.03);
  }

  /* ==========================================================================
     HARDWARE: Slim 1.5px Fretwires, Bone Nut & Soft Pearl Inlays
     ========================================================================== */

  /* Fine 1.5px Nickel-Silver Fretwire */
  .fret-wire-nickel {
    background: linear-gradient(
      90deg,
      rgba(0, 0, 0, 0.35) 0%,
      #ffffff 35%,
      #94a3b8 75%,
      rgba(0, 0, 0, 0.4) 100%
    );
    box-shadow: 0.5px 0 1px rgba(0, 0, 0, 0.3);
  }

  /* Real Bone Nut Block */
  .nut-bone-block {
    background: linear-gradient(
      90deg,
      #dcd5c2 0%,
      #f8f4e9 40%,
      #ffffff 60%,
      #ded6c4 85%,
      #b3a890 100%
    );
    box-shadow:
      inset 0 1px 1px rgba(255, 255, 255, 0.8),
      1px 0 3px rgba(0, 0, 0, 0.35);
  }

  /* Subtle Mother-of-Pearl Inlays */
  .pearl-inlay-dot {
    background: radial-gradient(
      circle at 35% 35%,
      #ffffff 0%,
      #f2f8fa 25%,
      #e2eff3 50%,
      #ebe5d6 75%,
      #b3aa98 100%
    );
    box-shadow:
      inset 0 1px 1px rgba(255, 255, 255, 0.9),
      0 1px 2px rgba(0, 0, 0, 0.45);
    border: 0.5px solid rgba(255, 255, 255, 0.3);
  }

  /* Plain Steel Strings (Strings 1~3) */
  .string-plain-steel {
    background: linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.95) 0%,
      rgba(203, 213, 225, 0.9) 40%,
      rgba(71, 85, 105, 0.95) 100%
    );
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.4);
  }

  /* Phosphor Bronze Wound Strings (Strings 4~6) */
  .string-wound-bronze {
    background-color: #a87f38;
    background-image:
      linear-gradient(
        180deg,
        rgba(255, 255, 255, 0.7) 0%,
        rgba(254, 240, 199, 0.3) 25%,
        rgba(0, 0, 0, 0.25) 65%,
        rgba(0, 0, 0, 0.6) 100%
      ),
      repeating-linear-gradient(
        90deg,
        #6e4a18 0px,
        #deb356 1px,
        #fef0c7 1.6px,
        #a87f38 2.4px,
        #523610 3.2px
      );
    box-shadow: 0 1px 2.5px rgba(0, 0, 0, 0.5);
  }

  /* ==========================================================================
     REFINED COLOR PALETTE: Matte Gold (Root) & Pearl White (Chord Tones)
     ========================================================================== */

  /* Root Note: Elegant Matte Gold with subtle luminous halo */
  .fret-badge-root {
    background: linear-gradient(135deg, #f59e0b 0%, #d97706 60%, #b45309 100%) !important;
    color: #ffffff !important;
    font-weight: 800 !important;
    border: 1px solid rgba(255, 255, 255, 0.85) !important;
    box-shadow: 0 2px 10px rgba(217, 119, 6, 0.6), 0 0 0 1px rgba(255, 255, 255, 0.9) !important;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
  }

  /* Chord Tone: Pearlescent Warm White with refined dark text & subtle border */
  .fret-badge-tone {
    background: linear-gradient(135deg, #ffffff 0%, #f1f5f9 100%) !important;
    color: #0f172a !important;
    font-weight: 700 !important;
    border: 1px solid rgba(0, 0, 0, 0.2) !important;
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.3), 0 1px 2px rgba(0, 0, 0, 0.15) !important;
  }

  /* ==========================================================================
     PHYSICS & HARMONIC SINE-WAVE VIBRATION ANIMATIONS
     ========================================================================== */

  @keyframes string-vibrate-harmonic {
    0% {
      transform: translateY(0px) scaleY(1);
    }
    15% {
      transform: translateY(-2.8px) scaleY(1.3);
      filter: brightness(1.2);
    }
    30% {
      transform: translateY(2.2px) scaleY(1.2);
    }
    48% {
      transform: translateY(-1.5px) scaleY(1.12);
    }
    68% {
      transform: translateY(0.8px) scaleY(1.06);
    }
    85% {
      transform: translateY(-0.3px) scaleY(1.02);
    }
    100% {
      transform: translateY(0px) scaleY(1);
    }
  }

  .string-vibrating {
    animation: string-vibrate-harmonic 0.34s cubic-bezier(0.36, 0, 0.66, -0.56) forwards;
  }

  @keyframes fret-pop {
    0% {
      transform: scale(0.4);
      opacity: 0.3;
    }
    60% {
      transform: scale(1.16);
      opacity: 1;
    }
    80% {
      transform: scale(0.95);
    }
    100% {
      transform: scale(1);
      opacity: 1;
    }
  }

  @keyframes fret-shockwave-expand {
    0% {
      transform: scale(0.5);
      opacity: 1;
    }
    100% {
      transform: scale(2.8);
      opacity: 0;
    }
  }

  .fret-spring-pop {
    animation: fret-pop 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards;
  }

  .fret-shockwave {
    animation: fret-shockwave-expand 0.42s cubic-bezier(0.1, 0.9, 0.2, 1) forwards;
  }

  /* Custom Smooth Scrollbar */
  .fretboard-viewport::-webkit-scrollbar {
    height: 5px;
  }
  .fretboard-viewport::-webkit-scrollbar-track {
    background: transparent;
  }
  .fretboard-viewport::-webkit-scrollbar-thumb {
    background: rgba(140, 140, 140, 0.2);
    border-radius: 3px;
  }
  .fretboard-viewport::-webkit-scrollbar-thumb:hover {
    background: rgba(140, 140, 140, 0.4);
  }

  @media (prefers-reduced-motion: reduce) {
    .fret-spring-pop,
    .fret-shockwave,
    .string-vibrating {
      animation: none !important;
    }
  }
</style>
