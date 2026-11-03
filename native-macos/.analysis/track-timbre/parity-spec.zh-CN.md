# 网页版 ↔ macOS 原生播放器「音轨 / 音色」行为对齐规格

- 任务：task-1（parity-spec）
- 基准（行为真理）：`project/src/components/player/ScorePlayer.svelte` + `project/src/lib/player/*`（Astro/Svelte 网页版）
- 对照（被测实现）：`project/native-macos/Resources/Player/player.js` + `project/native-macos/Sources/MIMIGuitarMac/Player/*.swift`
- 证据附录：`evidence/web-and-native-evidence.zh-CN.md`（含 SF2 预设表、AlphaTab last-match 实现、测试用例行号）
- 只读分析，未修改任何产品源码。

严重度定义（本文统一）：

| 级别 | 含义 |
|---|---|
| **P0** | 默认/切换音色听感错误（用户能立刻听出不是原曲音色） |
| **P1** | 播放中断、播放状态/位置丢失、"恢复原谱"无效、面板状态与播放器不一致 |
| **P2** | 仅 UI 文案、展示、持久化兼容性差异 |

---

## 0. 结论速览（3 条）

1. **原生播放器完全没有网页版的 SoundFont 选择逻辑**：初始化只写死 `settings.player.soundFont = /soundfont/main`（= sonivox GM 全库，`player.js:1074`），全文件没有一处 `loadSoundFont()` / `ukulele` / `category` / `flavor`（grep 证实），因此 ukulele 类别曲目的原谱音色在原生端实际由 GM program 25「Steel-str.Gt 钢弦吉他」发声，而不是 `ukulele_fast.sf2` 的「Ukulele Steel」。**P0**。
2. **"恢复原谱音色"在原生端只回写 `playbackInfo.program` / `name`，不回写 Instrument automation**（`player.js:1961-1967`），而切音色时 `applyTrackProgram` 会把所有 Instrument automation 值改成新 program（`player.js:586-600`）。网页版对此非常明确：`applyTrackInstrument` 同步改 automation，恢复时从原始 JSON 重建 score（`ScorePlayer.svelte:2667-2690, 2717-2737`）。因此凡是谱面里带 Instrument automation 的曲目，原生端"恢复原谱"后**听起来仍是用户刚选的音色**。**P0/P1**（是否可听取决于谱面是否带 automation，GP 首拍常带，见网页注释 `ScorePlayer.svelte:2675-2677`）。
3. **数据契约缺字段导致 UI 与后续实现都无法做对**：`load` 载荷没有 `category`（`NativePlayerPane.swift:1108-1114`），`trackSnapshot()` 没有 `sourceName/sourceFlavor/instrumentFlavor`（`player.js:563-584`），Swift `NativePlayerTrack` 也没有这些字段（`NativePlayerPane.swift:94-108`）；音色菜单只能显示 GM 名与 1 基编号（`NativePlayerPanels.swift:36-50`），打击乐判定依赖 `track.isPercussion`（AlphaTab 的 `Track` 没有该属性，属性在 `Staff` 上），极可能把鼓轨当旋律轨。**P1（UI）→ 也是 P0 修复的前置条件**。

---

## 1. 网页版判定模型（实现必须照抄的部分）

### 1.1 运行时状态字段（`ScorePlayer.svelte:277-314`）

| 字段 | 语义 | 初始值/来源 |
|---|---|---|
| `index` | score 音轨下标（不是"可见列表下标"） | 遍历 `sourceScore.tracks` 序号 |
| `name` | 面板显示名 | `原谱 · …` / `打击乐` / GM 名；见 §3 |
| `sourceName` | 原谱显示名（override 时用于回退） | 同初始 `name` |
| `sourceProgram` | 原谱 MIDI program | `track.playbackInfo.program`，非法→0 |
| `sourceFlavor` | 原谱音源库：`'gm' \| 'ukulele'` | `sourceInstrumentFlavor(category, tuning, sourceProgram)` |
| `instrumentFlavor` | **当前**音源库 | override 时 `'gm'`，否则 `sourceFlavor` |
| `instrumentOverride` | 是否用户显式改过音色 | false |
| `program` | 当前有效 program（打击乐=128） | percussion ? 128 : sourceProgram |
| `percussion` | 打击乐轨 | `isPercussionTrack(track)`（看 `track.isPercussion` **或任一 staff.isPercussion**） |
| `show/muted/soloed` | 可见/静音/独奏 | true/false/false |
| `volume` | 0–100 百分数 | `trackVolumePercent(playbackInfo.volume)` |

持久化用的派生视图（`ScorePlayer.svelte:304-314`）：`program = min(127, instrumentOverride ? program : sourceProgram)`；**这是 resume 兼容的关键：原谱未 override 时持久化的是 sourceProgram，而不是"当前 program"。**

### 1.2 音源库 flavor 判定（唯一入口）

`resolveScoreAuditionSourceFlavor(track, category)`（`src/lib/player/scoreAuditionResources.ts:105-112`）：
- 条件三者同时满足才 `'ukulele'`：`category === 'ukulele'`、**任一 staff 的 `tuning` 长度为 4**（`isFourStringTrack`，:96-98）、`playbackInfo.program ∈ {0,24,25}`（`UKULELE_PROGRAMS`，:63）；
- 否则一律 `'gm'`。
- 显式 GM 选择**不得**再被反向推断回 ukulele；网页靠运行时克隆字段 `track.mimiSoundfontFlavor = 'gm'` 固化（`scoreInstrumentOverrides.ts:11-18` + `ScorePlayer.svelte:2674`），plan 只信这个运行时标记，不信 category/tuning（`scoreAuditionResources.ts:147`，测试 `tests/score-audition-resources.test.mjs:94-127`）。

`sourceInstrumentFlavor(category, tuning, program)` 是上面函数的轻量包装（`scoreInstrumentOverrides.ts:12-18`）。

### 1.3 SoundFont 常量与校验（`src/lib/player/verifiedScoreSoundfont.ts`）

- `SCORE_GM_SOUNDFONT_URL = '/soundfonts/sonivox.sf2'`（:23）
- `SCORE_UKULELE_SOUNDFONT_URL = '/storage/soundfonts/ukulele_fast.sf2'`（:24）
- 两个文件均带 SHA-256 固定校验（:26-32），加载后必须 sha256 匹配（:385-432）并做 SF2 结构校验（:108-130, :148-256）。
- ukulele 源库只有 `bank 0 / program 0 / 24 / 25` 三个预设，名字分别是 `Ukulele Acoustic` / `Ukulele Nylon` / `Ukulele Steel`（见证据附录 A.1 的实测 preset 表）。**因此 uke 库不能整包 append**：整包 append 会把 bank 0 program 0（钢琴）也覆盖成尤克里里原声，所以网页按 preset 过滤后再 append。

---

## 2. Q1：默认"原谱音色"如何选 SoundFont

### 2.1 计划生成 `planScoreAuditionSoundfonts(tracks)`（`scoreAuditionResources.ts:127-168`）

算法（逐步，实现照抄）：

1. 遍历**全部** score tracks（不是只有可见轨）：
   - 打击乐轨（`isPercussionTrack`，:92-94）：登记 `{bank:128, program:0, flavor:'gm'}`，preset key `128:0`；若同 key 已被标为其它 flavor → conflict。
   - 普通轨：`programsUsedBy(track)`（:71-90）= 初始 `playbackInfo.program` **并集** 所有 beat 上 `automation.type === 2 | 'Instrument'` 的 `value`（合法 0–127）。
   - 对每个 program：`flavor = track.mimiSoundfontFlavor === 'ukulele' && program ∈ {0,24,25} ? 'ukulele' : 'gm'`（:147-149）。
   - preset key 用 `bank:program`（不含 flavor）；**同一个 bank:program 被两条轨要求不同 flavor 时返回 `{ok:false, reason:'conflicting-program', bank, program}`**（:150-155）。这就是"冲突规则"：AlphaTab 的 preset 表按 bank+program 唯一索引 + last-match，无法让同 program 同时响两种音源，只能 fail closed。
2. 排序：`gm` 优先（priority 0），ukulele 后（priority 1）；同 flavor 内 bank、program 升序（:160-163）。
3. `urls`：按 presets 顺序映射 flavor→URL 并去重 → 典型结果 `['/soundfonts/sonivox.sf2', '/storage/soundfonts/ukulele_fast.sf2']`（:164-166）。
4. 仅 percussion 的曲目 → `[sonivox]`；纯 ukulele 单轨 → 只有 `[ukulele_fast]` 也是合法计划（但音源文件是**过滤后**的单 preset 载荷，见 2.2）。

### 2.2 加载（`ScorePlayer.svelte:978-1109` + `verifiedScoreSoundfont.ts:439-527`）

- `loadVerifiedScoreSoundfontPlan(presets)`：GM 只取一份整库 `bytes`；**每个 ukulele preset 各生成一份只含该 preset 的过滤 SF2**（`filterScoreSoundfontPreset`，:326-331；实现为只重写 `phdr`：保留目标 preset 记录 + EOP，并保持原 `pbag/pgen` 索引，:297-323）。输出顺序 = 计划顺序（GM 在前，uke 逐个在后，:508-526）。
- 逐个 `loadSoundFontAwait(bytes, append = index > 0)`：**第一包 append=false（清空音源库），后续 append=true**（`ScorePlayer.svelte:1006-1025`，`soundfontLoadReceipt.ts:70-188` 保证一次只有一包在飞、带 15s 超时/失败毒化）。
- AlphaTab 的 last-match：`loadSoundFont` 把 SF2 追加进 `_loadedSoundFonts`（append=true 不清空）；预设查找 `_getPresetIndex` 从 `presets` 数组**尾部往前**扫（证据附录 A.2），所以后 append 的 uke 单 preset 精确覆盖同 bank:program 的 GM 预设，其他 program 不受影响。
- 计划键 `scoreSoundfontPlanKey = presets.map(bank:program:flavor).join('|')`（:949-957）；键变化就**整份重载**（append=false 打头，:993-1030）。重载过程中反复重算 plan，若与请求键不一致就直接放弃本次加载（防止用户在加载期间又改音色）。
- 成功后 `loadedPrograms = new Set(tracks.map(t => t.program))`，`soundReady = 计划键一致 && 每个当前 track.program 都在 loadedPrograms`（:1036, :1053-1063）。失败置 `soundError` + `soundReady=false`，并提供"重试音源"按钮（:3078-3080, :1671-1680）；若 API 的 receipt 已毒化则整页重载（:1671-1677）。

### 2.3 冲突处理（fail closed）

`failClosedForSoundfontConflict`（`ScorePlayer.svelte:955-976`）：播放意图作废、`playRequested=false`、`api.pause()`、释放音频焦点、`soundReady=false`、`soundError = renderNotice =` 文案：
`bank {b} program {p} 同时需要 GM 与原谱尤克里里音源，当前音轨组合无法安全播放。播放已暂停；请恢复冲突音轨的原谱音色，或调整另一条音轨。`
触发点：切音色前 `changeInstrument`（:2703-2706）、播放前 `playPause`（:2010-2014）、加载音源时（:986-989）。**原生端目前完全没有这条路径。**

### 2.4 音量默认值

`trackVolumePercent(volume)`（`src/lib/player/scorePlayerCorrectness.mjs:2-6`）：`clamp(volume,0,16)/16*100` 四舍五入，缺省按 16 → 100。面板滑块 0–100；传给 AlphaTab 时 `/100`（`ScorePlayer.svelte:1527, 2665`）。原生端 `createTrackMixState` 直接 `volume: 1`（`player.js:614`），**忽略 `playbackInfo.volume`**（P2，若谱面自定义音量会偏响）。

---

## 3. Q2：音轨面板控件与文案

网页版是**两个互斥抽屉**，从工具栏两个按钮进入（`ScorePlayer.svelte:3009-3028`）：

| 入口按钮 | 面板 | 控件（逐轨） |
|---|---|---|
| `音轨分层` | tracksPanel（:3082-3135） | ① 显示 checkbox（`显示音轨：{name}`）② 静音按钮（`静音`/`已静音`，`aria-pressed`）③ 独奏按钮（`独奏`/`已独奏`）④ 音量 range 0–100 step 1（`音量：{name}`） |
| `音色乐器` | instrumentsPanel（:3137-3177） | 每轨一个 `<select>`：第一项 `value="source"` 文案 = `tr.sourceName`；随后 `GM_INSTRUMENTS` **扁平 128 项**，文案 `"GM {program} · {name}"`（:3168-3171）；**打击乐轨 `disabled={tr.percussion}`**（:3164）；选择 `source` → `restoreSourceInstrument(i)`，否则 `changeInstrument(i, Number(value))` |

文案/命名规则（实现必须一致）：

- 普通轨：`sourceName = percussion ? '打击乐' : sourceNameFor(sourceProgram, sourceFlavor)`（:791）
  - gm：`原谱 · {GM 名}`（:542）
  - ukulele：`原谱 · 尤克里里（原声|尼龙弦|钢弦）`，program 0/24/25 分别对应（:537-543）
- override 后 `name = instrumentName(program)`（纯 GM 名，无"原谱 ·"前缀）（:1506, 2699-2701）
- 面板显示用 `tr.name`（:3104, :3156）；`select` 当前值 = `tr.instrumentOverride ? tr.program : 'source'`（:3158）
- 音源错误条：`{soundError}` + `重试音源` 按钮（:3078-3080）；状态文案：`正在准备音源 / 音源未就绪 / 准备就绪 / 尚未就绪`（:3073），播放键文案 `准备中…`（:2830）
- 无音轨时面板不渲染（`tracks.length===0`）；面板打开不影响播放（暂停由 focus/页面策略决定，不因开面板暂停）
- `GM_INSTRUMENTS` 是 `ALL_GM_INSTRUMENTS.map(x => [x.program, x.name])`，顺序 0→127，**不分组**（`src/lib/gmInstruments.ts:187`；名字为中文本地化名，如 0 原声大钢琴 / 24 尼龙弦吉他 / 25 钢弦吉他 / 105 班卓琴）

---

## 4. Q3：切换音色 / 恢复原谱的具体行为

### 4.1 `changeInstrument(i, program)`（`ScorePlayer.svelte:2692-2715`）

顺序（每一步都不能省）：
1. `markResumeIntent()`（触发 resume 落盘）。
2. 忽略感染：`tr.percussion` 或非法 program → return。
3. `applyTrackInstrument(score.tracks[tr.index], program)`（:2667-2690）：
   - 校验 0–127；
   - `track.playbackInfo.program = program`；
   - `track.name = track.shortName = instrumentName(program)`；
   - `track.mimiInstrumentOverride = true`；**`track.mimiSoundfontFlavor = 'gm'`**（这是让 plan 放弃该轨 uke 库的开关）；
   - **遍历全部 staff/bar/voice/beat/automation，把 `type === Instrument(2)` 的 `value` 改成新 program**（注释解释：MidiFileGenerator 先发 track 初始 Program Change，随后逐拍 automation 会覆盖，不改就"切了没声/没变"）。
4. 更新 `tracks` 状态：`{program, name, instrumentOverride:true, instrumentFlavor:'gm'}`。
5. `publishPrimaryInstrumentSelection()`（把主轨音色广播给全局/指板试听，带 flavor + override + scoreId）。
6. 重新 `planScoreAuditionSoundfonts(score.tracks, category)`：冲突 → `failClosedForSoundfontConflict` 并 return（此时 score 已被改，UI 报错要求用户恢复）。
7. 若 api 存在：`withRenderPreservingPosition(async () => { await loadSoundfonts(); await enqueueRender(() => renderScore(score, visibleTracks)); }, { reloadMidi: true })`。
   - `loadSoundfonts()` 检测计划键变化 → 整份重载音源（append=false 打头）。
   - `withRenderPreservingPosition`（:2301-2379）：若正在播放 → `interruptLoopLap()`、`audioFocusRetainedForRender=true`、`api.pause()`；执行 fn；`reloadMidi` 时 `loadMidiForScore()` 并 `await waitForMidiLoaded()`；**恢复 `tickPosition = clampTick(旧 tick)`**；若 `soundReady` 为假则保持暂停并给出 `音源尚未就绪…请恢复原谱音色或重试音源`（:2324-2334）；否则 `api.play()` 恢复播放。
   - 注意 `renderScore` 传的是**同一个 score 对象**，AlphaTab 不会触发 `scoreLoaded`、不会自动重载 MIDI，所以必须显式 `loadMidiForScore()`（注释 :2296-2299）。

### 4.2 `restoreSourceInstrument(i)`（`ScorePlayer.svelte:2717-2737`）

1. 前置：存在、非打击乐、确实有 override、`scoreJsonRaw` 存在（否则 return，即"没改过就点恢复"是 no-op）。
2. `tracks` 状态回 `{program: sourceProgram, name: sourceName, instrumentOverride:false, instrumentFlavor: sourceFlavor}`。
3. **从原始 JSON 重建 score**：`buildScoreFromJson(scoreDisplayMode)`（丢掉所有运行时改名/program/automation 改动）→ `score = restoredScore` → `rebuildTrackState(restoredScore)`（对其它仍有 override 的轨重放 `applyTrackInstrument`）→ `publishPrimaryInstrumentSelection()`。
4. `withRenderPreservingPosition(async () => { await loadSoundfonts(); await enqueueRender(() => renderScore(restoredScore, visibleTracks)); }, {reloadMidi:true})`。
   - 这里是**新 score 对象**：`_internalRenderTracks` 会触发 `scoreLoaded` + 自动 `loadMidiForScore()`，随后又显式 load 一次并等 `midiLoaded`；恢复位置与播放状态由 wrapper 统一处理。
   - 由于是全新的 score，Instrument automation 回到原谱值，**"恢复原谱"是真正彻底恢复**。

### 4.3 播放中转换的修复要点

`withRenderPreservingPosition` 保证：暂停 → 变更 → MIDI 重载完成 → 位置回写 → （原在播）`play()`；失败路径会把 UI 置为非播放并提示，不静默。位置用 `api.tickPosition`（AlphaTab 会按 tick 钳制），不依赖 `curTick` 显示值。

---

## 5. Q4：音色 override 的持久化语义

### 5.1 写入（`ScorePlayer.svelte:304-314` → `practiceTrackMix`）

每条 resume trackMix：`{index, muted, soloed, volume(0-100), program = override ? program : sourceProgram, instrumentOverride}`。
- 未 override 的 ukulele 轨持久化的是 `program: 25, instrumentOverride: false`（**不是 128，也不是 uke 标号**）。
- 打击乐轨也是 `instrumentOverride:false`，program 存 sourceProgram。

### 5.2 恢复（`ScorePlayer.svelte:2159-2180` + `scoreInstrumentOverrides.ts:25-41`）

`resolveResumeInstrument(sourceProgram, savedProgram?, savedOverride?)`：
- `savedOverride === true`：合法 savedProgram → override；非法 → 回原谱。
- `savedOverride === false`：**无条件回原谱**（即使 program 数值不同）。
- `savedOverride === undefined`（旧数据）：合法且 `savedProgram !== sourceProgram` → 视为 override；相等 → 原谱。
- 恢复流程：先 `tracks = 全部回 source`（:2146-2152）→ 从 JSON 重建 score → `rebuildTrackState` → 设 visibleTracks → 逐条 trackMix 应用 `resolveResumeInstrument`（override 才 `applyTrackInstrument`）→ `publishPrimaryInstrumentSelection()` → **`await loadSoundfonts(...)`**（按新计划重载音源）→ `renderScore(restoredScore, visibleTracks)` + 等 MIDI → `applyTrackMix(restoredScore, true)` → 恢复 loop/倍率/位置。
- 打击乐轨不参与 override（`(percussion ? {} : …)`，:2170-2174）。
- 校验：`preparePracticeResumeSettings` 过滤非法 index，`instrumentOverride` 若存在必须 boolean，旧记录缺字段保持可读（`src/lib/practice/practiceProgress.ts:158-185`）。

---

## 6. Q5：原生实现差异清单（逐项：现象 / 证据 / 严重度 / 建议改法）

> 原生侧共同前提：`player.js` 里**没有任何** `loadSoundFont`、`category`、`flavor`、`sourceName` 概念；Swift 侧也没有对应字段。下面 D1–D14 按"默认音色 → 切音色 → 恢复 → 持久化 → 面板/文案 → 辅助"排序。

### D1【P0】默认音源只有 GM sonivox，ukulele 曲目音色错误

- 现象：打开尤克里里曲（category=ukulele，program 25）→ 听到 GM「Steel-str.Gt 钢弦吉他」，不是 uke 音色；网页版听「原谱 · 尤克里里（钢弦）」。ukulele 类别下 program 0/24/25 三轨全部错；`1wmj8hqHnYf`、`1sdcWsfNEe0` 两首样例均属此情况。
- 证据：
  - `player.js:1074` `settings.player.soundFont = ${BASE}/soundfont/main`（唯一音源入口）；
  - `player.js` 全文无 `loadSoundFont`/`ukulele`/`category`/`flavor`（grep 结果见证据附录 A.3）；
  - 路由其实已就绪：`PlayerResourceSchemeHandler.swift:21-31, 87-98` 已能提供 `/soundfonts/sonivox.sf2` 与 `/storage/soundfonts/ukulele_fast.sf2`（`ukuleleSoundFontURL` 建好却无人请求）；
  - 实测 sonivox.sf2 preset：bank0 0–127 齐全（含 24 Nylon-str.Gt、25 Steel-str.Gt），无 Ukulele 预设；ukulele_fast.sf2 只有 bank0 0/24/25 = Ukulele Acoustic/Nylon/Steel（证据附录 A.1）；
  - 网页基线：`verifyScoreSoundfont.ts:23-24`、`scoreAuditionResources.ts:127-168`、`ScorePlayer.svelte:978-1109`。
- 建议改法（最小闭环，分 3 层）：
  1. **数据契约**：`load` 载荷增加 `category`（Swift `NativePlayerPane.swift:1108-1114`，值取 `model.personalScore?.category ?? model.item?.category`，归一化 `guitar|ukulele|bass`，可复用 :2557 的校验逻辑）；`player.js:1410` 保存 `scoreCategory = String(parameters.category || 'guitar')`。
  2. **player.js 迁移纯函数**（不要直接 import TS；通过 `score-rendering-entry.ts`/`practice-runtime-entry.ts` 暴露到 `window.MimiScoreRendering`/`NativePracticeCore` 再调用，避免双份逻辑）：`resolveSourceFlavor(track, category)`、`isPercussionTrack(track)`、`programsUsedBy(track)`、`planSoundfonts(tracks)`（返回 `{ok,presets,urls}` 或 conflict）、`filterScoreSoundfontPreset(bytes,bank,program)`。同时给 score track 打运行时标记：`track.mimiSoundfontFlavor=sourceFlavor`（`buildTrackMixState` 时）并在 override 时置 `'gm'`。
  3. **加载**：`createApi` 里把 `settings.player.soundFont` 置空/删除，改为载入流程末尾（`renderScore` + MIDI 就绪后）执行 `loadSoundfontPlan()`：按 plan 顺序 `fetch(url)` → `api.loadSoundFont(bytes, index>0)` → 等 `api.soundFontLoaded`（每包一次，带 15s 超时；失败发 `soundError` 并禁止播放）。uke 包必须是**单 preset 过滤载荷**，否则 bank0 program0 的 uke 预设会覆盖钢琴（见 §2.3）。若不想在 JS 里移植 SF2 重写，可在构建期用 `tools/build_ukulele_sf2.mjs` 生成 `ukulele_0/24/25.sf2` 放到 `Resources/Player/soundfonts/` 并在 scheme handler 加白名单（与网页二进制等价的输出，但要保证与 `filterScoreSoundfontPreset` 同语义：只含目标 preset + EOP）。
  4. AlphaTab 侧不要自己维护"已加载 program 集合"：每次 MIDI 重载后 AlphaSynth 会按新 `instrumentPrograms` 重新解析 `_loadedSoundFonts`，append 顺序保持即可（证据附录 A.2）。
- 验收：scheme 请求清单出现 `/soundfonts/sonivox.sf2`（纯 uke 曲可只出现 uke）+ `/storage/soundfonts/ukulele_fast.sf2`（或过滤资产）；Audition 默认预设名 `Ukulele Steel`；MIDI program change 仍是 bank0/25。

### D2【P0/P1】"恢复原谱音色"不回写 Instrument automation → 恢复无效

- 现象：对原谱 program 25 的 uke 轨改成 GM 40（小提琴）→ 点"恢复原谱音色"→ 面板显示回到 25，但**声音仍是小提琴**（凡带 Instrument automation 的谱面）。同理 `restoreResume` 的"回原谱"分支。
- 证据：
  - 覆盖时写 automation：`player.js:586-600`（`applyTrackProgram` 遍历 beats 改 `automation.value`）；
  - 恢复时只改 playbackInfo/name：`player.js:1961-1967`（**没有 automation 循环**）；
  - 同一文件 `restoreDefaults` 却写了 automation 恢复循环：`player.js:2286-2302`（反证这是遗漏）；
  - `restoreResume` 回原谱分支同样遗漏：`player.js:1890-1896`；
  - 网页基线：`ScorePlayer.svelte:2667-2690`（改 automation）、`:2675-2677` 注释明确 GP 首拍会写死原音色、`:2717-2737` 用原始 JSON 重建 score 彻底恢复。
- 建议改法：新增 `captureSourceInstrumentState(track)`（在首次 `createTrackMixState`/`scoreLoaded` 时保存每条轨**原始 automation 值列表**：`Map<beat, number>` 或 JSON 片段），`restoreTrackSourceProgram(track, state)` 同时写 `playbackInfo.program / name / shortName` **和全部 Instrument automation = state.sourceProgram**；或者更彻底：像网页一样持有 `rawScoreJson`（player.js 已有 `rawScoreJson`/`rebuildJsonScore`，`player.js:52, 1987-2140`），恢复原谱时直接 `rebuildJsonScore`（会从原始 JSON 重建，automation 全回源），代价是要重排/重载 MIDI —— 与网页 `restoreSourceInstrument` 完全等价，推荐这条（复用 `performJsonScoreRebuild` 的 `reloadState` 机制即可保住 mix/位置/播放状态）。
- 顺带修 D2b：`restoreResume` 在恢复源音色时也应从原始 JSON 重建（它已经走 `rebuildJsonScore`，只需把 `track.playbackInfo.program` 的写回改成"重建后再写"，或在重建后按 source 重放）。
- 验收：probe 步骤 4（`setTrack(0,'restoreProgram',true)`）后 MidiFile 中该 channel 所有 program change 都回到 25。

### D3【P1】打击乐轨判定错误（Track 没有 isPercussion）

- 现象：原生面板可能不把鼓轨标成打击乐：显示 GM 音色菜单可点、名称不是"打击乐"、resume 持久化 program 错误；甚至允许给鼓轨改 program（网页是禁用的）。`1xpyKV313Vh`（4 轨含鼓）可复现。
- 证据：
  - `player.js:568` `const percussion = !!track.isPercussion || program === 128;`，`:587` 同款；AlphaTab 的 `Track` 无 `isPercussion` 属性，该布尔在 `Staff`（网页正是这么判的：`scoreAuditionResources.ts:92-94`、`ScorePlayer.svelte:525-527`）；
  - `createTrackMixState` 也只看 `track.isPercussion`：`player.js:621`；
  - Swift 解码 `percussion: value["percussion"] as? Bool ?? false`：`NativePlayerPane.swift:2270`；面板据此禁用音色 select：`NativePlayerPanels.swift`（对标网页 `ScorePlayer.svelte:3164`，原生目前无 disabled）。
- 建议改法：`player.js` 增加 `isPercussionTrack(track)`（`track.isPercussion===true || staves.some(s=>s.isPercussion===true)`），替换 `:568,587,621` 与 `setTrack` 的 percussion 判断；`trackSnapshot` 的 `program` 对打击乐统一输出 128、`percussion:true`；Swift 侧不需要改判定，但需要在菜单上 `.disabled(track.percussion)`。
- 备注：鼓轨在 AlphaTab 里走 channel 9/bank128，program 数值本身不决定音色；显示 128 只是 UI 约定。probe 步骤 6 会给出 `trackSnapshot.percussion` 与 `staff.isPercussion` 的实际值。

### D4【P1】没有音源计划/冲突/错误状态，切音色缺少 fail-closed 与重试

- 现象：原生切音色只做 `applyTrackProgram + renderWithAudioReload`，没有任何"该 program 需要哪个音源库/是否会覆盖别人"的判断；一旦按 D1 引入 uke 库而不同时引入冲突检测，就会出现"同 program 两条轨一边 GM 一边 uke → 后加载的库悄悄覆盖前一条"，即无声/错音，且错误不呈现给用户。
- 证据：`player.js:1954-1960`（program 分支只有 apply + reload）；`player.js:628-637` 无音源逻辑；对比网页 `ScorePlayer.svelte:2703-2707, 955-976, 1053-1066, 3078-3080`（conflict fail closed + soundError + 重试按钮）。
- 建议改法：在 `applyTrackProgram` 之后、`renderWithAudioReload` 之前：`const plan = planSoundfonts(api.score.tracks, scoreCategory)`；`if (!plan.ok) { send('soundError', {message: conflict 文案, bank, program}); send('tracks', ...); return; }`；若 `planKey !== loadedPlanKey` 则 `await loadSoundfontPlan(plan)` 成功后再 reload；新增 `retrySoundfonts()` 暴露给 Swift（`window.NativePlayer.retrySoundfonts`）与桥事件 `"retrySoundfonts"`。Swift：`NativePlayerModel` 增 `@Published var soundError: String?`，在 `receive` 里处理 `soundError`/`soundPlan`，面板顶部显示错误条 + "重试音源"按钮（对标网页 :3078-3080）。

### D5【P1】切音色时播放位置/状态恢复不够严谨（位置可能瞬时跳回）

- 现象：播放中切音色 → 原生 `renderWithAudioReload` 先 `pause()` 记 `targetTick`，重排+MIDI 完成后 `requestSeek(targetTick,false)`（**不等待 seek 回执**）立即 `play()`（`player.js:2191-2198`）；若 seek 未生效，会从旧位置/0 开始发声几拍，再由 seek 校正。网页版等 `waitForMidiLoaded` 后先写 `tickPosition` 再 `play()`，且用 seek receipt 确认（`ScorePlayer.svelte:2316-2344` + `seekWithReceipt`）。
- 建议改法：复用文件内已有的 `seekAndWait()`（`restoreResume` 用它，`player.js:1922`）或 `pendingSeek` 回执机制：`await seekAndWait(clampedTick)` 后再 `play()`；超时则发 `send('error')` 并保持暂停，不要带错位播放。注意保持 `preserveAudioFocusForRender` 现有语义。
- 备注：`renderWithAudioReload` 已经 `await` 了 `midiLoaded`（`player.js:2171-2189`），这点是对的，不需要改。

### D6【P2】resume 持久化语义与网页不一致（legacy override / percussion / volume 量纲）

- 现象：
  a. 原生只认 `saved.instrumentOverride === true`，旧数据（字段缺失 = nil）里"program 与原谱不同"的 override 会丢（网页 `resolveResumeInstrument` 会按"不同即 override"兼容，`scoreInstrumentOverrides.ts:25-41`）。
  b. 原生 `PlayerTrackMix.volume` 是 0…1（`MIMICore/PracticeModels.swift:60-72`、`player.js:1899` clamp 0..1），网页是 0…100；若未来导入网页断点需换算。
  c. 原生保存 `program: track.program`（含打击乐），网页保存 `override ? program : sourceProgram` 且打击乐不参与 override（`ScorePlayer.svelte:304-314`）。
- 证据：`NativePlayerPane.swift:2327`（保存）、`player.js:1881-1903`（恢复）；网页见 §5。
- 建议改法：Swift 保存时 `program: $0.instrumentOverride ? $0.program : $0.sourceProgram`（打击乐强制 `sourceProgram`）；`player.js restoreResume` 移植 `resolveResumeInstrument(sourceProgram, saved.program, saved.instrumentOverride)`（注意 `undefined` 三分支）；volume 保持原生 0..1 但加注释/版本字段，或统一为 0..100（需同时改 Swift 滑块、resume 编解码、`changeTrackVolume` 换算）。风险：改动 resume schema 要考虑旧数据，`instrumentOverride` 已是 optional，直接扩展安全。

### D7【P2】面板文案/枚举与网页不一致（含 uke 名、GM 编号）

- 现象：
  - 音色菜单 "恢复原谱音色 · \(instrumentName(track.sourceProgram))"（`NativePlayerPanels.swift:37`）在 uke 轨显示 GM 名「钢弦吉他」；网页显示「原谱 · 尤克里里（钢弦）」（`ScorePlayer.svelte:537-543`）。
  - GM 项 "\(program+1). \(name)"（1 基，`NativePlayerPanels.swift:42`）vs 网页 "GM \(program) · \(name)"（0 基，`ScorePlayer.svelte:3169-3171`）。
  - 恢复原谱项永远可点（无 override 时是 no-op）；网页 select 第一项即 `sourceName`，语义等价但文案不同。
  - 原生菜单未对打击乐禁用（`NativePlayerPanels.swift:36-50` 无 `.disabled(track.percussion)`）。
- 建议改法：`NativePlayerTrack` 增 `sourceName`（桥数据），菜单 label 用 `track.instrumentOverride ? instrumentName(track.program) : track.sourceName`；恢复项文案 `恢复原谱音色 · \(track.sourceName)`；GM 项改 `GM \(program) · \(name)`；`.disabled(track.percussion)`。`instrumentName` 仍从 `gmInstruments` 查表（名单与网页 `GM_INSTRUMENTS` 同源，`practice-runtime.bundle.js:455`）。

### D8【P1】曲目类别未进入播放器 → 所有 flavor/默认音色逻辑无输入

- 见 D1 第 1 层。证据：`NativePlayerPane.swift:1108-1114` 载荷仅 `loadID/kind/title/artist/bpm`；`player.js:1410-1424` 只保存 `{...parameters}`，`scoreSourceMetadata` 随后只被用于 title/artist/tempo（`player.js:1107-1116, 1162`），`category` 若不加就永远拿不到。同时 Swift `NativePlayerTrack`（:94-108）需加 `sourceName: String`、`sourceFlavor: String`、`instrumentFlavor: String`，`receivePlayerSnapshot`（:2264-2277）对应解码 `as? String ?? "gm"`。

### D9【P1】原生把 AlphaTab 生成轨（@$Strumming$@/@$Chords$@）也列进面板

- 现象：网页 `buildTracks` 会跳过名为 `@$Strumming$@` / `@$Chords$@` 的合成轨（`ScorePlayer.svelte:783-785`），原生 `createTrackMixState` 对全部 `score.tracks` 建状态（`player.js:604-625`），面板因此可能多出这两条轨；若它们带 notes 还可能被渲染/发声。
- 建议改法：`player.js` 建状态时同样跳过这两个名字（但**保留 index**，`trackMix` 用 `state.index`），`trackSnapshot` 输出基于 `trackMix` 而不是全部 tracks；`visibleTrackIndexes` 也要排除。风险低，probe 步骤 1/6 可观察 4 轨曲目实际轨数。

### D10【P2】默认音量未取 `playbackInfo.volume`

- 见 §2.4。`player.js:614` 固定 `volume:1`；建议 `volume = clamp(Number(track.playbackInfo?.volume ?? 16)/16, 0, 1)`（保持原生 0..1 量纲），并在 `trackSnapshot` 输出该值。网页等价 `trackVolumePercent`。风险：resume 里旧 volume=1 会被当成 100%，可接受。

### D11【P2】音源错误/进度状态未接入 UI（soundProgress 有、soundError 无）

- 现象：`player.js:1184-1190` 只转发 `soundProgress`/`soundReady`；原生 `audioReady=false` 时只显示"等待音源加载完成"（`NativePlayerPane.swift:1011`），没有错误、没有重试入口；若 GM 音源加载失败（文件缺失/超时），用户只能重开。网页有错误条 + 重试（`ScorePlayer.svelte:3078-3080, 1671-1680`）。
- 建议改法：`createApi` 增加 `soundFontLoadFailed` 监听（AlphaTab 1.8.4 `player.soundFontLoadFailed` 事件存在，见 `soundfontLoadReceipt.ts:19-22`）→ `send('soundError',{message})`；Swift 增加错误展示 + `retrySoundfonts` 桥；`audioReady` 保持 fail-closed（canPlay 已依赖它，`NativePlayerPane.swift:1004`）。

### D12【P2】无音源完整性校验（SHA-256 / SF2 结构）

- 网页对两个 SF2 做固定 SHA-256 + 结构校验后才交给 AlphaTab（`verifiedScoreSoundfont.ts:26-32, 385-432, 108-256`）。原生直接由 AlphaTab 从 `/soundfont/main` 拉取（player.js:1074），损坏/替换的文件会直接导致播放异常且无明确错误。
- 建议：最低限度在 `loadSoundfontPlan()` 里校验大小与 SF2 magic（`RIFF/sfbk`），更稳妥是移植 SHA-256（WKWebView 有 `crypto.subtle`，网页同款）；若采用"构建期过滤资产"方案，可在构建脚本里校验并在 app 内保留校验和。P2（可后续做，但建议与 D1 一起落）。

### D13【P2】`setTrack('show')` 与网页的可见性语义细节

- 两边都是"隐藏=同时静音 + renderTracks"（网页 `ScorePlayer.svelte:2634-2646`，原生 `player.js:1933-1942`）。差异：网页在 `buildTracks` 兜底 `visibleTracks=[0]`（:816），原生 `setTrack('show')` 用 `visibleTrackIndexes.length>0` 守卫（:1939-1941）；全隐藏时两边都不重排，行为等价。另原生隐藏后 `send('tracks')` 会更新面板，但**没有** `applyTrackMixToApi` 之外的状态同步问题。结论：无 P0/P1 差异，仅在实现 D9 时一并检查 `visibleTrackIndexes` 的 index 基准。

### D14【P2】原生无 `publishPrimaryInstrumentSelection` 等价物（指板/全局音色广播）

- 网页切换音色后广播全局 program + flavor（`ScorePlayer.svelte:549-559`），虚拟指板试听据此选音源（:3189-3191）。原生播放器指板面板目前仅作展示/高亮，无音频试听路径（`NativePlayerFretboard.swift` 无音频播放代码），暂不影响听感；若后续加指板试听，需复用同一 flavor 字段。仅记录，不在本次修复范围。

---

## 7. 建议实施顺序（最小可验证路径）

1. **先修数据契约**（D8）：`category` 进 load；`sourceName/sourceFlavor/instrumentFlavor/percussion` 进 snapshot；Swift model/面板接字段（D3/D7 可同批）。此时 probe 可测出"面板显示原谱名/打击乐正确"。
2. **移植纯函数**：`resolveSourceFlavor` / `isPercussionTrack` / `programsUsedBy` / `planSoundfonts` / `filterScoreSoundfontPreset`（建议放回 `src/lib/player/` 并通过两个 entry 暴露，避免三份实现）。单测直接复用 `tests/score-audition-resources.test.mjs`、`tests/score-instrument-overrides.test.mjs` 的用例语义。
3. **接音源加载与冲突**（D1/D4/D11）：`loadSoundfontPlan()`、`retrySoundfonts()`、`soundError` 桥与 Swift 错误条；plan 键变化整份重载（append=false 打头）。
4. **修恢复语义**（D2/D6）：`restoreProgram` 走原始 JSON 重建（或 automation 回写）；`restoreResume` 用 `resolveResumeInstrument` 三分支；保存 program 用 sourceProgram。
5. **修播放衔接**（D5）：切音色后 `await seekAndWait` 再 `play()`。
6. **收尾**（D9/D10/D12/D13）：合成轨过滤、默认音量、校验、清理。

每步都可独立用 task-2 的探针复测（`setTrack` 驱动 + scheme 请求清单 + MidiFile program-change + PCM 非零块），建议修复基线与修复后各跑一遍同命令。

## 8. 验收标准（对应任务完成定义）

| # | 验收点 | 判定证据 |
|---|---|---|
| 1 | `1wmj8hqHnYf`（ukulele）加载后请求 `/storage/soundfonts/ukulele_fast.sf2`（或等价过滤资产），且 `/soundfonts/sonivox.sf2` 在 uke 单音源场景可仅 uke | scheme 请求清单 |
| 2 | uke 轨默认预设名为 `Ukulele Steel`（program 25）/`Ukulele Nylon`（24）/`Ukulele Acoustic`（0）；面板显示 `原谱 · 尤克里里（钢弦）` | 桥/`trackSnapshot` + UI 截图 |
| 3 | 切 GM 40 后 MidiFile 中该 channel program-change 变为 40 且音频 PCM 变化；播放位置 tick 前后差 < 1 拍、`isPlaying` 保持 | probe 步骤 3 |
| 4 | `restoreProgram` 后 MidiFile 全部 program-change 回 25（含 automation 产生的） | probe 步骤 4 |
| 5 | 同 program 冲突（构造 GM25+uke25）→ 暂停、`soundError` 文案、播放键不可恢复播放，恢复原谱后可播 | 手工/单测 |
| 6 | 静音/独奏/音量/可见性立即生效，隐藏=静音，打击乐轨音色菜单禁用 | probe 步骤 5 + UI |
| 7 | resume 保存/恢复：override 保存 program+true；未 override 保存 sourceProgram+false；旧数据不同 program 视为 override | 单测/断点回读 |
| 8 | 无回归：GM 曲目（如 guitar 类别）仍只加载 sonivox，音色与 0.2.4 基线一致 | probe 对比基线 |

## 9. 风险与开放问题

1. **IBE 谱面是否普遍带 Instrument automation 未在本次只读分析中解码确认**（样例 `.ibe` 是原站 AR 格式，需运行时解码）。网页注释与 GP 转换惯例表明常见；probe 步骤 1 的 MidiFile program-change 数量可直接证实。若样例无 automation，D2 仍应修（否则 GP/MusicXML 导入路径必错）。
2. **ukulele 过滤载荷的实现位置**：运行时移植 SF2 重写（与网页 100% 同构，但 ~300 行 JS，风险高）vs 构建期生成 3 个单 preset 资产（简单、可测，但要确保 bank/program 与源文件一致、并进 scheme 白名单）。建议优先构建期资产，并在 `score-rendering-entry.ts` 里保留一个 Node 侧生成脚本/校验；若必须与网页字节级等价，再移植 `filterScoreSoundfontPreset`。
3. **GS/XG bank 兼容**：sonivox 有 bank 128/255 预设；`programsUsedBy` 只收集 program，不收集 bank。网页也只按 bank 0/128 处理（`scoreAuditionResources.ts:137-157`），与现状一致，不扩大范围。
4. **`settings.player.soundFont` 的移除时序**：AlphaTab 构造函数会尝试预加载该 URL；若保留则每次都会先拉一次 sonivox（浪费且可能与手动 plan 加载冲突）。确认改为手动加载后需要初始化 `soundReady` 的等待逻辑（Swift `notifyReadyIfPossible` 依赖 `soundReady` 事件，不能漏发）。
5. 原生 `restoreResume` 目前是基于同一 score 对象做 `rebuildJsonScore` 后写回 program（而非网页的新对象重建），改 D2 时要保证 `displayMode/loop/mix` 的重建路径一致，避免二次引入 D2 类问题。
