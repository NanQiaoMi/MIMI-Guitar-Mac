# 乐谱播放指针闪烁修复（0.2.4，2026-10-27）

本轮针对“播放时红色乐谱指针闪烁 / 回跳 / 换行与全屏转场时整谱闪”的修复记录。历史 0.2.4 交付与验证结果保留不变；本文件只记录本轮源码修复、A/B 运行证据和边界。

## 1. 结论

- 根因不在 AlphaTab 的插值数学（22 秒 steady trace 的逐帧 x 仍然连续、872 个不同 x 值），而在 **重复的 `placeBeatCursor`（0ms 强制定位）、每帧触发的整谱重排、以及 0.2.4 新增的合成层/高亮重绘成本** 三者的叠加。
- 修复只改动两个运行时资源文件：`Resources/Player/player.js`、`Resources/Player/player.css`。构建脚本会原样复制它们，因此 **不需要重打 `score-rendering.bundle.js`**，也不需要改 AlphaTab 或 Swift 源码。
- `outputs/Native-Mac-0.2.4/MIMI Guitar.app` 已就地替换这两个文件、重新 ad-hoc 签名并重启验证（旧文件备份见第 7 节）。
- 同诊断程序、同 content 资源、同 1280×800 窗口，仅替换这两个文件做 A/B：seek 启动阶段强制定位 **2 → 1 次**、rAF P95 **56 → 18 ms**、指针不可见间隙 **128 → 0 ms**；22 秒 steady 阶段强制定位保持 1 次、回跳 0 次、不可见间隙 **66 → 50 ms**、滚动重启采样 **15 → 9**；U01/U03（含 pause/resume/seek/循环/变速/跨行）与 U07/U09 均通过。

## 2. 修复前的运行基线（0.2.4 交付资源，`--case player-ux`）

| 指标（WKWebView 内 60 Hz rAF 原始采样） | 修复前 |
| --- | ---: |
| U01 steady 22 s：帧数 / rAF P50 / P95 / max | 1316 / 17 / 19 / 43 ms |
| steady 内 `transition ≥N ms → 0 ms` 的强制 place | 1（跨行） |
| steady 内同行走回跳（dx < −0.5 pt） | 0 |
| steady 内指针不可见帧 / 最长间隙 | 4 / 66 ms |
| steady 内滚动目标重启（scrollTop 跳变 > 1 pt） | 15 |
| seekStartup（650 ms）：帧数 / rAF P95 / max | 27 / 56 / 176 ms |
| seekStartup 内强制 place | 2 |
| seekStartup 内指针不可见帧 / 最长间隙 | 10 / 128 ms |
| U03.pause 暂停瞬间光标本体横移 | 3.27 pt |

这与“自动检查通过、肉眼仍闪烁”的现象一致：DOM 矩形一直连续，但合成器层、逐帧重排和暂停时的双 place 不在 trace 的判定范围里。

## 3. 根因与修改

### 3.1 暂停时两次强制 place（红光标回跳/闪）

AlphaTab 1.8.4 `_onPlayerStateChanged` 在暂停时会先把引擎 tick 写回当前拍首并调用 `scrollToCursor()`；该写入会触发一个 `isSeek` 位置事件，先后导致：

1. 拍到拍首的 place（第 1 帧）；
2. `player.js` 用 `requestSeek(采样 tick)` 把引擎恢复到暂停前位置，确认后又 place 一次（第 2 帧）。

两次 place 在相邻帧，用户看到红线“回跳一下再跳回来”，暂停时还可能整屏跳转。

修改（`player.js`）：

- 新增 `beginPauseCursorGuard()` / `endPauseCursorGuard()`：暂停请求发出时冻结 `api._cursorUpdateTick` 与自定义跟谱滚动；恢复 seek 确认（或播放被重新恢复）后解除冻结，并 **只 place 一次** 到采样 tick。
- 保留原有的 restore seek，因此“暂停位置 = 恢复位置”的语义不变（U03.pause / U03.resume 通过，resume 时间继续前进）。
- `finishPendingSeek`、`state === 1`、`stop/load/dispose`、重建 API 时都会正确释放 guard。

### 3.2 容器尺寸变化触发逐帧整谱重排 + 强制 place

AlphaTab 在 `#score` 容器上挂 ResizeObserver（宽或高变化都触发），回调里执行 `renderer.updateSettings + renderer.width = ... + renderer.resizeRender()`；`postRenderFinished` 会清 `_currentBeat` 并 `_cursorUpdateTick(forceUpdate: true)`。窗口动画/全屏转场/面板开合期间尺寸每帧变化，于是 **每帧一次整谱重排 + 每帧一次强制 place**。

修改（`player.js`）：`createApi()` 里安装 `installResizeRenderCoalescer(api)`，对 `api.renderer.resizeRender` 做 140 ms trailing 合并，窗口尺寸稳定后只重排一次。

### 3.3 每拍全清全加高亮并改字重/描边

AlphaTab 每个 beat 都 `removeHighlights()` + `highlightElements()` 全量增删 class；而 0.2.4 的 CSS 额外给 `.at-highlight` 文本加 `stroke` 与 `font-weight: 500`，每拍触发 SVG 字形 re-shape 与整页重绘。

修改（`player.css`）：高亮只保留朱红 `fill`，去掉 `stroke` 与 `font-weight`。修复前后 1280×800 截图对比：谱面几何、红拍线、暖金小节底与红色音符高亮均一致（只是数字笔画略细）。

### 3.4 `#score-scroll` 常驻合成层

0.2.4 给滚动容器加了 `transform: translateZ(0)`、`will-change: transform`、`backface-visibility: hidden`、`perspective: 1000px`。这会把几千像素高的整张谱面常驻在一个 3D 合成层里，任何指针/高亮/滚动更新都要整层重栅格化——在 Intel + macOS 13 + WebKit 上表现为合成层级别的闪烁（DOM 几何完全正常）。

修改（`player.css`）：移除上述四个属性，保留 `contain: layout` 与原有背景/圆角。

### 3.5 附加的低风险收敛

- **拖动进度条 seek 合并 70 ms**（`player.js seek()`）：原生滑块每个指针采样都会发 seek，之前每次都强制 place；现在首个请求立即生效，连续请求合并到最新 tick（约 14 次/秒），拖动仍跟手。
- **变速同值写入跳过**（`setPlaybackSpeed` 与 watchdog 重试）：写入相同 `playbackSpeed` 本来就是 no-op，却会触发 `mainSeek` + 强制 place。
- **换行跟随更短**（`settings.player.scrollSpeed` 250 → 150 ms）：换行时光标先 place 到下一行，滚动动画把该行带入视口前有一段看不见的空窗；缩短后空窗从约 250 ms 降到 150 ms。
- **manuscript 滚动消息合并**：滚动监听改为每 rAF 最多一次，且页码不变不再 `send`，减少自动跟谱期间 SwiftUI 的状态刷新。

## 4. 修复后 A/B 结果

同一诊断程序（`.build/flicker-audit/MIMIRuntimeDiagnostics.app`）、同一 `Content` 资源、1280×800 窗口；唯一差异是 Player 资源：

| 指标 | 修复前 | 修复后 |
| --- | ---: | ---: |
| steady 22 s 帧数 | 1316 | 1317 |
| steady rAF P50 / P95 / max | 17 / 19 / 43 ms | 17 / 18 / 34 ms |
| steady 强制 place | 1（跨行） | 1（跨行） |
| steady 回跳（dx < −0.5 pt） | 0 | 0 |
| steady 不可见帧 / 最长间隙 | 4 / 66 ms | 3 / 50 ms |
| steady 滚动目标重启采样 | 15 | 9 |
| seekStartup 帧数 / rAF P95 / max | 27 / 56 / 176 ms | 41 / 18 / 25 ms |
| seekStartup 强制 place | 2 | 1 |
| seekStartup 不可见帧 / 最长间隙 | 10 / 128 ms | 12 / 0 ms |
| U03.pause 暂停瞬间横向移动 | 3.27 pt | 1.86 pt |
| U01 / U03（7 个子项）/ U07 / U09 | 通过 | 通过 |
| U08 真实输入 / U12 系统矩阵 | 未执行 | 未执行（overall partial） |

机器可读汇总：`diagnostics/0.2.4-flicker-fix-results.json`。

## 5. 变更文件

| 文件 | 变更 |
| --- | --- |
| `Resources/Player/player.js` | pause 光标冻结/单次 place；`resizeRender` 140 ms 合并；seek 70 ms 合并；变速同值跳过；换行跟随 150 ms；manuscript rAF 合并与去重 |
| `Resources/Player/player.css` | 移除 `#score-scroll` 强制合成属性；高亮只保留 `fill` |
| `outputs/Native-Mac-0.2.4/MIMI Guitar.app/Contents/Resources/Player/{player.js,player.css}` | 就地替换并重新 ad-hoc 签名（构建产物，非源码） |
| `diagnostics/0.2.4-flicker-fix-results.json` | 本轮 A/B 机器可读结果 |

修复后资源哈希：

- `player.js` `7ace38c1dcd5cce0ac41b55a5030756e739488c8bf918df6265b39322ed19e38`
- `player.css` `812be5df6b150cbfae14c1e4834542ff241f662aa5b1c824c93c62155dda6c22`

## 6. 复现与验证命令

```sh
# 诊断程序（已存在；如需重建）
bash project/tools/build_runtime_diagnostics.sh

APP=project/.build/flicker-audit/MIMIRuntimeDiagnostics.app/Contents/MacOS/runtime_diagnostics
RES="/Users/mimi/Documents/Codex/2026-10-24/l/outputs/Native-Mac-0.2.4/MIMI Guitar.app/Contents/Resources"

# 修复后（Player 资源换成源码目录 + 成品原资源拼出的 staging 目录）
"$APP" --content-root "$RES/Content" --player-root project/.build/flicker-audit/player-fixed --case player-ux

# 修复前基线
"$APP" --content-root "$RES/Content" --player-root "$RES/Player" --case player-ux
```

`project/.build/flicker-audit/` 下保留两轮原始 JSONL、屏幕捕获与截图。注意：源码目录 `native-macos/Resources/Player` 不含 `_astro/ font/ alphaTab.js ar.es.js`（这些由构建脚本从网页工程复制），验证时必须用上面的 staging 目录或成品 App 资源。

## 7. 边界、回滚与未完成项

- U08（真实 Esc/绿灯/菜单输入）与 U12（系统减少动态效果完整矩阵）两轮都未执行，overall 仍为 **partial**；本轮没有新增测试套件。
- 本轮 raw trace 是 DOM/CSS 级别的 60 Hz 采样，**不能直接证明合成器 1–2 帧的可见闪烁**；用强制 place 次数、rAF 停顿、不可见间隙、滚动重启作为代理指标。window 级 CGWindowList 截图拿不到 WebKit 的 `will-change` 光标层（需整屏捕获），因此没有做逐帧屏幕录像 A/B。
- 未执行窗口拖拽/全屏转场的连续屏幕录像对比；3.2 的合并按代码机制修复，A/B 中 seekStartup 的 rAF 176 ms → 25 ms 是间接证据。
- 交付 App 是 **ad-hoc 签名**、只替换资源并重新签名（`codesign --verify --deep --strict` 通过），未重建 Universal 2 二进制；`outputs/Native-Mac-0.2.4` 里的 **DMG 与 BUILD-MANIFEST 仍是修复前构建**，与当前 App 不一致。要正式重出包，运行 `bash native-macos/tools/build_macos_universal_app.sh`（源码已修复，会带入），并按 BUILDING.zh-CN.md 重新核验 DMG。
- 回滚：原文件备份在 `project/.build/flicker-audit/app-resources-backup/`（哈希与修复前交付一致），复制回 App 后重新 `codesign --force --deep --sign -` 即可。
