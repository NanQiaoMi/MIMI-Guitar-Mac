# 原站动效与系统适配迁移规格

主代理源代码核对，2026-10-24。实现负责人：complete_shell（全站原生界面）、complete_player（播放器/工坊）。这份规格为 FULL-PARITY-MATRIX 的补充；网页参数是复刻基线，动画应在原生窗口实际尺寸下自然适配。

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
