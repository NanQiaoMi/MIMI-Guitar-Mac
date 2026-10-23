<script lang="ts">
  import MotionDialog from '../ui/MotionDialog.svelte';
  import {
    filterStudioShortcuts,
    STUDIO_SHORTCUT_CATEGORIES,
    type StudioShortcutCategory,
  } from '../../lib/studio/studioShortcuts';

  let {
    isOpen = false,
    fallbackFocusSelector,
    onClose,
  }: {
    isOpen: boolean;
    fallbackFocusSelector?: string;
    onClose?: () => void;
  } = $props();

  let query = $state('');
  let category = $state<StudioShortcutCategory>('all');
  let filteredShortcuts = $derived(filterStudioShortcuts(query, category));

  $effect(() => {
    if (!isOpen) {
      query = '';
      category = 'all';
    }
  });
</script>

<MotionDialog
  open={isOpen}
  labelledBy="studio-shortcuts-title"
  describedBy="studio-shortcuts-description"
  {fallbackFocusSelector}
  backdropClass="items-center p-2 sm:p-4"
  panelClass="w-full max-w-2xl max-h-[calc(100dvh-2rem)] overflow-hidden rounded-3xl border border-[#e2d7c5] bg-[#fdfbf7] shadow-2xl text-[#2c2825]"
  onCloseRequest={() => onClose?.()}
>
  <section class="flex max-h-[calc(100dvh-2rem-2px)] min-h-0 flex-col">
    <header class="flex shrink-0 items-center justify-between gap-3 border-b border-[#e8dfd2] px-5 py-4 sm:px-7">
      <div class="flex min-w-0 items-center gap-2.5">
        <span class="text-xl" aria-hidden="true">⌨️</span>
        <h2 id="studio-shortcuts-title" class="text-lg font-serif font-bold text-[#966b1a]">制谱工坊快捷键速查</h2>
      </div>
      <button
        type="button"
        onclick={onClose}
        aria-label="关闭快捷键速查"
        class="inline-flex min-h-[44px] min-w-[44px] shrink-0 items-center justify-center rounded-full bg-[#ede5d8] text-sm font-bold text-[#705c42] transition-colors hover:bg-[#2c2825] hover:text-[#fbfaf7] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
      >
        ✕
      </button>
    </header>

    <div class="min-h-0 flex-1 space-y-2 overflow-y-auto overscroll-contain px-5 py-4 sm:px-7">
      <p id="studio-shortcuts-description" class="rounded-xl border border-[#e8dfd2] bg-[#f5efe6] px-3 py-2 text-xs leading-relaxed text-[#705c42]">
        谱面编辑快捷键仅在交互式乐谱画布拥有键盘焦点时生效。Tab / Shift+Tab 始终用于页面焦点导航。
      </p>
      <label class="block space-y-1.5 text-xs font-serif font-semibold text-[#705c42]" for="studio-shortcut-search">
        <span>搜索快捷键</span>
        <input
          id="studio-shortcut-search"
          type="search"
          bind:value={query}
          data-dialog-initial-focus
          placeholder="例如：休止符、推弦、Ctrl+S"
          class="min-h-[44px] w-full rounded-xl border border-[#dfd6c7] bg-white px-3 text-sm font-normal text-[#2c2825] placeholder:text-[#a89b8a] focus:border-[#c49a45] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
        />
      </label>
      <div class="flex flex-wrap gap-1.5" role="group" aria-label="快捷键类别">
        {#each STUDIO_SHORTCUT_CATEGORIES as item (item.id)}
          <button
            type="button"
            aria-pressed={category === item.id}
            onclick={() => (category = item.id)}
            class="min-h-[44px] min-w-[44px] rounded-full border px-3 text-xs font-serif font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] {category === item.id ? 'border-[#c49a45] bg-[#efe2c5] text-[#725114]' : 'border-[#dfd6c7] bg-white text-[#705c42] hover:bg-[#f5efe6]'}"
          >
            {item.label}
          </button>
        {/each}
      </div>
      <p class="text-xs text-[#8c7b68]" aria-live="polite" aria-atomic="true">
        {filteredShortcuts.length > 0 ? `显示 ${filteredShortcuts.length} 个快捷键` : '没有匹配的快捷键'}
      </p>
      {#if filteredShortcuts.length > 0}
        {#each filteredShortcuts as item (item.key)}
          <div class="flex min-h-11 flex-col justify-center gap-2 rounded-2xl border border-[#dfd6c7] bg-white p-3 shadow-2xs transition-colors hover:border-[#c49a45] sm:flex-row sm:items-center sm:justify-between">
            <kbd class="w-fit shrink-0 rounded-lg border border-[#dfd6c7] bg-[#ede5d8] px-2.5 py-1 font-mono text-xs font-bold text-[#966b1a] shadow-xs">
              {item.key}
            </kbd>
            <span class="text-left text-xs font-serif text-[#5c4a38] sm:text-right">
              {item.desc}
            </span>
          </div>
        {/each}
      {:else}
        <div class="rounded-2xl border border-dashed border-[#dfd6c7] bg-white/70 px-4 py-6 text-center">
          <p class="mb-3 text-sm text-[#705c42]">换个关键词，或清除当前筛选后再查看。</p>
          <button
            type="button"
            onclick={() => { query = ''; category = 'all'; }}
            class="min-h-[44px] rounded-full border border-[#c49a45] px-4 text-xs font-serif font-bold text-[#725114] hover:bg-[#efe2c5] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
          >
            清除筛选
          </button>
        </div>
      {/if}
    </div>

    <footer class="flex shrink-0 justify-end border-t border-[#e8dfd2] px-5 py-3 sm:px-7">
      <button
        type="button"
        onclick={onClose}
        class="inline-flex min-h-[44px] items-center justify-center rounded-full bg-[#2c2825] px-6 text-xs font-serif font-bold text-[#fbfaf7] shadow-xs transition-colors hover:bg-[#403b37] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
      >
        我知道了（Esc）
      </button>
    </footer>
  </section>
</MotionDialog>
