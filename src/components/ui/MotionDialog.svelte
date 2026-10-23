<script lang="ts">
  import { onDestroy, tick, type Snippet } from 'svelte';
  import { fadeMotion, prefersReducedMotion, registerMotionSurface, surfaceMotion } from '../../lib/ui/motion';
  import { acquireBodyScrollLock, restoreFocus } from './dialogController';

  type CloseReason = 'escape' | 'backdrop';
  type Props = {
    open: boolean;
    label?: string;
    labelledBy?: string;
    describedBy?: string;
    fallbackFocusSelector?: string;
    closeOnBackdrop?: boolean;
    align?: 'center' | 'top';
    backdropClass?: string;
    panelClass?: string;
    onCloseRequest: (reason: CloseReason) => void;
    children: Snippet;
  };

  let {
    open,
    label,
    labelledBy,
    describedBy,
    fallbackFocusSelector,
    closeOnBackdrop = true,
    align = 'center',
    backdropClass = '',
    panelClass = '',
    onCloseRequest,
    children,
  }: Props = $props();

  let dialogElement = $state<HTMLDialogElement | null>(null);
  let backdropElement = $state<HTMLDivElement | null>(null);
  let panelElement = $state<HTMLDivElement | null>(null);
  let contentVisible = $state(false);

  let releaseScrollLock: (() => void) | null = null;
  let returnFocusTarget: HTMLElement | null = null;

  function releaseDialogResources(restoreTrigger: boolean) {
    const target = returnFocusTarget;
    returnFocusTarget = null;
    try {
      releaseScrollLock?.();
    } finally {
      releaseScrollLock = null;
      if (restoreTrigger && dialogElement) {
        const documentRef = dialogElement.ownerDocument;
        if (!restoreFocus(target, documentRef) && fallbackFocusSelector) {
          let fallback: HTMLElement | null = null;
          try {
            fallback = documentRef.querySelector<HTMLElement>(fallbackFocusSelector);
          } catch {
            // A bad optional selector must not disrupt modal teardown.
          }
          if (fallback) {
            try {
              fallback.focus({ preventScroll: true });
            } catch {
              fallback.focus();
            }
          }
        }
      }
    }
  }

  function closeNativeDialog() {
    const dialog = dialogElement;
    const wasOpen = Boolean(dialog?.open);
    if (wasOpen) dialog?.close();
    releaseDialogResources(wasOpen);
  }

  function focusInitialTarget(dialog: HTMLDialogElement) {
    const initialTarget = dialog.querySelector<HTMLElement>('[data-dialog-initial-focus]');
    const target = initialTarget ?? dialog;
    try {
      target.focus({ preventScroll: true });
    } catch {
      target.focus();
    }
  }

  function setBackdropInert(inert: boolean) {
    const backdrop = backdropElement;
    if (!backdrop) return;
    backdrop.inert = inert;
    if (inert) backdrop.setAttribute('aria-hidden', 'true');
    else backdrop.removeAttribute('aria-hidden');
  }

  function requestClose(reason: CloseReason) {
    onCloseRequest(reason);
  }

  function handleCancel(event: Event) {
    // Keep the native modal in the top layer until its visual outro is done.
    event.preventDefault();
    requestClose('escape');
  }

  function handleBackdropPointerDown(event: PointerEvent) {
    if (!closeOnBackdrop || event.target !== event.currentTarget) return;
    requestClose('backdrop');
  }

  function handleOutroEnd() {
    if (!open) closeNativeDialog();
  }

  $effect(() => {
    const dialog = dialogElement;
    const backdrop = backdropElement;
    if (!dialog) return;

    if (open) {
      contentVisible = true;
      if (backdrop) setBackdropInert(false);
      if (!dialog.open) {
        const activeElement = dialog.ownerDocument.activeElement;
        returnFocusTarget = activeElement && 'focus' in activeElement
          ? activeElement as HTMLElement
          : null;
        dialog.showModal();
        releaseScrollLock = acquireBodyScrollLock(dialog.ownerDocument.body);
      }

      void tick().then(() => {
        if (open && dialog.open) focusInitialTarget(dialog);
      });
      return;
    }

    if (!dialog.open) {
      contentVisible = false;
      return;
    }

    contentVisible = false;
    if (backdrop) setBackdropInert(true);
    if (prefersReducedMotion()) closeNativeDialog();
  });

  onDestroy(() => {
    const dialog = dialogElement;
    if (dialog?.open) dialog.close();
    releaseDialogResources(false);
  });
</script>

<dialog
  bind:this={dialogElement}
  class="motion-dialog"
  aria-modal="true"
  aria-label={label}
  aria-labelledby={labelledBy}
  aria-describedby={describedBy}
  tabindex="-1"
  oncancel={handleCancel}
>
  {#if contentVisible}
    <div
      bind:this={backdropElement}
      class={`motion-dialog-backdrop ${align === 'top' ? 'motion-dialog-backdrop--top' : 'motion-dialog-backdrop--center'} ${backdropClass}`}
      use:registerMotionSurface
      transition:fadeMotion={{ kind: 'panel' }}
      onpointerdown={handleBackdropPointerDown}
      onoutroend={handleOutroEnd}
    >
      <div
        bind:this={panelElement}
        class={`motion-dialog-panel ${panelClass}`}
        use:registerMotionSurface
        transition:surfaceMotion={{ kind: 'panel' }}
      >
        {@render children()}
      </div>
    </div>
  {/if}
</dialog>

<style>
  dialog.motion-dialog {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    max-width: none;
    max-height: none;
    margin: 0;
    padding: 0;
    overflow: hidden;
    border: 0;
    background: transparent;
    color: inherit;
  }

  dialog.motion-dialog[open] {
    display: block;
  }

  dialog.motion-dialog:not([open]) {
    display: none;
  }

  dialog.motion-dialog::backdrop {
    background: transparent;
  }

  .motion-dialog-backdrop {
    position: fixed;
    inset: 0;
    display: flex;
    justify-content: center;
    width: 100%;
    height: 100%;
    overflow-x: hidden;
    overflow-y: auto;
    overscroll-behavior: contain;
  }

  .motion-dialog-backdrop--center {
    align-items: center;
  }

  .motion-dialog-backdrop--top {
    align-items: flex-start;
  }

  .motion-dialog-panel {
    min-width: 0;
  }

  .motion-dialog-backdrop--center .motion-dialog-panel {
    margin: auto;
  }

  .motion-dialog-backdrop--top .motion-dialog-panel {
    margin-inline: auto;
  }

</style>
