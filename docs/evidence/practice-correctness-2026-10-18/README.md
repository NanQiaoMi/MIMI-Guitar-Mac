# 练习闭环验收（2026-10-18）

输入均为自写短谱，浏览器资料位于独立 `127.0.0.1:4337` origin。用户 `4336` 当前工坊标签没有被导航、刷新或编辑；原工作树也不用于安装、构建或修复。截图是实际页面，夹具不是用户谱或曲库运营数据。

## 已复现的稳定基线问题

- `baseline-player-log.json`：catalog:acceptance-0 在 00:33:02 初次载入，同页点击“开始练习”后 00:33:09 再次 load/render；界面停在 tick 1、继续练习、0 秒。对应原 parent 在 revision 晋升时重挂载路径。
- 曲末 B 点：2 小节谱 `endTick=7680`，设 A=1 后拖到曲末，旧公式把 B 算成7681。旧参数错误还显示“重试保存”，且可能被后台断点写成功清掉；本轮为其增加精确曲末和错误归属回归。
- `baseline-backup-summary.json`：经产品真实下载的 revision 26 备份，2 个附件摘要与严格数据校验通过；唯一完成记录为 2 个切片、4288 ms。这里只证明旧流程的短时记录能落盘，不能证明提速、续练、声音可闻或完整练习闭环。

## 修复版浏览器步骤与判定

1. 真实文件选择器导入 `self-authored-practice.json`，保存并加入待练，使用成功提示的直达入口。确认练习版双轨各自 capo 2/5，第一轨音量 0；不注入 IndexedDB 或私有播放器状态。
2. 暂停状态分步 Home → 设 A → End → 设 B，每步读取公开 UI；曲末应形成 `[A,7680)`，并显示实际末小节/拍。再检查单拍及倒选，失败不能改变现有区间。
3. 设置真实 60→80 BPM、步长10、每级1圈；开始会话和提速，连续跨越真实循环边界，到目标后保持80。中途暂停不增加伴奏时长；在圈中 seek/暂停使未完成圈失效。
4. 填写备注，暂停并刷新。未明确恢复前保持默认可见位置且不能覆盖旧断点；点击继续上次后实际恢复 A-B、倍率、混音和原谱 capo，仍保持暂停。继续播放、结束并保存，核对回顾与备份。
5. 产品备份恢复导入 `self-authored-catalog-backup.json`（3 个合法 placeholder 引用，使用自己生成的静态 IBE）；fresh acceptance-1 首次开始应直接播放，没有第二次 loadScore。acceptance-2 验证反复/变速的展开位置。
6. 我的谱中实际上移、归档、恢复，刷新核对顺序与选择器；已归档/不存在的显式 URL 不得悄悄打开另一首。
7. v1 备份从产品 UI 真正下载，以下载工具返回路径运行 `verify-ui-backup.mjs`，严格校验 payload、引用集合、每个资源 SHA、切片 ID 和时长；从实际数据汇总速度计划/断点/备注。
8. 在 320/390/768/1024/1366 CSS 视口核对全页溢出、主要入口和按钮。恢复临时浏览器仿真设置。设备尺寸仿真不等于 iOS/Android/Safari 真机证据。

## 可复现命令

```powershell
node docs/evidence/practice-correctness-2026-10-18/prepare-fixtures.mjs
# 构建会替换 dist；每次构建后重新运行上句，将测试资源复制到 dist/client。
node docs/evidence/practice-correctness-2026-10-18/verify-ui-backup.mjs '<actual-download-path>' '<summary-output-path>'
```

生成器只写本目录自写夹具和可选的 dist 测试资源，从不打开真实浏览器数据库。测试资源仅在隔离验收服务可用；正式产品构建不包含该临时静态目录。

## 修复版实测结果

第一轮构建/typecheck退出0（58个历史Svelte warnings），332项测试中325通过、7数据库跳过。当前已实际完成：

- fresh catalog:acceptance-1 首次开始自然播放到末尾，保存4秒，没有首次开始引起的第二次载入；随后建立 `[0,7680)`，完整圈依次达到60/70/80 BPM。
- `runtime-observations.json` 记录实际60/70/80状态和时间。暂停后30秒、刷新前后不增加；明确恢复后仍暂停，位置5761→5762（AlphaTab回执容差1tick）、倍率2/3、loop和逐轨source capo恢复。`phase1-backup-summary.json` 严格校验4附件与SHA，已完成的该会话为30287 ms、6切片，并包含输入的备注和currentBpm80。
- 工坊真实文件选择器导入新夹具，保存后直达 `project:imported_7zcf5p9_mvcn8cj1`；UI原谱capo为逐轨2/5品，第一轨音量0。`studio-to-practice.png` 为真实保存成功入口截图。
- UI两次上移“曲库排序乙”后到队首；归档“曲库校验甲”刷新后保持归档，活动selector不含它，显式已归档URL显示恢复提示且播放器数0；恢复后追加活动队尾。
- 第一轮曾观测普通模式320 CSS视口过渡后的client/scroll均为305、主要按钮44px；这只是当时的一次读数，不足以代表最终响应式验收。`responsive-checks.json` 是宽度过渡中的首次取样，不能视为稳定布局通过；`responsive-reduced-motion-checks.json` 五档均无溢出。后续普通模式复测与搜索收口结果见下方“第二轮响应式复测状态”。IAB在仿真尺寸下截图有缩放/捕获限制，尺寸依据DOM实测，不用模糊截图伪装真机证据。

第一轮反复段**不通过**：A12288/B15360（第二遍第二小节90 BPM）、45目标与0.5倍计算正确，但暂停后回到首遍4801，继续播放在选段外7943，未推进圈数。缺陷记录单独标注并结束，62333 ms不作为选段成功证据。SDK原因和第二轮修复记录在总计划；第二轮须重新构建，并新建独立会话复测，不能复用这个失败结果。

## 第二轮真实复测：首次恢复计划不一致（2026-10-18，历史记录）

第二轮用独立新 session 重新测了相同的反复段，保留第一轮失败结果，不以第二轮结果覆盖或抹去它。实际 A/B 为 `[12288,15360)`；复测确认第二遍段内播放，逐步由45 BPM达到60 BPM。暂停时实际位置稳定在 tick 14173，范围仍为 `[12288,15360)`，实际倍率为2/3。刷新后先保持引擎默认位置/速度，点击“继续上次并保持暂停”后才恢复 tick 14173、相同范围和2/3倍率，播放器保持暂停。

续练的计划提示当时不一致：刷新前展示“上次计划 45 BPM，恢复后生效”；显式恢复后实际速度为60 BPM，却显示“断点实际倍率与已保存提速计划不一致；已保留实际倍率，请重设计划”。`phase2-backup-summary.json` 中 session `7ebca2ae-a999-4cfb-b170-06528c4cd7b2` 是 21298 ms、5 slices，备注记录了旧45计划与实际60不一致。该记录保留为缺陷证据，**不能算完整续练闭环通过**。Practice owner 后续定位并修正 loopGeneration 被误传为 `persistSession` 的 practiceGeneration；第三、四轮结果见下文。

同轮其它定向结果：单拍区间 `[0,960)` 通过；倒选并包含原 A 点拍末后规范成 `[0,7680)` 通过；曲末 A 参数错误没有进入“重试保存”，重新设 A 可清除该错误。对应的单拍/倒选公开 UI 记录在 `runtime-observations.json`；曲末错误恢复依据本轮实际 UI 操作记录。以上不替代提速恢复缺陷的重新验收。

### 第二轮响应式复测状态（历史记录）

`Base.astro` 已收口导航搜索按钮的宽度过渡，按钮仍保持44px。随后普通动效模式实测仍失败：`responsive-normal-final.json` 在320 CSS视口记录 `clientWidth=305`、`scrollWidth=427`，390视口记录375/434；视口改动时练习入口长按钮没有正确换行，造成全页水平溢出。Practice owner 后续修正断点换行；第四轮最终两种动效模式×五档视口结果见下文。该段保留为问题历史。

第二轮最近一次综合检查曾为335 total、328 passed、7 database skipped、0 failed，build/typecheck退出码均为0；该快照不包含后续修复，不能作为最终证明。最终修复分支检查见下文。

## 第三、四轮收敛与交付检查

第三轮反复段刷新恢复中，界面显示计划60 BPM，显式恢复后回到 tick 14582、A-B `[12288,15360)`、倍率2/3并保持暂停。长 session `e198317c-59b1-4fb2-ad53-9d473c4645b7` 累计23033032 ms/4129 slices，但任务续接时约6小时没有持续观察；它**不作为受控长测、声音或真机证据**。第三轮首次点击恢复曾未改变 UI，原因未确认；输入备注后首次结束只保存备注，待回顾更新后再次点击才结束。第四轮用独立短会话验证了一次恢复和备注后单次结束流程。

第四轮短会话 `81685aad-a2d2-4a60-acda-0855690520d4` 真实跨过反复段 `[12288,15360)`，从45 BPM达到60 BPM。落盘计划为 nativeAnchor90、start45、target60、step15、每级1圈、current60、completedLaps0。暂停 tick13272；刷新后先显示默认 tick1/BPM120与“上次计划60 BPM”；单次点击明确恢复后为 tick13273（与 pause 相差1 tick，属于 AlphaTab 回执容差），A-B、2/3倍率和暂停状态一致。输入长备注后**单次点击结束并保存成功**，会话为16560 ms/5 slices；`practice-restored.png` 为真实页面截图。第四轮也把 `PracticeReview` 移到播放器/空列表提示之后，备注失焦自动保存不会再推动主操作按钮。

| 验收项 | 第四轮证据与结论 |
| --- | --- |
| 反复段 A-B、真实提速 | `[12288,15360)` 内循环，45→60 BPM，目标达成并保持；最终计划和会话记录见 `final-backup-summary.json` |
| 刷新后继续上次 | 刷新后、明确恢复前保持默认播放位置；显式单次恢复到 tick13273、范围 `[12288,15360)`、倍率2/3并保持暂停（pause tick13272，容差1） |
| 长备注后结束 | 第四轮单次点击“结束并保存”成功，落盘16560 ms/5 slices；回顾位于主操作之后 |
| 真实备份恢复往返 | `restore-roundtrip-check.json`：真实下载→文件选择器→产品校验预览→合并恢复→再次下载，8455→8456；payload除revision外深度相同，7条会话、4附件无重复，关键计划/断点字段相同 |
| 完整备份校验 | `final-backup-summary.json` revision8455，4个引用附件；严格 SHA 与引用集合校验通过 |
| 响应式布局 | `responsive-acceptance.json`：普通与reduced-motion两种模式×320/390/768/1024/1366共10档，scrollWidth==clientWidth，关键按钮高度均≥44px；临时视口模拟已清 |
| 代码检查 | 修复分支336项测试：329通过、7数据库跳过、0失败；build退出0；typecheck退出0（58个既有Svelte warnings、44个Astro hints）；git diff check退出0 |
| 原工作树保护 | `D:\MIMIguitarweb` 的1023个保护文件 SHA差异0，402行状态快照差异0 |

验收服务曾在 build 未结束时被提前启动，因缺少 manifest 退出。根代理停止重叠检查，等 build exit0 后重新启动服务并完成复测；这是服务启动时序问题，不是最终代码构建失败。最终响应式仿真结束后已清理临时设置。

本轮主要变更按范围分组：

- 播放器与回执衔接：`src/components/player/ScorePlayer.svelte`、`src/lib/player/scorePlayerCorrectness.mjs`；复用已有 `src/lib/practice/seekReceipt.ts`，该文件本轮未修改。
- 待练、提速、会话与布局：`src/components/PersonalPractice.svelte`、`src/components/PersonalLibrary.svelte`、`src/components/practice/PracticePanel.svelte`、`src/lib/practice/practiceProgress.ts`、`src/lib/practice/practiceSessionWriter.ts`、`src/lib/practice/practiceSaveIssues.ts`。
- 资料、版本、校验与工坊入口：`src/lib/personal/practiceQueue.ts`、`src/lib/personal/catalog.ts`、`src/lib/personal/studioPersistence.ts`、`src/lib/personal/types.ts`、`src/lib/personal/validation.ts`、`src/components/studio/ScoreStudioApp.svelte`、`src/components/studio/StudioHeader.svelte`、`src/pages/tabs/[id].astro`、`src/pages/ukulele/[id].astro`、`src/layouts/Base.astro`。
- 专属回归：`tests/personal-practice-queue.test.mjs`、`tests/practice-capo-compatibility.test.mjs`、`tests/practice-progress.test.mjs`、`tests/practice-save-issues.test.mjs`、`tests/practice-session-writer.test.mjs`、`tests/score-player-correctness.test.mjs`。

修复代码与协议已在分支提交 `ea85e296`（`fix: make practice playback and saved progress consistent`，26 files），随后通过本地 no-ff 合并提交 `1fa53177` 合入 master。该轮 master 回归结果来自 `master-regression-round4.json`。第五轮表单修复提交 `7c550233` 随后通过 `fc53750e` 合入 master，并完成下述最终回归。

### 第四轮本地 master 合并后验证（历史快照）

实际回归的 master commit 为 `1fa5317780cf8a9e86f542c73515d96fc1c2a46d`，代码 commit 为 `ea85e2961c64dd0b134c876758490a6667689941`。验证通过：

| 命令/检查 | 结果 |
| --- | --- |
| `npm test` | 336 total，329 passed，7 database skipped，0 failed |
| `npm run build` | exit 0 |
| `npm run typecheck` | exit 0；58个既有 Svelte warnings、44个 Astro hints |
| `git diff --check` | exit 0 |

master 独立 checkout 起初缺少 Git ignored 的 soundfont。根代理从原目录只读复制已有132个文件（约20 MiB）到 ignored 目录 `public/storage/soundfonts`，132个文件 SHA 均与原目录一致，原目录无改动。补齐后 build exit0 并在 `http://127.0.0.1:4336` 实际启动：health HTTP200，studio HTTP200；`acoustic_guitar_fast.sf2`、`ukulele_fast.sf2`、`0.sf2` 均 HTTP200，SHA 与本地一致；readiness 的 soundfonts 为 ready 3/3。`qaResourcesIncluded=false`，正式 dist 没有 `__practice-audit__` 测试资源。

整体 readiness 仍 HTTP503，因为隔离预览未连接真实数据库，数据库及依赖其上的 catalog/resources 状态不可用。migration 状态为 unavailable；required4 / applied0 / pending4 是 unavailable 响应里的占位计数，不代表实际迁移状态。未运行迁移或生产操作；不能表述为全部服务 ready 或真实曲库数据库验证通过。HTTP/SHA 只证明文件存在并匹配，不证明播放声音已被听到。原工作树保护复核仍为1023个文件 SHA 差异0、402行状态快照差异0。

### 第五轮提速计划表单验收（已完成 master 最终回归）

提交 `7c550233` 为 `PracticePanel.svelte` 增加加载有效已保存计划及显式恢复后的 start/target/step/laps 回填（45/60/15/1）。`speed-plan-form-observations.json` 的四个阶段由 `speed-plan-form-check.json` 断言。实际45→60 BPM期间，未提交 target75 草稿保留；刷新冷载回填保存值45/60/15/1；再把 target 改为75后点击继续上次，也恢复成45/60/15/1。暂停tick12780，显式恢复tick12781（1 tick容差）、A-B `[12288,15360)`、倍率2/3并保持暂停。会话 `ab18094b-1f82-454a-b393-fad51ba65b1a` completed 19071 ms/5 slices。第五轮真实产品备份为revision8487，4个附件严格校验；落盘计划 target/current 均为60，未被target75草稿覆盖。`practice-restored.png` 现为第五轮参数表单截图，第四轮截图为 `practice-restored-round4.png`。

第五轮修复分支及合并后的实际 master `fc53750e` 均重新执行检查：`npm test` 为336 total、329 passed、7 database skipped、0 failed；`npm run build`、`npm run typecheck` 和 `git diff --check` 均 exit0，typecheck保留58个既有Svelte warnings、44个Astro hints。最终结果为 `master-regression.json`；第四轮的 `master-regression-round4.json` 单独保留为 `1fa53177` 历史证据。

仍需依序补充的边界验证：

1. 受控长测：持续观察前台/持有音频焦点下的播放、暂停、后台、恢复和结束，核对实际时间片，不能用间隔数小时无人观察的累计记录代替。
2. 可闻声音：在实际扬声器/耳机上确认非静音轨道可听、速度变化生效且静音轨道确实静音；当前 UI 和备份字段不证明声音已听到。
3. 真机与触摸：在目标 iOS/Android 浏览器或设备上验证触控、横竖屏、焦点和虚拟键盘；CSS视口仿真不等于真机。
4. 真实曲库数据库：仅在隔离非生产环境验证连接和读写；本轮使用自写谱、本地资料与真实产品备份 UI，不声明真实曲库数据库已验证。

第五轮已通过速度计划表单回填、草稿保护及实际 master 回归。`master-regression.json` 记录测试提交 `fc53750e556855e2b072ccb4e2a1e8c29eb4c3e2` 和源码 `7c550233022177265df4e0f05aee26a4f1b9c52b`。最终预览重新启动于4336：health/studio200，基础音源HTTP/SHA通过且ready3/3；整体readiness503仍因为隔离预览数据库不可用，未运行迁移。正式dist没有QA测试资源，原目录1023文件及402行状态差异均0。后续交付记录提交仅更新文档与证据，应用源码与该已验证提交一致。
