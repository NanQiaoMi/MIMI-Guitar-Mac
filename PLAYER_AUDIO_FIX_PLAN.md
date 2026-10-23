# PLAYER_AUDIO_FIX_PLAN.md —— 转调/变调夹/乐器切换音频生效修复计划

## 一、审计结论（已实测确认，非推测）

### 1. 转调目前只改显示，不改播放声音 —— 确认为 Bug
- 代码现状：ScorePlayer.svelte 的 applyTransposition() 只设置 staff.capo 与 staff.transpositionPitch，然后 renderScore 重渲染，未重新生成播放 MIDI。
- AlphaTab 机制（源码确认）：_internalRenderTracks() 只有在 score !== this.score（换新 score 对象）时才调用 loadMidiForScore()；同一 score 对象重渲染走 else 分支，不会重生成播放 MIDI。播放器 MIDI 停留在初次加载时生成的原调版本。
- 实测证据（Playwright）：监听 loadMidiForScore 调用计数，转调 +5 并重渲染后计数仍为 0；同一音符 calculateRealValue(true,true) 从 52→54→57（模型正确 +2/+5），但播放器 MIDI 未刷新 → 听感仍是原调。
- 结论：显示的五线谱/六线谱/和弦名已移调，实际播放音频未移调，显示与听感不一致。

### 2. 变调夹 / 降半调调弦同样只改显示不改播放
- staff.capo 会进入 stringTuning（Note.stringTuning = staff.capo + ...），MIDI 生成时用 calculateRealValue(true,true) 会包含 capo，但同样因为同一 score 重渲染不重生成 MIDI → 音频不变。
- 初始 Capo（页面加载即带原始 capo 的谱）在首次 renderScore（新 score 对象）时已生效，只有运行中切换不生效。

### 3. 乐器切换同类 Bug
- changeInstrument() 只改 track.playbackInfo.program + 重渲染，未重生成 MIDI → program change 事件不刷新，换乐器后音色不变。

### 4. 和弦声音是否正确（原调下）
- 模型/MIDI 数据正确：晴天首个强力和弦实际发音 {E2,B2,E3,G3,B3,E4} = Em 构成，与谱面音符一致；演奏的是谱面真实音符，非系统 bug。
- 说明：谱面第一处标签为 Em7，但实际 voicing 是 Em（无 D），这是原曲谱数据本身的标注，系统忠实演奏谱面内容。
- 修复转调后，音频会与显示同步移调，和弦音程关系保持正确（整体平移，和弦性质不变）。

## 二、根因

AlphaTab 1.8.4 中播放器 MIDI 的生成时机：
- 首次 renderScore / 新 score 对象 → _internalRenderTracks 新对象分支 → loadMidiForScore()
- 同一 score 对象重渲染（改 capo / transpositionPitch / program）→ else 分支 → 只重渲染，不重生成 MIDI
- 因此所有「改模型字段后重渲染」的音频变更都不会生效，需要显式调用 api.loadMidiForScore()。

## 三、修复方案（主选：loadMidiForScore 重生成）

### 3.1 统一就绪等待工具
- 新增 waitForPlaybackReady(timeoutMs=8000)：注册 api._player.readyForPlayback 一次性监听，超时兜底 resolve（不阻塞 UI）。

### 3.2 withRenderPreservingPosition 支持 reloadMidi
- 签名扩展：withRenderPreservingPosition(fn, { reloadMidi?: boolean })。
- 流程：记录 wasPlaying + pos → pause() → await fn() → 若 reloadMidi：先注册 waitForPlaybackReady，再 api.loadMidiForScore()，await 就绪 → 恢复 api.tickPosition=clamp(pos) → 若 wasPlaying 则 api.play()。
- 说明：loadMidiForScore 会停止播放并重载 MIDI，必须在就绪后再恢复位置/续播，避免时序竞态。

### 3.3 调用点改造
- applyTransposition()（变调夹/降半调调弦/转调共用）：withRenderPreservingPosition(..., { reloadMidi: true })。
- changeInstrument()：先 await loadSoundfonts()（新乐器 sf2），再 withRenderPreservingPosition(..., { reloadMidi: true })。
- 纯显示类（字体缩放/数字谱/和弦模式/音轨显隐）保持不 reloadMidi。

## 四、备选方案（对比，主选失败再启用）

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| A. loadMidiForScore（主选） | 重生成播放 MIDI | 单一数据源（staff 字段同时驱动显示与音频），capo/transposition 天然一致，无双重移调风险 | 会短暂停止播放，需等待就绪后恢复；整谱重生成略重 |
| B. 实时移调 api.changeTrackTranspositionPitch | 合成器实时音高偏移 | 无需重生成、不打断 | 与显示（staff.transpositionPitch）双数据源需严格同步，capo/transposition 需合并计算，易双重生效；需按每轨 channel 设置 |

推荐 A。

## 五、实施里程碑

### M-A1 就绪等待 + reloadMidi 基础设施（分支 fix/player-audio-midi）
- 新增 waitForPlaybackReady、改造 withRenderPreservingPosition、applyTransposition/changeInstrument 接入。
- 验收：转调 +2 后 loadMidiForScore 调用计数 +1；播放中切变调夹/转调位置不重置、不卡死；控制台零报错。

### M-A2 播放音高自动化验证
- 新增 Playwright 专项 verify-player-audio.mjs：
  - 读取 api.score 模型 calculateRealValue(true,true) 在转调 ±、变调夹、降半调下的偏移（应为精确半音差）；
  - 断言 loadMidiForScore 调用计数在每次音频类变更后递增（证明播放 MIDI 刷新）；
  - 断言同一 score 对象重渲染（数字谱/字体/和弦模式）不触发 loadMidiForScore（不误刷新）；
  - 和弦音高正确性：取前 N 个和弦的音符集合，验证转调前后每个音符平移相同半音数（音程保持）；
  - 乐器切换：program 改变后 MIDI program change 事件目标为新模式（通过重生成 MIDI 抽样验证）。

### M-A3 回归与收尾
- 全量回归：verify-score-details 8/8、verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build。
- 更新 DEV_LOG.md（M8.5 音频生效修复）与 PLAN.md；合并 master 后主分支回归。

## 六、风险与说明

- loadMidiForScore 会短暂停播，已用 readyForPlayback 等待 + 超时兜底；极端慢环境最多延迟 8s 恢复（可调）。
- 音轨显隐不重生成 MIDI（隐藏轨道仍发声）：与参考站行为待确认，本计划不处理，另立任务。
- 音色正确性依赖每 program 的 sf2 映射（M2 已修复单声道）；若个别音色不理想属音源质量，可后续替换/调 EQ。
- 备选方案 B 仅在 A 出现异常时启用，需更新 pitch.mjs 单测覆盖 capo+transpose 合并偏移。
