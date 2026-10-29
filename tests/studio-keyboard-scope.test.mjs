import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isStudioKeyboardTargetBlocked,
  shouldHandleStudioCanvasShortcut,
} from '../src/lib/studio/studioKeyboardScope.ts';

const allowedContext = {
  enabled: true,
  targetInsideCanvas: true,
  focusInsideCanvas: true,
  targetIsBlocked: false,
  modalOpen: false,
  defaultPrevented: false,
  isComposing: false,
  key: 'ArrowLeft',
};

test('canvas shortcuts require enabled canvas focus and an unclaimed key event', () => {
  assert.equal(shouldHandleStudioCanvasShortcut(allowedContext), true);

  for (const patch of [
    { enabled: false },
    { targetInsideCanvas: false },
    { focusInsideCanvas: false },
    { targetIsBlocked: true },
    { modalOpen: true },
    { defaultPrevented: true },
    { isComposing: true },
    { key: 'Tab' },
  ]) {
    assert.equal(
      shouldHandleStudioCanvasShortcut({ ...allowedContext, ...patch }),
      false,
      `expected shortcut guard to reject ${JSON.stringify(patch)}`,
    );
  }
});

test('text fields and command controls keep their keys away from score editing', () => {
  for (const target of [
    { tagName: 'INPUT' },
    { tagName: 'textarea' },
    { tagName: 'SELECT' },
    { tagName: 'button' },
    { tagName: 'a' },
    { role: 'textbox' },
    { role: 'menuitem' },
    { role: 'combobox' },
    { isContentEditable: true },
    { hasInteractiveAncestor: true },
    { hasModalAncestor: true },
    { hasPopoverAncestor: true },
    { hasMenuAncestor: true },
    { isInert: true },
  ]) {
    assert.equal(isStudioKeyboardTargetBlocked(target), true, JSON.stringify(target));
  }

  assert.equal(isStudioKeyboardTargetBlocked({ tagName: 'DIV', role: 'region' }), false);
});
