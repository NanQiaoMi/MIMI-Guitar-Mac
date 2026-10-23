import * as alphaTab from "@coderline/alphatab";
import { inspectScoreSoundfontPreset } from "./verifiedScoreSoundfont.ts";

export interface SampleNoteEvent {
  midi: number;
  startSeconds: number;
  durationSeconds: number;
  velocity?: number;
}

export interface RenderSampleNotesOptions {
  soundfontBytes: Uint8Array;
  bank: number;
  program: number;
  notes: readonly SampleNoteEvent[];
  sampleRate?: number;
  signal?: AbortSignal;
  /** Minimum total output length; extends trailing silence and can render a rest with no notes. */
  renderDurationSeconds?: number;
}

export interface RenderedSamplePcm {
  sampleRate: number;
  /** Stereo, deinterleaved PCM channels in the order expected by AudioBuffer. */
  channels: [Float32Array, Float32Array];
}

const MIDI_CHANNEL = 0;
const MIDI_DIVISION = 960;
const MIDI_BPM = 120;
const TICKS_PER_SECOND = MIDI_DIVISION * MIDI_BPM / 60;
const DEFAULT_SAMPLE_RATE = 44_100;
const DEFAULT_VELOCITY = 96;
const RELEASE_TAIL_SECONDS = 0.25;
const MAX_SOUND_FONT_BYTES = 64 * 1024 * 1024;
const MAX_NOTE_COUNT = 16;
const MAX_NOTE_DURATION_SECONDS = 8;
const MAX_START_SECONDS = 4;
const MAX_RENDER_DURATION_SECONDS = 12;
const MAX_PCM_OVERRUN_SECONDS = 0.25;
const RENDER_CHUNK_MILLISECONDS = 100;

const noOpEvent: alphaTab.IEventEmitter = {
  on: () => () => undefined,
  off: () => undefined,
};

const noOpNumberEvent: alphaTab.IEventEmitterOfT<number> = {
  on: () => () => undefined,
  off: () => undefined,
};

/**
 * Render MIDI note events through alphaTab's public SoundFont synthesizer/exporter API.
 * This produces PCM only: the output adapter never opens or requests an audio device.
 */
export async function renderSampleNotes({
  soundfontBytes,
  bank,
  program,
  notes,
  sampleRate = DEFAULT_SAMPLE_RATE,
  signal,
  renderDurationSeconds,
}: RenderSampleNotesOptions): Promise<RenderedSamplePcm> {
  validateInputs({ soundfontBytes, bank, program, notes, sampleRate, renderDurationSeconds });
  throwIfAborted(signal);
  inspectScoreSoundfontPreset(soundfontBytes, bank, program);
  throwIfAborted(signal);

  const midi = buildMidiFile(bank, program, notes, renderDurationSeconds);
  const output = createSilentOutput(sampleRate);
  const synth = new alphaTab.synth.AlphaSynth(output, RENDER_CHUNK_MILLISECONDS);
  try {
    const options = new alphaTab.synth.AudioExportOptions();
    options.soundFonts = [soundfontBytes];
    options.sampleRate = sampleRate;
    options.useSyncPoints = false;
    options.masterVolume = 1;
    options.metronomeVolume = 0;

    const exporter = synth.exportAudio(options, midi, [], new Map());
    const chunks: Float32Array[] = [];
    let frameCount = 0;

    while (true) {
      throwIfAborted(signal);
      const chunk = exporter.render(RENDER_CHUNK_MILLISECONDS);
      if (!chunk) break;
      if (chunk.samples.length % 2 !== 0) {
        throw new Error("alphaTab returned an invalid interleaved stereo PCM chunk");
      }
      if (chunk.samples.length > 0) {
        const chunkFrames = chunk.samples.length / 2;
        const maxFrames = Math.ceil(sampleRate * (MAX_RENDER_DURATION_SECONDS + MAX_PCM_OVERRUN_SECONDS));
        if (frameCount + chunkFrames > maxFrames) {
          throw new RangeError("alphaTab exceeded the maximum PCM frame count");
        }
        chunks.push(chunk.samples);
        frameCount += chunkFrames;
      }
      if (chunk.samples.length === 0) break;

      // Let focus/session cancellation and browser input run between bounded render chunks.
      await new Promise<void>((resolve) => globalThis.setTimeout(resolve, 0));
    }

    throwIfAborted(signal);
    const left = new Float32Array(frameCount);
    const right = new Float32Array(frameCount);
    let outputFrame = 0;
    for (const chunk of chunks) {
      for (let i = 0; i < chunk.length; i += 2) {
        const leftSample = chunk[i];
        const rightSample = chunk[i + 1];
        if (!Number.isFinite(leftSample) || !Number.isFinite(rightSample)) {
          throw new Error("alphaTab returned non-finite PCM samples");
        }
        left[outputFrame] = leftSample;
        right[outputFrame] = rightSample;
        outputFrame += 1;
      }
    }

    return { sampleRate, channels: [left, right] };
  } finally {
    synth.destroy();
  }
}

function validateInputs({
  soundfontBytes,
  bank,
  program,
  notes,
  sampleRate,
  renderDurationSeconds,
}: Omit<RenderSampleNotesOptions, "signal"> & { sampleRate: number }): void {
  if (!(soundfontBytes instanceof Uint8Array) || soundfontBytes.byteLength === 0) {
    throw new TypeError("A non-empty SF2 Uint8Array is required");
  }
  if (soundfontBytes.byteLength > MAX_SOUND_FONT_BYTES) {
    throw new RangeError(`SoundFont exceeds the ${MAX_SOUND_FONT_BYTES}-byte limit`);
  }
  assertIntegerInRange("bank", bank, 0, 16_383);
  assertIntegerInRange("program", program, 0, 127);
  if (!Array.isArray(notes)) {
    throw new TypeError("notes must be an array");
  }
  if (notes.length > MAX_NOTE_COUNT) {
    throw new RangeError(`At most ${MAX_NOTE_COUNT} notes can be rendered at once`);
  }
  if (notes.length === 0 && renderDurationSeconds === undefined) {
    throw new RangeError("An empty note list requires renderDurationSeconds for a silent rest");
  }
  if (!Number.isInteger(sampleRate) || sampleRate < 8_000 || sampleRate > 96_000) {
    throw new RangeError("sampleRate must be an integer between 8000 and 96000 Hz");
  }
  if (renderDurationSeconds !== undefined &&
      (!Number.isFinite(renderDurationSeconds) || renderDurationSeconds <= 0 ||
       renderDurationSeconds > MAX_RENDER_DURATION_SECONDS)) {
    throw new RangeError(`renderDurationSeconds must be greater than 0 and at most ${MAX_RENDER_DURATION_SECONDS}`);
  }

  for (const [index, note] of notes.entries()) {
    if (!note || typeof note !== "object") {
      throw new TypeError(`notes[${index}] must be a note object`);
    }
    assertIntegerInRange(`notes[${index}].midi`, note.midi, 0, 127);
    if (!Number.isFinite(note.startSeconds) || note.startSeconds < 0 || note.startSeconds > MAX_START_SECONDS) {
      throw new RangeError(`notes[${index}].startSeconds must be between 0 and ${MAX_START_SECONDS}`);
    }
    if (!Number.isFinite(note.durationSeconds) || note.durationSeconds < 0.02 ||
        note.durationSeconds > MAX_NOTE_DURATION_SECONDS) {
      throw new RangeError(`notes[${index}].durationSeconds must be between 0.02 and ${MAX_NOTE_DURATION_SECONDS}`);
    }
    if (note.velocity !== undefined) {
      assertIntegerInRange(`notes[${index}].velocity`, note.velocity, 1, 127);
    }
  }

  const latestNoteEnd = notes.reduce(
    (latest, note) => Math.max(latest, note.startSeconds + note.durationSeconds),
    0,
  );
  const renderLength = Math.max(
    renderDurationSeconds ?? 0,
    latestNoteEnd + RELEASE_TAIL_SECONDS,
  );
  if (renderLength > MAX_RENDER_DURATION_SECONDS) {
    throw new RangeError(`Rendered audio cannot exceed ${MAX_RENDER_DURATION_SECONDS} seconds`);
  }
}

function buildMidiFile(
  bank: number,
  program: number,
  notes: readonly SampleNoteEvent[],
  renderDurationSeconds?: number,
): alphaTab.midi.MidiFile {
  const midi = new alphaTab.midi.MidiFile();
  midi.division = MIDI_DIVISION;
  const channel = bank === 128 ? 9 : MIDI_CHANNEL;

  const events: Array<{ tick: number; priority: number; event: alphaTab.midi.MidiEvent }> = [
    {
      tick: 0,
      priority: 0,
      event: new alphaTab.midi.ControlChangeEvent(
        0,
        0,
        channel,
        alphaTab.midi.ControllerType.BankSelectCoarse,
        Math.floor(bank / 128),
      ),
    },
    {
      tick: 0,
      priority: 1,
      event: new alphaTab.midi.ControlChangeEvent(
        0,
        0,
        channel,
        alphaTab.midi.ControllerType.BankSelectFine,
        bank % 128,
      ),
    },
    {
      tick: 0,
      priority: 2,
      event: new alphaTab.midi.ProgramChangeEvent(0, 0, channel, program),
    },
  ];

  let latestNoteEndTick = 0;
  for (const note of notes) {
    const startTick = Math.round(note.startSeconds * TICKS_PER_SECOND);
    const durationTicks = Math.max(1, Math.round(note.durationSeconds * TICKS_PER_SECOND));
    const endTick = startTick + durationTicks;
    latestNoteEndTick = Math.max(latestNoteEndTick, endTick);
    events.push({
      tick: startTick,
      priority: 4,
      event: new alphaTab.midi.NoteOnEvent(
        0,
        startTick,
        channel,
        note.midi,
        note.velocity ?? DEFAULT_VELOCITY,
      ),
    });
    events.push({
      tick: endTick,
      priority: 3,
      event: new alphaTab.midi.NoteOffEvent(0, endTick, channel, note.midi, 0),
    });
  }

  const requestedEndTick = Math.round((renderDurationSeconds ?? 0) * TICKS_PER_SECOND);
  const tailTicks = Math.round(RELEASE_TAIL_SECONDS * TICKS_PER_SECOND);
  const endTick = Math.max(1, requestedEndTick, latestNoteEndTick + tailTicks);
  events.push({
    tick: endTick,
    priority: 5,
    event: new alphaTab.midi.EndOfTrackEvent(0, endTick),
  });

  events.sort((a, b) => a.tick - b.tick || a.priority - b.priority);
  for (const entry of events) midi.addEvent(entry.event);
  return midi;
}

function createSilentOutput(sampleRate: number): alphaTab.synth.ISynthOutput {
  return {
    sampleRate,
    ready: noOpEvent,
    samplesPlayed: noOpNumberEvent,
    sampleRequest: noOpEvent,
    open: () => undefined,
    play: () => undefined,
    destroy: () => undefined,
    pause: () => undefined,
    addSamples: () => undefined,
    resetSamples: () => undefined,
    activate: () => undefined,
    enumerateOutputDevices: async () => [],
    setOutputDevice: async () => undefined,
    getOutputDevice: async () => null,
  };
}

function assertIntegerInRange(name: string, value: number, min: number, max: number): void {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new RangeError(`${name} must be an integer between ${min} and ${max}`);
  }
}

function throwIfAborted(signal?: AbortSignal): void {
  if (!signal?.aborted) return;
  const error = new Error("Sample rendering was aborted");
  error.name = "AbortError";
  throw error;
}
