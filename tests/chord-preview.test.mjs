import assert from 'node:assert/strict';
import test from 'node:test';
import {
  attachChordPreviewListeners,
  chordPreviewAccessibleName,
  createChordPreviewState,
  createChordPreviewTarget,
  positionChordPopover,
  reconcileChordPreviewContext,
  resolveChordPreview,
  updateChordPreviewState,
} from '../src/lib/ui/chordPreview.ts';
function target(name, anchor = {}) {
  return createChordPreviewTarget(
    { getBoundingClientRect: () => ({}), ...anchor },
    name,
    `<svg aria-label="${name}"></svg>`,
  );
}

test('an uncollected flat chord opens a truthful, accessible unavailable preview', () => {
  const name = 'Eb';
  const preview = createChordPreviewTarget(
    { getBoundingClientRect: () => ({}) },
    name,
    null,
  );
  const state = updateChordPreviewState(createChordPreviewState(), { type: 'focus', target: preview });

  assert.equal(resolveChordPreview(state), preview, 'keyboard focus still opens a preview for an unknown diagram');
  assert.equal(preview.svg, null);
  assert.equal(preview.unavailableMessage, '暂未收录此和弦指法图');
  assert.equal(preview.accessibleName, '查看Eb和弦指法图收录情况');
  assert.equal(chordPreviewAccessibleName('G', true), '预览G和弦指法图');
  assert.equal(chordPreviewAccessibleName('Eb', false), '查看Eb和弦指法图收录情况');
});

test('hover and focus can overlap without one dismissal hiding the other source', () => {
  const anchor = {};
  const preview = target('G', anchor);
  let state = createChordPreviewState();

  state = updateChordPreviewState(state, { type: 'hover', target: preview });
  state = updateChordPreviewState(state, { type: 'focus', target: preview });
  state = updateChordPreviewState(state, { type: 'leave', anchor: preview.anchor });
  assert.equal(resolveChordPreview(state), preview, 'keyboard focus keeps the preview open after pointer leave');

  state = updateChordPreviewState(state, { type: 'blur', anchor: preview.anchor });
  assert.equal(resolveChordPreview(state), null, 'the preview closes when both focus and hover leave');
});

test('first activation pins an already visible preview; a second activation closes it', () => {
  const preview = target('C');
  let state = createChordPreviewState();

  state = updateChordPreviewState(state, { type: 'focus', target: preview });
  state = updateChordPreviewState(state, { type: 'activate', target: preview });
  assert.equal(resolveChordPreview(state), preview, 'focus followed by click pins instead of closing');

  state = updateChordPreviewState(state, { type: 'activate', target: preview });
  assert.equal(resolveChordPreview(state), null, 'the pinned preview closes even while its anchor remains focused');
});

test('view and visible-item changes dismiss a pinned tooltip without pointer input', () => {
  const preview = target('G', { isConnected: false });
  let state = updateChordPreviewState(createChordPreviewState(), { type: 'focus', target: preview });
  state = updateChordPreviewState(state, { type: 'activate', target: preview });
  const gallery = { viewMode: 'gallery', visibleItemsSignature: 'song-1:G|song-2:D' };

  const changedView = reconcileChordPreviewContext(
    state,
    gallery,
    { ...gallery, viewMode: 'compact' },
    () => false,
  );
  assert.equal(resolveChordPreview(changedView), null, 'Tab can move to the view switcher and dismiss the unmounted anchor');

  const changedItems = reconcileChordPreviewContext(
    state,
    gallery,
    { ...gallery, visibleItemsSignature: 'song-3:Am' },
    () => true,
  );
  assert.deepEqual(changedItems, createChordPreviewState(), 'a new visible set invalidates an old chord label even if its button was reused');
});

test('an unchanged gallery context keeps an available anchor and clears a disconnected one', () => {
  const connectedPreview = target('D', { isConnected: true });
  const state = updateChordPreviewState(createChordPreviewState(), { type: 'activate', target: connectedPreview });
  const gallery = { viewMode: 'gallery', visibleItemsSignature: 'song-1:D' };

  assert.equal(reconcileChordPreviewContext(state, gallery, gallery, (active) => active.anchor.isConnected !== false), state);

  const removedPreview = target('G', { isConnected: false });
  const removedState = updateChordPreviewState(createChordPreviewState(), { type: 'activate', target: removedPreview });
  assert.equal(resolveChordPreview(reconcileChordPreviewContext(
    removedState,
    gallery,
    gallery,
    (active) => active.anchor.isConnected !== false,
  )), null);
});

test('keyboard focus on another chord replaces an earlier pinned preview', () => {
  const first = target('G');
  const second = target('D');
  let state = updateChordPreviewState(createChordPreviewState(), { type: 'activate', target: first });
  state = updateChordPreviewState(state, { type: 'focus', target: second });

  assert.equal(resolveChordPreview(state), second, 'the focused trigger always describes its own preview');
});

test('clicking another chord switches the pinned preview; outside and Escape dismissal clear it', () => {
  const first = target('G');
  const second = target('Em');
  let state = createChordPreviewState();
  state = updateChordPreviewState(state, { type: 'activate', target: first });
  assert.equal(resolveChordPreview(state), first, 'a touch click opens without requiring hover or focus');
  state = updateChordPreviewState(state, { type: 'activate', target: first });
  assert.equal(resolveChordPreview(state), null, 'a second click on the same trigger closes it');

  state = updateChordPreviewState(state, { type: 'activate', target: first });

  state = updateChordPreviewState(state, { type: 'activate', target: second });
  assert.equal(resolveChordPreview(state), second);
  state = updateChordPreviewState(state, { type: 'dismiss' });
  assert.equal(resolveChordPreview(state), null);
  state = updateChordPreviewState(state, { type: 'activate', target: first });
  state = updateChordPreviewState(state, { type: 'dismiss' });
  assert.equal(resolveChordPreview(state), null);
});

test('outside click and Escape dismiss without consuming anchor/popover clicks, and listeners clean up', () => {
  const previousNode = Object.getOwnPropertyDescriptor(globalThis, 'Node');
  class FakeNode {}
  Object.defineProperty(globalThis, 'Node', { configurable: true, writable: true, value: FakeNode });

  function eventHub() {
    const listeners = new Map();
    return {
      addEventListener(type, listener) {
        const entries = listeners.get(type) ?? new Set();
        entries.add(listener);
        listeners.set(type, entries);
      },
      removeEventListener(type, listener) {
        listeners.get(type)?.delete(listener);
      },
      dispatch(type, event = {}) {
        for (const listener of [...(listeners.get(type) ?? [])]) listener(event);
      },
      count() {
        return [...listeners.values()].reduce((total, entries) => total + entries.size, 0);
      },
    };
  }

  try {
    const doc = eventHub();
    const view = eventHub();
    const anchorNode = new FakeNode();
    const popoverNode = new FakeNode();
    const preview = target('D', { contains: (node) => node === anchorNode });
    let active = preview;
    let dismissCount = 0;
    let repositionCount = 0;
    const dispose = attachChordPreviewListeners({
      getActive: () => active,
      getPopover: () => ({ contains: (node) => node === popoverNode }),
      dismiss() { dismissCount += 1; active = null; },
      reposition() { repositionCount += 1; },
    }, { document: doc, window: view });

    doc.dispatch('pointerdown', { target: anchorNode });
    doc.dispatch('pointerdown', { target: popoverNode });
    assert.equal(dismissCount, 0, 'the trigger and read-only tooltip do not count as outside clicks');

    const outsidePointerEvent = {
      target: new FakeNode(),
      defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; },
    };
    doc.dispatch('pointerdown', outsidePointerEvent);
    assert.equal(dismissCount, 1);
    assert.equal(outsidePointerEvent.defaultPrevented, false, 'outside dismissal does not consume the underlying click/navigation');
    active = preview;
    let prevented = false;
    doc.dispatch('keydown', { key: 'Escape', preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
    assert.equal(dismissCount, 2);

    active = preview;
    doc.dispatch('scroll');
    view.dispatch('resize');
    assert.equal(repositionCount, 2);
    dispose();
    assert.equal(doc.count(), 0);
    assert.equal(view.count(), 0);
    doc.dispatch('pointerdown', { target: new FakeNode() });
    assert.equal(dismissCount, 2, 'unmount removes document listeners');
  } finally {
    if (previousNode) Object.defineProperty(globalThis, 'Node', previousNode);
    else delete globalThis.Node;
  }
});

test('positioning flips below near the top and clamps both horizontal edges', () => {
  const nearTop = positionChordPopover(
    { left: 2, right: 22, top: 12, bottom: 32, width: 20, height: 20 },
    { width: 140, height: 100 },
    { width: 320, height: 640 },
  );
  assert.equal(nearTop.side, 'below');
  assert.equal(nearTop.left, 8);
  assert.equal(nearTop.top, 40, 'the below position uses measured height and an eight-pixel gap');
  assert.ok(nearTop.left + 140 <= 312);

  const nearBottom = positionChordPopover(
    { left: 296, right: 316, top: 600, bottom: 620, width: 20, height: 20 },
    { width: 140, height: 100 },
    { width: 320, height: 640 },
  );
  assert.equal(nearBottom.side, 'above');
  assert.equal(nearBottom.left, 172);
  assert.equal(nearBottom.top, 492, 'the above position uses measured height and an eight-pixel gap');
  assert.ok(nearBottom.arrowLeft > 100, 'the tail follows the anchor near the popover right edge after clamping');
  assert.ok(nearBottom.top + 100 <= 632);
});
