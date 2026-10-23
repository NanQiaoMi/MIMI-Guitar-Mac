<script lang="ts">
  import MotionDialog from '../ui/MotionDialog.svelte';
  import {
    collectStudioLyrics,
    summarizeStudioLyrics,
    tokenizeStudioLyrics,
    type StudioLyricsCommand,
  } from '../../lib/studio/studioLyrics';
  import type { StudioProject } from '../../lib/studio/studioScoreModel';

  type LyricsTarget = {
    projectId: string;
    projectTitle: string;
    trackId: string;
    trackName: string;
    expectedRevision: number;
  };

  type LyricsDraft = {
    text: string;
    expectedRevision: number;
  };

  let {
    isOpen = false,
    project,
    selectedTrackIndex = 0,
    studioRevision,
    fallbackFocusSelector,
    onClose,
    onApplyLyrics,
  }: {
    isOpen: boolean;
    project: StudioProject;
    selectedTrackIndex: number;
    studioRevision: number;
    fallbackFocusSelector?: string;
    onClose?: () => void;
    onApplyLyrics: (command: StudioLyricsCommand) => void;
  } = $props();

  let lyricsText = $state('');
  let target = $state<LyricsTarget | null>(null);
  let drafts = $state<Record<string, LyricsDraft>>({});
  let feedback = $state('');
  let feedbackIsError = $state(false);
  let wasOpen = false;

  const currentTrack = $derived(project.tracks[selectedTrackIndex] ?? null);
  const targetProjectMatches = $derived(Boolean(target && project.id === target.projectId));
  const targetTrackExists = $derived.by(() => {
    const currentTarget = target;
    if (!currentTarget || !targetProjectMatches) return false;
    const targetTrackId = currentTarget.trackId;
    return project.tracks.some((track) => track.id === targetTrackId);
  });
  const targetRevisionMatches = $derived(Boolean(target && studioRevision === target.expectedRevision));
  const targetIsCurrentSelection = $derived(Boolean(
    target && currentTrack && project.id === target.projectId && currentTrack.id === target.trackId,
  ));
  const canEditTarget = $derived(Boolean(target && targetProjectMatches && targetTrackExists && targetRevisionMatches));
  const summary = $derived.by(() => {
    if (!target || !targetProjectMatches || !targetTrackExists) {
      return { wordCount: tokenizeStudioLyrics(lyricsText).length, availablePositions: 0, existingLyrics: 0 };
    }
    return summarizeStudioLyrics(project, target.trackId, lyricsText);
  });
  const canAlign = $derived(Boolean(
    canEditTarget && summary.wordCount > 0 && summary.availablePositions > 0 && summary.wordCount <= summary.availablePositions,
  ));
  const canClear = $derived(Boolean(canEditTarget && summary.existingLyrics > 0));

  function targetKey(projectId: string, trackId: string): string {
    return JSON.stringify([projectId, trackId]);
  }

  function loadTarget(nextProject: StudioProject, trackIndex: number, revision: number, preferDraft = true) {
    const track = nextProject.tracks[trackIndex];
    if (!track) {
      target = null;
      lyricsText = '';
      feedback = '当前工程没有可用音轨。';
      feedbackIsError = true;
      return;
    }

    const key = targetKey(nextProject.id, track.id);
    const savedDraft = preferDraft ? drafts[key] : undefined;
    target = {
      projectId: nextProject.id,
      projectTitle: nextProject.title || '未命名乐谱',
      trackId: track.id,
      trackName: track.name,
      expectedRevision: savedDraft?.expectedRevision ?? revision,
    };
    lyricsText = savedDraft?.text ?? collectStudioLyrics(nextProject, track.id);
    feedback = '';
    feedbackIsError = false;
  }

  function storeDraft(text = lyricsText) {
    if (!target) return;
    drafts[targetKey(target.projectId, target.trackId)] = {
      text,
      expectedRevision: target.expectedRevision,
    };
  }

  $effect(() => {
    if (!isOpen) {
      wasOpen = false;
      return;
    }
    if (wasOpen) return;
    wasOpen = true;
    loadTarget(project, selectedTrackIndex, studioRevision);
  });

  function handleLyricsInput(event: Event) {
    lyricsText = (event.currentTarget as HTMLTextAreaElement).value;
    feedback = '';
    feedbackIsError = false;
    storeDraft();
  }

  function dispatchLyricsCommand(kind: 'align' | 'clear'): boolean {
    if (!target || !canEditTarget) return false;
    const command: StudioLyricsCommand = {
      kind,
      projectId: target.projectId,
      trackId: target.trackId,
      expectedRevision: target.expectedRevision,
      ...(kind === 'align' ? { text: lyricsText } : {}),
    };

    try {
      onApplyLyrics(command);
      feedbackIsError = false;
      return true;
    } catch (error) {
      feedback = error instanceof Error ? error.message : '歌词没有应用，请检查工程状态后重试。';
      feedbackIsError = true;
      storeDraft();
      return false;
    }
  }

  function applyLyrics() {
    if (!canAlign || !target) return;
    if (!dispatchLyricsCommand('align')) return;

    delete drafts[targetKey(target.projectId, target.trackId)];
    onClose?.();
  }

  function clearWrittenLyrics() {
    if (!canClear || !target) return;
    if (!dispatchLyricsCommand('clear')) return;

    // The explicit project clear leaves the user's uncommitted text intact.
    target = { ...target, expectedRevision: target.expectedRevision + 1 };
    storeDraft();
    feedback = '已清空当前音轨中已写入的歌词；输入框草稿仍保留。';
    feedbackIsError = false;
  }

  function switchToCurrentTrack() {
    storeDraft();
    loadTarget(project, selectedTrackIndex, studioRevision);
  }

  function discardDraftAndReloadCurrentLyrics() {
    const track = currentTrack;
    if (!track) return;

    const key = targetKey(project.id, track.id);
    delete drafts[key];
    loadTarget(project, selectedTrackIndex, studioRevision, false);
    feedback = '已放弃当前选中音轨的未应用输入，并重新载入工程中已写入的歌词。';
    feedbackIsError = false;
  }
</script>

<MotionDialog
  open={isOpen}
  labelledBy="lyrics-drawer-title"
  describedBy="lyrics-drawer-description"
  {fallbackFocusSelector}
  backdropClass="items-center p-2 sm:p-4"
  panelClass="w-full max-w-xl max-h-[calc(100dvh-2rem)] overflow-hidden rounded-3xl border border-[#e2d7c5] bg-[#fdfbf7] shadow-2xl text-[#2c2825]"
  onCloseRequest={() => onClose?.()}
>
  <section class="flex max-h-[calc(100dvh-2rem-2px)] min-h-0 flex-col">
    <header class="flex shrink-0 items-center justify-between gap-3 border-b border-[#e8dfd2] px-5 py-4 sm:px-7">
      <div class="flex min-w-0 items-center gap-2.5">
        <span class="text-xl" aria-hidden="true">📝</span>
        <h2 id="lyrics-drawer-title" tabindex="-1" data-dialog-initial-focus class="text-lg font-serif font-bold text-[#966b1a]">歌词智能吸附与对齐</h2>
      </div>
      <button
        type="button"
        onclick={onClose}
        aria-label="关闭歌词对齐"
        class="inline-flex min-h-[44px] min-w-[44px] shrink-0 items-center justify-center rounded-full bg-[#ede5d8] text-sm font-bold text-[#705c42] transition-colors hover:bg-[#2c2825] hover:text-[#fbfaf7] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
      >
        ✕
      </button>
    </header>

    <div class="min-h-0 flex-1 space-y-4 overflow-y-auto overscroll-contain p-5 sm:p-7">
      <p id="lyrics-drawer-description" class="text-xs font-serif leading-relaxed text-[#705c42]">
        在下方文本框中直接粘贴或输入整首歌曲的歌词，点击「智能对齐」，系统将根据当前音轨的非休止符音符自动按字分词并对位到每个节拍下方。
      </p>

      {#if target}
        <div class="rounded-xl border border-[#e8dfd2] bg-[#f5efe6] px-3 py-2 text-xs text-[#5c4a38]" aria-live="polite">
          <span class="font-bold">歌词目标：</span>{target.projectTitle} · {target.trackName}
        </div>
      {/if}

      {#if target && (!targetProjectMatches || !targetTrackExists)}
        <div class="rounded-xl border border-[#d9a78e] bg-[#fff4ef] px-3 py-2 text-xs leading-relaxed text-[#8d3b27]" role="alert">
          目标工程或音轨已变化。输入仍保存在原目标草稿中；切换到当前选中音轨后，才会对新目标执行操作。
        </div>
      {:else if target && !targetRevisionMatches}
        <div class="rounded-xl border border-[#d9a78e] bg-[#fff4ef] px-3 py-2 text-xs leading-relaxed text-[#8d3b27]" role="alert">
          工程内容在打开歌词窗口后发生了变化。草稿已保留；请明确重载工程歌词后再应用，避免覆盖较新的编辑。
        </div>
      {:else if target && !targetIsCurrentSelection}
        <div class="rounded-xl border border-[#d8bd76] bg-[#fff8e8] px-3 py-2 text-xs leading-relaxed text-[#765514]" role="status">
          当前选中音轨已切换；此草稿仍绑定到「{target.trackName}」，操作不会写入新选中音轨。
        </div>
      {/if}

      <label for="studio-lyrics-input" class="block text-xs font-bold text-[#5c4a38]">整首歌词</label>
      <textarea
        id="studio-lyrics-input"
        value={lyricsText}
        oninput={handleLyricsInput}
        disabled={!target}
        rows="8"
        aria-describedby="lyrics-drawer-description lyrics-lifecycle-note lyrics-alignment-summary"
        placeholder="在此处粘贴完整歌词，例如：&#10;慢慢弹响每一根弦&#10;听见木纹里的风..."
        class="min-h-32 max-h-[38dvh] w-full resize-y rounded-2xl border border-[#dfd6c7] bg-white p-4 text-xs font-serif leading-relaxed text-[#2c2825] shadow-2xs placeholder-[#a89b8a] focus:border-[#c49a45] focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[#c49a45]/60"
      ></textarea>

      <p id="lyrics-lifecycle-note" class="rounded-xl border border-[#e8dfd2] bg-[#f5efe6] px-3 py-2 text-xs leading-relaxed text-[#705c42]">
        未应用的输入只在当前页面内按工程和音轨暂存；刷新或离开此页后会丢失。应用并保存成功后，歌词写入工程，可随工程备份。
      </p>

      <div id="lyrics-alignment-summary" class="space-y-1 text-xs leading-relaxed text-[#705c42]" aria-live="polite">
        {#if target && targetProjectMatches && targetTrackExists}
          <p>有效字词 {summary.wordCount} 个 · 当前目标有 {summary.availablePositions} 个可对齐拍位。</p>
          {#if summary.wordCount === 0}
            <p>请至少输入一个可识别的中文单字或英文词组。</p>
          {:else if summary.availablePositions === 0}
            <p>当前目标没有带音符的非休止拍，请先录入音符。</p>
          {:else if summary.wordCount > summary.availablePositions}
            <p class="font-bold text-[#8d3b27]">多出 {summary.wordCount - summary.availablePositions} 个字词；系统不会静默截断，请缩短歌词或增加音符。</p>
          {/if}
          {#if summary.existingLyrics === 0}
            <p>当前音轨尚无已写入歌词可清空。</p>
          {/if}
        {:else}
          <p>先选择有效工程与音轨，再输入歌词。</p>
        {/if}
      </div>

      {#if feedback}
        <p class="rounded-xl px-3 py-2 text-xs leading-relaxed {feedbackIsError ? 'border border-[#d9a78e] bg-[#fff4ef] text-[#8d3b27]' : 'border border-[#c8ddc9] bg-[#eef8f0] text-[#2e6b39]'}" role={feedbackIsError ? 'alert' : 'status'}>
          {feedback}
        </p>
      {/if}
    </div>

    <footer class="flex shrink-0 flex-col gap-2 border-t border-[#e8dfd2] bg-[#fdfbf7] p-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          onclick={clearWrittenLyrics}
          disabled={!canClear}
          aria-describedby="lyrics-alignment-summary"
          class="inline-flex min-h-[44px] items-center justify-center rounded-full bg-[#ede5d8] px-4 text-xs font-serif text-[#c84b31] transition-colors hover:bg-[#c84b31] hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45] disabled:cursor-not-allowed disabled:opacity-50"
        >
          清空当前音轨歌词
        </button>
        {#if target && currentTrack}
          <button
            type="button"
            onclick={discardDraftAndReloadCurrentLyrics}
            disabled={!currentTrack}
            aria-label="放弃当前选中音轨草稿并重载已保存歌词"
            class="inline-flex min-h-[44px] items-center justify-center rounded-full border border-[#dfd6c7] bg-white px-4 text-xs font-serif text-[#5c4a38] hover:bg-[#f5efe6] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45] disabled:cursor-not-allowed disabled:opacity-50"
          >
            放弃草稿并重载当前歌词
          </button>
        {/if}
      </div>

      <div class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          onclick={onClose}
          class="inline-flex min-h-[44px] items-center justify-center rounded-full bg-[#ede5d8] px-5 text-xs font-serif text-[#5c4a38] transition-colors hover:bg-[#e2d7c5] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
        >
          取消
        </button>
        {#if target && !targetIsCurrentSelection && targetProjectMatches}
          <button
            type="button"
            onclick={switchToCurrentTrack}
            class="inline-flex min-h-[44px] items-center justify-center rounded-full border border-[#c49a45] bg-[#fff8e8] px-4 text-xs font-serif font-bold text-[#765514] hover:bg-[#f5efe6] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45]"
          >
            切换到当前音轨
          </button>
        {/if}
        <button
          type="button"
          onclick={applyLyrics}
          disabled={!canAlign}
          aria-describedby="lyrics-alignment-summary"
          class="inline-flex min-h-[44px] items-center justify-center rounded-full bg-[#2c2825] px-5 text-xs font-serif font-bold text-[#fbfaf7] shadow-xs transition-colors hover:bg-[#403b37] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#c49a45] disabled:cursor-not-allowed disabled:opacity-50"
        >
          ✨ 智能对齐到音符
        </button>
      </div>
    </footer>
  </section>
</MotionDialog>
