"use strict";
(() => {
  // src/lib/practice/practiceProgress.ts
  var MIN_ALPHA_TAB_PLAYBACK_RATIO = 0.125;
  var MAX_ALPHA_TAB_PLAYBACK_RATIO = 8;
  function isValidPlaybackRatio(value) {
    return typeof value === "number" && Number.isFinite(value) && value >= MIN_ALPHA_TAB_PLAYBACK_RATIO && value <= MAX_ALPHA_TAB_PLAYBACK_RATIO;
  }
  function isValidPracticeLoopRange(range, scoreEndTick) {
    return Number.isSafeInteger(scoreEndTick) && scoreEndTick > 0 && !!range && Number.isSafeInteger(range.startTick) && Number.isSafeInteger(range.endTick) && range.startTick >= 0 && range.endTick > range.startTick && range.endTick <= scoreEndTick;
  }
  function normalizePracticeLoopSelection(input) {
    const { pointATick, pointABeatEndTick, currentTick, currentBeatEndTick, scoreEndTick } = input;
    if (!Number.isSafeInteger(scoreEndTick) || scoreEndTick <= 0) {
      throw new RangeError("\u5F53\u524D\u8C31\u9762\u66F2\u672B\u65E0\u6548\uFF0C\u65E0\u6CD5\u8BBE\u7F6E A-B \u533A\u95F4\u3002");
    }
    if (!Number.isSafeInteger(pointATick) || pointATick < 0 || pointATick >= scoreEndTick) {
      throw new RangeError("A \u70B9\u5DF2\u8D85\u51FA\u5F53\u524D\u8C31\u9762\u8303\u56F4\uFF0C\u8BF7\u91CD\u65B0\u8BBE\u7F6E A\u3002");
    }
    if (!Number.isSafeInteger(currentTick) || currentTick < 0 || currentTick > scoreEndTick) {
      throw new RangeError("\u5F53\u524D\u4F4D\u7F6E\u5DF2\u8D85\u51FA\u5F53\u524D\u8C31\u9762\u8303\u56F4\uFF0C\u8BF7\u7B49\u5F85\u64AD\u653E\u5668\u540C\u6B65\u540E\u91CD\u8BD5\u3002");
    }
    const isExactScoreEndSelection = currentTick === scoreEndTick && currentBeatEndTick === scoreEndTick;
    if (!Number.isSafeInteger(currentBeatEndTick) || !isExactScoreEndSelection && currentBeatEndTick <= currentTick || currentBeatEndTick > scoreEndTick) {
      throw new RangeError("\u65E0\u6CD5\u786E\u8BA4\u5F53\u524D\u62CD\u672B\uFF0C\u8BF7\u7B49\u5F85\u62CD\u70B9\u4FE1\u606F\u66F4\u65B0\u540E\u91CD\u8BD5\u3002");
    }
    let startTick;
    let endTick;
    if (currentTick >= pointATick) {
      startTick = pointATick;
      endTick = currentBeatEndTick;
    } else {
      if (!Number.isSafeInteger(pointABeatEndTick) || pointABeatEndTick <= pointATick || pointABeatEndTick > scoreEndTick) {
        throw new RangeError("\u5012\u9009\u65F6\u65E0\u6CD5\u786E\u8BA4 A \u70B9\u5F53\u65F6\u7684\u62CD\u672B\uFF0C\u8BF7\u91CD\u65B0\u8BBE\u7F6E A\u3002");
      }
      startTick = currentTick;
      endTick = pointABeatEndTick;
    }
    const range = { startTick, endTick };
    if (!isValidPracticeLoopRange(range, scoreEndTick)) {
      throw new RangeError("A-B \u533A\u95F4\u4E3A\u7A7A\u6216\u8D85\u51FA\u5F53\u524D\u8C31\u9762\u8303\u56F4\uFF0C\u8BF7\u91CD\u65B0\u9009\u62E9\u3002");
    }
    return range;
  }
  function preparePracticeResumeSettings(resume, currentRevision, trackCount) {
    if (resume.scoreRevision !== currentRevision) throw new Error("\u7EC3\u4E60\u65AD\u70B9\u4E0E\u5F53\u524D\u8C31\u9762\u7248\u672C\u4E0D\u4E00\u81F4\uFF0C\u8BF7\u91CD\u65B0\u6253\u5F00\u66F2\u8C31");
    if (!Number.isSafeInteger(trackCount) || trackCount < 0) throw new RangeError("\u5F53\u524D\u8C31\u9762\u97F3\u8F68\u6570\u91CF\u65E0\u6548");
    const validIndex = (index) => Number.isSafeInteger(index) && index >= 0 && index < trackCount;
    const visibleTrackIndexes = [...new Set((resume.trackIndexes ?? []).filter(validIndex))].sort((a, b) => a - b);
    const trackMix = (resume.trackMix ?? []).filter((mix) => validIndex(mix.index)).map((mix) => {
      if (mix.instrumentOverride !== void 0 && typeof mix.instrumentOverride !== "boolean") {
        throw new Error("\u7EC3\u4E60\u65AD\u70B9\u7684\u97F3\u8272\u8986\u76D6\u6807\u8BB0\u65E0\u6548\uFF0C\u8BF7\u91CD\u65B0\u4FDD\u5B58\u540E\u7EED\u7EC3");
      }
      return { ...mix };
    });
    const display = resume.display;
    if (display && (!Number.isFinite(display.fontScale) || display.fontScale < 0.6 || display.fontScale > 1.6 || !["name", "diagram"].includes(display.chordMode) || !["mixed", "tab"].includes(display.scoreDisplayMode) || typeof display.numberTab !== "boolean" || typeof display.showFretboard !== "boolean")) {
      throw new Error("\u7EC3\u4E60\u65AD\u70B9\u7684\u8C31\u9762\u663E\u793A\u8BBE\u7F6E\u65E0\u6548\uFF0C\u8BF7\u91CD\u65B0\u4FDD\u5B58\u540E\u7EED\u7EC3");
    }
    return {
      visibleTrackIndexes: visibleTrackIndexes.length ? visibleTrackIndexes : Array.from({ length: trackCount }, (_unused, index) => index),
      trackMix,
      display: display ? { ...display } : void 0
    };
  }
  function createLoopLapProgress(generation, interruptionRevision, range) {
    return {
      generation,
      interruptionRevision,
      rangeKey: range ? `${range.startTick}:${range.endTick}` : "none",
      previousTick: null,
      observedFromA: false
    };
  }
  function observeLoopLapProgress(previous, input) {
    const next = createLoopLapProgress(input.generation, input.interruptionRevision, input.range);
    const identityMatches = previous.generation === next.generation && previous.interruptionRevision === next.interruptionRevision && previous.rangeKey === next.rangeKey;
    if (!input.range || !input.playing || !input.focused || !input.visible) return next;
    const current = identityMatches ? previous : next;
    if (input.isSeek) {
      return {
        ...current,
        previousTick: null,
        observedFromA: startsCompleteLoopLap(null, input.tick, input.range, true)
      };
    }
    return {
      ...current,
      previousTick: input.tick,
      observedFromA: current.observedFromA || startsCompleteLoopLap(current.previousTick, input.tick, input.range, false)
    };
  }
  function createPracticeSession(scoreId, scoreRevision, now = Date.now()) {
    return {
      id: crypto.randomUUID(),
      scoreId,
      scoreRevision,
      state: "active",
      startedAt: now,
      updatedAt: now,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
      slices: [],
      note: ""
    };
  }
  function isResumeCheckpointDue(now, lastWrite, intervalMs = 5e3) {
    if (lastWrite === null || !Number.isFinite(lastWrite) || !Number.isFinite(now)) return true;
    return now < lastWrite || now - lastWrite >= intervalMs;
  }
  function createSpeedPlan(revision, startBpm, targetBpm, stepBpm, lapsPerLevel, nativeAnchorBpm, loopRange) {
    if (![startBpm, targetBpm, stepBpm].every(Number.isFinite) || startBpm < 20 || targetBpm > 300 || targetBpm < startBpm || stepBpm <= 0 || !Number.isInteger(lapsPerLevel) || lapsPerLevel < 1) {
      throw new RangeError("Speed plan requires BPM values from 20 to 300, target >= start, and positive whole laps");
    }
    if (nativeAnchorBpm !== void 0 && (!Number.isFinite(nativeAnchorBpm) || nativeAnchorBpm < 1 || nativeAnchorBpm > 1e3)) {
      throw new RangeError("Native anchor BPM must be between 1 and 1000");
    }
    if (loopRange && (!Number.isInteger(loopRange.startTick) || !Number.isInteger(loopRange.endTick) || loopRange.startTick < 0 || loopRange.endTick <= loopRange.startTick)) {
      throw new RangeError("Speed plan loop range must have non-negative start and a later end");
    }
    if (nativeAnchorBpm !== void 0 && (!isValidPlaybackRatio(startBpm / nativeAnchorBpm) || !isValidPlaybackRatio(targetBpm / nativeAnchorBpm))) {
      throw new RangeError("Speed plan BPM range exceeds AlphaTab playback limits (0.125\u20138\xD7)");
    }
    return { revision, nativeAnchorBpm, loopRange, startBpm, targetBpm, stepBpm, lapsPerLevel, currentBpm: startBpm, completedLaps: 0 };
  }
  function isCompletedLoopLap(previousTick, currentTick, range, isSeek) {
    if (isSeek || previousTick === null || range.endTick <= range.startTick) return false;
    return previousTick < range.endTick && currentTick >= range.endTick;
  }
  function canCountLoopCompletion(input) {
    const { event, range } = input;
    return input.playing && input.focused && input.visible && input.observedFromA && !!event && !!range && event.startTick === range.startTick && event.endTick === range.endTick;
  }
  function startsCompleteLoopLap(previousTick, currentTick, range, isSeek) {
    if (range.endTick <= range.startTick || currentTick < range.startTick || currentTick >= range.endTick) return false;
    if (isSeek) return Math.abs(currentTick - range.startTick) <= 1;
    if (previousTick === null) return currentTick === range.startTick;
    return previousTick <= range.startTick;
  }
  function advanceSpeedPlan(plan, lapId, seenLapIds) {
    if (!lapId || seenLapIds.has(lapId)) return { plan, changed: false };
    if (plan.currentBpm >= plan.targetBpm) {
      return plan.completedLaps === 0 ? { plan, changed: false } : { plan: { ...plan, completedLaps: 0 }, changed: true };
    }
    seenLapIds.add(lapId);
    const completedLaps = plan.completedLaps + 1;
    if (completedLaps < plan.lapsPerLevel) {
      return { plan: { ...plan, completedLaps }, changed: true };
    }
    return {
      plan: {
        ...plan,
        currentBpm: Math.min(plan.targetBpm, plan.currentBpm + plan.stepBpm),
        completedLaps: 0
      },
      changed: true
    };
  }

  // src/lib/scoreDisplayMode.mjs
  var SCORE_DISPLAY_MODES = {
    MIXED: "mixed",
    // 主音轨六线谱 + 其余音轨简谱（对齐参考站）
    ALL_TAB: "tab"
    // 全部音轨六线谱（有调弦的渲染六线谱，无调弦的渲染简谱）
  };
  var DEFAULT_SCORE_DISPLAY_MODE = SCORE_DISPLAY_MODES.MIXED;
  function hasTuning(stave) {
    const t = stave?.stringTuning ?? stave?.stringtuning;
    return (t?.tunings?.length ?? 0) > 0;
  }
  function isWholeRestBeat(b) {
    if (!b || typeof b !== "object") return false;
    if (b.duration !== 1) return false;
    if (b.isrest === true || b.isRest === true) return true;
    return Array.isArray(b.notes) ? b.notes.length === 0 : false;
  }
  function replaceWholeRestsInSecondaryTracks(json) {
    const tracks = json?.tracks;
    if (!Array.isArray(tracks)) return 0;
    let firstTuned = -1;
    for (let i = 0; i < tracks.length; i++) {
      if ((tracks[i]?.staves ?? []).some((st) => (st?.stringtuning?.tunings?.length ?? 0) > 0)) {
        firstTuned = i;
        break;
      }
    }
    if (firstTuned < 0) return 0;
    let replaced = 0;
    for (let i = 0; i < tracks.length; i++) {
      if (i === firstTuned) continue;
      for (const st of tracks[i]?.staves ?? []) {
        for (const bar of st?.bars ?? []) {
          for (const v of bar?.voices ?? []) {
            const beats = v?.beats;
            if (!Array.isArray(beats) || beats.length === 0) continue;
            const out = [];
            let changed = false;
            for (const b of beats) {
              if (isWholeRestBeat(b)) {
                for (let k = 0; k < 4; k++) {
                  const clone = { ...b, duration: 4 };
                  if (k > 0) {
                    if ("text" in clone) clone.text = null;
                    if ("automations" in clone) clone.automations = [];
                  }
                  delete clone.id;
                  out.push(clone);
                }
                changed = true;
                replaced++;
              } else {
                out.push(b);
              }
            }
            if (changed) v.beats = out;
          }
        }
      }
    }
    return replaced;
  }
  function resolveStaveDisplay(mode, trackIndex, firstTunedTrackIndex, staveHasTuning) {
    if (mode === SCORE_DISPLAY_MODES.ALL_TAB) {
      return { showTablature: !!staveHasTuning, showNumbered: !staveHasTuning };
    }
    const asTab = staveHasTuning && trackIndex === firstTunedTrackIndex;
    return { showTablature: asTab, showNumbered: !asTab };
  }
  function applyScoreDisplayMode(score, mode) {
    if (!score?.tracks) return;
    let firstTunedTrackIndex = -1;
    for (let i = 0; i < score.tracks.length; i++) {
      if (score.tracks[i].staves?.some((st) => hasTuning(st))) {
        firstTunedTrackIndex = i;
        break;
      }
    }
    for (let i = 0; i < score.tracks.length; i++) {
      const track = score.tracks[i];
      for (const st of track.staves ?? []) {
        const flags = resolveStaveDisplay(mode, i, firstTunedTrackIndex, hasTuning(st));
        st.showTablature = flags.showTablature;
        st.showNumbered = flags.showNumbered;
      }
    }
  }

  // src/lib/gmInstruments.ts
  var ALL_GM_INSTRUMENTS = [
    // 钢琴 (0-7)
    { program: 0, name: "\u539F\u58F0\u5927\u94A2\u7434", enName: "Acoustic Grand Piano", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 1, name: "\u4EAE\u97F3\u5927\u94A2\u7434", enName: "Bright Acoustic Piano", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 2, name: "\u7535\u94A2\u7434 (\u67D4\u548C)", enName: "Electric Grand Piano", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 3, name: "\u9152\u5427\u94A2\u7434", enName: "Honky-tonk Piano", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 4, name: "\u7535\u94A2\u7434 1 (Rhodes)", enName: "Electric Piano 1", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 5, name: "\u7535\u94A2\u7434 2 (DX7/\u5408\u5531)", enName: "Electric Piano 2", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 6, name: "\u7FBD\u7BA1\u952E\u7434 (\u5927\u952E\u7434)", enName: "Harpsichord", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 7, name: "\u53E4\u94A2\u7434 (Clavinet)", enName: "Clavinet", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    // 色彩打击乐 (8-15)
    { program: 8, name: "\u94A2\u7247\u7434", enName: "Celesta", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 9, name: "\u949F\u7434 (\u94C1\u7434)", enName: "Glockenspiel", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 10, name: "\u516B\u97F3\u76D2", enName: "Music Box", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 11, name: "\u98A4\u97F3\u7434 (\u7535\u98A4\u7434)", enName: "Vibraphone", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 12, name: "\u9A6C\u6797\u5DF4\u6728\u7434", enName: "Marimba", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1FAB5}" },
    { program: 13, name: "\u6728\u7434 (Xylophone)", enName: "Xylophone", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1FAB5}" },
    { program: 14, name: "\u7BA1\u949F (Tubular Bells)", enName: "Tubular Bells", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 15, name: "\u626C\u7434 (Dulcimer)", enName: "Dulcimer", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA95}" },
    // 风琴 (16-23)
    { program: 16, name: "\u97F3\u6813\u7BA1\u98CE\u7434 (Drawbar Organ)", enName: "Drawbar Organ", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 17, name: "\u6253\u51FB\u611F\u98CE\u7434 (Percussive Organ)", enName: "Percussive Organ", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 18, name: "\u6447\u6EDA\u98CE\u7434 (Rock Organ)", enName: "Rock Organ", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 19, name: "\u6559\u5802\u7BA1\u98CE\u7434 (Church Organ)", enName: "Church Organ", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 20, name: "\u7C27\u98CE\u7434 (Reed Organ)", enName: "Reed Organ", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1F3B9}" },
    { program: 21, name: "\u624B\u98CE\u7434 (Accordion)", enName: "Accordion", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1FA97}" },
    { program: 22, name: "\u53E3\u7434 (Harmonica)", enName: "Harmonica", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B5}" },
    { program: 23, name: "\u63A2\u6208\u624B\u98CE\u7434 (Bandoneon)", enName: "Tango Accordion", category: "\u94A2\u7434\u4E0E\u952E\u76D8", icon: "\u{1FA97}" },
    // 吉他族 (24-31)
    { program: 24, name: "\u53E4\u5178\u5C3C\u9F99\u5F26\u5409\u4ED6", enName: "Acoustic Guitar (nylon)", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1FAB5}" },
    { program: 25, name: "\u6C11\u8C23\u94A2\u5F26\u6728\u5409\u4ED6", enName: "Acoustic Guitar (steel)", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1F3B8}" },
    { program: 26, name: "\u7235\u58EB\u7A7A\u5FC3\u7535\u5409\u4ED6", enName: "Electric Guitar (jazz)", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1F3B8}" },
    { program: 27, name: "\u6E05\u97F3\u7535\u5409\u4ED6 (Clean)", enName: "Electric Guitar (clean)", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u26A1" },
    { program: 28, name: "\u95F7\u97F3\u7535\u5409\u4ED6 (Muted)", enName: "Electric Guitar (muted)", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u26A1" },
    { program: 29, name: "\u8FC7\u8F7D\u6447\u6EDA\u7535\u5409\u4ED6 (Overdrive)", enName: "Overdriven Guitar", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1F525}" },
    { program: 30, name: "\u5931\u771F\u91CD\u91D1\u5C5E\u7535\u5409\u4ED6 (Distortion)", enName: "Distortion Guitar", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1F525}" },
    { program: 31, name: "\u5409\u4ED6\u81EA\u7136\u6CDB\u97F3 (Harmonics)", enName: "Guitar Harmonics", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u2728" },
    // 贝斯族 (32-39)
    { program: 32, name: "\u539F\u58F0\u6728\u8D1D\u65AF (Acoustic Bass)", enName: "Acoustic Bass", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F3BB}" },
    { program: 33, name: "\u6307\u5F39\u7535\u8D1D\u65AF (Finger Bass)", enName: "Electric Bass (finger)", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F3B8}" },
    { program: 34, name: "\u62E8\u7247\u7535\u8D1D\u65AF (Pick Bass)", enName: "Electric Bass (pick)", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F3B8}" },
    { program: 35, name: "\u65E0\u54C1\u7535\u8D1D\u65AF (Fretless Bass)", enName: "Fretless Bass", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F3B8}" },
    { program: 36, name: "\u51FB\u5F26\u8D1D\u65AF 1 (Slap Bass 1)", enName: "Slap Bass 1", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F4A5}" },
    { program: 37, name: "\u51FB\u5F26\u8D1D\u65AF 2 (Slap Bass 2)", enName: "Slap Bass 2", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F4A5}" },
    { program: 38, name: "\u5408\u6210\u8D1D\u65AF 1 (Synth Bass 1)", enName: "Synth Bass 1", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F39B}\uFE0F" },
    { program: 39, name: "\u5408\u6210\u8D1D\u65AF 2 (Synth Bass 2)", enName: "Synth Bass 2", category: "\u8D1D\u65AF\u65CF", icon: "\u{1F39B}\uFE0F" },
    // 弦乐独奏 (40-47)
    { program: 40, name: "\u5C0F\u63D0\u7434 (Violin)", enName: "Violin", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 41, name: "\u4E2D\u63D0\u7434 (Viola)", enName: "Viola", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 42, name: "\u5927\u63D0\u7434 (Cello)", enName: "Cello", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 43, name: "\u4F4E\u97F3\u63D0\u7434 (Contrabass)", enName: "Contrabass", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 44, name: "\u9707\u97F3\u5F26\u4E50 (Tremolo Strings)", enName: "Tremolo Strings", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 45, name: "\u62E8\u594F\u5F26\u4E50 (Pizzicato Strings)", enName: "Pizzicato Strings", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 46, name: "\u7BA1\u5F26\u4E50\u7AD6\u7434 (Orchestral Harp)", enName: "Orchestral Harp", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1FA95}" },
    { program: 47, name: "\u5B9A\u97F3\u9F13 (Timpani)", enName: "Timpani", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F941}" },
    // 合奏与人声 (48-55)
    { program: 48, name: "\u5F26\u4E50\u5408\u594F 1 (\u6162\u5F13 Strings 1)", enName: "String Ensemble 1", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 49, name: "\u5F26\u4E50\u5408\u594F 2 (\u5FEB\u5F13 Strings 2)", enName: "String Ensemble 2", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F3BB}" },
    { program: 50, name: "\u5408\u6210\u5F26\u4E50 1 (Synth Strings 1)", enName: "Synth Strings 1", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 51, name: "\u5408\u6210\u5F26\u4E50 2 (Synth Strings 2)", enName: "Synth Strings 2", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 52, name: "\u5408\u5531\u4EBA\u58F0 (Choir Aahs)", enName: "Choir Aahs", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F5E3}\uFE0F" },
    { program: 53, name: "\u4EBA\u58F0\u4F34\u5531 (Voice Oohs)", enName: "Voice Oohs", category: "\u5F26\u4E50\u4E0E\u7BA1\u5F26", icon: "\u{1F5E3}\uFE0F" },
    { program: 54, name: "\u5408\u6210\u4EBA\u58F0 (Synth Voice)", enName: "Synth Voice", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 55, name: "\u7BA1\u5F26\u6253\u51FB\u4E50\u5F3A\u594F (Orchestra Hit)", enName: "Orchestra Hit", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F4A5}" },
    // 铜管乐器 (56-63)
    { program: 56, name: "\u5C0F\u53F7 (Trumpet)", enName: "Trumpet", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3BA}" },
    { program: 57, name: "\u957F\u53F7 (Trombone)", enName: "Trombone", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3BA}" },
    { program: 58, name: "\u5927\u53F7 (Tuba)", enName: "Tuba", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3BA}" },
    { program: 59, name: "\u5F31\u97F3\u5C0F\u53F7 (Muted Trumpet)", enName: "Muted Trumpet", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3BA}" },
    { program: 60, name: "\u6CD5\u56FD\u5706\u53F7 (French Horn)", enName: "French Horn", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F4EF}" },
    { program: 61, name: "\u94DC\u7BA1\u5408\u594F\u7EC4 (Brass Section)", enName: "Brass Section", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3BA}" },
    { program: 62, name: "\u5408\u6210\u94DC\u7BA1 1 (Synth Brass 1)", enName: "Synth Brass 1", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 63, name: "\u5408\u6210\u94DC\u7BA1 2 (Synth Brass 2)", enName: "Synth Brass 2", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    // 簧管木管 (64-79)
    { program: 64, name: "\u9AD8\u97F3\u8428\u514B\u65AF (Soprano Sax)", enName: "Soprano Sax", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B7}" },
    { program: 65, name: "\u4E2D\u97F3\u8428\u514B\u65AF (Alto Sax)", enName: "Alto Sax", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B7}" },
    { program: 66, name: "\u6B21\u4E2D\u97F3\u8428\u514B\u65AF (Tenor Sax)", enName: "Tenor Sax", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B7}" },
    { program: 67, name: "\u4E0A\u4F4E\u97F3\u8428\u514B\u65AF (Baritone Sax)", enName: "Baritone Sax", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B7}" },
    { program: 68, name: "\u53CC\u7C27\u7BA1 (Oboe)", enName: "Oboe", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B5}" },
    { program: 69, name: "\u82F1\u56FD\u7BA1 (English Horn)", enName: "English Horn", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B5}" },
    { program: 70, name: "\u5927\u7BA1 / \u5DF4\u677E\u7BA1 (Bassoon)", enName: "Bassoon", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B5}" },
    { program: 71, name: "\u5355\u7C27\u7BA1 / \u9ED1\u7BA1 (Clarinet)", enName: "Clarinet", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1F3B5}" },
    { program: 72, name: "\u77ED\u7B1B (Piccolo)", enName: "Piccolo", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1FA88}" },
    { program: 73, name: "\u957F\u7B1B (Flute)", enName: "Flute", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1FA88}" },
    { program: 74, name: "\u7AD6\u7B1B / \u76F4\u7B1B (Recorder)", enName: "Recorder", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1FA88}" },
    { program: 75, name: "\u6392\u7BAB (Pan Flute)", enName: "Pan Flute", category: "\u94DC\u7BA1\u4E0E\u6728\u7BA1", icon: "\u{1FA88}" },
    { program: 76, name: "\u5439\u74F6\u97F3 (Blown Bottle)", enName: "Blown Bottle", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F37E}" },
    { program: 77, name: "\u5C3A\u516B (Shakuhachi)", enName: "Shakuhachi", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA88}" },
    { program: 78, name: "\u7231\u5C14\u5170\u54E8\u7B1B (Whistle)", enName: "Whistle", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA88}" },
    { program: 79, name: "\u9676\u7B1B / \u57D9 (Ocarina)", enName: "Ocarina", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA88}" },
    // 合成主音 (80-87)
    { program: 80, name: "\u65B9\u6CE2\u4E3B\u97F3 (Lead 1 - Square)", enName: "Lead 1 (square)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 81, name: "\u952F\u9F7F\u6CE2\u4E3B\u97F3 (Lead 2 - Sawtooth)", enName: "Lead 2 (sawtooth)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 82, name: "\u6C7D\u7B1B\u98CE\u7434\u4E3B\u97F3 (Lead 3 - Calliope)", enName: "Lead 3 (calliope)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 83, name: "\u5439\u7BA1\u4E3B\u97F3 (Lead 4 - Chiff)", enName: "Lead 4 (chiff)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 84, name: "\u5409\u4ED6\u5408\u6210\u4E3B\u97F3 (Lead 5 - Charang)", enName: "Lead 5 (charang)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 85, name: "\u4EBA\u58F0\u4E3B\u97F3 (Lead 6 - Voice)", enName: "Lead 6 (voice)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F5E3}\uFE0F" },
    { program: 86, name: "\u4E94\u5EA6\u4E3B\u97F3 (Lead 7 - Fifths)", enName: "Lead 7 (fifths)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    { program: 87, name: "\u8D1D\u65AF\u6DF7\u5408\u4E3B\u97F3 (Lead 8 - Bass + Lead)", enName: "Lead 8 (bass + lead)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F39B}\uFE0F" },
    // 合成铺底 (88-95)
    { program: 88, name: "\u65B0\u4E16\u7EAA\u97F3\u8272 (Pad 1 - New Age)", enName: "Pad 1 (new age)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 89, name: "\u6E29\u6696\u6E29\u6696\u94FA\u5E95 (Pad 2 - Warm)", enName: "Pad 2 (warm)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 90, name: "\u590D\u97F3\u5408\u6210\u5668 (Pad 3 - Polysynth)", enName: "Pad 3 (polysynth)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 91, name: "\u5408\u5531\u94FA\u5E95 (Pad 4 - Choir)", enName: "Pad 4 (choir)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 92, name: "\u5F13\u5F26\u94FA\u5E95 (Pad 5 - Bowed)", enName: "Pad 5 (bowed)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 93, name: "\u91D1\u5C5E\u8D28\u611F\u94FA\u5E95 (Pad 6 - Metallic)", enName: "Pad 6 (metallic)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 94, name: "\u5149\u6655\u6C1B\u56F4\u94FA\u5E95 (Pad 7 - Halo)", enName: "Pad 7 (halo)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    { program: 95, name: "\u626B\u9891\u94FA\u5E95 (Pad 8 - Sweep)", enName: "Pad 8 (sweep)", category: "\u5408\u6210\u4E3B\u97F3\u4E0E\u94FA\u5E95", icon: "\u{1F30C}" },
    // 合成特效 (96-103)
    { program: 96, name: "\u96E8\u58F0\u7279\u6548 (FX 1 - Rain)", enName: "FX 1 (rain)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F327}\uFE0F" },
    { program: 97, name: "\u7535\u5F71\u539F\u58F0\u6C1B\u56F4 (FX 2 - Soundtrack)", enName: "FX 2 (soundtrack)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F3AC}" },
    { program: 98, name: "\u6C34\u6676\u97F3\u8272 (FX 3 - Crystal)", enName: "FX 3 (crystal)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F48E}" },
    { program: 99, name: "\u592A\u7A7A\u5927\u6C14 (FX 4 - Atmosphere)", enName: "FX 4 (atmosphere)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1FA90}" },
    { program: 100, name: "\u660E\u4EAE\u661F\u5149 (FX 5 - Brightness)", enName: "FX 5 (brightness)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u2B50" },
    { program: 101, name: "\u5C0F\u5996\u7CBE\u56DE\u97F3 (FX 6 - Goblins)", enName: "FX 6 (goblins)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F47E}" },
    { program: 102, name: "\u56DE\u97F3\u6C34\u6EF4 (FX 7 - Echoes)", enName: "FX 7 (echoes)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F4A7}" },
    { program: 103, name: "\u79D1\u5E7B\u8109\u51B2 (FX 8 - Sci-fi)", enName: "FX 8 (sci-fi)", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F680}" },
    // 民族乐器 (104-111)
    { program: 104, name: "\u897F\u5854\u5C14\u7434 (Sitar)", enName: "Sitar", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA95}" },
    { program: 105, name: "\u73ED\u5353\u7434", enName: "Banjo", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1FA95}" },
    { program: 106, name: "\u4E09\u5473\u7EBF (Shamisen)", enName: "Shamisen", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA95}" },
    { program: 107, name: "\u65E5\u672C\u7B5D / \u53E4\u7B5D (Koto)", enName: "Koto", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1FA95}" },
    { program: 108, name: "\u5361\u6797\u5DF4\u62C7\u6307\u7434 (Kalimba)", enName: "Kalimba", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1F514}" },
    { program: 109, name: "\u98CE\u7B1B (Bagpipe)", enName: "Bagpipe", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1F4EF}" },
    { program: 110, name: "\u6C11\u65CF\u5C0F\u63D0\u7434 (Fiddle)", enName: "Fiddle", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1F3BB}" },
    { program: 111, name: "\u5370\u5EA6\u5522\u5450 (Shanai)", enName: "Shanai", category: "\u6C11\u65CF\u7279\u8272\u4E50\u5668", icon: "\u{1F3BA}" },
    // 打击乐器 (112-119)
    { program: 112, name: "\u78B0\u94C3 / \u53EE\u5F53\u94C3 (Tinkle Bell)", enName: "Tinkle Bell", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 113, name: "\u963F\u54E5\u54E5\u94C3 (Agogo)", enName: "Agogo", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F514}" },
    { program: 114, name: "\u94A2\u9F13 (Steel Drums)", enName: "Steel Drums", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F941}" },
    { program: 115, name: "\u6728\u9C7C / \u6728\u5757 (Woodblock)", enName: "Woodblock", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1FAB5}" },
    { program: 116, name: "\u592A\u9F13 (Taiko Drum)", enName: "Taiko Drum", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F941}" },
    { program: 117, name: "\u901A\u901A\u9F13 (Melodic Tom)", enName: "Melodic Tom", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F941}" },
    { program: 118, name: "\u5408\u6210\u7535\u5B50\u9F13 (Synth Drum)", enName: "Synth Drum", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F941}" },
    { program: 119, name: "\u53CD\u8F6C\u9572\u7247 (Reverse Cymbal)", enName: "Reverse Cymbal", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F4A5}" },
    // 声音特效 (120-128)
    { program: 120, name: "\u5409\u4ED6\u54C1\u4E1D\u566A\u97F3 (Guitar Fret Noise)", enName: "Guitar Fret Noise", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F50A}" },
    { program: 121, name: "\u547C\u5438\u58F0 (Breath Noise)", enName: "Breath Noise", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F32C}\uFE0F" },
    { program: 122, name: "\u6D77\u6D6A\u58F0 (Seashore)", enName: "Seashore", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F30A}" },
    { program: 123, name: "\u9E1F\u9E23 (Bird Tweet)", enName: "Bird Tweet", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F426}" },
    { program: 124, name: "\u7535\u8BDD\u94C3\u58F0 (Telephone Ring)", enName: "Telephone Ring", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u260E\uFE0F" },
    { program: 125, name: "\u76F4\u5347\u673A (Helicopter)", enName: "Helicopter", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F681}" },
    { program: 126, name: "\u638C\u58F0 (Applause)", enName: "Applause", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F44F}" },
    { program: 127, name: "\u67AA\u58F0 (Gunshot)", enName: "Gunshot", category: "\u6253\u51FB\u4E50\u4E0E\u7279\u6548", icon: "\u{1F52B}" },
    { program: 128, name: "\u6807\u51C6\u7235\u58EB/\u6447\u6EDA\u6253\u51FB\u4E50\u67B6\u5B50\u9F13\u7EC4", enName: "Standard Drum Kit", category: "\u5E38\u7528\u5409\u4ED6\u4E0E\u5F39\u62E8", icon: "\u{1F941}" }
  ];
  var GM_INSTRUMENTS = ALL_GM_INSTRUMENTS.map((x) => [x.program, x.name]);

  // src/lib/player/manuscriptBeatBars.mjs
  function buildManuscriptBeatBarIndex(tracks) {
    const beatToBarIndex = /* @__PURE__ */ new Map();
    const ambiguousBeatIds = /* @__PURE__ */ new Set();
    for (const track of Array.isArray(tracks) ? tracks : []) {
      for (const staff of Array.isArray(track?.staves) ? track.staves : []) {
        for (const bar of Array.isArray(staff?.bars) ? staff.bars : []) {
          const barIndex = bar?.index;
          if (!Number.isSafeInteger(barIndex) || barIndex < 0) continue;
          for (const voice of Array.isArray(bar?.voices) ? bar.voices : []) {
            for (const beat of Array.isArray(voice?.beats) ? voice.beats : []) {
              const beatId = beat?.id;
              if (!Number.isSafeInteger(beatId) || beatId < 0 || ambiguousBeatIds.has(beatId)) continue;
              const previousBarIndex = beatToBarIndex.get(beatId);
              if (previousBarIndex === void 0 || previousBarIndex === barIndex) {
                beatToBarIndex.set(beatId, barIndex);
              } else {
                beatToBarIndex.delete(beatId);
                ambiguousBeatIds.add(beatId);
              }
            }
          }
        }
      }
    }
    return beatToBarIndex;
  }
  function resolveManuscriptBarIndexForBeatGroup(classNames, beatToBarIndex) {
    const tokens = String(classNames ?? "").split(/\s+/).filter(Boolean);
    const resolvedBarIndices = /* @__PURE__ */ new Set();
    for (const token of tokens) {
      const match = token.match(/^b(\d+)$/);
      if (!match) continue;
      const beatId = Number(match[1]);
      if (!Number.isSafeInteger(beatId)) continue;
      const barIndex = beatToBarIndex?.get(beatId);
      if (Number.isSafeInteger(barIndex) && barIndex >= 0) resolvedBarIndices.add(barIndex);
    }
    return resolvedBarIndices.size === 1 ? [...resolvedBarIndices][0] : null;
  }

  // native-macos/Resources/Player/practice-runtime-entry.ts
  var scope = globalThis;
  scope.NativePracticeCore = Object.freeze({
    normalizeLoop: normalizePracticeLoopSelection,
    prepareResume: preparePracticeResumeSettings,
    createSession: createPracticeSession,
    createSpeedPlan,
    advanceSpeedPlan,
    isValidPlaybackRatio,
    isResumeCheckpointDue,
    isCompletedLoopLap,
    startsCompleteLoopLap,
    canCountLoopCompletion,
    createLoopLapProgress,
    observeLoopLapProgress,
    applyScoreDisplayMode,
    replaceWholeRestsInSecondaryTracks,
    gmInstruments: GM_INSTRUMENTS,
    buildManuscriptBeatBarIndex,
    resolveManuscriptBarIndexForBeatGroup
  });
})();
