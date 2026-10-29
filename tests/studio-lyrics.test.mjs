import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import {
  applyStudioLyricsCommand,
  collectStudioLyrics,
  summarizeStudioLyrics,
  tokenizeStudioLyrics,
} from '../src/lib/studio/studioLyrics.ts';

function makeProject() {
  const project = createBlankProject('guitar');
  project.id = 'project-a';
  const firstTrack = project.tracks[0];
  const generatedTrackId = firstTrack.id;
  firstTrack.id = 'track-a';
  const secondTrack = { ...firstTrack, id: 'track-b', name: '第二音轨' };
  project.tracks.push(secondTrack);

  for (const bar of project.bars) {
    const firstTrackBeats = bar.trackBeats[generatedTrackId];
    delete bar.trackBeats[generatedTrackId];
    bar.trackBeats['track-a'] = firstTrackBeats;
    bar.trackBeats['track-b'] = firstTrackBeats.map((beat) => ({
      ...beat,
      id: `b-${beat.id}`,
      notes: beat.notes.map((note) => ({ ...note })),
    }));
  }

  const original = project.bars[0].trackBeats['track-a'][0];
  project.bars[0].trackBeats['track-a'] = [
    { ...original, id: 'sound-1', isRest: false, notes: [{ string: 1, fret: 3 }], lyrics: '旧一', chordName: 'Am' },
    { ...original, id: 'rest', isRest: true, notes: [], lyrics: '休止旧词' },
    { ...original, id: 'sound-2', isRest: false, notes: [{ string: 2, fret: 2 }], lyrics: '旧二' },
    { ...original, id: 'sound-3', isRest: false, notes: [{ string: 3, fret: 0 }], lyrics: '旧尾词' },
  ];
  project.bars[0].trackBeats['track-b'][0] = {
    ...project.bars[0].trackBeats['track-b'][0],
    isRest: false,
    notes: [{ string: 1, fret: 5 }],
    lyrics: '别改',
  };
  return project;
}

test('tokenizeStudioLyrics preserves Chinese character and English word behavior', () => {
  assert.deepEqual(tokenizeStudioLyrics(' 故事 can\'t-stop 123! '), ['故', '事', "can't", 'stop', '123']);
  assert.deepEqual(tokenizeStudioLyrics(' —，？！\n '), []);
});

test('summarizeStudioLyrics counts valid words, sounding positions, and existing text by track ID', () => {
  const project = makeProject();
  assert.deepEqual(summarizeStudioLyrics(project, 'track-a', '故事'), {
    wordCount: 2,
    availablePositions: 3,
    existingLyrics: 4,
  });
  assert.equal(collectStudioLyrics(project, 'track-a'), '旧一 休止旧词 旧二 旧尾词');
});

test('alignment clears stale trailing/rest lyrics and only changes the requested track', () => {
  const project = makeProject();
  const next = applyStudioLyricsCommand(project, 7, {
    kind: 'align', projectId: 'project-a', trackId: 'track-a', expectedRevision: 7, text: '新词',
  });

  const targetBeats = next.bars[0].trackBeats['track-a'];
  assert.deepEqual(targetBeats.map((beat) => beat.lyrics), ['新', null, '词', null]);
  assert.equal(targetBeats[0].chordName, 'Am');
  assert.deepEqual(targetBeats[0].notes, [{ string: 1, fret: 3 }]);
  assert.equal(next.bars[0].trackBeats['track-b'][0].lyrics, '别改');
  assert.equal(project.bars[0].trackBeats['track-a'][0].lyrics, '旧一');
  assert.equal(project.bars[0].trackBeats['track-a'][3].lyrics, '旧尾词');
});

test('clear removes only stored lyrics for the target track and does not mutate the source', () => {
  const project = makeProject();
  const next = applyStudioLyricsCommand(project, 3, {
    kind: 'clear', projectId: 'project-a', trackId: 'track-a', expectedRevision: 3,
  });

  assert.ok(next.bars[0].trackBeats['track-a'].every((beat) => beat.lyrics === null));
  assert.equal(next.bars[0].trackBeats['track-b'][0].lyrics, '别改');
  assert.equal(project.bars[0].trackBeats['track-a'][0].lyrics, '旧一');
});

test('rejects stale targets, empty/oversized lyrics, missing tracks, and tracks without sounding beats', () => {
  const project = makeProject();
  const command = { kind: 'align', projectId: 'project-a', trackId: 'track-a', expectedRevision: 7, text: '好' };

  assert.throws(() => applyStudioLyricsCommand(project, 8, command), /工程内容已变化/);
  assert.throws(() => applyStudioLyricsCommand(project, 7, { ...command, projectId: 'project-b' }), /工程已变化/);
  assert.throws(() => applyStudioLyricsCommand(project, 7, { ...command, trackId: 'missing' }), /音轨已不存在/);
  assert.throws(() => applyStudioLyricsCommand(project, 7, { ...command, text: ' ？！ ' }), /有效歌词/);
  assert.throws(() => applyStudioLyricsCommand(project, 7, { ...command, text: '太多歌词内容' }), /只有 3 个可用拍位/);

  const silent = makeProject();
  silent.bars.forEach((bar) => {
    bar.trackBeats['track-a'] = bar.trackBeats['track-a'].map((beat) => ({ ...beat, isRest: true, notes: [] }));
  });
  assert.throws(() => applyStudioLyricsCommand(silent, 7, command), /没有可对齐的发声音符/);
  assert.equal(project.bars[0].trackBeats['track-a'][0].lyrics, '旧一');
});
