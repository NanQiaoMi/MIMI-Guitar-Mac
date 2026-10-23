# 乐器/技巧音效补齐计划（M9 · feat/player-instrument-fx）

## Summary
用户反馈「很多乐器的效果都没有实现」。经代码审阅 + CDN 实测 + 全量谱面扫描确认根因：

1. **P0 音源覆盖不足**：本地 `public/storage/soundfonts/` 仅有 72 个 `{program}.sf2`，而原站 CDN `https://p.insstudy.com/puquanle/soudfont/{program}.sf2` 实测 0–128 全部 200。缺失的 57 个音色（风琴 16-23、弦乐 47-51、铜管 59-63、木管 70-79、合成器 83-103、世界乐器 108-111、音效 120-127 等）在 `resolveSf2()` 中回退到 `0.sf2`（钢琴）→ 切换乐器或播放多乐器谱时大量音色被钢琴替代。
2. **P1 鼓组音源偏旧**：本地 `128.sf2` = 700,572B，CDN = 918,922B，需换新版并确认鼓组采样/映射。
3. **P1 贝斯击勾（tap/slap/pop）无 MIDI 效果**：全量扫描 8125 谱，tap=41 / slap=15 / pop=13 谱存在 `beat.tap/slap/pop` 数据，但 AlphaTab 1.8.4 MidiFileGenerator 不为其生成任何力度/音色差异（仅谱面渲染 S/P/T 字母）。
4. **P2 演奏技巧可闻性**：bend/harmonic/palmMute/letRing/slide/vibrato/dead/accent 等数据→MIDI 链路已确认完整，可闻性依赖音源质量；补齐音源后抽样验证并给用户试听清单。

## 关键决策
- 音源：全部 129 个 program（0–128，含 128 鼓组）从原站 CDN 拉取（用户已确认沿用原站 sf2），立体声→单声道复用现有 `convert-sf2-mono.mjs`，重建 `index.json`。
- 回退：补齐后 `resolveSf2` 仍保留 `0.sf2` 兜底（防御），但正常不再触发。
- tap/slap/pop：先做可行性调研（AlphaTab 1.8.4 私有 `_midiFile` 后处理 or 放弃），实现则按「力度差异 + 短促时值」增强，验收以 MIDI 事件断言为准。
- 不升级 AlphaTab、不改源码、不引入第三方 DSP（混响/延迟/失真不在本档；如需另立任务）。

## 里程碑（每步 开发→验证→记录→验收，未通过不进下一步）

### M9.1 音源全量补齐（P0）
- 新增 `tools/fetch-sf2.mjs`：遍历 0–128，HEAD 探测→GET 下载到临时目录；失败重试（最多 3 次，退避 1s/3s/6s）；小并发（4）控制 CDN 压力；进度输出；产物清单。
- 对每个新下载文件跑 `convertSf2`（立体声→单声道），原子写回 `public/storage/soundfonts/{p}.sf2`；已有且已被 mono 化的文件若与 CDN 字节一致可跳过。
- 重建 `index.json`（0..128 全量）。
- 验收：`index.json` 含 129 项；`tools/analyze-sf2.mjs` 全量无 sampleType 2/4 残留；无下载失败文件（失败项列出并重试）。

### M9.2 音源加载验证（P0）
- Playwright 专项 `tools/verify-instrument-fx.mjs`：
  - 对代表性缺失 program（17 风琴 / 40 小提琴 / 48 弦乐 / 49 弦乐 / 56 小号 / 64 萨克斯 / 73 长笛 / 108 马林巴 / 128 鼓）切换乐器 → 断言加载对应 `{p}.sf2` 且**不再**回退 0.sf2（network 断言 + loadedPrograms 断言）。
  - 多乐器谱播放：全音轨 program 均有对应 sf2 加载，console 无 `unsupported sample` / 404 / 静音警告。
  - 截图/日志归档 `tests/evidence/instrument-fx/`。
- 回归：`node --test`、`npx astro build`、`tools/verify-track-controls.mjs`、`tools/verify-instrument-switch.mjs` 不回归。

### M9.3 鼓组与打击乐核对（P1）
- 换新版 `128.sf2`（CDN 918KB → mono 后约 460KB）；确认 `PercussionMapper` 音符映射（kick/snare/hihat/tom/cymbal）落在鼓采样范围。
- 抽查含 Drumkit 轨的谱（如 `1wn6yWS3fJR` 系列）：播放无静音警告、鼓轨独立音量/静音/独奏生效。
- 验收：鼓组播放有实际事件（`midiEventsPlayed` 或控制台无异常）；鼓轨 UI 控制生效。

### M9.4 贝斯击勾 tap/slap/pop（P1，先调研）
- 调研：AlphaTab 1.8.4 `_midiFile` 私有访问可行性（`(api as any)._player...` / `_midiFile` 结构 / tickCache 定位）；评估对 `loadMidiForScore` 产物的后处理方案。
- 若可行：实现 `applyBassArticulations()` —— 对 tap/slap/pop 拍上的音符（经 `api.tickCache` 定位 tick），slap/pop 提升力度（+20 左右）、tap 用短促时值；在 `withRenderPreservingPosition({reloadMidi:true})` 的 MIDI 重生成路径后调用；单测锁定。
- 若不可行：记录原因与备选（不破坏官方 API），标注「待用户决策」。
- 验收：含 tap/slap/pop 谱（如 `1H9RahleH`）的 MIDI 事件中该拍音符 velocity 有差异；回归无破坏。

### M9.5 技巧音效可闻性抽查与试听清单（P2）
- 用 Playwright 对含 bend（天地龙鳞 `1H9WW324T`）/ harmonic / palmMute / letRing / slide 的代表谱播放：断言 MIDI 事件含 PerNotePitchBend / 力度差异 / 时值缩短等，console 零报错。
- 产出「试听清单」（歌名 + 技法 + 预期听感）写入 DEV_LOG，供用户在浏览器最终确认（headless 无法听音）。

### M9.6 回归收尾
- 全量回归（node --test 全量、astro build、verify-track-controls、verify-track-mode、verify-instrument-switch、verify-player-display、verify-player-audio、verify-score-details、verify-player-fix、verify-m7-final）。
- 更新 DEV_LOG.md（M9.1–M9.6 逐条日志 + 进度看板）与 PLAN.md。
- 合并 master（`--no-ff`）后主分支冒烟；清理临时脚本与下载缓存。

## 测试与验收总纲
- 每个里程碑：Playwright（打开页面→交互→截图→console/pageerror 零报错）+ 对应单测（sf2 转换、index.json 完整性、tap/slap/pop MIDI）。
- 音源专项：129 项全存在且 mono；切换任一 program 不再回退钢琴；鼓组/多乐器谱播放无警告。
- 证据统一写入 `tests/evidence/instrument-fx/` 与 DEV_LOG.md。

## 风险与延迟项
- 下载 129 个 sf2 约 40MB：网络/CDN 限流可能慢，脚本带重试与断点（已下载跳过）。
- 大文件（24/25 = 11.6MB）加载内存/时序：沿用现有串行加载与去重，必要时预加载常用 program。
- tap/slap/pop 若需源码级 hack 则不做（保持官方 API），改用备选或标记限制。
- 混响/延迟/失真等 DSP 音效不在本档（AlphaSynth 为纯 GM 合成器），如需另立任务。