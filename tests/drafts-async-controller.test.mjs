import assert from 'node:assert/strict';
import test from 'node:test';
import { DraftsAsyncController, loadDraftAfterBoundary } from '../src/lib/studio/draftsAsyncController.ts';

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

test('a close and reopen makes late list reads from the previous session stale', () => {
  const controller = new DraftsAsyncController();
  const firstSession = controller.openSession();
  const oldRead = controller.beginRead(firstSession);

  assert.equal(controller.closeSession(firstSession), true);
  const secondSession = controller.openSession();
  const currentRead = controller.beginRead(secondSession);

  assert.notEqual(firstSession, secondSession);
  assert.equal(controller.isReadCurrent(oldRead), false);
  assert.equal(controller.isReadCurrent(currentRead), true);
});

test('only the newest list request in an open session can publish its result', () => {
  const controller = new DraftsAsyncController();
  const session = controller.openSession();
  const firstRead = controller.beginRead(session);
  const retryRead = controller.beginRead(session);

  assert.equal(controller.isReadCurrent(firstRead), false);
  assert.equal(controller.isReadCurrent(retryRead), true);
});

test('commit operations lock close and competing actions until their exact ticket settles', () => {
  const controller = new DraftsAsyncController();
  const session = controller.openSession();
  const read = controller.beginRead(session);
  const load = controller.beginCommit('load', session, 'draft-1');

  assert.equal(controller.isReadCurrent(read), false);
  assert.equal(controller.isCommitting, true);
  assert.equal(controller.closeSession(session), false);
  assert.equal(controller.beginCommit('delete', session, 'draft-1'), null);
  assert.equal(controller.isCommitCurrent(load), true);

  assert.equal(controller.finishCommit(load), true);
  assert.equal(controller.isCommitCurrent(load), false);
  assert.equal(controller.isCommitting, false);
  assert.equal(controller.closeSession(session), true);
});

test('disposing the dialog invalidates pending read and commit completions', () => {
  const controller = new DraftsAsyncController();
  const session = controller.openSession();
  const read = controller.beginRead(session);
  const commit = controller.beginCommit('import', session);

  controller.dispose();

  assert.equal(controller.isReadCurrent(read), false);
  assert.equal(controller.isCommitCurrent(commit), false);
  assert.equal(controller.finishCommit(commit), false);
  assert.equal(controller.openSession(), null);
});

test('loading waits for the save boundary before reading and adopting a fresh snapshot', async () => {
  const boundary = deferred();
  const events = [];
  const project = { id: 'draft-1', revision: 'after-save' };

  const load = loadDraftAfterBoundary(
    () => {
      events.push('boundary-start');
      return boundary.promise.then(() => events.push('boundary-settled'));
    },
    async () => {
      events.push('read');
      return project;
    },
    () => true,
    (loadedProject) => {
      events.push(`adopt:${loadedProject.revision}`);
    },
  );

  assert.deepEqual(events, ['boundary-start']);
  boundary.resolve();
  assert.equal(await load, 'adopted');
  assert.deepEqual(events, ['boundary-start', 'boundary-settled', 'read', 'adopt:after-save']);
});

test('a failed save boundary neither reads nor adopts a draft', async () => {
  const failure = new Error('保存结算失败');
  let readCount = 0;
  let adoptCount = 0;

  await assert.rejects(
    loadDraftAfterBoundary(
      async () => { throw failure; },
      async () => {
        readCount += 1;
        return { id: 'draft-1' };
      },
      () => true,
      () => { adoptCount += 1; },
    ),
    failure,
  );

  assert.equal(readCount, 0);
  assert.equal(adoptCount, 0);
});

test('a load ticket invalidated by the save boundary skips both the fresh read and adoption', async () => {
  let current = true;
  let readCount = 0;
  let adoptCount = 0;

  const result = await loadDraftAfterBoundary(
    async () => { current = false; },
    async () => {
      readCount += 1;
      return { id: 'draft-1' };
    },
    () => current,
    () => { adoptCount += 1; },
  );

  assert.equal(result, 'stale');
  assert.equal(readCount, 0);
  assert.equal(adoptCount, 0);
});
