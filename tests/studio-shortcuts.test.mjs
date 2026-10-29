import assert from 'node:assert/strict';
import test from 'node:test';
import {
  filterStudioShortcuts,
  STUDIO_SHORTCUT_CATEGORIES,
  STUDIO_SHORTCUTS,
} from '../src/lib/studio/studioShortcuts.ts';

test('shortcut categories divide the full reference list without losing entries', () => {
  assert.equal(STUDIO_SHORTCUT_CATEGORIES.length, 6);
  assert.equal(filterStudioShortcuts('', 'all').length, STUDIO_SHORTCUTS.length);
  assert.equal(filterStudioShortcuts('', 'technique').length, 8);
  assert.equal(filterStudioShortcuts('', 'rhythm').length, 3);
  assert.equal(filterStudioShortcuts('', 'playback').length, 1);
  assert.equal(filterStudioShortcuts('', 'project').length, 1);
});

test('shortcut search matches Chinese descriptions and technique aliases within a category', () => {
  assert.deepEqual(filterStudioShortcuts('休止符', 'rhythm').map(({ key }) => key), ['R']);
  assert.deepEqual(filterStudioShortcuts('hammer pull', 'technique').map(({ key }) => key), ['H']);
  assert.deepEqual(filterStudioShortcuts('推弦', 'edit'), []);
});

test('shortcut search ignores case, spacing, and punctuation in key combinations', () => {
  assert.deepEqual(filterStudioShortcuts(' CTRL + S ', 'project').map(({ key }) => key), ['Ctrl/Cmd + S']);
  assert.deepEqual(filterStudioShortcuts('Alt+4', 'rhythm').map(({ key }) => key), ['Alt+1…6']);
  assert.deepEqual(filterStudioShortcuts('12品', 'edit').map(({ key }) => key), ['0 ~ 9']);
});

test('undo and redo references match the implemented Ctrl/Cmd combinations', () => {
  assert.deepEqual(filterStudioShortcuts('⌘Z', 'edit').map(({ key }) => key), ['Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('Ctrl+Z', 'edit').map(({ key }) => key), ['Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('CtrlZ', 'edit').map(({ key }) => key), ['Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('⌘+Shift+Z', 'edit').map(({ key }) => key), ['Shift + Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('Shift+Cmd+Z', 'edit').map(({ key }) => key), ['Shift + Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('Command+Shift+Z', 'edit').map(({ key }) => key), ['Shift + Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('Shift+Ctrl+Z', 'edit').map(({ key }) => key), ['Shift + Ctrl/Cmd + Z']);
  assert.deepEqual(filterStudioShortcuts('Ctrl+Y', 'edit').map(({ key }) => key), ['Ctrl/Cmd + Y']);
});

test('Mac Command save shortcuts are visible and searchable', () => {
  assert.deepEqual(filterStudioShortcuts('Cmd S').map(({ key }) => key), ['Ctrl/Cmd + S']);
  assert.deepEqual(filterStudioShortcuts('CmdS').map(({ key }) => key), ['Ctrl/Cmd + S']);
  assert.deepEqual(filterStudioShortcuts('Command+S').map(({ key }) => key), ['Ctrl/Cmd + S']);
  assert.deepEqual(filterStudioShortcuts('⌘S').map(({ key }) => key), ['Ctrl/Cmd + S']);
  assert.deepEqual(filterStudioShortcuts('⌘S', 'project').map(({ key }) => key), ['Ctrl/Cmd + S']);
  assert.deepEqual(filterStudioShortcuts('Command+S', 'project').map(({ key }) => key), ['Ctrl/Cmd + S']);
});

test('an unmatched query returns an empty result for the explicit empty state', () => {
  assert.deepEqual(filterStudioShortcuts('不存在的快捷键'), []);
});
