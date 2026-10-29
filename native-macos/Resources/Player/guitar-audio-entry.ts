import {
  acquireGuitarAudioSession,
  getNoteMidi,
  playProgramChordStrum,
  playProgramNote,
  type GuitarAudioSession,
} from '../../../src/lib/guitarSound.ts';

type FretPayload = {
  string: number;
  fret: number;
  tuning?: number[];
  capo?: number;
  transpose?: number;
  program?: number;
  flavor?: 'gm' | 'ukulele';
};

type ChordPayload = {
  notes: Array<{ string: number; fret: number } | { midi: number }>;
  tuning?: number[];
  capo?: number;
  transpose?: number;
  program?: number;
  flavor?: 'gm' | 'ukulele';
  direction?: 'up' | 'down';
};

let generation = 0;
let activeSession: GuitarAudioSession | null = null;

function stop(): void {
  generation += 1;
  const previous = activeSession;
  activeSession = null;
  previous?.release();
}

async function withSession<T>(play: (session: GuitarAudioSession, token: number) => Promise<T>): Promise<T | undefined> {
  stop();
  const token = generation;
  const session = await acquireGuitarAudioSession(() => {
    if (generation === token) {
      generation += 1;
      activeSession = null;
    }
  });
  if (token !== generation || !session.active) {
    session.release();
    return undefined;
  }
  activeSession = session;
  try {
    return await play(session, token);
  } finally {
    if (activeSession === session) {
      activeSession = null;
      session.release();
    }
  }
}

function midiForFret(input: { string: number; fret: number }, tuning: number[], capo: number, transpose: number): number {
  const effectiveFret = Math.max(0, input.fret) + (input.fret > 0 ? Math.max(0, capo) : 0);
  return getNoteMidi(input.string, effectiveFret, tuning) + transpose;
}

const scope = globalThis as typeof globalThis & {
  NativeGuitarAudio?: {
    previewFret(payload: FretPayload): Promise<void | undefined>;
    previewChord(payload: ChordPayload): Promise<void | undefined>;
    cancel(): void;
  };
};

scope.NativeGuitarAudio = Object.freeze({
  previewFret(payload: FretPayload) {
    const tuning = Array.isArray(payload.tuning) && payload.tuning.length ? payload.tuning : [64, 59, 55, 50, 45, 40];
    const midi = midiForFret(payload, tuning, Number(payload.capo) || 0, Number(payload.transpose) || 0);
    const program = Number.isInteger(payload.program) ? payload.program : 25;
    return withSession((session) => playProgramNote(midi, program, 1.2, session, payload.flavor || 'gm'));
  },
  previewChord(payload: ChordPayload) {
    const tuning = Array.isArray(payload.tuning) && payload.tuning.length ? payload.tuning : [64, 59, 55, 50, 45, 40];
    const capo = Number(payload.capo) || 0;
    const transpose = Number(payload.transpose) || 0;
    const midiNotes = (payload.notes || []).map((note) => 'midi' in note
      ? Math.max(0, Math.min(127, Math.trunc(Number(note.midi) || 0)))
      : midiForFret(note, tuning, capo, transpose)).filter((midi) => midi > 0 && midi <= 127);
    const program = Number.isInteger(payload.program) ? payload.program : 25;
    return withSession((session) => playProgramChordStrum(midiNotes, payload.direction || 'down', program, session, payload.flavor || 'gm'));
  },
  cancel: stop,
});
