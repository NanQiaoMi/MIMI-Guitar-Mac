// 贝斯击勾（tap/slap/pop）MIDI 力度增强
// AlphaTab 1.8.4 MidiFileGenerator 不为其生成 MIDI 效果（仅谱面渲染 S/P/T 字母），
// 本模块通过官方 midiLoad 事件对生成的 MIDI 做后处理：slap/pop/tap 拍上的音符提升力度。
// MidiEventType.NoteOn = 128
const NOTE_ON = 128;

/** 返回某拍因击勾技巧应加的力度增量（无则 0）。纯函数，可单测。 */
export function bassArticulationBoost(beat) {
  if (beat && beat.slap) return 22;
  if (beat && beat.pop) return 18;
  if (beat && beat.tap) return 10;
  return 0;
}

/**
 * 对 MIDI 文件按 boostMap 提升 NoteOn 力度。
 * 兼容 format 0（单 track，事件自带 .track 字段）与 format 1（每轨一个 track）。
 * @param midiFile alphaTab 生成的 MidiFile（midiLoad 事件参数）
 * @param boostMap Map<trackIndex, Map<tick, boost>> —— 由 score + tickCache 构建
 * @returns 原对象（原地修改）
 */
export function applyVelocityBoostToMidi(midiFile, boostMap) {
  if (!midiFile || !boostMap || boostMap.size === 0) return midiFile;
  for (const mt of midiFile.tracks ?? []) {
    for (const ev of mt?.events ?? []) {
      if (ev.type === NOTE_ON) {
        const tickMap = boostMap.get(ev.track);
        if (tickMap && tickMap.has(ev.tick)) {
          const boost = tickMap.get(ev.tick) || 0;
          ev.noteVelocity = Math.min(127, Math.max(0, (ev.noteVelocity ?? 0) + boost));
        }
      }
    }
  }
  return midiFile;
}