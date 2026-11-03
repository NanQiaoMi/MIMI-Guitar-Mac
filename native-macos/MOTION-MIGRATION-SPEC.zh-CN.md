# 原站动效与系统适配迁移规格

主代理源代码核对，2026-10-24。实现负责人：complete_shell（全站原生界面）、complete_player（播放器/工坊）。这份规格为 FULL-PARITY-MATRIX 的补充；网页参数是复刻基线，动画应在原生窗口实际尺寸下自然适配。

## 0.2.4 原生动效实现与验证边界（2026-10-27）

本节补充当前原生实现与实测结果。原站的纸色、墨色、金色和信息层级仍是视觉基线；本轮没有把全站改成另一套设计。

- 普通页面切换采用轻量淡入与 6 pt 归位位移；受系统 Reduce Motion 影响时去掉空间位移，应用 `off` 只取消装饰过渡。系统减少动态效果不得把必要的播放线改成跳点或静止。
- 主谱播放线继续使用 AlphaTab 音频/tick 驱动的连续插值。最终 App Resources 的 packaged-18 U01 通过：22 秒、1,321 帧，rAF P50/P95/max 为 17/18/22 ms，超过 100 ms 的间隔为 0；1,317/1,321 帧可见、同一行 872 个不同 X 值，最大步长 3.196 pt、flat 18 ms。单独的 settled-resize-19 resize U01 也通过，覆盖 1280×800 与 980×720 两个可见尺寸；这些数据不证明整页 FPS，也不外推到其它窗口宽度或 DPI。
- 工具栏的原生时间进度栏与曲谱绘制层游标是两条视图路径：前者使用系统 `NSSlider` 保留 tracking、键盘与 VoiceOver 语义，`CALayer` 绘制轨道、进度和拇指；后者仍由 AlphaTab 音频/tick 推进。时间栏只以 worker 样本为锚，不使用 SwiftUI 60Hz `TimelineView`、新增 timer 或独立时钟。`transportRevision` 在显式 seek/清空时重置层动画；slider 正在拖动时原生输入优先，后台 worker 样本只更新锚点元数据。
- 主谱 OffScreen follow 的 bar-top 去重值在 AlphaTab `renderStarted` 时失效；resize/reflow 后下一次 cursor 更新会重新判断当前视口，并沿用原 scroll handler。AlphaTab 首次 `initialRender` 由 RAF 调度，主谱在 `api.load` 前等待一次可取消 RAF，以免 hidden 文档暂停 RAF 时首轮渲染早于 `preRender` 清理监听；Swift readiness watchdog 在视图隐藏时暂停计时。修复前 clean-integrated-16 的 hidden 样本仍保留为失败；packaged-18 U03 七个子项均通过，跨行一次且滚动位置实际改变。`settled-resize-19-player-ux-1.jsonl` 的 resize U01 通过：postResize3 连续 visible 帧后，1280×800 elapsed 43 ms、980×720 elapsed 218 ms 截图均为真实 visible。早先 250 ms 截图过早；settled 结果仅覆盖这两个窗口尺寸，不外推到其它宽度或 DPI。
- 页面切换已移除同步 `cacheDisplay` 全页位图路径，保留轻量入场。对应 Home/Catalog 三轮测量见 `RUNTIME-DIAGNOSTICS.zh-CN.md`；这些进程 CPU 与主队列定时器数据不是通用帧率或功耗结果。
- packaged-18 中 U07 全屏往返与 U09 试听通过，U03 七个子项均通过。overall partial 仅因 U08 真实 Esc/绿灯/menu 输入和 U12 系统矩阵未运行；真实 NSSlider 鼠标/键盘输入也不在程序化 target/action 通过项的声明范围内。旧 hidden 总项失败仍保留为历史。packaged-18 中程序化 NSSlider target/action 成功，七个 `CALayer.presentation` 样本在相同 worker tick 间前进，actualRatio 约 0.7834→0.7844、宽度 833.5；AppKit 缓存截图的 model 终点不作播放进度真值，预览采用静态 0:00 图。

本轮运行时系统 Reduce Motion 保持开启，没有为测试更改系统偏好。因此，关闭系统 Reduce Motion 后的 full 空间页面动效矩阵未运行；真实 Esc、窗口绿灯和菜单输入也未运行。`diagnostic-build-18b` 的完整播放器三轮原生诊断 CPU 中位数为 0.606066 秒；audio sample rate 未锁定，批次间 audio clock step 不同，且指标不代表 FPS、功耗或整体性能改善，口径见 `RUNTIME-DIAGNOSTICS.zh-CN.md`。最终 Universal 已完成双架构、签名、DMG 挂载和普通产品启动核验；U08/U12 与完整迁移仍未完成。旧规格表中的“强制静止”应理解为装饰性位移/动效，不包括真实音频进度、时间和 AlphaTab 必要播放线。

## 动效偏好契约

| 原站选择 | 实际效果 | 系统减少动态效果 |
| --- | --- | --- |
| 跟随系统 | full 系统动效 | 强制静止 |
| 轻柔 | 最长140ms，仅淡入、颜色、背景、边框、阴影；无位移、缩放、倾斜、持续装饰和纸张翻页 | 强制静止 |
| 静止 | 状态直接到达最终帧，页面内容与操作不隐藏 | 静止 |

持久值来自 `mimi:motion-preference:v1`（system/gentle/off）。系统偏好始终优先；不能读到系统偏好时按静止处理。应用内切换动效时，正在进行的弹层/翻页/开卷须立即到达安全终态并解锁输入；不重播、不留半透明控件。遵循 macOS `accessibilityReduceMotion`。静止只关闭装饰过渡，不停止声音/输入/播放进度，也不隐藏必要的信息。

## 源参数

主要 tokens（`src/lib/ui/motion.ts`）：

| 用途 | full | easing |
| --- | ---: | --- |
| micro | 120 ms | standard `cubic-bezier(0.2, 0, 0, 1)` |
| control | 200 ms | settle `cubic-bezier(0.22, 1, 0.36, 1)` |
| panel | 260 ms | standard |
| page | 280 ms | standard/settle（离场/入场分别） |
| exit | 160 ms | 依 surface kind |
| folio | 360 ms | 由翻页 keyframe 决定 |

- menu 默认向下偏移8px、scale .99；panel 偏移12px、scale .985；notice 偏移4px。退出默认为160ms。反向变化从当前帧平滑继续。
- gentle 中 menu/panel/页面进入只淡入，无位移缩放；最高140ms。静止0ms。
- 原生实现可用 SwiftUI/AppKit 动画曲线近似其控制点，但需同方向、同持续时间及可逆行为；不可为显示参数添加空白控制。
- 页面前进淡出、到达淡入向上6px（gentle仅淡入）。共享导航条保持不动，活动导航项用200ms选中变化。
- 控件的hover/press、active、disabled、focus 视觉需分别表达。focus-visible边框2px `#41a1cf`/offset2 不应依赖动画。

## 纸艺与首页效果

- 页面底纹为源64×64 SVG fractal noise（约3.8% alpha）叠原 radial/linear gradients；可重复的静态纹理先绘入缓存层，不随心跳逐帧重画。
- `paperReveal` 仅在元素已经出现过、之后滚入可视区域时单次触发；full淡入+10px、220ms、delay最多60ms；gentle淡入140ms；首屏 SSR 已绘内容不先隐藏，键盘聚焦立即 settle。
- `ink-draw` 为 1.4s `cubic-bezier(.16,1,.3,1)` 的 stroke-dashoffset 1200→0。纸封面绕左边缘 rotateY 0→−172°，1.3s `cubic-bezier(.25,1,.35,1)`；在动效页的“重播开卷”入口每次均从一致起点播放，不能只变封面静态标记。
- PaperFolio 卡片翻页为方向不同的 3D 翻页，token360ms、事件/有界timer负责解锁。翻页中禁止第二次翻页；Esc/隐藏窗口/切到gentle或off时结算到最终页并清理 timer。全动态时播放0.48s纸张摩擦音；gentle/off/减少动态效果不播放该装饰音。
- 首页英雄卡 hover/换曲只变对应纸卡与谱例，不移动整页；同页 audition 准备/播放/暂停/失败有各自状态。声波/光效依据真实播放事件；不可因模型有 activeItem 而冒充正在播放。

## 播放器、音符、后台

- 全屏两侧水印谱线/视差只在 full、窗口可见且细指针桌面触发；视差每帧最多一次，位移限约±5px。播放时暖金呼吸；真拍事件短脉冲；暂停/隐藏/reduce 后回落并注销 timer/rAF。
- MusicNoteParticles 只对可见的实际尺寸区域运行（源 uses IntersectionObserver + document visibility），离屏/后台停止 rAF；计数受限。谱面 note sparks 由引擎 `playedBeatChanged` 的真实 note positions触发并有生命周期上限，禁止用合成时钟假装音符。
- 指板的琴弦谐振、品位弹出与波纹来自真实手动试听/当前拍；manual audition 要走同一 audio focus。静止模式保留当前弦/品的状态高亮，不运行弹跳。
- 真实音符高亮、AlphaTab 播放光标和声音时序仍工作；切换应用失焦时不重叠播放。装饰层可暂停，音频焦点策略单独负责真实播放器的暂停/恢复。

## 性能、资源与验收边界

- 持续效果只在有声音/可视/需要动画时激活。页面切走后停掉非必要帧回调、timer、观察器；结束、取消、改变动效偏好要清理。大图列表先按显示像素降采样并限制缓存；不能把整张 90 卡片大图同步解码在主线程。
- 优先 transform/opacity 的合成变化；背景噪点、阴影、模糊、列表布局不可在60Hz回调里无界变化。动态视差/粒子不应增加静音时功耗。避免把播放器主 WebKit 和整个导航/账户/个人库包进 WKWebView。
- 验收记录需分清：代码/资源检查、静态编译、网页交互参照、原生 UI/Reduce Motion/音频/能耗实测。网页截图不能证明原生像素或 Mac 性能；本机原生 UI 自动化当前不可用，未实际操作的状态标记“未验收”。

## 对应源文件

`src/lib/ui/motion.ts`、`motionPreferences.ts`、`folioMotion.ts`、`paperReveal.ts`，`src/styles/motion.css`、`global.css`，`src/components/PaperFolioSection.svelte`、`ambient/MusicNoteParticles.svelte`、`ambient/FullscreenPaperWatermarks.svelte`、`ambient/MasterpieceIntro.svelte`、`player/ScoreNoteSparkTrails.svelte`、`player/VirtualFretboard.svelte`。
