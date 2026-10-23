<script lang="ts">
  import { tick } from 'svelte';
  import { registerMotionSurface, surfaceMotion } from '../lib/ui/motion';

  let { user = false }: { user?: boolean } = $props();

  let open = $state(false);
  let rootElement = $state<HTMLDivElement | null>(null);
  let triggerElement = $state<HTMLButtonElement | null>(null);
  let menuPosition = $state({ top: '3rem', bottom: 'auto', right: '0px', maxHeight: 'calc(100dvh - 5rem)' });

  function toggle() {
    open = !open;
  }

  function close() {
    open = false;
  }

  function handleDocumentPointerDown(event: PointerEvent) {
    const target = event.target;
    if (!(target instanceof Node) || !rootElement?.contains(target)) close();
  }

  function handleDocumentKeyDown(event: KeyboardEvent) {
    if (!open || event.key !== 'Escape') return;
    // Let an active native modal own Escape before dismissing the background menu.
    if (document.querySelector('dialog[open]')) return;
    event.preventDefault();
    close();
    triggerElement?.focus({ preventScroll: true });
  }

  function handleFocusOut(event: FocusEvent) {
    const nextTarget = event.relatedTarget;
    if (nextTarget instanceof Node && rootElement?.contains(nextTarget)) return;
    close();
  }

  function updateMenuPosition() {
    const trigger = triggerElement;
    const root = rootElement;
    const view = trigger?.ownerDocument.defaultView;
    if (!trigger || !root || !view) return;

    const computedStyle = view.getComputedStyle(trigger);
    if (
      trigger.getClientRects().length === 0 ||
      computedStyle.display === 'none' ||
      computedStyle.visibility === 'hidden'
    ) {
      close();
      return;
    }

    const rect = trigger.getBoundingClientRect();
    const rootRect = root.getBoundingClientRect();
    const safeEdge = 12;
    const gap = 8;
    const spaceBelow = Math.max(0, view.innerHeight - rect.bottom - gap - safeEdge);
    const spaceAbove = Math.max(0, rect.top - gap - safeEdge);
    const openAbove = spaceAbove > spaceBelow;
    const maxHeight = Math.max(0, Math.min(view.innerHeight - safeEdge * 2, openAbove ? spaceAbove : spaceBelow));

    menuPosition = {
      top: openAbove ? 'auto' : `${rect.bottom - rootRect.top + gap}px`,
      bottom: openAbove ? `${rootRect.bottom - rect.top + gap}px` : 'auto',
      right: `${Math.max(0, rootRect.right - rect.right)}px`,
      maxHeight: `${maxHeight}px`,
    };
  }

  $effect(() => {
    if (!open || typeof document === 'undefined') return;
    const view = triggerElement?.ownerDocument.defaultView;
    void tick().then(updateMenuPosition);
    document.addEventListener('pointerdown', handleDocumentPointerDown);
    document.addEventListener('keydown', handleDocumentKeyDown);
    view?.addEventListener('resize', updateMenuPosition);
    view?.addEventListener('scroll', updateMenuPosition, true);
    return () => {
      document.removeEventListener('pointerdown', handleDocumentPointerDown);
      document.removeEventListener('keydown', handleDocumentKeyDown);
      view?.removeEventListener('resize', updateMenuPosition);
      view?.removeEventListener('scroll', updateMenuPosition, true);
    };
  });

  async function handleLogout(e: Event) {
    e.preventDefault();
    close();
    try {
      await fetch('/api/auth/logout', { method: 'POST' });
    } catch {
      /* ignore */
    }
    location.href = '/';
  }
</script>

<div bind:this={rootElement} class="relative" onfocusout={handleFocusOut}>
  <button
    bind:this={triggerElement}
    type="button"
    onclick={toggle}
    class="btn flex h-[44px] w-[44px] min-h-[44px] min-w-[44px] items-center justify-center p-0 transition-transform active:scale-95"
    aria-label={open ? '关闭导航菜单' : '打开导航菜单'}
    aria-expanded={open}
    aria-controls="mobile-navigation-menu"
  >
    <svg class="h-4 w-4 text-ink" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <line class={`menu-icon-line menu-icon-line--top ${open ? 'menu-icon-line--open' : ''}`} x1="4" y1="8" x2="20" y2="8"></line>
      <line class={`menu-icon-line menu-icon-line--bottom ${open ? 'menu-icon-line--open' : ''}`} x1="4" y1="16" x2="20" y2="16"></line>
    </svg>
  </button>

  <div
    id="mobile-navigation-menu"
    inert={!open}
    aria-hidden={!open}
    style={`top:${menuPosition.top};bottom:${menuPosition.bottom};right:${menuPosition.right}`}
    class="pointer-events-none absolute z-[9999]"
  >
    {#if open}
    <div
      use:registerMotionSurface
      transition:surfaceMotion={{ kind: 'menu' }}
      style={`max-height:${menuPosition.maxHeight}`}
      class="pointer-events-auto w-[min(15rem,calc(100vw-2rem))] overflow-y-auto overscroll-contain rounded-3xl border hairline bg-paper/95 p-3 shadow-xl backdrop-blur-xl"
    >
      <nav aria-label="站点导航">
      <div class="space-y-1">
        <a href="/tabs" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-signal"></span>
          吉他谱库
        </a>
        <a href="/ukulele" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-signal"></span>
          尤克里里
        </a>
        <a href="/article" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-ash"></span>
          专栏文章
        </a>
        <a href="/studio" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-[#c49a45]"></span>
          ✍️ 制谱工坊
        </a>
        <a href="/searchResults" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <svg class="h-3.5 w-3.5 text-mid-gray" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <circle cx="11" cy="11" r="8"></circle>
            <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
          </svg>
          快捷检索
        </a>
        <a href="/practice" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-[#c49a45]"></span>我的练习
        </a>
        <a href="/library" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-[#c49a45]"></span>我的谱
        </a>
        <a href="/settings/data" onclick={close} class="flex min-h-[44px] items-center gap-2 rounded-pill px-3.5 py-2 text-body-sm font-medium text-ink transition hover:bg-canvas">
          <span class="h-1.5 w-1.5 rounded-full bg-[#c49a45]"></span>数据与备份
        </a>
      </div>

      <div class="my-2 border-t hairline"></div>

      <p class="px-3 py-1 text-caption font-medium uppercase tracking-wider text-mid-gray">谱面上传</p>
      <div class="grid grid-cols-2 gap-1.5">
        <a href="/upload?type=guitar" onclick={close} class="btn btn-ghost min-h-[44px] !py-1.5 text-center text-xs">传吉他谱</a>
        <a href="/upload?type=ukulele" onclick={close} class="btn btn-ghost min-h-[44px] !py-1.5 text-center text-xs">传尤克谱</a>
      </div>

      <div class="my-2 border-t hairline"></div>

      {#if user}
        <p class="px-3 py-1 text-caption font-medium uppercase tracking-wider text-mid-gray">账号中心</p>
        <div class="space-y-0.5">
          <a href="/account/0" onclick={close} class="flex min-h-[44px] items-center rounded-pill px-3.5 py-1.5 text-body-sm text-charcoal transition hover:bg-canvas">我的收藏</a>
          <a href="/account/1" onclick={close} class="flex min-h-[44px] items-center rounded-pill px-3.5 py-1.5 text-body-sm text-charcoal transition hover:bg-canvas">创作中心</a>
          <a href="/account/2" onclick={close} class="flex min-h-[44px] items-center rounded-pill px-3.5 py-1.5 text-body-sm text-charcoal transition hover:bg-canvas">浏览记录</a>
          <a href="/account/3" onclick={close} class="flex min-h-[44px] items-center rounded-pill px-3.5 py-1.5 text-body-sm text-charcoal transition hover:bg-canvas">个人资料</a>
          <button type="button" onclick={handleLogout} class="mt-1 min-h-[44px] block w-full rounded-pill px-3.5 py-1.5 text-left text-body-sm text-danger transition hover:bg-canvas">退出登录</button>
        </div>
      {:else}
        <div class="flex gap-2 pt-1">
          <button
            type="button"
            disabled
            class="btn min-h-[44px] flex-1 !py-1.5 text-center text-xs opacity-40 cursor-not-allowed bg-transparent border border-[#d6d0c4] text-[#a89b8a] pointer-events-none select-none"
            title="登录功能暂未开放"
          >
            登录
          </button>
          <button
            type="button"
            disabled
            class="btn min-h-[44px] flex-1 !py-1.5 text-center text-xs opacity-40 cursor-not-allowed bg-[#a89b8a]/20 border border-[#d6d0c4] text-[#8c7b68] pointer-events-none select-none"
            title="注册功能暂未开放"
          >
            注册
          </button>
        </div>
      {/if}
      </nav>
    </div>
    {/if}
  </div>
</div>

<style>
  .menu-icon-line {
    transform-box: view-box;
    transform-origin: center;
    transition: transform var(--motion-duration-control, 200ms) var(--motion-ease-settle, cubic-bezier(0.22, 1, 0.36, 1));
  }

  .menu-icon-line--top.menu-icon-line--open {
    transform: translateY(4px) rotate(45deg);
  }

  .menu-icon-line--bottom.menu-icon-line--open {
    transform: translateY(-4px) rotate(-45deg);
  }

  @media (prefers-reduced-motion: reduce) {
    .menu-icon-line {
      transition-duration: 0ms !important;
    }
  }
</style>
