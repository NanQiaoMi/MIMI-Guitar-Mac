export interface StudioKeyboardTargetInfo {
  tagName?: string | null;
  role?: string | null;
  isContentEditable?: boolean;
  hasInteractiveAncestor?: boolean;
  hasModalAncestor?: boolean;
  hasPopoverAncestor?: boolean;
  hasMenuAncestor?: boolean;
  isInert?: boolean;
}

export interface StudioCanvasShortcutContext {
  enabled: boolean;
  targetInsideCanvas: boolean;
  focusInsideCanvas: boolean;
  targetIsBlocked: boolean;
  modalOpen: boolean;
  defaultPrevented: boolean;
  isComposing: boolean;
  key: string;
}

const blockedTags = new Set(['a', 'button', 'input', 'option', 'select', 'summary', 'textarea']);
const blockedRoles = new Set([
  'button',
  'combobox',
  'dialog',
  'link',
  'listbox',
  'menu',
  'menubar',
  'menuitem',
  'option',
  'tab',
  'textbox',
]);

/** True for text-entry and command surfaces that must keep their own keys. */
export function isStudioKeyboardTargetBlocked(target: StudioKeyboardTargetInfo): boolean {
  const tagName = target.tagName?.toLowerCase() ?? '';
  const role = target.role?.toLowerCase() ?? '';

  return Boolean(
    blockedTags.has(tagName) ||
      blockedRoles.has(role) ||
      target.isContentEditable ||
      target.hasInteractiveAncestor ||
      target.hasModalAncestor ||
      target.hasPopoverAncestor ||
      target.hasMenuAncestor ||
      target.isInert,
  );
}

/** Keep document-level listeners scoped to an explicitly focused score canvas. */
export function shouldHandleStudioCanvasShortcut(context: StudioCanvasShortcutContext): boolean {
  return Boolean(
    context.enabled &&
      context.targetInsideCanvas &&
      context.focusInsideCanvas &&
      !context.targetIsBlocked &&
      !context.modalOpen &&
      !context.defaultPrevented &&
      !context.isComposing &&
      context.key !== 'Tab',
  );
}
