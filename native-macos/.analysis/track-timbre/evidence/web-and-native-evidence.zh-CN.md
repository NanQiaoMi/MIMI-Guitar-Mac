# 证据附录：网页版 SoundFont 行为 + 原生差异（只读实测/源码行号）

> 对应主文档 `parity-spec.zh-CN.md`。所有行号来自当前工作树（2026-10-27 只读分析），未改动任何文件。

## A.1 SoundFont 预设表实测（app Content 内的实际文件）

解析方式：Python 直接读 SF2 `RIFF/sfbk → LIST pdta → phdr` 记录（每 38 字节：20B 名称 + u16 program + u16 bank + u16 bagNdx）。文件来自
`/Users/mimi/Documents/Codex/2026-10-24/l/outputs/Native-Mac-0.2.4/MIMI Guitar.app/Contents/Resources/Content/`（与 `public/soundfonts`、`public/storage/soundfonts` 同源）。

| 文件 | 大小 | preset 数 | 与音轨音色相关的预设 |
|---|---|---|---|
| `soundfonts/sonivox.sf2` | 1,351,896 B | 133 | bank0：0 `Piano 1`、24 `Nylon-str.Gt`、25 `Steel-str.Gt`、40 `Violin`、73 `Flute`、80 `Square Wave`、81 `Saw Wave`、105 `Banjo` …（bank0 全 GM 0–127）；bank128：0 `Standard`、40 `Brush`；另有 bank255 |
| `storage/soundfonts/ukulele_fast.sf2` | 1,205,140 B | 4（3 有效 + EOP 终止记录） | bank0：0 `Ukulele Acoustic`、24 `Ukulele Nylon`、25 `Ukulele Steel`；EOP |
| `storage/soundfonts/acoustic_guitar_fast.sf2` | 1,205,140 B | 4 | 与 ukulele_fast 预设表相同（历史/别名文件，播放器未用） |

结论：
1. 原生播放器当前唯一加载的 sonivox **没有 Ukulele 预设**，uke 曲目的 program 25 只能落到 `Steel-str.Gt`（听感错误的直接原因）。
2. uke 库是"bank0 + 0/24/25"的**同 bank 同 program** 覆盖型库；整包 append 会把 bank0 program0（钢琴）一起覆盖，因此网页必须"按 preset 过滤后 append"（见 A.2）。

## A.2 AlphaTab（随 app 打包的 1.8.x 运行时）last-match 与 append 语义

文件：`project/native-macos/Resources/Player/score-rendering.bundle.js`（内含 AlphaTab core）：

- `loadSoundFont(data, append)`：`append=false` 时清空 `_loadedSoundFonts`，随后 push 新 Hydra；`append=true` 直接 push（`score-rendering.bundle.js:37690-37707`）。
- 每次 `soundFontLoaded`/`midiLoaded` 后 `_checkReadyForPlayback()` 都会按 `instrumentPrograms`（当前 MIDI 用到的 program 集合）与 `percussionKeys` 重新 `loadPresets(soundFont, programs, percussionKeys, append)`，第一个包 append=false（替换 preset 表），后续包 append=true（追加）（`score-rendering.bundle.js:37707-37722`）。
- preset 合并：`if (!append || !this.presets) this.presets = newPresets; else for (const preset of newPresets) this.presets.push(preset);`（`score-rendering.bundle.js:37384-37385`）。
- 查找：`_getPresetIndex(bank, presetNumber)` **从数组尾部向前扫**，返回最后一个匹配 → 后 append 的库/预设覆盖先前的同 bank+program（`score-rendering.bundle.js:36880-36888`）。
- 这也解释了网页 `planScoreAuditionSoundfonts` 的排序（GM priority 0，uke priority 1）和"同一 program 两种 flavor = 冲突、必须 fail closed"。

## A.3 原生播放器 grep 证据（结论：完全没有 SoundFont 选择逻辑）

`project/native-macos/Resources/Player/player.js`（2572 行）中：

```
$ grep -n "loadSoundFont\|resetSoundFonts\|soundFont" player.js
1074:    settings.player.soundFont = `${BASE}/soundfont/main`;
1184:    api.soundFontLoad.on((event) => {
1190:    api.soundFontLoaded.on(() => { if (isCurrentLoad()) sendFor(loadID, 'soundReady'); });

$ grep -n "category\|flavor\|Flavor" player.js
（无匹配）
```

对照网页版入口：`ScorePlayer.svelte:8` 导入 `GM_INSTRUMENTS`；`:24-28` 导入 `resolveResumeInstrument/sourceInstrumentFlavor/planScoreAuditionSoundfonts/loadVerifiedScoreSoundfontPlan/loadSoundfontWithReceipt`；`:978-1109` 完整音源计划/加载/重试流程。

## A.4 原生资源路由（已具备，但无人调用）

`project/native-macos/Sources/MIMIGuitarMac/Player/PlayerResourceSchemeHandler.swift`：

- `:21-31` 初始化即解析两个 SF2：`soundFontURL = /soundfonts/sonivox.sf2`，`ukuleleSoundFontURL = /storage/soundfonts/ukulele_fast.sf2`（`try?`，可为 nil）。
- `:87-98` 路由：`/soundfont/main` 与 `/soundfonts/sonivox.sf2` → sonivox；`/storage/soundfonts/ukulele_fast.sf2` → uke。三者都经 `validateContentFile` 校验在 contentRoot 内。
- `:100-122` 其余静态资源白名单（无 soundfonts 目录文件，若要加"过滤后的单 preset 资产"需在此登记）。
- CSP：`Resources/Player/index.html:6` `connect-src 'self'`；页面 origin 为 `mimiplayer://app`，因此 `fetch('/storage/soundfonts/ukulele_fast.sf2')` 同源允许（与现有 `/source/current` 的 fetch 方式一致）。

## A.5 原生音轨状态与 UI 代码位置（逐条对应主文档 D 项）

- `player.js:563-584` `trackSnapshot()`：字段 `index/name/program/sourceProgram/sourceCapo/percussion/show/muted/soloed/volume/instrumentOverride/tuning`；**无 sourceName/sourceFlavor/instrumentFlavor**；`percussion = !!track.isPercussion || program === 128`（:568）。
- `player.js:586-600` `applyTrackProgram()`：改 `playbackInfo.program/name/shortName` + 遍历 automations 改 `type===Instrument` 值。
- `player.js:602-626` `createTrackMixState()`：新建 `{show,muted,soloed,volume:1,program,sourceProgram,sourceName,instrumentOverride}`；`sourceName` 取 `track.name`（原始谱面名，未本地化为"原谱 · …"/"打击乐"）；仅 `track.isPercussion` 判定（:621）。
- `player.js:628-637` `applyTrackMixToApi()`：`changeTrackMute(muted||show===false)` / `changeTrackSolo` / `changeTrackVolume`。
- `player.js:639-655` / `:1373-1379` `sendPlayerState()` / renderFinished 快照：只带 `tracks/scoreEndTick/gmInstruments/displayMode/numberTab/chordMode/capo/useSourceCapo/transpose/metronome/countIn/loop`。
- `player.js:1069-1078` `createApi()`：`useWorkers=false`、`soundFont=/soundfont/main`、`scrollElement`、`display.scale`。
- `player.js:1184-1190`：只监听 `soundFontLoad`（进度）与 `soundFontLoaded`（`soundReady`），**无 `soundFontLoadFailed`**。
- `player.js:1410-1424` `load(parameters)`：`scoreSourceMetadata = {...parameters}`；接收 `kind/loadID/title/artist/bpm`（Swift 端 :1108-1114），**无 category**；`:1486` `currentApi.load(scoreInput, [-1])`（全轨渲染，包含 `@$Strumming$@` 类合成轨）。
- `player.js:1844-1926` `restoreResume()`：`:1881-1903` 逐条 trackMix；override 仅认 `saved.instrumentOverride === true`（:1886）；源分支只写 `playbackInfo.program/name/shortName`（:1890-1896，**无 automation 回写**）；`:1899` volume clamp 0..1。
- `player.js:1928-1970` `setTrack()`：`show/muted/soloed/volume` 直改 API；`program` → `applyTrackProgram` + `instrumentOverride=true` + `renderWithAudioReload()`（:1954-1960）；`restoreProgram` → 只回写 playbackInfo/name（:1961-1967，**无 automation 回写**，也不重新加载音源）；结尾统一 `send('tracks', {tracks: trackSnapshot()})`。
- `player.js:2141-2217` `renderWithAudioReload()`：pause → renderScore(同一 score, visibleTrackIndexes) → 等 renderFinished → 显式 `loadMidiForScore()` 并等 `midiLoaded` → `requestSeek(targetTick,false)`（**不 await 回执**）→ 若原在播则 `play()`（:2191-2198）；异常路径发 `error`。
- `player.js:2267-2322` `restoreDefaults()`：**有** automation 回写循环（:2292-2299）——与 `setTrack('restoreProgram')` 的不一致正是 D2 的证据。
- `player.js:2286-2302` 亦可见"恢复源音色必须同步 automation"的意图。
- `Sources/MIMIGuitarMac/Player/NativePlayerPane.swift`
  - `:94-108` `NativePlayerTrack`：`index/name/program/sourceProgram/sourceCapo/percussion/show/muted/soloed/volume/instrumentOverride/tuning`（无 flavor/sourceName）。
  - `:1108-1114` `load` 载荷：`loadID/kind/title/artist/bpm`（无 category）。
  - `:1749-1752` `setTrack(_:field:value:)`：`send("setTrack", [...])` + `markResumeDirty()`。
  - `:2258-2300` `receivePlayerSnapshot`：`tracks` 解码见 :2264-2277（percussion 默认 false）；`gmInstruments` 解码 :2280-2285；随后 `markResumeDirty()`。
  - `:2317-2350` `scheduleResumeCheckpoint`：`:2327` 保存 `PlayerTrackMix(program: $0.program, instrumentOverride: $0.instrumentOverride)`（即使未 override 也存当前 program，与网页 :311 不同）。
  - `:1004` `canPlay = isScoreSource && scoreReady && audioReady && playerError == nil`（fail-closed 基础已具备）。
  - `:1253-1255` `soundReady` 事件 → `audioReady=true`；`:1011` 未就绪文案"曲谱已载入，等待本地音源加载完成。"
  - `:2554-2558` 已有 category 归一化逻辑（`["guitar","ukulele","bass"]`）可复用于 load 载荷。
- `Sources/MIMIGuitarMac/Player/NativePlayerPanels.swift`
  - `:22-62` `trackRow`：show Toggle（:25）、名称 + 调弦/打击乐副标题（:28-30）、静音（:32-33）、独奏（:34-35）、音色 Menu（:36-50）、音量 Slider 0…1 + 百分比（:51-55，`disabled(!audioReady)`）。
  - `:37` 恢复原谱文案 `"恢复原谱音色 · \(instrumentName(track.sourceProgram))"`；`:42` GM 项 `"\(program+1). \(name)"`；`:47` 标签 `track.instrumentOverride ? instrumentName(track.program) : "原谱 · \(instrumentName(track.sourceProgram))"`；菜单未 `disabled(track.percussion)`。
- `Sources/MIMICore/PracticeModels.swift:60-72` `PlayerTrackMix`：`index/muted/soloed/volume(Double)/program/instrumentOverride: Bool?`。
- `Resources/Player/practice-runtime.bundle.js:455` `gmInstruments: GM_INSTRUMENTS`（即网页同一份中文 GM 名表，`src/lib/gmInstruments.ts:187`）。

## A.6 网页版基准代码位置（按主题索引）

| 主题 | 位置 |
|---|---|
| 状态字段定义 | `ScorePlayer.svelte:277-314` |
| 面板开关/互斥/焦点 | `:318-378` |
| 乐器名/原谱显示名映射 | `:521-543` |
| `buildTracks`（跳过合成轨、sourceFlavor、默认音量） | `:778-818` |
| 共享音源预热（GM+uke） | `:830-848` |
| 音源计划键/冲突文案/fail closed | `:949-976` |
| 音源计划加载/append 顺序/重试 | `:978-1109`（`loadVerifiedScoreSoundfontPlan` :1000；append=`index>0` :1014-1020；`loadedPrograms` :1036；`soundReady` :1053-1063；播放恢复 :1071-1106） |
| `applyTrackMix` | `:1520-1532` |
| 重载快照恢复（位置/混音） | `:1581-1669` |
| 播放前冲突检查/播放中音源补载 | `:2010-2014, 2036-2038` |
| resume 恢复（trackMix + 音源重载） | `:2108-2212`（`resolveResumeInstrument` 应用 :2159-2180；`loadSoundfonts` :2182；render+MIDI :2185；applyTrackMix :2188） |
| `waitForMidiLoaded` | `:2272-2294` |
| `withRenderPreservingPosition`（暂停→修改→MIDI→位置→续播） | `:2301-2379` |
| 音轨面板：可见/静音/独奏/音量 | `:2634-2666` |
| `applyTrackInstrument`（program+name+flavor 标记+automation 全改） | `:2667-2690` |
| `changeInstrument`（计划/冲突/音源/重排/MIDI/位置/续播） | `:2692-2715` |
| `restoreSourceInstrument`（原始 JSON 重建 → 彻底恢复） | `:2717-2737` |
| 两个面板 UI 与 GM 下拉 | `:3009-3028, 3082-3177`（音源错误条 :3078-3080；GM 选项 :3168-3171；打击乐禁用 :3164） |
| 状态文案 | `:2830, 3073` |
| `practiceTrackMix` 持久化视图 | `:304-314` |

## A.7 共享库与测试（可执行规格）

- `src/lib/player/scoreAuditionResources.ts`：`resolveScoreAuditionSourceFlavor` :105-112；`planScoreAuditionSoundfonts` :127-168（打击乐 :137-144；uke flavor :147-149；冲突 :150-155；排序 :160-163；URL 去重 :164-166）；`programsUsedBy` :71-90；`isPercussionTrack` :92-94；`isFourStringTrack` :96-98。
- `src/lib/player/scoreInstrumentOverrides.ts`：`UKULELE_PRESET_PROGRAMS=[0,24,25]` :5；`sourceInstrumentFlavor` :12-18；`resolveResumeInstrument` :25-41。
- `src/lib/player/verifiedScoreSoundfont.ts`：URL :23-24；SHA :26-32；`filterScoreSoundfontPreset` :326-331；`replacePresetTables`（只重写 phdr）:297-323；`loadVerifiedScoreSoundfont`（uke 返回过滤字节、GM 返回整库副本）:439-461；`loadVerifiedScoreSoundfontPlan`（GM 一份 + uke 每 preset 一份，顺序 GM→uke）:464-527。
- `src/lib/player/soundfontLoadReceipt.ts`：per-API 串行队列/毒化/15s 超时 :52-59, :70-188。
- `src/lib/player/scorePlayerCorrectness.mjs:2-6`：`trackVolumePercent`（0..16 → 0..100，缺省 16）。
- 测试（网页行为的可执行断言，原生修复后建议直接对照）：
  - `tests/score-audition-resources.test.mjs:55-127`（全 GM/打击乐计划、uke 判定条件、冲突、uke 单 preset 隔离、automation 额外 program 30 走 GM）
  - `tests/score-instrument-overrides.test.mjs:5-30`（uke 0/24/25 精确集合、resume 三分支、legacy 兼容）
- `tools/build_ukulele_sf2.mjs`：现有 uke_fast.sf2 的生成脚本（修正 keyRange/sampleModes、重建 0/24/25 三预设）；若走"构建期生成单 preset 资产"方案可在此扩展。

## A.8 原生 0.2.4 实测基线（待 task-2 探针补全）

本任务不运行产品 app；以下为待探针确认项（与 task-2 约定一致）：
1. `1wmj8hqHnYf`（萱草花，ukulele，2 轨 Ukulele prog25 + Vocal prog0）加载后 scheme 请求是否**只有** `/soundfont/main`（预期：是；无 uke 请求）→ 证明 D1。
2. `trackSnapshot()` 实际输出：`program/sourceProgram/percussion/name`；尤其 `1xpyKV313Vh` 的鼓轨 `percussion` 是否为 false（预期：`track.isPercussion` 为 undefined，program 非 128 → false）→ 证明 D3。
3. MidiFile 中 program-change 事件数量（每 track/channel）：若某轨 >1 个（initial + automation），证明 D2 的 automation 风险成立。
4. 播放中 `setTrack(0,'program',40)` 后：`tracks` 是否推送新 program、是否有 `error`、seek 前后 tick 差、PCM 是否变化、是否自动续播 → 验证 D5。
5. `setTrack(0,'restoreProgram',true)` 后 MidiFile program-change 是否回 25 → 验证 D2（预期：automation 仍为 40 时仅 initial change 回 25，整体仍 40）。
6. 4 轨曲目面板轨数是否包含 `@$Strumming$@`/`@$Chords$@` 类合成轨 → 验证 D9。
