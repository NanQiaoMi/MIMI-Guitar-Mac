import assert from 'node:assert/strict';
import test from 'node:test';
import * as alphaTab from '@coderline/alphatab';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeIbeToJsonNode } from '../src/lib/ibe.node.ts';
import {
  alphaTabJsonToStudioProject,
  encodeStudioProjectToMimiIbe,
  exportStudioProjectFile,
  importStudioScoreBytes,
  studioProjectToAlphaTabScore,
} from '../src/lib/studio/studioScoreBridge.ts';
import { createBlankProject, normalizeStudioProject } from '../src/lib/studio/studioScoreModel.ts';

installNodeAr();

function makeSemanticFixture() {
  const project = createBlankProject('guitar');
  const track = project.tracks[0];
  project.title = '弦序回读测试';
  project.artist = '语义夹具';
  project.key = 'D';
  project.initialTempo = 108;
  track.tuning = [67, 58, 55, 49, 43, 36];
  track.capo = 0;

  const beatSpecs = [
    { duration: 8, triplet: true, notes: [{ string: 1, fret: 3 }, { string: 6, fret: 12 }], lyrics: '三连音一' },
    { duration: 8, triplet: true, notes: [{ string: 2, fret: 5 }], lyrics: '三连音二' },
    { duration: 8, triplet: true, notes: [{ string: 4, fret: 7 }], lyrics: '三连音三' },
    { duration: 4, dot: true, notes: [{ string: 5, fret: 9 }], chordName: 'A7', lyrics: '附点四分' },
    { duration: 2, notes: [], lyrics: '休止歌词' },
  ];
  project.bars[0].tempo = 108;
  project.bars[0].section = '主歌语义';
  project.bars[0].repeatStart = true;
  project.bars[0].trackBeats[track.id] = beatSpecs.map((spec, index) => ({
    id: `semantic-beat-${index}`,
    duration: spec.duration,
    isRest: spec.notes.length === 0,
    dot: spec.dot === true,
    triplet: spec.triplet === true,
    notes: spec.notes,
    chordName: spec.chordName ?? null,
    lyrics: spec.lyrics,
    brush: null,
  }));
  project.bars[1].repeatEnd = true;
  project.bars[1].repeatCount = 3;
  project.bars[1].volta = 2;
  return project;
}

function semanticSnapshot(project) {
  return {
    artist: project.artist,
    key: project.key,
    initialTempo: project.initialTempo,
    tracks: project.tracks.map((track) => ({
      name: track.name,
      program: track.program,
      tuning: track.tuning,
      capo: track.capo,
    })),
    bars: project.bars.map((bar) => ({
      timeSignatureNumerator: bar.timeSignatureNumerator,
      timeSignatureDenominator: bar.timeSignatureDenominator,
      tempo: bar.tempo ?? null,
      section: bar.section ?? null,
      repeatStart: bar.repeatStart === true,
      repeatEnd: bar.repeatEnd === true,
      repeatCount: bar.repeatCount ?? 2,
      volta: bar.volta ?? null,
      tracks: project.tracks.map((track) => (bar.trackBeats[track.id] ?? []).map((beat) => ({
        duration: beat.duration,
        isRest: beat.isRest,
        dot: beat.dot,
        triplet: beat.triplet,
        chordName: beat.chordName ?? null,
        lyrics: beat.lyrics ?? null,
        brush: beat.brush ?? null,
        notes: beat.notes.map((note) => ({
          string: note.string,
          fret: note.fret,
          pitch: track.tuning[note.string - 1] + note.fret,
        })).sort((a, b) => a.string - b.string || a.fret - b.fret),
      }))),
    })),
  };
}

function alphaTabSemanticSnapshot(score) {
  return {
    tracks: score.tracks.map((track) => track.staves.map((staff) => ({
      tuning: staff.tuning,
      bars: staff.bars.map((bar) => (bar.voices[0]?.beats ?? []).map((beat) => {
        const chord = beat.chordId == null
          ? null
          : staff.chords?.get?.(String(beat.chordId))?.name ?? staff.chords?.[String(beat.chordId)]?.name ?? null;
        return {
          duration: beat.duration,
          dots: beat.dots,
          tupletNumerator: beat.tupletNumerator,
          tupletDenominator: beat.tupletDenominator,
          isRest: beat.notes.length === 0,
          text: beat.text ?? null,
          chord,
          notes: beat.notes.map((note) => ({ string: note.string, fret: note.fret, pitch: note.realValue }))
            .sort((a, b) => a.string - b.string || a.fret - b.fret),
        };
      })),
    }))),
    masterBars: score.masterBars.map((bar) => ({
      keySignature: bar.keySignature,
      keySignatureType: bar.keySignatureType,
      timeSignatureNumerator: bar.timeSignatureNumerator,
      timeSignatureDenominator: bar.timeSignatureDenominator,
      tempo: bar.tempoAutomation?.value ?? null,
      repeatStart: bar.isRepeatStart,
      repeatEnd: bar.isRepeatEnd,
      repeatCount: bar.repeatCount,
      alternateEndings: bar.alternateEndings,
    })),
  };
}

async function captureDownloads(run) {
  const originalCreateObjectUrl = Object.getOwnPropertyDescriptor(URL, 'createObjectURL');
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const originalWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const blobs = new Map();
  const downloads = [];
  let nextUrl = 0;
  Object.defineProperty(URL, 'createObjectURL', {
    configurable: true,
    value(blob) {
      const url = `blob:studio-test-${++nextUrl}`;
      blobs.set(url, blob);
      return url;
    },
  });
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      body: { appendChild() {} },
      createElement(tag) {
        assert.equal(tag, 'a');
        return {
          href: '',
          download: '',
          click() { downloads.push({ filename: this.download, blob: blobs.get(this.href) }); },
          remove() {},
        };
      },
    },
  });
  Object.defineProperty(globalThis, 'window', { configurable: true, value: { setTimeout() { return 1; } } });
  try {
    await run(downloads);
    return downloads;
  } finally {
    if (originalCreateObjectUrl) Object.defineProperty(URL, 'createObjectURL', originalCreateObjectUrl);
    else delete URL.createObjectURL;
    if (originalDocument) Object.defineProperty(globalThis, 'document', originalDocument);
    else delete globalThis.document;
    if (originalWindow) Object.defineProperty(globalThis, 'window', originalWindow);
    else delete globalThis.window;
  }
}

test('JSON, MIMI IBE, and Guitar Pro 7 exports preserve core score semantics on readback', async () => {
  const project = makeSemanticFixture();
  const expected = semanticSnapshot(project);
  const downloads = await captureDownloads(async () => {
    await exportStudioProjectFile(project, 'json');
    await exportStudioProjectFile(project, 'ibe');
    await exportStudioProjectFile(project, 'gp');
  });
  assert.deepEqual(downloads.map((entry) => entry.filename), ['弦序回读测试.json', '弦序回读测试.ibe', '弦序回读测试.gp']);
  assert.ok(downloads.every((entry) => entry.blob instanceof Blob));

  const jsonBytes = new Uint8Array(await downloads[0].blob.arrayBuffer());
  const jsonProject = await importStudioScoreBytes(jsonBytes, 'studio.json', {
    kind: 'file', id: 'studio-json-fixture', fileName: 'studio.json', format: 'json',
  });
  assert.deepEqual(semanticSnapshot(normalizeStudioProject(jsonProject.project)), expected);

  const ibeBytes = new Uint8Array(await downloads[1].blob.arrayBuffer());
  const ibeProject = alphaTabJsonToStudioProject(decodeIbeToJsonNode(ibeBytes)).project;
  assert.deepEqual(semanticSnapshot(ibeProject), expected);

  const gpBytes = new Uint8Array(await downloads[2].blob.arrayBuffer());
  const settings = new alphaTab.Settings();
  settings.player.enablePlayer = false;
  const expectedAlphaTab = studioProjectToAlphaTabScore(project);
  const gpScore = alphaTab.importer.ScoreLoader.loadScoreFromBytes(gpBytes, settings);
  assert.deepEqual(alphaTabSemanticSnapshot(gpScore), alphaTabSemanticSnapshot(expectedAlphaTab));
  const gpProject = await importStudioScoreBytes(gpBytes, 'studio.gp', {
    kind: 'library', id: 'gp-original', fileName: 'studio.gp', format: 'gp',
  });
  assert.deepEqual(gpProject.project.bars.map((bar) => bar.repeatEnd), project.bars.map((bar) => bar.repeatEnd === true));
  assert.deepEqual(gpProject.project.tracks[0].tuning, project.tracks[0].tuning);
  assert.equal(gpProject.project.bars.length, project.bars.length);
});

function midiEndTick(score) {
  const file = new alphaTab.midi.MidiFile();
  const handler = new alphaTab.midi.AlphaSynthMidiFileHandler(file);
  new alphaTab.midi.MidiFileGenerator(score, new alphaTab.Settings(), handler).generate();
  return Math.max(...file.tracks.flatMap((track) => track.events.map((event) => event.tick)));
}

test('an ordinary four-bar project plays once after IBE encoding, without implicit repeats', async () => {
  const project = createBlankProject('guitar');
  assert.equal(project.bars.length, 4);
  const encoded = await encodeStudioProjectToMimiIbe(project);
  const score = alphaTab.model.JsonConverter.jsonToScore(JSON.stringify(decodeIbeToJsonNode(encoded)), new alphaTab.Settings());
  assert.ok(score.masterBars.every((bar) => !bar.isRepeatEnd));
  assert.equal(midiEndTick(score), 4 * 4 * 960);
});

test('real repeat endings retain their exact MIDI duration and survive official GP JSON conversion', async () => {
  const project = createBlankProject('guitar');
  project.bars[0].repeatStart = true;
  project.bars[1].repeatEnd = true;
  project.bars[1].repeatCount = 3;
  const encoded = await encodeStudioProjectToMimiIbe(project);
  const score = alphaTab.model.JsonConverter.jsonToScore(JSON.stringify(decodeIbeToJsonNode(encoded)), new alphaTab.Settings());
  assert.deepEqual(score.masterBars.map((bar) => bar.isRepeatEnd), [false, true, false, false]);
  assert.equal(midiEndTick(score), 8 * 4 * 960);
  const officialJson = JSON.parse(alphaTab.model.JsonConverter.scoreToJson(studioProjectToAlphaTabScore(project)));
  const imported = alphaTabJsonToStudioProject(officialJson).project;
  assert.deepEqual(imported.bars.map((bar) => bar.repeatEnd), [false, true, false, false]);
  assert.equal(imported.bars[1].repeatCount, 3);
});
