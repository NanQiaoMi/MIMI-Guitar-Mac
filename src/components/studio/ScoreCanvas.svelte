<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { AlphaTabApi, NotationElement, StaveProfile } from '@coderline/alphatab';
  import { createScoreSettings, installScoreLayoutFixes } from '../../lib/playerSettings';
  import { projectToAlphaTex, type StudioProject, type CursorPosition } from '../../lib/studio/studioScoreModel';
  import { studioCursorAtClientPoint, studioCursorFromBeat } from '../../lib/studio/scoreBounds';
  import { isStudioKeyboardTargetBlocked, shouldHandleStudioCanvasShortcut } from '../../lib/studio/studioKeyboardScope';
  import { loadVerifiedScoreSoundfontPlan } from '../../lib/player/verifiedScoreSoundfont.ts';
  import { loadSoundfontWithReceipt } from '../../lib/player/soundfontLoadReceipt.ts';

  let {
    project,
    cursor,
    isPlaying = false,
    hasLoop = false,
    metronome = false,
    countIn = false,
    keyboardEnabled = true,
    onCursorChange,
    onKeyDown,
    onKeyboardBoundary,
    onApiReady,
    onAudioReady,
    onPlayerStateChange,
    onInsertBar,
    onDuplicateBar,
    onDeleteBar,
    onClearBar,
  }: {
    project: StudioProject;
    cursor: CursorPosition;
    isPlaying: boolean;
    hasLoop?: boolean;
    metronome?: boolean;
    countIn?: boolean;
    keyboardEnabled?: boolean;
    onCursorChange?: (pos: CursorPosition) => void;
    onKeyDown?: (e: KeyboardEvent) => void;
    onKeyboardBoundary?: () => void;
    onApiReady?: (api: AlphaTabApi) => void;
    onAudioReady?: (ready: boolean) => void;
    onPlayerStateChange?: (playing: boolean) => void;
    onInsertBar?: () => void;
    onDuplicateBar?: () => void;
    onDeleteBar?: () => void;
    onClearBar?: () => void;
  } = $props();

  let canvasWrapper: HTMLDivElement | null = $state(null);
  let container: HTMLDivElement | null = $state(null);
  let api: AlphaTabApi | null = $state(null);
  let renderDebounceTimer: any = null;
  let renderState: 'loading' | 'ready' | 'error' = $state('loading');
  let renderError = $state('');
  let rendererInitialized = $state(false);
  let disposed = false;
  let soundError = $state('');
  let soundGeneration = 0;
  let soundAbort: AbortController | null = null;
  let soundQueue: Promise<void> = Promise.resolve();
  let cancelSoundWait: (() => void) | null = null;
  const loadedSoundUrls = new Set<string>();

  function waitForPlayerReady(currentApi: AlphaTabApi): Promise<void> {
    return new Promise((resolve, reject) => {
      let off = () => {};
      let settled = false;
      const finish = (cause?: Error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout); off(); cancelSoundWait = null;
        if (cause) reject(cause); else resolve();
      };
      const timeout = setTimeout(() => finish(new Error('工坊音源准备超时，请重新打开工坊后重试。')), 15000);
      cancelSoundWait = () => finish(new Error('音源准备已取消'));
      off = currentApi.playerReady.on(() => finish());
    });
  }

  function prepareSoundfonts(currentApi: AlphaTabApi, programs: number[]) {
    const generation = ++soundGeneration;
    soundAbort?.abort();
    cancelSoundWait?.();
    const controller = new AbortController();
    soundAbort = controller;
    onAudioReady?.(false);
    soundError = '';
    const current = () => !disposed && api === currentApi && generation === soundGeneration;
    soundQueue = soundQueue.catch(() => {}).then(async () => {
      if (!current()) return;
      if (!currentApi.player?.isReady) await waitForPlayerReady(currentApi);
      // Studio instrument selections are explicit GM programs. Tuning affects
      // pitch only; four strings must not replace a piano or guitar with uke.
      if (programs.length === 0) throw new Error('当前作品没有可播放的乐器音轨。');
      const soundfonts = await loadVerifiedScoreSoundfontPlan(programs.map((program) => ({
        bank: program === 128 ? 128 : 0,
        program: program === 128 ? 0 : program,
        flavor: 'gm' as const,
      })), controller.signal);
      for (const { url, bytes } of soundfonts) {
        if (!current()) return;
        if (loadedSoundUrls.has(url)) continue;
        const receipt = await loadSoundfontWithReceipt(currentApi, bytes, false, { signal: controller.signal });
        if (receipt.status !== 'loaded') {
          if (receipt.status === 'cancelled') throw new DOMException('音源准备已取消', 'AbortError');
          throw receipt.error ?? new Error('工坊音源未能完成加载，请重新打开工坊后重试。');
        }
        if (!current()) return;
        loadedSoundUrls.add(url);
      }
      if (current()) onAudioReady?.(true);
    }).catch((cause) => {
      if (current()) soundError = cause instanceof Error ? cause.message : '伴奏音源尚未准备好。';
    });
  }

  // AlphaTab owns the hit-test geometry; SVG parsing is not used to infer beats.
  function applyAlphaTabCursor(beat: any, note?: any) {
    if (!keyboardEnabled) return;
    onKeyboardBoundary?.();
    const next = studioCursorFromBeat(beat, project, cursor.stringIndex, note);
    if (next) commitPointerCursor(next);
  }

  function commitPointerCursor(next: CursorPosition) {
    focusCanvasWrapper();
    onCursorChange?.(next);
  }

  function focusCanvasWrapper() {
    if (!keyboardEnabled) return;
    canvasWrapper?.focus({ preventScroll: true });
  }

  /** 平滑滚动画布视口，确保当前小节与指针保持在视野中 */
  let lastScrolledBarIdx = -1;
  function scrollToActiveCursor() {
    if (!container) return;
    const beatEl = container.querySelector('.at-cursor-beat') as HTMLElement;
    const barEl = container.querySelector('.at-cursor-bar') as HTMLElement;
    const target = beatEl || barEl;
    if (!target) return;

    const rect = target.getBoundingClientRect();
    const viewportHeight = window.innerHeight;

    // 当光标进入新行或超出舒适视口时，平滑滚动使光标居中保持可见
    if (rect.bottom > viewportHeight - 140 || rect.top < 120) {
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  // 1. 初始化 AlphaTab 引擎
  onMount(async () => {
    if (!container || typeof window === 'undefined') return;

    try {
      installScoreLayoutFixes();
      const settings = createScoreSettings();
      settings.core.includeNoteBounds = true;
      settings.display.scale = 0.95;
      settings.display.layoutMode = 0; // LayoutMode.Page = 0 (分页流式排版)
      settings.display.staveProfile = StaveProfile.ScoreTab;
      settings.importer.beatTextAsLyrics = true;
      settings.notation.elements.set(NotationElement.ScoreCopyright, false);
      settings.player.enablePlayer = true;
      settings.player.enableCursor = true;
      settings.player.enableAnimatedBeatCursor = true;
      settings.player.enableElementHighlighting = true;
      settings.player.enableUserInteraction = true;
      settings.player.soundFont = '';
      settings.player.scrollElement = '#studio-score-scroll';
      settings.player.scrollMode = 1; // ScrollMode.OffScreen
      settings.player.scrollSpeed = 250;

      // 黄金比例 16.5 弦距（实测约 14.2px 疏朗弦距，品数清晰透亮）
      if (settings.display.resources?.engravingSettings) {
        settings.display.resources.engravingSettings.tabLineSpacing = 16.5;
      }

      // 先阻止 AlphaTab 构造函数创建默认播放器，确保 Worker 工厂注入后只创建一个实例
      const configuredPlayerMode = settings.player.playerMode;
      const configuredEnablePlayer = settings.player.enablePlayer;
      settings.player.enablePlayer = false;
      settings.player.playerMode = 0; // PlayerMode.Disabled

      const alphaTabInstance = new AlphaTabApi(container, settings);
      api = alphaTabInstance;
      (window as any).__studioApi = alphaTabInstance;
      onApiReady?.(alphaTabInstance);
      alphaTabInstance.beatMouseDown.on((beat: any) => applyAlphaTabCursor(beat));
      alphaTabInstance.beatMouseUp.on((beat: any) => { if (beat) applyAlphaTabCursor(beat); });
      alphaTabInstance.noteMouseDown.on((note: any) => applyAlphaTabCursor(note?.beat, note));

      // 覆盖底层 Web Worker 工厂：使用绝对路径运行时，避免相对路径/模块解析造成音源初始化失败
      const facade = (alphaTabInstance as any).uiFacade;
      if (facade?.constructor) {
        facade.constructor.createAlphaSynthWebWorker = function () {
          const code = `
            importScripts(location.origin + '/alphaTab.js');
          `;
          const blob = new Blob([code], { type: 'application/javascript' });
          return new Worker(URL.createObjectURL(blob));
        };
      }

      settings.player.enablePlayer = configuredEnablePlayer;
      settings.player.playerMode = configuredPlayerMode;
      (alphaTabInstance as any)._setupOrDestroyPlayer();

      // 编辑态始终让五线谱与 TAB 显示同一批音高，并预览全部音轨。
      alphaTabInstance.scoreLoaded.on((score) => {
        if (score && score.tracks && score.tracks.length > 0) {
          for (let index = 0; index < score.tracks.length; index++) {
            const studioTrack = project.tracks[index];
            const scoreTrack = score.tracks[index] as any;
            if (!studioTrack || !scoreTrack) continue;
            for (const staff of scoreTrack.staves ?? []) {
              staff.showStandardNotation = true;
              staff.showTablature = true;
            }
            const playback = scoreTrack.playbackInfo;
            if (playback) {
              playback.volume = Math.round(Math.max(0, Math.min(1, studioTrack.volume)) * 15);
              playback.balance = Math.round(Math.max(-1, Math.min(1, studioTrack.pan)) * 7 + 8);
              playback.isMute = studioTrack.mute;
              playback.isSolo = studioTrack.solo;
            }
          }
        }
      });

      // 渲染完成事件触发后立即同步光标
      alphaTabInstance.postRenderFinished.on(() => {
        renderState = 'ready';
        renderError = '';
        if (!isPlaying) {
          syncVisualCursor();
          setTimeout(syncVisualCursor, 40);
          setTimeout(syncVisualCursor, 140);
        }
      });

      // 绑定播放器与时间指针事件
      const playerObj = (alphaTabInstance as any).player || (alphaTabInstance as any)._player;

      const handlePositionChange = (args: any) => {
        // 时间位置更新
      };

      const handleStateChange = (args: any) => {
        const state = args?.state ?? args;
        const playing = state === 1;
        onPlayerStateChange?.(playing);
        if (!playing) {
          setTimeout(syncVisualCursor, 50);
        }
      };

      const handlePlayedBeat = (beat: any) => {
        if (!beat) return;
        const mb = beat.voice?.bar?.masterBar;
        const barIdx = mb ? mb.index : (beat.voice?.bar?.index ?? 0);
        const beatIdx = beat.index ?? 0;

        onCursorChange?.({
          trackIndex: cursor.trackIndex,
          barIndex: Math.max(0, barIdx),
          beatIndex: Math.max(0, beatIdx),
          stringIndex: cursor.stringIndex,
        });

        if (barIdx !== lastScrolledBarIdx) {
          lastScrolledBarIdx = barIdx;
          requestAnimationFrame(scrollToActiveCursor);
        }
      };

      if (playerObj) {
        if (playerObj.timePositionChanged) playerObj.timePositionChanged.on(handlePositionChange);
        if (playerObj.positionChanged) playerObj.positionChanged.on(handlePositionChange);
        if (playerObj.stateChanged) playerObj.stateChanged.on(handleStateChange);
        if (playerObj.playedBeatChanged) playerObj.playedBeatChanged.on(handlePlayedBeat);
      }

      alphaTabInstance.playerPositionChanged?.on(handlePositionChange);
      alphaTabInstance.playerStateChanged?.on(handleStateChange);
      alphaTabInstance.playedBeatChanged?.on(handlePlayedBeat);

      // 监听异常
      alphaTabInstance.error.on((err: any) => {
        console.warn('[ScoreCanvas] alphaTab notice:', err);
        if (err?.type === 0 || err?.type === 1 || err?.type === 2) {
          renderState = 'error';
          renderError = err?.message || 'AlphaTab 无法解析这份编辑工程';
        }
      });

      // AlphaTab installs its partial-render reset in its first animation frame.
      // Rendering before that frame appends stale fragments on fast project loads.
      await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
      if (!disposed && api === alphaTabInstance) rendererInitialized = true;
    } catch (e) {
      console.error('[ScoreCanvas] AlphaTab init failed:', e);
      renderState = 'error';
      renderError = e instanceof Error ? e.message : '乐谱引擎启动失败';
    }
  });

  onDestroy(() => {
    disposed = true;
    soundGeneration++;
    soundAbort?.abort();
    cancelSoundWait?.();
    onAudioReady?.(false);
    if (renderDebounceTimer) clearTimeout(renderDebounceTimer);
    try {
      if ((window as any).__studioApi === api) {
        (window as any).__studioApi = null;
      }
      api?.destroy();
    } catch {}
  });

  // 2. 当 project 发生变更时，防抖重新渲染谱面
  $effect(() => {
    if (api && project && rendererInitialized) {
      const renderApi = api;
      if (renderDebounceTimer) clearTimeout(renderDebounceTimer);
      renderDebounceTimer = setTimeout(() => {
        try {
          renderState = 'loading';
          renderError = '';
          const tex = projectToAlphaTex(project);
          if (!disposed && api === renderApi) renderApi.tex(tex, project.tracks.map((_, index) => index));
        } catch (e) {
          console.warn('[ScoreCanvas] re-render tex error:', e);
          renderState = 'error';
          renderError = e instanceof Error ? e.message : '乐谱更新失败';
        }
      }, 60);
    }
  });

  $effect(() => {
    const programs = [...new Set(project.tracks.map((track) => track.program))];
    if (api && rendererInitialized) prepareSoundfonts(api, programs);
  });

  // 同步外部节拍器 / 预备拍 / 循环设置
  $effect(() => {
    if (api) {
      try {
        api.metronomeVolume = metronome ? 1.0 : 0;
        api.countInVolume = countIn ? 1.0 : 0;
        api.isLooping = hasLoop;
      } catch {}
    }
  });

  // 3. 计算并在打谱编辑态同步小节高光框与打谱指针（播放中由 AlphaTab 引擎独占控制）
  function syncVisualCursor() {
    const scoreContainer = container;
    if (!scoreContainer || isPlaying) return;
    const barEl = scoreContainer.querySelector('.at-cursor-bar') as HTMLElement;
    const beatEl = scoreContainer.querySelector('.at-cursor-beat') as HTMLElement;
    const lookup = (api as any)?.renderer?.boundsLookup;
    const surface = (api as any)?.canvasElement;
    if (!barEl || !beatEl || !surface?.element || !lookup) return;

    const masterBarBounds = lookup.findMasterBarByIndex(cursor.barIndex);
    const trackBarBounds = masterBarBounds?.bars?.find((entry: any) =>
      entry.bar?.staff?.track?.index === cursor.trackIndex && (entry.bar?.staff?.index ?? 0) === 0,
    );
    const beatBounds = trackBarBounds?.beats?.find((entry: any) => entry.beat?.index === cursor.beatIndex);
    const barBounds = masterBarBounds?.lineAlignedBounds;
    if (!barBounds || !beatBounds) return;
    const surfaceRect = surface.element.getBoundingClientRect();
    const containerRect = scoreContainer.getBoundingClientRect();
    const scaleX = surfaceRect.width / (surface.width || surfaceRect.width || 1);
    const scaleY = surfaceRect.height / (surface.height || surfaceRect.height || 1);

    const toContainerPoint = (x: number, y: number) => {
      return {
        x: surfaceRect.left - containerRect.left + x * scaleX,
        y: surfaceRect.top - containerRect.top + y * scaleY,
      };
    };
    const topLeft = toContainerPoint(barBounds.x, barBounds.y);
    const bottomRight = toContainerPoint(barBounds.x + barBounds.w, barBounds.y + barBounds.h);
    const beatPoint = toContainerPoint(beatBounds.onNotesX, barBounds.y);
    const barW = Math.abs(bottomRight.x - topLeft.x);
    const barH = Math.abs(bottomRight.y - topLeft.y);
    if (barW <= 0 || barH <= 0) return;

    barEl.style.transformOrigin = 'top left';
    beatEl.style.transformOrigin = 'top left';
    barEl.style.transform = `translate(${topLeft.x}px, ${topLeft.y}px) scale(${barW / 100}, ${barH / 100})`;
    barEl.style.display = 'block';
    barEl.style.visibility = 'visible';
    barEl.style.opacity = '1';

    beatEl.style.transform = `translate(${beatPoint.x}px, ${topLeft.y}px) scale(0.01, ${barH / 100})`;
    beatEl.style.display = 'block';
    beatEl.style.visibility = 'visible';
    beatEl.style.opacity = '1';
  }

  // 4. 监听 cursor 字段变化
  $effect(() => {
    const _b = cursor?.barIndex;
    const _bt = cursor?.beatIndex;
    const _s = cursor?.stringIndex;
    const _p = isPlaying;
    if (_b !== undefined && !_p) {
      syncVisualCursor();
    }
  });

  // AlphaTab bounds use the full render-surface origin, not each partial SVG's
  // local origin. This mirrors its native mouse-to-bounds coordinate path.
  function handleScorePointerUp(e: PointerEvent) {
    if (!keyboardEnabled) return;
    if (!container || !(e.target instanceof Element)) return;
    const svg = e.target.closest('svg') as SVGSVGElement | null;
    if (!svg || !container.contains(svg)) return;
    const lookup = (api as any)?.renderer?.boundsLookup;
    const surface = (api as any)?.canvasElement?.element as HTMLElement | undefined;
    onKeyboardBoundary?.();
    const next = studioCursorAtClientPoint(lookup, surface ?? null, e.clientX, e.clientY, project, cursor.stringIndex);
    if (next) commitPointerCursor(next);
  }

  function targetKeyboardInfo(target: Element) {
    const editableAncestor = target.closest('[contenteditable]');
    const isContentEditable = target instanceof HTMLElement
      ? target.isContentEditable
      : Boolean(editableAncestor && editableAncestor.getAttribute('contenteditable')?.toLowerCase() !== 'false');

    return {
      tagName: target.tagName,
      role: target.getAttribute('role'),
      isContentEditable,
      hasInteractiveAncestor: Boolean(target.closest(
        'a[href], button, dialog, input, option, select, summary, textarea, [role="button"], [role="link"], [role="menuitem"], [role="tab"], [role="combobox"], [role="textbox"]',
      )),
      hasModalAncestor: Boolean(target.closest('dialog, [role="dialog"], [aria-modal="true"]')),
      hasPopoverAncestor: Boolean(target.closest('[popover], [data-popover]')),
      hasMenuAncestor: Boolean(target.closest('[role="menu"], [role="menubar"], [role="listbox"]')),
      isInert: Boolean(target.closest('[inert]')),
    };
  }

  function isKeyboardBoundaryTarget(target: EventTarget | null): boolean {
    return target instanceof Element && isStudioKeyboardTargetBlocked(targetKeyboardInfo(target));
  }

  // Close the pending fret-entry window before focus or a pointer action leaves editing.
  function handleCanvasFocusOut(event: FocusEvent) {
    const next = event.relatedTarget;
    const remainsInCanvas = next instanceof Node && Boolean(canvasWrapper?.contains(next));
    if (!remainsInCanvas || isKeyboardBoundaryTarget(next)) onKeyboardBoundary?.();
  }

  function handleCanvasPointerDown(event: PointerEvent) {
    if (!keyboardEnabled || isKeyboardBoundaryTarget(event.target)) return;
    onKeyboardBoundary?.();
    focusCanvasWrapper();
  }

  function handleWindowPointerDown(event: PointerEvent) {
    const active = typeof document !== 'undefined' ? document.activeElement : null;
    const canvasHasFocus = active instanceof Node && Boolean(canvasWrapper?.contains(active));
    if (!canvasHasFocus) return;

    const targetInsideCanvas = event.target instanceof Node && Boolean(canvasWrapper?.contains(event.target));
    if (!targetInsideCanvas || isKeyboardBoundaryTarget(event.target)) onKeyboardBoundary?.();
  }

  // Document-level keydown is accepted only while the score region owns focus.
  function handleContainerKeyDown(e: KeyboardEvent) {
    const target = e.target instanceof Element ? e.target : null;
    const active = typeof document !== 'undefined' ? document.activeElement : null;
    const accepted = shouldHandleStudioCanvasShortcut({
      enabled: keyboardEnabled,
      targetInsideCanvas: Boolean(target && canvasWrapper?.contains(target)),
      focusInsideCanvas: active instanceof Node && Boolean(canvasWrapper?.contains(active)),
      targetIsBlocked: !target || isStudioKeyboardTargetBlocked(targetKeyboardInfo(target)),
      modalOpen: Boolean(target?.closest('dialog, [role="dialog"], [aria-modal="true"]')),
      defaultPrevented: e.defaultPrevented,
      isComposing: e.isComposing || e.key === 'Process',
      key: e.key,
    });
    if (!accepted) return;
    onKeyDown?.(e);
  }
</script>

<svelte:window onpointerdown={handleWindowPointerDown} onkeydown={handleContainerKeyDown} />

<!-- 古典宣纸典藏乐谱画布容器 -->
<div
  bind:this={canvasWrapper}
  id="studio-score-scroll"
  class="relative w-full min-h-[560px] bg-[#FAF8F5] rounded-3xl p-4 sm:p-8 border border-[#e8e2d4] shadow-[0_16px_48px_rgba(138,107,41,0.08),0_2px_8px_rgba(138,107,41,0.04)] flex flex-col items-center justify-start overflow-x-auto select-none group cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#c49a45] focus-visible:ring-offset-2"
  role="region"
  aria-label="交互式主乐谱画布"
  tabindex="0"
  onfocusout={handleCanvasFocusOut}
  onpointerdown={handleCanvasPointerDown}
  onpointerup={handleScorePointerUp}
>
  <!-- 宣纸底纹微观噪点质感层 -->
  <div
    class="pointer-events-none absolute inset-0 rounded-3xl opacity-60 mix-blend-multiply"
    style="background-image: radial-gradient(at 100% 0%, rgba(246, 244, 238, 0.9) 0px, transparent 55%), radial-gradient(at 0% 100%, rgba(240, 237, 229, 0.8) 0px, transparent 55%), url(&quot;data:image/svg+xml,%3Csvg viewBox='0 0 64 64' width='64' height='64' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='1' stitchTiles='stitch'/%3E%3CfeColorMatrix type='matrix' values='0 0 0 0 0.15 0 0 0 0 0.13 0 0 0 0 0.1 0 0 0 0 0.038 0'/%3E%3C/filter%3E%3Crect width='64' height='64' filter='url(%23n)'/%3E%3C/svg%3E&quot;); background-repeat: no-repeat, no-repeat, repeat; background-size: cover, cover, 64px 64px;"
  ></div>

  <!-- 典藏四角青铜花角榫 (Corner Bronze Brackets) -->
  <div class="pointer-events-none absolute top-3.5 left-3.5 w-6 h-6 border-t-2 border-l-2 border-[#c49a45]/70 rounded-tl-sm z-20"></div>
  <div class="pointer-events-none absolute top-3.5 right-3.5 w-6 h-6 border-t-2 border-r-2 border-[#c49a45]/70 rounded-tr-sm z-20"></div>
  <div class="pointer-events-none absolute bottom-3.5 left-3.5 w-6 h-6 border-b-2 border-l-2 border-[#c49a45]/70 rounded-bl-sm z-20"></div>
  <div class="pointer-events-none absolute bottom-3.5 right-3.5 w-6 h-6 border-b-2 border-r-2 border-[#c49a45]/70 rounded-br-sm z-20"></div>

  <!-- 谱面上方小节悬浮控制栏 (Measure Control Overlay) -->
  <div class="sticky top-2 z-30 w-full max-w-5xl flex flex-wrap items-center justify-between gap-2 px-3 py-1.5 rounded-2xl bg-[#2c2825]/92 text-[#faf8f5] backdrop-blur-md border border-[#dfd6c7]/40 shadow-lg font-serif text-xs">
    <!-- 当前位置信息胶囊 -->
    <div class="flex min-w-0 flex-wrap items-center gap-2">
      <span class="text-[#e2c178] font-bold font-mono">第 {cursor.barIndex + 1} / {project.bars.length} 小节</span>
      <span class="text-[#8c7b68]">|</span>
      <span class="font-mono">第 {cursor.beatIndex + 1} 拍</span>
      <span class="text-[#8c7b68]">|</span>
      <span class="font-mono text-[#fbfaf7] font-bold">{cursor.stringIndex} 弦</span>
      {#if isPlaying}
        <span class="inline-flex items-center gap-1 text-[11px] text-[#c84b31] font-sans font-bold ml-2">
          <span class="w-2 h-2 rounded-full bg-[#c84b31] animate-ping"></span>
          实况演奏中
        </span>
      {:else}
        <span class="inline-flex items-center gap-1 text-[11px] text-[#8c7b68] font-sans ml-2">
          <span class="w-1.5 h-1.5 rounded-full bg-[#41a1cf]"></span>
          打谱编辑中
        </span>
      {/if}
    </div>

    <!-- 小节快捷管理按钮群 (Measure Action Overlays) -->
    <div class="flex max-w-full flex-wrap items-center justify-end gap-1.5">
      <button
        type="button"
        onclick={(e) => { e.stopPropagation(); onInsertBar?.(); }}
        class="min-h-[44px] min-w-[44px] px-2.5 py-1 rounded-xl bg-[#ede5d8]/20 hover:bg-[#c49a45] hover:text-[#2c2825] transition-all text-[#fbfaf7] font-bold text-[11px] flex items-center gap-1 shadow-2xs"
        title="在当前小节后插入空白小节"
      >
        <span>+</span>
        <span>加小节</span>
      </button>
      <button
        type="button"
        onclick={(e) => { e.stopPropagation(); onDuplicateBar?.(); }}
        class="min-h-[44px] min-w-[44px] px-2.5 py-1 rounded-xl bg-[#ede5d8]/20 hover:bg-[#c49a45] hover:text-[#2c2825] transition-all text-[#fbfaf7] text-[11px] flex items-center gap-1 shadow-2xs"
        title="复制当前小节并插在后面"
      >
        <span>⧉</span>
        <span>复节</span>
      </button>
      <button
        type="button"
        onclick={(e) => { e.stopPropagation(); onClearBar?.(); }}
        class="min-h-[44px] min-w-[44px] px-2 py-1 rounded-xl bg-[#ede5d8]/15 hover:bg-[#ede5d8]/30 transition-all text-[#e2d7c5] text-[11px] shadow-2xs"
        title="清空当前小节音符"
      >
        <span>✕ 清空</span>
      </button>
      <button
        type="button"
        onclick={(e) => { e.stopPropagation(); onDeleteBar?.(); }}
        class="min-h-[44px] min-w-[44px] px-2 py-1 rounded-xl bg-[#c84b31]/30 hover:bg-[#c84b31] text-[#faf8f5] transition-all text-[11px] flex items-center gap-1 shadow-2xs"
        title="删除当前小节"
      >
        <span>🗑️</span>
        <span>删节</span>
      </button>
    </div>
  </div>

  {#if renderState === 'loading'}
    <div class="absolute top-16 left-1/2 -translate-x-1/2 z-20 px-3 py-1.5 rounded-full bg-white/90 border border-[#dfd6c7] text-xs text-[#705c42] shadow-sm" role="status" aria-live="polite">
      正在排版五线谱与六线谱…
    </div>
  {:else if renderState === 'error'}
    <div class="absolute top-16 left-1/2 -translate-x-1/2 z-20 max-w-[90%] px-4 py-2 rounded-2xl bg-[#fff4ef] border border-[#c84b31]/30 text-xs text-[#8d3b27] shadow-sm text-center" role="alert">
      <div class="font-bold">谱面预览失败</div>
      <div class="mt-1 break-words">{renderError}</div>
      <button type="button" class="mt-2 underline" onclick={() => { renderState = 'loading'; renderError = ''; try { api?.tex(projectToAlphaTex(project)); } catch { renderState = 'error'; } }}>重新排版</button>
    </div>
  {/if}

  {#if soundError}<p role="status" class="relative z-20 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">{soundError} 当前可继续编辑和保存谱面。</p>{/if}

  <!-- AlphaTab 主乐谱渲染容器 -->
  <div bind:this={container} class="w-full max-w-5xl z-10 my-4 min-h-[460px] score-studio-canvas"></div>
</div>

<style>
  /* 隐藏 AlphaTab 原生水印与不需要的控件 */
  :global(.score-studio-canvas .at-player-control),
  :global(.score-studio-canvas [data-alphatab-controls]),
  :global(.score-studio-canvas .at-watermark),
  :global(.score-studio-canvas .alphaTab-watermark),
  :global(.score-studio-canvas div:has(> a[href*="alphatab"])),
  :global(.score-studio-canvas .at-surface + div) {
    display: none !important;
    opacity: 0 !important;
    visibility: hidden !important;
    height: 0 !important;
    pointer-events: none !important;
  }

  /* 谱面音符与排版字体颜色：物理深暖炭黑 #1E1A18 */
  :global(.score-studio-canvas svg text) {
    fill: #1E1A18 !important;
    text-rendering: geometricPrecision;
  }

  :global(.score-studio-canvas svg path) {
    fill: #1E1A18;
    stroke: #1E1A18;
    shape-rendering: geometricPrecision;
  }

  /* 播放时的音符与路径经典朱砂红高亮 */
  :global(.score-studio-canvas .at-highlight text),
  :global(.score-studio-canvas text.at-highlight),
  :global(.score-studio-canvas .at-highlight tspan) {
    fill: #c84b31 !important;
    stroke: #c84b31 !important;
    font-weight: 600 !important;
  }

  :global(.score-studio-canvas .at-highlight path),
  :global(.score-studio-canvas path.at-highlight) {
    fill: #c84b31 !important;
    stroke: #c84b31 !important;
  }
</style>
