// 谱面显示模式纯函数（供 ScorePlayer 组件与 node --test 单测共用，纯 JS 以便 .mjs 直接导入）
//
// 背景：部分曲谱（如《安和桥》）含多个有调弦音轨（吉他伴奏 + 人声/旋律轨），若全部渲染成
// 六线谱会出现「两排六线谱」；参考站 guistudy 每个 system 只显示 1 个六线谱 + 1 行简谱数字 + 歌词。
// 方案 C：主音轨（第一个有调弦的音轨）渲染六线谱，其余音轨渲染简谱；两种模式都保留，可随时切换。
//
// 已知 AlphaTab 1.8.4 边界：简谱（numbered）渲染器在遇到「全音符休止符」拍时会崩溃
// （NumberedBarRenderer.calculateBeamingOverflows -> beatOfHighestNote 读 null，实测定位；
// 且 MidiFileGenerator._detectTickShift 依赖 voice.isEmpty，模型级改拍易引发副作用）。
// 处理：在 JSON 层（JsonConverter 之前）把非主音轨的全音符休止符替换为 4 个四分休止符——
// 时长不变（休止符无声，不影响音频）、简谱空小节显示 0 0 0 0（对齐参考站）、由 JsonConverter
// 生成合法 Beat，避免模型级改动的副作用。主音轨保持六线谱不受影响。

export const SCORE_DISPLAY_MODES = {
  MIXED: 'mixed', // 主音轨六线谱 + 其余音轨简谱（对齐参考站）
  ALL_TAB: 'tab', // 全部音轨六线谱（有调弦的渲染六线谱，无调弦的渲染简谱）
};

export const DEFAULT_SCORE_DISPLAY_MODE = SCORE_DISPLAY_MODES.MIXED;

/** 显示模式的中文标签 */
export function scoreDisplayModeLabel(mode) {
  return mode === SCORE_DISPLAY_MODES.ALL_TAB ? '全部六线谱' : '吉他谱+简谱';
}

/** 某 stave 是否有弦调音（有调音才能渲染六线谱）；兼容模型(camelCase)与归一化 JSON(lowercase) */
export function hasTuning(stave) {
  const t = stave?.stringTuning ?? stave?.stringtuning;
  return (t?.tunings?.length ?? 0) > 0;
}

/** 谱面中可渲染六线谱（有调弦）的音轨数；切换控件仅在 >=2 时才有意义 */
export function countTabTracks(score) {
  if (!score?.tracks) return 0;
  return score.tracks.filter((t) => t.staves?.some((st) => hasTuning(st))).length;
}

/**
 * 检测 stave 是否含全音符休止符（duration=1）。此模式会触发 AlphaTab 1.8.4 简谱渲染器崩溃，
 * 但 replaceWholeRestsInSecondaryTracks() 会在 JsonConverter 前替换，仅作诊断/审计用。
 */
export function hasWholeRestCrash(stave) {
  for (const bar of stave?.bars ?? []) {
    for (const voice of bar?.voices ?? []) {
      for (const beat of voice?.beats ?? []) {
        if (beat?.isRest && beat.duration === 1) return true;
      }
    }
  }
  return false;
}

/** 混合模式是否可用于该谱面：至少 2 个有调弦音轨 */
export function canUseMixedMode(score) {
  if (!score?.tracks) return false;
  const tuned = score.tracks.map((t) => t.staves?.some((st) => hasTuning(st)));
  const first = tuned.indexOf(true);
  if (first < 0 || tuned.filter(Boolean).length < 2) return false;
  return true;
}

/**
 * Detect whether a normalized-JSON beat is a whole-note rest.
 * Normalized JSON keys are all lowercase; in the corpus a whole rest has no
 * isrest key at all and appears as { duration: 1, notes: [] }. isrest=true is
 * handled for robustness.
 */
function isWholeRestBeat(b) {
  if (!b || typeof b !== 'object') return false;
  if (b.duration !== 1) return false;
  if (b.isrest === true || b.isRest === true) return true;
  return Array.isArray(b.notes) ? b.notes.length === 0 : false;
}

/**
 * JSON-level preprocessing -- call BEFORE model.JsonConverter.jsonToScore().
 * For every tuned track except the first tuned (primary) track, replace each
 * whole-note rest beat with 4 quarter-rest clones.
 *
 * Why: AlphaTab 1.8.4's NumberedBarRenderer crashes on whole rests
 * (duration=1) -- NumberedBarRenderer.calculateBeamingOverflows reads
 * beatOfHighestNote which is null for an all-rest beam helper. Quarter rests
 * (duration=4 >= Half) take the safe single-long-beat branch. The four clones
 * keep the bar silent and the numbered staff shows "0 0 0 0", matching the
 * reference site's jianpu. JsonConverter recomputes displayStart/playbackStart
 * and displayDuration/playbackDuration (via Beat.updateDurations), so only
 * duration is significant here.
 *
 * The primary track is left untouched (it renders as tab, which handles whole
 * rests natively). Returns the number of whole rests replaced.
 */
export function replaceWholeRestsInSecondaryTracks(json) {
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
                // Keep text/automations only on the first clone to avoid duplication.
                if (k > 0) {
                  if ('text' in clone) clone.text = null;
                  if ('automations' in clone) clone.automations = [];
                }
                // Avoid duplicate beat ids across the clones.
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

export function resolveStaveDisplay(mode, trackIndex, firstTunedTrackIndex, staveHasTuning) {
  if (mode === SCORE_DISPLAY_MODES.ALL_TAB) {
    return { showTablature: !!staveHasTuning, showNumbered: !staveHasTuning };
  }
  // mixed：仅第一个有调弦的音轨渲染六线谱，其余（含无调弦的旋律轨）渲染简谱
  const asTab = staveHasTuning && trackIndex === firstTunedTrackIndex;
  return { showTablature: asTab, showNumbered: !asTab };
}

/** 把显示模式写到 score 的所有 stave 上（就地修改，供渲染/打印/PDF 共用） */
export function applyScoreDisplayMode(score, mode) {
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

