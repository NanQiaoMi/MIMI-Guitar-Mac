import assert from 'node:assert/strict';
import test from 'node:test';
import { acquireBodyScrollLock, restoreFocus } from '../src/components/ui/dialogController.ts';

function fakeBody(overflow = '', overscrollBehavior = '') {
  return { style: { overflow, overscrollBehavior } };
}

test('body scroll lock restores the previous inline styles and releases only once', () => {
  const body = fakeBody('auto', 'contain');
  const release = acquireBodyScrollLock(body);

  assert.equal(body.style.overflow, 'hidden');
  assert.equal(body.style.overscrollBehavior, 'none');

  release();
  release();
  assert.equal(body.style.overflow, 'auto');
  assert.equal(body.style.overscrollBehavior, 'contain');
});

test('nested dialogs keep the body locked until the last lease is released', () => {
  const body = fakeBody('scroll', '');
  const releaseFirst = acquireBodyScrollLock(body);
  const releaseSecond = acquireBodyScrollLock(body);

  releaseFirst();
  assert.equal(body.style.overflow, 'hidden');

  releaseSecond();
  assert.equal(body.style.overflow, 'scroll');
  assert.equal(body.style.overscrollBehavior, '');
});

test('scroll lock does not overwrite styles changed by another owner', () => {
  const body = fakeBody('auto', 'contain');
  const release = acquireBodyScrollLock(body);
  body.style.overflow = 'clip';
  body.style.overscrollBehavior = 'none';

  release();
  assert.equal(body.style.overflow, 'clip');
  assert.equal(body.style.overscrollBehavior, 'contain');
});

test('focus restoration ignores disconnected triggers and focuses connected triggers without scrolling', () => {
  let focused = null;
  const connectedTrigger = {
    isConnected: true,
    focus: (options) => { focused = options; },
  };
  const disconnectedTrigger = { isConnected: false, focus: () => assert.fail('must not focus a detached trigger') };
  const documentRef = { activeElement: connectedTrigger };

  assert.equal(restoreFocus(connectedTrigger, documentRef), true);
  assert.deepEqual(focused, { preventScroll: true });
  assert.equal(restoreFocus(disconnectedTrigger, documentRef), false);
  assert.equal(restoreFocus(null, documentRef), false);
});
