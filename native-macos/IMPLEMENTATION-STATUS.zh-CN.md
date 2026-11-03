# 全量迁移实施与验收状态

日期：2026-10-27（Asia/Shanghai）。用户要求将网页的界面和功能完整迁移为可安装 macOS 软件，复刻细节，不省略。

本文件记录代码范围和已取得的检查证据。**完整迁移尚未验收完成**。用户在 0.2.1 实际使用中报告曲谱无法播放，并出现“导入谱面路径无效，必须先复制到应用的 Imports 目录”，首页、曲库和工坊均有卡顿。旧 `outputs/Native-Mac-Full/MIMI Guitar.app` 是这一失败版本；它的编译、资源、签名与 DMG 校验不能作为功能通过的依据，也不代表当前 0.2.3 工作树。0.2.2 的修复与构建记录保留在下方历史。逐项页面和功能状态见 `FULL-PARITY-MATRIX.zh-CN.md`。

## 0.2.4 播放与界面优化（截至 2026-10-27，仍在验收）

本轮继续以原网页纸色、墨色和金色界面为基线，修复真实播放器路径并收紧页面转场成本。CPU 优化后的 0.2.4 Universal 包已通过架构、资源、签名、DMG 挂载和普通产品启动核验。完整迁移仍未验收完毕；packaged-18 中 U08 真实输入和 U12 系统矩阵未运行。

### 本轮实现范围

- 主谱复用原网页同版 AlphaTab 1.8.4、播放器设置、显示模式、歌词预处理、和弦布局补丁与导出实现。连续播放线使用引擎的音频采样/tick 插值；原生只读桥接不作为逐帧游标来源。
- 原生位置栏采用系统 `NSSlider` 输入/可访问性语义，并由 `CALayer` 绘制进度和拇指；SwiftUI 不再以整行 `TimelineView` 每帧重算控件。时间只由现有 worker 样本重锚，层动画按实际剩余时间线性推进，不增加 display link、timer 或独立时钟。`transportRevision` 在显式 seek/清空时重置旧动画，原生拖动期间 worker 更新只保存锚点，不抢写 slider 值或图层。packaged-18 已验证程序化 NSSlider target/action 路径和 `CALayer.presentation` 进度推进；没有把程序化输入描述成真实鼠标或键盘操作。
- 变速按 worker 实际回报重锚时间并过滤旧速度回报。暂停、恢复、seek、速度和循环操作沿既有 transport 执行。
- Seek 统一通过 single-flight、latest-wins 请求状态机。根因是 AlphaTab 的 `tickPosition` setter 会先在 API 当前样本写入目标 tick、保留旧 time，再向音频 worker 发定位命令；若立即用该临时样本作锚点，就会混合新 tick 与旧 time。现在只在 `playerPositionChanged` 返回 `isSeek` 且 tick 匹配当前 in-flight 请求时确认；等待期间沿用最后一次确认位置，快速连续定位合并到最新目标，超时会暂停并报告失败，load/stop/dispose 清理计时器和等待者。
- AlphaTab 构造时通过 RAF 延后 `initialRender()`，它在该回调中注册清理 renderer 结果计数的 `preRender` 监听。主谱现在在创建 API 后、`api.load` 前等待一次可取消的 RAF；隐藏文档未调度 RAF 时保持等待，不报加载失败，新 load 或 dispose 会取消旧等待并通过 load generation 核对。Swift readiness watchdog 在 native view 隐藏时取消，仅在 view 可见时开始或继续计时；这不改变播放 guard。
- 字体就绪只预加载 Cascadia Code，以保留 AlphaTab 原有字体选择/检查顺序，避免预载全部字体时提前种入不同的 `FontSizes` 缓存；FZ/Bravura 文件、CSS 与 AlphaTab 自身字体检查保持原样。真实 Docker source `clean-reference-17` 与 native `display-wake-17` 的三态对照中，13/13/12 个、共 38 个 SVG 节点及 computed profiles 逐项匹配；该比较全程 visible，并只读 `FontSizes` 缓存。隔离实验 font-load-order-experiment-14 保留为历史证据，不替代本轮真实来源对照。
- `positionSnapshot` 只读取已有位置样本；`diagnostics` 声明 `diagnosticsReadOnly: true`，读取现有的 `FontSizes` cache，不调用 `measureText`。源码属性不代替可见运行结果。
- 主谱 OffScreen follow 在 AlphaTab `renderStarted` 时清空上一 bar 的 y 缓存，使 resize/reflow 后下次 cursor 更新重新检查视口并沿用既有引擎滚动逻辑；不另设 timer 或时钟。packaged-18 的 U03 七个子项通过且跨行一次、滚动改变。单独的 `settled-resize-19-player-ux-1.jsonl` 中 U01 通过：postResize3 连续 visible 帧后，1280×800 截图延迟 43 ms、980×720 延迟 218 ms，native document 均真实 visible；不外推到其它宽度或 DPI。
- 详情标题/作者与主要动作在宽窗口对齐，窄窗口可折行；下载原件、改编、试听、分享、练习等原有入口保留。
- 专注/全屏继续复用同一播放器、WKWebView 和文档。切页不再同步缓存全页位图，改用轻量淡入与受动效策略约束的位移，避免同步绘制长页面。
- 系统减少动态效果时取消装饰性空间位移；应用关闭装饰动效不停止功能性播放线。

### 最新 packaged-18 与性能证据

- `clean-reference-native-17-comparison.json`：真实 Docker source clean-reference-17 对照 native display-wake-17，系统三态下 13/13/12 个 SVG 节点（共 38 个）与 computed profiles 全部逐项匹配；全部样本可见，`FontSizes` 仅只读。此项确认被测三态实谱字体/度量与 SVG 对照，不代表全谱库或所有窗口状态。
- `freshprogress-layout-18`：CPU 优化后的最终资源中 38 个 SVG 节点与 computed profiles 对照全部匹配。
- `functional-final-17` 场景索引 5/5 成功：direct、catalog reference、private GP5、XHE、Practice UI。GP5 样本取得 25 个非零 PCM 输出块；此批只作功能检查，不作为性能结果。
- 最终 `packaged-18-player-ux-1.jsonl` overall 为 **partial**；U01、U03 七个子项、U07、U09 通过，未运行项为 U08 真实输入和 U12 系统矩阵。22 秒、1,321 帧，rAF P50/P95/max 为 17/18/22 ms、超过 100 ms 的间隔为 0；872 distinct X、same-row 最大步长 3.196 pt、flat 18 ms、visible 1,317/1,321，跨行 1 次。该批没有覆盖真实 Esc/绿灯/menu 输入或 U12 系统矩阵。
- `settled-resize-19-player-ux-1.jsonl` 是 resize 专项，U01 通过，overall partial 是因为其它 case 不在本轮 scope。等待 postResize3 连续 visible 帧后捕获：1280×800 elapsed 43 ms、980×720 elapsed 218 ms；两处 native document 均真实 visible。此结果不扩展到其它窗口尺寸或 DPI。
- packaged-18 程序化设置原生 NSSlider 值并发送 target/action 成功；七个 `CALayer.presentation` 样本在同一 worker tick 间前进，actualRatio 约 0.7834→0.7844、宽度 833.5。它验证程序化输入/呈现层采样路径，不等于真实鼠标或键盘输入。AppKit 缓存截图可能反映 CALayer model 终点；真实进度应依据 presentation 样本，交付预览用静态 0:00 图，不以播放中缓存截图作为进度视觉真值。
- `packaged-17-player-ux-1.jsonl` 使用的是进度栏优化前资源，保留其 U01/U03/U07/U09 历史数据，不作为新 NSSlider/CALayer 控件验收。Stage 与 packaged Player 的 27 个资源文件、23,119,944 bytes 逐文件一致这一核对也属于 packaged-17。
- 早先在 resize 后 250 ms 抓取的 980×720 截图过早；`settled-resize-19-player-ux-1.jsonl` 已在稳定可见帧后完成复查并通过 U01，不用早期截图推断 resize 结果。
- 无编译、压缩或其他诊断同时进行的 `diagnostic-build-18b` 三轮完整播放器样本均成功。原生诊断 CPU 为 0.547545、0.606066、0.665143 秒，中位数 0.606066 秒；对照 `baseline-late-17-full-player3` 中位数 0.779609 秒，旧未优化 `packaged-perf-17-full-player3` 为 3.079423 秒。50 ms 心跳延迟中位数的 P95 为 2.08107 ms（旧基线 2.138189 ms），P99 为 3.024284 ms（旧基线 5.526499 ms）。这是所测原生诊断进程 CPU/心跳指标，不覆盖 WebKit、GPU、WindowServer，也不是 FPS、功耗或全系统性能结论；实际 PCM 正常不代表扬声器听感通过。
- 最终 Universal 2：版本 0.2.4、build `202610261557`；DMG 559,067,199 bytes，SHA-256 `d83b549ef56b34b8e9abc587dc7d16ce9b7ee63dbe468fdb969d260da9a3341d`。双架构、ad-hoc 签名、只读挂载、32,654 个文件/646,776,666 bytes 的包内外逐文件一致、SQLite 16,233 首曲谱/8 篇文章、正常卸载及完整路径普通产品启动均通过；PID 61000 在启动 12 秒后仍存活。日志 `universal-024-progress-final-build.log`，冻结清单 `release-024-progress-final-frozen-inputs.json`，完整核验 `package-024-final-verification.json`。优化前负向候选包保留于 `A24/package-before-progress-optimization`。
- `diagnostic-build-18b` 的 CPU 三轮仍为 0.547545/0.606066/0.665143 秒，中位数 0.606066；心跳 P95/P99 中位数 2.08107/3.024284 ms。音频采样率未锁定且不同批次音频时钟步长不同，不能外推到所有音频条件；CPU/主队列数据也不是 FPS、能耗或整机结论。

### 早期运行证据（保留历史）

以下结果来自较早的独立诊断批次，保留为历史。AlphaTab 首次 RAF barrier 与隐藏态 readiness watchdog 的可见运行证据以本节 packaged-18 和 clean-reference-native-17 为准；旧批次负例不覆盖新样本。

- 《斑马斑马》真实曲库主谱连续采样 22 秒：1,321 帧；rAF 间隔 P50 17 ms、P95 18 ms、最大 43 ms，未出现超过 100 ms 的间隔；同一行采得 837 个不同横坐标。U01 通过。该数据仅描述可见谱面游标，不是整页或整机 FPS。
- 半速 40 BPM、两倍速 160 BPM、恢复 66 BPM，连同暂停、seek、四小节循环均通过各自子检查。跨谱行跟随滚动子检查通过，实际滚动位置变化 1,037 pt；播放检查的 U03 总项仍为失败，因为恢复时文档处于 hidden，光标样本为 0 帧。transport 时间继续前进约 939 ms，不等于已验证恢复时的可见游标。
- 全屏循环 6 次的 U07 通过：同一 native 模型、WKWebView、文档 nonce、导航条目和音频上下文保持稳定，时间继续推进且音频非零块增加。
- U08 中通过了诊断自有窗口的程序化全屏往返和已有全屏状态恢复；真实 Esc、窗口绿灯和菜单输入没有被自动化，标记为未运行。
- 同曲/异曲试听 U09 通过，观察到新的非零音频输出；同曲重复试听迷你条隐藏。
- U12 未通过。当前系统 Reduce Motion 为开启且未更改；system/gentle/off 值有传到页面，但三种偏好下的必要游标样本都处于 hidden、0 帧，所以不能判定游标持续移动。系统 Reduce Motion 关闭矩阵及空间动效实测未运行。
- 真实 MusicXML Studio fixture 完成 48 次录入；导入内容为 4 小节、1 轨、16 音，撤销/重做、保存内容核对、PCM 试听及主谱非零音频通过。真实私有 GP5 附件导入后谱面/音源 ready、时钟前进，并取得 27 个非零输出块。

### 当前边界

- 字体三态对照的 38 个 SVG 节点及 computed profiles 已通过 clean-reference-native-17 的逐项比较；没有因此外推全谱库和全窗口状态。
- packaged-18 的 U01/U03 七个子项/U07/U09 通过，overall partial 仅因 U08 真实输入和 U12 系统矩阵未运行。独立 `settled-resize-19-player-ux-1.jsonl` 的 resize U01 通过；hidden 旧失败保留为历史，不覆盖新样本。NSSlider 程序化 target/action 与 presentation 采样通过，但未验证真实鼠标/键盘输入。
- `clean-integrated-16-score-fidelity-1.jsonl` 的 hidden 文档样本仍记为失败：initial ready 有 13 个 SVG，fast3 状态累积至 52/91/128 个，`surface=1`、`stability=hidden`。根因是隐藏态暂停 RAF，令 `initialRender` 中的 `preRender` 清理监听尚未绑定，而 `api.load` 已触发渲染。当前 barrier 与 watchdog 后的 visible 实谱对照及 packaged player UX 已取得上方所列结果；不删除旧 SVG/旧失败日志，也不把它们并入新结果。
- Home/Catalog 仅有同口径三轮进程 CPU 与 50 ms 主队列定时器对照，具体数据见 `RUNTIME-DIAGNOSTICS.zh-CN.md`；它不代表帧率、能耗或整台系统的性能结论。
- 初始化修复前的首个 Universal 包归档于 `A24/package-before-initialization-fix`，进度栏优化前的负向候选包归档于 `A24/package-before-progress-optimization`；均只作历史记录。CPU 优化后的最终 Universal 已按上方清单通过包核验与普通启动。U08、U12 系统矩阵及完整迁移边界仍未验收。0.2.3 的实现、诊断与安装包记录保留在下方，不回写为 0.2.4 验收。

## 0.2.3 源站界面还原与卡顿修复（2026-10-25）

本轮已生成独立 0.2.3 安装包；完整迁移仍按逐项清单继续验收。下面结果来自本轮最终冻结源码、实际安装包资源与本机运行，0.2.2 的结果在下方作为历史保留。

### 本轮实现

- 恢复原站导航、字体/颜色、页面容器与页脚；“我的谱”恢复 7 个纵向分区，仅显式指定分区或导入成功时执行一次定位滚动。
- 曲库恢复分组过滤与三种视图；修正窄窗口排序与热门词换行。练习按原站顺序读取本机活跃曲谱，不自动开始播放。
- 详情恢复标题/元标签/操作/说明、播放器、元资料/手稿/相关推荐的顺序。标签优先按 JSON 数组解析；相关推荐恢复带缩略图的横向卡片。播放器采用可换行紧凑工具栏、520 pt 谱面视口和正确的毫秒时钟。
- Studio 恢复整宽画布、底部工作台/调音台及草稿/歌词/高级属性弹层。常驻同一 WK 引擎，初始化成功后协调默认工程；恢复停止与定位当前拍、音乐时值字体和可见和弦按钮。单次 rAF watchdog 处理渲染帧未执行时的空白，不循环轮询。
- 草稿编码/扫描/原子写入放到串行后台；自动保存按 450 ms 空闲、最长 1.8 s 合并。草稿用原始工程 ID 的 SHA-256 命名，兼容旧文件时核对 ID。手动保存/导出/切换等待已接受编辑；异步回调核对工程、版本与所有权，离开与销毁有总时限。
- 帮助和 Showcase 恢复原标题、宽度、区块顺序与原有交互；没有为本轮重新定义视觉方向。

### 已取得的检查

- 最终 stage11 产品与诊断 typecheck 均通过；源码功能/视觉场景 12/12、最终 App 资源复查 5/5 成功。Player/Practice 各连续约 12 秒，实际进度、谱面和非零数字音频通过；MusicXML Studio 导入 4 小节/16 音，编辑、试听、撤销/重做与保存内容核对通过。
- 已人工复查 28 张最终页面快照，覆盖主要页面的 1280×900/980×900 和次要页面。原网页当前未运行，未取得同状态网页截图，不能判定逐像素一致。
- 三轮同驱动对照共 18/18 成功：曲库主队列 P99 中位数降低 33.6%；Studio 单次编辑原生 CPU 开销降低 49.4%，同等约 12 秒编辑数 31→50。首页 CPU +6.0%、P99 +2.0%，没有测出整体改善。指标不等同 FPS/能耗，详见运行诊断。
- Universal 2 0.2.3（202610250756）已构建并校验：最低 macOS 13、Intel/arm64、签名/资源/SQLite/DMG 挂载逐文件比对通过，普通产品启动 12 秒后仍运行。产品 Core -O / App -Osize；诊断两者 -Osize，二者分开报告。
- [安装包](../../../Native-Mac-0.2.3/MIMI-Guitar-macOS-universal2.dmg) · [安装说明](../../../Native-Mac-0.2.3/安装说明.zh-CN.md) · [本轮证据](RUNTIME-DIAGNOSTICS.zh-CN.md) · [机器可读结果](diagnostics/0.2.3-results.json)。未提交、未推送；签名为 ad-hoc、未公证。

### 仍待完成

完整像素/动画与全控件状态、全曲库/格式覆盖、系统听感、备份恢复及真实文件面板、并发和中断恢复、长时性能、帧率/能耗、Apple silicon 实机和正式签名。没有用类型检查、数字音频或截图就绪代替这些项目。

## 0.2.2 播放与性能修复

- 已定位播放路径错误：曲库条目记入最近记录、收藏或待练后成为 `source = catalog` 的个人曲谱引用；播放器将其包内 `Content/storage` 路径送入仅允许个人 `Imports` 的校验分支。修复让曲库引用重新解析原始曲库记录，复用曲库路径与 IBE/XHE 格式分发；个人附件仍按摘要核验并落入 Imports。
- 使用真实曲库文件与 0.2.1 的 Player 资源运行后，进一步捕获到 `undefined is not an object (evaluating 'api.soundFontLoadFailed.on')`；864.8 ms 即失败，谱面和音源均未 ready。该事件只存在于内部合成器，公开 API 已通过 `error` 转发；旧代码的重复订阅会直接中断初始化。另发现 CSP 的 `worker-src 'none'` 禁止了合成器必需的 Worker，关闭排版 Worker 并不会关闭音频 Worker。两者均纳入修复，不能只修 Imports 路径即视为播放恢复。
- 个人附件落盘、原谱读取及摘要计算移到后台任务，减少打开谱面时的主线程文件工作。
- 播放器发布状态的同步请求按主队列合并，控制器只发布变化的字段；界面在对应卡片和状态栏局部订阅试听状态，避免将播放时钟转发到全窗口。
- 首页搜索占位文字、指针光斑、指板/谱型/音轨示例状态拆到各自子视图；长页面与列表采用延迟布局，保留原有内容、控件与动效。
- 独立运行诊断已取得代表性证据：真实曲库 IBE 直接打开、曲库个人引用、个人 IBE 附件和首页试听均有 ready、播放进度前进与非零数字音频输出；XHE 曲库个人引用文字谱加载通过。它们不代表遍历全部 16,233 首曲谱、全部格式，也不代替扬声器听感检查。细节见 `RUNTIME-DIAGNOSTICS.zh-CN.md`。
- 首页/曲库各完成三轮注册 `Inter-Regular`、`Fraunces-Regular` 字体的交错 A/B 诊断：相较基线，CPU 秒中位数分别下降 51.4% / 41.2%，CPU/操作时段比值中位数分别下降 54.1% / 44.7%；主队列 P99 仍约 171–177 ms。测量固定为 1280×720 的指定场景，采用 `-Osize` 诊断构建；不代表 FPS、能耗、完整手动操作或发布包 CPU。工坊旧全功能诊断仍有明显卡顿负例；本阶段已完成三轮真实 `enterFret` Studio 诊断，但不能与旧 apply-only 负例计算严格 A/B，也不代表全量交互/长期性能验收。
- 本阶段又落地一组 Studio 与播放改动：工具栏按钮采用固定尺寸轻量布局；元数据、音轨、小节检查器、和弦与歌词等状态按可见值稳定更新；播放位置由独立 `StudioPlaybackPosition` 发布，避免通知整个编辑器；末拍录入、快捷键编辑和新增小节完成异步保存/更新后才移动游标。音符试听改为独立 `NativeGuitarAudio` PCM 路径并复用 SoundFont 缓存，移除主谱临时调用 `api.tex` 与延迟恢复机制，音频焦点以 token 防止旧回调释放新声源。
- MusicXML/IBE 的新改动已经有窄范围 WK 探针证据：IBE 使用 Studio 静态预加载的 `ar.es.js`，共享 `ar.browser` loader 复用已加载全局并跳过 CSP 禁止的 `eval`，CSP 未放宽；esbuild 重打 IBE/Studio bundle。Model 成功导入统一经 `install` 重置游标/历史、`contentRevision` 并取消旧操作/播放；失败解析在 clone 上执行，不污染原工程。GM 音符试听和和弦浏览器音源分工等范围及往返细节见 `RUNTIME-DIAGNOSTICS.zh-CN.md`。这些证据不覆盖完整原生窗口操作。
- 前一轮 `regions-final` 11 项诊断中有 10 项成功；唯一失败为当时真实 MusicXML→Studio 导入异常。后续全流程诊断还捕获 JavaScript 导入成功但 PersonalStore 因空 `artist` 拒绝持久化。共享导入桥已将缺失/空作者规范为“未知作者”，保留已有署名，不放宽 PersonalStore/Web schema，也未改原生 Swift。更新后小型 WK 桥接/格式往返探针以及当前10项完整 UI/播放诊断均通过。最新 MusicXML 产品场景成功导入4小节、1轨、16音，MIDI序列正确，personal revision 1→39；真实编辑33项/12.092 s、CPU 10.210 s、心跳 P99 89.83 ms，试听PCM/主谱非零音频与时钟、自动续写、撤销/重做和保存检查通过。空白 Guitar 编辑场景34项/12.209 s、CPU 10.062 s、P99 88.89 ms通过；Player/Practice 各自严格 UI 播放场景也通过。两条导入负例保留为历史；当前结果不代表所有 MusicXML 或所有工程通过。详见 `RUNTIME-DIAGNOSTICS.zh-CN.md`。
- 三轮 Studio 实际 `enterFret` 每轮约 12 s 完成 34 项编辑，CPU 分别为 9.909 / 9.817 / 9.822 s，心跳 P99 为 85.16 / 85.92 / 87.01 ms；末拍/快捷键追加、撤销/重做、保存、试听后主谱稳定均为 true。第三轮另确认主谱播放有非零 PCM 输出和时钟前进。完整 Player 与 Practice UI 各完成一轮真实挂载、连续约 12 s 播放、时钟前进、音频非零及实际谱面渲染检查；修正 `CGFloat` 数值误判后的严格 SVG/canvas 与正尺寸门槛通过。
- 当前状态：10 项 `verified-final` 源码诊断场景全部通过，包含实际 MusicXML 导入、保存、33 项编辑与主谱播放，完整 Player/Practice UI 连续播放，以及 direct/catalog/private/GP5/XHE/audition 六路径检查。两条此前 MusicXML 解析/持久化失败作为历史负例保留；证据仅覆盖所测 fixture 和场景。Universal `-O` 0.2.2 `.app`/DMG 已构建；lipo、架构切片与最终代码签名、资源树、`hdiutil verify` 及 DMG 挂载后的内外 App/资源逐文件比对均通过，DMG 内 SQLite 完整性、16,233 首曲谱、8 篇文章和 Applications 链接检查通过。使用同一诊断 binary 和最终 App 资源的 7/7 复跑通过：曲库末两轮与 staging 对照一轮、完整 Player、Practice、MusicXML Studio（16 音 MIDI 顺序正确，PCM 试听/主播放/保存为 true）及 audition；无产品代码变更。此前首次及随后 7 次资源复跑失败记录仍保留。`pmset` 显示 02:37 屏幕关闭、02:45/02:46 再次关闭，12:32 LidOpen 后唤醒；失败时 Studio 的 rAF 没有实际渲染。屏幕保持活跃并由临时 `caffeinate -di` 包装后，同一 binary 与资源通过全部场景，结果与休眠环境相关；这不构成完整睡眠/唤醒恢复验收。最终 `-O` App 已用完整路径 `open` 启动，PID 92852 在 12.08 s 后仍运行，仅为启动烟雾检查，不代表视觉或完整交互通过。全曲库、长期稳定、帧率/功耗及其它实机验收仍未完成。

## 当前实现范围

| 区域 | 当前代码范围 | 已知验收边界 |
| --- | --- | --- |
| 原生应用外壳 | SwiftUI/AppKit 主窗、侧栏/检查器、导航/搜索、原生菜单、键盘命令、文件面板、Finder/拖放分发、设置与页面路由 | 实际窗口布局、辅助功能、Finder 与导入流程尚未实机逐项验收 |
| 首页与设计细节 | 来源首页主层级、9 首 Hero 曲目、独立四首精选、TAB 向量预览、曲库试听/和弦弹层、搜索占位逐字动画、卡片倾斜/光照、乐理/榜单/练习信息/页脚/组件展示 | Bento 的记谱切换和三轨静音按原站保留为局部示例状态；试听徽标/时间/等化器与指板跟随全局播放器和实际音符。动画帧、减少动态效果与视觉像素未实测 |
| 曲库与详情 | 本地 SQLite 曲库、吉他/尤克里里类别、筛选/排序/分页、标题/歌手/文章搜索、命令面板和近期搜索、卡片/列表/谱集视图、详情/关联内容与本地文件动作 | 搜索语义、全部原站字段/失败状态、窗口尺寸下的布局和真实缺文件流程待验收 |
| 个人资料与练习 | 独立本机数据库、收藏/待练/个人曲谱/工坊工程、备注冲突、归档/恢复、最近记录、实时播放时段、续练快照、A–B 区间、递增速度计划、片段及删除墓碑 | 新安装不会读取网页 IndexedDB；浏览器资料需要用户通过备份流程显式导入。并发窗口及中断恢复仍待运行检查 |
| 个人数据备份 | v1/v2 JSON 与分卷模型、摘要/数量预览、附件和哈希校验、暂存、取消、冲突检测与事务恢复 | 需在最终应用中通过真实选择面板完成导出、导入、取消、坏文件和大文件体验检查 |
| 谱面播放器 | 本地 AlphaTab/WebKit 资源、IBE/GP/MusicXML 路径、XHE 文本谱、本地字体/SoundFont、播放传输、曲谱进度、速度/节拍器/预备拍、音轨、转调/变调夹、显示模式、和弦、指板、谱面图库、PDF/图像/原件/打印入口 | 代表性 IBE 路径已有 ready、进度和非零数字音频证据，XHE 曲库个人引用文字谱加载通过；全曲库、GP/MusicXML 矩阵、系统听感、打印及音频焦点仍待验收。MIDI 与独立 `.gpif` 不支持 |
| 制谱工坊 | 原生项目/音轨/小节/拍/音符模型；导入、草稿、元数据与轨道编辑、操作/撤销/重做、奏法与刷弦、和弦/歌词/指板、WebKit 谱面选区、CAS 保存与多格式导出通道 | 源站 8 种奏法及快捷键已对齐；拍级上/下扫与清除已接通模型、撤销/重做和导出。Studio toolbar、可见值更新、独立播放位置和异步光标更新已由真实输入诊断检查。0.2.3 最终 App 资源场景导入 4 小节/16 音 MusicXML 后完成 48 次录入，保存 9 次；持久化内容、公开保存确认、dirty 与 revision 核对通过，末拍/快捷键追加、撤销/重做、PCM 试听、谱面稳定和主谱音频/时钟通过。三轮同驱动编辑数中位数 31→50；完整功能矩阵、格式广度、导出兼容、命中区域、Retina 和长期性能仍待验收 |
| 文章、账户与说明 | 本地 8 篇文章索引/详情/搜索、发布页、登录/注册/资料/重置错误路径、帮助/政策/许可、关闭投稿声明、动效偏好与九区 Showcase | 需要服务端配置的动作必须报告真实服务错误；密码短信和公开投稿不可模拟成功。文章内容排版和远端接口尚未实机验收 |
| 离线数据和许可 | schema 2 本地 SQLite、来源文章与曲谱、公共 storage/SoundFont、AlphaTab/集成库/字体说明 | `FZXiaoBiaoSong.TTF` 来源文件没有附再分发授权；公开发行需确认其许可或移除/替换并重新核对谱面效果 |

## 0.2.1 细节补齐与整合

- 路由返回先恢复筛选、搜索域、排序、页码和查询；查询、账户服务和工坊源加载检查请求代次，旧响应不覆盖当前页面。
- 曲库引用使用一致身份；收藏和待练徽标、最近记录的曲名、重复迁入旧收藏已修正。练习状态与备注采用独立字段的原子更新；保存期间继续输入会保留新草稿，不会被提交快照覆盖或清除；归档、恢复、加入和移动与原站保持稳定队列顺序。
- Studio 编辑、撤销、重做与歌词操作进入串行保存队列；工程按 updatedAt 比较冲突。有练习副本时，工程和重新生成的 IBE 在同一事务保存，保留原件、旧副本 ID、备注和练习状态。切换工程会使旧编辑回调作废。
- 文章列表、搜索和详情区分加载、空、缺失、失败与重试；正文按原站保留原始换行。真实发布成功后缓存服务端接受的正文与 ID，按服务地址隔离，成功页可以立即打开全文。
- 动效页恢复暖身、分段、回顾、速度调节和渐进速度设置；Showcase 主题筛选作用于实际内容。图库采用可取消的后台图片解码。
- v2 备份采用网页外层格式，同时读取旧原生清单；已存在的同摘要附件核验后复用，打开其他窗口不清除有效恢复暂存。
- 打包补齐 `guitar-audio.bundle.js`，同时解析 Player/Studio HTML 检查本地脚本与样式入口依赖。旧 0.2.0 包仅做复制清单对照时未发现此遗漏，不能作为完整运行资源的最终包。
- PDF/PNG 导出复用原站离屏完整排版：A4 分页与完整长图，PNG 保留原站尺寸上限；文件生成和保存错误会明确显示。原生打印与实际输出文件仍须单独验收。

## 数据基线

- `Data/catalog.sqlite` 导出 16,233 首曲谱、8 篇文章，schema 2。
- 本地 storage 共 32,599 个文件；导出元数据记录 32,453 个资源引用检查，缺失 0、非法路径 0。
- 构建前/构建期间使用只读 SQLite 完整性查询；不启动 PostgreSQL、不更改 Docker 内容、不读取或覆盖网页个人资料。
- 个人资料存储与网页 IndexedDB 分离。第一次启动创建本地个人库；网页收藏、练习、片段、项目及附件只有在用户导入兼容备份后才迁入。

## 0.2.2 检查（历史记录）

| 检查 | 状态 |
| --- | --- |
| 0.2.2 源码运行诊断 | 代表性 IBE 播放路径和 XHE 文字谱加载已有结果；详见 `RUNTIME-DIAGNOSTICS.zh-CN.md`，不代表全格式覆盖 |
| `verified-final` 运行诊断 | 10/10 场景通过。MusicXML 完整原生 Studio 测例导入4小节、1轨、16音且MIDI正确，个人 revision 1→39；33项编辑/12.092 s、CPU 10.210 s、主队列心跳P99 89.83 ms；PCM试听、主谱播放音频/时钟、自动追加、撤销重做和保存通过。空白 Guitar 场景34项/12.209 s，CPU 10.062 s、P99 88.89 ms。Player/Practice 连续约12秒、非零音频、时钟、尺寸与11个SVG均通过，P99 31.56/42.05 ms；六条 direct/catalog/private/GP5/XHE/audition 场景按各自门槛通过（XHE仅文字谱加载）。此前两条MusicXML解析/空作者持久化负例保留。详细范围见运行诊断文件 |
| 首页/曲库性能对比 | 字体注册后三轮交错 A/B 已完成：CPU 中位数分别下降 51.4% / 41.2%，CPU/操作时段比值中位数分别下降 54.1% / 44.7%；固定 1280×720、`-Osize` 诊断构建，见 `RUNTIME-DIAGNOSTICS.zh-CN.md`。结果不是 FPS/能耗/发布包性能结论 |
| 工坊性能 | 三轮真实 `enterFret` 各约 12 s 完成 34 项编辑，CPU 9.909/9.817/9.822 s、心跳 P50 22.55/19.87/22.02 ms、P99 85.16/85.92/87.01 ms；PCM 试听、试听后稳定、末拍/快捷键追加、撤销/重做/保存检查均通过，第三轮主谱播放有非零输出与时钟前进。历史全功能 12.192 s/4 编辑、CPU 11.800 s、P99 818 ms 负例保留；旧 apply-only 与新 `enterFret` 不同负载，不计算 A/B 降幅。全功能性能、长期稳定、帧率/能耗仍未验收 |
| `-Osize` 隔离诊断 App | `release-final-build` 对应此诊断构建；10 项 `verified-final` 场景已全部通过 |
| 0.2.2 `.app` / Universal 2 / DMG | `native-macos/tools/build_macos_universal_app.sh` 的 `-O` Universal 2 构建已成功退出；x86_64/arm64、lipo、各架构/合并/最终 codesign、资源树、`hdiutil verify` 及 DMG 挂载后的内外 App/资源逐文件比对通过。DMG 内 SQLite 完整性、16,233 首曲谱、8 篇文章和 Applications 链接检查通过。82 项 package 输入 hash 已冻结，47 个 Swift 源文件 hash 与诊断编译时一致 |
| 0.2.2 成品 App / 资源运行 | 使用同一诊断 binary 和最终 App 资源的 7/7 场景通过，未改产品代码；包括曲库两轮及 staging 对照、Player、Practice、MusicXML Studio 与 audition。初次及 7 次失败记录保留；`pmset`/rAF 证据指向显示器关闭时环境关联，醒屏并临时 `caffeinate -di` 后同一场景通过，但不视为完整睡眠/唤醒验收 |
| 0.2.2 正常 App 启动 | 完整路径 `open` 启动成功；PID 92852 在 12.08 s 后仍运行。仅为启动烟雾检查，不代表视觉或完整交互验收 |
| 自动化测试 | 未新增、未运行；项目规则要求不得擅自添加或运行测试 |
| macOS UI/声音/导入/导出实机检查 | `-Osize` 源码诊断及使用最终 App 资源的 7/7 代表性场景已通过，普通 `-O` App 通过启动烟雾检查。最终资源复跑不改产品代码；它没有覆盖全部页面交互。Finder、全部格式矩阵、设备听感、打印/导出、像素级视觉、睡眠/唤醒完整流程、全控件和长时稳定仍未逐项验收 |
| 帧率、GPU/WindowServer、能耗及完整交互性能 | 未测；CPU 和主队列数据不等价于帧率或整体性能通过 |
| Developer ID / 公证 | 尚未配置；本地构建使用 ad-hoc 签名 |

### 构建过程说明

- 0.2.1 曾使用显式 macOS SDK 的 `swiftc` 路径完成构建；本机 SwiftPM 的 SDK `PlatformPath` 查询当时未成功。此记录是旧构建历史。
- 0.2.2 Universal 2 构建脚本默认版本与输出路径为 `0.2.2` 和 `outputs/Native-Mac-0.2.2/`；`release-final-build` 是 `-Osize` 隔离诊断 App，不是发布构建。10 项 `verified-final` 源码诊断通过后，`-O` 发布构建已成功并完成 lipo、架构切片/最终 codesign、资源树、`hdiutil verify` 及 DMG 挂载后的内外 App/资源逐文件比对。DMG 内 SQLite 完整性、16,233 首曲谱、8 篇文章和 Applications 链接检查通过。版本为 0.2.2（build 202610241829），最低 macOS 13.0，x86_64 + arm64；包内 32,599 个 storage 文件，Resources 共 32,649 个文件、592,813,534 B。App 约 700,755,968 B，DMG 563,044,527 B。最终 App 资源 7/7 代表场景通过；普通 `-O` App 正常启动烟雾检查通过。屏幕关闭时的一次初始运行及 7 次复跑失败记录保留，`pmset` 与 Studio 无实际 rAF 渲染表明结果与休眠环境有关；屏幕活跃并临时 `caffeinate -di` 后同一 binary/资源全部通过，不声称完整睡眠/唤醒功能已验收。首次卸载因诊断 Python 持有只读 SQLite 连接而返回 busy；进程退出释放连接后普通 detach 成功，未强制卸载，原始负例报告保留。47 个 Swift 源文件 hash 与诊断编译时一致，82 项 package 输入 hash 已冻结；签名为 ad-hoc，不含 Developer ID 或公证。

## 交付约束

- 当前交付为独立 `outputs/Native-Mac-0.2.3/` 中的 App/DMG/安装说明；0.2.3 的结果见本文顶部。原有 0.2.1/0.2.2 产物保持原样。
- 保持旧 `outputs/Native-Mac-Full/` 中失败的 0.2.1 包原样不动；0.2.2 `.app`、DMG 与安装说明已写入独立的 `/Users/mimi/Documents/Codex/2026-10-24/l/outputs/Native-Mac-0.2.2/`。DMG 挂载比对、最终资源 7/7 代表场景及正常启动烟雾检查均已通过；更广的设备、视觉和交互验收仍未完成。
- 现有 `package.json` 的用户改动保持原样；不提交、不推送、不创建 PR。
- 不能将“代码已写”表述为“像素级一致”或“全部功能验收通过”。任何未实现、仅示例化、远端不可用或尚未实机验证的行为应在逐项清单中继续保留。
