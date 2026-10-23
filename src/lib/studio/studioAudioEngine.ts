import { acquireGuitarAudioSession, playProgramNote, playProgramChordStrum, getNoteMidi, getAudioContext, type GuitarAudioSession } from '../guitarSound.ts';
import type { StudioProject, StudioBeat, StudioNote } from './studioScoreModel.ts';

/**
 * 制谱工坊专用高保真零延迟物理音频引擎与播放调度器
 * 1. 负责键盘打谱/指板点按/和弦挑选时的 0ms 物理即时发声
 * 2. 彻底由当前 track.tuning 与 track.program 动态驱动，告别硬编码吉他调弦
 * 3. 完美支持多音和弦、附点 (1.5x)、三连音 (2/3x) 的准确时钟步进
 * 4. 内置精准节拍器音效 (playMetronomeTick)
 * 5. 提供与 AlphaTab 谱面光标 100% 同步的可靠步进回调与停止机制
 */

class StudioAudioEngine {
  private isPlaying = false;
  private currentBarIndex = 0;
  private currentBeatIndex = 0;
  private playbackTimer: any = null;
  private playbackSession: GuitarAudioSession | null = null;
  private playbackGeneration = 0;
  private onStepCallback: ((barIdx: number, beatIdx: number) => void) | null = null;
  private onEndCallback: (() => void) | null = null;

  /** 播放单音 (由动态调弦与 program 驱动) */
  playNote(
    stringNum: number,
    fret: number,
    program = 25,
    tuning: Array<number | string> = [64, 59, 55, 50, 45, 40]
  ) {
    const midi = getNoteMidi(stringNum, fret, tuning);
    void playProgramNote(midi, program, 1.2);
  }

  /** 播放和弦扫弦 (支持动态调弦、方向与指定音色) */
  playChord(
    notes: Array<{ string: number; fret: number; dead?: boolean }>,
    program = 25,
    tuning: Array<number | string> = [64, 59, 55, 50, 45, 40],
    direction: 'down' | 'up' = 'down'
  ) {
    const liveNotes = notes.filter((n) => !n.dead);
    const targetNotes = liveNotes.length > 0 ? liveNotes : notes;
    const midiNotes = targetNotes.map((n) => getNoteMidi(n.string, n.fret, tuning));
    if (midiNotes.length > 0) {
      playProgramChordStrum(midiNotes, direction, program);
    }
  }

  /** 播放单个 Beat 中的所有发音 (支持休止符、单音、多音和弦与上下扫弦) */
  playBeat(
    beat: StudioBeat,
    program = 25,
    tuning: Array<number | string> = [64, 59, 55, 50, 45, 40],
    session?: GuitarAudioSession
  ) {
    if (beat.isRest || !beat.notes || beat.notes.length === 0) return;
    const direction: 'down' | 'up' = beat.brush === 'up' ? 'up' : 'down';
    if (beat.notes.length === 1) {
      const midi = getNoteMidi(beat.notes[0].string, beat.notes[0].fret, tuning);
      void playProgramNote(midi, program, 1.2, session);
    } else {
      const liveNotes = beat.notes.filter((n) => !n.dead);
      const targetNotes = liveNotes.length > 0 ? liveNotes : beat.notes;
      const midiNotes = targetNotes.map((n) => getNoteMidi(n.string, n.fret, tuning));
      if (midiNotes.length > 0) void playProgramChordStrum(midiNotes, direction, program, session);
    }
  }

  /** 播放节拍器音效（isDownbeat 为 true 时发较高清脆重音） */
  playMetronomeTick(isDownbeat = false, volume = 0.8, session?: GuitarAudioSession) {
    if (!session?.active) return;
    const ctx = getAudioContext();
    if (!ctx) return;
    try {
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = 'sine';
      // 小节首拍重音 1600Hz -> 800Hz，其他拍 900Hz -> 450Hz
      osc.frequency.setValueAtTime(isDownbeat ? 1600 : 900, now);
      osc.frequency.exponentialRampToValueAtTime(isDownbeat ? 800 : 450, now + 0.025);

      gain.gain.setValueAtTime(volume, now);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.035);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start(now);
      osc.stop(now + 0.04);
      let disconnected = false;
      session.track(osc, () => {
        if (disconnected) return;
        disconnected = true;
        try { osc.disconnect(); } catch { /* already disconnected */ }
        try { gain.disconnect(); } catch { /* already disconnected */ }
      });
    } catch (e) {
      console.warn('[StudioAudio] Metronome tick error:', e);
    }
  }

  /** 开始全谱步进播放 (由乐轨自身 tuning 与 program 动态驱动) */
  async startPlayback(
    project: StudioProject,
    startBar = 0,
    startBeat = 0,
    onStep?: (barIdx: number, beatIdx: number) => void,
    onEnd?: () => void,
    trackIndex = 0,
    enableMetronome = false,
    enableCountIn = false,
    onFocusLost?: () => void
  ): Promise<boolean> {
    this.stopPlayback();
    const generation = this.playbackGeneration;
    this.currentBarIndex = startBar;
    this.currentBeatIndex = startBeat;
    this.onStepCallback = onStep || null;
    this.onEndCallback = onEnd || null;

    const track = project.tracks[trackIndex] || project.tracks[0];
    if (!track) {
      return false;
    }

    let session: GuitarAudioSession;
    try {
      session = await acquireGuitarAudioSession(() => {
        if (this.playbackGeneration !== generation) return;
        this.playbackGeneration++;
        this.isPlaying = false;
        if (this.playbackTimer) clearTimeout(this.playbackTimer);
        this.playbackTimer = null;
        this.playbackSession = null;
        try { onFocusLost?.(); } catch { /* UI callback cannot revive playback */ }
      });
    } catch {
      return false;
    }
    if (generation !== this.playbackGeneration || !session.active) {
      session.release();
      return false;
    }
    this.playbackSession = session;
    this.isPlaying = true;

    const program = track.program ?? 25;
    const tuning = track.tuning && track.tuning.length > 0 ? track.tuning : [64, 59, 55, 50, 45, 40];

    // 高精度时间校准，消除 setTimeout 漂移
    let nextStepExpectedTime = performance.now();
    let countInRemaining = enableCountIn
      ? Math.max(1, Math.min(16, Math.trunc(project.bars[startBar]?.timeSignatureNumerator || 4)))
      : 0;

    const step = () => {
      if (!this.isPlaying) return;

      if (countInRemaining > 0) {
        const firstBar = project.bars[startBar];
        const bpm = firstBar?.tempo || project.initialTempo || 120;
        const denominator = firstBar?.timeSignatureDenominator || 4;
        this.playMetronomeTick(countInRemaining === Math.max(1, Math.min(16, Math.trunc(firstBar?.timeSignatureNumerator || 4))), 0.8, session);
        countInRemaining--;
        nextStepExpectedTime += (60000 / bpm) * (4 / denominator);
        this.playbackTimer = setTimeout(step, Math.max(10, nextStepExpectedTime - performance.now()));
        return;
      }

      if (this.currentBarIndex >= project.bars.length) {
        this.stopPlayback();
        this.onEndCallback?.();
        return;
      }

      const bar = project.bars[this.currentBarIndex];
      if (!bar) {
        this.stopPlayback();
        this.onEndCallback?.();
        return;
      }

      const beats = bar.trackBeats[track.id] || [];

      if (beats.length === 0) {
        this.currentBarIndex++;
        this.currentBeatIndex = 0;
        step();
        return;
      }

      if (this.currentBeatIndex >= beats.length) {
        this.currentBarIndex++;
        this.currentBeatIndex = 0;
        step();
        return;
      }

      const beat = beats[this.currentBeatIndex];
      const curBar = this.currentBarIndex;
      const curBeat = this.currentBeatIndex;

      if (beat) {
        this.playBeat(beat, program, tuning, session);
        if (enableMetronome) {
          this.playMetronomeTick(curBeat === 0, 0.8, session);
        }
        // 触发光标步进回调
        this.onStepCallback?.(curBar, curBeat);
      }

      // 小节速度处理：支持小节独立 BPM (bar.tempo)，沿用初始速度
      const bpm = bar.tempo || project.initialTempo || 120;

      // 计算当前拍的时值毫秒数：附点 (1.5x)、三连音 (2/3x)
      const durationVal = beat?.duration || 4;
      let durationMs = (60000 / bpm) * (4 / durationVal);
      if (beat?.dot) durationMs *= 1.5;
      if (beat?.triplet) durationMs *= (2 / 3);

      this.currentBeatIndex++;

      // 高精度时钟校准调度
      nextStepExpectedTime += durationMs;
      const delay = Math.max(10, nextStepExpectedTime - performance.now());
      this.playbackTimer = setTimeout(step, delay);
    };

    step();
    return true;
  }

  /** 停止播放并清理资源 */
  stopPlayback() {
    this.playbackGeneration++;
    this.isPlaying = false;
    if (this.playbackTimer) {
      clearTimeout(this.playbackTimer);
      this.playbackTimer = null;
    }
    const session = this.playbackSession;
    this.playbackSession = null;
    session?.release();
  }

  get active(): boolean {
    return this.isPlaying;
  }
}

export const studioAudio = new StudioAudioEngine();
export { StudioAudioEngine };
