import { getInstrumentByProgram, type GMInstrumentInfo } from './gmInstruments.ts';
import { claimAudioFocus } from './player/audioFocus.ts';

type InstrumentFlavor = 'gm' | 'ukulele';

export interface GlobalInstrumentSelectionSnapshot {
  program: number;
  flavor: InstrumentFlavor;
  instrumentOverride: boolean;
  source: string;
  scoreId: string | null;
}

export interface GlobalInstrumentSelectionOptions {
  source?: string;
  broadcast?: boolean;
  flavor?: InstrumentFlavor;
  instrumentOverride?: boolean;
  scoreId?: string | null;
}

/**
 * All guitar and studio previews use SoundFont samples rendered offline by
 * alphaTab. alphaTab is imported only after a note is requested so the player
 * does not add its synthesizer to the light homepage bundle.
 */

let globalAudioCtx: AudioContext | null = null;
let currentProgram = 25;
let instrumentSelection: GlobalInstrumentSelectionSnapshot = {
  program: 25,
  flavor: 'gm',
  instrumentOverride: false,
  source: 'default',
  scoreId: null,
};

const GUITAR_AUDIO_OWNER = 'guitar-sound-engine';
const DEFAULT_SAMPLE_RATE = 44_100;
const DEFAULT_NOTE_DURATION = 2.4;
const CHORD_NOTE_DURATION = 2.1;
const STRUM_STEP_SECONDS = 0.042;
const PCM_CACHE_MAX_BYTES = 16 * 1024 * 1024;
const UKULELE_PROGRAMS = new Set([0, 24, 25]);
const INTERNAL_SESSION = Symbol('internal-guitar-audio-session');

export interface GuitarAudioSession {
  readonly active: boolean;
  readonly signal?: AbortSignal;
  track(source: AudioScheduledSourceNode, cleanup?: () => void): void;
  release(): void;
}

interface SharedFocus {
  active: boolean;
  ready: boolean;
  releaseFocus: (() => void) | null;
  sessions: Set<InternalSession>;
}

interface InternalSession extends GuitarAudioSession {
  readonly [INTERNAL_SESSION]: true;
  readonly signal: AbortSignal;
  sources: Set<AudioScheduledSourceNode>;
  cleanups: Map<AudioScheduledSourceNode, () => void>;
  onLost?: () => void;
  shared: SharedFocus;
  released: boolean;
  abortController: AbortController;
}

type InstrumentSound = { bank: number; program: number; flavor: InstrumentFlavor; key: string };
type Pcm = { sampleRate: number; channels: [Float32Array, Float32Array] };
type PcmCacheEntry = { pcm: Pcm; byteLength: number };
type ActiveSource = { key: string; session: GuitarAudioSession; cleanup: () => void };

let sharedFocus: SharedFocus | null = null;
let pendingFocus: Promise<SharedFocus> | null = null;
const activeInstrumentSources = new Map<AudioScheduledSourceNode, ActiveSource>();
const pendingRendersByInstrument = new Map<string, Set<AbortController>>();
const pcmCache = new Map<string, PcmCacheEntry>();
let pcmCacheBytes = 0;

/** Reentrant lease for all guitar/studio sounds. */
export async function acquireGuitarAudioSession(onLost?: () => void): Promise<GuitarAudioSession> {
  let shared = sharedFocus;
  if (!shared?.active || !shared.ready) {
    if (!pendingFocus) {
      const candidate: SharedFocus = { active: true, ready: false, releaseFocus: null, sessions: new Set() };
      sharedFocus = candidate;
      pendingFocus = claimAudioFocus(GUITAR_AUDIO_OWNER, () => {
        candidate.active = false;
        for (const session of [...candidate.sessions]) cancelSession(session, true);
        if (sharedFocus === candidate) sharedFocus = null;
      }).then((release) => {
        if (!candidate.active || sharedFocus !== candidate) {
          release();
          throw new Error('吉他音频焦点申请已取消');
        }
        candidate.releaseFocus = release;
        candidate.ready = true;
        return candidate;
      }).finally(() => {
        if (sharedFocus === candidate && !candidate.releaseFocus) sharedFocus = null;
        pendingFocus = null;
      });
    }
    shared = await pendingFocus;
  }
  if (!shared.active) throw new Error('吉他音频焦点已失效');

  const sources = new Set<AudioScheduledSourceNode>();
  const cleanups = new Map<AudioScheduledSourceNode, () => void>();
  const abortController = new AbortController();
  const session: InternalSession = {
    [INTERNAL_SESSION]: true,
    shared,
    sources,
    cleanups,
    onLost,
    released: false,
    abortController,
    get signal() { return abortController.signal; },
    get active() { return !session.released && shared.active; },
    track(source, cleanup) {
      if (!session.active) {
        stopSource(source);
        cleanup?.();
        return;
      }
      sources.add(source);
      if (cleanup) cleanups.set(source, cleanup);
      source.addEventListener('ended', () => forgetSessionSource(session, source), { once: true });
    },
    release() { cancelSession(session); },
  };
  shared.sessions.add(session);
  return session;
}

function stopSource(source: AudioScheduledSourceNode): void {
  try { source.stop(); } catch { /* already ended or not started */ }
  try { source.disconnect(); } catch { /* already disconnected */ }
}

function forgetSessionSource(session: InternalSession, source: AudioScheduledSourceNode): void {
  session.sources.delete(source);
  const cleanup = session.cleanups.get(source);
  session.cleanups.delete(source);
  cleanup?.();
}

function forgetTrackedSource(session: GuitarAudioSession, source: AudioScheduledSourceNode): void {
  if (INTERNAL_SESSION in session) forgetSessionSource(session as InternalSession, source);
}

function cancelSession(session: InternalSession, notifyLoss = false): void {
  if (session.released) return;
  session.released = true;
  session.abortController.abort();
  for (const source of [...session.sources]) {
    stopSource(source);
    forgetSessionSource(session, source);
  }
  session.sources.clear();
  session.shared.sessions.delete(session);
  if (notifyLoss) {
    try { session.onLost?.(); } catch { /* client callbacks cannot retain focus */ }
  }
  if (session.shared.sessions.size === 0 && session.shared.active) {
    session.shared.active = false;
    session.shared.releaseFocus?.();
    if (sharedFocus === session.shared) sharedFocus = null;
  }
}

export function getGlobalProgram(): number {
  return currentProgram;
}

export function getGlobalInstrumentSelection(): GlobalInstrumentSelectionSnapshot {
  return { ...instrumentSelection };
}

function normalizedProgram(program: number): number {
  if (!Number.isFinite(program)) return currentProgram;
  return Math.max(0, Math.min(128, Math.round(program)));
}

function resolveFlavor(program: number, flavor: InstrumentFlavor | undefined): InstrumentFlavor {
  if (program === 128) return 'gm';
  return flavor === 'ukulele' && UKULELE_PROGRAMS.has(program) ? 'ukulele' : 'gm';
}

function soundIdentity(program: number, flavor: InstrumentFlavor): InstrumentSound {
  const bank = program === 128 ? 128 : 0;
  const soundfontProgram = program === 128 ? 0 : program;
  const resolvedFlavor = resolveFlavor(program, flavor);
  return {
    bank,
    program: soundfontProgram,
    flavor: resolvedFlavor,
    key: `${resolvedFlavor}:${bank}:${soundfontProgram}`,
  };
}

function cancelInstrumentPlayback(key: string): void {
  for (const controller of pendingRendersByInstrument.get(key) ?? []) controller.abort();
  pendingRendersByInstrument.delete(key);
  for (const [source, active] of activeInstrumentSources) {
    if (active.key !== key) continue;
    stopSource(source);
    forgetTrackedSource(active.session, source);
    active.cleanup();
  }
}

export function setGlobalProgram(program: number, options: GlobalInstrumentSelectionOptions = {}): void {
  const nextProgram = normalizedProgram(program);
  const nextFlavor = resolveFlavor(nextProgram, options.flavor ?? 'gm');
  const nextSelection: GlobalInstrumentSelectionSnapshot = {
    program: nextProgram,
    flavor: nextFlavor,
    instrumentOverride: options.instrumentOverride ?? false,
    source: options.source ?? 'user',
    scoreId: options.scoreId ?? null,
  };
  const previousSelection = instrumentSelection;
  const instrumentChanged = previousSelection.program !== nextSelection.program || previousSelection.flavor !== nextSelection.flavor;
  const metadataChanged = previousSelection.instrumentOverride !== nextSelection.instrumentOverride ||
    previousSelection.source !== nextSelection.source || previousSelection.scoreId !== nextSelection.scoreId;
  if (!instrumentChanged && !metadataChanged) return;

  if (instrumentChanged) {
    cancelInstrumentPlayback(soundIdentity(previousSelection.program, previousSelection.flavor).key);
  }
  currentProgram = nextProgram;
  instrumentSelection = nextSelection;

  const shouldBroadcast = options.broadcast ?? (nextSelection.source !== 'score' && nextSelection.source !== 'sync');
  if (shouldBroadcast && typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('mimi:instrument-change', {
      detail: {
        ...nextSelection,
        instrument: getInstrumentByProgram(nextProgram),
      },
    }));
  }
}

/** Parse an English note name such as E4 or C#3 into its MIDI note number. */
const NOTE_NAME_TO_SEMITONE: Record<string, number> = {
  C: 0, 'C#': 1, DB: 1, D: 2, 'D#': 3, EB: 3, E: 4, F: 5, 'F#': 6, GB: 6,
  G: 7, 'G#': 8, AB: 8, A: 9, 'A#': 10, BB: 10, B: 11,
};

export function parsePitchToMidi(pitchStr: string | number): number {
  if (typeof pitchStr === 'number') return pitchStr;
  if (!pitchStr || typeof pitchStr !== 'string') return 64;
  const match = pitchStr.trim().match(/^([A-Ga-g][#b]?)(-?\d+)?$/);
  if (!match) return 64;
  const noteName = match[1].toUpperCase();
  const octave = match[2] !== undefined ? parseInt(match[2], 10) : 4;
  return (octave + 1) * 12 + (NOTE_NAME_TO_SEMITONE[noteName] ?? 0);
}

/**
 * Convert a 1-based string/fret pair to MIDI. Default tuning is standard guitar
 * from the high E string down to low E.
 */
export function getNoteMidi(
  stringNum: number,
  fretNum: number,
  tuning: Array<string | number> = ['E4', 'B3', 'G3', 'D3', 'A2', 'E2'],
): number {
  const safeStrIndex = stringNum >= 1 && stringNum <= tuning.length
    ? stringNum - 1
    : Math.max(0, Math.min(tuning.length - 1, stringNum));
  const basePitch = tuning[safeStrIndex] !== undefined ? tuning[safeStrIndex] : 'E4';
  return parsePitchToMidi(basePitch) + Math.max(0, fretNum);
}

/** Lazily create and resume the Web Audio context only after an audio request. */
export function getAudioContext(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  if (!globalAudioCtx) {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
    if (AudioContextClass) globalAudioCtx = new AudioContextClass();
  }
  if (globalAudioCtx?.state === 'suspended') globalAudioCtx.resume().catch(() => {});
  return globalAudioCtx;
}

function makeAbortError(): Error {
  if (typeof DOMException !== 'undefined') return new DOMException('Aborted', 'AbortError');
  const error = new Error('Aborted');
  error.name = 'AbortError';
  return error;
}

function throwIfAborted(signal: AbortSignal): void {
  if (signal.aborted) throw makeAbortError();
}

function createPlaybackOperation(sound: InstrumentSound, session?: GuitarAudioSession) {
  const controller = new AbortController();
  const linkedSignals = new Set<AbortSignal>();
  const activeForKey = pendingRendersByInstrument.get(sound.key) ?? new Set<AbortController>();
  activeForKey.add(controller);
  pendingRendersByInstrument.set(sound.key, activeForKey);
  const onSessionAbort = () => controller.abort();
  const linkSession = (nextSession?: GuitarAudioSession) => {
    const signal = nextSession?.signal;
    if (!signal || linkedSignals.has(signal)) return;
    linkedSignals.add(signal);
    if (signal.aborted) controller.abort();
    else signal.addEventListener('abort', onSessionAbort, { once: true });
  };
  linkSession(session);
  return {
    signal: controller.signal,
    linkSession,
    dispose() {
      for (const signal of linkedSignals) signal.removeEventListener('abort', onSessionAbort);
      linkedSignals.clear();
      const pending = pendingRendersByInstrument.get(sound.key);
      pending?.delete(controller);
      if (pending?.size === 0) pendingRendersByInstrument.delete(sound.key);
    },
  };
}

function pcmCacheKey(sound: InstrumentSound, notes: readonly { midi: number; startSeconds: number; durationSeconds: number; velocity: number }[]): string {
  const fontAsset = sound.flavor === 'ukulele'
    ? '/storage/soundfonts/ukulele_fast.sf2'
    : '/soundfonts/sonivox.sf2';
  return JSON.stringify([
    fontAsset,
    sound.bank,
    sound.program,
    DEFAULT_SAMPLE_RATE,
    notes.map((note) => [note.midi, note.startSeconds, note.durationSeconds, note.velocity]),
  ]);
}

function getCachedPcm(key: string): Pcm | undefined {
  const entry = pcmCache.get(key);
  if (!entry) return undefined;
  pcmCache.delete(key);
  pcmCache.set(key, entry);
  return entry.pcm;
}

function cachePcm(key: string, pcm: Pcm): void {
  const byteLength = pcm.channels[0].byteLength + pcm.channels[1].byteLength;
  if (byteLength > PCM_CACHE_MAX_BYTES) return;
  const existing = pcmCache.get(key);
  if (existing) {
    pcmCacheBytes -= existing.byteLength;
    pcmCache.delete(key);
  }
  pcmCache.set(key, { pcm, byteLength });
  pcmCacheBytes += byteLength;
  while (pcmCacheBytes > PCM_CACHE_MAX_BYTES) {
    const oldestKey = pcmCache.keys().next().value as string | undefined;
    if (oldestKey === undefined) break;
    const oldest = pcmCache.get(oldestKey);
    pcmCache.delete(oldestKey);
    if (oldest) pcmCacheBytes -= oldest.byteLength;
  }
}

async function renderInstrumentPcm(
  sound: InstrumentSound,
  notes: readonly { midi: number; startSeconds: number; durationSeconds: number; velocity: number }[],
  signal: AbortSignal,
): Promise<Pcm> {
  const key = pcmCacheKey(sound, notes);
  const cached = getCachedPcm(key);
  if (cached) return cached;
  throwIfAborted(signal);

  const [{ loadVerifiedScoreSoundfont }, { renderSampleNotes }] = await Promise.all([
    import('./player/verifiedScoreSoundfont.ts'),
    import('./player/sampleNoteRenderer.ts'),
  ]);
  throwIfAborted(signal);
  const font = await loadVerifiedScoreSoundfont({
    bank: sound.bank,
    program: sound.program,
    flavor: sound.flavor,
    signal,
  });
  throwIfAborted(signal);
  const pcm = await renderSampleNotes({
    soundfontBytes: font.bytes,
    bank: sound.bank,
    program: sound.program,
    notes: notes.map(({ midi, startSeconds, durationSeconds, velocity }) => ({ midi, startSeconds, durationSeconds, velocity })),
    sampleRate: DEFAULT_SAMPLE_RATE,
    signal,
  });
  throwIfAborted(signal);
  cachePcm(key, pcm);
  return pcm;
}

function createAudioBuffer(ctx: AudioContext, pcm: Pcm): AudioBuffer {
  const frameCount = Math.min(pcm.channels[0].length, pcm.channels[1].length);
  const buffer = ctx.createBuffer(2, frameCount, pcm.sampleRate);
  buffer.getChannelData(0).set(pcm.channels[0].subarray(0, frameCount));
  buffer.getChannelData(1).set(pcm.channels[1].subarray(0, frameCount));
  return buffer;
}

function waitForSourceEnd(
  session: GuitarAudioSession,
  source: AudioScheduledSourceNode,
  fallbackMs: number,
  releaseSession: boolean,
): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const cleanup = () => {
      if (done) return;
      done = true;
      clearTimeout(fallback);
      source.removeEventListener('ended', onEnded);
      session.signal?.removeEventListener('abort', onAbort);
      if (releaseSession) session.release();
      resolve();
    };
    const onEnded = () => cleanup();
    const onAbort = () => cleanup();
    const fallback = setTimeout(cleanup, fallbackMs);
    source.addEventListener('ended', onEnded, { once: true });
    session.signal?.addEventListener('abort', onAbort, { once: true });
    if (!session.active || session.signal?.aborted) cleanup();
  });
}

async function playRenderedNotes(
  notes: readonly { midi: number; startSeconds: number; durationSeconds: number; velocity: number }[],
  requestedProgram: number | undefined,
  existingSession: GuitarAudioSession | undefined,
  requestedFlavor: InstrumentFlavor | undefined,
): Promise<void> {
  const program = requestedProgram === undefined ? currentProgram : normalizedProgram(requestedProgram);
  const inferredFlavor = requestedFlavor ?? (program === instrumentSelection.program ? instrumentSelection.flavor : 'gm');
  const sound = soundIdentity(program, inferredFlavor);
  let session = existingSession;
  const ownsSession = !session;
  let scheduled = false;
  const operation = createPlaybackOperation(sound, session);

  try {
    if (!session) {
      try { session = await acquireGuitarAudioSession(); }
      catch { return; }
      operation.linkSession(session);
    }
    if (!session.active || operation.signal.aborted) return;
    const ctx = getAudioContext();
    if (!ctx) return;

    const pcm = await renderInstrumentPcm(sound, notes, operation.signal);
    if (!session.active || operation.signal.aborted) return;
    const source = ctx.createBufferSource();
    source.buffer = createAudioBuffer(ctx, pcm);
    source.connect(ctx.destination);

    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;
      activeInstrumentSources.delete(source);
      try { source.disconnect(); } catch { /* already disconnected */ }
    };
    activeInstrumentSources.set(source, { key: sound.key, session, cleanup });
    session.track(source, cleanup);
    if (!session.active || operation.signal.aborted) {
      stopSource(source);
      forgetTrackedSource(session, source);
      cleanup();
      return;
    }

    try {
      source.start(ctx.currentTime);
      scheduled = true;
    } catch (error) {
      stopSource(source);
      forgetTrackedSource(session, source);
      cleanup();
      throw error;
    }
    const longestEnd = notes.reduce((max, note) => Math.max(max, note.startSeconds + note.durationSeconds), 0) + 0.5;
    await waitForSourceEnd(session, source, Math.max(500, longestEnd * 1000), ownsSession);
  } catch (error) {
    if ((error as Error)?.name !== 'AbortError') throw error;
  } finally {
    operation.dispose();
    if (ownsSession && session && (!scheduled || !session.active || operation.signal.aborted)) session.release();
  }
}

/** Play one MIDI note through the selected verified SoundFont preset. */
export async function playProgramNote(
  midiNote: number,
  overrideProgram?: number,
  duration?: number,
  existingSession?: GuitarAudioSession,
  flavor?: InstrumentFlavor,
): Promise<void> {
  if (!Number.isInteger(midiNote) || midiNote <= 0 || midiNote > 127) return;
  const program = overrideProgram === undefined ? currentProgram : normalizedProgram(overrideProgram);
  const noteDuration = duration ?? DEFAULT_NOTE_DURATION;
  await playRenderedNotes([
    { midi: midiNote, startSeconds: 0, durationSeconds: noteDuration, velocity: 96 },
  ], overrideProgram === undefined ? undefined : program, existingSession, flavor);
}

/** Play a deterministic arpeggiated chord through one real SoundFont render. */
export async function playProgramChordStrum(
  midiNotes: number[],
  direction: 'down' | 'up' = 'down',
  overrideProgram?: number,
  existingSession?: GuitarAudioSession,
  flavor?: InstrumentFlavor,
): Promise<void> {
  if (!Array.isArray(midiNotes) || midiNotes.length === 0) return;
  const ordered = direction === 'down' ? [...midiNotes] : [...midiNotes].reverse();
  const notes = ordered
    .filter((midi) => Number.isInteger(midi) && midi > 0 && midi <= 127)
    .map((midi, index) => ({
      midi,
      startSeconds: index * STRUM_STEP_SECONDS,
      durationSeconds: CHORD_NOTE_DURATION,
      velocity: 92,
    }));
  if (notes.length === 0) return;
  const program = overrideProgram === undefined ? currentProgram : normalizedProgram(overrideProgram);
  await playRenderedNotes(notes, overrideProgram === undefined ? undefined : program, existingSession, flavor);
}

/** Backwards-compatible alias used by older callers. */
export const playAcousticChordStrum = playProgramChordStrum;
