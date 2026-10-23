<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import {
    createBlankProject,
    cloneProject,
    evaluateBarTiming,
    setNoteFret,
    deleteNote,
    setBeatDuration,
    toggleBeatDot,
    toggleBeatTriplet,
    toggleBeatRest,
    toggleNoteTechnique,
    setBeatChord,
    insertBeatInBar,
    deleteBeatInBar,
    insertBarAfter,
    duplicateBar,
    deleteBar,
    updateBarMeta,
    type StudioProject,
    type CursorPosition,
    type DurationValue,
    type StudioNote,
  } from '../../lib/studio/studioScoreModel';
  import { saveStudioProject, saveStudioProjectForPractice, listStudioProjects, loadStudioProject, deleteStudioProject, rememberStudioProjectVersion } from '../../lib/personal/studioPersistence.ts';
  import { applyStudioLyricsCommand, type StudioLyricsCommand } from '../../lib/studio/studioLyrics.ts';
  import { createStudioFretInput } from '../../lib/studio/studioFretInput.ts';
  import { createStudioSaveBoundary } from '../../lib/studio/studioSaveBoundary.ts';
  import { fadeMotion, registerMotionSurface, surfaceMotion } from '../../lib/ui/motion.ts';
  import MotionSegmentedControl from '../ui/MotionSegmentedControl.svelte';
  import { claimAudioFocus } from '../../lib/player/audioFocus.ts';
  import { hashBytes } from '../../lib/personal/repository.ts';
  import { isSafeLocalPath } from '../../lib/personal/validation.ts';
  import { studioAudio } from '../../lib/studio/studioAudioEngine';
  import {
    exportStudioProjectFile,
    importStudioScoreBytes,
    importStudioScoreFile,
  } from '../../lib/studio/studioScoreBridge';
  import {
    downloadStoredOriginalScore,
    getOriginalScoreFile,
  } from '../../lib/studio/studioOriginalFileStore';

  import StudioHeader from './StudioHeader.svelte';
  import StudioToolbar from './StudioToolbar.svelte';
  import ScoreCanvas from './ScoreCanvas.svelte';
  import VirtualFretboard from './VirtualFretboard.svelte';
  import ChordPalette from './ChordPalette.svelte';
  import TrackMixer from './TrackMixer.svelte';
  import LyricsDrawer from './LyricsDrawer.svelte';
  import ShortcutHelpModal from './ShortcutHelpModal.svelte';
  import DraftsModal from './DraftsModal.svelte';
  import StudioGuide from './StudioGuide.svelte';

  let project = $state<StudioProject>(createBlankProject('guitar'));
  let cursor = $state<CursorPosition>({
    trackIndex: 0,
    barIndex: 0,
    beatIndex: 0,
    stringIndex: 1,
  });

  let undoStack = $state<StudioProject[]>([]);
  let redoStack = $state<StudioProject[]>([]);

  let isPlaying = $state(false);
  let startingPlayback = $state(false);
  let playbackGeneration = 0;
  let nativeFocusRelease: (() => void) | null = null;
  let hasLoop = $state(false);
  let metronome = $state(false);
  let countIn = $state(false);
  let isChordMode = $state(false);

  let isBottomDrawerCollapsed = $state(false);
  let activeBottomTab = $state<'workbench' | 'mixer'>('workbench');
  type StudioDialog = 'lyrics' | 'shortcuts' | 'drafts' | 'guide';
  let activeStudioDialog = $state<StudioDialog | null>(null);
  let studioRevision = $state(0);
  let studioMessage = $state('');
  let studioMessageType: 'success' | 'warning' | 'error' = $state('success');
  let practiceDestination = $state<{ projectId: string; href: string } | null>(null);
  let isImporting = $state(false);
  let isInitializing = $state(true);
  let isSwitchingProject = $state(false);
  let persistenceRevision = 0;
  const saveBoundary = createStudioSaveBoundary();
  let fretInputPending = false;
  let beforeUnloadAttached = false;

  let alphaTabApi: any = $state(null);
  let nativeAudioReady = $state(false);
  let bottomPanel: HTMLDivElement;
  let bottomToggle: HTMLButtonElement;
  let bottomControls: HTMLDivElement;
  const bottomOptions = [
    { value: 'workbench', label: '指板与和弦' },
    { value: 'mixer', label: '多轨调音台' },
  ];
  const fretInput = createStudioFretInput({
    context: () => `${project.id}:${studioRevision}:${cursor.trackIndex}:${cursor.barIndex}:${cursor.beatIndex}:${cursor.stringIndex}`,
    commit: inputFretNumber,
    onPendingChange: (pending) => {
      fretInputPending = pending;
      syncBeforeUnloadGuard();
    },
  });

  function warnBeforeUnload(event: BeforeUnloadEvent) {
    // A delayed 1/2 fret digit is user work too. Commit it before checking whether
    // the resulting draft write has settled.
    fretInput.flush();
    const snapshot = saveBoundary.getSnapshot();
    if (snapshot.pending || snapshot.error !== null || fretInputPending) {
      event.preventDefault();
      event.returnValue = '';
    }
  }

  function syncBeforeUnloadGuard() {
    if (typeof window === 'undefined') return;
    const snapshot = saveBoundary.getSnapshot();
    const shouldAttach = fretInputPending || snapshot.pending || snapshot.error !== null;
    if (shouldAttach && !beforeUnloadAttached) {
      window.addEventListener('beforeunload', warnBeforeUnload);
      beforeUnloadAttached = true;
    } else if (!shouldAttach && beforeUnloadAttached) {
      window.removeEventListener('beforeunload', warnBeforeUnload);
      beforeUnloadAttached = false;
    }
  }

  onMount(() => {
    const unsubscribe = saveBoundary.subscribe(() => syncBeforeUnloadGuard());
    const onPageHide = () => stopPlay({ resetCursor: false, pauseNative: true });
    window.addEventListener('pagehide', onPageHide);
    syncBeforeUnloadGuard();
    return () => {
      unsubscribe();
      window.removeEventListener('pagehide', onPageHide);
      window.removeEventListener('beforeunload', warnBeforeUnload);
      beforeUnloadAttached = false;
    };
  });

  function replaceStudioProject(value: StudioProject) {
    fretInput.cancel();
    project = value;
    studioRevision += 1;
    const trackIndex = Math.min(cursor.trackIndex, Math.max(0, value.tracks.length - 1));
    const barIndex = Math.min(cursor.barIndex, Math.max(0, value.bars.length - 1));
    const track = value.tracks[trackIndex];
    const beats = value.bars[barIndex]?.trackBeats[track?.id] ?? [];
    cursor = {
      trackIndex, barIndex,
      beatIndex: Math.min(cursor.beatIndex, Math.max(0, beats.length - 1)),
      stringIndex: Math.min(cursor.stringIndex, track?.tuning.length || 6),
    };
  }

  function openStudioDialog(dialog: StudioDialog) {
    fretInput.flush();
    activeStudioDialog = dialog;
  }

  function closeStudioDialog(dialog: StudioDialog) {
    if (activeStudioDialog === dialog) activeStudioDialog = null;
  }

  async function settleProjectSaves() {
    fretInput.flush();
    try {
      await saveBoundary.settle();
    } catch (error) {
      throw new Error(`当前工程尚未保存成功，请先导出工程备份或重试保存，再切换工程。${error instanceof Error ? error.message : String(error)}`);
    }
  }

  function selectBottomTab(value: string) {
    if (value !== 'workbench' && value !== 'mixer') return;
    fretInput.flush();
    if (bottomPanel?.contains(document.activeElement)) {
      bottomControls?.querySelector<HTMLButtonElement>(`[role="radio"][aria-label="${value === 'mixer' ? '多轨调音台' : '指板与和弦'}"]`)?.focus();
    }
    activeBottomTab = value;
    isBottomDrawerCollapsed = false;
  }

  function toggleBottomDrawer() {
    fretInput.flush();
    if (!isBottomDrawerCollapsed && bottomPanel?.contains(document.activeElement)) bottomToggle?.focus();
    isBottomDrawerCollapsed = !isBottomDrawerCollapsed;
  }

  function selectStudioTrack(trackIndex: number) {
    fretInput.flush();
    const track = project.tracks[trackIndex];
    if (!track) return;
    const beats = project.bars[cursor.barIndex]?.trackBeats[track.id] ?? [];
    cursor = { ...cursor, trackIndex, beatIndex: Math.min(cursor.beatIndex, Math.max(0, beats.length - 1)), stringIndex: Math.min(cursor.stringIndex, track.tuning.length) };
  }

  // 获取当前光标所在的 Beat 与 Note 信息
  let currentTrack = $derived(project.tracks[cursor.trackIndex] || project.tracks[0]);
  let currentBar = $derived(project.bars[cursor.barIndex] || project.bars[0]);
  let currentBeat = $derived(
    currentBar && currentTrack ? (currentBar.trackBeats[currentTrack.id] || [])[cursor.beatIndex] : null
  );
  let currentDuration = $derived<DurationValue>(currentBeat?.duration || 4);
  let hasDot = $derived(!!currentBeat?.dot);
  let hasTriplet = $derived(!!currentBeat?.triplet);
  let isRest = $derived(!!currentBeat?.isRest);
  let currentTiming = $derived(currentBar && currentTrack ? evaluateBarTiming(currentBar, currentTrack.id) : null);

  let activeNotes = $derived<StudioNote[]>(currentBeat?.notes || []);
  let activeTechniques = $derived.by((): Record<string, boolean> => {
    const note = activeNotes.find((n) => n.string === cursor.stringIndex);
    if (!note) return {};
    return {
      tie: !!note.tie,
      hammerPull: !!note.hammerPull,
      slide: !!note.slide,
      bend: !!note.bend,
      harmonic: !!note.harmonic,
      palmMute: !!note.palmMute,
      dead: !!note.dead,
      vibrato: !!note.vibrato,
      accent: !!note.accent,
      ghost: !!note.ghost,
    };
  });

  async function persistProject(value: StudioProject, original?: { id: string; fileName: string; mimeType: string; bytes: Uint8Array }) {
    const ticket = ++persistenceRevision;
    try {
      await saveBoundary.track(saveStudioProject(value, original));
      if (ticket === persistenceRevision) {
        studioMessageType = 'success';
        studioMessage = `「${value.title || '未命名乐谱'}」已保存到个人资料并包含在备份中。`;
      }
      return true;
    } catch (error) {
      if (ticket === persistenceRevision) {
        studioMessageType = 'error';
        studioMessage = `个人草稿保存失败：${error instanceof Error ? error.message : String(error)}。请导出工程文件备份。`;
      }
      return false;
    }
  }

  // 1. 初始化时加载草稿或改编目标
  onMount(async () => {
    if (typeof window === 'undefined') return;

    // 曲库改编入口创建个人副本；失败时明确报告，不误载入另一份本地草稿。
    const params = new URLSearchParams(window.location.search);
    const cloneFrom = params.get('cloneFrom');
    const projectId = params.get('project');

    if (cloneFrom) {
      isImporting = true;
      try {
        const res = await fetch(`/api/tabs/${encodeURIComponent(cloneFrom)}`);
        if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `曲库请求失败（${res.status}）`);
        const tab = await res.json();
        if (tab.format === 'xhe' || !isSafeLocalPath(tab.scoreUrl)) throw new Error('这份曲谱没有可编辑的原谱文件。');
        const scoreResponse = await fetch(tab.scoreUrl);
        if (!scoreResponse.ok) throw new Error(`原谱文件不可用（${scoreResponse.status}），请从曲库重新打开或下载原谱。`);
        const bytes = new Uint8Array(await scoreResponse.arrayBuffer());
        const source = {
          kind: 'library' as const,
          id: `library:${String(tab.id || cloneFrom)}:${await hashBytes(bytes)}`,
          fileName: `${String(tab.title || '曲库乐谱')}.ibe`,
          format: String(tab.format || 'ibe'),
          title: String(tab.title || ''),
        };
        const imported = await importStudioScoreBytes(bytes, source.fileName, source);
        imported.project.title = `${String(tab.title || imported.project.title).replace(/（个人改编）$/, '')}（个人改编）`;
        imported.project.artist = String(tab.artist || imported.project.artist || '');
        imported.project.key = String(tab.key || imported.project.key || 'C');
        imported.project.initialTempo = Number(tab.tempo) > 0 ? Number(tab.tempo) : imported.project.initialTempo;
        const saved = await persistProject(imported.project, { id: source.id, fileName: source.fileName, mimeType: 'application/octet-stream', bytes });
        if (!saved) throw new Error('个人副本与原件未保存成功，当前工程已保留。');
        replaceStudioProject(imported.project);
        cursor = { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1 };
        undoStack = [];
        redoStack = [];
        studioMessageType = imported.warnings.length ? 'warning' : (saved ? 'success' : 'error');
        studioMessage = imported.warnings.length
          ? `已载入原谱并建立个人副本；有 ${imported.warnings.length} 项转换提醒，请先检查黄色说明。`
          : '已建立独立个人副本，并单独保存原始文件。';
      } catch (e) {
        studioMessageType = 'error';
        studioMessage = `无法基于原谱创建个人副本：${e instanceof Error ? e.message : String(e)}`;
      } finally {
        isImporting = false;
        isInitializing = false;
      }
      return;
    }

    if (projectId) {
      try {
        const savedProject = await loadStudioProject(projectId);
        if (!savedProject) throw new Error('我的谱中找不到这份工坊工程。');
        rememberStudioProjectVersion(savedProject);
        replaceStudioProject(savedProject);
        cursor = { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1 };
        undoStack = [];
        redoStack = [];
        studioMessage = `已从我的谱打开「${savedProject.title || '未命名乐谱'}」，可以继续编辑。`;
      } catch (error) {
        studioMessageType = 'error';
        studioMessage = `无法打开这份个人工程：${error instanceof Error ? error.message : String(error)}`;
      } finally {
        isInitializing = false;
      }
      return;
    }

    // 优先恢复本地最新草稿 (来自 mimi_studio_draft_score)
    let draft: StudioProject | null = null;
    try {
      draft = (await listStudioProjects()).sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0))[0] ?? null;
    } catch (error) {
      studioMessageType = 'error';
      studioMessage = `读取个人草稿失败：${error instanceof Error ? error.message : String(error)}`;
    }
    if (draft && draft.bars?.length > 0) {
      rememberStudioProjectVersion(draft);
      replaceStudioProject(draft);
      studioMessage = `已恢复本机草稿「${draft.title || '未命名乐谱'}」。`;
    }
    isInitializing = false;
  });

  onDestroy(() => {
    fretInput.cancel();
    playbackGeneration++;
    nativeFocusRelease?.();
    nativeFocusRelease = null;
    studioAudio.stopPlayback();
  });

  // 2. 状态原子化变更与 50 步 Undo 栈管理
  function applyChange(newProject: StudioProject, original?: { id: string; fileName: string; mimeType: string; bytes: Uint8Array }, persist = true): boolean {
    undoStack = [...undoStack.slice(-50), cloneProject(project)];
    redoStack = [];
    if (persist) newProject.updatedAt = Date.now();
    replaceStudioProject(newProject);
    if (persist) void persistProject(newProject, original);
    studioMessageType = 'success';
    studioMessage = persist ? '正在保存个人草稿…' : '已载入个人工程。';
    const saved = true;
    return saved;
  }

  function handleUndo() {
    fretInput.flush();
    if (undoStack.length === 0) return;
    const prev = undoStack[undoStack.length - 1];
    undoStack = undoStack.slice(0, -1);
    redoStack = [...redoStack.slice(-50), cloneProject(project)];
    replaceStudioProject(prev);
    void persistProject(prev);
  }

  function handleRedo() {
    fretInput.flush();
    if (redoStack.length === 0) return;
    const next = redoStack[redoStack.length - 1];
    redoStack = redoStack.slice(0, -1);
    undoStack = [...undoStack.slice(-50), cloneProject(project)];
    replaceStudioProject(next);
    void persistProject(next);
  }

  // 3. 键盘输入品数与发音
  function inputFretNumber(fret: number) {
    const next = setNoteFret(
      project,
      cursor.trackIndex,
      cursor.barIndex,
      cursor.beatIndex,
      cursor.stringIndex,
      fret
    );
    applyChange(next);

    // 播放即时原声物理拨弦
    const prog = currentTrack?.program ?? 25;
    const tuning = currentTrack?.tuning ?? [64, 59, 55, 50, 45, 40];
    studioAudio.playNote(cursor.stringIndex, fret, prog, tuning);

    // 单音步进模式自动移至下一拍；和弦录入模式保持在当前拍，方便上下弦选音
    if (!isChordMode) {
      advanceCursor();
    }
  }

  function advanceCursor() {
    const beats = currentBar?.trackBeats[currentTrack.id] || [];
    if (cursor.beatIndex < beats.length - 1) {
      cursor = { ...cursor, beatIndex: cursor.beatIndex + 1 };
    } else if (cursor.barIndex < project.bars.length - 1) {
      cursor = { ...cursor, barIndex: cursor.barIndex + 1, beatIndex: 0 };
    } else {
      // 连续打谱体验：若在全曲最后一小节末拍继续前进，自动追加一个新小节并移入
      const next = insertBarAfter(project, cursor.barIndex);
      applyChange(next);
      cursor = { ...cursor, barIndex: cursor.barIndex + 1, beatIndex: 0 };
    }
  }

  function retreatCursor() {
    if (cursor.beatIndex > 0) {
      cursor = { ...cursor, beatIndex: cursor.beatIndex - 1 };
    } else if (cursor.barIndex > 0) {
      const prevBar = cursor.barIndex - 1;
      const prevBeats = project.bars[prevBar]?.trackBeats[currentTrack.id] || [];
      cursor = { ...cursor, barIndex: prevBar, beatIndex: Math.max(0, prevBeats.length - 1) };
    }
  }

  // 插入拍与删除拍
  function handleInsertBeat() {
    const next = insertBeatInBar(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex);
    applyChange(next);
    cursor = { ...cursor, beatIndex: cursor.beatIndex + 1 };
  }

  function handleDeleteBeat() {
    const next = deleteBeatInBar(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex);
    applyChange(next);
    cursor = { ...cursor, beatIndex: Math.max(0, cursor.beatIndex - 1) };
  }

  // 新建作品预设 (吉他 / 尤克里里 / 贝斯)
  async function handleNewProject(type: 'guitar' | 'ukulele' | 'bass') {
    if (isSwitchingProject) return;
    isSwitchingProject = true;
    try {
      await settleProjectSaves();
      if (typeof window !== 'undefined') {
        const url = new URL(window.location.href);
        url.searchParams.delete('project');
        url.searchParams.delete('cloneFrom');
        history.replaceState({}, '', url.pathname + url.search);
      }
      stopPlay();
      const p = createBlankProject(type);
      applyChange(p);
      cursor = { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1 };
    } catch (error) {
      studioMessageType = 'error';
      studioMessage = `新建未完成，当前工程已保留：${error instanceof Error ? error.message : String(error)}`;
    } finally {
      isSwitchingProject = false;
    }
  }

  // 清空当前小节
  function handleClearBar() {
    const next = cloneProject(project);
    const beats = next.bars[cursor.barIndex]?.trackBeats[currentTrack.id] || [];
    beats.forEach((b) => {
      b.notes = [];
      b.chordName = null;
      b.isRest = true;
    });
    applyChange(next);
  }

  // 4. 键盘事件处理器
  function handleKeyDown(e: KeyboardEvent) {
    // Flush a pending 1/2 fret before other commands so an arrow or edit key
    // cannot move the cursor first and enter the fret on a different beat.
    if (!/^[0-9]$/.test(e.key) || e.ctrlKey || e.metaKey || e.altKey) fretInput.flush();
    // Tab remains the browser's focus navigation key, including Shift+Tab.
    if (e.key === 'Tab') return;

    // 快捷键撤销 / 重做 (Ctrl+Z / Ctrl+Y)
    if (e.ctrlKey || e.metaKey) {
      if (e.key === 'z' || e.key === 'Z') {
        e.preventDefault();
        if (e.shiftKey) handleRedo();
        else handleUndo();
        return;
      }
      if (e.key === 'y' || e.key === 'Y') {
        e.preventDefault();
        handleRedo();
        return;
      }
      if (e.key === 's' || e.key === 'S') {
        e.preventDefault();
        handleSaveDraft();
        return;
      }
      return;
    }

    // 空格键：播放/暂停
    if (e.key === ' ') {
      e.preventDefault();
      togglePlay();
      return;
    }

    // 时值切换快捷键 (Alt+1..6 或 Ctrl+1..6)
    if (e.altKey) {
      if (e.key === '1') { e.preventDefault(); applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, 1)); return; }
      if (e.key === '2') { e.preventDefault(); applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, 2)); return; }
      if (e.key === '3') { e.preventDefault(); applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, 4)); return; }
      if (e.key === '4') { e.preventDefault(); applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, 8)); return; }
      if (e.key === '5') { e.preventDefault(); applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, 16)); return; }
      if (e.key === '6') { e.preventDefault(); applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, 32)); return; }
      return;
    }

    // 数字键 0 ~ 9 直接输入品数 (支持两位数输入如 12, 15, 24 品)
    if (/^[0-9]$/.test(e.key) && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault();
      if (isPlaying || startingPlayback) {
        studioMessageType = 'warning';
        studioMessage = '播放中暂不录入品位；请先按空格暂停，再输入音符。';
        return;
      }
      fretInput.push(e.key);
      return;
    }

    // 方向键移动光标
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (cursor.stringIndex > 1) cursor = { ...cursor, stringIndex: cursor.stringIndex - 1 };
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      const maxString = currentTrack?.tuning?.length || 6;
      if (cursor.stringIndex < maxString) cursor = { ...cursor, stringIndex: cursor.stringIndex + 1 };
      return;
    }
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      retreatCursor();
      return;
    }
    if (e.key === 'ArrowRight') {
      e.preventDefault();
      advanceCursor();
      return;
    }

    // Shift+Delete 删除一拍；普通 Delete / Backspace 删除当前弦的音符。
    if (e.key === 'Delete' && e.shiftKey) {
      e.preventDefault();
      handleDeleteBeat();
      return;
    }
    if (e.key === 'Delete' || e.key === 'Backspace') {
      e.preventDefault();
      const next = deleteNote(
        project,
        cursor.trackIndex,
        cursor.barIndex,
        cursor.beatIndex,
        cursor.stringIndex
      );
      applyChange(next);
      return;
    }

    if (e.key === '.') { applyChange(toggleBeatDot(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex)); return; }
    if (e.key === '/') { applyChange(toggleBeatTriplet(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex)); return; }
    if (e.key === 'r' || e.key === 'R') { applyChange(toggleBeatRest(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex)); return; }

    // 演奏技巧键位 (H, S, B, P, X, V)
    const keyLower = e.key.toLowerCase();
    if (keyLower === 'l') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'tie')); return; }
    if (keyLower === 'h') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'hammerPull')); return; }
    if (keyLower === 's') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'slide')); return; }
    if (keyLower === 'b') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'bend')); return; }
    if (keyLower === 'n') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'harmonic')); return; }
    if (keyLower === 'p') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'palmMute')); return; }
    if (keyLower === 'x') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'dead')); return; }
    if (keyLower === 'v') { applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, 'vibrato')); return; }

    if (e.key === 'Insert') {
      e.preventDefault();
      if (e.shiftKey) {
        handleInsertBeat();
      } else {
        applyChange(insertBarAfter(project, cursor.barIndex));
        cursor = { ...cursor, barIndex: cursor.barIndex + 1, beatIndex: 0 };
      }
      return;
    }

  }

  // 5. 播放控制 (双引擎调度：AlphaTab 原生 + studioAudio 物理引擎无缝降级)
  async function togglePlay() {
    fretInput.flush();
    if (isPlaying || startingPlayback) {
      playbackGeneration++;
      startingPlayback = false;
      isPlaying = false;
      try {
        alphaTabApi?.pause();
      } catch {}
      nativeFocusRelease?.();
      nativeFocusRelease = null;
      studioAudio.stopPlayback();
    } else {
      const generation = ++playbackGeneration;
      startingPlayback = true;
      let alphaTabPlayed = false;
      try {
        if (alphaTabApi && nativeAudioReady && alphaTabApi.isReadyForPlayback) {
          const release = await claimAudioFocus('studio-native', () => {
            playbackGeneration++;
            startingPlayback = false;
            isPlaying = false;
            try { alphaTabApi?.pause(); } catch {}
            nativeFocusRelease = null;
          });
          if (generation !== playbackGeneration) { release(); return; }
          nativeFocusRelease = release;
          if (alphaTabApi.score) {
            const track = alphaTabApi.score.tracks[cursor.trackIndex] || alphaTabApi.score.tracks[0];
            const stave = track?.staves[0];
            const bar = stave?.bars[cursor.barIndex];
            const beat = bar?.voices[0]?.beats[cursor.beatIndex] || bar?.voices[0]?.beats[0];
            if (beat && beat.absolutePlaybackStart != null) {
              alphaTabApi.tickPosition = beat.absolutePlaybackStart;
            }
          }
          alphaTabPlayed = !!alphaTabApi.play();
          if (alphaTabPlayed) isPlaying = true;
          else { nativeFocusRelease?.(); nativeFocusRelease = null; }
        }
        if (!alphaTabPlayed && generation === playbackGeneration) {
          await startFallbackPlayback(cursor.barIndex, cursor.beatIndex, countIn, generation);
        }
      } catch (error) {
        nativeFocusRelease?.(); nativeFocusRelease = null;
        if (generation === playbackGeneration) {
          isPlaying = false;
          studioMessageType = 'error';
          studioMessage = `播放未开始：${error instanceof Error ? error.message : String(error)}`;
        }
      } finally {
        if (generation === playbackGeneration) startingPlayback = false;
      }
    }

  }

  async function startFallbackPlayback(startBar: number, startBeat: number, withCountIn = false, generation = playbackGeneration) {
    const started = await studioAudio.startPlayback(
      project,
      startBar,
      startBeat,
      (barIdx, beatIdx) => {
        cursor = { ...cursor, barIndex: barIdx, beatIndex: beatIdx };
      },
      () => {
        if (hasLoop && generation === playbackGeneration) {
          void startFallbackPlayback(0, 0, false, generation).catch((error) => {
            isPlaying = false;
            studioMessageType = 'error';
            studioMessage = `循环播放已暂停：${error instanceof Error ? error.message : String(error)}`;
          });
        } else {
          isPlaying = false;
          cursor = { ...cursor, barIndex: 0, beatIndex: 0 };
        }
      },
      cursor.trackIndex,
      metronome,
      withCountIn,
      () => { playbackGeneration++; isPlaying = false; startingPlayback = false; }
    );
    if (generation !== playbackGeneration) { studioAudio.stopPlayback(); return; }
    isPlaying = started;
    if (!started) throw new Error('工坊播放引擎或音频焦点不可用');
  }

  function stopPlay(options: { resetCursor?: boolean; pauseNative?: boolean } = {}) {
    fretInput.flush();
    playbackGeneration++;
    startingPlayback = false;
    isPlaying = false;
    try {
      if (options.pauseNative) alphaTabApi?.pause();
      else alphaTabApi?.stop();
    } catch {}
    nativeFocusRelease?.(); nativeFocusRelease = null;
    studioAudio.stopPlayback();
    // AlphaTab can publish its pause/stop event synchronously; the command wins
    // over any intermediate player-state callback.
    startingPlayback = false;
    isPlaying = false;
    if (options.resetCursor !== false) cursor = { ...cursor, barIndex: 0, beatIndex: 0 };
  }

  // 6. 导出与发布
  async function handleExportImage() {
    fretInput.flush();
    try {
      const { exportScoreToImage } = await import('../../lib/printScore');
      if (!alphaTabApi) throw new Error('乐谱渲染器尚未就绪');
      await exportScoreToImage(alphaTabApi, project.title);
      studioMessageType = 'success';
      studioMessage = '长图已生成并发起下载，请确认文件保存在设备中。';
    } catch (e) {
      studioMessageType = 'error';
      studioMessage = `导出长图失败：${e instanceof Error ? e.message : String(e)}`;
    }
  }

  async function handleExportPdf() {
    fretInput.flush();
    try {
      const { downloadPdf } = await import('../../lib/printScore');
      if (!alphaTabApi?.score) throw new Error('乐谱尚未载入，请等待排版完成后重试。');
      await downloadPdf(alphaTabApi.score, project.title, project.artist);
      studioMessageType = 'success';
      studioMessage = 'A4 分页 PDF 已生成并发起下载，请确认文件保存在设备中。';
    } catch (e) {
      studioMessageType = 'error';
      studioMessage = `导出 PDF 失败：${e instanceof Error ? e.message : String(e)}`;
    }
  }

  async function handleSaveDraft() {
    fretInput.flush();
    studioMessageType = 'success';
    studioMessage = '正在保存个人草稿…';
    await persistProject(project);
  }

  async function handleAddProjectToPractice() {
    fretInput.flush();
    const currentProject = project;
    const ticket = ++persistenceRevision;
    practiceDestination = null;
    studioMessageType = 'warning';
    studioMessage = '正在把当前可编辑工程转换为完整 IBE 练习谱，并与工程一起保存；导入原件继续单独保留。';
    try {
      await saveBoundary.track(saveStudioProjectForPractice(currentProject));
      if (ticket === persistenceRevision) {
        practiceDestination = { projectId: currentProject.id, href: `/practice?score=${encodeURIComponent(`project:${currentProject.id}`)}` };
        studioMessageType = currentProject.importWarnings?.length ? 'warning' : 'success';
        studioMessage = currentProject.importWarnings?.length
          ? `「${currentProject.title || '未命名乐谱'}」已加入待练。练习谱采用工坊可编辑内容；${currentProject.importWarnings.length} 项导入转换提醒仍适用，原始文件已保留。`
          : `「${currentProject.title || '未命名乐谱'}」已保存并加入待练，可在我的谱和我的练习中打开。`;
      }
    } catch (error) {
      if (ticket === persistenceRevision) {
        studioMessageType = 'error';
        studioMessage = `加入待练失败：${error instanceof Error ? error.message : String(error)}。当前编辑内容仍保留在工坊，可导出工程 JSON 或 IBE 后重试。`;
      }
    }
  }

  async function handleExportFile(format: 'json' | 'ibe' | 'gp' | 'tex') {
    fretInput.flush();
    try {
      await exportStudioProjectFile(project, format);
      studioMessageType = 'success';
      const labels = { json: '工程 JSON', ibe: 'MIMI IBE', gp: 'Guitar Pro 7', tex: 'AlphaTex' };
      studioMessage = `${labels[format]}文件已导出。`;
    } catch (e) {
      studioMessageType = 'error';
      studioMessage = `导出失败：${e instanceof Error ? e.message : String(e)}`;
    }
  }

  async function handleImportFile(file: File): Promise<boolean> {
    if (file.size > 30 * 1024 * 1024) {
      studioMessageType = 'error';
      studioMessage = '单个乐谱文件不能超过 30 MB。';
      return false;
    }
    isImporting = true;
    try {
      await settleProjectSaves();
      const imported = await importStudioScoreFile(file);
      const source = imported.project.source;
      if (!source) throw new Error('导入结果缺少原始文件信息。');
      const bytes = new Uint8Array(await file.arrayBuffer());
      persistenceRevision++;
      await saveBoundary.track(saveStudioProject(imported.project, { id: source.id, fileName: file.name, mimeType: file.type, bytes }));
      stopPlay();
      const saved = applyChange(imported.project, undefined, false);
      cursor = { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1 };
      studioMessageType = imported.warnings.length ? 'warning' : (saved ? 'success' : 'error');
      studioMessage = imported.warnings.length
        ? `已保留原始文件并导入可编辑部分；发现 ${imported.warnings.length} 项需检查内容。${saved ? '' : ' 草稿保存失败，请导出工程 JSON。'}`
        : saved ? `已保留原始文件，并载入「${imported.project.title}」。` : '已保留原始文件，但草稿保存失败，请立即导出工程 JSON。';
      return true;
    } catch (e) {
      studioMessageType = 'error';
      studioMessage = `导入失败，当前工程未被替换：${e instanceof Error ? e.message : String(e)}`;
      return false;
    } finally {
      isImporting = false;
    }
  }

  async function handleDownloadSource() {
    const source = project.source;
    if (!source) return;
    try {
      const stored = await getOriginalScoreFile(source.id);
      if (stored) {
        downloadStoredOriginalScore(stored);
      } else if (source.kind === 'file') {
        if (!stored) throw new Error('本机原始文件备份不存在。可能已清理网站数据，请从原位置重新导入。');
      } else {
        const metadataResponse = await fetch(`/api/tabs/${encodeURIComponent(source.id)}`);
        if (!metadataResponse.ok) throw new Error('原谱目录不可用，请从备份恢复原始文件。');
        const metadata = await metadataResponse.json();
        if (!isSafeLocalPath(metadata.scoreUrl)) throw new Error('原谱路径不可用。');
        const response = await fetch(metadata.scoreUrl);
        if (!response.ok) throw new Error(`原谱服务器返回 ${response.status}`);
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = source.fileName;
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
        window.setTimeout(() => URL.revokeObjectURL(url), 2000);
      }
      studioMessageType = 'success';
      studioMessage = '原始文件下载已发起，请确认文件保存在设备中。';
    } catch (e) {
      studioMessageType = 'error';
      studioMessage = `下载原始文件失败：${e instanceof Error ? e.message : String(e)}`;
    }
  }

  async function handleDeleteDraft(id: string) {
    if (id === project.id) throw new Error('这份工程正在编辑，请先新建或载入其他工程后再删除。');
    await settleProjectSaves();
    await deleteStudioProject(id);
    // Original-file backups deliberately outlive draft deletion; a checkpoint is not the source artifact.
  }

  function handleApplyLyrics(command: StudioLyricsCommand) {
    applyChange(applyStudioLyricsCommand(project, studioRevision, command));
  }

  async function handleLoadDraft(value: StudioProject): Promise<boolean> {
    await settleProjectSaves();
    stopPlay();
    rememberStudioProjectVersion(value);
    applyChange(value, undefined, false);
    cursor = { trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1 };
    studioMessage = `已载入「${value.title || '未命名乐谱'}」，可以继续编辑。`;
    return true;
  }
</script>

{#if isInitializing}<p role="status" class="mb-3 text-sm text-ash">正在读取个人工程，请稍候…</p>{/if}
<div inert={isInitializing || isSwitchingProject} aria-busy={isInitializing || isImporting || isSwitchingProject} class="w-full text-[#2c2825] flex flex-col font-sans select-none relative space-y-5">
  <!-- 1. 顶部控制栏 (Top: StudioHeader & StudioToolbar) -->
  <div class="w-full relative rounded-3xl border border-[#e2d8c3] bg-[#f8f5ee]/95 shadow-[0_4px_20px_rgba(76,59,43,0.05)] backdrop-blur-md z-30">
    <StudioHeader
      {project}
      selectedTrackIndex={cursor.trackIndex}
      {isPlaying}
      canUndo={undoStack.length > 0}
      canRedo={redoStack.length > 0}
      {hasLoop}
      {metronome}
      {countIn}
      onTogglePlay={togglePlay}
      onStop={stopPlay}
      onToggleLoop={() => (hasLoop = !hasLoop)}
      onToggleMetronome={() => (metronome = !metronome)}
      onToggleCountIn={() => (countIn = !countIn)}
      onUndo={handleUndo}
      onRedo={handleRedo}
      onOpenMixer={() => selectBottomTab('mixer')}
      onOpenLyrics={() => openStudioDialog('lyrics')}
      onOpenShortcuts={() => openStudioDialog('shortcuts')}
      onOpenGuide={() => openStudioDialog('guide')}
      onOpenDrafts={() => openStudioDialog('drafts')}
      onDownloadSource={handleDownloadSource}
      onNewProject={handleNewProject}
      onSaveDraft={handleSaveDraft}
      onAddToPractice={handleAddProjectToPractice}
      onExportFile={handleExportFile}
      onExportImage={handleExportImage}
      onExportPdf={handleExportPdf}
      onUpdateProject={applyChange}
    />

    {#if studioMessage}
      <div class="mx-3 my-2 flex items-start justify-between gap-3 rounded-xl px-3 py-2 text-xs {studioMessageType === 'error' ? 'bg-[#fff4ef] text-[#8d3b27]' : studioMessageType === 'warning' ? 'bg-[#fff8e8] text-[#765514]' : 'bg-[#eef8f0] text-[#2e6b39]'}" role={studioMessageType === 'error' ? 'alert' : 'status'}>
        <span>{isImporting ? '正在读取谱面…' : studioMessage}{#if practiceDestination?.projectId === project.id && studioMessageType !== 'error'}<a href={practiceDestination.href} class="ml-3 inline-flex min-h-[44px] items-center rounded-lg px-2 font-bold underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2">进入练习：A-B、提速与记录</a>{/if}</span>
        <button type="button" class="shrink-0 font-bold min-w-[44px] min-h-[44px] rounded-lg focus-visible:outline-2 focus-visible:outline-offset-2" aria-label="关闭提示" onclick={() => (studioMessage = '')}>✕</button>
      </div>
    {/if}

    {#if project.importWarnings?.length}
      <details class="mx-3 mb-3 rounded-2xl border border-[#d8bd76] bg-[#fff8e8] text-[#654c17]">
        <summary class="cursor-pointer px-4 py-3 text-xs font-bold">
          导入转换报告 · {project.importWarnings.length} 项需要检查。完整内容仍保存在原始文件备份中。
        </summary>
        <ul class="px-7 pb-4 list-disc space-y-1.5 text-xs leading-relaxed">
          {#each project.importWarnings as warning}
            <li>{warning}</li>
          {/each}
        </ul>
      </details>
    {/if}

    <!-- 音符时值与演奏技巧工具栏 -->
    <StudioToolbar
      {currentDuration}
      {hasDot}
      {hasTriplet}
      {isRest}
      {isChordMode}
      {activeTechniques}
      onSetDuration={(dur) => applyChange(setBeatDuration(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, dur))}
      onToggleDot={() => applyChange(toggleBeatDot(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex))}
      onToggleTriplet={() => applyChange(toggleBeatTriplet(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex))}
      onToggleRest={() => applyChange(toggleBeatRest(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex))}
      onToggleChordMode={() => (isChordMode = !isChordMode)}
      onToggleTechnique={(tech) => applyChange(toggleNoteTechnique(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, cursor.stringIndex, tech as any))}
      onInsertBeat={handleInsertBeat}
      onDeleteBeat={handleDeleteBeat}
      onInsertBar={() => {
        applyChange(insertBarAfter(project, cursor.barIndex));
        cursor.barIndex++;
        cursor.beatIndex = 0;
      }}
      onDuplicateBar={() => {
        applyChange(duplicateBar(project, cursor.barIndex));
        cursor.barIndex++;
      }}
      onDeleteBar={() => {
        applyChange(deleteBar(project, cursor.barIndex));
        cursor.barIndex = Math.max(0, cursor.barIndex - 1);
      }}
      onSetSection={(sec) => applyChange(updateBarMeta(project, cursor.barIndex, { section: sec }))}
    />
  </div>

  <!-- 2. 中部主编辑区 (Middle: ScoreCanvas with Manuscript paper styling & measure control overlays) -->
  <main id="studio-main" tabindex="-1" class="w-full flex flex-col items-center relative z-10 focus-visible:outline-2 focus-visible:outline-[#966b1a] focus-visible:outline-offset-4">
    {#if currentTiming?.isOverflow || currentTiming?.isUnderflow}
      <div class="w-full mb-3 rounded-xl border border-[#c49a45]/40 bg-[#fff8e8] px-4 py-2 text-xs text-[#765514]" role="status">
        {#if currentTiming.isOverflow}
          当前小节时值超出拍号：{currentTiming.totalDuration.toFixed(2)} 拍，预期 {currentTiming.expectedDuration.toFixed(2)} 拍。可删拍或调整音符时值。
        {:else}
          当前小节尚未填满：{currentTiming.totalDuration.toFixed(2)} / {currentTiming.expectedDuration.toFixed(2)} 拍。可继续输入音符或休止符。
        {/if}
      </div>
    {/if}
    <div class="w-full">
      <ScoreCanvas
        {project}
        {cursor}
        {isPlaying}
        {hasLoop}
        {metronome}
        {countIn}
        keyboardEnabled={!activeStudioDialog && !isInitializing && !isImporting && !isSwitchingProject}
        onKeyboardBoundary={() => fretInput.flush()}
        onCursorChange={(pos) => (cursor = pos)}
        onKeyDown={handleKeyDown}
        onApiReady={(api) => (alphaTabApi = api)}
        onAudioReady={(ready) => (nativeAudioReady = ready)}
        onPlayerStateChange={(statePlaying) => {
          if (!statePlaying && nativeFocusRelease) { nativeFocusRelease(); nativeFocusRelease = null; }
          isPlaying = statePlaying || studioAudio.active;
        }}
        onInsertBar={() => {
          applyChange(insertBarAfter(project, cursor.barIndex));
          cursor = { ...cursor, barIndex: cursor.barIndex + 1, beatIndex: 0 };
        }}
        onDuplicateBar={() => {
          applyChange(duplicateBar(project, cursor.barIndex));
          cursor = { ...cursor, barIndex: cursor.barIndex + 1 };
        }}
        onDeleteBar={() => {
          applyChange(deleteBar(project, cursor.barIndex));
          cursor = { ...cursor, barIndex: Math.max(0, cursor.barIndex - 1) };
        }}
        onClearBar={handleClearBar}
      />
    </div>
  </main>

  <!-- 3. 底部停靠式可折叠工作台抽屉 (Bottom: Docked Collapsible Studio Drawer) -->
  <footer class="w-full bg-[#fbf9f4]/98 border border-[#e4dbcc] rounded-3xl p-3.5 sm:p-5 z-20 flex flex-col gap-3 backdrop-blur-xl shadow-lg">
    <!-- 抽屉顶部控制与标签切换 -->
    <div class="flex flex-wrap items-center justify-between gap-2 border-b border-[#e8dfcf] pb-2.5">
      <div bind:this={bottomControls} class="flex flex-wrap items-center gap-2 min-w-0">
        <!-- 折叠/展开切换按键 -->
        <button
          type="button"
          bind:this={bottomToggle}
          id="studio-workbench-toggle"
          aria-expanded={!isBottomDrawerCollapsed}
          aria-controls="studio-workbench-panel"
          onclick={toggleBottomDrawer}
          class="inline-flex items-center gap-1.5 min-h-[44px] min-w-[44px] px-3 py-1.5 rounded-xl bg-[#2c2825] text-[#faf8f5] hover:bg-[#c49a45] hover:text-[#2c2825] transition-colors text-xs font-serif font-bold shadow-xs cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#966b1a]"
          title={isBottomDrawerCollapsed ? '展开底部指板与和弦工作台' : '收起底部工作台'}
        >
          <span>{isBottomDrawerCollapsed ? '▲' : '▼'}</span>
          <span>{isBottomDrawerCollapsed ? '展开打谱抽屉' : '收起工作台'}</span>
        </button>

        <!-- 标签页切换 -->
        <MotionSegmentedControl id="studio-workbench-controls" value={activeBottomTab} options={bottomOptions} onChange={selectBottomTab} label="工作台视图" />
      </div>

      <!-- 快捷键与打谱模式提示 -->
      <div class="text-[11px] text-[#8c7b68] font-mono hidden md:flex items-center gap-2 font-serif">
        <span>键盘按 <kbd class="px-1.5 py-0.5 bg-[#ede5d8] rounded border border-[#dfd6c7] text-[#966b1a] font-bold font-mono">0-24</kbd> 输入品数</span>
        <span>·</span>
        <span>按 <kbd class="px-1.5 py-0.5 bg-[#ede5d8] rounded border border-[#dfd6c7] text-[#966b1a] font-bold font-mono">Space</kbd> 播放</span>
        <span>·</span>
        <span>按 <kbd class="px-1.5 py-0.5 bg-[#ede5d8] rounded border border-[#dfd6c7] text-[#966b1a] font-bold font-mono">Alt+1..6</kbd> 切时值</span>
      </div>
    </div>

    <!-- 抽屉展开内容区 -->
    <div id="studio-workbench-panel" bind:this={bottomPanel} inert={isBottomDrawerCollapsed}>
      {#if !isBottomDrawerCollapsed}
      <div class="w-full grid items-start" use:registerMotionSurface transition:surfaceMotion={{ kind: 'panel', y: 8, scale: 1 }}>
        <div class="col-start-1 row-start-1 min-w-0" inert={activeBottomTab !== 'workbench'}>
        {#if activeBottomTab === 'workbench'}
          <!-- 左右联动打谱工作区：左侧和弦调色盘 (含 C, Am, F, G, Dm, Em 快速注入)，右侧 24 品实况指板 -->
          <div class="grid grid-cols-1 lg:grid-cols-12 gap-3.5 items-stretch" use:registerMotionSurface transition:fadeMotion={{ kind: 'menu' }}>
            <!-- 左侧：和弦调色盘 -->
            <div class="lg:col-span-5 xl:col-span-4 flex flex-col">
              <ChordPalette
                track={currentTrack}
                onChordSelect={(name, notes) => {
                  let next = setBeatChord(project, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, name);
                  notes.forEach((n) => {
                    next = setNoteFret(next, cursor.trackIndex, cursor.barIndex, cursor.beatIndex, n.string, n.fret);
                  });
                  applyChange(next);
                  advanceCursor();
                }}
              />
            </div>

            <!-- 右侧：24品实况吉他指板 -->
            <div class="lg:col-span-7 xl:col-span-8 flex flex-col">
              <VirtualFretboard
                track={currentTrack}
                {activeNotes}
                onFretClick={(strNum, fret) => {
                  fretInput.flush();
                  cursor.stringIndex = strNum;
                  inputFretNumber(fret);
                }}
              />
            </div>
          </div>
        {/if}
        </div>
        <div class="col-start-1 row-start-1 min-w-0" inert={activeBottomTab !== 'mixer'}>
        {#if activeBottomTab === 'mixer'}
          <div class="w-full max-w-5xl mx-auto" use:registerMotionSurface transition:fadeMotion={{ kind: 'menu' }}>
            <TrackMixer
              {project}
              selectedTrackIndex={cursor.trackIndex}
              onSelectTrack={selectStudioTrack}
              onUpdateProject={applyChange}
            />
          </div>
        {/if}
        </div>
      </div>
      {/if}
    </div>
  </footer>

  <!-- 歌词抽屉 -->
  <LyricsDrawer
    isOpen={activeStudioDialog === 'lyrics'}
    {project}
    {studioRevision}
    selectedTrackIndex={cursor.trackIndex}
    fallbackFocusSelector="#studio-main"
    onClose={() => closeStudioDialog('lyrics')}
    onApplyLyrics={handleApplyLyrics}
  />

  <!-- 快捷键速查模态框 -->
  <ShortcutHelpModal
    isOpen={activeStudioDialog === 'shortcuts'}
    fallbackFocusSelector="#studio-main"
    onClose={() => closeStudioDialog('shortcuts')}
  />

  <StudioGuide
    isOpen={activeStudioDialog === 'guide'}
    fallbackFocusSelector="#studio-main"
    onClose={() => closeStudioDialog('guide')}
  />

  <!-- 本地草稿箱模态框 -->
  <DraftsModal
    isOpen={activeStudioDialog === 'drafts'}
    fallbackFocusSelector="#studio-main"
    onClose={() => closeStudioDialog('drafts')}
    beforeLoad={settleProjectSaves}
    activeProjectId={project.id}
    onImportFile={handleImportFile}
    onDeleteDraft={handleDeleteDraft}
    onLoadProject={handleLoadDraft}
  />
</div>
