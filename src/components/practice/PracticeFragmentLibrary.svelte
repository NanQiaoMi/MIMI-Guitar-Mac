<script lang="ts">
  import { tick } from 'svelte';
  import { fadeMotion, registerMotionSurface, surfaceMotion } from '../../lib/ui/motion';
  import type { PracticeFragment } from '../../lib/personal/types.ts';

  type FragmentPatch = Partial<Pick<PracticeFragment, 'name' | 'note'>>;
  type FragmentDraft = Pick<PracticeFragment, 'name' | 'note'>;

  let {
    fragments = [],
    currentScoreId = null,
    currentScoreRevision = null,
    currentRevisionTrusted = false,
    canSaveReason = '请先准备有效的 A-B 区间与提速参数。',
    applyBlockedReason = () => null,
    busy = false,
    error = '',
    status = '',
    onSave,
    onUpdate,
    onDelete,
    onApply,
  }: {
    fragments?: readonly PracticeFragment[];
    currentScoreId?: string | null;
    currentScoreRevision?: string | null;
    currentRevisionTrusted?: boolean;
    /** null means the parent confirms the active A-B, tempo and bounds are saveable. */
    canSaveReason?: string | null;
    /** Return an actionable reason when this specific fragment cannot be applied. */
    applyBlockedReason?: (fragment: PracticeFragment) => string | null;
    busy?: boolean;
    error?: string;
    status?: string;
    onSave: (draft: FragmentDraft) => Promise<void>;
    onUpdate: (id: string, expectedUpdatedAt: number, patch: FragmentPatch) => Promise<void>;
    onDelete: (id: string, expectedUpdatedAt: number) => Promise<void>;
    onApply: (id: string, expectedUpdatedAt: number) => Promise<void>;
  } = $props();

  let nameDraft = $state('');
  let noteDraft = $state('');
  let editId = $state<string | null>(null);
  let editName = $state('');
  let editNote = $state('');
  let editExpectedUpdatedAt = $state(0);
  let pendingDeleteId = $state<string | null>(null);
  let editNameInput = $state<HTMLInputElement | null>(null);
  let savedFragmentsHeading = $state<HTMLHeadingElement | null>(null);
  let localBusySequence = $state<number | null>(null);
  let localError = $state('');
  let localStatus = $state('');
  let operationSequence = 0;
  let contextGeneration = 0;
  let previousScoreContext = '';

  const activeFragments = $derived(
    [...fragments].filter((fragment) => fragment.deletedAt === undefined).sort((left, right) => right.updatedAt - left.updatedAt),
  );
  const isBusy = $derived(busy || localBusySequence !== null);
  const shownError = $derived(localError || error);
  const shownStatus = $derived(localStatus || status);
  const trimmedName = $derived(nameDraft.trim());
  const createBlockedReason = $derived(canSaveReason ?? (trimmedName ? null : '请输入片段名称。'));

  function scoreContextKey(): string {
    return `${currentScoreId ?? ''}\u001f${currentScoreRevision ?? ''}`;
  }

  $effect(() => {
    const nextContext = scoreContextKey();
    if (nextContext === previousScoreContext) return;
    previousScoreContext = nextContext;
    contextGeneration++;
    operationSequence++;
    localBusySequence = null;
    nameDraft = '';
    noteDraft = '';
    editId = null;
    editName = '';
    editNote = '';
    editExpectedUpdatedAt = 0;
    pendingDeleteId = null;
    localError = '';
    localStatus = '';
  });

  $effect(() => {
    const editingId = editId;
    if (!editingId || activeFragments.some((fragment) => fragment.id === editingId)) return;
    editId = null;
    editName = '';
    editNote = '';
    editExpectedUpdatedAt = 0;
    localError = '此片段已在另一标签页删除，未保存的编辑草稿已取消。';
    localStatus = '';
  });

  function fragmentVersionMessage(fragment: PracticeFragment): string | null {
    if (!currentScoreId) return '请先打开当前曲谱，再选择或应用片段。';
    if (fragment.scoreId !== currentScoreId) return '此片段属于另一份曲谱。';
    if (!currentRevisionTrusted || !currentScoreRevision) return '当前曲谱版本尚未核验，暂不能应用。';
    if (fragment.scoreRevision !== currentScoreRevision) return '曲谱版本已变化；请在当前版本重新选区并另存，旧片段不会自动映射。';
    return null;
  }

  function applyReason(fragment: PracticeFragment): string | null {
    return fragmentVersionMessage(fragment) ?? applyBlockedReason(fragment);
  }

  function clearMessages() {
    localError = '';
    localStatus = '';
  }

  function fragmentEditTriggerId(id: string): string {
    return `practice-fragment-edit-${encodeURIComponent(id)}`;
  }

  function fragmentDeleteTriggerId(id: string): string {
    return `practice-fragment-delete-${encodeURIComponent(id)}`;
  }

  function fragmentReasonId(id: string): string {
    return `practice-fragment-reason-${encodeURIComponent(id)}`;
  }

  async function focusEditTrigger(id: string) {
    await tick();
    if (typeof document === 'undefined') return;
    const trigger = document.getElementById(fragmentEditTriggerId(id));
    if (trigger instanceof HTMLButtonElement && trigger.isConnected && !trigger.disabled) trigger.focus();
  }

  async function focusDeleteTrigger(id: string) {
    await tick();
    if (typeof document === 'undefined') return;
    const trigger = document.getElementById(fragmentDeleteTriggerId(id));
    if (trigger instanceof HTMLButtonElement && trigger.isConnected && !trigger.disabled) trigger.focus();
  }

  async function performAction(action: () => Promise<void>, successMessage: string): Promise<boolean> {
    if (isBusy) return false;
    const actionContext = scoreContextKey();
    const actionGeneration = contextGeneration;
    const actionSequence = ++operationSequence;
    clearMessages();
    localBusySequence = actionSequence;
    try {
      await action();
      if (actionContext !== scoreContextKey() || actionGeneration !== contextGeneration || actionSequence !== operationSequence) return false;
      localStatus = successMessage;
      return true;
    } catch (cause) {
      if (actionContext !== scoreContextKey() || actionGeneration !== contextGeneration || actionSequence !== operationSequence) return false;
      localError = cause instanceof Error ? cause.message : '本地操作失败，请重试。';
      return false;
    } finally {
      if (localBusySequence === actionSequence) localBusySequence = null;
    }
  }

  async function saveNew(event: SubmitEvent) {
    event.preventDefault();
    if (createBlockedReason || !trimmedName) return;
    const saved = await performAction(
      () => onSave({ name: trimmedName, note: noteDraft }),
      '练习片段已保存到本设备。',
    );
    if (saved) {
      nameDraft = '';
      noteDraft = '';
    }
  }

  function cancelCreateDraft(event?: KeyboardEvent) {
    if (event?.key !== 'Escape') return;
    event.preventDefault();
    event.stopPropagation();
    nameDraft = '';
    noteDraft = '';
    clearMessages();
    localStatus = '已取消新片段草稿。';
  }

  async function beginEdit(fragment: PracticeFragment) {
    clearMessages();
    pendingDeleteId = null;
    editId = fragment.id;
    editName = fragment.name;
    editNote = fragment.note;
    editExpectedUpdatedAt = fragment.updatedAt;
    await tick();
    if (editId === fragment.id) editNameInput?.focus();
  }

  function cancelEdit(event?: KeyboardEvent, fragmentId?: string) {
    if (event) {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
    }
    editId = null;
    editName = '';
    editNote = '';
    editExpectedUpdatedAt = 0;
    clearMessages();
    localStatus = '已取消编辑。';
    if (fragmentId) void focusEditTrigger(fragmentId);
  }

  function editHasConflict(fragment: PracticeFragment): boolean {
    return editId === fragment.id && editExpectedUpdatedAt !== fragment.updatedAt;
  }

  async function saveEdit(event: SubmitEvent, fragment: PracticeFragment) {
    event.preventDefault();
    if (isBusy || editHasConflict(fragment)) return;
    const name = editName.trim();
    if (!name) {
      localError = '片段名称不能为空。';
      return;
    }
    const patch: FragmentPatch = {};
    if (name !== fragment.name) patch.name = name;
    if (editNote !== fragment.note) patch.note = editNote;
    if (Object.keys(patch).length === 0) {
      cancelEdit(undefined, fragment.id);
      return;
    }
    const saved = await performAction(
      () => onUpdate(fragment.id, editExpectedUpdatedAt, patch),
      '片段名称和备注已更新。',
    );
    if (saved) {
      editId = null;
      editName = '';
      editNote = '';
      editExpectedUpdatedAt = 0;
      await focusEditTrigger(fragment.id);
    }
  }

  async function applyFragment(fragment: PracticeFragment) {
    const reason = applyReason(fragment);
    if (reason) {
      localError = reason;
      return;
    }
    await performAction(
      () => onApply(fragment.id, fragment.updatedAt),
      '片段已应用，播放器保持暂停。',
    );
  }

  async function confirmDelete(fragment: PracticeFragment) {
    if (pendingDeleteId !== fragment.id) {
      pendingDeleteId = fragment.id;
      clearMessages();
      return;
    }
    const deleteIndex = activeFragments.findIndex((item) => item.id === fragment.id);
    const nextFocusId = activeFragments[deleteIndex + 1]?.id ?? activeFragments[deleteIndex - 1]?.id ?? null;
    const deleted = await performAction(
      () => onDelete(fragment.id, fragment.updatedAt),
      '片段已删除。',
    );
    if (deleted) {
      pendingDeleteId = null;
      await tick();
      if (typeof document !== 'undefined') {
        const nextTrigger = nextFocusId ? document.getElementById(fragmentDeleteTriggerId(nextFocusId)) : null;
        if (nextTrigger instanceof HTMLButtonElement && nextTrigger.isConnected && !nextTrigger.disabled) {
          nextTrigger.focus();
        } else {
          savedFragmentsHeading?.focus();
        }
      }
    }
  }

  function cancelDelete(fragmentId: string) {
    pendingDeleteId = null;
    clearMessages();
    void focusDeleteTrigger(fragmentId);
  }
</script>

<section class="mt-4 rounded-xl border border-[#e8dfd2] bg-[#fbf9f4] p-3 sm:p-4" aria-labelledby="practice-fragments-heading">
  <div class="flex flex-wrap items-start justify-between gap-2">
    <div>
      <h3 id="practice-fragments-heading" class="text-sm font-semibold text-ink">命名练习片段</h3>
      <p class="mt-1 text-xs text-mid-gray">保存当前 A-B、提速参数和独立备注，之后可应用到同版本曲谱。</p>
    </div>
    <span class="text-xs text-mid-gray">本设备保存</span>
  </div>

  {#if shownError}
    <p use:registerMotionSurface class="mt-3 rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-800" role="alert" in:surfaceMotion={{ kind: 'notice' }}>{shownError}</p>
  {/if}
  {#if shownStatus}
    <p use:registerMotionSurface class="mt-2 rounded-lg border border-emerald-200 bg-emerald-50 p-2 text-sm text-emerald-900" role="status" aria-live="polite" aria-atomic="true" in:surfaceMotion={{ kind: 'notice' }}>{shownStatus}</p>
  {/if}

  <form class="mt-3 grid gap-3 rounded-lg border border-[#e8dfd2] bg-white/70 p-3" onsubmit={saveNew}>
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="block text-xs font-medium text-ink" for="practice-fragment-name">
        片段名称
        <input
          id="practice-fragment-name"
          class="mt-1 min-h-[44px] w-full min-w-0 rounded-lg border border-[#d8cebd] bg-white px-3 text-sm text-ink"
          type="text"
          maxlength="120"
          autocomplete="off"
          required
          bind:value={nameDraft}
          oninput={clearMessages}
          onkeydown={cancelCreateDraft}
          aria-describedby="practice-fragment-save-reason practice-fragment-key-help"
        />
      </label>
      <label class="block text-xs font-medium text-ink" for="practice-fragment-note">
        片段备注（可选）
        <textarea
          id="practice-fragment-note"
          class="mt-1 min-h-[44px] w-full min-w-0 resize-y rounded-lg border border-[#d8cebd] bg-white px-3 py-2 text-sm text-ink"
          rows="2"
          maxlength="5000"
          bind:value={noteDraft}
          oninput={clearMessages}
          onkeydown={cancelCreateDraft}
        ></textarea>
      </label>
    </div>
    <div class="grid gap-2 sm:flex sm:flex-wrap sm:items-center sm:justify-between">
      <p id="practice-fragment-save-reason" class="min-w-0 text-xs text-mid-gray sm:flex-1">
        {#if createBlockedReason}{createBlockedReason}{:else}当前 A-B 与提速配置会由播放器确认后保存。{/if}
      </p>
      <p id="practice-fragment-key-help" class="text-xs text-mid-gray">名称栏按 Enter 保存；Esc 清空草稿。</p>
      <button
        type="submit"
        class="btn btn-primary min-h-[44px] min-w-[44px] justify-self-start !px-4 !py-2 text-sm"
        disabled={isBusy || !!createBlockedReason || !trimmedName}
      >
        {isBusy ? '正在保存…' : '保存片段'}
      </button>
    </div>
  </form>

  <div class="mt-4">
    <h4 bind:this={savedFragmentsHeading} tabindex="-1" class="text-xs font-semibold text-ink">已保存片段</h4>
    {#if activeFragments.length === 0}
      <p class="mt-2 rounded-lg border border-dashed border-[#d8cebd] bg-white/60 p-3 text-sm text-mid-gray">还没有命名片段。设置有效 A-B 和提速参数后，可以在上面保存一份。</p>
    {:else}
      <ul class="mt-2 divide-y divide-[#e8dfd2]">
        {#each activeFragments as fragment (fragment.id)}
          {@const versionMessage = fragmentVersionMessage(fragment)}
          {@const blockedReason = applyReason(fragment)}
          {@const conflict = editHasConflict(fragment)}
          <li class="min-w-0 py-3 first:pt-1">
            {#if editId === fragment.id}
              <form use:registerMotionSurface class="grid min-w-0 gap-3 rounded-lg bg-white/70 p-3" onsubmit={(event) => saveEdit(event, fragment)} in:surfaceMotion={{ kind: 'panel' }}>
                <label class="block text-xs font-medium text-ink" for={'practice-fragment-edit-name-' + fragment.id}>
                  片段名称
                  <input
                    id={'practice-fragment-edit-name-' + fragment.id}
                    class="mt-1 min-h-[44px] w-full min-w-0 rounded-lg border border-[#d8cebd] bg-white px-3 text-sm text-ink"
                    type="text"
                    maxlength="120"
                    required
                    bind:this={editNameInput}
                    bind:value={editName}
                    oninput={clearMessages}
                    onkeydown={(event) => cancelEdit(event, fragment.id)}
                  />
                </label>
                <label class="block text-xs font-medium text-ink" for={'practice-fragment-edit-note-' + fragment.id}>
                  片段备注（不影响本次练习备注）
                  <textarea
                    id={'practice-fragment-edit-note-' + fragment.id}
                    class="mt-1 min-h-[44px] w-full min-w-0 resize-y rounded-lg border border-[#d8cebd] bg-white px-3 py-2 text-sm text-ink"
                    rows="3"
                    maxlength="5000"
                    bind:value={editNote}
                    oninput={clearMessages}
                    onkeydown={(event) => cancelEdit(event, fragment.id)}
                  ></textarea>
                </label>
                {#if conflict}
                  <p class="text-sm text-amber-900" role="status">此片段已在另一标签页更新。为避免覆盖，请取消编辑并载入最新内容。</p>
                {/if}
                <div class="flex flex-wrap gap-2">
                  <button type="submit" class="btn btn-primary min-h-[44px] min-w-[44px] !px-3 text-sm" disabled={isBusy || conflict || !editName.trim()}>{isBusy ? '正在保存…' : '保存修改'}</button>
                  <button type="button" class="btn btn-ghost min-h-[44px] min-w-[44px] !px-3 text-sm" onclick={() => cancelEdit(undefined, fragment.id)} disabled={isBusy}>取消</button>
                </div>
              </form>
            {:else}
              <div class="flex min-w-0 flex-wrap items-start justify-between gap-2">
                <div class="min-w-0 flex-1">
                  <p class="break-words text-sm font-semibold text-ink">{fragment.name}</p>
                  <p class="mt-1 break-words text-xs text-mid-gray">A-B [{fragment.range.startTick}, {fragment.range.endTick}) · {fragment.speed.startBpm} → {fragment.speed.targetBpm} BPM，每级 +{fragment.speed.stepBpm}，{fragment.speed.lapsPerLevel} 圈</p>
                  <p class="mt-1 text-xs text-mid-gray">A 点原速 {fragment.speed.nativeAnchorBpm} BPM</p>
                  {#if fragment.note}
                    <p class="mt-2 whitespace-pre-wrap break-words text-sm text-ash">{fragment.note}</p>
                  {/if}
                  {#if versionMessage}
                    <p id={fragmentReasonId(fragment.id)} class="mt-2 rounded-lg bg-amber-50 p-2 text-xs text-amber-950" role="status">{versionMessage}</p>
                  {/if}
                  {#if !versionMessage && blockedReason}
                    <p id={fragmentReasonId(fragment.id)} class="mt-2 text-xs text-mid-gray" role="status">{blockedReason}</p>
                  {/if}
                </div>
                <div class="flex w-full flex-wrap gap-2 sm:w-auto sm:justify-end">
                  <button type="button" class="btn btn-primary min-h-[44px] min-w-[44px] flex-1 !px-3 text-sm sm:flex-none {blockedReason ? '!border-[#d8cebd] !bg-[#eee8dc] !text-mid-gray cursor-not-allowed opacity-75 shadow-none' : ''}" onclick={() => applyFragment(fragment)} disabled={isBusy || !!blockedReason} aria-label={'应用片段：' + fragment.name} aria-describedby={blockedReason ? fragmentReasonId(fragment.id) : undefined} title={blockedReason ?? (isBusy ? '正在处理操作' : '应用练习片段')}>应用</button>
                  <button type="button" id={fragmentEditTriggerId(fragment.id)} class="btn btn-ghost min-h-[44px] min-w-[44px] flex-1 !px-3 text-sm sm:flex-none" onclick={() => beginEdit(fragment)} disabled={isBusy} aria-label={'编辑片段：' + fragment.name}>改名 / 备注</button>
                  <button
                    type="button"
                    id={fragmentDeleteTriggerId(fragment.id)}
                    class="btn min-h-[44px] min-w-[44px] flex-1 !px-3 text-sm sm:flex-none {pendingDeleteId === fragment.id ? '!border-red-300 !bg-red-50 !text-red-800' : 'btn-ghost'}"
                    onclick={() => confirmDelete(fragment)}
                    disabled={isBusy}
                    aria-label={pendingDeleteId === fragment.id ? '确认删除片段：' + fragment.name : '删除片段：' + fragment.name}
                  >
                    {#if pendingDeleteId === fragment.id}<span in:fadeMotion>确认删除</span>{:else}<span>删除</span>{/if}
                  </button>
                  {#if pendingDeleteId === fragment.id}
                    <button type="button" class="btn btn-ghost min-h-[44px] min-w-[44px] flex-1 !px-3 text-sm sm:flex-none" onclick={() => cancelDelete(fragment.id)} disabled={isBusy} in:fadeMotion>取消</button>
                  {/if}
                </div>
              </div>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</section>
