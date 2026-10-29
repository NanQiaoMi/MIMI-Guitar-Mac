# MIMI Guitar：Mac 接续开发 Backlog

更新：2026-10-23。此清单把已有计划按迁移后的实际次序重新归组。它是后续工作队列，不是完成报告；即使源代码已有实现，也必须在 Mac 上重新验收，发现缺陷时再以最小改动修复。

## 排序与共同完成规则

依赖顺序：

~~~text
P0.1 包校验、依赖安装与单测
  └─ P0.3 隔离曲库恢复（创建 .env.mac.local）
       └─ P0.2 build/typecheck、媒体与服务验收
            ├─ P0.4 私人浏览器备份恢复
            └─ P0.5 Mac 音源/音频验收
                 └─ P1 练习/工坊可靠性 -> P2 体验与架构 -> P3 真机/长期门槛
~~~

- 每项完成记录实际分支、变更文件、命令及退出码、浏览器/设备范围、失败或跳过项。没有发生的行为标为“未执行”，不能从计划、代码存在或历史 Windows 结果推断通过。
- Mac 恢复先针对迁移包和新建隔离环境。没有用户另行要求，不连接 Windows 原数据库、不清理浏览器资料、不覆盖已有 Mac 数据、不推送/发布。
- 单测验证代码边界，浏览器验证真实页面流程，设备和听音验证由实际 Mac/iPhone/iPad/Android 与目标音频输出完成。Readiness、HTTP 200、MIDI 事件和播放按钮各自只支持其直接观测结论。
- 尽量只为 Mac 上复现的问题或用户明确选择的功能改代码。若已有 Windows 已验收行为在 Mac 通过，不重复重构；把验证结果补到对应证据文档。

## P0：恢复与验证

### P0.1 校验迁移包并在 Mac 建立稳定代码环境

**目的与状态：** 首次迁移门槛。包结构已有明确入口：`START-HERE.md`、`PACKAGE-MANIFEST.json`、通用备用 `SHA256SUMS`、包外 `zip.sha256`、`project/source-revision.json`，以及包根 `reports/source-export.json`、`reports/media-inventory.json`、`reports/catalog-resource-coverage.json`、`preserved-work/manifest.json`。逐项以实包清单和脚本帮助为准；包校验与 Mac 安装尚未执行。

**入口：** 包根 START-HERE.md、`project/tools/verify-handoff.mjs`；`project/package.json`、`package-lock.json`、`prisma/schema.prisma`；`tools/mac-bootstrap.mjs`；docs/mac-handoff-plan.md。

**依赖：** 拿到完整迁移包；拥有匹配芯片的 macOS 与 Node 24.x；npm ci 能访问 package-lock 实际 `resolved` 镜像及 Prisma 引擎分发服务。锁文件记录了大量 `https://repo.huaweicloud.com/repository/npm/` URL；仅修改 npm 默认 registry 未必改变锁定的 resolved。需要数据库时安装并启动 Docker Desktop。

**边界：** 不带/使用 Windows node_modules、dist、.astro、.env；Mac 包 Git 是可追溯稳定源码的独立快照历史，不要求当前 HEAD 等于 `c0fdccae`；不使用 npm install 或 npm update 改锁文件；保留现有 Mac 项目和浏览器数据；不得为绕过失败升级依赖或重置数据库。

**验证：** 解压后先在包根运行 `node project/tools/verify-handoff.mjs --root .`，检查包外 `zip.sha256`、`PACKAGE-MANIFEST.json` 中逐文件大小/SHA、媒体数量和 database metadata；再核对 Node 24.x/架构，运行 `node tools/mac-bootstrap.mjs --help`、`doctor`、`install --dry-run`、`install`。install 应执行 `npm ci` 和 `npx prisma generate`。运行 `npm test` 并记录实际结果及 skip；完成 P0.3 隔离恢复（为 wrapper 生成 `.env.mac.local`）后，按 `node tools/mac-bootstrap.mjs build` → `npm run typecheck` 顺序继续检查。Windows 原 7 项数据库 skip 来自 `tests/search.test.mjs` 的 5 项、`tests/sheetform.test.mjs` 的 2 项：各文件用 `db.tab.count()` 探测当前配置库，探测失败就 skip；`REQUIRE_TEST_DATABASE=1` 时则失败。不要把 skip 归因为 Docker 不可用。

**完成门槛：** 包内全部逐项摘要匹配；`package-lock.json` 无变化；Node ABI 和 Prisma Client 在 Mac 本地生成；`npm test` 有真实结果。构建与类型检查由 P0.2 在本机数据库配置就绪后验证。失败、skip 或具体网络/环境 blocker 留在 P0，不标为通过。迁移镜像若确有必要，另立变更审查全部 lockfile 后重新执行安装、测试和构建验证；本任务不改镜像、不更新依赖。

### P0.2 完整恢复 public/storage 与构建交付验证

**目的与状态：** 稳定 Windows `public/storage` 已盘点 32,595 个文件、554,546,235 字节；全量曲库 URL 检查为 12,106 `scoreUrl`（稳定目录有 12,102，另有原目录独有 4 份待补入）、4,127 `xheUrl` 和 16,220 `screenshotUrl` 均有稳定目录对应文件，另 13 条无截图但非 missing；无外链、非法路径或两边都缺失。原目录新增的 10 个不同文件都留在隔离 overlay 作候选，其中引用的 4 份会额外复制进包内稳定媒体；不覆盖既有稳定文件。包内 `project/public/storage` 最终为 32,599 文件、555,536,315 字节；最终数/字节以包根 `PACKAGE-MANIFEST.json` 和 `reports/media-inventory.json` 为准，覆盖记录见 `reports/catalog-resource-coverage.json`。Mac 解压、构建输出和运行服务仍待检查。

**入口：** project/public/storage；tools/prepare-score-resources.mjs；tools/mac-bootstrap.mjs doctor；package.json 的 resources:prepare / resources:check；docs/score-resource-delivery-plan.md；docs/evidence/score-resource-delivery-2026-10-19/。

**依赖：** P0.1、P0.3；包里的完整媒体目录、逐文件 SHA-256 清单和 license/notice 文件。Mac wrapper build 需要先由 restore-catalog 创建 `.env.mac.local`。

**边界：** 不从网上重新抓谱或音源，不根据名字映射替代缺失文件；不纳入 personal uploads；不把 public 检查代替 dist 检查。已存在不同摘要文件时停止，不覆盖。文件分类计数只是完整清单的交叉核对。

**验证：** 对 Mac 解压后的最终清单计算 SHA-256；运行 `node tools/mac-bootstrap.mjs build` 后执行 `npm run typecheck`，顺序执行，勿并行清理 Astro 生成类型；对本地 public 与构建后的 dist/client/storage 执行资源工具；从实际服务 HTTP 请求清单内抽样的真实 IBE、XHE、截图和基础 SF2，核对长度/摘要与解码。确认候选 QA fixture 不在正式 dist。

**完成门槛：** 完整清单 missing/extra/different 都为零，字节数及摘要与包清单一致；至少一份吉他谱和一份尤克里里谱从实际 Mac 服务被正确读取。抽样仅作为运行验收，不能代替完整 SHA 清单。

### P0.3 在 Mac 隔离恢复本次曲库快照

**目的与状态：** 本次新鲜 PostgreSQL custom dump 已生成，大小 1,235,838 字节，SHA-256 `7f709c83bf7d43d18d9a92ebf8b08a9dd1ddbbf6dc1cbe3173611f96168c71a1`；Windows 已在无网络、tmpfs 隔离的 PostgreSQL 16 容器中成功恢复并核对：Tab=16,233、Article=8、migrations=4。`User`、`Favorite`、`UploadRecord` 有表结构且各为 0 行。Mac 上恢复尚未执行。

**入口：** database/catalog.dump；project/tools/mac-bootstrap.mjs restore-catalog；project/docker-compose.mac.yml；prisma/schema.prisma、prisma/migrations/；docs/catalog-runtime-recovery-plan.md、docs/local-catalog-startup.md、docs/evidence/catalog-runtime-2026-10-20/。

**依赖：** P0.1；包根校验通过；包内 `database/catalog.dump` 与 `database/catalog-metadata.json` 存在且匹配；Mac Docker Desktop 已正常启动。该步骤先于 P0.2 的 wrapper build，因为它创建 build/dev/start 所需本机配置文件。

**边界：** 只恢复到迁移脚本新建的 Compose project `mimi-guitar-mac-dev`、容器 `mimi-guitar-mac-dev-db`、volume `mimi-guitar-mac-dev-data` 和 PostgreSQL 16；端口固定为 `127.0.0.1:15433`，已占用或目标资源已存在就停止。严禁 `--clean`、drop、覆盖已有数据库、连接 Windows `mimi-guitar-pg` 或写生产库。不要在原数据库上试 restore。metadata 记录 `postgresMajor=16`、SHA 与 `counts.tabs/articles/migrations=16233/8/4`；恢复校验只允许 `Tab`、`Article`、`_prisma_migrations` 的 TABLE DATA，迁移后要求行数精确匹配、4 条 migration 均已完成且无未完成 migration，`User/Favorite/UploadRecord=0`。

**验证：** 先运行 `node tools/mac-bootstrap.mjs restore-catalog --dry-run`，确认它校验 custom dump、metadata/SHA、Docker、固定端口和现有目标资源且不写配置/不启动容器；dry-run 不检查 archive TOC。再执行真实恢复。脚本核对 archive 白名单及导入后 exact counts/migration/account-table 条件；TOC capture 不完整或超出校验限额时须 fail-closed。若恢复在创建容器/volume 后失败，检查资源状态后再人工处理，脚本不会自动删除。另行核对曲库资源引用和本地文件关联的覆盖范围；观察 `/api/readiness` 的 database/catalog/resources 子状态，不要只看 health。

**完成门槛：** 有本次 Mac 隔离恢复的命令退出码、目标身份、metadata/SHA 结果、非敏感精确计数和 readiness 结果；引用核对有覆盖说明。任何 dump 缺失、损坏、摘要不符、连接失败或引用不完整都保留为未恢复/不完整，并继续允许无数据库的演示降级。

### P0.4 迁移个人浏览器资料

**目的与状态：** 个人数据位于浏览器 IndexedDB，不在 PostgreSQL dump。Windows 原浏览器里的个人资料必须通过产品备份功能独立转移。

**入口：** Windows 与 Mac 的 /settings/data；src/components/PersonalDataSettings.svelte；src/lib/personal/backup.ts、backupVolumes.ts、repository.ts、validation.ts；docs/personal-data-contract.md；docs/evidence/practice-correctness-2026-10-18/。

**依赖：** 在含真实个人资料的 Windows 浏览器上生成备份；P0.1—P0.3 完成，Mac wrapper app 已构建并可运行；全部文件已在 Windows 下载目录中确认存在。

**边界：** v1 JSON 最多 64 MiB；v2 manifest 最多 64 MiB，最多 128 个分卷、每卷负载最多 8 MiB，整套最多 1 GiB；必须选中同一快照的全部分卷。单一下载请求不代表文件落盘。1 GiB 未做设备容量验收。不得将整套个人资料 dump 或覆盖成服务端数据库内容。

**验证：** 在 Mac 新浏览器 profile / origin 中预检完整文件集；校验摘要与预览数量；恢复后检查收藏、待练、个人谱、工坊工程、附件、会话、A-B片段、提速计划和断点。建议长期固定使用 wrapper `start` 的 `http://127.0.0.1:4336`；`dev` 的 `http://127.0.0.1:4321` 是不同 origin。同一 origin 在不同浏览器或 profile 中的 IndexedDB 也隔离。恢复一份练习谱，保持暂停并明确点击继续；再次导出，核对实体计数、引用关系与附件摘要。

**完成门槛：** 完整 v1 或 v2 文件集校验成功、恢复事务成功且页面重开后数据仍在；关键实体和附件无静默缺失；导出往返一致。取消/损坏/缺卷/冲突测试保持原资料 revision 不变。origin（协议+host+port）和浏览器 profile 记入记录。

### P0.5 验证 Mac 播放资源及服务状态

**目的与状态：** Windows 已验证标准 GM Sonivox 与隔离尤克里里 preset 的配置；同 bank/program 冲突显式阻断。Mac 声卡、浏览器音频策略和真实可闻声音均未验收。

**入口：** src/lib/player/verifiedScoreSoundfont.ts、scoreAuditionResources.ts、soundfontLoadReceipt.ts、src/lib/player/scoreInstrumentOverrides.ts、src/lib/guitarSound.ts；tests/verified-score-soundfont.test.mjs、tests/score-audition-resources.test.mjs；docs/preview-duration-timbre-plan.md；docs/evidence/preview-timbre-2026-10-20/。

**依赖：** P0.1、P0.2；真实媒体和标准音源已还原；至少一个真实谱已由 Mac 页面载入。

**边界：** 不把 Sonivox 文件存在说成音色听感通过；不把尤克里里 preset 扩展到曲内全部乐器；同一 bank/program 的互斥来源必须失败关闭；无有效轨道或音源缺失时显示原因。不引入麦克风权限。

**验证：** 确认 GM / 尤克里里源 URL、preset、bank/program 与加载 receipt；浏览器试听原曲有效轨道，执行停止、快切、取消、重播与音频焦点交接；在 Mac 扬声器或目标耳机上实际听到并记录观察结果。

**完成门槛：** 浏览器与音频设备、系统版本、音源身份及实际听音范围被记录。若无可信听音观察，保留“资源配置通过，实际听音未验收”，不要把它合写为音色已通过。

## P1：工坊与练习可靠性

### P1.1 A-B、提速、记录、继续上次的 Mac 实际流程

**当前状态：** Windows 多轮实现和 Chromium 流程已有证据；修复覆盖循环位置、提速计划、保存重试、断点、恢复后暂停和单次结束。Mac 的 AlphaTab/WASM、键盘焦点和浏览器音频策略尚未实测。

**入口：** src/components/player/ScorePlayer.svelte；src/components/practice/PracticePanel.svelte、PracticeFragmentLibrary.svelte；src/lib/practice/practiceSessionWriter.ts、seekReceipt.ts、nativeTempo.ts、applyPracticeFragment.ts；src/lib/personal/practiceFragments.ts；tests/practice-*.test.mjs、tests/score-player-correctness.test.mjs；docs/practice-playback-contract.md、docs/architecture-and-fragments-plan.md、docs/evidence/practice-correctness-2026-10-18/。

**依赖：** P0.1、P0.2、P0.4、P0.5；用户选择的真实谱与能听见的轨道。

**边界：** 区间使用展开 tick 的左闭右开语义；只有完整且持有音频焦点的一圈推进提速；有冲突/过期谱面版本时须拒绝应用旧片段。恢复不自动播放；保存失败不得清掉重试数据；播放时间不代表演奏识别或掌握程度。

**验证：** Mac 浏览器完成“加入待练 → 选 A/B → 45→60 BPM 或适配曲谱的参数 → 真实播放一圈并推进 → 暂停保存 → 刷新 → 明确继续并保持暂停 → 单次结束保存 → 回顾 → 备份恢复”流程。再测反复小节、seek、切曲、后台、音频焦点丢失和备注未提交时的边界。检查导出字段中的实际倍率、循环范围、保存速度计划和 session slices。

**完成门槛：** 单曲完整短流程与恢复后一致性均有 Mac 浏览器证据；无假播放/假保存/自动播放；失败可恢复；导出数据独立校验。长时间和移动真机仍由 P3 单独门控。

### P1.2 私人导入、工坊工程保存及格式损失边界

**当前状态：** 工坊支持空白工程、曲库副本、个人文件导入、保存、播放及导出；Windows 通过真实文件选择器检查过代表流程。格式转换并非所有 GP/MusicXML 能力无损。

**入口：** src/components/studio/ScoreStudioApp.svelte、ScoreCanvas.svelte、DraftsModal.svelte、StudioHeader.svelte；src/lib/studio/localScorePersistence.ts、studioScoreModel.ts、studioScoreBridge.ts、studioOriginalFileStore.ts、studioSaveBoundary.ts；src/lib/gpUpload.ts、src/lib/ibe.browser.ts；tests/studio-format-roundtrip.test.mjs、studio-personal-persistence.test.mjs、studio-local-persistence.test.mjs、personal-score-import.test.mjs；docs/score-studio-development.md、docs/studio-format-and-hit-testing.md、docs/studio-interaction-polish-plan.md。

**依赖：** P0.1、P0.2、P0.4；用隔离的个人谱/工程或测试浏览器 profile。

**边界：** 原始文件与可编辑副本独立保存；未经明确告知不可声称 GP 技法或多轨数据无损；导入失败不得替换当前工程；离线个人导入只写本地 IndexedDB，不上传服务端。个人工程、未提交歌词草稿及导出语义按原文档定义。

**验证：** 用仓库测试夹具和用户选定的非敏感文件分别走导入、转换报告、工程编辑、保存、重开、加入练习和导出；对比工程版本与原件摘要，核对乐器、轨道、节拍、小节及可承诺保存的歌词/音符字段。断开网络验证个人导入不依赖数据库；触发读写失败和同工程双标签冲突，确认草稿保留且不静默覆盖。

**完成门槛：** 已验证格式逐项形成可读/可保存/可导出结果矩阵；差异明确提示；失败保留当前工程和原件；至少一条 Mac 实际端到端记录和导出文件结构核验。

### P1.3 个人备份恢复故障边界回归

**当前状态：** Windows 上已经实现 v1/v2、摘要/附件校验、预览、revision CAS、staging 和原子合并；完整 1 GiB 真机测试未执行。

**入口：** src/lib/personal/backup.ts、backupVolumes.ts、repository.ts、validation.ts；src/components/PersonalDataSettings.svelte；tests/personal-backup.test.mjs、personal-backup-volumes.test.mjs、personal-backup-budget.test.mjs、personal-repository.test.mjs。

**依赖：** P0.1、P0.4；若测试运行在产品浏览器中，使用全新 profile 和自制夹具。

**边界：** 恢复必须先验证 manifest、全卷、附件摘要、数量和预算；全部有效后才一次提交。预览后资料 revision 变化、缺卷、混用快照、摘要损坏、取消或配额不足时不能部分写入。不能用小夹具声称完整 1 GiB 容量已通过。

**验证：** 对离线用例检查失败前后 revision 及引用集合相同；Mac 空 profile 做正常 v1/v2 小样本往返；在可隔离环境模拟缺卷、损坏卷、重复卷、快照不匹配、并发编辑、取消和配额失败。

**完成门槛：** 正常备份能完整恢复；全部失败场景保持原数据不变或明确报告无法确认 staging 清理；任何文件已发起下载都不误报为已保存。

## P2：体验与架构

### P2.1 备份进度、下载确认与恢复错误的清晰状态（原路线图 P2-B）

**当前状态：** 核心备份/恢复协议已存在。路线图仍要求进一步区分校验、哈希、打包、可下载、下载已发起、用户确认文件可见、恢复校验和恢复提交；这些界面状态不能代替 P1 数据正确性。

**入口：** src/components/PersonalDataSettings.svelte；src/lib/personal/backup.ts、backupVolumes.ts；docs/interaction-experience-roadmap.md 的 P2-B。

**依赖：** P1.3 通过；沿用现有备份预算，不改变快照格式，避免破坏 v1/v2 兼容。

**边界：** 进度必须来自真实已处理 bytes/assets/chunks/volumes，不能由 timer/CSS 伪造；浏览器不能报告下载最终落盘；取消已发起下载不能声称撤回；错误要给可恢复路径。

**验证：** 慢速/失败/取消生成与恢复；实际文件选择；缺失卷提示和单卷重试；读屏状态；预览后并发写入；320、390、768 和桌面视口检查。

**完成门槛：** 每个 UI 状态与实际 helper 状态对应；文件存在仅由用户确认；错误可重试；状态播报准确；P1.3 所有数据不变门槛继续通过。

### P2.2 播放器 capo 与全屏设置交互（原路线图 P2-C）

**当前状态：** 原路线图识别出全屏设置的 capo 操作绕过统一 render/MIDI reload 流程，设置触发器缺少展开语义，小控件命中区不足；Mac 页面尚未验收。

**入口：** src/components/player/ScorePlayer.svelte 中的 selectCapo、withRenderPreservingPosition、fullscreen settings；docs/interaction-experience-roadmap.md 的 P2-C。

**依赖：** P1.1 的播放器状态/位置证据；不另加播放器动效控制器或运行时依赖。

**边界：** capo/调性命令需走原有 render/MIDI 串行边界并保留播放位置；设置面板开合不暂停声音；Esc 先关内层设置再退全屏；失败不能显示未应用的选中值。

**验证：** 播放中分别从普通工具栏和全屏设置换 capo/转调，核对 MIDI、tick、倍率与播放状态；覆盖原生 Fullscreen 成功/拒绝、Safari CSS fallback、系统手势退出、快速连续点击和卸载。

**完成门槛：** 位置与音频状态正确保留；实际应用值与 UI 一致；焦点、监听器和小屏控件有浏览器证据；目标 Safari/真机结论单列，不继承 Chromium 结果。

### P2.3 曲库筛选与结果反馈（原路线图 P2-D）

**当前状态：** 服务端 query string、筛选、结果、空态、演示与不可用状态已有代码；待办集中于动效预算、可访问状态与多视口边界，不重写客户端路由。

**入口：** src/components/TabCardGrid.svelte、src/components/FilterBar.astro、src/pages/tabs/index.astro、src/pages/ukulele/index.astro、src/pages/searchResults.astro；docs/interaction-experience-roadmap.md 的 P2-D。

**依赖：** P0.3 的真实曲库状态或诚实演示/不可用模式；保留 Astro 多文档和 query 参数契约。

**边界：** URL 仍是查询状态唯一来源；不得把当前服务端页伪装成全库客户端筛选；保留浏览器返回、分页、demo/unavailable/empty 区分；转场不等待音频停止或用户导航。

**验证：** 搜索、筛选、排序、分页、刷新、复制 URL、返回/前进、新标签，以及空/演示/数据库不可用路径；检查减少动态模式、键盘、触摸和窄屏横向溢出。

**完成门槛：** 新 URL 与服务器结果一致；没有错误状态被隐藏为动画或空列表；键盘/触控可达；窄屏无整页横向溢出。

### P2.4 围绕稳定边界的架构拆分

**当前状态：** 个人数据已有 repository/validation/backup/practice helper 边界，播放器也有音频焦点、加载、音源和 session writer helper；较大的 Svelte 组件仍承担部分接线。架构拆分不是迁移首要任务。

**入口：** src/components/player/ScorePlayer.svelte、src/components/practice/PracticePanel.svelte、src/components/PersonalPractice.svelte、src/lib/player/、src/lib/practice/、src/lib/personal/；docs/platform-development-plan.md、docs/architecture-and-fragments-plan.md。

**依赖：** P1.1—P1.3 的实际行为验收；先指出重复状态/责任冲突或 macOS 特有失败。

**边界：** 不更换 Astro/Svelte/AlphaTab，不引入全局状态库或微服务；不在没有回归夹具时做大规模“顺手整理”；领域逻辑优先于组件视觉层，稳定 IndexedDB 与备份契约不得改变。

**验证：** 对拆出的行为建立可隔离的单测，再跑相关练习、工坊、备份回归；用真实页面确认播放器不重挂载、不乱序保存、不丢音频焦点。

**完成门槛：** 责任归属更清楚、代码范围可回滚、核心行为证据不退化；提交说明解释为什么该次拆分解决了已观察问题。

## P3：长期门槛与按需扩展

### P3.1 多设备、辅助技术与音频真实环境

**入口：** 当前播放器、练习、工坊、移动菜单和动效组件；docs/platform-development-plan.md 的三端标准、docs/platform-backlog-and-acceptance.md、docs/interaction-experience-roadmap.md 的 P3。

**依赖：** P0 及 P1 核心流程稳定；可用的 iPhone/iPad Safari、Android Chrome、Mac Safari/Chromium 与实际输入/输出设备。

**边界：** Chromium 视口模拟不算触屏验收；静态截图不证明虚拟键盘、pointercancel、读屏、音频焦点或真实听感；减少动态模式单独测试。

**验证：** 目标分辨率与横竖屏；实际触摸、旋转、软键盘、焦点恢复、屏幕阅读器、200% 放大；完整练习/工坊/恢复；真实音频输出、单一音频焦点和页面离开。

**完成门槛：** 每个设备及 OS/browser 版本有独立记录；核心流程全通过或具体限制被产品明确呈现；设备缺席时标未执行。

### P3.2 受控长测与大数据量压力

**入口：** src/lib/practice/practiceSessionWriter.ts、src/lib/personal/backupVolumes.ts、src/lib/player/、tests/personal-backup-budget.test.mjs；对应的练习与备份证据目录。

**依赖：** P1.1 和 P1.3；持续可观察的桌面与移动设备会话；安全的隔离资料夹具。

**边界：** 无人观察的超长累计时长不算持续播放；格式允许 1 GiB 不表示真实设备支持 1 GiB；不以一次内存尖峰判内存泄漏或无泄漏。

**验证：** 桌面 2 小时、目标移动设备至少 30 分钟；期间记录播放/暂停/后台/恢复、每条 session slice、曲目切换及音频焦点；多次导入/导出大附件，监测实际时长、内存和失败回退。

**完成门槛：** 长测连续有观察记录，无叠音、计时重复、失焦继续计时、断点回退或静默数据丢失；容量结论只覆盖实际执行的数据规模和设备。

### P3.3 经用户再次选择后的长期学习扩展

**入口：** 由未来用户访谈单独选择；现有文章/和弦工具以及开发计划 M6 仅作方向参考。

**依赖：** 首个个人练习闭环可恢复，且用户明确选定一个具体扩展目标。

**边界：** 节拍器、调音器、分级教程、课程进度和推荐都不是本次迁移承诺；一次只增加一个可独立验证的个人功能。社区扩张、公开采集、账号同步和全站离线不因迁移而自动进入 backlog。

**验证：** 为被选定功能定义个人使用路径、数据保存边界、失败行为、需要的权限与设备证据，再单独立项。

**完成门槛：** 新需求得到明确选择并形成范围、验收标准和数据/隐私契约；本条本身只表示待确认，不计为开发完成。

## 与原计划的关系

- docs/platform-development-plan.md 的 M0–M6 是完整平台的历史总路线；当前许多核心阶段已有后续实现记录，不能按旧日期状态重新启动或按计划文案宣称全部完成。
- docs/platform-implementation.md 汇总分阶段实现和 Windows 验收；读取时以 2026-10-20 的播放/音色、媒体交付和曲库证据为较新来源。
- docs/interaction-experience-roadmap.md 的 P2-A 工坊交互和 docs/studio-interaction-polish-plan.md 已有独立 Windows 实施记录；本 Backlog 只列 P2-B/P2-C/P2-D 为体验待办。
- docs/catalog-runtime-recovery-plan.md、docs/local-catalog-startup.md 与 docs/mac-handoff-plan.md 的数据库、环境恢复门槛仍需对应本次 Mac 包和 dump 的新证据。本次 dump 已在 Windows 独立临时 PostgreSQL 16 容器通过恢复计数检查；Mac 实际恢复、应用 readiness 和资源引用覆盖仍未执行。
- docs/preview-duration-timbre-plan.md 和 docs/evidence/preview-timbre-2026-10-20/ 记录了 Windows 的资源身份及行为检查；Mac 实际听音和目标设备证据仍开放。

## 建议每项完成记录模板

~~~text
任务 ID：
基线/分支/提交：
变更文件：
验证环境（OS、浏览器/设备、Node、Docker、端口）：
命令与退出码：
自动测试（总数、通过、失败、跳过及原因）：
浏览器实际流程：
数据库/媒体/个人备份证据：
设备/实际听音证据：
未执行项与限制：
回退方式：
~~~
