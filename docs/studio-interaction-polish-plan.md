# 制谱工坊交互与可靠性优化计划（2026-10-17）

## 1. 基线、目标和范围

从已验收 master `888262a5` 创建 `feature/studio-interaction-polish`，复用隔离实现工作树。原 `D:\MIMIguitarweb` 仍在 `feature/complete-score-studio`，不清理、不切换；本轮重新记录并核对 1024 文件 SHA-256 和 402 行 `git status --short`。实现工作树的依赖联接已改到独立依赖副本，避免类型生成或构建刷新原目录缓存。

执行既定 [P2-A 路线图](interaction-experience-roadmap.md)：把日常制谱中反复使用的菜单、四类弹层、工作台切换和键盘编辑做成一致流程。保留暖纸视觉、现有数据格式、备份/CAS 规则和音频引擎。本轮不修改数据库 schema、账号同步、公开投稿、播放器 capo/全屏或备份分卷协议；后两项继续作为独立增量。

当前源码证据：Header 两个菜单直接条件渲染，缺少完整焦点边界；四弹层各自实现遮罩，其中部分有独立全局 Escape；Drafts 异步读取没有代次，载入/导入/删除共享错误且可互相重入；Lyrics 只有单份文本，不按工程/音轨隔离；ScoreCanvas 在 window 上接收编辑键，未要求画布拥有焦点；父级延迟品位输入可能在打开工具后落到新上下文。功能和生命周期先正确，动画只负责反馈。

## 2. 动效与可访问性约束

- 复用 P1 `motion.ts` 和 `MotionDialog`，菜单 200ms、弹层 260ms，可从当前进度反转；正文入场短距离、不做大谱面变形。减少动态效果取消空间位移，运行中切换也必须落定。
- 不新增动画依赖、常驻 RAF、`transition: all` 或业务等待定时器。现有双位品位输入定时器属于输入协议，必须有上下文与清理保护。
- 原生 dialog 拥有焦点范围、Escape 与滚动锁。各业务弹层保持挂载，以 `isOpen` 控制，不在父级用外层条件立即销毁 outro。初始焦点有明确目标；关闭回到可见触发器，必要时使用调用方提供的局部 fallback。
- 主要按钮/菜单操作 ≥44 CSS px；短动态视口有界面板、独立滚动，320px 下操作行与文件名换行。禁用必须有原因，错误与空列表分开表达。

## 3. 交付增量与状态边界

### A. 新建、保存/导出菜单

两个菜单互斥，触发器补稳定 ID、`aria-expanded` / `aria-controls`。普通按钮/链接语义，不添加半套 ARIA menu。外点、焦点移出、Escape 收起；Escape 归还触发器。退出时外层立即 inert，保留动画节点供反转。命令立即执行，不能等 outro 才保存/导出；忙碌时避免重复触发，错误继续走现有父级反馈。

打开四类弹层的按钮提供可恢复焦点的稳定标识。菜单和说明开关本身不重建 AlphaTab、不开始或停止音频。项目替换仍在明确提交边界停播。

### B. 歌词、快捷键、指南

三者接入公共 MotionDialog，去掉各自的 Escape/遮罩实现；标题、说明、关闭、初始焦点明确，内容可滚动。父级以单个 `activeStudioDialog` 决定四类弹层开关，避免多个业务 modal 同时处于 open 状态。

歌词草稿按工程 ID + 音轨 ID 保留；关闭只收起输入，不静默提交。切换工程/音轨后不得把旧输入应用到新目标；重新载入当前歌词必须是明确操作。目标变化或结构/歌词冲突时保留文本并说明原因，不静默覆盖。对齐只使用有音符的非休止拍；显示字词/可用位置数量，没有可用位置或有效字词时禁用。处理剩余旧歌词，避免缩短输入后旧尾部残留；超出容量不能静默截断。清空当前音轨已写入歌词与取消文本是不同命令，工程变更继续走父级撤销/保存路径。

### C. 草稿箱异步操作

把读取、行载入、导入、删除、错误分别表达。打开/关闭/重开拥有 generation 或操作身份；旧列表结果不得覆写新会话，不把读取失败显示为“没有草稿”。列表读取可安全退出并忽略迟到结果；真正替换/导入/删除提交期间锁住冲突操作和关闭请求，明确状态，不能假报取消。

父级提供保存结算边界：载入/导入/删除之前先结算当前页面已发起保存，失败时保留当前工程并说明备份/重试路径。载入回调支持同步或异步结果并等待，不在父级拒绝时仍关闭。导入保持“解析、校验及原件/工程保存成功后再替换当前工程”的现有顺序；成功替换时停播、取消待录品位、重置光标。读取载入本身不额外把旧快照再保存回去。删除有明确确认与错误提示，关联练习谱的删除拒绝继续由现有持久层保证；本轮不设计墓碑或清空资料。

### D. 画布键盘与底部工作台

ScoreCanvas 增加 `keyboardEnabled` 及编辑边界通知；只有画布/其非交互内容拥有焦点且无 modal、未初始化/导入忙碌时才接收编辑快捷键。输入框、按钮、链接、菜单、可编辑文字、组合输入和已处理事件不冒泡到背景编辑。画布有可见键盘焦点；普通 Tab 用于焦点移动，不劫持所有页面 Tab。现有编辑命令继续通过父级执行。

父级在打开工具、离开画布、切光标/音轨/工程、播放与卸载时结算或取消待录数字。合法的单数字在原上下文结算，两位品位和 24 品上限保持；过期定时器不能写入新工程/拍位，不因为收起弹层把数字带入之后的编辑。

底部工作台补展开/控制区域语义；两种视图复用单选分段控件。折叠/切换只改变局部呈现，隐藏内容退出时 inert，不重建上方 ScoreCanvas。退出内容前焦点落到可见触发器，保留当前工程、光标、音轨和播放位置。取消 footer 的全属性过渡，不动画谱面高度。

## 4. 文件所有权与共享契约

全部子代理使用 `gpt-6-luna / max`，先审查再实施，不操作 Git、服务、安装依赖或浏览器，不改其他 owner 文件。

| Owner | 独占文件 |
| --- | --- |
| Dialogs 代理 | `LyricsDrawer.svelte`、`ShortcutHelpModal.svelte`、`StudioGuide.svelte`，必要歌词纯 helper 与测试 |
| Drafts 代理 | `DraftsModal.svelte`，必要异步操作纯控制器及测试；不改存储协议 |
| Header 代理 | `StudioHeader.svelte`、`ScoreCanvas.svelte`，必要键盘范围 helper 及测试 |
| 主代理 | `ScoreStudioApp.svelte`、必要待录输入/保存结算控制器及测试、计划/证据/索引、集成/Git/实际浏览器 |

现有四组件 `isOpen` / `onClose` 保留。业务弹层可新增 `fallbackFocusSelector?: string`；默认不硬编码站点 selector。Drafts 的载入回调允许 `void | boolean | Promise<void | boolean>`，以 `false` 或 throw 表示没有替换；可增加 `beforeLoad?: () => Promise<void>`，由父级等待已发起保存。ScoreCanvas 使用 `keyboardEnabled?: boolean` 和 `onKeyboardBoundary?: () => void`；回调应在焦点退出/指针切位前同步通知，父级拥有待录输入。最终接口在实施前由主代理与对应 owner 确认。

审查后冻结：歌词使用父级单调 `studioRevision`（不把保存提示代次当版本）和 `StudioLyricsCommand`，包含 `kind: align | clear`、`projectId`、`trackId`、`expectedRevision`、可选文本；父级在当前项目上同步检查版本再原子应用，失败抛出/拒绝且保留输入。三个说明/输入弹层和草稿箱均接收 `fallbackFocusSelector`，调用方指定 `#studio-main`。草稿导入保持 `Promise<boolean>`：true 仅表示原件/工程已存储且当前工程已替换，false 表示未替换；载入支持等待并识别 false。草稿箱读取使用无版本表副作用的列表快照，确认当前操作有效后才由父级记忆工程版本；不调用会提前记忆版本的过期载入。键盘/菜单触点使用显式 `44px`，不依赖根字号变化后的 rem 换算；不添加只检查源码字符串的测试。

## 5. 实施与验收顺序

1. 新建分支与本计划提交；冻结接口，代理按互不重叠所有权并行。
2. 父级统一 modal/保存结算/待录品位与工作台；代理提交文件到共享工作树，根代理逐项复核。
3. 运行有意义的歌词目标、容量/残留、过期异步结果、防重入、键盘范围和待录定时器测试；再跑全套单测、类型检查、构建。构建与类型生成串行，均使用原目录之外的依赖。
4. 独立 loopback 预览，不接生产数据库。使用自制工程和独立浏览器资料，验证实际状态、键盘、尺寸和播放器连续性；截图与有限运行时观察不能外推持续帧率。
5. 修复发现的问题后提交；干净 master `git merge --no-ff`；实际 master 回归；复核原树保护、文档链接、两工作树 clean。无推送、PR 或部署。

## 6. 验证矩阵和边界

| 场景 | 必须观察的结果 |
| --- | --- |
| 两菜单连续开关/反向/Escape/外点/Tab | 只显示一套菜单；命令一次；关闭内容不可聚焦；触发器可恢复 |
| 四类弹层各自开关、Tab/Shift+Tab/Escape、reduce | 原生 modal 边界、初始/返回焦点正确；退出后无锁/遮罩；无背景编辑或误播放 |
| 歌词输入→关闭→重开；换轨/换工程；缩短/空白/溢出 | 文本按目标保留；不覆盖错音轨；不残留旧尾词、不静默丢字；撤销仍有效 |
| 草稿列表延迟/关闭重开/失败/重试 | 旧代次被忽略；空/忙/错分开；失败可恢复 |
| 载入/导入/删除重复与失败 | 仅一次提交；忙碌不可假取消；当前工程/原件不半替换；失败保留信息 |
| 画布数字/两位/箭头/空格/撤销，弹层和输入框内同键 | 只有明确编辑焦点执行；待录数字不跨拍位或工程；普通 Tab 可离开 |
| 工作台快速折叠/展开/切调音台；播放中打开说明 | 光标和工程不跳变；工具开关不额外 pause/restart；无隐藏焦点 |
| 320×740、390×844、768×1024、1024×768、1366×900 | 关键新触点 44px；弹层可滚动、无新增横向溢出；工程画布自己的谱面横滚单独评估 |
| 实际用户数据与设备 | 原源码/状态保护零差异；没有设备不写真机、触摸/虚拟键盘、读屏、声音或长期稳定通过 |

本轮单测基线实际为 285 total / 278 pass / 7 DB skip / 0 fail（exit 0）。有界 Docker 查询 8 秒超时，数据库不可用状态与代码检查分开记录；不反复启动/重启用户 Docker，也不把上轮数据库结果当本轮通过。涉及可恢复性和销毁的低层测试使用隔离数据；浏览器对删除确认至少验证取消路径，不操作原用户草稿。

真实 Safari/iOS/Android、读屏、虚拟键盘、两小时桌面/三十分钟移动、持续帧率、电量和大容量恢复仍是后续门槛。工坊并不因本轮 UI 完善而成为已验收的公开发布系统。

## 7. 实现、偏差与交付记录

实施前计划已落盘；最终文件、命令/退出码、浏览器证据、未执行项、提交与 master 回归在本节增补。

### 7.1 实现与接口

- Header 使用互斥 disclosure、稳定触发器、外点/焦点离开/Escape 关闭、命令执行时归还焦点；移动宽度保留歌词/调音台入口。菜单边界放在永久容器，过渡内容退出时立即 inert。底部工作台使用 `MotionSegmentedControl` 和独立入退面板，删除 footer 的全属性过渡；画布保持挂载。
- 四弹层复用原生 `MotionDialog`。歌词、快捷键和指南以标题作为初始焦点，草稿箱初始聚焦关闭按钮；这是实施时的焦点选择，避免打开手机歌词窗口就强制弹出虚拟键盘，虚拟键盘真机效果仍未执行。对话框有有界高度、内部滚动和 44px 操作区。
- 歌词新增 `studioLyrics.ts` 的版本受控原子命令；项目 ID、音轨 ID、`studioRevision` 均校验，短文本清理旧尾词，休止/无音符拍不占用位置，超容量拒绝提交。未应用文本只是页面内按目标暂存，界面明确刷新/离页会丢失；应用并保存成功后才随工程备份，没有另造未验证的数据协议。
- 草稿箱新增 `DraftsAsyncController` 和 `loadDraftAfterBoundary`。只读列表可安全关闭；真正载入、导入、删除期间锁住冲突动作和关闭，失败保留行/文件并提供重试。先结算已发起保存，再读取新鲜快照，最后才记忆版本并采纳；载入不把旧快照额外保存回去。
- 父级新增 `studioSaveBoundary.ts`，保存失败阻止工程替换，成功重试后可继续；新增 `studioFretInput.ts`，取消后仍迟到的定时器及过期上下文不能写入新拍位。画布显式拥有编辑焦点，Tab 仍用于页面焦点导航。播放中数字录入明确要求先暂停，避免 320ms 延迟输入跨播放拍位而丢失；说明窗口/工作台切换保持播放。
- 当前工程不能在草稿箱删除，按钮禁用、可见原因和父级 guard 同时存在。否则持久层仍记忆旧版本，删除后继续编辑会持续触发 CAS 冲突；本轮未修改 CAS 或设计删除墓碑。

### 7.2 检查与审查记录

三个 `gpt-6-luna / max` 子代理按第 4 节独占实现，并交叉只读复核；主代理整合父级、补输入/保存边界测试、运行浏览器和 Git 收口。审查修复了读取快照早于保存结算、当前工程删除后无法保存、播放中的延迟数字输入、两个类型收窄错误，以及 44px 命中区缺口。

新增 21 项有意义的领域测试：草稿会话/请求代次、提交互斥、关闭/销毁、结算后读取/拒绝后不采纳 7 项；品位上下文/迟到定时器/24 品/重入和保存队列结算 7 项；歌词目标/版本/容量/尾词/其他音轨保护 5 项；键盘范围、交互目标、IME/defaultPrevented/Tab 2 项。全套实际 `npm test` 为 306 total / 299 pass / 7 DB skip / 0 fail，exit 0。数据库仍不可用，不沿用之前迭代的 DB 通过结果。

生产构建与 TypeScript → Astro → Svelte 检查串行执行；已修复后的 `npm run build` exit 0，`npm run typecheck` exit 0、0 errors，58 Svelte warnings / 19 files、44 Astro hints，与本轮基线一致。AlphaTab 大 chunk 提示仍存在，不把压缩体积当性能验收。项目没有单独 lint/formatter 脚本；另执行 `git diff --check`。最后运行与实际 master 回归另在交付段列出。

### 7.3 浏览器证据和限制

使用隔离 loopback `http://127.0.0.1:4336/studio`，从本工作树的生产 `dist` 启动；不连接生产数据库。通过真实文件选择器导入[自制双轨工程](evidence/studio-interactions-2026-10-17/self-authored-studio.json)，未写入原用户资料。通过真实导出菜单下载并核对[工程 JSON](evidence/studio-interactions-2026-10-17/verified-project-export.json)：第一轨前两拍为 1、12 品；歌词只剩“慢”“弹”，其余旧尾词为空；第二轨两处“原词”均保留。

已观察的流程包括：超容量禁止应用；关闭重开保留输入；清空已写入歌词保留文本；两个音轨隔离；新工程不带入旧输入、返回旧工程保留原输入并检查版本冲突；显式重载；菜单互斥/Escape；Tab 离开画布；损坏 JSON 导入失败后保留当前工程和所选文件；删除确认取消与当前工程删除禁用。异步迟到/提交防重入等确定性场景由 deferred 单测覆盖，实际浏览器不伪造存储或网络故障。

四弹层各连续开关 20 次，关闭后 native dialog 数为 0、body overflow 恢复、焦点回到触发器。此观察支持已覆盖的 UI 生命周期；没有做堆快照或全局 listener 精确计数，不能据此声称完全没有内存泄漏。实际播放中开关歌词/快捷键/指南、切换及收起工作台，播放按钮保持暂停符号、可见拍位从第一小节继续前进到第二小节；仅验证 UI 播放状态与进度，不宣称实际声音或长时稳定。

尺寸覆盖四弹层 × 320×740、390×844、768×1024、1024×768、1366×900，共 20 组；另验证 390×400 短视口的独立滚动和操作区。首轮发现指南底部约 4px 超界，已修正高度预算，并在最终构建下重测 20 组无超界、无页面横向溢出、没有低于 44px 的弹层按钮。进一步从 320px 手机入口直接打开四类弹层，修复原响应式隐藏歌词/调音台按钮；新建/导出菜单两侧为 x≈29.8 / 275，页面宽 305，关闭后永久边界 `inert` 存在且 `aria-hidden=true`，Escape 返回导出触发器。

普通入场采样可见 `matrix(0.992745, 0, 0, 0.992745, 0, 5.80396)`、opacity≈0.516；在运行中切到 reduce 后 transform 为 none、opacity 为 1，关闭后 dialog 为 0、滚动锁解除并回到快捷键触发器。这只证明所采样入场和运行时减少动态效果生效，不证明持续帧率。所有尺寸都是桌面 Chromium 仿真，Safari/iOS/Android、触摸、虚拟键盘和读屏未执行。

本轮不宣称完成 P2-B 备份进度、P2-C capo/全屏、P2-D 曲库反馈、P3 真机与长时门槛。下一批按路线图优先推进备份真实阶段、取消/失败恢复与浏览器落盘提示。

### 7.4 证据索引

- [歌词修订保护桌面](evidence/studio-interactions-2026-10-17/01-lyrics-revision-guard-desktop.jpg)、[320px 草稿错误与保留](evidence/studio-interactions-2026-10-17/02-drafts-error-mobile-320.jpg)。
- [390×400 教程内部滚动](evidence/studio-interactions-2026-10-17/03-guide-short-390x400.jpg)、[320px 直接打开歌词](evidence/studio-interactions-2026-10-17/04-lyrics-mobile-320.jpg)、[平板横屏教程](evidence/studio-interactions-2026-10-17/05-guide-tablet-landscape.jpg)。
- [浏览器流程记录](evidence/studio-interactions-2026-10-17/browser-observations.json)、[尺寸与最终复测记录](evidence/studio-interactions-2026-10-17/final-browser-acceptance.json)，附自制输入与真实导出工程以便复核；这些不包含真实用户曲目或原工作树资料。

最终源码构建后再次复测全部 20 组尺寸，0 超界/小触点失败；320px 直接打开歌词成功。指南深色卡片标题原 computed color 为 `rgb(10,10,10)`，已改为 `rgb(251,249,244)`，背景为 `rgb(44,40,37)`；上列截图已刷新为修复后版本。本地浏览器最终 console error/warn 记录为空。仿真的尺寸和媒体偏好覆盖在结束时已解除，预览标签保留供查看。

### 7.5 变更文件、Git 与实际主分支回归

| 范围 | 文件 |
| --- | --- |
| 菜单、画布与父级整合 | `src/components/studio/StudioHeader.svelte`、`ScoreCanvas.svelte`、`ScoreStudioApp.svelte` |
| 四弹层 | `src/components/studio/LyricsDrawer.svelte`、`ShortcutHelpModal.svelte`、`StudioGuide.svelte`、`DraftsModal.svelte` |
| 纯边界与业务 helper | `src/lib/studio/studioFretInput.ts`、`studioSaveBoundary.ts`、`studioLyrics.ts`、`studioKeyboardScope.ts`、`draftsAsyncController.ts` |
| 回归测试 | `tests/studio-input-boundary.test.mjs`、`studio-lyrics.test.mjs`、`studio-keyboard-scope.test.mjs`、`drafts-async-controller.test.mjs` |
| 文档与证据 | 本计划、`platform-development-plan.md`、`platform-implementation.md`、`interaction-experience-roadmap.md`，以及本轮 5 张截图和 4 份 JSON |

本轮计划提交 `e107b02b`、接口提交 `300fd2d4`，实现与证据提交 **`629a03f5`**。在干净的 `D:\MIMIguitarweb-master-merge` / `master` 使用 `git merge --no-ff feature/studio-interaction-polish`，代码合并提交为 **`169d06b5`**。仅本地提交和合并，没有推送、PR、发布、远程配置或生产迁移。

实际 master 合并后重新运行以下命令，均取得完成退出码；与候选分支的 UI 验收分别记录：

| 命令 | 结果 |
| --- | --- |
| `npm test` | exit 0；306 total / 299 pass / 7 DB skip / 0 fail |
| `npm run build` | exit 0；保留 AlphaTab >500 kB chunk 提示 |
| `npm run typecheck` | exit 0；TypeScript/Astro/Svelte 0 errors，Svelte 58 warnings / 19 files，Astro 44 hints |
| `git diff --check` | exit 0，无空白错误 |
| 4 份更新文档的本地链接检查 | 0 缺失；20 组证据 JSON 0 失败；真实导出前两拍 1/12 品 |
| 原项目保护核对 | 1024 文件 SHA-256 0 差异，402 行 status 0 差异 |

本节为验收后的文档增补，另作 docs 提交并 `--no-ff` 合并，不改变已验收代码树；最终对文档链接、Git 状态与原树保护再做检查。开发分支和 master 的本轮工作均保持已提交状态；预览保留 `127.0.0.1:4336/studio`，运行实现工作树的同版生产构建，不冒充另一次 master 浏览器验证。
