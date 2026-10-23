# 练习功能正确性审计与修复计划（2026-10-17，更新至2026-10-18）

## 1. 用户问题与证据边界

用户指出制谱工坊仍不好用，并明确本轮重点为**待练、A-B、逐步提速、练习记录、继续上次**。上轮的动效/弹层/工程导出检查不能替代这五项端到端验收。本轮先按实际播放与落盘结果审计，确认缺陷后修复，不把按钮、纯函数测试或历史截图视为完整实现。

稳定基线 `master@a93a2de5`；独立实现分支 `fix/practice-runtime-correctness`。原 `D:\MIMIguitarweb` 保持原分支/改动；新保护清单含 1023 个文件（显式排除环境秘密/签名文件）与当前 Git 状态。实现/稳定工作树继续使用原目录外的独立依赖，不读 `.env` 或私钥，不推送、发布或迁移生产库。

## 2. 执行次序与分工

1. 三位 `gpt-6-luna / max` 子代理只读审查：播放器/练习状态机、个人资料/待练/版本与恢复衔接、工坊导出练习内容的语义。每条发现需有触发条件、代码定位、实际影响和验证方式，不以推测写成已证实错误。
2. 主代理只读查看用户当前工坊，不导航或改动该标签；另起 `127.0.0.1:4337` 独立 origin，导入自制谱，保护用户正在编辑的工程和个人练习数据。
3. 冻结真实缺陷与写所有权，先补能暴露错误的模型/协议回归，再做最小修复。涉及同一大型 Svelte 文件时由同一 owner 编辑，避免并发覆盖；不开展无关编辑器重写或继续堆动画。
4. 实际浏览器从真实文件选择器开始，经保存并加入待练、打开播放、设置 A-B、逐级提速、暂停/结束/备注、刷新恢复，最后真实导出备份核对内容。只使用 UI 与公开 DOM 状态观察，不注入私有播放器状态或直接改 IndexedDB。
5. 全套测试、构建与类型检查取得退出码后提交，干净稳定工作树 `git merge --no-ff`，实际 master 回归，更新本计划及开发/播放契约。无真机/实际声音/长期运行证据的项目单列未执行。

## 3. 功能判定标准与边界矩阵

| 功能 | 必须正确的行为 | 本轮验证 |
| --- | --- | --- |
| 工坊→待练 | 当前可编辑工程生成真实 IBE；工程/播放资源/待练项同事务成功后才提示成功；能直接找到并打开正确版本 | 自制两轨谱真实保存与导出；失败保留原件和工程；旧谱改动后版本变化 |
| 待练列表 | 添加幂等，状态/顺序可保存；当前选择与 URL/前进后退一致；删除/归档与正在播放的谱不会错接 | 实际刷新、同页操作与跨页返回；并发/异步代次定向测试 |
| A-B | 定义 `[A,B)` 与包含结束拍；单拍、倒序、曲末、跨 tempo/反复可解释；实际播放在选段内循环，清除后整曲播放 | 短固定速度与带反复/变速谱；观察真实循环与导出区间，不只看“循环中”标签 |
| 逐步提速 | 绑定当前谱版本、区间和原生 A 速度；完整圈才推进，去重，暂停/seek/隐藏不算完整圈；达到目标保持 | 设置每级 1–2 圈，实际连续跨级；单测覆盖中断/重复事件；核对落盘 currentBpm/completedLaps |
| 练习记录 | 只有可见/播放/持有焦点的活动会话计时；暂停/预备拍/后台/失败等待不计；时间片幂等，结束真正持久化 | 真实播放/暂停/结束及备注，导出 slices/duration/session；领域测试单调时间和写失败 |
| 继续上次 | 从正确版本断点恢复位置、A-B、倍率/音轨/显示，保持暂停；刷新不先用默认值覆盖旧断点；旧版本明确失效而不是错套 | 新标签/刷新后先读取 UI，再明确继续；真实导出核对恢复前后数据；缺资源保持旧记录 |
| 退出与切谱 | 暂停/页面隐藏/切谱/销毁最后边界明确；旧回调不能写入新谱，保存失败可重试且提示真实 | 切谱时有活动会话、失焦和正常离页；deferred 回归与实际普通 UI 路径分开记录 |
| 可达性 | 工坊说明其整曲试听与完整练习的边界；保存成功后有清楚下一步；手机入口和禁用原因可理解 | 桌面与 320/390/768/1024 CSS 视口；真机、触摸、虚拟键盘仍单列 |

## 4. 夹具、验证与范围控制

使用自写短谱，至少包含固定速度、两轨、变速/反复情形；保存输入文件、导出文件、必要截图和时间线记录。对循环计数/提速验证要真正跨过循环边界，不以手工触发事件替代浏览器结果。浏览器宿主可能节流，若环境阻止完整循环须如实写未验证，不能据此伪造成功或补入时间片。

历史 master 的 306 total / 299 pass / 7 DB skip 与类型/构建通过只是起点，本轮变更后重新运行。数据库功能与本地练习分开；不反复启动用户 Docker，不访问生产库。纯领域测试可以使用隔离 fake IndexedDB，真实浏览器流程须从产品 UI 建立资料。

## 5. 发现、修复及交付记录

修复前已确认：曲末 tick 等于 endTick 时 B 点被加一拒绝（真实浏览器）；零音量被 `volume || 16` 变为满音量；原谱各轨变调夹被默认 0 覆盖；曲库谱由 unverified 升级 SHA 时父层会重建播放器；归档项混入待练、删除后新增可产生 order 冲突，初次资料读取缺少过期代次保护（代码路径）。当时真实循环提速与记录尚待完整播放和备份核对；第三、四轮的复测结论见下文。

### 修复合同与写所有权（2026-10-18）

- `luna_player_correctness`：唯一编辑 ScorePlayer；新增专属纯函数及测试。零音量保持 0；seek 后以当前展开 tick cache 更新拍末。新增可选 `onPracticeScoreVerified(verified: PersonalScore)`，只在实际 bytes hash 验证后通知，不自行修改父层挂载 key。source/asset/revision 身份校验必须保留。
- `luna_practice_correctness`：唯一编辑 PracticePanel 与 practiceProgress/专属练习 helper 和测试。B 是实际拍末且允许恰为曲末，不能接受真正越界或用未知旧拍末扩大区间；区分参数操作错误与持久化失败。传入 `useSourceCapo?: boolean` 并写进断点；续练始终保持暂停。保留完整圈、中断、写入幂等和版本保护。
- `luna_queue_correctness`：唯一编辑 PersonalPractice、PersonalLibrary、catalog、studioPersistence，新增 queue/选择协调 helper 和测试。活动队列排除 archived，归档单列可恢复；排序原子归一并提供上下移。初次/订阅读取和销毁均有代次。只有当前播放器亲自验证过的相同 catalog source/URL/asset 身份的 unverified→SHA 提升可以原地同步，实际版本/附件变化必须重新加载。
- 主代理：types/validation 与其测试、工坊直达练习入口、两处曲谱详情传入缺失 capo 的语义、整合/实际浏览器/文档/Git。shared 新字段 `PlayerResume.useSourceCapo?: boolean`：true 保留原谱逐轨 capo；false 为显式绝对覆盖；缺失维持旧断点数值绝对覆盖语义，不重新解释旧 0。无显式 capo prop 的新加载使用 source；显式数字 prop 沿用指定覆盖。UI 的降半调 -1 应可保存（旧验证错误禁止该现有选项）。

上述三位子代理均使用用户指定的 `gpt-6-luna / max`，不提交或操作用户标签。根代理收集改动后统一验证提交。

### 真实验收追加的修复（第二轮，仍属本练习闭环）

固定段已真实完成 60→70→80 BPM、暂停不增时、刷新后手动恢复、备注与 30287 ms/6 切片落盘；工坊直达正确工程、逐轨 2/5 品及零音量、队列排序/归档/恢复也已走真实 UI。不能据此提前宣布反复段通过：

1. Player owner 修正第二小节拍号：AlphaTab `Beat.playbackStart` 为小节内相对 tick，不能再减 masterBar.start；必须用真实 JsonConverter/MidiTickLookup 的第一/第二遍测试。
2. Practice owner 区分保存的待恢复提速计划与真正应用到当前 loop/ratio 的计划，恢复前不能显示“保持80”或以该计划 BPM 覆盖实际默认速度。
3. Player owner 修正 AlphaTab 1.8.4 暂停重复段自动回到首遍 beat start 的 SDK 行为：捕获可信展开位置，按当前 load/intent 代次用引擎回执恢复，用户新 seek/stop/切谱取消旧纠正；非零 A 的 loop 在曲末重播必须从 A 开始，不能统一回0。不在组件中伪造 loop 完成事件。重新跑相同反复/90 BPM 夹具，再核对真实范围、圈数和备份。
4. Queue owner 只追加导航相关 CSS：普通宽度过渡从1366缩到320/390时搜索触发器会暂时撑出全页横向滚动；减少动态效果模式与稳定视口正常。收口搜索/导航几何边界，维持44px触控目标和原有交互。根代理复测普通/减少动态效果五档视口。

### 第二轮真实复测结果与剩余项（2026-10-18，历史记录）

第二轮使用同一自写反复夹具重新验证，不覆盖第一轮“暂停后回到首遍、越出 `[12288,15360)`、提速不推进”的失败记录。复测中 A=12288、B=15360；播放器实际在该段第二遍播放，45→60 BPM 到达目标。暂停后 UI 与导出断点稳定在 tick 14173，区间仍为 `[12288,15360)`，实际 speed=60 BPM、playbackRatio=2/3；刷新后明确继续上次也恢复到 tick 14173、该区间和 2/3 倍率，保持暂停。

这仍不是完整续练闭环通过：刷新前恢复提示仍显示“上次计划 45 BPM，恢复后生效”，与实际60 BPM不一致；继续后又提示断点实际倍率与保存计划不一致，并要求重设计划。`phase2-backup-summary.json` 中 session `7ebca2ae-a999-4cfb-b170-06528c4cd7b2` 为 21298 ms/5 slices，备注明确记录此不一致，故该 session 仅作缺陷证据，不计为完整恢复通过。Practice owner 已定位 loopGeneration 误传给 `persistSession` 的 practiceGeneration，正在修正；修复后须重新验证恢复提示、真实速度计划、实际 loop/ratio、暂停位置以及最终备份中的 session/计划字段。

第二轮其余定向 UI 检查：单拍 A-B 为 `[0,960)`；倒选且包含原 A 拍末时规范为 `[0,7680)`；曲末 A 参数操作错误未显示“重试保存”，重新设 A 后错误可清除。`runtime-observations.json` 记录单拍与倒选结果，曲末错误恢复来自同轮实际 UI 操作记录。它们不替代下一轮反复段与提速恢复复测。

导航搜索宽度过渡已收口，触发按钮仍为44px；但 `responsive-normal-final.json` 显示普通模式仍有横向溢出：320 CSS 视口 client/scroll 为305/427，390视口为375/434。根因定位为练习入口长按钮在断点变化时未正确换行，Practice owner 正在修；因此普通模式响应式结果不能写作通过。`responsive-reduced-motion-checks.json` 的320/390/768/1024/1366五档均无溢出，但这不能覆盖普通模式问题。重修后应重新取两种动效模式的五档结果，并确认触控目标仍为44px。

第一、二轮的检查数是历史快照，第四轮完成后已按最终代码重新运行检查，详见下方“第四轮交付收口”。本轮 CSS 仿真/短时浏览器实播仍不替代真机、可闻声音、受控长时间运行和真实曲库数据库验证。

### 第三、四轮修复与第四轮交付收口（2026-10-18）

第三轮将反复练习提速计划写入和恢复时的提示对齐：会话 `e198317c-59b1-4fb2-ad53-9d473c4645b7` 的 UI 实际到达60 BPM，刷新后计划显示60 BPM，明确恢复回到 tick 14582、`[12288,15360)`、倍率2/3且保持暂停。该记录累计23033032 ms/4129 slices，但任务续接之间约6小时没有持续观察；不能以累计时间替代受控长测、可闻声音或真机结果。第三轮曾观察到首次点击恢复未改变 UI，原因未确认；另在输入备注后首次点击结束只保存备注，待回顾更新后再次点击才结束。第四轮以独立短会话复测了一次恢复和备注后单次结束路径。

第四轮反复段短会话 `81685aad-a2d2-4a60-acda-0855690520d4` 已通过：真实循环从45推进到60 BPM，计划为 nativeAnchor90、start45、target60、step15、每级1圈、current60，区间 `[12288,15360)`。暂停位置为 tick 13272；刷新后页面先呈默认 tick1/BPM120，并提示上次计划60 BPM；明确恢复一次后位置为 tick13273（AlphaTab 回执允许1 tick差）、范围和2/3倍率恢复且保持暂停。输入长备注后单次点击“结束并保存”即完成。该会话为16560 ms/5 slices，`final-backup-summary.json` 校验的会话计划字段与此一致；实际页面截图为 `practice-restored.png`。session 中 `completedLaps=0` 是落盘字段原值，不在这里推断为多圈长时间已验收。

第四轮还修正主操作受回顾区重排影响的问题：`PracticeReview` 位于播放器/空列表提示之后，备注失焦触发保存时不会推开正在操作的播放器按钮。单击结束的真实流程已在上述短会话复测通过。

| 交付检查 | 第四轮结果 |
| --- | --- |
| `npm test` | 336 total；329 passed；7 database skipped；0 failed |
| `npm run build` | exit 0 |
| `npm run typecheck` | exit 0；58 个既有 Svelte warnings、44 个 Astro hints |
| `git diff --check` | exit 0 |
| 原工作树保护 | `D:\MIMIguitarweb`：1023 个保护文件 SHA 差异0；402行 Git 状态快照差异0 |

验收服务曾在构建未结束时提前启动并因缺少 manifest 退出；根代理停止重叠检查，等待 build exit0 后重新启动服务并完成复测。该次启动顺序错误不是源代码构建失败。临时 CSS 视口模拟已清理。

最终产品备份 `final-backup-summary.json` 为 revision 8455，4个引用附件通过严格 SHA 和引用集合校验。`restore-roundtrip-check.json` 记录实际下载→文件选择器→产品校验预览→合并恢复→再次下载：8455→8456，除 revision 外 payload 深度相同，7条会话、4个附件且无重复，关键提速计划和断点字段相同。实际 UI roundtrip 与最终会话字段检查不替代生产数据库验证。

`responsive-acceptance.json` 在最终布局和恢复后的页面数据上记录普通模式与 reduced-motion 各320/390/768/1024/1366共10档；每档 scrollWidth 等于 clientWidth，关键按钮高度至少44px。它验证的是 CSS 视口，不是真机布局或触摸反馈。

| 变更范围 | 主要文件 |
| --- | --- |
| 播放器、seek 回执衔接、重复段暂停恢复与曲末 A-B | `src/components/player/ScorePlayer.svelte`、`src/lib/player/scorePlayerCorrectness.mjs`（复用已有 `src/lib/practice/seekReceipt.ts`，该文件本轮未修改） |
| 提速、会话计时/保存重试与回顾布局 | `src/components/practice/PracticePanel.svelte`、`src/lib/practice/practiceProgress.ts`、`src/lib/practice/practiceSessionWriter.ts`、`src/lib/practice/practiceSaveIssues.ts`、`src/components/PersonalPractice.svelte` |
| 待练队列、归档/顺序、选择与 SHA 晋升 | `src/components/PersonalPractice.svelte`、`src/components/PersonalLibrary.svelte`、`src/lib/personal/practiceQueue.ts`、`src/lib/personal/catalog.ts`、`src/lib/personal/studioPersistence.ts` |
| 类型、校验、工坊入口及曲谱页面衔接 | `src/lib/personal/types.ts`、`src/lib/personal/validation.ts`、`src/components/studio/ScoreStudioApp.svelte`、`src/components/studio/StudioHeader.svelte`、`src/pages/tabs/[id].astro`、`src/pages/ukulele/[id].astro`、`src/layouts/Base.astro` |
| 专属回归 | `tests/personal-practice-queue.test.mjs`、`tests/practice-capo-compatibility.test.mjs`、`tests/practice-progress.test.mjs`、`tests/practice-save-issues.test.mjs`、`tests/practice-session-writer.test.mjs`、`tests/score-player-correctness.test.mjs` |

源代码、协议和专属测试已在修复分支提交 `ea85e296`（`fix: make practice playback and saved progress consistent`，26 files），之后通过本地 `git merge --no-ff` 合入 master，第四轮合并提交为 `1fa53177`。该轮 master 后回归以 `master-regression-round4.json` 为准；第五轮提交及最终 master 结果另见下文。

### 第四轮本地 master 合并后回归（2026-10-18，历史快照）

实际验收的 master 提交为 `1fa5317780cf8a9e86f542c73515d96fc1c2a46d`，源代码提交为 `ea85e2961c64dd0b134c876758490a6667689941`。测试 `npm test` 为336 total / 329 passed / 7 database skipped / 0 failed；`npm run build`、`npm run typecheck`、`git diff --check` 均 exit0。typecheck 保留58个既有 Svelte warnings、44个 Astro hints。

独立 master checkout 最初没有 Git ignored 的 soundfont 文件。根代理从原目录只读复制已有132个文件（约20 MiB）到 master ignored `public/storage/soundfonts`；源文件 SHA 差异0、原目录未改。补齐资源后 build exit0，服务在 `http://127.0.0.1:4336` 启动：health HTTP200，studio HTTP200，三份基础音源均 HTTP200 且 SHA 与本地相符，readiness 的 soundfonts 为 ready 3/3；`qaResourcesIncluded=false`，正式 dist 不含 `__practice-audit__` 测试资源。

整体 readiness 仍为 HTTP503：隔离预览没有连接真实数据库，database/catalog/resources 状态不可用。migration 状态是 unavailable，required4 / applied0 / pending4 是 unavailable 响应中返回的占位计数，不代表实际迁移执行状态；未运行迁移或生产操作，因此不能写作“全部服务 ready”，也不据此声称真实曲库数据库已通过。HTTP/SHA 证明资源存在且一致，不证明声音已实际听到。

### 第五轮提速计划表单真实复测（2026-10-18；已完成 master 回归）

代码提交 `7c550233` 在 `PracticePanel.svelte` 增加有效已保存提速计划的加载与显式恢复回填：start/target/step/laps 为45/60/15/1。`speed-plan-form-observations.json` 有四阶段，`speed-plan-form-check.json` 对这四阶段作断言。实际45→60 BPM期间，未提交的target75草稿保持不变；冷载后表单回填45/60/15/1；再将target改为75后明确继续上次，表单仍回填保存值45/60/15/1。暂停 tick12780，恢复 tick12781（1 tick回执容差），范围 `[12288,15360)`、倍率2/3并保持暂停。会话 `ab18094b-1f82-454a-b393-fad51ba65b1a` completed 19071 ms/5 slices；第五轮备份 revision8487、4附件严格校验通过，保存计划 target/current 均为60，未被target75草稿覆盖。`practice-restored.png` 现为第五轮表单状态截图；第四轮截图另存 `practice-restored-round4.png`。

第五轮修复分支 `npm test` 为336 total / 329 passed / 7 database skipped / 0 failed；`npm run build`、`npm run typecheck`、`git diff --check` 均 exit0，typecheck仍有58个既有Svelte warnings和44个Astro hints。commit `7c550233` 已通过本地 no-ff 合并提交 `fc53750e` 合入 master；在该 master 实际重新执行上述四项检查，结果相同，详见 `master-regression.json`。第四轮的 `master-regression-round4.json` 单独保留，不用于替代第五轮检查。

当前未执行边界和下一轮建议顺序：

1. 做受控长测：在持续可观察的前台/音频焦点会话中记录真实播放、暂停、后台、恢复和结束时间，并核对每个 slice；不能用跨越长时间无人观察的会话累计时长替代。
2. 做可闻声音检查：在目标输出设备上实际听到有效轨道，并核对静音轨和非零音量轨的变化；目前 UI/备份音量字段正确不证明声音已被听见。
3. 做真机触控与布局验证：在目标 iOS/Android 浏览器或应用宿主检查按钮触控、横竖屏、键盘与焦点行为；CSS 视口仿真不能替代设备证据。
4. 在隔离的非生产环境验证真实曲库数据库连接和读写边界；本轮使用自写夹具与本地个人资料，不声明已验证真实曲库数据库。

第五轮已完成保存计划回填和草稿保护的实测及 master 回归。`master-regression.json` 记录实际测试的 `fc53750e556855e2b072ccb4e2a1e8c29eb4c3e2` 与源码 `7c550233022177265df4e0f05aee26a4f1b9c52b`。修复版重新在4336启动，health和studio为200，三份基础音源HTTP200且SHA一致、readiness音源3/3；整体503仍源于隔离预览数据库不可用。正式dist无QA资源，原目录1023文件和402行状态复核差异均0。其后的交付记录提交仅更新文档与证据，应用源码与该已验证提交一致。
