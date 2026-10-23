import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { renderSampleNotes } from "../src/lib/player/sampleNoteRenderer.ts";

const projectRoot = fileURLToPath(new URL("..", import.meta.url));
const soundfontPath = path.join(projectRoot, "public", "soundfonts", "sonivox.sf2");
const outputArgument = process.argv[2];
if (!outputArgument) {
  console.error("Usage: node tools/render-instrument-comparison.mjs <output.wav>");
  process.exit(2);
}
const outputPath = path.resolve(outputArgument);
const sampleRate = 44_100;
const gapSeconds = 0.3;

// An original C-major arpeggio with identical MIDI timing and velocity for each preset.
const phrase = [
  { midi: 60, startSeconds: 0.05, durationSeconds: 0.18, velocity: 100 },
  { midi: 64, startSeconds: 0.32, durationSeconds: 0.18, velocity: 100 },
  { midi: 67, startSeconds: 0.59, durationSeconds: 0.18, velocity: 100 },
  { midi: 72, startSeconds: 0.86, durationSeconds: 0.18, velocity: 100 },
  { midi: 67, startSeconds: 1.13, durationSeconds: 0.18, velocity: 100 },
  { midi: 64, startSeconds: 1.4, durationSeconds: 0.18, velocity: 100 },
  { midi: 60, startSeconds: 1.67, durationSeconds: 0.2, velocity: 100 },
];

const presets = [
  { program: 24, label: "GM 24 Nylon Guitar" },
  { program: 25, label: "GM 25 Steel Guitar" },
  { program: 0, label: "GM 0 Acoustic Grand Piano" },
];

const soundfontBytes = new Uint8Array(await readFile(soundfontPath));
const rendered = [];
for (const preset of presets) {
  const pcm = await renderSampleNotes({
    soundfontBytes,
    bank: 0,
    program: preset.program,
    notes: phrase,
    sampleRate,
    renderDurationSeconds: 2,
  });
  rendered.push({ ...preset, pcm });
}

const gapFrames = Math.round(sampleRate * gapSeconds);
const totalFrames = rendered.reduce((sum, entry) => sum + entry.pcm.channels[0].length, 0)
  + gapFrames * (rendered.length - 1);
const left = new Float32Array(totalFrames);
const right = new Float32Array(totalFrames);
let frameOffset = 0;
for (const entry of rendered) {
  const [sourceLeft, sourceRight] = entry.pcm.channels;
  left.set(sourceLeft, frameOffset);
  right.set(sourceRight, frameOffset);
  frameOffset += sourceLeft.length + gapFrames;
}

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, encodePcm16Wav([left, right], sampleRate));

console.log(`Offline AlphaTab/SF2 comparison written: ${outputPath}`);
console.log(`Format: stereo PCM16, ${sampleRate} Hz, ${(totalFrames / sampleRate).toFixed(3)} seconds`);
for (const entry of rendered) {
  console.log(`${entry.label}: ${(entry.pcm.channels[0].length / sampleRate).toFixed(3)} seconds`);
}

function encodePcm16Wav(channels, rate) {
  const channelCount = channels.length;
  const frames = channels[0].length;
  if (!channels.every((channel) => channel.length === frames)) {
    throw new RangeError("All WAV channels must have the same number of frames");
  }

  const bytesPerSample = 2;
  const blockAlign = channelCount * bytesPerSample;
  const dataBytes = frames * blockAlign;
  const wav = Buffer.alloc(44 + dataBytes);
  wav.write("RIFF", 0, "ascii");
  wav.writeUInt32LE(36 + dataBytes, 4);
  wav.write("WAVE", 8, "ascii");
  wav.write("fmt ", 12, "ascii");
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(channelCount, 22);
  wav.writeUInt32LE(rate, 24);
  wav.writeUInt32LE(rate * blockAlign, 28);
  wav.writeUInt16LE(blockAlign, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36, "ascii");
  wav.writeUInt32LE(dataBytes, 40);

  let offset = 44;
  for (let frame = 0; frame < frames; frame += 1) {
    for (let channel = 0; channel < channelCount; channel += 1) {
      const sample = Math.max(-1, Math.min(1, channels[channel][frame]));
      const pcm16 = sample < 0 ? Math.round(sample * 32_768) : Math.round(sample * 32_767);
      wav.writeInt16LE(pcm16, offset);
      offset += bytesPerSample;
    }
  }
  return wav;
}
