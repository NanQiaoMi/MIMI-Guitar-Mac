# 交互体验后续路线图：P2 / P3

## 范围与当前证据

本文列出 P1 动效系统之后的增量。P1 设计基线见 [interaction-motion-plan.md](./interaction-motion-plan.md)，P2-A 的实现与独立复测见 [studio-interaction-polish-plan.md](./studio-interaction-polish-plan.md)。自动化、类型/构建、本地 Chromium 与减少动态效果分别记录；P2-B/C/D 和 P3 仍为后续工作，不继承已完成迭代的通过结论。

保持暖纸、墨色、发丝边框和现有谱面阅读层级。继续共用 `src/lib/ui/motion.ts` 的时长与 easing：micro 120ms、control 200ms、panel 260ms、page 280ms、exit 160ms；书卷翻页保留 folio 360ms。动作优先用 opacity/transform，减少动态效果下取消位移与缩放。页面导航、音频命令、保存/恢复提交不等待动效；所有异步结果必须有取消或代次保护。新增交互不引入依赖。

本文中的时长/人日都是**估算**，用于排期比较，不是承诺日期或完成时限。

## P2-A：工坊菜单、底部工作台与四类对话框

2026-10-17：本轮已实现；最终命令、浏览器范围和未执行门槛以[独立验收记录](studio-interaction-polish-plan.md)为准。以下源码行号与问题描述保留为 `master@888262a5` 实施前快照，不代表当前仍有这些问题。歌词未应用文本仅在本次页面内保留；当前编辑工程的删除被禁止；播放中数字录入需先暂停。后续优先进入 P2-B 备份真实进度和失败恢复。

**优先级：P2 高。依赖：P1 的 `MotionDialog`、`surfaceMotion` / `fadeMotion` 和 motion tokens 通过根代理验收。工时估算：2–4 人日。**

**范围与源码证据**

- `src/components/studio/StudioHeader.svelte:60-62,303-536`：新建和导出菜单由 `showNewMenu`、`showExportMenu` 条件渲染，只使用入场 `animate-fade-in`；触发器只有 click toggle，没有 `aria-expanded` / `aria-controls`。多个菜单项会先关菜单再执行新建、保存或导出动作。
- `src/components/studio/ScoreStudioApp.svelte:72-77,119-133,352-385,881-1006`：底部抽屉及四种弹层分别使用布尔状态；草稿保存有 `persistenceRevision` 保护异步提示；编辑快捷键由 `ScoreCanvas` 接收。底部工作台 footer 使用 `transition-all duration-200`，内容以 `{#if !isBottomDrawerCollapsed}` 直接增删，折叠按钮没有明确展开语义，两个 tab 也没有 tab 语义。
- `src/components/studio/LyricsDrawer.svelte:7-93`：歌词文本保存在组件状态，关闭再打开会保留输入；初始值只在文本为空时从当前选中音轨采集。清空歌词会直接更新工程但留在弹层；“智能对齐”同步更新工程后关闭。自定义遮罩没有 Escape、焦点圈定或标题关联。
- `src/components/studio/ShortcutHelpModal.svelte:24-43`：自有 window Escape 监听器；遮罩有 `role=dialog` / `aria-modal`，没有 `aria-labelledby` 和可见焦点管理。快捷键清单含删除、播放与保存等编辑操作。
- `src/components/studio/StudioGuide.svelte:42-60`：自有 window Escape、遮罩点击关闭，已有标题关联和内部滚动；没有焦点圈定/恢复。
- `src/components/studio/DraftsModal.svelte:19-91`：打开即异步读取草稿，没有请求代次；读取结束可能覆盖关闭/重开的新状态。载入、删除、导入异步并共享一条 `importError`；只在导入期间禁用文件选择，载入/删除/关闭仍可触发。遮罩和面板未声明 dialog 语义；列表行在窄屏仍横向放置。

**最小增量**

1. 给新建/导出菜单加展开状态、控制面板关联、外点和 Escape 关闭；Escape 把焦点还给仍存在的触发器。菜单项命令立即执行，动画只负责呈现，不延迟保存、导入、导出或新建。
2. 底部抽屉补 `aria-expanded` / `aria-controls`；工作台/调音台切换表达为单选 tab 或有清楚选中语义的按钮组。用现有状态驱动可反转的局部入退，不对和弦盘、整块指板或乐谱做高度动画。抽屉收起时内容不得留在 Tab 顺序中；切 tab 与展开保持当前项目、光标和音轨状态。
3. 四种弹层统一接入 P1 `MotionDialog` 的原生 modal、焦点初始位置/恢复、滚动锁、Escape、关闭期间的遮罩隔离与减少动态处理。给四者稳定的标题关联；以父组件单一 `activeStudioDialog` 或等效门控保证一次只开放一个 modal。删除各弹层重复的 Escape 监听，避免一次按键关闭两层。保留关闭和重开的原状态反转，不用 setTimeout 等待业务动作。
4. 歌词弹层把“放弃输入”“清除已有歌词”“应用对齐”保持为不同操作。用户修改后的文本作为本地草稿保留到显式应用或显式清除；如果当前工程/音轨在弹层打开期间切换，提示将要应用到的目标，不能静默拿旧音轨或用新工程覆盖文本。没有可用音轨、空文本或无可对齐音符时禁用/说明应用原因。
5. 草稿弹层为读取、每行载入/删除和导入建立独立忙碌/错误状态及请求代次；关闭后完成的只读刷新不得写回已关闭或新会话。对会替换当前工程的载入/导入明确展示忙碌状态并锁住冲突操作；无法真实取消的提交阶段明确保持打开或拒绝关闭，不能显示已取消。载入成功继续沿用当前 `stopPlay`、版本记忆、应用工程和光标复位顺序；打开/关闭列表本身不暂停音频。删除失败保留当前行并提供可重试反馈。对重复 click 做幂等保护。
6. 工坊键盘快捷键只在编辑画布拥有焦点且没有 modal 时生效；打开帮助文档时空格不应启动/暂停谱面、Delete 不应删除音符，输入文本时 Ctrl+S 等按键也不误触背景编辑。别丢弃已有的待录品位数字或让它在弹层关闭后写入错误节拍。

**焦点、草稿、音频、异步、反转、禁用与窄屏边界**

- 菜单/抽屉焦点只移动到可见控件；折叠后先把焦点归到抽屉触发器，已隐藏内容设为 inert 或等价不可聚焦。
- 关闭 Lyrics / Shortcuts / Drafts / Guide 时恢复原触发器焦点；若触发器已卸载，使用调用方可提供的合理局部 fallback，而不在通用 dialog 写站点 selector。
- 纯说明/输入弹层开关不暂停 Studio 音频；草稿应用/导入只能在原有项目提交边界明确停播，失败时不留下半应用工程或失效音频焦点。
- 关闭中立即重开时，原节点从当前位置反转；异步列表结果只提交给当前代次。退出完成后无残留遮罩、滚动锁、document/window listener 或隐藏焦点。
- 导入期间文件选择禁用；载入/删除分别禁用冲突行按钮；没有音轨、草稿为空、数据读取失败及工程保存失败均有明确状态，不能把错误当空列表。
- 320 CSS px、放大字号和虚拟键盘下弹层有界高度及内部滚动；歌词 textarea、按钮和菜单选项不被遮挡；Footer 和草稿行换行，不产生横向滚动。主要触摸目标以至少 44 CSS px 为目标；键盘/读屏仍可达。

**验收用例（具体结果见本轮记录）**

- 对新建/导出菜单连续开关、点外部、Escape、Shift+Tab；验证命令执行一次、焦点回到触发器、没有重叠菜单。
- 底部抽屉/两个面板快速反转与反复切 tab；折叠后 Tab 不会进入隐藏指板，展开前后的工程/光标/播放 tick 一致。
- 对四个 modal 分别验证初始/返回焦点、Tab/Shift+Tab、Escape、关闭期间重开、reduce 动态偏好切换；检查 body 滚动锁及 listeners 在连续 20 次开关后清零。
- Lyrics 输入后取消、重新打开、切换音轨、清空后取消、保存后撤销；确认只有明确的应用/清除命令改变工程，重复提交不会覆盖新版本。
- Drafts 打开后迅速关闭重开并模拟列表读取延迟；执行载入/导入/删除时重复点击或让请求失败；确认当前工程、草稿和播放状态只按既定提交动作改变、错误可恢复。
- 320×740、390×844 和 768×1024 下检查表单、列表、按钮、软键盘滚动与横向溢出。

## P2-B：备份真实进度与失败恢复

**优先级：P2 高（个人数据保护）。依赖：当前备份预算、版本校验、恢复 staging/CAS 契约；变更 callback 时对 `backupVolumes.ts` 做有意义的契约测试。工时估算：2–4 人日。**

**范围与源码证据**

- `src/components/PersonalDataSettings.svelte:86-108`：单文件备份先构造完整 Blob，然后创建下载链接；消息明确只表示下载已发起并要求用户确认文件落到设备。
- `src/components/PersonalDataSettings.svelte:144-207`：v2 备份目前可显示清单校验、准备第 N 卷、已准备与用户发起下载等阶段；`AbortController` 可取消准备，已经发起的下载无法撤回。UI 通过 `initiatedVolumes` 记录发起，不代表浏览器已保存。
- `src/components/PersonalDataSettings.svelte:210-292` 与 `src/lib/personal/backupVolumes.ts`：恢复已有按卷校验 callback、`expectedRevision`、临时 staging、取消预览和失败清理提示；若清理不确定会保留预览并告知重新进入页面清理。

**最小增量**

1. 把“正在校验”“扫描/哈希附件”“分卷打包”“已准备可下载”“下载请求已发起”“已由用户确认文件可见”“恢复校验”“恢复提交”区分成状态阶段。向备份 helper 增加可取消、基于实际完成 bytes/asset/chunk/volume 的 progress callback；只有总量已由 metadata 确认时才展示有分母的进度，不用 timer 或 CSS 伪造百分比。避免每个小 chunk 频繁渲染，按实际批次合并状态更新。
2. UI 明确网页只能发起浏览器下载，无法观测最终写入文件系统。将 `initiatedVolumes` 标成“下载已发起”；允许用户重新发起单个文件并手动确认下载列表可见，不宣称确认来自应用。缺清单/卷、文件名或校验不符时给出具体缺项；不把部分分卷叫作完整备份。
3. 失败时将准备、用户下载、预览校验、恢复提交分成独立阶段。可恢复的读取错误保留可重试输入；源 revision 变化或内容摘要失败使旧计划/预览失效并要求重建；取消/离页调用已有 AbortController、取消方法和 staging 清理。清理未确认时保留诊断上下文及明确重试入口，不隐藏错误或清除用户仍需的卷文件选择。
4. 用 `role=status` / `aria-live=polite` 报告阶段和确切数量；只把失败/阻止完整备份的错误用 assertive alert。busy/无效数据时禁用会破坏当前计划的按钮，但允许安全离开/停止；明确“当前资料尚未变更”直到恢复提交成功。沿用既有预算与迁移 fail-closed gate。

**焦点、草稿、音频、异步、反转、禁用与窄屏边界**

- 备份进度不夺焦点；动态状态不连续播报每个 hash。键盘焦点在取消/重试后留在对应按钮或明确状态标题。
- 不改个人草稿、原件和恢复前数据；先检查摘要、预算与 revision，最后才合并。单文件和分卷恢复失败保持现有数据不变。待清理 staging 未确认时不假报成功。
- 数据设置页不控制乐谱播放；离页中止处理释放 controller、helper plan、Object URL 和订阅。已发起浏览器下载不会因页面动画/取消提示被误报为撤回。
- 连续点取消/重试、关闭页面后 resolve 的请求通过 operation identity/generation 检查，不允许旧回调把新操作标成完成；动作即时开始，不等待 120–280ms 的呈现动画。
- 无可引用附件时仍能完成只含 manifest 的流程；迁移不完整、超预算、缺卷、损坏卷、revision 过期、浏览器下载拒绝和清理失败均保留明确禁用/恢复路径。
- 320 CSS px 下文件名、卷计数、进度/错误和控件纵向换行，信息完整且不靠颜色/动画表达；高缩放可滚动到“取消 / 重试 / 恢复”按钮。

**验收用例（后续）**

- 使用 0 附件、1 附件、多卷附件验证报告阶段、已处理 bytes/卷数与 helper 回调真实值一致；准备不同阶段中止并重试。
- 手动取消浏览器下载或拒绝下载权限，确认界面仍只说“已发起”，用户能重新下载单卷；少一卷/错一卷时完整恢复按钮不可用。
- 在校验中修改源 revision、制造哈希错误、文件截断、存储读取失败及 staging 清理失败；确认没有半提交，提示能区分“旧预览保留”“重建计划”“重开页面重试清理”。
- 逐卷恢复成功后核对摘要、实体计数、附件引用和恢复前数据；失败路径核对当前资料 revision 不变。
- 连续取消、关闭/离页并快速重进，确认没有旧进度更新、悬挂监听、Blob URL 或 staging 被静默丢弃。

## P2-C：播放器 capo 与全屏设置

**优先级：P2 高（会改音频与播放位置）。依赖：现有 render chain、MIDI reload、恢复播放位置流程；不另引入播放器动效控制器。工时估算：1–2 人日。**

**范围与源码证据**

- `src/components/player/ScorePlayer.svelte:296-332`：全屏先同步切 CSS 状态，再尝试原生 Fullscreen API，iOS 等不支持时静默降级；`fullscreenchange` 和 document Escape 在 `$effect` 内注册并清理。当前 Escape 在设置面板打开时也直接退出全屏。
- `src/components/player/ScorePlayer.svelte:1629-1745`：`withRenderPreservingPosition` 保存 tick/播放状态，暂停、渲染、必要时重新加载 MIDI、恢复 tick/续播，并在失败时提示/尝试恢复播放。`selectCapo()` 经过该路径；普通工具栏的 capo 选项也调用它。
- `src/components/player/ScorePlayer.svelte:2113-2140,2487-2559`：工具栏菜单有 `aria-expanded`；全屏设置开关未关联面板/展开状态。全屏面板的 capo 按钮当前直接赋值 `capoMode = n`，绕过 `selectCapo()` 和 MIDI reload。capo/转调触点只有 24×24 CSS px，选中模式没有 `aria-pressed`。

**最小增量**

1. 全屏 capo 选择统一调用 `selectCapo(n)`；选择/转调渲染时在当前事务内禁用重复调性命令并通过可见状态说明等待。遵守既有串行 render/MIDI 更新，失败遵循 rollback/render notice，不单独做分数或播放器变形。
2. 全屏设置触发器补 `aria-expanded` / `aria-controls`，选择控件补 `aria-pressed` 或合适 radio/listbox 语义及可见焦点。Esc 优先关闭设置并返回设置触发器；设置已关闭时下一次 Esc 才退出全屏。原生 fullscreenchange、用户手势退出和 CSS fallback 仍同步。
3. 设置面板以 200–260ms 局部 opacity/轻微位移进退，状态变化即时；快速开/关反转当前过渡。不要动画谱页高度、音符光标或播放进度，也不要为 panel 开关 pause/resume 音频。

**焦点、草稿、音频、异步、反转、禁用与窄屏边界**

- 设置打开/关闭时焦点进入面板并回到仍存在的设置按钮；Esc 关闭内层设置的顺序优先级不能被全屏退出监听抢占。用户从系统退出原生全屏时，焦点回落到正常页面的播放器入口。
- capo/transpose 动作是用户设置，不应被打开/关闭设置面板覆盖；当前播放位置与暂停/播放状态由原 `withRenderPreservingPosition` 负责。异步 render/MIDI 加载失败后保留可恢复状态和错误提示，不显示未应用的选中值。
- 变调或打开全屏本身不清草稿、不切换谱面、不额外请求音源；全屏设置隐藏时不可聚焦。无 score/loading/transposition pending 的情况明确禁用相关设置。
- `requestFullscreen()` 拒绝、Safari CSS fallback、系统手势退出、快速重复开关、render 队列等待和组件卸载均清理 body lock 与 `fullscreenchange` / `keydown` listener；效果完成时面板状态与真实全屏状态一致。
- 320 CSS px 与横屏短视口中面板有界滚动、控件换行，不盖住退出按钮/播放控制；小于 44px 的 capo/transpose 触点需扩大命中区，面板不能挤出视口或遮挡谱面操作。

**验收用例（后续）**

- 播放期间在工具栏与全屏面板更换 capo；比较前后 tick、正确 MIDI、是否连续播放和 audio focus 次数。
- 快速连续选择 capo、同时转调、模拟 MIDI load timeout/render error；确认不会并发调用 AlphaTab，不留在假成功数值，能恢复/报告失败。
- 原生 fullscreen 成功、API 拒绝、系统手势退出分别验证 CSS 锁、设置状态、Escape 两级关闭和焦点归还。
- 连续开关面板并卸载播放器，检查动画能反转、body class/监听器恢复、页面控制可以再次聚焦。
- 320×740 竖屏、横屏短视口、键盘和屏幕阅读器检查控制可见、选中态可辨、触控命中区与谱面滚动。

## P2-D：曲库筛选、结果与分页反馈

**优先级：P2 中。依赖：P1 跨文档导航决策；先维持 Astro 多文档与 query string 契约，不启用新的客户端路由。工时估算：1–3 人日。**

**范围与源码证据**

- `src/components/TabCardGrid.svelte:334-379,418-629`：`filteredTabs` 明确等于服务器返回 `tabs`，筛选和排序通过 `window.location.assign()` 完整导航并重置页码；不会在客户端重算全集。分页用 query string 构造地址。
- `src/components/TabCardGrid.svelte:657-676`：画廊结果当前 `animate:flip` 300ms，进入 `fly` 350ms，index 阶梯延迟最高 400ms，退出淡出 150ms；与统一 120–280ms 页面级预算不一致。另有卡片指针倾斜/hover 300ms 反馈。
- `src/components/TabCardGrid.svelte:1049-1109`：无结果/曲库不可用已有不同说明；分页是真实链接。页面还可播放卡片“即时吉他原声微试听”，所以离页不能等待动效完成。
- `src/pages/tabs/index.astro`、`src/pages/ukulele/index.astro`：过滤结果由 `queryTabs(params)` 服务端取页，再传 `TabCardGrid`；`src/pages/searchResults.astro:80-243` 用查询参数表达搜索、分类、筛选、排序与分页；`src/components/FilterBar.astro` 是另一个保持原生 anchor/form 语义的静态筛选器。

**最小增量**

1. 筛选/排序选中态用 control 200ms，结果初次呈现最多 page 280ms；降低或移除 350ms 入场和 400ms 阶梯排队。列表 FLIP 仅用于同一批仍在页面的稳定键项目，禁止把服务端重排伪装为本地实时筛选。保留 folio 页面专属 360ms 翻页，不套到普通结果更新。
2. 不延迟 `window.location.assign`、form submit、分页链接、修饰键新标签、下载和浏览器后退/前进；不引入额外 ClientRouter。所有筛选继续保留 query/hash/history 现有约定，空结果、demo 与 unavailable 的内容及语义不被过渡层隐藏。
3. 把选中状态暴露为 `aria-pressed` / `aria-current`，把结果数量和加载/新页标题作为短暂 polite status。触发筛选后焦点按原生页面导航规则落在新页面，不跨页保存虚假的焦点索引。搜索输入按 Enter 原样提交。
4. 若导航开始时卡片原声试听正在播，只做必要的试听停止/代次失效和现有 timer/audio cleanup；不得为“播完动效”延迟离页，也不得在返回后自动重新发声。减少动态时不启动列表位移/卡片 3D 倾斜动画。

**焦点、草稿、音频、异步、反转、禁用与窄屏边界**

- 筛选是原生链接/表单：维持 Tab、Enter、浏览器返回语义；选项目标扩到适合触摸的命中区。服务端加载中不伪装可点的幽灵结果。
- URL 是筛选和搜索的持久状态；导航不得丢关键词、category、sort、filter、page 规则、原生 hash 或用户文本。无需在离页动画层另存一份易过期草稿。
- 同一列表内切显示模式不暂停试听；筛选导航真实离页时清除/失效试听定时器且不重放。动作不得等待过渡；结果旧页快速导航时不得由旧文档延迟回调覆盖新状态。
- 无结果、曲库 `unavailable`、`demo`、页码超界及禁用条件均保持可理解的正文和恢复筛选入口；error 不与 empty 共用一个状态动画。
- 320 CSS px 下分类、视图切换、难度/谱型、搜索和排序可换行或分组，不出现水平溢出；筛选结果卡片保留标题、艺人和打开谱面链接可见，按钮至少 44px 目标。
- `prefers-reduced-motion` 改变时，运行中列表运动可立即落到目标；用户重复点筛选/分页时继续使用真实导航，不叠加转场队列。

**验收用例（后续）**

- guitar/ukulele/searchResults 中分别筛选、排序、重置、分页；复制 URL 后重载、后退/前进、新标签打开，验证参数和服务端结果对应。
- 开启 reduce 后筛选/排序/分页；检查无 fly/flip 位移，选中状态及结果信息仍立即更新。
- 空数据、demo、unavailable 与有结果路径分别检查可访问状态和恢复入口；快速多次导航不得让旧结果闪回。
- 正播放卡片试听时筛选离页并立刻后退，确认无延时跳转、旧 chord timeout 或自动续播；当前无浏览器结果不得被静态测试替代。
- 320 CSS px、200% 缩放检查所有筛选、状态、结果卡与分页键盘可达且无横向滚动。

## P3：设备、辅助技术与长时性能验收

**优先级：P3，依赖 P2 各模块合并到候选版本且桌面测试稳定。工时估算：每轮设备矩阵 2–5 人日，取决于可用设备与辅助技术环境。**

**覆盖范围**：上述 Studio 菜单/抽屉/四弹层、个人数据备份状态、播放器全屏和 capo、曲库筛选/结果及 `src/lib/ui/motion.ts` 共用生命周期。先做桌面键盘/屏幕阅读器和桌面浏览器，再做 iOS/iPad Safari、Android Chrome 真机、触摸、设备旋转、虚拟键盘、系统全屏手势、200% 缩放/大字号与低性能设备。按 P1 矩阵观察 320×740、390×844、768×1024、1024×768、1366×900；采集真机性能/电量样本，不从静态帧率推断。播放稳定性依 P1 原计划分别记录桌面 2 小时、移动端 30 分钟实际运行，不用构建/单测替代。

**验收边界**：检查 reduce 动态运行时变更、页面隐藏/恢复、全屏退出、取消慢任务和反复开关后的焦点、body lock、MediaQuery/document listener、timer、Object URL、临时恢复 staging、音频位置/音频焦点。每种真机/辅助技术写清型号、操作系统/浏览器、缩放和结果；缺设备写“未执行”。P3 的辅助技术、真机和长时验收尚未执行；P1 本地 Chromium 的已验收范围见 [本轮记录](interaction-motion-plan.md)，不能外推为 P2/P3 通过。

## 建议依赖顺序

1. 根代理完成 P1 类型/build 与实际浏览器验收，并确认 `MotionDialog`、`surfaceMotion` 的稳定接口。
2. 先完成 P2-A 的 modal/菜单生命周期和 P2-B 的备份阶段契约；二者可独立开发，但各自改动由各自 owner 验收。
3. P2-C 在音频回归确认后交付；P2-D 保持原生导航与 query 契约，再收敛长时长列表动画和窄屏布局。
4. 全部 P2 增量走桌面辅助技术/减少动态验收后，进入 P3 设备矩阵与实际长时播放观测。

每个阶段都单独记录自动化、类型/构建、浏览器、辅助技术与真机证据；没有执行的场景标“未执行”，不能以文档计划或源码静态审查代替运行时结论。
