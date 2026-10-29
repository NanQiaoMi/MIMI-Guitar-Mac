<script lang="ts">
  import { onDestroy } from 'svelte';
  import { listStudioProjects, deleteStudioProject } from '../../lib/personal/studioPersistence.ts';
  import type { StudioProject } from '../../lib/studio/studioScoreModel.ts';
  import { DraftsAsyncController, loadDraftAfterBoundary, type DraftCommitTicket } from '../../lib/studio/draftsAsyncController.ts';
  import MotionDialog from '../ui/MotionDialog.svelte';

  type DraftSummary = {
    id: string;
    title: string;
    artist: string;
    updatedAt: number;
    trackCount: number;
    barCount: number;
  };

  type ActiveCommit = {
    kind: 'load' | 'import' | 'delete';
    draftId?: string;
    message: string;
  };

  let {
    isOpen = false,
    onClose,
    onLoadProject,
    beforeLoad,
    onImportFile,
    onDeleteDraft,
    fallbackFocusSelector,
    activeProjectId,
  }: {
    isOpen: boolean;
    onClose?: () => void;
    onLoadProject?: (project: StudioProject) => void | boolean | Promise<void | boolean>;
    beforeLoad?: () => Promise<void>;
    onImportFile?: (file: File) => Promise<boolean>;
    onDeleteDraft?: (id: string) => void | Promise<void>;
    fallbackFocusSelector?: string;
    activeProjectId?: string;
  } = $props();

  const operations = new DraftsAsyncController();
  let activeSession = $state<number | null>(null);
  let activeCommit = $state<ActiveCommit | null>(null);
  let drafts = $state<DraftSummary[]>([]);
  let listState = $state<'idle' | 'loading' | 'ready' | 'error'>('idle');
  let listError = $state('');
  let pendingLoadId = $state<string | null>(null);
  let rowErrors = $state<Record<string, string>>({});
  let deleteConfirmId = $state<string | null>(null);
  let selectedImportFile = $state<File | null>(null);
  let importError = $state('');
  let closeNotice = $state('');
  let importInput: HTMLInputElement | null = null;

  const dialogOpen = $derived(isOpen || activeCommit !== null);

  $effect(() => {
    if (isOpen) {
      closeNotice = '';
      if (activeSession === null) startSession();
      return;
    }

    if (activeSession !== null && activeCommit === null) {
      closeSessionFromParent(activeSession);
    }
  });

  onDestroy(() => operations.dispose());

  function startSession() {
    const session = operations.openSession();
    if (session === null) return;
    activeSession = session;
    drafts = [];
    listState = 'loading';
    listError = '';
    rowErrors = {};
    pendingLoadId = null;
    deleteConfirmId = null;
    selectedImportFile = null;
    importError = '';
    void refreshDrafts(session);
  }

  function closeSessionFromParent(session: number) {
    if (!operations.closeSession(session)) return;
    activeSession = null;
    resetTransientInput();
  }

  function resetTransientInput() {
    pendingLoadId = null;
    deleteConfirmId = null;
    selectedImportFile = null;
    importError = '';
    closeNotice = '';
    if (importInput) importInput.value = '';
  }

  function requestClose() {
    if (activeCommit !== null || operations.isCommitting) {
      closeNotice = `${activeCommit?.message ?? '草稿操作'}；完成前无法关闭。`;
      return;
    }
    if (!onClose) return;

    if (activeSession !== null && !operations.closeSession(activeSession)) {
      closeNotice = '草稿操作正在提交，完成前无法关闭。';
      return;
    }
    activeSession = null;
    resetTransientInput();
    onClose();
  }

  function errorMessage(error: unknown, fallback: string) {
    return error instanceof Error && error.message ? error.message : fallback;
  }

  function toSummary(project: StudioProject): DraftSummary {
    return {
      id: project.id,
      title: project.title || '未命名乐谱',
      artist: project.artist || '原创作者',
      updatedAt: project.updatedAt || Date.now(),
      trackCount: project.tracks?.length || 1,
      barCount: project.bars?.length || 0,
    };
  }

  async function refreshDrafts(session = activeSession) {
    if (session === null) return;
    const ticket = operations.beginRead(session);
    if (!ticket) return;

    listState = 'loading';
    listError = '';
    try {
      const projects = await listStudioProjects();
      if (!operations.isReadCurrent(ticket)) return;
      drafts = projects.map(toSummary).sort((a, b) => b.updatedAt - a.updatedAt);
      listState = 'ready';
    } catch (error) {
      if (!operations.isReadCurrent(ticket)) return;
      listState = 'error';
      listError = `读取个人草稿失败：${errorMessage(error, '未知错误')}`;
    }
  }

  function setRowError(id: string, message: string) {
    rowErrors = { ...rowErrors, [id]: message };
  }

  function clearRowError(id: string) {
    if (!(id in rowErrors)) return;
    const next = { ...rowErrors };
    delete next[id];
    rowErrors = next;
  }

  function setActiveCommit(ticket: DraftCommitTicket, message: string) {
    activeCommit = {
      kind: ticket.kind,
      ...(ticket.draftId ? { draftId: ticket.draftId } : {}),
      message,
    };
    closeNotice = '';
  }

  function finishCommit(ticket: DraftCommitTicket) {
    if (!operations.isCommitCurrent(ticket)) return false;
    const finished = operations.finishCommit(ticket);
    if (finished) {
      activeCommit = null;
      closeNotice = '';
    }
    return finished;
  }

  async function handleLoadDraft(id: string) {
    const session = activeSession;
    if (session === null || listState !== 'ready' || pendingLoadId !== null || activeCommit !== null) return;
    const commitTicket = operations.beginCommit('load', session, id);
    if (!commitTicket) return;

    pendingLoadId = id;
    deleteConfirmId = null;
    clearRowError(id);
    closeNotice = '';
    let loaded = false;
    setActiveCommit(commitTicket, '正在结算当前工程并载入草稿');

    try {
      if (!onLoadProject) throw new Error('当前页面暂时无法载入草稿。');
      const result = await loadDraftAfterBoundary(
        beforeLoad,
        async () => (await listStudioProjects()).find((entry) => entry.id === id) ?? null,
        () => operations.isCommitCurrent(commitTicket),
        onLoadProject,
      );
      loaded = result === 'adopted';
    } catch (error) {
      if (operations.isCommitCurrent(commitTicket)) {
        setRowError(id, `无法载入这份草稿：${errorMessage(error, '未知错误')}`);
      }
    } finally {
      finishCommit(commitTicket);
      if (operations.isSessionCurrent(session)) pendingLoadId = null;
    }

    if (loaded && operations.isSessionCurrent(session)) requestClose();
  }

  function requestDeleteConfirmation(id: string) {
    if (id === activeProjectId || activeCommit !== null || pendingLoadId !== null || listState !== 'ready') return;
    clearRowError(id);
    deleteConfirmId = deleteConfirmId === id ? null : id;
  }

  async function handleDeleteDraft(id: string) {
    const session = activeSession;
    if (session === null || id === activeProjectId || deleteConfirmId !== id || activeCommit !== null || pendingLoadId !== null) return;

    const ticket = operations.beginCommit('delete', session, id);
    if (!ticket) return;
    deleteConfirmId = null;
    clearRowError(id);
    setActiveCommit(ticket, '正在删除本机草稿');

    let deleted = false;
    try {
      if (onDeleteDraft) await onDeleteDraft(id);
      else await deleteStudioProject(id);
      if (!operations.isCommitCurrent(ticket)) return;
      drafts = drafts.filter((draft) => draft.id !== id);
      deleted = true;
    } catch (error) {
      if (operations.isCommitCurrent(ticket)) {
        setRowError(id, `删除草稿失败：${errorMessage(error, '未知错误')}`);
      }
    } finally {
      finishCommit(ticket);
    }

    if (deleted && operations.isSessionCurrent(session)) {
      void refreshDrafts(session);
    }
  }

  function handleImportSelection(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    selectedImportFile = file;
    importError = '';
    void handleImportFile(file);
  }

  async function handleImportFile(file: File) {
    const session = activeSession;
    if (session === null || pendingLoadId !== null || listState === 'loading' || activeCommit !== null) return;
    if (!onImportFile) {
      selectedImportFile = file;
      importError = '当前页面暂时无法导入文件。';
      return;
    }

    const ticket = operations.beginCommit('import', session);
    if (!ticket) return;
    selectedImportFile = file;
    importError = '';
    setActiveCommit(ticket, '正在解析、保存并替换当前工程');

    let imported = false;
    try {
      const succeeded = await onImportFile(file);
      if (!operations.isCommitCurrent(ticket)) return;
      if (!succeeded) {
        importError = '文件未载入；当前编辑工程已保留。请查看工坊提示后重试。';
      } else {
        imported = true;
        selectedImportFile = null;
        if (importInput) importInput.value = '';
      }
    } catch (error) {
      if (operations.isCommitCurrent(ticket)) {
        importError = `导入失败，当前编辑工程已保留：${errorMessage(error, '未知错误')}`;
      }
    } finally {
      finishCommit(ticket);
    }

    if (imported && operations.isSessionCurrent(session)) requestClose();
  }

  function formatTime(ts: number) {
    const date = new Date(ts);
    if (Number.isNaN(date.getTime())) return '时间未知';
    return `${date.getMonth() + 1}月${date.getDate()}日 ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }
</script>

<MotionDialog
  open={dialogOpen}
  labelledBy="studio-drafts-title"
  describedBy="studio-drafts-description"
  {fallbackFocusSelector}
  closeOnBackdrop={activeCommit === null}
  backdropClass="bg-black/50 backdrop-blur-xs p-3 sm:p-4"
  onCloseRequest={requestClose}
>
  <section
    aria-busy={listState === 'loading' || pendingLoadId !== null || activeCommit !== null}
    class="flex max-h-[min(85dvh,48rem)] w-full min-w-0 max-w-xl flex-col overflow-hidden rounded-3xl border border-[#e2d7c5] bg-[#FAF8F5] text-[#2c2825] shadow-2xl"
  >
    <header class="flex items-start justify-between gap-3 border-b border-[#e8e0d0] bg-[#f5efe6] p-4 sm:p-5">
      <div class="flex min-w-0 items-start gap-2">
        <span aria-hidden="true" class="text-xl">📁</span>
        <div class="min-w-0">
          <h2 id="studio-drafts-title" class="font-serif text-base font-bold">本地草稿箱</h2>
          <p id="studio-drafts-description" class="mt-1 text-xs leading-5 text-[#705c42]">
            本机自动保存快照，随时恢复打谱进度。
          </p>
        </div>
      </div>
      <button
        type="button"
        aria-label="关闭本地草稿箱"
        data-dialog-initial-focus
        onclick={requestClose}
        disabled={activeCommit !== null}
        title={activeCommit ? '草稿操作完成前无法关闭' : '关闭草稿箱'}
        class="flex min-h-[44px] min-w-[44px] shrink-0 items-center justify-center rounded-full bg-[#ede5d8] text-[#705c42] transition-colors hover:bg-[#e2d7c5] hover:text-[#2c2825] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:cursor-wait disabled:opacity-50"
      >
        <span aria-hidden="true">✕</span>
      </button>
    </header>

    <div class="min-h-0 flex-1 overflow-y-auto p-3 sm:p-5">
      {#if activeCommit}
        <p role="status" aria-live="polite" class="mb-3 rounded-xl bg-[#efe5d4] px-3 py-2 text-sm text-[#705c42]">
          {activeCommit.message}…请稍候。完成前无法关闭。
        </p>
      {:else if pendingLoadId}
        <p role="status" aria-live="polite" class="mb-3 rounded-xl bg-[#efe5d4] px-3 py-2 text-sm text-[#705c42]">
          正在读取草稿；此阶段可以安全关闭。
        </p>
      {:else if listState === 'loading'}
        <p role="status" aria-live="polite" class="mb-3 rounded-xl bg-[#efe5d4] px-3 py-2 text-sm text-[#705c42]">
          正在读取本机草稿…
        </p>
      {/if}

      {#if listState === 'error'}
        <div class="mb-3 flex flex-col gap-2 rounded-xl border border-[#d9a493] bg-[#fff5f1] p-3 text-sm text-[#8f3d2b] sm:flex-row sm:items-center sm:justify-between">
          <p role="alert" class="min-w-0 break-words">{listError}</p>
          <button
            type="button"
            onclick={() => void refreshDrafts()}
            disabled={activeCommit !== null || pendingLoadId !== null}
            class="min-h-[44px] shrink-0 rounded-xl border border-[#b8644b] px-3 font-serif text-sm font-bold hover:bg-[#f9e4dc] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:opacity-50"
          >
            重试读取
          </button>
        </div>
      {/if}

      {#if listState === 'loading' && drafts.length === 0}
        <div class="flex min-h-40 flex-col items-center justify-center gap-2 text-center text-[#8c7b68]" role="status">
          <span aria-hidden="true" class="text-3xl opacity-50">⏳</span>
          <span class="font-serif text-sm">正在读取草稿</span>
        </div>
      {:else if listState === 'error' && drafts.length === 0}
        <div class="flex min-h-40 flex-col items-center justify-center gap-2 text-center text-[#8c7b68]">
          <span aria-hidden="true" class="text-3xl opacity-50">📂</span>
          <span class="font-serif text-sm">草稿列表暂时不可用</span>
          <span class="text-xs">读取失败不代表草稿箱为空；可以重试读取。</span>
        </div>
      {:else if listState === 'ready' && drafts.length === 0}
        <div class="flex min-h-40 flex-col items-center justify-center gap-2 text-center text-[#8c7b68]">
          <span aria-hidden="true" class="text-3xl opacity-50">📂</span>
          <span class="font-serif text-sm">暂无本地保存的草稿</span>
          <span class="text-xs text-[#a0907e]">在编辑器中修改或按 Ctrl+S 即可自动生成快照。</span>
        </div>
      {:else}
        <div class="flex flex-col gap-2.5">
          {#each drafts as draft (draft.id)}
            <article class="min-w-0 rounded-2xl border border-[#e8e2d4] bg-white p-3.5 transition-colors hover:border-[#c49a45]">
              <div class="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div class="min-w-0 flex-1">
                  <h3 class="break-words font-serif text-sm font-bold text-[#2c2825]">{draft.title}</h3>
                  <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[#705c42]">
                    <span>作者：{draft.artist}</span>
                    <span aria-hidden="true">•</span>
                    <span>{draft.barCount} 小节</span>
                    <span aria-hidden="true">•</span>
                    <span>{draft.trackCount} 音轨</span>
                  </div>
                  <p class="mt-1 break-words text-xs text-[#a0907e]">修改于 {formatTime(draft.updatedAt)}</p>
                </div>

                <div class="flex w-full shrink-0 gap-2 sm:w-auto">
                  <button
                    type="button"
                    aria-label={`载入草稿：${draft.title}`}
                    aria-busy={pendingLoadId === draft.id || (activeCommit?.kind === 'load' && activeCommit.draftId === draft.id)}
                    onclick={() => void handleLoadDraft(draft.id)}
                    disabled={listState !== 'ready' || pendingLoadId !== null || activeCommit !== null}
                    class="min-h-[44px] min-w-0 flex-1 rounded-xl bg-[#966b1a] px-3 font-serif text-sm font-bold text-white shadow-2xs transition-colors hover:bg-[#7d5612] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:cursor-wait disabled:opacity-50 sm:flex-none"
                  >
                    {pendingLoadId === draft.id || (activeCommit?.kind === 'load' && activeCommit.draftId === draft.id) ? '载入中…' : '载入'}
                  </button>
                  <button
                    type="button"
                    aria-label={`删除草稿：${draft.title}`}
                    aria-expanded={deleteConfirmId === draft.id}
                    onclick={() => requestDeleteConfirmation(draft.id)}
                    title={draft.id === activeProjectId ? '当前编辑中，先新建或载入其他工程后再删除' : undefined}
                    disabled={draft.id === activeProjectId || listState !== 'ready' || pendingLoadId !== null || activeCommit !== null}
                    class="min-h-[44px] min-w-[44px] rounded-xl bg-[#ede5d8] px-3 font-serif text-sm text-[#a5432d] transition-colors hover:bg-[#c84b31]/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:cursor-wait disabled:opacity-50"
                  >
                    删除
                  </button>
                </div>
              </div>

              {#if draft.id === activeProjectId}
                <p class="mt-2 break-words text-xs text-[#705c42]" role="note">
                  当前编辑中，先新建或载入其他工程后再删除。
                </p>
              {/if}

              {#if deleteConfirmId === draft.id && draft.id !== activeProjectId}
                <div class="mt-3 flex flex-col gap-2 rounded-xl bg-[#fff5f1] p-3 sm:flex-row sm:items-center sm:justify-between" role="group" aria-label={`确认删除草稿：${draft.title}`}>
                  <p class="min-w-0 break-words text-sm text-[#8f3d2b]">确定删除这份本机草稿吗？</p>
                  <div class="flex w-full gap-2 sm:w-auto">
                    <button
                      type="button"
                      onclick={() => (deleteConfirmId = null)}
                      class="min-h-[44px] flex-1 rounded-xl border border-[#dfd6c7] px-3 font-serif text-sm hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] sm:flex-none"
                    >
                      取消
                    </button>
                    <button
                      type="button"
                      onclick={() => void handleDeleteDraft(draft.id)}
                      class="min-h-[44px] flex-1 rounded-xl bg-[#a5432d] px-3 font-serif text-sm font-bold text-white hover:bg-[#8f3d2b] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] sm:flex-none"
                    >
                      确认删除
                    </button>
                  </div>
                </div>
              {/if}

              {#if rowErrors[draft.id]}
                <p class="mt-3 break-words rounded-xl bg-[#fff5f1] px-3 py-2 text-sm text-[#8f3d2b]" role="alert">
                  {rowErrors[draft.id]}
                </p>
              {/if}
            </article>
          {/each}
        </div>
      {/if}
    </div>

    {#if importError}
      <div class="border-t border-[#e8e0d0] bg-[#fff5f1] px-3 py-3 sm:px-5" role="alert">
        <p class="break-words text-sm text-[#8f3d2b]">{importError}</p>
        {#if selectedImportFile && activeCommit === null}
          <div class="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <p class="min-w-0 break-words text-xs text-[#705c42]">已保留所选文件：{selectedImportFile.name}</p>
            <button
              type="button"
              onclick={() => void handleImportFile(selectedImportFile!)}
              disabled={pendingLoadId !== null || listState === 'loading'}
              class="min-h-[44px] rounded-xl border border-[#b8644b] px-3 font-serif text-sm font-bold text-[#8f3d2b] hover:bg-[#f9e4dc] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:opacity-50"
            >
              重试导入
            </button>
          </div>
        {/if}
      </div>
    {/if}

    {#if closeNotice}
      <p class="border-t border-[#e8e0d0] bg-[#f5efe6] px-4 py-2 text-sm text-[#705c42]" role="status" aria-live="polite">
        {closeNotice}
      </p>
    {/if}

    <footer class="flex flex-col gap-2 border-t border-[#e8e0d0] bg-[#f5efe6] p-3.5 sm:flex-row sm:items-center sm:justify-between sm:p-4">
      <label class="import-picker inline-flex min-h-[44px] w-full min-w-0 cursor-pointer items-center justify-center gap-2 rounded-xl border border-[#dfd6c7] bg-white px-3 font-serif text-sm font-bold text-[#705c42] shadow-2xs transition-colors hover:border-[#c49a45] hover:text-[#2c2825] focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-[#966b1a] sm:w-auto">
        <span class="min-w-0 break-words text-center">
          {#if activeCommit?.kind === 'import'}⏳ 正在导入并保存…{:else}📥 导入谱面或工程文件{/if}
        </span>
        <input
          bind:this={importInput}
          type="file"
          aria-label="选择要导入的乐谱或工程文件"
          accept=".json,.ibe,.gp,.gp3,.gp4,.gp5,.gpx,.gp7,.gp8,.musicxml,.xml,.tex,.alphatex"
          onchange={handleImportSelection}
          class="sr-only"
          disabled={activeCommit !== null || pendingLoadId !== null || listState === 'loading'}
        />
      </label>

      <button
        type="button"
        onclick={requestClose}
        disabled={activeCommit !== null}
        title={activeCommit ? '草稿操作完成前无法关闭' : undefined}
        class="min-h-[44px] w-full rounded-xl bg-[#2c2825] px-4 font-serif text-sm font-bold text-[#fbfaf7] shadow-xs transition-colors hover:bg-[#403b37] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a] disabled:cursor-wait disabled:opacity-50 sm:w-auto"
      >
        完成
      </button>
    </footer>
  </section>
</MotionDialog>
