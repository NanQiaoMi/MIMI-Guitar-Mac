# 0.2.3 运行、界面与安装包证据

日期：2026-10-25（Asia/Shanghai）。最终源码冻结为 `integrated-stage11`，与当前产品输入摘要一致。产品和诊断的全量 `swiftc -typecheck` 均通过，Universal 2 产品包已生成。下方 0.2.2 内容保留为历史；两轮数字不混合计算。机器可读汇总见 [0.2.3-results.json](diagnostics/0.2.3-results.json)。**完整迁移和全部功能验收仍未完成。**

## 本轮环境与口径

- 本机 MacBookPro15,1 / Intel Core i7-8750H / 32 GiB / macOS 13.7.8。功能诊断使用独立临时个人库，不清空、恢复或迁移用户个人库。
- 产品是 Core `-O`、App `-Osize`，不定义诊断宏；独立运行诊断是 Core/App 均 `-Osize`，定义 `MIMI_RUNTIME_DIAGNOSTICS`。诊断通过不能替代正常产品的全控件操作验收。
- 用户确认保持解锁后顺序运行最终复查。性能轮次没有并行编译或其它 MIMI 诊断，使用临时活动断言，没有修改永久电源设置；未控制所有其它应用负载。
- 三轮性能对照中，修改前/后使用字节完全相同的三份诊断驱动，均为 1280×720、关闭额外 trace、每个场景约 12 秒；第 2 轮交换运行顺序。Home/Catalog 执行相同操作，Studio 每次录入等待实际渲染确认，在同一时长内完成的编辑数量不同。
- CPU 是原生诊断进程的累计 CPU 秒；主队列延迟是 50 ms 定时器的迟到量。不包含 WebKit/GPU/WindowServer 全部开销，不是 FPS、功耗或整台 Mac 的流畅度结论。

## 最终功能检查

下表的原始文件均位于 `../.build/runtime-audit-023/`。

| 检查组 | 实际结果 | 原始证据 |
| --- | --- | --- |
| 最终源码场景 | 12/12 成功：9 条功能路径与 3 组视觉捕获。覆盖 IBE 直接打开、曲库个人引用、个人附件、GP5、XHE 文字谱、首页试听、完整 Player/Practice UI 与 MusicXML Studio | `final-source-verification-index.json` |
| 最终安装包资源 | 同一源码诊断程序直接使用 0.2.3 App 的 Content/Player/Studio 资源，曲库引用、试听、Player、Practice、Studio 共 5/5 成功 | `final-package-resources-scenario-index.json` |
| Player / Practice | 最终包资源复查各连续约 12 秒；时钟从 0:00 到 0:12，末尾仍在播放，实际 SVG 渲染和正尺寸检查通过。各取得 27 个非零音频块、110,592 帧、peak 约 0.21249 | `full-player.final-package-resources-1.jsonl`、`practice-ui.final-package-resources-1.jsonl` |
| MusicXML → Studio | 同一 4 小节/1 轨/16 音 fixture，导入 MIDI 序列正确。最终包资源运行完成 48 次真实录入；撤销/重做、自动续写、快捷键续写、PCM 试听、试听后谱面稳定、主谱非零音频与时钟均通过 | `studio-edit.final-package-resources-1.jsonl` |
| Studio 保存 | 最终包资源运行 saveCount 9、手动保存 1；current/requested revision 均 54、dirty=false。Store 内容与当前工程全部字段（除 updatedAt）一致；模型公开的已保存工程内容及 updatedAt 与持久化快照一致。不是仅凭“已保存”文案判定 | 同上，`saveVerification.successfulAttempt` |
| 普通产品启动 | 完整路径启动实际 0.2.3 Universal App，open 返回 0，12 秒后 PID 64877 仍运行；仅证明正常启动 | `normal-product-startup.json` |

XHE 是文字谱，不要求音频；非零数字音频不代替扬声器/耳机听感检查。最终源码 MusicXML 那轮完成 49 次编辑，发生在编译期间，只用于功能检查，未纳入性能对照。

## 本轮性能对照（三轮中位数）

| 场景 | CPU 秒：修改前 → 修改后 | 主队列 P50 ms | 主队列 P99 ms | 结论 |
| --- | --- | --- | --- | --- |
| Home | 1.426 → 1.512（+6.0%） | 1.281 → 0.911 | 135.06 → 137.76（+2.0%） | 没有测出整体提升，保留为后续优化项 |
| Catalog | 1.831 → 1.775（−3.1%） | 1.135 → 0.864 | 166.29 → 110.37（−33.6%） | 所测操作中的尾部延迟下降 |
| Studio 录入 | 10.164 → 8.347（−17.9%） | 27.963 → 7.080 | 100.99 → 85.46（−15.4%） | 每轮编辑数 31 → 50；单次编辑 CPU 329.98 → 166.94 ms（−49.4%） |

Studio 保存次数中位数 37 → 8；所有三轮修改后样本的撤销、重做、保存内容核对均通过。三场景两版本三轮共 **18/18** 成功。相同时间窗口完成更多编辑是吞吐量变化，不能描述为完全相同工作量下的总 CPU 比较。逐轮数据与方法见 `final-performance-summary.json`、`final-unlocked-performance-index.json`。

## 界面对照

- 最终源码已抓取并人工查看 28 张 PNG：主要页面 1280×900 与 980×900 各 9 张，次要页面 1280×900 共 10 张。视觉窗口高度 900，与数值性能测量的 720 分开记录。
- 主要页面：首页、曲库、我的谱顶部/底部、练习、详情顶部/底部、Studio 顶部/底部。次要页面：备份顶部/底部、文章列表/详情、账户资料/收藏/登录、帮助、动效设置、Showcase。
- 捕获工具先等待布局，再选取当前路由对应的 WKWebView，捕获前后复核身份，并检查实际 SVG/canvas 与非空图像。最终 9+10+9 条路由就绪门槛通过；这不等于每个控件、每张缩略图和所有状态均已逐项验收。
- 截图复核后修正窄窗口热门词、筛选排序、和弦按钮换行，恢复完整导入类别文案与音乐时值字体。工坊横向工具栏和指板保留区域滚动及全部操作入口。
- 原网页 127.0.0.1:4336 当前不可连接；依据为原源码和已保存的历史截图，没有同状态网页截图。**像素级一致性、全部动效与全状态仍待验收。**

快照目录：`visual-snapshots.final-source-wide-1-snapshots/`、`visual-secondary-snapshots.final-source-wide-1-snapshots/`、`visual-snapshots.final-source-narrow-1-snapshots/`，均在本轮 audit 目录内。它们是本进程 NSView/WKView 快照，不是已安装产品的系统截屏。

## 0.2.3 安装包

- 输出：[MIMI-Guitar-macOS-universal2.dmg](../../../Native-Mac-0.2.3/MIMI-Guitar-macOS-universal2.dmg)。版本 0.2.3，build `202610250756`，最低 macOS 13.0，含 x86_64 + arm64。
- 最终 Universal 构建、lipo、ad-hoc codesign、资源树与 hdiutil verify 通过。DMG 只读挂载后，内外可执行文件、Info.plist、签名资源与所有 Resources 逐文件相同；普通 detach 成功。
- Resources 32,649 个文件、592,819,671 B，其中 storage 32,599 个；SQLite integrity=ok，16,233 首曲谱、8 篇文章。导出 metadata schema_version=2，SQLite user_version=0，二者不混称。
- DMG 560,234,782 B；SHA-256 `93b62392a953ffdcbd8b14877aad789198871ca862d107e45f470c81d355f59d`。验证原始报告：`package-023-verification.json`。
- 签名为 ad-hoc，未做 Developer ID 签名或 Apple 公证；arm64 通过交叉编译和结构检查，未在 Apple silicon 实机运行。

## 本轮保留的失败与工具修正

1. 初始手工诊断 App 缺少 Resources 目录，隔离配置失败；补全后重跑。源目录 Player 本来不含打包时补入的全部依赖，首次视觉 staging 不完整；不计作产品故障或通过。
2. Stage 7 完整资源下 Studio 确实空白，initial_score_render 超时。探针显示 hidden document 的 rAF 安排后不进入，而直接 api.tex 能渲染。产品增加单次可取消的 120 ms watchdog，保留 rAF 主路径及 generation/身份检查。Stage 8 隐藏环境真实导入 4 小节/16 音、36 次录入、保存及音频随后通过；trace 显示 rAF=0、timer=1，不能据此声称完整睡眠恢复通过。
3. Stage 8 曾报告 9/9 视觉 ready，但 05-score.png 实际使用离开中的 Practice WK，是工具 false positive。最终严格版本重新取得路由对应 WK 并捕获，旧结果不追认通过。
4. Stage 8 Player/Practice 的 playback_not_started、时钟 0 与 document hidden 同时出现；播放器按既有规则禁止后台开始播放。用户确认解锁后最终源码及最终包资源均复跑通过。失败日志保留，不直接归为产品回归。
5. 早期两轮 perf-final-fixed-studio-round2/3 保存门槛失败，状态被“试听完成”覆盖，不能由此推断磁盘结果。最终驱动改为内容、保存确认、dirty 和 revision 核对；旧失败保留，最终基线也用相同新驱动重编译。产品同时防止旧试听完成回调覆盖新保存状态。
6. 首次 0.2.3 Universal 打包因最后三处窄窗口排版修正而主动停止（143）；最终冻结源码的 universal-023-build.final.log 返回 0。历史编译失败与修复原因见 work-log.json。

未新增或运行自动化测试套件。全曲库/全部格式、设备听感、Finder/拖放与保存/打印面板、备份恢复、并发/中断/强制退出、长时使用、FPS/能耗、Apple silicon 实机和逐像素界面仍保留在 [完整清单](FULL-PARITY-MATRIX.zh-CN.md)。

# 0.2.2 运行诊断（历史记录）

数据截至 2026-10-25。本次诊断针对用户报告的曲谱播放失败和多个页面卡顿。`release-final-build` 是 `-Osize` 独立诊断 App，不是 Universal 发布构建。10 项 `verified-final-scenario-index.json` 源码诊断场景均已通过。其后 `native-macos/tools/build_macos_universal_app.sh` 的 `-O` Universal 发布构建已完成；lipo、双架构切片与最终 codesign、资源树、`hdiutil verify`、DMG 挂载后的内外 App/资源逐文件比对及 DMG 内 SQLite/曲目/文章/Applications 链接检查均通过。使用同一诊断 binary 与最终 App 资源的 7/7 场景已通过；正常 `-O` App 也通过一次启动烟雾检查。本文件仍区分源码诊断、资源复跑和正常 App 启动，后两者均不等同完整 GUI 验收。

## 设备与隔离

- 本机为 MacBookPro15,1，Intel Core i7-8750H、12 个逻辑 CPU、32 GiB 内存，macOS 13.7.8。
- 诊断程序从真实产品 Swift 源码编译，使用独立应用标识 `com.mimi.guitar.runtime-audit`，以临时个人数据库和 Imports 运行，退出时清理临时数据。
- 曲库和其他随包内容仅只读引用；用户正在运行的 0.2.1 应用、个人资料和 Docker 部署均未替换或重置。
- 编译旗标 `MIMI_RUNTIME_DIAGNOSTICS` 仅用于临时数据目录、诊断注入和运行入口；普通安装包不启用这些代码。

## 已复现的失败

1. 曲库引用被交给个人 Imports 校验，触发用户提供的原始错误。修复后必须分别检查目录直接打开、个人库/收藏/待练引用与实际导入附件。
2. 使用真实曲库 IBE 和 0.2.1 Player 资源，864.8 ms 后捕获 `undefined is not an object (evaluating 'api.soundFontLoadFailed.on')`，`scoreReady = false`、`audioReady = false`。公开 AlphaTab API 没有此事件，其失败已通过 `api.error` 转发。
3. 原页面 CSP 禁止 Worker；音频合成器即使选择 ScriptProcessor 输出也仍需 Worker。修复采用页面读取本地完整 classic runtime 后建立 Blob Worker，保留离线资源白名单。
4. 首轮真实首页试听诊断等待 45 秒仍未取得 host。原 `NativeAuditionHost` 的空 Group 无实际视图承载初始化回调；修复使生命周期依附始终存在的视图，并由局部视图观察谱面源。

## 播放检查口径

使用真实曲库文件、实际原生模型、WebKit 资源处理器与 AlphaTab 运行时。音频检查在原 ScriptProcessor 回调完成后读取其生成的输出缓冲，要求：

- 谱面与音源均 ready。
- 进入播放状态且时间实际前进。
- AudioContext 为 running，至少一个音频输出块非零。

这证明应用生成了可播放的数字音频，不代替系统输出设备、静音状态或扬声器听感检查。XHE 按来源站点是文本和弦谱，检查文字谱加载，不将其记为音频播放通过。

当前代表性结果如下，均使用真实曲库条目；这些结果不代表遍历了全部 16,233 首曲谱或全部导入格式。

| 入口 | 结果 | 数字音频证据 |
| --- | --- | --- |
| 曲库直接打开 | 谱面/音源 ready，进度从 0 前进到 2,414.9 ms | running；26 个非零块，106,496 帧 |
| 收藏/待练使用的曲库个人引用 | 原路径错误消失，实际播放成功 | running；26 个非零块，106,496 帧 |
| 实际导入数据库的个人 IBE 附件 | 摘要校验、落盘、加载与播放成功 | running；25 个非零块，102,400 帧 |
| 实际导入的个人 Guitar Pro 5 附件 | 个人附件读取、曲谱/音源 ready，播放进度前进 | running；25 个非零块，102,400 帧 |
| 首页隐藏宿主试听 | 宿主正常初始化，谱面/音源在约 2.5 s ready，进度实际前进 | running；25 个非零块，102,400 帧 |
| XHE 曲库个人引用 | 真实文字谱加载成功 | 不适用，文本谱 |

隐藏试听的首轮成功诊断还显示 1 × 1 WebView 会把谱面内容压到 68 px 宽、3,760 px 高。后续修复给内部 WebView 稳定 1024 × 720 排版尺寸，外部保留裁切后的不可见宿主。复查的谱面内容宽度为 940 px、滚动高度 2,742 px，页面仍为 visible，25 个音频块非零且时间前进；未删除源谱或音轨。

## 完整播放器与练习页诊断

最新 `verified-final` 中的 `full-player` 与 `practice-ui` 实际挂载完整 `NativePlayerPane`，使用真实曲库来源和隔离的个人库；各完成一个连续播放约 12 s 的样本，谱面/音源 ready、开始与进度前进、非零音频、播放期间状态和播放时钟均有效。以下为这批最新样本数据；更早 `regions-final` 的原始性能结果在后文保留为历史记录。两批均使用 `-Osize` 源码诊断 App，不是最终 Universal 发布 App。

| 场景 | 心跳 P99 | 连续播放与 UI 渲染检查 |
| --- | ---: | --- |
| 完整播放器 | 31.56 ms | 连续约 12 s，非零音频、时钟前进；11 个 SVG、WebView/DOM 正尺寸且无 Web 错误 |
| 完整练习页 | 42.05 ms | 连续约 12 s，非零音频、时钟前进；11 个 SVG、WebView/DOM 正尺寸且无 Web 错误 |

修复数值转换后的渲染门槛还要求 AlphaTab 可用、无 Web 错误、WebView frame/bounds 和 DOM score/scroll 尺寸为正，并至少有一个尺寸有效的 SVG 或 canvas。两份最新记录均有 11 个可见 SVG、0 个 canvas、2 个 score 子节点，WebView frame/bounds 与 score/scroll 尺寸均为正；`nativePlayerRenderObserved=true`。练习场景另确认 `practiceDataReady` 与 `practiceJoined` 为 true。

更早两轮原始记录仍保留 `nativePlayerRenderObserved=false`，它们因诊断谓词把 `[String: Any]` 中的 `CGFloat` 硬转换为 `Double` 而误判；这些历史记录没有被重写。后续重跑修复数值归一化，并增加实际 SVG/canvas 与尺寸联合门槛，达到条件后才报告通过。以上是各一轮 12 秒源码诊断，不代表帧率、功耗、长时稳定性、最终发布包运行或所有控件均已验收。

## 首页与曲库性能口径

固定 1280 × 720 窗口、同一只读曲库和隔离的原生窗口，比较同一产品源码中修改前/后的 Views 快照。两组都以 `-Osize` 编译诊断程序，注册 bundled `Inter-Regular` 与 `Fraunces-Regular` 字体（三次运行均确认字体可用），每个场景按交错顺序各运行三次。记录进程 CPU 时间、预设操作时段、50 ms 主队列心跳延迟和首屏加载时间。产品发布脚本使用 `-O`；诊断构建优化参数不同，不能将其绝对 CPU 值直接当作发布包实测。

这些数据衡量指定场景的工作量与主队列阻塞，**不是帧率**；不覆盖 WindowServer/GPU 能耗、WebKit 子进程总 CPU 或完整手动操作体验。工坊编辑另用实际工程和编辑操作检查，不能用空工坊页面的数据代替编辑性能。

### 三次运行的中位数

| 场景 | 版本 | 进程 CPU 秒 | 操作时段 | 心跳延迟 P99 | 每轮最大延迟的中位数 | 首屏加载 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 首页滚动与切页 | 基线 | 3.163 | 12.294 s | 250.6 ms | 1,178.9 ms | 2,424.8 ms |
| 首页滚动与切页 | 修改后 | 1.536 | 12.842 s | 171.2 ms | 274.9 ms | 386.2 ms |
| 曲库滚动与切页 | 基线 | 3.211 | 12.151 s | 291.5 ms | 1,124.2 ms | 1,704.2 ms |
| 曲库滚动与切页 | 修改后 | 1.886 | 12.801 s | 176.8 ms | 272.0 ms | 580.6 ms |

- 三次运行的进程 CPU 秒中位数：Home 降低 51.4%，Catalog 降低 41.2%；按各轮 CPU/操作时段比值取中位数后，分别降低 54.1% 和 44.7%。修改后两场景的主队列 P99 与首屏加载中位数也低于基线。
- 基线每轮滚动动作中位数为 11 次（其中一轮 12 次），修改后为 12 次。日志确认各场景找到 NSScrollView 且实际滚动发生；不能据此说每次尝试都滚动成功：修改后 Catalog 首轮第一次滚动时 `maxY=0`、`didScroll=false`，后续滚动操作成功。
- 结果来自同一组当前产品源码（除 Views 快照外）、只读曲库和注册成功的 bundled 字体。这里比较的是诊断构建；不代表交付 app 已构建，也不证明所有页面、动画、手动操作或能耗目标通过。修改后仍有单次较长主队列延迟，不能宣称无卡顿或达到 60 FPS。
- 指标汇总可在 `native-macos/diagnostics/0.2.2-results.json` 的 `fontRegisteredUIPerformance` 核对；原始记录位于 `.build/runtime-audit-022/home.font-{baseline,fixed}.[1-3].jsonl` 和 `catalog.font-{baseline,fixed}.[1-3].jsonl`。

## 工坊真实编辑（`regions-final` 三轮）

历史完整功能记录中，约 12.192 s 只完成 4 项编辑，进程 CPU 时间为 11.800 s，50 ms 心跳延迟 P50 为 483 ms、P99 为 818 ms。这一负例继续保留。新源码的三轮 `regions-final` 均使用实际 `enterFret`，每轮约 12 s 完成 34 项编辑：首轮 CPU 9.909 s、心跳 P50/P99/max 为 22.55/85.16/95.95 ms；第二轮 9.817 s、19.87/85.92/94.24 ms；第三轮 9.822 s、22.02/87.01/88.33 ms。三轮均检查到编辑、自动续写、撤销/重做、保存、非零 PCM 试听及试听后主谱稳定；第三轮还确认主谱播放时钟前进并有非零输出。三轮运行不能证明所有工程或长期稳定性，也不能与旧 apply-only 脚本计算严格 A/B 降幅。

隔离对照没有支持“24 品指板是主要瓶颈”的早期判断：关闭指板的诊断变体反而更慢。另一诊断变体仅为测量而不构建工具栏，约 12 s 内完成 15 项编辑，P99 为 170 ms，但 CPU 仍为 11.242 s；该结果改变了诊断界面组成，不能视为完整产品修复或交付性能。旧 apply-only 操作与新 `enterFret` 不是同一工作负载，不用它们计算 A/B 降幅。三轮完整产品 Studio 输入诊断已完成上述范围检查，但仍不是帧率、能耗、全量交互或长期稳定性验收。

## `regions-final` 前一轮诊断（11 项场景，保留历史结果）

本轮以实际产品交互验证 Studio 播放与编辑，而非沿用仅调用 `apply` 的旧性能脚本。批次索引 `.build/runtime-audit-022/regions-final-scenario-index.json` 共列 11 项：10 项退出码为 0，唯一失败为真实 MusicXML→Studio 导入。各路径的范围与结果如下：

| 诊断路径 | 运行时检查 | 状态 |
| --- | --- | --- |
| Studio 音符试听 | 实际触发 `enterFret`；检查 `NativeGuitarAudio` PCM 非零、试听后主谱稳定 | 三轮通过；每轮 7 个非零 PCM buffer、448,000 帧、peak 约 0.20246；重复 2 与主谱播放第三轮均有 34 项编辑 |
| Studio 自动续写 | 末拍输入、快捷键和新增小节完成异步工作后移动游标；检查撤销/重做、保存 | 三轮自动追加、快捷键追加、撤销/重做和保存检查均为 true；第三轮另确认主谱播放音频非零且时钟前进 |
| Studio 导入 | 真实 MusicXML 文件进入产品 Studio 导入流程并验证可编辑谱面 | **当时失败**：旧源码诊断中的 `minimal-audible.musicxml` 在 `studio_file_import` 阶段返回“导入失败：发生了JavaScript异常”；未保存预期工程名，个人库 revision 未变化、编辑数为 0。此为后续修复前的历史负例；新源码另有下节小型 WK 探针结果，完整原生 UI 路径仍待本轮复查 |
| 完整 Player UI | 实际挂载完整 `NativePlayerPane`，连续播放约 12 s 并检查谱面渲染、音频和时钟 | 一轮通过：CPU 3.541 s，心跳 P99/max 29.66/132.04 ms；播放约 12.007 s，时钟前进，25 个非零块/102,400 帧；11 个可见 SVG，尺寸检查有效 |
| 完整 Practice UI | 实际挂载完整 `NativePlayerPane`，连续播放约 12 s 并确认练习数据/加入状态 | 一轮通过：CPU 4.859 s，心跳 P99/max 40.66/40.82 ms；播放约 12.049 s，时钟前进，25 个非零块/102,400 帧；11 个可见 SVG，练习数据 ready 且已加入 |
| 其他播放器样本 | direct IBE、曲库引用、个人附件、GP5、XHE、首页试听 | 本批均通过各自检查：IBE/GP5/首页试听数字音频非零，XHE 为文字谱加载检查，不记作音频通过；不代表全格式矩阵 |

Studio 三轮原始记录位于 `.build/runtime-audit-022/studio.regions-final.1.jsonl`、`studio.regions-final.2.jsonl` 与 `studio.regions-final.audio.jsonl`。第三轮实际主谱播放的音频上下文处于 running，观测 13 个输出块（11 个非零、53,248 帧、peak 约 0.1443），时钟从 0 前进至约 1,207 ms。该 11 项批次是导入修复前的历史记录；其中的 MusicXML 失败不覆盖随后新源码的小型桥接探针结果，也不能由该探针反推完整原生 Studio 流程已通过。其余成功记录只覆盖表中列出的具体场景，不等于长期稳定或完整功能矩阵通过。

为降低通知范围，Studio 元数据、轨道、小节检查器、和弦和歌词状态改为按可见值稳定更新，播放位置由独立 `StudioPlaybackPosition` 发布；工具栏按钮采用固定尺寸的轻量布局。音符预览使用独立 `NativeGuitarAudio` PCM 路径并复用 SoundFont 缓存，不再通过主谱临时 `api.tex` 与延迟恢复试听；音频焦点 token 用于阻止旧回调释放新声源。三轮真实输入诊断支持表中编辑与音频检查；旧全功能卡顿负例和非全功能对照继续保留。Player/Practice 首轮渲染门槛阴性记录也继续保留作诊断历史；修复 `[String: Any]` 内 `CGFloat` 数值转换后，新一轮要求 AlphaTab 无错误、WebView 与 DOM 尺寸为正且实际 SVG/canvas 有有效尺寸，本批两页各见 11 个可见 SVG 并通过门槛。

## MusicXML→Studio 小型桥接与往返探针

导入失败负例之后新增 `.build/runtime-audit-022/import-roundtrip-author.json` 小型 WK 真实桥探针。探针确认不带 TAB 的标准五线谱 `Guitar` 可导入，缺少原始调弦时推断标准吉他 E-A-D-G-B-E，自动匹配 0–24 品音符；warning 明确提示核对自动指法并保留原谱。最大匹配边界用同拍 `[64, 88]` 两音测试，均保留。一个 4 小节、16 音 fixture（MIDI 序列 `[60, 62, 64, 67]` 重复四次）在导入及 JSON、AlphaTex、GP、IBE 往返读取后，小节/音轨/音符数和 MIDI 序列一致；空作者被归一为“未知作者”，JSON 空作者探针也通过；当前导出大小为 JSON 15,355 B、AlphaTex 625 B、GP 3,222 B、IBE 1,789 B。上一版探针字节数已被此作者归一化版本替代。

为解决 IBE 往返在 CSP 下被 `eval` 拦截，Studio 改为静态预加载 `ar.es.js`；共享 `ar.browser` loader 复用已加载全局而跳过 `eval`，未放宽 CSP，并以 esbuild 重打自有 IBE 与 Studio bundle。构建日志中的 Astro、tsconfigs/strict 与隔离环境警告为非致命项。模型成功导入经统一 `install` 重置游标/历史、更新 `contentRevision` 并取消旧操作和播放；失败解析在 clone 上处理，避免把源文件部分追加到旧工程。音符试听使用 GM 音源；和弦库的 GM 选择由浏览器处理，只有隐式四弦 program 24 与和弦库 Ukulele 使用特殊音源。此处记录的是源码实现和小型桥接/往返证据；真实原生 Studio 导入、保存、编辑及主播放器回放另在下方最新 `verified-final` 场景验证，不用小探针替代全格式验收。

此前完整 Studio MusicXML 路径另有一条持久化负例，保存在 `.build/runtime-audit-022/studio.musicxml.release-final.jsonl`：JavaScript 导入成功，但无作者的谱面被 PersonalStore 拒绝，因为 Web schema 要求 `artist` 非空。新修复只在共享导入桥将缺失/空作者规范为“未知作者”，保留已有署名；没有放宽 Store 校验，原生 Swift 未改。WK author 探针检查了该默认值及 JSON 往返。该探针本身不替代真实原生窗口验收；当前真实导入、持久化、编辑与主播放已有单一 fixture 场景结果，边界见下表。

## `verified-final` 当前 10 项场景（均通过）

最新场景索引 `.build/runtime-audit-022/verified-final-scenario-index.json` 中 10 项均为成功结果。MusicXML 的真实产品流程已经在该批诊断中覆盖；这项结果是完整 Native Studio UI 的样本，和前述仅 WK 的小探针分开记录。

| 场景 | 运行证据 | 边界 |
| --- | --- | --- |
| MusicXML 导入及编辑 | `minimal-audible.musicxml` 导入 4 小节、1 音轨、16 音，MIDI 序列正确；PersonalStore revision 从 1 到 39。随后真实 `enterFret` 完成 33 项编辑/12.092 s，CPU 10.210 s，50 ms 心跳 P99 89.83 ms；预览 PCM、试听后稳定、主谱 14 个非零输出块/57,344 帧和时钟前进、自动续写/快捷键、撤销/重做/保存均通过 | 该 fixture 经此路径通过，不代表所有 MusicXML 变体或完整导入兼容矩阵 |
| 空白 Guitar 工程 Studio 编辑 | 真实 `enterFret` 完成 34 项编辑/12.209 s，CPU 10.062 s，心跳 P99 88.89 ms；对应编辑、试听、播放、保存检查通过 | 单次诊断场景，不表示所有 Studio 控件和大型工程均验收 |
| 完整 Player UI | 实际挂载 Player，连续播放约 12 s，音频非零、时钟前进；谱面有 11 个 SVG，WebView/DOM 尺寸为正且无 Web 错误，心跳 P99 31.56 ms | 代表性 IBE 场景，不代表所有格式、控件、帧率或长时性能 |
| 完整 Practice UI | 实际挂载 Practice，连续播放约 12 s，音频非零、时钟前进；谱面有 11 个 SVG，正尺寸/无 Web 错误门槛通过，心跳 P99 42.05 ms | 一轮代表性练习样本；练习长时恢复、会话边界仍未覆盖 |
| 其它六条播放路径 | direct、catalog reference、private IBE、private GP5、XHE reference、audition 全部通过各自场景检查 | XHE 是文字谱加载，不记作音频播放；其余数字音频结果也不代替扬声器听感或完整格式矩阵 |

前述两条 MusicXML 负例都保留为历史：一次解析阶段 JavaScript 异常，另一次导入成功但空 `artist` 被 PersonalStore 拒绝。新源码和最新端到端样本通过这两个故障点；小探针、单一 MusicXML fixture 和十项源码诊断仍不等同于全量格式覆盖、每个 Studio 功能验收或最终发布 App 验收。

## 最终 App 资源复跑与普通启动

在 Universal 包完成后，使用同一诊断 binary、接入最终 App 资源树复跑；这一步没有改产品代码。`packaged-resources-awake-scenario-index.json` 的 7/7 场景通过：曲库最后两轮与 staging 对照一轮、完整 Player、Practice、MusicXML Studio 和 audition。MusicXML 样本确认 16 音 MIDI 序列正确，PCM 试听、主谱播放和保存均为 true。场景索引与环境上下文记录位于 `.build/runtime-audit-022/A/packaged-resources-awake-scenario-index.json` 和 `.build/runtime-audit-022/A/packaged-resources-awake-context.json`。

此前首次运行和后续 7 次复跑失败记录均保留。`pmset` 记录显示 02:37 显示器关闭、02:45 和 02:46 再次关闭，12:32 `LidOpen` 后唤醒；失败时 Studio 的 rAF 没有实际渲染。显示活跃并临时用 `caffeinate -di` 包装后，同一 binary 与资源通过所有场景。证据支持失败与当时的显示器休眠环境相关，但不构成睡眠/唤醒完整功能验收，也不能推广为其他睡眠恢复行为已通过。

普通 `-O` App 使用完整路径 `open` 启动后，PID 92852 在 12.08 s 后仍运行，记录见 `.build/runtime-audit-022/A/normal-app-startup.json`。这只是启动烟雾检查；未记录完整 GUI 交互或像素视觉结果。Apple silicon 仅有架构编译/包结构检查，没有 Apple silicon 实机启动。

## 开发入口

在项目根运行 `bash tools/build_runtime_diagnostics.sh`。程序位于 `.build/runtime-audit-022/MIMIRuntimeDiagnostics.app/Contents/MacOS/runtime_diagnostics`，接收 `--content-root`、`--player-root`、可选 `--studio-root` 与 `--case`。所有数据输出均为运行诊断结果，未新增或运行测试套件。

原始运行记录保存在项目 `.build/runtime-audit-022/`，最终证据汇总在本文件更新。`release-final-build` 对应独立 `-Osize` 诊断 App；10 项 `verified-final` 源码诊断已通过。Universal `-O` 发布构建已生成 `.app` 与 DMG，双架构、lipo、codesign、资源树、`hdiutil verify` 及 DMG 内外 App/资源逐文件比较通过；DMG 内 SQLite 完整性、曲谱/文章计数及 Applications 链接检查通过。首次卸载因诊断 Python 持有只读 SQLite 连接而返回 busy；进程退出释放后普通 detach 成功，未强制卸载，原始负例报告保留。随后使用同一诊断 binary 和最终 App 资源完成 7/7 场景：曲库最后两轮与 staging 对照、完整 Player、Practice、MusicXML Studio、audition。MusicXML 检查确认 16 音 MIDI 正确，PCM 试听、主谱播放、保存均为 true；产品代码未变。此前首次资源运行及 7 次复跑失败记录保留：pmset 记录 02:37 屏幕关闭、02:45/02:46 再次关闭，12:32 LidOpen 后唤醒；Studio 当时 rAF 未实际渲染。醒屏并用临时 `caffeinate -di` 包装后同一 binary/资源全部通过，显示结果与休眠状态相关；不据此声称完整睡眠/唤醒恢复通过。普通 `-O` App 已通过完整路径 `open` 启动，PID 92852 在 12.08 s 后仍运行，见 `A/normal-app-startup.json`；这只是启动 smoke check，不代表视觉或完整 GUI 验收。包版本为 0.2.2（202610241829）、最低 macOS 13.0，x86_64 + arm64；DMG 563,044,527 B，SHA-256 `c5ceb4af88585455777a36c1d710d7100ff1918cee577bca8ab7d6ecbc2dd8e2`。签名为 ad-hoc，未公证；未在 Apple silicon 实机运行，其他检查也不替代全曲库、听感、FPS 或全面功能验收。


## 成品资源复查、显示状态与正常启动

2026-10-25 的最终交付记录保存在 `diagnostics/0.2.2-results.json`。`packaged-resources-awake-scenario-index.json` 记录 7 次成功复查：两次最终资源曲库引用、一次 staging 对照、完整 Player、Practice、MusicXML Studio 和首页试听。直接使用成品资源的运行共 6 次，另有 1 次对照；这些运行仍使用独立 `-Osize` 诊断程序。MusicXML 原始 4 小节、16 音的 MIDI 序列、真实保存、录入、独立 PCM 试听与主谱播放均通过。

首次成品资源检查及随后 7 次复跑出现了已就绪但未播放、Studio 无实际谱面渲染的失败。电源日志显示 02:37 屏幕关闭，02:45 和 02:46 再次关闭，12:32 开盖唤醒；这些失败与显示关闭/休眠时段对应。原始失败日志、`packaged-resources-retry-scenario-index.json` 和显示观测均保留。屏幕恢复活跃后，临时用 `caffeinate -di` 包装诊断进程，相同程序与相同资源 7/7 通过。该结果支持显示休眠阻断 WebKit 渲染/播放的解释，不构成完整睡眠/恢复交互验收；未因这组结果修改产品。临时电源断言随诊断进程结束释放。

实际 Universal `-O` 应用随后通过完整路径正常启动，进程在 12.08 秒后仍存活，记录于 `normal-app-startup.json`。这是实际成品的启动检查；不等价于视觉像素、全部控件、扬声器听感或 Apple silicon 设备验收。
