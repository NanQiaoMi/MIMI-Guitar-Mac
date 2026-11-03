# 原生播放器「音轨 / 音色」问题 — Swift 侧只读审计与补丁建议

- 任务：task-3（Swift 音轨/音色路径审计）
- 审计对象：`project/native-macos`（0.2.4 原生播放器）
- 方式：只读代码审计（数据解码 / 面板控件 / setTrack 调用链 / resume 持久化 / 音源路由 / 加载播放状态机），并用 `Resources/Player/player.js`（协议对照）与网页版 `src/lib/player/scoreAuditionResources.ts`、`scoreInstrumentOverrides.ts` 交叉核对。
- 未改动任何产品源码；未构建、未启动服务。本文档是唯一写入产物。
- 行号基于当前工作树（`Resources/Player/player.js` 2572 行、`NativePlayerPane.swift` 2952 行）。

---

## 0. 结论摘要（按严重度）

| # | 严重度 | 现象（用户可感知） | 根因归属 | Swift 侧是否可单独修 |
|---|--------|--------------------|----------|----------------------|
| F1 | **P0 阻断** | 音色切换/播放中重排一旦遇到“音频焦点未就绪 / 重排超时”等**可恢复** JS error，整个播放器被置为失败态（`scoreReady=false`、播放键禁用），只能重开谱面 | Swift（`NativePlayerPane.swift:1412-1424`）+ player.js 错误语义 | ✅ 可（配合 player.js 增加 `fatal` 标记） |
| F2 | **P0 功能缺失** | 尤克里里曲目**没有尤克里里原谱音色**：全部走 sonivox GM；`ukulele_fast.sf2` 虽已在 Swift 白名单中，但从未被请求 | Swift 未把 `category` 传给播放页（`NativePlayerPane.swift:1108-1114`）；player.js 固定 `/soundfont/main`（`player.js:1074`） | ✅ Swift 侧最小改动见 §2；音源规划在 player.js（Lead） |
| F3 | **P1 听感错误（跨边界）** | 切音色/恢复原谱后，之前设置的**静音 / 独奏 / 音量被重置**：面板仍显示“已静音 30%”，实际该轨全音量发声 | player.js 重载路径缺 `applyTrackMixToApi`（`player.js:2141-2217` 对照 `:2105`）；alphaTab 的 mute/volume 只作用于播放器通道（`score-rendering.bundle.js:45103-45107`） | ⚠️ 根因在 player.js（Lead 范围）；Swift 可临时自愈（§F3） |
| F4 | **P1 数据断链** | 含打击乐轨的曲目，断点/音色设置可能**永远保存失败**：`program=128` 被 `PersonalDataValidator` 拒绝，整份个人资料 commit 抛错 | Swift `NativePlayerPane.swift:2327` 原样持久化 snapshot `program`；校验 `PersonalValidation.swift:117` 只允许 0...127 | ✅ 可 |
| F5 | **P2 UI 错误状态** | 切换曲目后音轨面板**仍显示上一首的音轨**（直到新谱 snapshot 到达；新谱加载失败则永久显示旧轨），并可对旧轨操作而实际作用到新谱同 index | Swift 全仓库没有任何 `tracks = []` 重置（`open` / `pageDidBecomeReady` / `loadPersonalScore` 均未清空） | ✅ 可 |
| F6 | **P2 高频写/竞态** | 拖动音量滑块或连续切音色时，Swift 每次都在 JS 回显**之前**落盘旧 mix，且每个回显再次落盘（explicit 绕过 5 s 节流）→ PersonalStore 高频 commit、断点可能存成旧音色 | `setTrack` 立即 `markResumeDirty`（`:1749-1752`）+ `receivePlayerSnapshot` 无条件 `markResumeDirty`（`:2299`）+ `explicit` 绕过节流（`:2322-2326`） | ✅ 可 |
| F7 | **P2 兼容性** | 旧版本断点（无 `instrumentOverride` 字段）恢复时**丢掉用户选过的音色**，回到原谱 | Swift 原样转发 resume；player.js 只认 `saved.instrumentOverride === true`（`player.js:1886-1889`），而网页版 `resolveResumeInstrument` 会用“program ≠ sourceProgram”推断（`scoreInstrumentOverrides.ts`） | ✅ 可在 Swift 转发前归一化 |
| F8 | **P3 UI/交互** | 打击乐轨也显示可点的音色菜单：标签是“原谱 · 原声大钢琴”或“MIDI 129”；选了没反应（JS 忽略）；“恢复原谱音色”却会执行 | `NativePlayerPanels.swift:36-50`；JS `setTrack` program 分支对 percussion 直接 return（`player.js:1956`），restoreProgram 分支未 guard（`:1961-1967`） | ✅ 可 |
| F9 | **P3 可用性** | 曲库详情页（`mode == .player`）里改音色/混音**不会持久化**；resume 也从不加载（`refreshPracticeData()` 只在 `loadPersonalScore` 路径调用） | `scheduleResumeCheckpoint` 门槛 `mode == .practice && practiceJoined`（`:2323`）；`open(item:)`（`:1788-1815`）不调用 `refreshPracticeData` | ✅ 可（需产品确认是否刻意） |
| F10 | **P3 粘滞错误** | 任意一次 JS 调用失败（`callAsyncJavaScript` completion failure）写入 `playerError` 后**不会自愈**，播放键常驻“无法播放：…” | `send()` completion 写 `playerError`（`:1996-2004`）；`playerError` 只在 `scoreReady`/`pageDidBecomeReady`/`open` 清除 | ✅ 可 |
| F11 | **P3 域不一致** | `PlayerTrackMix.volume` 实际是 0...1，但校验允许到 100；`program` 对打击乐无意义 | `PersonalValidation.swift:116-117` vs `trackSnapshot` clamp 0..1（`player.js:1952`） | ✅ 可（注释/校验收紧） |

> 说明：F3 的根因在 `player.js`，但它是“切音色后听感错误”最直接的来源之一（面板与实际发声不一致），所以一并列出，并在 §F3 给出 Swift 临时自愈 + 建议 Lead 的一行修复。F2 的 JS 侧规划逻辑由 parity-spec / Lead 负责，本文只给 **Swift 最小改动**。

---

## 1. 协议对照事实（读代码得到的契约，供后续所有结论引用）

### 1.1 `trackSnapshot()` 字段（`Resources/Player/player.js:563-584`）

```js
{ index, name, program, sourceProgram, sourceCapo, percussion,
  show, muted, soloed, volume, instrumentOverride, tuning }
```

- `program`：`playbackInfo.program` 为安全整数时原样输出；否则 `percussion ? 128 : 0`（`:567-573`）——**打击乐轨有可能输出 128**。
- `sourceProgram`：优先取 `trackMix[i].sourceProgram`（首次由 `createTrackMixState` 用谱面 program 初始化，`:602-626`）。
- `volume`：0...1（JS 端 clamp，`:1952`）。

### 1.2 `setTrack(index, field, value)`（`player.js:1928-1970`）

| field | 行为 | 是否触发音频重载 |
|---|---|---|
| `show` | 更新 `visibleTrackIndexes`、`changeTrackMute`、`renderTracks(visible)`（`:1933-1942`） | 否（重排谱面） |
| `muted` | `changeTrackMute([track], muted \|\| !show)`（`:1943-1945`） | 否 |
| `soloed` | `changeTrackSolo`（`:1946-1948`） | 否 |
| `volume` | `changeTrackVolume`（0...1，`:1949-1953`） | 否 |
| `program` | **打击乐直接 return**；否则 `applyTrackProgram` + `renderWithAudioReload()`（`:1954-1960`） | 是 |
| `restoreProgram` | 还原 `sourceProgram/sourceName`（**未 guard 打击乐**）+ `renderWithAudioReload()`（`:1961-1967`） | 是 |

每次 `setTrack` 结束时都 `send('tracks', {tracks: trackSnapshot()})`（`:1969`）；`send()` 会自动附 `loadID`（`:800-805`），Swift `receive()` 的 loadID 校验（`NativePlayerPane.swift:1118-1123`）能匹配。

### 1.3 `restoreResume()` 的 trackMix 语义（`player.js:1844-1926`）

```js
// :1886-1896
if (!track.isPercussion && saved.instrumentOverride === true && 0<=saved.program<=127) {
  applyTrackProgram(track, saved.program); state.instrumentOverride = true;
} else if (!track.isPercursion) {
  track.playbackInfo.program = state.sourceProgram; track.name = state.sourceName; ...
  state.instrumentOverride = false;
}
// :1897-1902 无论如何恢复 muted/soloed/volume
```

→ **只有显式 `instrumentOverride === true` 才恢复音色**；旧 resume 缺该字段时 program 被忽略（对照网页版 `resolveResumeInstrument` 会用 `program !== sourceProgram` 推断）。

### 1.4 `renderWithAudioReload()`（`player.js:2141-2217`）

暂停 → `renderScore` → `loadMidiForScore` → `requestSeek(targetTick)` → 若曾在播放则 `play()` → `sendPlayerState()`。
**注意：此路径没有调用 `applyTrackMixToApi(currentApi)`**；而谱面重建路径 `performJsonScoreReload` 在重新 seek 前调用了它（`:2105`）。这是 F3 的直接根因。

### 1.5 Swift ↔ JS 数据通道

- `NativePlayerPane.send()`：`callAsyncJavaScript` + `arguments: ["payload": arguments]`（`:1950-2007`）。
- `receive()`：非 `ready` 事件必须携带匹配 `loadID`（`:1118-1123`）；`playerSnapshot` 与 `tracks` 都走 `receivePlayerSnapshot`（`:1393-1394`）。
- 首次加载时 `api.scoreLoaded` 里 `createTrackMixState` 后立刻 `sendPlayerState()`（`player.js:1145/1181`），因此正常加载下音轨面板会收到 tracks，不会永远“等待音轨载入”。

---

## 2. 【必读·最小改动】实现 ukulele 原谱音色所必需的 Swift 侧改动

### 2.1 现状（Swift 侧已经准备了一半）

- `PlayerResourceSchemeHandler` **已经**解析并允许 `/storage/soundfonts/ukulele_fast.sf2`：
  - `Sources/MIMIGuitarMac/Player/PlayerResourceSchemeHandler.swift:22` `private let ukuleleSoundFontURL: URL?`
  - `:30-31` `ukuleleSoundFontURL = try? AppPaths.resolve(reference: "/storage/soundfonts/ukulele_fast.sf2", contentRoot:)`
  - `:87-98` `/soundfont/main`、`/soundfonts/sonivox.sf2`、`/storage/soundfonts/ukulele_fast.sf2` 三条路由。
- 但 Swift 在页面 ready 后发给 JS 的 load payload **没有 `category`**（`NativePlayerPane.swift:1108-1114`）：
  ```swift
  send("load", arguments: [
      "loadID": loadID,
      "kind": source.kind.rawValue,
      "title": metadataTitle,
      "artist": metadataArtist,
      "bpm": Int(sourceTempo),
  ])
  ```
- `player.js` 只能拿到 `scoreSourceMetadata = {...parameters}`（`player.js:1424`）却无人使用，且 `settings.player.soundFont` 固定 `BASE/soundfont/main`（`player.js:1074`）。它需要 `category` 才能做与网页等价的 flavor 判定：
  - 网页版：`ScorePlayer.svelte` 用 `sourceInstrumentFlavor(category || practiceScoreRef?.category || '', tuning, sourceProgram)` 给 track 打 `mimiSoundfontFlavor`（`ScorePlayer.svelte:790-797`），再由 `planScoreAuditionSoundfonts` 选 `SCORE_UKULELE_SOUNDFONT_URL`（`scoreAuditionResources.ts:133-168`）；
  - 判定条件：`category === 'ukulele'` 且 4 弦且 program ∈ {0,24,25}（`scoreAuditionResources.ts:106-116`），冲突（同一 0:program 既要 GM 又要 uke）→ 降级/报错，GM 先 append、ukulele 后 append 保证 last-match。

### 2.2 补丁 A（最小、4 处改动，只需改 NativePlayerPane.swift）

**① 新增派发值**（放在 `isXhe` 附近，`NativePlayerPane.swift:988` 之前/之后均可）：

```swift
/// 曲目类别：用于播放器选择原谱音色（guitar / ukulele / bass）。
/// 个人谱优先取自身 category，曲库谱取 CatalogItem.category，其余一律 guitar。
var scoreCategory: String {
    for raw in [item?.category, personalScore?.category] {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["guitar", "ukulele", "bass"].contains(value) { return value }
    }
    return "guitar"
}
```

**② load payload 加一行**（`NativePlayerPane.swift:1108-1114`）：

```diff
         send("load", arguments: [
             "loadID": loadID,
             "kind": source.kind.rawValue,
             "title": metadataTitle,
             "artist": metadataArtist,
             "bpm": Int(sourceTempo),
+            "category": scoreCategory,
         ])
```

**③ 面板显示“原谱音色”时不要再猜 GM 名**（可选但强烈建议，与 2.3 的 JS 回显字段联动；`NativePlayerPanels.swift:47`）：
待 player.js 在 `trackSnapshot` 增加 `sourceFlavor`（`'gm' | 'ukulele'`）后，Swift `NativePlayerTrack` 加 `sourceFlavor: String = "gm"` 字段（`NativePlayerPane.swift:94-108` + 解码 `:2264-2277`），面板：

```swift
Label(track.instrumentOverride
      ? instrumentName(track.program)
      : "原谱 · \(track.percussion ? "打击乐" : (track.sourceFlavor == "ukulele" ? "尤克里里" : instrumentName(track.sourceProgram)))",
      systemImage: "music.note")
```

**④ 资源缺失不要静默降级**（`PlayerResourceSchemeHandler.swift:31`）：现在 `try?` 让文件缺失时静默 nil，JS 请求 uke 音源会 404 → `error` 事件 → 触发 F1 的“永久失败态”。建议改为：

```swift
do {
    ukuleleSoundFontURL = try AppPaths.resolve(reference: "/storage/soundfonts/ukulele_fast.sf2", contentRoot: contentRoot)
} catch {
    ukuleleSoundFontURL = nil
    NSLog("MIMI player: ukulele soundfont missing: \(error.localizedDescription)")
}
```
并在打包资源清单里确认 `Content/storage/soundfonts/ukulele_fast.sf2` 存在（Lead/构建负责）。

**⑤ 本地导入文件（item/personalScore 均为 nil）**：payload 只能给 `"guitar"`。建议 Lead 在 player.js 用“4 弦 + program 24/25”兜底推断（网页版 `isUkuleleScore(category, tuning)` 已有类似兜底），Swift 无需为导入文件额外改。

> 风险：`scoreCategory` 在 `pageDidBecomeReady()` 时读取，而 `loadPersonalScore` 的 catalog 分支在 `MainActor.run` 里先设置 `item` 再 `webViewIdentity = UUID()`（`NativePlayerPane.swift:2129-2141`），时序安全；导入路径 `item == nil && personalScore == nil` 时退回 guitar，符合预期。**不改任何持久化/校验代码即可生效**，风险极低。

### 2.3 更干净的可选变体（B，3 个文件，推荐但在 25 分钟窗口外）

把 `category` 挂到 `NativePlayerSource`（`NativePlayerPane.swift:821-825`），在 `resolveSource(item:...)`/`open(item:)`/`loadPersonalScore` 的 catalog 分支里写入，`pageDidBecomeReady` 用 `source.category`。优点：payload 只有单一真值来源，不会受切歌瞬间的 `item/personalScore` 竞争影响；缺点：`NativePlayerSource` 是内部 struct，改动点分散（`open` `:1788-1815`、`loadPersonalScore` `:2031-2151`、三处 `resolveSource` 调用）。

### 2.4 Lead/JS 侧对应要做的事（不在本任务写入范围，仅提示）

1. `player.js` 在 `scoreLoaded` 前用 `metadata.category` 给每个 track 打 `mimiSoundfontFlavor`（规则同 `scoreAuditionResources.ts:106-116`）；
2. 按 `planScoreAuditionSoundfonts` 规则把所需 sf2 预设 append 到 alphaTab 音源（GM 先、uke 后；`bank 128/0` 打击乐始终 GM；冲突时报可读错误而不是静默错音）；
3. `trackSnapshot` 增加 `sourceFlavor` 供 Swift 面板显示；
4. `renderWithAudioReload` 在 `loadMidiForScore` 之后补 `applyTrackMixToApi(currentApi)`（修 F3）；
5. 可选：`error` 事件增加 `fatal: true|false` 语义（修 F1）。

---

## 3. 逐条发现（现象 → 根因 → 建议补丁 → 风险）

### F1（P0）非致命 JS error 被 Swift 当作致命错误，音色切换后播放器可能“废掉”

**现象**
- 播放中切换音色 / 恢复原谱 / 改显示模式时，JS 走 `renderWithAudioReload()`（`:2141-2217`）。该函数在“音频焦点未就绪导致没能自动恢复播放”时发送
  `window.NativePlayer` → `send('error', {message:'谱面更新完成，但音频焦点未就绪，播放器没有自动恢复。'})`（`player.js:2196-2197`），重排/音频加载超时发送“等待谱面重排超时。/等待音频谱面更新超时。”（`:2159, 2178`），catch 分支再发一次 error（`:2215`）。
- Swift 收到任何 `error` 就把播放器打成失败态：`scoreReady = false; audioReady = false; resetPositionSample(); playerError = message`，且 `playerError` 只有 `scoreReady`/`pageDidBecomeReady`/`open` 才会清（`NativePlayerPane.swift:1230-1236, 1412-1424`）。
- 结果：`canPlay == false`（`:1004`），播放键禁用，面板还在但 `setTrack` 已无实际意义；用户只能返回重进曲目。用户主观感受就是“一换音色播放就坏了”。

**根因**
- `Sources/MIMIGuitarMac/Player/NativePlayerPane.swift:1412-1424`：
  ```swift
  case "error":
      isPlaying = false
      isLoading = false
      isLoadingSound = false
      scoreReady = false
      audioReady = false
      resetPositionSample()
      let message = event["message"] as? String ?? "谱面载入失败。"
      playerError = message
      statusMessage = message
      cancelReadinessTimeout()
  ```
- 协议里 `error` 没有分级语义；`player.js` 把“可恢复的自动恢复失败”和“谱面载入失败”混在同一个事件里（`:1095-1097` 是致命，`:2195-2197/2215` 是可恢复）。

**建议补丁（Swift 侧，可与 JS 并行）**

```swift
case "error":
    let message = event["message"] as? String ?? "播放器操作失败。"
    // 新协议：JS 显式给 fatal；旧协议回退：只有“谱面/音源尚未就绪”阶段的错误才致命
    let fatal = event["fatal"] as? Bool
        ?? (!scoreReady || (!audioReady && !playerPageReady))
    isPlaying = false
    isLoading = false
    isLoadingSound = false
    if fatal {
        scoreReady = false
        audioReady = false
        resetPositionSample()
        playerError = message
        cancelReadinessTimeout()
    } else {
        // 保留 scoreReady/audioReady/canPlay，允许用户直接再按播放或再次切音色
        statusMessage = message
        playerError = nil            // 不把可恢复失败升级为粘滞错误
        // 可选：把 UI 位置与 JS 重新对齐
        // send("seek", arguments: ["tick": Int(currentTick)])
    }
```

配套建议 Lead 在 player.js 的 `fail()`（载入失败，`:812-816`）和 `api.error`（`:1095-1097`）里加 `fatal: true`，在 `renderWithAudioReload`/`performJsonScoreReload` 的 `send('error', ...)` 里加 `fatal: false`。

**风险**：若判断过于宽松，真正的载入失败可能被当成非致命，UI 停在“可播放”但 JS 已无 api。用 `fatal` 显式字段最稳妥；回退逻辑只在旧资源包（不会出现）时生效。建议同时把 F10 的 sticky `playerError` 一起处理。

---

### F2（P0）尤克里里原谱音色未实现（Swift 侧根因：load payload 无 category）

见 §2。**Swift 侧最小改动 = §2.2 的 ①②（两处、约 10 行）**；`ukulele_fast.sf2` 的 scheme 路由已经就绪不需要改。要点：

- 取值位置：`CatalogItem.category`（`Sources/MIMICore/Catalog.swift:7`；默认 `"guitar"`，`:33`）、`PersonalScore.category`（`Sources/MIMICore/PersonalModels.swift:10`）。
- 注入位置：`NativePlayerPane.swift:1108-1114` 的 `send("load", ...)`。
- 播放器入口已保证有值：曲库详情 `ScoreDetailView.swift:97`（`item: item`）、个人谱详情 `:149`、练习页 `FullParityViews.swift:691`（`personalScore: activeScore`）。
- 现状只会播放 GM：`player.js:1074 settings.player.soundFont = `${BASE}/soundfont/main``；`gmInstruments` 只有 128 条 GM（`practice-runtime.bundle.js:395`），所以面板只能显示 GM 名（“原谱 · 尼龙弦吉他”等），听感是合成器 GM 吉他/钢琴。

**风险**：JS 未消费 `category` 时该字段无副作用（`scoreSourceMetadata` 只是对象展开）；Swift 改动可先行合入。

---

### F3（P1，跨边界）切音色后静音/独奏/音量被重置（面板与实际发声不一致）

**现象**：设某轨静音（或独奏、音量 30%）→ 再切音色/恢复原谱 → 面板仍显示“已静音/30%”（因为 `trackMix[]` 状态没丢，`trackSnapshot` 照样回显），但实际该轨以全音量发声。

**根因（player.js，Lead 修复范围）**
- `changeTrackMute` 只改播放器通道：`score-rendering.bundle.js:45103-45107`
  ```js
  changeTrackMute(tracks, mute) {
    for (const track of tracks) {
      this._player.setChannelMute(track.playbackInfo.primaryChannel, mute);
      this._player.setChannelMute(track.playbackInfo.secondaryChannel, mute);
    }
  }
  ```
  音量/独奏同理，仅作用于当前 AlphaSynth 通道状态，不写回 score。
- `renderWithAudioReload()` 重新 render + `loadMidiForScore()`（`player.js:2168-2189`）会重建通道状态，但该路径**没有** `applyTrackMixToApi(currentApi)`（`:628-637` 的现成函数）。
- 对照：`performJsonScoreReload` 在 seek 前调用了 `applyTrackMixToApi(currentApi)`（`player.js:2105`），所以“改显示模式”能保住混音，而“改音色”不能。

**建议补丁**
1. **首选（Lead，player.js）**：在 `renderWithAudioReload` 的 `if (currentApi !== api) return;`（`:2190`）之后、`requestSeek(...)`（`:2191`）之前加一行
   ```js
   applyTrackMixToApi(currentApi);
   ```
   风险：低；`applyTrackMixToApi` 对每条 track 调 3 个 player API，代价很小，且顺序在 seek/play 之前保证恢复播放时混音已生效。
2. **Swift 临时自愈（若 Lead 暂不改 player.js）**：在 `receivePlayerSnapshot` 检测到 `instrumentOverride`/`program` 变化后，把当前 `muted/soloed/volume` 重新下发一遍（这些字段不触发音频重载）：
   ```swift
   // receivePlayerSnapshot 末尾，仅当本次 tracks 中 program/instrumentOverride 发生变化时
   for track in tracks where track.muted || track.soloed || abs(track.volume - 1) > 0.001 {
       send("setTrack", arguments: ["index": track.index, "field": "muted",   "value": track.muted])
       send("setTrack", arguments: ["index": track.index, "field": "soloed",  "value": track.soloed])
       send("setTrack", arguments: ["index": track.index, "field": "volume",  "value": track.volume])
   }
   ```
   风险：3×N 次桥调用、短暂抖动；必须在 JS 重载**完成之后**的 snapshot 上做（`renderWithAudioReload` 末尾有 `sendPlayerState()`，`:2202`，可满足）。不建议长期保留。

**验收**：探针 setTrack(program) 前后检查“被静音轨的 PCM 通道是否重新有声”。

---

### F4（P1）打击乐 `program=128` 会让整份个人资料保存失败（断点/音色设置丢失）

**现象**：含打击乐轨（如 `1xpyKV313Vh`）的曲目在练习模式播放后，断点保存可能报错（练习面板出现 `saveError`），下次打开没有断点；反复保存失败。

**根因链**
1. JS `trackSnapshot`：`program = Number.isSafeInteger(program) ? program : (percussion ? 128 : 0)`（`player.js:572`）→ 打击乐的 `playbackInfo.program` 若缺失/非数字，snapshot 里 **program = 128**。
2. Swift 原样解码并原样持久化：`NativePlayerPane.swift:2267`（decode）→ `:2327`（写入 `PlayerTrackMix`）：
   ```swift
   let mixes = tracks.map { PlayerTrackMix(index: $0.index, muted: $0.muted, soloed: $0.soloed,
                                           volume: $0.volume, program: $0.program,
                                           instrumentOverride: $0.instrumentOverride) }
   ```
3. 校验直接拒绝：`Sources/MIMICore/PersonalValidation.swift:117`
   `guard mix.volume <= 100, (0...127).contains(mix.program)` → 抛 `PersonalDataValidationError`。
4. `PersonalStore.validate` 把它转成 `PersonalStoreError.validation`（`PersonalStore.swift:943-946`），`persistResume` catch 后 `saveError = ...`（`NativePlayerPane.swift:2372-2376`）→ 断点永远存不上，且**同一事务里的其他个人数据提交也会失败**。

**建议补丁（Swift）**

```swift
// scheduleResumeCheckpoint，NativePlayerPane.swift:2327
let mixes = tracks.map { track in
    PlayerTrackMix(
        index: track.index,
        muted: track.muted,
        soloed: track.soloed,
        volume: min(1, max(0, track.volume)),          // 明确 0...1 域
        program: track.percussion ? 0 : min(127, max(0, track.program)),
        instrumentOverride: track.percussion ? false : track.instrumentOverride
    )
}
```

并在**同一次提交前置**对 `PlayerResume` 里的所有 mix 做同样 clamp（防旧断点/其他入口）：

```swift
// persistResume 开头
var safe = value
safe.trackMix = value.trackMix?.map { mix in
    var next = mix
    next.volume = min(1, max(0, mix.volume))
    next.program = min(127, max(0, mix.program))
    return next
}
```
同时建议把 `PersonalValidation.swift:116-117` 的 volume 上界从 100 收紧为 1（写在文档/comment 里说明历史值 0...100 兼容），或至少加注释避免下一个人再踩。

**风险**：极低（打击乐 program 对播放无意义，restoreResume JS 也跳过打击乐 program）。但如果 probe 证实 `1xpyKV313Vh` 的打击乐 snapshot program 实际是 `0`，则本项降级为“潜在风险”，仍建议加 clamp（防御未来数据）。

---

### F5（P2）切曲目后旧 tracks 残留，可对旧轨操作、作用于新谱

**现象**
1. 从 A 曲直接切到 B 曲，B 加载完成前音轨面板仍列出 A 的音轨（`scoreReady=false` 时也不隐藏，`NativePlayerPanels.swift:10-16` 只判断 `tracks.isEmpty`）；
2. 若 B 加载失败，A 的音轨**永久**留在面板（`error` 分支不清 tracks，`:1412-1424`）；
3. 对残留行操作会 `send("setTrack", index, ...)`，一旦 B 的 `loadID` 匹配且 index 存在，就作用到 B 的同名轨（音量/静音/音色都可能改错），或 index 越界被 JS 静默丢弃但 Swift 已 `markResumeDirty()`。
4. 副作用：`primaryTrack`（`:993`）用于 `activeCapo`、`displayKey` 等，切换瞬间会显示旧轨的调弦/来源 capo。

**根因（Swift）**
- 全仓库没有任何 `tracks = []`（`grep` 确认 0 处）：`open(item:)`（`:1788-1815`）、`loadPersonalScore`（`:2031-2051`）、`pageDidBecomeReady`（`:1088-1116`）都只重置 `scoreReady/audioReady/isPlaying` 等，不清音轨。
- 唯一更新点是 `receivePlayerSnapshot`（`:2258-2285`），且 `event["tracks"]` 缺失时保持旧值（`:2260 if let values`）。

**建议补丁**

```swift
// pageDidBecomeReady() 内，send("load", ...) 之前
tracks = []
gmInstruments = []          // 静态 GM 表，清掉也无害，避免旧 runtime 形状
pendingTrackMixSignature = []   // 若实现 F6 的 diff 逻辑

// open(item:) 与 loadPersonalScore(_:) 开头（source 重置处）
tracks = []
gmInstruments = []

// setTrack 增加前置校验
func setTrack(_ track: NativePlayerTrack, field: String, value: Any) {
    guard scoreReady, playerError == nil, !isLoading,
          tracks.contains(where: { $0.index == track.index }) else { return }
    ...
}
```

**风险**：`pageDidBecomeReady` 在每次 webView 重建时都会调用；清空后到首次 snapshot 之间面板短暂显示“等待谱面音轨载入…”，属于正确状态。不要清 `gmInstruments` 也可以，但清掉可避免“上一 runtime 的 gm 表”极端情况。

---

### F6（P2）音色/音量改动的高频落盘与旧值竞态

**现象**
- 拖动音量 Slider 一次（几十个 tick）→ 每个 tick 触发 `setTrack(volume)`，JS 回 `tracks`（`player.js:1969`）→ Swift `receivePlayerSnapshot` → `markResumeDirty()` → `scheduleResumeCheckpoint(explicit: true)` 绕过 5 s 节流（`:2326 if !explicit, ... < 5 return`）→ 每个 tick 至少 1~2 次 `PersonalStore.snapshot()+commit()`（整份 JSON 校验 + 写盘 + 备份）。
- 切音色时：`setTrack(program)` 先同步 `markResumeDirty()`（`:1749-1752`），此时 `tracks` 还是**旧值**（`program=sourceProgram, instrumentOverride=false`），会落盘一次旧状态；等 JS `renderWithAudioReload` 完成回显后（可能 0.5~3 s）再落盘新状态。两次写入之间若退出应用/切页，可能把旧音色写进断点。
- 后果：音量拖动时 UI 卡顿/磁盘写风暴；`PersonalStore` revision 冲突概率上升（练习切片也在并发写），极端时练习面板出现“断点保存遇到连续版本冲突”。

**根因**
- `Sources/MIMIGuitarMac/Player/NativePlayerPane.swift:1749-1752`（setTrack 无条件 markResumeDirty）
- `:2299`（receivePlayerSnapshot 无条件 markResumeDirty）
- `:2317-2350`（`markResumeDirty` 固定 `explicit: true` → 跳过 5 s 节流；节流判断在 `:2326`）

**建议补丁**

```swift
// 1) setTrack 不再立即落盘；program/restoreProgram 必须等 JS 回显（tracks 事件）再写
func setTrack(_ track: NativePlayerTrack, field: String, value: Any) {
    guard ...前置校验... else { return }
    send("setTrack", arguments: ["index": track.index, "field": field, "value": value])
    // 不再 markResumeDirty()：JS 的 tracks 回显会到 receivePlayerSnapshot
}

// 2) receivePlayerSnapshot 只在“混音签名”真变化时 explicit 落盘，其余走节流
private var lastTrackMixSignature: [String] = []

private static func mixSignature(_ tracks: [NativePlayerTrack]) -> [String] {
    tracks.map { "\($0.index)|\($0.muted)|\($0.soloed)|\(String(format: "%.3f", $0.volume))|\($0.program)|\($0.instrumentOverride)|\($0.show)" }
}

// receivePlayerSnapshot 末尾替换 :2299
let signature = Self.mixSignature(tracks)
if signature != lastTrackMixSignature {
    lastTrackMixSignature = signature
    let now = ProcessInfo.processInfo.systemUptime
    if let last = lastTrackMixWriteUptime, now - last < 0.4 {   // 滑块拖动合并写
        scheduleResumeCheckpoint()                              // 节流版，5 s 内最多一次
    } else {
        lastTrackMixWriteUptime = now
        markResumeDirty()                                       // explicit
    }
}
```
（`lastTrackMixWriteUptime` 新增私有变量；`scheduleResumeCheckpoint()` 已有 5 s 节流 `:2325-2326`。）

**风险**：低。`show` 也纳入签名（恢复 resume/trackIndexes 需要）；`resume` 的 `loop/capo/...` 仍由原有事件驱动。若某天 JS 不再为 `setTrack` 回发 `tracks`，则音色不会持久化——当前 `player.js:1969` 每次都发，且有 `playerSnapshot` 兜底（`:2202`）。

---

### F7（P2）旧断点缺 `instrumentOverride` 时丢音色（与网页语义不一致）

**现象**：0.2.x 早期/网页写入的 resume 里 `trackMix[].program` 记录了用户音色但没有 `instrumentOverride` 字段。原生“恢复设置/继续”后音色回到原谱，用户觉得“我的设置没恢复”。

**根因**
- Swift 原样编码转发（`NativePlayerPane.swift:1820-1833` → `player.js:1844`），`PlayerTrackMix.instrumentOverride` 为 nil 时 JSONEncoder **省略该 key**（`PracticeModels.swift:66, 117-137`）。
- JS 只认显式 `true`：`player.js:1886-1889`；nil/缺失会走 `:1890-1896` 把 program 重置为 `sourceProgram`。
- 网页版有兼容逻辑 `resolveResumeInstrument(sourceProgram, savedProgram, savedOverride)`：`savedOverride===undefined` 且 `savedProgram !== sourceProgram` 时推断为 override（`src/lib/player/scoreInstrumentOverrides.ts`）。原生 JS 没有。

**建议补丁（Swift 转发前归一化，最省事）**

```swift
func restoreResume(_ value: PlayerResume) {
    guard value.scoreRevision == scoreRevision else { ... 原逻辑 ... }
    var normalized = value
    if !tracks.isEmpty, let mixes = value.trackMix {
        normalized.trackMix = mixes.map { mix in
            guard let track = tracks.first(where: { $0.index == mix.index }) else { return mix }
            var next = mix
            if track.percussion {
                next.program = 0
                next.instrumentOverride = false
            } else if next.instrumentOverride == nil {
                next.instrumentOverride = next.program != track.sourceProgram
            }
            return next
        }
    }
    guard let encoded = try? JSONEncoder().encode(normalized), ... else { ... }
    send("restoreResume", arguments: ["resume": object])
    markResumeDirty()
}
```
（注意必须放在 `scoreRevision` guard 之后、编码之前；若实现 F4 的 clamp，也在这里做。）

**风险**：低。`tracks` 为空时保持原样（JS 也无法恢复；可考虑延迟到 `playerSnapshot` 后再执行 restore，属产品级交互优化）。若 Lead 选择在 player.js 实现 `resolveResumeInstrument` 等价逻辑（更符合网页语义），Swift 本项可不做；两者择一即可，但不要同时做导致双写。

---

### F8（P3）打击乐轨的音色菜单：可点、无效、标签错误

**现象**
- 打击乐行显示菜单标签“原谱 · 原声大钢琴”（program=0 时）或“MIDI 129”（program=128 时），用户以为能换鼓组音色；
- 点任意 GM 音色：Swift `setTrack(program)` 已发出并 `markResumeDirty`（`:1749-1752`），JS `setTrack` 在 `track.isPercussion` 时直接 return（`player.js:1956`），不回 `tracks`、不报错 → UI 无变化，用户感知“点了没用”；
- 点“恢复原谱音色”：JS 的 `restoreProgram` 分支**没有** percussion guard（`player.js:1961-1967`），会改写打击乐 track 的 `playbackInfo.program/name` 并触发一次不必要的音频重载。

**根因**
- `Sources/MIMIGuitarMac/Player/NativePlayerPanels.swift:36-50`（菜单对 percussion 未分支）+ `:70-72`（`instrumentName` 只查 GM 表）。

**建议补丁**

```swift
// NativeTrackMixerPanel.trackRow：替换 Menu 部分
if track.percussion {
    Label("打击乐轨 · 鼓组音色由谱面固定", systemImage: "music.note")
        .lineLimit(1).frame(maxWidth: 205, alignment: .leading)
        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
} else {
    Menu { ...原样... } label: { ...原样... }
}
```
并在 `NativePlayerModel.setTrack`（`:1749`）加 `guard !track.percussion || field == "show" || field == "muted" || field == "soloed" || field == "volume"`。
（可选：Lead 在 `player.js:1961` 的 `restoreProgram` 分支也加 `if (!track.isPercussion)`。）

**风险**：低；纯 UI 一致性。注意若某天出现“可换鼓组”需求，再放开 percussion program override 并同步校验域。

---

### F9（P3）曲库详情页（非练习模式）不保存/不加载逐曲设置

**现象**：在曲库详情页播放器里调音量/静音/音色，退出再进，全部丢失；练习页（`mode == .practice` 且已加入待练）才保存。

**根因**
- `scheduleResumeCheckpoint` 开头门槛（`NativePlayerPane.swift:2322-2324`）：
  ```swift
  guard mode == .practice, practiceJoined, practiceDataReady, scoreReady, scoreEndTick > 0,
        scoreRevision.count == 64 else { return }
  ```
- 反向：`open(item:)`（`:1788-1815`）不调用 `refreshPracticeData()`，所以曲库详情页从不加载 `resume`，回顾面板也不会出现“恢复设置/继续”。

**结论/建议**：这可能是产品有意设计（断点=练习资料）。若产品期望“播放器里的音色选择也要记住”，最小改动：
1. 允许 `mode == .player` 下也 checkpoint（把 `mode == .practice &&` 放宽为 `(mode == .practice && practiceJoined) || mode == .player`，但 `practiceDataReady` 需保证为 true 才拿得到 store）；
2. `open(item:)` 成功后调用一次 `refreshPracticeData()`（`:1812 computeRevision` 之后），让 resume 可见/可恢复。
风险：会写入“未加入待练”的曲目断点，需与产品确认；数据量小（每曲一条）。

---

### F10（P3）`playerError` 粘滞：一次桥调用失败后播放键常驻不可用

**现象**：偶发 `callAsyncJavaScript` 失败（页面正在销毁、切页瞬间、WebKit 偶发）后，`playerError` 被写入且无人清理，播放键永久显示“无法播放：…”，直到重进曲目。

**根因**
- `send()` completion failure（`NativePlayerPane.swift:1991-2006`）：
  ```swift
  if case .failure(let error) = result {
      self?.playerError = error.localizedDescription
      self?.isLoading = false
      self?.isLoadingSound = false
      self?.statusMessage = error.localizedDescription
      self?.readinessTimeout?.cancel()
      self?.readinessTimeout = nil
  }
  ```
- 清除点只有 `scoreReady`（`:1233`）、`pageDidBecomeReady`（`:1095`）、`open`（`:1802`）、`loadPersonalScore`（`:2048`）。

**建议补丁**：桥调用失败只记 statusMessage（非粘滞），或加 `playerError` 的自动清除（下一次 `playbackState`/`playerSnapshot` 成功即清）：

```swift
completionHandler: { [weak self] result in
    guard case .failure(let error) = result else { return }
    self?.statusMessage = "播放器通讯失败：\(error.localizedDescription)"
    // 仅当尚未就绪时才算致命
    if self?.scoreReady != true { self?.playerError = error.localizedDescription }
}
```
并在 `receivePlayerSnapshot` 成功时 `if playerError != nil && scoreReady { playerError = nil }`。

**风险**：低；注意不要把真正的持续失败掩盖掉，`readinessTimeout` 仍会兜底报“加载超过 60 秒”。

---

### F11（P3）`volume/program` 持久化域不一致（防御性）

- `PlayerTrackMix.volume` 实际存 0...1（`trackSnapshot`/`setTrack` 都是 0...1，`player.js:1952`），但校验允许 `<= 100`（`PersonalValidation.swift:116`）。历史原因（网页 0...100？）导致 100 也被接受，将来若有人误存 100，恢复时 JS `Math.max(0,Math.min(1,100))` 截断——行为上“音量 50 恢复成 100%”，用户可感知。
- `program` 对 percussion 无意义（见 F4/F8）。
- **建议**：校验收紧为 `volume <= 1`（或存盘前 normalize），并在 `PlayerTrackMix` 注释中写明“0...1 归一化音量”；`program` 对 percussion 统一存 0。属于防御性修复，风险低，但会与历史 0...100 数据不兼容→需同时做读取时的 `volume > 1 ? volume/100 : volume` 迁移判断（Lead 决定）。

---

## 4. task-3 六个问题的逐项回答

**Q1. `receivePlayerSnapshot` 解码 `gmInstruments/tracks` 是否正确？缺字段/缺 tracks 时 UI 行为？**
- `tracks`：`as? [[String: Any]]`（`NativePlayerPane.swift:2260`）对 WK 桥来说是正确形状；逐字段 `NSNumber`/`Bool`/`String` 取值 + 默认值齐全（`:2262-2277`）。**没有发现解码错误**。`tuning` 为空/缺省给 `[]`，`primaryTrack` 有兜底（`:993`）。
- `gmInstruments`：JS 端是 `[ [program, name], ... ]`（`practice-runtime.bundle.js:395`），Swift 用 `as? [[Any]]` + `pair[0] as? NSNumber`（`:2280-2285`）可以解出；`String(describing: pair[1])` 对 `NSString` 得到正确中文名。**无功能缺陷**，仅建议改成更防御的 `[[Any]]` 逐元素 `as? [Any]`（不必须）。
- `program=128`：**不是解码问题，而是持久化/校验问题**（F4）。
- `tracks` 缺失：若首次加载在 `api.scoreLoaded` 之前失败，`error` 事件走 `:1412`，面板因 `tracks.isEmpty` 显示“等待谱面音轨载入…”且 `scoreReady=false`，**会一直等到用户重开**（没有自动重试）；若此前有旧曲目，则显示旧 tracks（F5）。正常路径下 `scoreLoaded → sendPlayerState()`（`player.js:1181`）会在 `scoreReady` 前把 tracks 送到，不会长期等待。

**Q2. 面板控件是否都正确调用 `model.setTrack` 且语义匹配？音量 Slider 是否会造成 reload？静音/独奏/可见性是否在 JS 生效？**
- 全部 6 个控件都走 `model.setTrack`（`NativePlayerPanels.swift:25,32,34,38,43,52`），字段名与 JS 完全一致（`show/muted/soloed/volume/program/restoreProgram`），值域正确。
- `volume` 在 JS 不触发 `renderWithAudioReload`（`player.js:1949-1953` 仅 `changeTrackVolume`），**确认不会重载音频**；但会触发 `send('tracks')` → Swift 高频落盘（F6）。
- `show` 会 `renderTracks`（重排，不重载音频，`:1933-1942`）；`muted/soloed` 只改通道状态，均**在 JS 生效**。
- 唯一语义坑：`show=false` 同时静音（JS 有意），但面板 help 文案只说“在谱面中显示/隐藏此轨”（`NativePlayerPanels.swift:26`），用户可能以为“隐藏但还出声”。建议文案改为“显示并参与播放”。
- 打击乐轨的 program 控件无效（F8）。

**Q3. 音色 override 持久化是否闭环？打击乐 program 是否合法？旧 resume？sourceProgram/Name 是否会被覆盖错？**
- 键名闭环：`PlayerTrackMix{CodingKeys}`（`PracticeModels.swift:60-72`）与 JS `restoreResume` 读取的 `index/muted/soloed/volume/program/instrumentOverride` 完全对应；`PlayerResume` 其余字段（`trackIndexes/display/speed/playbackRatio/loop/capo/useSourceCapo/transpose`）也与 `player.js:1864-1917` 对应。**主链路闭环**。
- 打击乐 program 不合法：见 F4（可输出 128 → 校验失败；即使 0..127 也无播放意义 → F8）。
- 旧 resume 无 `instrumentOverride`：见 F7（会丢 override，与网页语义不一致）。
- `sourceProgram/sourceName` 错误覆盖：**Swift 不会覆盖**；JS 在 `applyTrackProgram` 里把 `track.name/shortName` 改成 GM 名（`player.js:591-592`），恢复/restoreProgram 时用 `state.sourceName` 还原（`:1963-1964`, `:1891-1893`）。唯一风险是 `createTrackMixState` 在“重载/显示模式重建”时保留旧 `sourceProgram`（`:606-608`），若谱面版本变化（scoreRevision 不同本就不 restore）不会被误用；在当前 revision 守卫（`NativePlayerPane.swift:1821`）下安全。

**Q4. 切音色时 Swift 是否有卡死/重复发送/无回调/播放状态不同步？**
- 无回调：`send()` 不等待 JS 结果，`setTrack` 的完成依靠 `tracks`/`playerSnapshot` 事件（`:1969`, `:2202`），正常有回调；JS 若在 `renderQueue` 中（`player.js:1972-1985`）会排队，期间 Swift 无 in-flight 标记。
- **重复发送**：面板未在任何“请求中”状态禁用，用户连续点不同音色会排多个 `renderWithAudioReload`（串行，每次最多 15 s 超时），前一次 `sendPlayerState` 的 tracks 会与后一次交错 → UI 短暂显示中间态。建议 Swift 侧对 `program/restoreProgram` 加 300-500 ms 去抖 + `trackChangeInFlight` 标记（UI 上可显示“正在切换音色…”）。**风险低但建议做**。
- `pendingSeek`：只有显式 `seek()` 会设置（`:1890-1937`），`setTrack` 不碰——**没有发现错误置位**。
- 播放状态/时间轴：JS 在重载期间用 `preserveAudioFocusForRender`（`player.js:2149, 1219-1239`）让 Swift 不释放音频焦点（`NativePlayerPane.swift:1299-1303`），重载后 `play()` 恢复；Swift `isPlaying` 随 `playbackState` 0→1 翻转，`reanchorPosition` 有 fence 保护（`:1559-1567`）。**未发现 UI 时间轴错乱**。真正的脆弱点仍是“自动恢复失败 → error → F1 永久失败态”。

**Q5. 面板默认“原谱音色”显示？实现 ukulele 原谱音色 Swift 需传什么？**
- 现状：`instrumentName(track.sourceProgram)`（`NativePlayerPanels.swift:47,71`）只查 128 条 GM 表，尤克里里曲目（program 24/25，`4 弦`）显示“原谱 · 尼龙弦吉他/钢弦吉他”，而不是“尤克里里”。原因：player.js 没有 flavor 概念（`trackSnapshot` 无此字段），`gmInstruments` 只有 GM。
- 必备 Swift 改动：§2.2 ①②（load payload `category`，来源 `CatalogItem.category` / `PersonalScore.category`）。
- 建议联动：player.js `trackSnapshot` 增加 `sourceFlavor`，Swift `NativePlayerTrack` 增加可选字段并在面板显示“尤克里里”。否则即使音源修好，面板文案仍会误导。
- 音源路由：Swift `PlayerResourceSchemeHandler` 已支持（`:87-98`），**不需要改路由**；只需 Lead 在 player.js 请求该 URL，并确认打包资源存在。

**Q6. 其它会导致用户可感知“音轨/音色”问题的 bug（按严重度）**
F1（播放器废掉）> F3（切音色后静音失效）> F4（断点保存失败）> F5（旧轨道残留/操作错轨）> F6（高频落盘/旧值竞态）> F7（旧断点丢音色）> F8（打击乐菜单误导）> F9（非练习页不持久化）> F10（粘滞错误）> F11（域不一致）。另注：`player.js` 的 `restoreProgram` 未 guard 打击乐（极小）、`loopRange` 在 snapshot 缺 loop 键时不清空（`NativePlayerPane.swift:2294-2298`，仅 UI 陈旧，低危）。

---

## 5. 建议 Lead 的验收/复测点（与 task-2 探针对齐）

1. **uke 路由**：加载 `1wmj8hqHnYf`，scheme handler 请求日志应出现 `/storage/soundfonts/ukulele_fast.sf2`（现在是 0 次）；同时 MidiFile program 仍应为 25（音源 flavor 与 program 是两件事）。
2. **切音色混音保持**：setTrack muted/volume → setTrack program → 播放，确认被静音轨/低音量轨的 PCM 仍按混音设置（F3 是否修好）。
3. **打击乐 program**：加载 `1xpyKV313Vh`，记录 `tracks[percussion].program`（0 还是 128）与 `percussion` 字段，验证 F4 的触发条件。
4. **错误分级**：故意制造一次 reload 失败/超时（或在 player.js 注入强制 `send('error', {message:'test'})`），确认 Swift 不再把 `scoreReady` 清掉、播放键仍可用（F1）。
5. **切歌残留**：A→B 切换，观察音轨面板在 B ready 前是否清空；B 加载失败时面板不应显示 A 的轨（F5）。
6. **旧 resume 兼容**：构造一条无 `instrumentOverride`、`program != sourceProgram` 的 resume，点“恢复设置”，确认音色恢复为保存值（F7；若 Lead 选择 JS 侧修，则探针直接测 restoreResume）。
7. **音量拖动写盘**：拖动 1 s 时统计 `PersonalStore` commit 次数（F6 目标：≤2 次/秒，且每 tick 不再写）。

## 6. 附：关键行号索引

| 主题 | 位置 |
|---|---|
| NativePlayerTrack 定义 | `Sources/MIMIGuitarMac/Player/NativePlayerPane.swift:94-108` |
| NativeGMInstrument 定义 | `:118-122` |
| NativePlayerSource | `:821-825` |
| canPlay / scoreReady 语义 | `:1004-1019` |
| pageDidBecomeReady + load payload | `:1088-1116`（payload `:1108-1114`） |
| receive() loadID 过滤 | `:1118-1123` |
| scoreReady / playerReady / soundReady | `:1230-1269` |
| playbackState / 音频焦点 | `:1270-1312`、`:2760-2789` |
| playerSnapshot / tracks 分发 | `:1393-1394` |
| **error 致命化** | `:1412-1424` |
| setTrack → JS | `:1749-1752` |
| restoreResume → JS | `:1820-1833` |
| send() / callAsyncJavaScript | `:1950-2007` |
| loadPersonalScore | `:2031-2151` |
| receivePlayerSnapshot 解码 | `:2258-2300` |
| markResumeDirty / scheduleResumeCheckpoint | `:2317-2350` |
| persistResume | `:2352-2377` |
| 轨道面板控件 | `Sources/MIMIGuitarMac/Player/NativePlayerPanels.swift:22-72` |
| 音源白名单（含 uke） | `Sources/MIMIGuitarMac/Player/PlayerResourceSchemeHandler.swift:22,30-31,87-98` |
| PlayerTrackMix / PlayerResume | `Sources/MIMICore/PracticeModels.swift:60-72, 87-138` |
| trackMix 校验 | `Sources/MIMICore/PersonalValidation.swift:111-118`（program 域 `:117`） |
| 持久化校验入口 | `Sources/MIMICore/PersonalStore.swift:943-946` |
| CatalogItem.category | `Sources/MIMICore/Catalog.swift:7,33` |
| PersonalScore.category | `Sources/MIMICore/PersonalModels.swift:10,20` |
| 播放器入口（category 可得） | `Sources/MIMIGuitarMac/Views/ScoreDetailView.swift:97,149`；`Views/FullParityViews.swift:691` |
| player.js trackSnapshot | `Resources/Player/player.js:563-584` |
| player.js setTrack | `:1928-1970`（program `:1954-1960`，percussion guard `:1956`，restoreProgram `:1961-1967`） |
| player.js restoreResume / trackMix | `:1844-1926`（override `:1886-1896`） |
| player.js applyTrackMixToApi | `:628-637`（仅在 `:2105` 被调用） |
| player.js renderWithAudioReload（缺 applyTrackMixToApi） | `:2141-2217`（loadMidiForScore `:2187`，seek `:2191`，play `:2193`） |
| player.js 固定 GM soundFont | `:1074` |
| player.js createTrackMixState | `:602-626` |
| alphaTab changeTrackMute（仅通道） | `Resources/Player/score-rendering.bundle.js:45103-45107` |
| 网页 flavor 规则（对照） | `project/src/lib/player/scoreAuditionResources.ts:106-168`；`scoreInstrumentOverrides.ts`（`resolveResumeInstrument`） |
| 网页 ScorePlayer 打 flavor | `project/src/components/player/ScorePlayer.svelte:790-797` |
