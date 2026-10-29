import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { renderSampleNotes } from "../src/lib/player/sampleNoteRenderer.ts";
import {
  inspectScoreSoundfontPreset,
  loadVerifiedScoreSoundfont,
} from "../src/lib/player/verifiedScoreSoundfont.ts";

const soundfontBytes = new Uint8Array(
  await readFile(fileURLToPath(new URL("../public/soundfonts/sonivox.sf2", import.meta.url))),
);

const common = {
  soundfontBytes,
  bank: 0,
  sampleRate: 44_100,
  notes: [{ midi: 64, startSeconds: 0.12, durationSeconds: 0.35, velocity: 100 }],
};

function peak(channel) {
  let value = 0;
  for (const sample of channel) value = Math.max(value, Math.abs(sample));
  return value;
}

test("AlphaTab renders real SF2 PCM at the requested GM programs", async () => {
  const nylon = await renderSampleNotes({ ...common, program: 24 });
  const steel = await renderSampleNotes({ ...common, program: 25 });
  const warmPad = await renderSampleNotes({ ...common, program: 89 });

  for (const pcm of [nylon, steel, warmPad]) {
    assert.equal(pcm.sampleRate, common.sampleRate);
    assert.equal(pcm.channels.length, 2);
    assert.ok(pcm.channels[0].length > 0);
    assert.equal(pcm.channels[0].length, pcm.channels[1].length);
    assert.ok(peak(pcm.channels[0]) > 0.001);
    assert.ok(peak(pcm.channels[1]) > 0.001);
    assert.ok([...pcm.channels[0], ...pcm.channels[1]].every(Number.isFinite));
  }

  const nylonFrames = nylon.channels[0].length;
  assert.ok(Math.abs(nylonFrames / nylon.sampleRate - 0.72) < 0.01);
  const leadingRestFrames = Math.floor(0.1 * nylon.sampleRate);
  assert.ok(nylon.channels[0].subarray(0, leadingRestFrames).every((sample) => sample === 0));

  assert.notDeepEqual(nylon.channels[0], steel.channels[0]);
  assert.notDeepEqual(nylon.channels[0], warmPad.channels[0]);
});

test("bank 128 program 0 renders the drum preset instead of melodic piano", async () => {
  const percussionNote = [{ midi: 60, startSeconds: 0, durationSeconds: 0.35, velocity: 100 }];
  const drums = await renderSampleNotes({
    soundfontBytes,
    bank: 128,
    program: 0,
    notes: percussionNote,
    sampleRate: 44_100,
  });
  const piano = await renderSampleNotes({
    soundfontBytes,
    bank: 0,
    program: 0,
    notes: percussionNote,
    sampleRate: 44_100,
  });

  assert.ok(peak(drums.channels[0]) > 0.001);
  assert.notDeepEqual(drums.channels[0], piano.channels[0]);
});

test("verified ukulele SF2 presets render through AlphaTab and expose only the requested preset", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const url = new URL(String(input), "https://local.test");
    const localFile = fileURLToPath(new URL(`../public${url.pathname}`, import.meta.url));
    return new Response(await readFile(localFile), { status: 200 });
  };

  try {
    for (const program of [0, 24, 25]) {
      const verified = await loadVerifiedScoreSoundfont({ bank: 0, program, flavor: "ukulele" });
      assert.equal(verified.bank, 0);
      assert.equal(verified.program, program);

      const target = inspectScoreSoundfontPreset(verified.bytes, 0, program);
      assert.ok(target.sampleNames.length > 0);
      for (const otherProgram of [0, 24, 25].filter((candidate) => candidate !== program)) {
        assert.throws(() => inspectScoreSoundfontPreset(verified.bytes, 0, otherProgram));
      }

      const rendered = await renderSampleNotes({
        soundfontBytes: verified.bytes,
        bank: verified.bank,
        program: verified.program,
        notes: [{ midi: 64, startSeconds: 0, durationSeconds: 0.3, velocity: 100 }],
        sampleRate: 44_100,
      });
      assert.ok(peak(rendered.channels[0]) > 0.001, `ukulele preset ${program} should render non-silent PCM`);
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("an explicit rest renders the requested length of silence", async () => {
  const rest = await renderSampleNotes({
    soundfontBytes,
    bank: 0,
    program: 24,
    notes: [],
    sampleRate: 48_000,
    renderDurationSeconds: 0.4,
  });

  assert.equal(rest.sampleRate, 48_000);
  assert.ok(Math.abs(rest.channels[0].length / rest.sampleRate - 0.4) < 0.01);
  assert.ok(rest.channels[0].every((sample) => sample === 0));
  assert.ok(rest.channels[1].every((sample) => sample === 0));
});

test("invalid MIDI and rendering boundaries fail closed", async (t) => {
  const cases = [
    ["negative bank", { ...common, bank: -1, program: 24 }, RangeError],
    ["program above MIDI range", { ...common, bank: 0, program: 128 }, RangeError],
    ["note above MIDI range", { ...common, bank: 0, program: 24, notes: [{ ...common.notes[0], midi: 128 }] }, RangeError],
    ["zero velocity", { ...common, bank: 0, program: 24, notes: [{ ...common.notes[0], velocity: 0 }] }, RangeError],
    ["short note", { ...common, bank: 0, program: 24, notes: [{ ...common.notes[0], durationSeconds: 0.01 }] }, RangeError],
    ["too many notes", { ...common, bank: 0, program: 24, notes: Array.from({ length: 17 }, () => common.notes[0]) }, RangeError],
    ["empty soundfont", { ...common, bank: 0, program: 24, soundfontBytes: new Uint8Array() }, TypeError],
    ["empty notes without rest duration", { ...common, bank: 0, program: 24, notes: [] }, RangeError],
    ["rest over duration limit", {
      ...common,
      bank: 0,
      program: 24,
      notes: [],
      renderDurationSeconds: 12.1,
    }, RangeError],
    ["note and release tail exceed duration limit", {
      ...common,
      bank: 0,
      program: 24,
      notes: [{ midi: 64, startSeconds: 4, durationSeconds: 8, velocity: 100 }],
    }, RangeError],
    ["malformed SoundFont", { ...common, bank: 0, program: 24, soundfontBytes: new Uint8Array([1, 2, 3]) }, Error],
    ["missing SoundFont preset", { ...common, bank: 1, program: 0 }, Error],
  ];

  for (const [name, options, errorType] of cases) {
    await t.test(name, async () => {
      await assert.rejects(renderSampleNotes(options), errorType);
    });
  }
});

test("an aborted render rejects with AbortError", async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    renderSampleNotes({ ...common, program: 24, signal: controller.signal }),
    { name: "AbortError" },
  );
});

test("an AbortSignal can cancel between bounded render chunks", async () => {
  const controller = new AbortController();
  const abortTimer = setTimeout(() => controller.abort(), 0);
  try {
    await assert.rejects(
      renderSampleNotes({
        ...common,
        program: 24,
        notes: [{ midi: 64, startSeconds: 0, durationSeconds: 6, velocity: 100 }],
        signal: controller.signal,
      }),
      { name: "AbortError" },
    );
  } finally {
    clearTimeout(abortTimer);
  }
});
