import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test, { afterEach, beforeEach } from 'node:test';
import { createBlankProject } from '../src/lib/studio/studioScoreModel.ts';
import { hashBytes, mutatePersonalData, readAsset, readPersonalData } from '../src/lib/personal/repository.ts';
import { deleteStudioProject, loadStudioProject, rememberStudioProjectVersion, saveStudioProject, saveStudioProjectForPractice } from '../src/lib/personal/studioPersistence.ts';
import { readPlayableScoreAsset } from '../src/lib/personal/playableScoreAsset.ts';

const require = createRequire(import.meta.url);
const { IDBFactory } = require('fake-indexeddb');
const savedGlobals = {};

beforeEach(() => {
  savedGlobals.window = globalThis.window;
  savedGlobals.indexedDB = globalThis.indexedDB;
  savedGlobals.localStorage = globalThis.localStorage;
  globalThis.window = {};
  globalThis.indexedDB = new IDBFactory();
  globalThis.localStorage = { length: 0, key: () => null, getItem: () => null, setItem: () => {}, removeItem: () => {} };
});

afterEach(() => {
  for (const name of ['window', 'indexedDB', 'localStorage']) {
    if (savedGlobals[name] === undefined) delete globalThis[name];
    else globalThis[name] = savedGlobals[name];
  }
});

test('a stale studio tab cannot overwrite another tab or save its source asset', async () => {
  const created = createBlankProject('guitar');
  created.title = '初始工程';
  await saveStudioProject(created);
  const editorBaseline = await loadStudioProject(created.id);
  assert.ok(editorBaseline);

  await mutatePersonalData((draft) => {
    const project = draft.projects.find((item) => item.id === created.id);
    project.title = '另一个标签页的更新';
    project.updatedAt += 1;
  });

  const originalBytes = new TextEncoder().encode('original file must not be stored after conflict');
  const originalId = await hashBytes(originalBytes);
  const staleEdit = { ...editorBaseline, title: '旧标签页的覆盖' };
  await assert.rejects(
    saveStudioProject(staleEdit, { id: 'source-original', fileName: 'source.gp5', mimeType: 'application/octet-stream', bytes: originalBytes }),
    /已在其他页面更新/,
  );
  const data = await readPersonalData();
  assert.equal(data.projects.find((item) => item.id === created.id).title, '另一个标签页的更新');
  assert.equal(data.originals.some((item) => item.id === 'source-original'), false);
  assert.equal(await readAsset(originalId), null);
});

test('same-page rapid saves queue and advance the baseline after each successful commit', async () => {
  const project = createBlankProject('guitar');
  const first = { ...project, title: '第一版' };
  const second = { ...project, title: '第二版' };
  await Promise.all([saveStudioProject(first), saveStudioProject(second)]);

  const loaded = await loadStudioProject(project.id);
  assert.equal(loaded.title, '第二版');
  const third = { ...loaded, title: '第三版' };
  rememberStudioProjectVersion(loaded);
  await saveStudioProject(third);
  assert.equal((await loadStudioProject(project.id)).title, '第三版');

  const callTimeSnapshot = await loadStudioProject(project.id);
  callTimeSnapshot.title = '调用时的工程快照';
  const queuedSave = saveStudioProject(callTimeSnapshot);
  callTimeSnapshot.title = '调用后被继续编辑的内容';
  await queuedSave;
  assert.equal((await loadStudioProject(project.id)).title, '调用时的工程快照');
});

test('joining a project to practice saves a complete IBE asset and blocks orphaning deletion', async () => {
  const project = createBlankProject('guitar');
  project.title = '待练工程';
  const trackId = project.tracks[0].id;
  project.bars[0].trackBeats[trackId][0] = {
    ...project.bars[0].trackBeats[trackId][0],
    isRest: false,
    notes: [{ string: 2, fret: 7 }],
    chordName: 'G',
    lyrics: '练习',
  };
  const originalBytes = new TextEncoder().encode('source GP file remains independent');
  await saveStudioProject(project, { id: 'studio-source-original', fileName: 'source.gp5', mimeType: 'application/octet-stream', bytes: originalBytes });
  const savedProject = await loadStudioProject(project.id);
  await saveStudioProjectForPractice(savedProject);

  const afterJoin = await readPersonalData();
  const score = afterJoin.scores.find((item) => item.id === `project:${project.id}`);
  assert.ok(score);
  assert.equal(score.source, 'project');
  assert.equal(score.projectId, project.id);
  assert.equal(score.sourceId, project.id);
  assert.equal(score.revision, score.assetId);
  assert.ok(afterJoin.practiceItems.some((item) => item.scoreId === score.id));
  const playableAsset = await readAsset(score.assetId);
  assert.ok(playableAsset);
  assert.equal(await readPlayableScoreAsset(score, () => false), null);
  assert.deepEqual((await readPlayableScoreAsset(score)).bytes, new Uint8Array(playableAsset.bytes));
  const { decodeIbeToJsonNode } = await import('../src/lib/ibe.node.ts');
  const decoded = decodeIbeToJsonNode(new Uint8Array(playableAsset.bytes));
  assert.equal(decoded.title, project.title);
  assert.equal(decoded.masterbars.length, project.bars.length);
  assert.equal(decoded.tracks.length, project.tracks.length);

  const originalReference = afterJoin.originals.find((item) => item.id === 'studio-source-original');
  assert.ok(originalReference);
  assert.notEqual(originalReference.assetId, score.assetId);
  assert.deepEqual(new Uint8Array((await readAsset(originalReference.assetId)).bytes), originalBytes);

  await assert.rejects(deleteStudioProject(project.id), /原始文件和当前练习版本会继续保留/);
  const afterRejectedDelete = await readPersonalData();
  assert.ok(afterRejectedDelete.projects.some((item) => item.id === project.id));
  assert.ok(afterRejectedDelete.scores.some((item) => item.id === score.id));
  assert.ok(afterRejectedDelete.practiceItems.some((item) => item.scoreId === score.id));
  assert.ok(afterRejectedDelete.originals.some((item) => item.id === originalReference.id));
});

test('saving a newer linked project refreshes its asset revision without rewriting old resumes', async () => {
  const project = createBlankProject('guitar');
  const trackId = project.tracks[0].id;
  project.bars[0].trackBeats[trackId][0] = {
    ...project.bars[0].trackBeats[trackId][0], isRest: false, notes: [{ string: 1, fret: 3 }],
  };
  await saveStudioProjectForPractice(project);
  const firstData = await readPersonalData();
  const firstScore = firstData.scores.find((item) => item.id === `project:${project.id}`);
  assert.ok(firstScore);
  await mutatePersonalData((draft) => {
    draft.resumes.push({ scoreId: firstScore.id, scoreRevision: firstScore.revision, tick: 800, timeMs: 1000, speed: 120, capo: 0, transpose: 0, loop: null, trackIndexes: [0], metronome: false, countIn: false, updatedAt: Date.now() });
  });

  const edited = await loadStudioProject(project.id);
  edited.bars[0].trackBeats[trackId][0].notes[0].fret = 9;
  await saveStudioProject(edited);

  const finalData = await readPersonalData();
  const nextScore = finalData.scores.find((item) => item.id === firstScore.id);
  assert.ok(nextScore);
  assert.notEqual(nextScore.revision, firstScore.revision);
  assert.equal(nextScore.assetId, nextScore.revision);
  assert.equal(finalData.projects.find((item) => item.id === project.id).bars[0].trackBeats[trackId][0].notes[0].fret, 9);
  assert.equal(finalData.resumes.find((item) => item.scoreId === firstScore.id).scoreRevision, firstScore.revision);
  const nextAsset = await readAsset(nextScore.assetId);
  assert.ok(nextAsset);
  const { decodeIbeToJsonNode } = await import('../src/lib/ibe.node.ts');
  const decoded = decodeIbeToJsonNode(new Uint8Array(nextAsset.bytes));
  const roundTripProject = (await import('../src/lib/studio/studioScoreBridge.ts')).alphaTabJsonToStudioProject(decoded).project;
  assert.equal(roundTripProject.bars[0].trackBeats[roundTripProject.tracks[0].id][0].notes[0].fret, 9);
});
