import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as alphaTab from '@coderline/alphatab';
import { installNodeAr } from '../src/lib/ar.node.ts';
import { decodeOriginalIbeToJson } from '../src/lib/ibe.ts';
import { decodeIbeToJsonNode } from '../src/lib/ibe.node.ts';
import {
  alphaTabJsonToStudioProject,
  encodeStudioProjectToMimiIbe,
  importStudioScoreBytes,
  importStudioScoreFile,
  studioProjectToAlphaTabScore,
} from '../src/lib/studio/studioScoreBridge.ts';
import { createBlankProject, normalizeStudioProject } from '../src/lib/studio/studioScoreModel.ts';

installNodeAr();

const fixture = new URL('./fixtures/qingtian.ibe', import.meta.url);

function decodedFixture() {
  return decodeOriginalIbeToJson(new Uint8Array(readFileSync(fixture)));
}

test('legacy IBE conversion keeps editable string tracks and reports skipped instruments', () => {
  const { project, warnings, sourceFormat } = alphaTabJsonToStudioProject(decodedFixture(), {
    kind: 'library',
    id: 'fixture-qingtian',
    fileName: '晴天.ibe',
    format: 'ibe',
    title: '晴天',
  });

  assert.equal(sourceFormat, 'ibe');
  assert.equal(project.title, '晴天');
  assert.equal(project.bars.length, 53);
  assert.ok(project.tracks.length >= 1);
  assert.equal(project.source?.kind, 'library');
  assert.ok(project.bars.some((bar) => Object.values(bar.trackBeats).flat().some((beat) => beat.notes.length > 0)));
  assert.ok(warnings.some((warning) => warning.includes('原谱已保留')));
  assert.deepEqual(project.importWarnings, warnings);
});

test('plain beat text is retained as lyrics with one conversion warning per score', () => {
  const score = structuredClone(decodedFixture());
  const beats = score.tracks.flatMap((track) => track.staves ?? [])
    .flatMap((staff) => staff.bars ?? [])
    .flatMap((bar) => bar.voices?.[0]?.beats ?? []);
  assert.ok(beats.length >= 2);
  beats[0].text = 'rit.';
  beats[1].text = 'poco a poco';
  delete beats[0].lyrics;
  delete beats[1].lyrics;

  const { project, warnings } = alphaTabJsonToStudioProject(score);
  const warning = '外部谱拍文字可能是演奏标记；拍文字按歌词保留，请核对演奏标记。原谱已保留。';

  assert.equal(project.bars[0].trackBeats[project.tracks[0].id][0].lyrics, 'rit.');
  assert.equal(warnings.filter((entry) => entry === warning).length, 1);
});

test('complex GP5 imports group repeated voice warnings and bound the visible report', () => {
  const gp5 = new Uint8Array(readFileSync(new URL('./fixtures/canon.gp5', import.meta.url)));
  const settings = new alphaTab.Settings();
  settings.player.enablePlayer = false;
  const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(gp5, settings);
  const scoreJson = JSON.parse(alphaTab.model.JsonConverter.scoreToJson(score));
  const { project, warnings } = alphaTabJsonToStudioProject(scoreJson);

  assert.equal(project.bars.length, 224);
  assert.ok(warnings.length <= 100);
  assert.equal(project.importWarnings.length, warnings.length);
  assert.ok(warnings.some((warning) => /多个声部/.test(warning)));
  assert.ok(warnings.filter((warning) => /多个声部/.test(warning)).length <= project.tracks.length);
});

test('GP5 tuning arrays remain high-to-low while AlphaTab note strings map once into Studio', () => {
  const gp5 = new Uint8Array(readFileSync(new URL('./fixtures/canon.gp5', import.meta.url)));
  const settings = new alphaTab.Settings();
  settings.player.enablePlayer = false;
  const sourceScore = alphaTab.importer.ScoreLoader.loadScoreFromBytes(gp5, settings);
  const sourceStaff = sourceScore.tracks[0].staves[0];
  const sourceNote = sourceStaff.bars[8].voices[0].beats[0].notes.find((note) => note.fret === 19);

  assert.deepEqual(sourceStaff.tuning, [64, 59, 55, 50, 45, 40]);
  assert.deepEqual(
    sourceNote && { string: sourceNote.string, fret: sourceNote.fret, realValue: sourceNote.realValue },
    { string: 5, fret: 19, realValue: 78 },
  );

  const sourceJson = JSON.parse(alphaTab.model.JsonConverter.scoreToJson(sourceScore));
  const { project } = alphaTabJsonToStudioProject(sourceJson);
  assert.deepEqual(project.tracks[0].tuning, [64, 59, 55, 50, 45, 40]);
  const studioNote = project.bars[8].trackBeats[project.tracks[0].id][0].notes.find((note) => note.fret === 19);
  assert.deepEqual(studioNote && { string: studioNote.string, fret: studioNote.fret }, { string: 2, fret: 19 });

  const exportedScore = studioProjectToAlphaTabScore(project);
  const exportedNote = exportedScore.tracks[0].staves[0].bars[8].voices[0].beats[0].notes.find((note) => note.fret === 19);
  assert.deepEqual(
    exportedNote && { string: exportedNote.string, fret: exportedNote.fret, realValue: exportedNote.realValue },
    { string: 5, fret: 19, realValue: 78 },
  );
});

test('Studio file import sends real GP5 bytes through AlphaTab and retains the anchored pitch', async () => {
  const gp5 = new Uint8Array(readFileSync(new URL('./fixtures/canon.gp5', import.meta.url)));
  const imported = await importStudioScoreFile(new File([gp5], 'canon.gp5', { type: 'application/octet-stream' }));
  const note = imported.project.bars[8].trackBeats[imported.project.tracks[0].id][0].notes.find((entry) => entry.fret === 19);

  assert.equal(imported.sourceFormat, 'gp5');
  assert.deepEqual(imported.project.tracks[0].tuning, [64, 59, 55, 50, 45, 40]);
  assert.deepEqual(note && { string: note.string, fret: note.fret }, { string: 2, fret: 19 });
});

test('Studio file import reads basic MusicXML pitch, duration, and TAB string data', async () => {
  const musicXml = `<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>Basic TAB</work-title></work>
  <part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes>
      <divisions>4</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time>
      <clef number="1"><sign>TAB</sign><line>5</line></clef><staff-details number="1"><staff-lines>6</staff-lines>
        <staff-tuning line="1"><tuning-step>E</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
        <staff-tuning line="2"><tuning-step>A</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
        <staff-tuning line="3"><tuning-step>D</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
        <staff-tuning line="4"><tuning-step>G</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
        <staff-tuning line="5"><tuning-step>B</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
        <staff-tuning line="6"><tuning-step>E</tuning-step><tuning-octave>4</tuning-octave></staff-tuning>
      </staff-details>
    </attributes>
    <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>quarter</type><staff>1</staff><notations><technical><string>2</string><fret>7</fret></technical></notations></note>
    <note><rest/><duration>4</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
  </measure></part>
</score-partwise>`;
  const imported = await importStudioScoreFile(new File([musicXml], 'basic.musicxml', { type: 'application/vnd.recordare.musicxml+xml' }));
  const firstBeat = imported.project.bars[0].trackBeats[imported.project.tracks[0].id][0];
  const xmlSettings = new alphaTab.Settings();
  const xmlScore = alphaTab.importer.ScoreLoader.loadScoreFromBytes(new TextEncoder().encode(musicXml), xmlSettings);
  const xmlStaff = xmlScore.tracks[0].staves[0];
  const xmlNote = xmlStaff.bars[0].voices[0].beats[0].notes[0];

  assert.equal(imported.sourceFormat, 'musicxml');
  assert.equal(xmlNote.realValue, 66);
  assert.deepEqual(imported.project.tracks[0].tuning, [64, 59, 55, 50, 45, 40]);
  assert.equal(firstBeat.duration, 4);
  assert.deepEqual(firstBeat.notes.map(({ string, fret }) => ({ string, fret })), [{ string: 2, fret: 7 }]);
  assert.equal(imported.project.tracks[0].tuning[1] + firstBeat.notes[0].fret, xmlNote.realValue);
});

test('StudioProject renders linked standard notation and tablature through AlphaTab', () => {
  const { project } = alphaTabJsonToStudioProject(decodedFixture());
  project.key = 'F#m';
  project.tracks[0].volume = 0.4;
  project.tracks[0].pan = -0.5;
  project.tracks[0].mute = true;
  const score = studioProjectToAlphaTabScore(project);

  assert.equal(score.tracks.length, project.tracks.length);
  assert.equal(score.masterBars.length, project.bars.length);
  assert.equal(score.masterBars[0].keySignature, 3);
  assert.equal(score.masterBars[0].keySignatureType, 1);
  assert.equal(score.tracks[0].playbackInfo.volume, 6);
  assert.equal(score.tracks[0].playbackInfo.isMute, true);
  assert.deepEqual(
    score.masterBars.flatMap((bar, index) => bar.isRepeatStart ? [index] : []),
    project.bars.flatMap((bar, index) => bar.repeatStart ? [index] : []),
  );
  assert.deepEqual(
    score.masterBars.flatMap((bar, index) => bar.alternateEndings ? [[index, bar.alternateEndings]] : []),
    project.bars.flatMap((bar, index) => bar.volta ? [[index, 2 ** (bar.volta - 1)]] : []),
  );
  for (const track of score.tracks) {
    for (const staff of track.staves) {
      assert.equal(staff.showStandardNotation, true);
      assert.equal(staff.showTablature, true);
    }
  }
});

test('band presets create synchronized notation staves for every track', () => {
  const project = createBlankProject('band');
  const score = studioProjectToAlphaTabScore(project);

  assert.equal(score.tracks.length, 3);
  assert.equal(score.masterBars.length, project.bars.length);
  assert.ok(score.tracks.every((track) => track.staves.every((staff) => staff.showStandardNotation && staff.showTablature)));
});

test('exported GP7 can be read back by AlphaTab with all editable bars', () => {
  const { project } = alphaTabJsonToStudioProject(decodedFixture());
  const score = studioProjectToAlphaTabScore(project);
  const settings = new alphaTab.Settings();
  const bytes = new alphaTab.exporter.Gp7Exporter().export(score, settings);
  const roundTrip = alphaTab.importer.ScoreLoader.loadScoreFromBytes(bytes, settings);

  assert.equal(roundTrip.tracks.length, project.tracks.length);
  assert.equal(roundTrip.masterBars.length, project.bars.length);
  assert.ok(roundTrip.tracks[0].staves[0].bars.length > 0);
});

test('MIMI IBE export encodes a score AlphaTab can decode', async () => {
  const { project } = alphaTabJsonToStudioProject(decodedFixture());
  const bytes = await encodeStudioProjectToMimiIbe(project);
  const decoded = decodeIbeToJsonNode(bytes);

  assert.equal(decoded.title, project.title);
  assert.equal(decoded.masterbars.length, project.bars.length);
  assert.equal(decoded.tracks.length, project.tracks.length);
});

test('AlphaTex text round trip keeps bar count, repeats, and editable notes', async () => {
  const { project } = alphaTabJsonToStudioProject(decodedFixture());
  project.bars[0].trackBeats[project.tracks[0].id][0].lyrics = '自制 AlphaTex 歌词';
  const score = studioProjectToAlphaTabScore(project);
  const alphaTex = new alphaTab.exporter.AlphaTexExporter().exportToString(score, new alphaTab.Settings());
  const imported = await importStudioScoreBytes(new TextEncoder().encode(alphaTex), 'roundtrip.tex', {
    kind: 'file',
    id: 'roundtrip-alpha-tex',
    fileName: 'roundtrip.tex',
    format: 'tex',
  });

  assert.equal(imported.project.bars.length, project.bars.length);
  assert.ok(imported.project.bars.some((bar) => Object.values(bar.trackBeats).flat().some((beat) => beat.notes.length > 0)));
  assert.deepEqual(
    imported.project.bars.flatMap((bar, index) => bar.repeatStart ? [index] : []),
    project.bars.flatMap((bar, index) => bar.repeatStart ? [index] : []),
  );
  const lyricsSnapshot = (value) => value.tracks.map((track) => value.bars.map((bar) =>
    (bar.trackBeats[track.id] ?? []).map((beat) => beat.lyrics ?? null)));
  assert.ok(lyricsSnapshot(project).flat(2).some(Boolean));
  assert.deepEqual(lyricsSnapshot(imported.project), lyricsSnapshot(project));
});

test('native project schema migrates older drafts and rejects unknown versions', () => {
  const oldProject = createBlankProject('guitar');
  delete oldProject.schemaVersion;

  assert.equal(normalizeStudioProject(oldProject).schemaVersion, 1);
  assert.throws(
    () => normalizeStudioProject({ ...oldProject, schemaVersion: 99 }),
    /不支持工程格式版本 99/,
  );
});
