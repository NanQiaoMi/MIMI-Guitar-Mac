# MIMI Guitar：Mac 开发接续指南

日期：2026-10-23（Asia/Shanghai）。本文服务于从 Windows 迁移到 macOS 的本地开发接续。本文记录的是工作区盘点、已有 Windows 证据和待执行步骤；计划、包内清单或脚本存在都不代表相应恢复或 Mac 验收已经完成。

## 接续基线与结论

- 稳定应用源码来源：Windows `master@c0fdccae`；交付包内 `project/source-revision.json` 记录来源提交。为避免携带未经全历史敏感信息检查的 Git 历史，交付源码使用独立干净快照历史，因此 Mac 包内 Git HEAD 不要求等于 `c0fdccae`。迁移工作在 `chore/mac-development-handoff` 的隔离工作树进行；Mac 的业务开发应从交付包中明确的稳定代码和 Git 状态开始。
- 项目使用 Astro 5、Svelte 5、Tailwind CSS 4、AlphaTab 1.8.4、Prisma 6.19.3 与 PostgreSQL 16。package.json 只接受 Node.js 24.x（>=24.0.0 <25）。保留 package-lock.json，Mac 重新安装依赖并本机生成 Prisma Client；不要带 Windows 的 node_modules、dist、.astro 或运行时 .env，也不要升级依赖来完成迁移。
- 交付包以顶层 `START-HERE.md` 为入口，包含稳定项目 `project/`、`PACKAGE-MANIFEST.json`、通用备用校验 `SHA256SUMS`、包外 ZIP 摘要 `zip.sha256`、数据库 dump/metadata，以及隔离保存的 `preserved-work/` 候选工作。以实际包清单和入口文档为准；候选工作不覆盖稳定源码。
- 稳定 Windows 源码验证的 npm test 为 523 项：516 通过、7 跳过、0 失败。跳过项精确来自 tests/search.test.mjs 的 5 个查询测试及 tests/sheetform.test.mjs 的 2 个数据库查询测试；每个文件先尝试 db.tab.count()，连不上当前配置数据库时默认 skip，REQUIRE_TEST_DATABASE=1 时则报错而不会 skip。这个结果只说明当次全量测试没有配置可用的独立测试库，不足以推断 Docker 当时不可用；2026-10-20 的 Docker 状态记录为健康。npm run typecheck 与 npm run build 均为 0 errors；静态检查保留 57 条 Svelte warnings（18 个文件）和 40 条 Astro hints。以上是 Windows 证据，不能代替 Mac 的重新执行。
- 稳定 Windows `public/storage` 盘点为 32,595 个文件、554,546,235 字节；其中包含 12,118 个 IBE、16,210 个 JPG、4,123 个 JSON 和 131 个 SF2 文件。全量数据库引用检查发现：12,106 条 `scoreUrl` 中，稳定目录已有 12,102 条，另有原目录独有的 4 份；4,127 条 `xheUrl`、16,220 条 `screenshotUrl` 均在稳定目录存在，另有 13 条无截图但非 missing 记录；无外链、非法路径或两边都缺失的资源。原目录新增的 10 个不同文件全部隔离保存在 overlay 作候选，其中被引用的 4 份会额外补入包内稳定媒体；不覆盖现有文件，也不改 Windows 原媒体，因此包内稳定目录为 32,599 个文件、555,536,315 字节。最终媒体数/字节数以包根 `reports/media-inventory.json` 和 `PACKAGE-MANIFEST.json` 为准；全引用核对见包根 `reports/catalog-resource-coverage.json`。标准 GM Sonivox SF2 另有 1,351,896 字节。所有计数都不能替代逐文件 SHA-256 核验。
- 新鲜 database/catalog.dump 已导出，大小 1,235,838 字节，SHA-256 为 7f709c83bf7d43d18d9a92ebf8b08a9dd1ddbbf6dc1cbe3173611f96168c71a1。快照有 16,233 条 Tab、8 条 Article、4 条 migration；User、Favorite 和 UploadRecord 表结构存在，但均为 0 行。快照已在无网络、tmpfs 隔离 PostgreSQL 16 容器中成功恢复并核对计数，临时测试容器已删除。Mac 上的恢复仍未执行；打包时仍需用清单核对 dump 摘要，不能把 Windows 隔离恢复记录写成 Mac 通过。
- 已确认标准 GM 使用完整 Sonivox 音源；尤克里里通过隔离 preset 配置。相同 bank/program 的混合来源冲突会显式阻断。Windows 上的文件身份、加载和浏览器状态已验；目标设备上的实际听音与 Mac/手机/平板真机播放仍未验收。

## 产品范围：沿用六轮决定

| 访谈 | 已确认的选择 | 接续时的产品约束 |
| --- | --- | --- |
| 1 | 个人练琴、自学使用 | 优先做可靠的找谱、练习、记录和恢复，不把教师、班级或社交加入首期。 |
| 2 | 单设备本地资料，完整备份与恢复 | 个人工程、收藏、待练、练习历史、附件和断点属于浏览器 IndexedDB；没有账号云同步承诺。 |
| 3 | 个人曲库与个人文件导入 | 保留现有联网曲库和私有导入，不扩大社区采集、公开投稿或 AI 识谱范围。 |
| 4 | 电脑、平板、手机 | 三类设备的关键流程都要可靠；桌面 Chromium 视口不代表 Safari 或真机通过。 |
| 5 | 待练、A-B 分段、逐步提速、练习记录和继续上次 | A-B 用展开后的演奏 tick；提速只在完整一圈后推进；恢复默认暂停，需要用户明确继续。 |
| 6 | 联网找谱，离线时明确提示缺资源 | 断网下已下载的个人资料可以备份或打开；曲库、未下载谱和音源仍可能不可用，不承诺整站离线。 |

练习时长表示页面可见、当前标签持有音频焦点且引擎实际播放期间的可观察时长，不代表识别了真人演奏。不要添加麦克风评分或“已掌握”的自动判断。

## 先读的源码与证据

| 主题 | 主要入口 | 必读文档与证据 |
| --- | --- | --- |
| 页面和产品入口 | src/pages/library.astro、src/pages/practice.astro、src/pages/settings/data.astro、src/pages/studio.astro | README.md、docs/platform-development-plan.md |
| 本地个人数据、导入、附件和备份 | src/lib/personal/、src/components/PersonalLibrary.svelte、src/components/PersonalPractice.svelte、src/components/PersonalDataSettings.svelte | docs/personal-data-contract.md、docs/evidence/personal-platform-2026-10-15/、docs/evidence/practice-correctness-2026-10-18/ |
| 练习播放、A-B、提速、恢复 | src/components/player/ScorePlayer.svelte、src/components/practice/PracticePanel.svelte、src/lib/practice/、src/lib/player/ | docs/practice-playback-contract.md、docs/architecture-and-fragments-plan.md、docs/evidence/practice-touch-2026-10-19/、docs/evidence/playback-repair-2026-10-20/ |
| 制谱工坊与格式 | src/components/studio/、src/lib/studio/、src/lib/gpUpload.ts、src/lib/ibe.*.ts | docs/score-studio-development.md、docs/studio-format-and-hit-testing.md、docs/studio-interaction-polish-plan.md、docs/evidence/studio-interactions-2026-10-17/ |
| 曲库、数据库和媒体 | src/lib/catalogReadGate.ts、src/lib/tabQuery.ts、src/lib/server/readiness.ts、prisma/schema.prisma、prisma/migrations/、public/storage/ | docs/local-catalog-startup.md、docs/catalog-runtime-recovery-plan.md、docs/score-resource-delivery-plan.md、docs/evidence/catalog-runtime-2026-10-20/、docs/evidence/score-resource-delivery-2026-10-19/ |
| GM、音色与播放资源 | src/lib/player/scoreInstrument.ts、src/lib/player/scoreInstrumentOverrides.ts、src/lib/player/verifiedScoreSoundfont.ts、src/lib/player/scoreAuditionResources.ts | docs/preview-duration-timbre-plan.md、docs/evidence/preview-timbre-2026-10-20/、docs/third-party/sonivox-soundfont/ |
| 页面动效与后续体验 | src/lib/ui/、src/components/ui/、src/components/TabCardGrid.svelte | docs/interaction-motion-plan.md、docs/interaction-experience-roadmap.md、docs/evidence/expressive-motion-2026-10-18/、docs/evidence/fast-navigation-2026-10-19/ |

较早的计划和证据保留了曾经失败的尝试、基线问题与迭代快照。判断当前状态时，优先看对应文档中日期较新的“最终验证”“交付”记录，并核对记录中的来源版本是否对应 `project/source-revision.json`；不要要求其 commit 与 Mac 快照 HEAD 相同，也不要从历史计划的勾选项或旧截图推断当前环境已恢复。

## Mac 安装与本地启动

交付包安装依赖需要访问锁文件中记录的实际 `resolved` 镜像（其中有大量 `https://repo.huaweicloud.com/repository/npm/` URL）和 Prisma 引擎分发服务；需要数据库时还要拉取 Docker 镜像。此交付不是免网络安装包。单改 npm 默认 registry 不一定会覆盖 lockfile 中的 `resolved` 地址。若镜像/引擎网络访问失败，记录实际失败 URL 与错误类别，不要升级依赖或重写锁文件绕过；更换镜像须作为独立变更，审查完整 lockfile 并重做安装、测试和构建验证。Apple 芯片和 Intel 芯片须选匹配的 Node、Docker Desktop 构建，不共用 Windows 可执行文件。

官方参考：

- [Node.js 24.x 官方发行归档](https://nodejs.org/en/download/archive/v24.22.0)：按 Mac 芯片选择 darwin arm64 或 x64；只满足项目的 24.x 引擎范围，不改 npm 依赖。
- [Docker Desktop for Mac 安装说明](https://docs.docker.com/desktop/setup/install/mac-install/)：根据芯片安装对应版本。macOS 权限、条款和首次启动由设备使用者处理。
- [Prisma 系统要求](https://docs.prisma.io/docs/orm/reference/system-requirements)：保留锁定的 Prisma 6；Mac 本机执行 generate，不复用 Windows Prisma 引擎。

先在迁移包顶层阅读 `START-HERE.md`。下载后先核对包外 `zip.sha256`；解压后在包根执行 portable root 校验：

~~~sh
node project/tools/verify-handoff.mjs --root .
~~~

该检查校验 `PACKAGE-MANIFEST.json`、清单记录的文件路径/字节数/SHA-256 和包结构；根 `SHA256SUMS` 是通用备用校验文件。校验全部通过后再进入 `project/` 并运行 `install`。Mac 源码是独立干净快照历史；`project/source-revision.json` 记录来源提交，Mac 当前 Git HEAD 不要求等于 Windows SHA 或 `c0fdccae`。

~~~sh
cd "<迁移包>/project"
node tools/mac-bootstrap.mjs --help
node tools/mac-bootstrap.mjs doctor
node tools/mac-bootstrap.mjs install --dry-run
node tools/mac-bootstrap.mjs install
node tools/mac-bootstrap.mjs dev
~~~

迁移 CLI 命令为 doctor、install、build、dev、start、restore-catalog、help。除 doctor/help 外，命令支持在子命令后追加 `--dry-run`；restore-catalog 的 dry-run 会校验 dump/metadata SHA、Docker、端口及已有资源，但不写配置或启动容器，也不检查 archive TOC；其余 dry-run 只显示将执行的动作。install 执行 npm ci --include=dev 和 npm run prisma:generate；build 调用 npm build 脚本，start 直接运行 `dist/server/entry.mjs`。显式包含dev依赖，即使外部NODE_ENV或omit默认值为production/dev也保留本地工具；Prisma使用项目锁定脚本，不通过npx缺失回退获取新版本。不要用 npm install 或 npm update 改写锁文件。可用 `node -p "process.platform + ' ' + process.arch"` 确认当前是 darwin arm64 或 darwin x64，`node -v` 应处于 24.x。

Docker Desktop 必须已按脚本所需启动。Mac Compose 独立使用 project `mimi-guitar-mac-dev`、容器 `mimi-guitar-mac-dev-db`、卷 `mimi-guitar-mac-dev-data`、PostgreSQL 16，并只绑定 `127.0.0.1:15433`；不复用 Windows 的 `mimi-guitar-pg`。如果该端口或服务端口冲突，先停止并确认占用来源；脚本拒绝冲突，不应自行换名或改端口。`dev` 固定服务于 http://127.0.0.1:4321，`start` 服务于 http://127.0.0.1:4336。`build`、`dev`、`start` 都由 wrapper 注入本机 `.env.mac.local` 环境；不要直接运行 `npm run start` 来代替 `start`，因为它不会注入该文件。`restore-catalog` 建立本机 `.env.mac.local`，其中只保存新生成的本机随机开发口令，权限设为 `0600` 且由 Git 忽略；之后 `build`/`dev`/`start` 读取并只向子进程注入本地数据库配置；`install` 不创建该文件。不要复制配置进交付包、提交 Git 或输出到诊断报告。新口令只留在本机。

public/storage 有约 32.6K 文件；开发服务器若扫描很慢，可用 project wrapper 的 build/start 运行已构建 Node 服务。build 会在 Mac 本机重新生成 dist；不要使用 Windows 的 dist，也不要绕过 wrapper 直接启动生产进程。

/api/health 仅代表进程存活；/api/readiness 另行检查数据库、迁移、曲库状态、抽样资源和基础音源。没有恢复真实曲库时 readiness 未就绪是诚实状态，演示曲谱只可标记为演示。不要因页面 HTTP 200、播放器控件出现或音源文件存在，就报告完整曲库恢复成功。

## 数据恢复：两种数据需要分别处理

### 浏览器个人练习资料

完整个人资料必须从 Windows 上实际存有练习数据的浏览器打开 MIMI Guitar 的 /settings/data，使用应用备份功能导出。PostgreSQL dump 不包含 IndexedDB 中的个人工程、导入原件、待练、收藏、练习历史、A-B 片段、断点和附件。

个人备份格式与硬限制：

- v1 是一个最多 64 MiB 的 JSON 文件。
- v2 包含一个最多 64 MiB 的 JSON manifest 和最多 128 个二进制卷；每卷负载最多 8 MiB；整套文件总计最多 1 GiB。
- v2 必须一起保存 manifest 与全部卷。每个下载按钮只表示浏览器已收到下载请求；用户须在下载文件夹核对每一个文件确实存在。缺卷、混用快照或 SHA 不匹配时不得当作完整备份。
- 1 GiB 是格式上限，未在真实 Mac 或完整 1 GiB 设备上验证。

在 Mac 上先用新的浏览器配置文件做恢复预演，避免与已有资料混在一起。验证后建议长期固定使用 http://127.0.0.1:4336；dev 的 127.0.0.1:4321 是不同 origin，适合独立开发，不用于承载同一份练习资料。协议、host、port 任一变化都会切换 IndexedDB 空间；同一 origin 在不同浏览器或不同浏览器 profile 中仍各自隔离。通过 UI 选择完整备份集、完成校验与预览，再确认恢复；确认后检查曲目数、工程、附件、待练、会话和断点，并实际打开一份导入谱和一份工坊工程。恢复后再导出一次作往返检查。失败、取消、缺卷、配额不足或预览期间发生新写入都应保持旧资料不变；不要为排错清空原浏览器数据。

### 联网曲库数据库

只有交付包中确实有 `database/catalog.dump` 和 `database/catalog-metadata.json`，并且包级清单校验通过，才运行以下恢复：

~~~sh
cd "<迁移包>/project"
node tools/mac-bootstrap.mjs restore-catalog --dry-run
node tools/mac-bootstrap.mjs restore-catalog
~~~

metadata 必须声明 `postgresMajor=16`、dump 的 `sha256`，以及 `counts.tabs/articles/migrations`；本次预期分别为 16,233、8、4。`restore-catalog` 会流式校验 dump SHA-256，并与 package 内 metadata/固定预期核对；再检查 PG custom archive 的 TABLE DATA 白名单只含 `Tab`、`Article`、`_prisma_migrations`，且三表都在。恢复到脚本新建的隔离数据库后，脚本核对行数与 metadata 完全一致、4 条 migration 均已完成且无未完成 migration，并确认 `User`、`Favorite`、`UploadRecord` 均为 0 行。恢复目标使用 Compose project `mimi-guitar-mac-dev`、PostgreSQL 16、本机独立卷；默认容器 `mimi-guitar-mac-dev-db`、volume `mimi-guitar-mac-dev-data`、端口 `127.0.0.1:15433`。不能对已有数据库运行 `--clean`、drop、覆盖或其他破坏性恢复。`restore-catalog --dry-run` 检查 dump/metadata SHA、Docker、固定端口及现有目标资源，不写配置或启动容器；它不检查 archive TOC。若恢复在资源创建后失败，脚本保留新建容器/卷供手动检查，不会自动删除或清理；检查其状态后再决定如何处理。路径或目标不清楚时停止，保留 dump 并记录为未恢复。若 dump 缺失、摘要不匹配或恢复失败，继续使用不带完整曲库的本地演示状态，不从旧快照或公共来源猜测补齐。

应用页面可启动不等于目录数据库可用；readiness 应在数据库迁移和曲库检验后才可能变为 ready。不要在真实或 Windows 原数据库上测试 Mac 的 restore 脚本。

## Mac 首轮检查顺序

在 Mac 完成以下工作并留下不含秘密的结果记录：

1. 在包根验证 `zip.sha256`，解压后运行 `node project/tools/verify-handoff.mjs --root .`；核对 `PACKAGE-MANIFEST.json` 的文件数、字节数和逐文件 SHA-256，并确认 `database/catalog-metadata.json` 的 Postgres 主版本、dump SHA 与计数。只看总量或抽样不能替代完整清单。
2. 确认 Node 24.x 与正确架构；阅读 help/doctor，再用 install --dry-run 预览。install 成功后确认 npm ci 和 npm run prisma:generate 已由 wrapper 执行且锁文件未变。如果依赖安装受阻，记录锁文件实际 resolved URL/Prisma 引擎分发请求及错误类别，不改锁文件或升级依赖绕过。
3. 运行 `npm test` 并记录退出码、跳过项、warning/hint。Windows 全量结果中的 7 个数据库 skip 来自 `tests/search.test.mjs` 的 5 项及 `tests/sheetform.test.mjs` 的 2 项；各文件先调用 `db.tab.count()`，数据库连接不可用时 skip，若 `REQUIRE_TEST_DATABASE=1` 则直接失败。它们不能证明 Docker 不可用。若配置独立 `mimi_platform_test` 并运行 `npm run test:db`，连接失败就是失败，不能当作通过。
4. 运行 `node tools/mac-bootstrap.mjs restore-catalog --dry-run`，确认目标空闲后执行真实 `restore-catalog`，核对 metadata 与摘要/计数；该步骤创建隔离数据库和 `.env.mac.local`。bootstrap 的 `build`、`dev`、`start` 要求该配置存在，因此在恢复失败时不要手工伪造连接信息来继续，也不要把 app build/runtime 记作通过。
5. 按顺序执行 `node tools/mac-bootstrap.mjs build` → `npm run typecheck`，记录真实退出码；build 会维护生成类型，勿与 typecheck 并行。确认实际 dist/client/storage 与包内资源一致；打开真实曲谱，分别验证吉他、尤克里里、未知资源和资源缺失状态。正式页面不能含测试夹具。这样项目检查顺序为 `npm test` → wrapper build → typecheck，数据库恢复是 build 的先决准备。
6. 用 wrapper dev 验证 127.0.0.1:4321，或用 wrapper build/start 验证 127.0.0.1:4336；确认页面、静态资源、health、readiness 与真实数据源各自的结果。用长期 origin 的 profile 恢复私人浏览器备份，验证一份练习和一份工坊工程。
7. 在 Mac 目标音频输出设备上实际试听原谱有效轨道，并尝试短时切换、暂停、焦点交接和恢复。页面处于 playing、tick 推进、SoundFont 请求成功只能证明这些软件状态，不能证明实际听到了正确音色。

## 未合并 Windows 工作与 Git 接续

原 D:/MIMIguitarweb 存在 402 项未提交状态。它不是稳定基线，不能用整目录覆盖稳定源码；迁移包将把经筛查的候选内容独立放入 `preserved-work/`，并在该目录的 `manifest.json` 中记录状态、排除项和摘要。候选内容要逐项读 diff、分类、和稳定源码比较；不能把“已被打包”写成“已合并”或“功能已完成”。

源码包不带未经全历史敏感信息检查的 Git bundle，而是提供独立干净快照历史和 `project/source-revision.json` 追溯来源提交；包根 `reports/source-export.json` 记录稳定来源 revision、`excludedPaths`、`.env.example` 去值处理及未携带旧 history 的事实。迁移包不包含旧 `docker-compose.yml` 和 9 份历史运维/验证脚本；Mac 使用独立 `project/docker-compose.mac.yml`。这些排除与模板变换只反映在迁移包中，原 Windows 仓库文件不改。不要要求 Mac 当前 Git HEAD 等于 Windows SHA、原始 `c0fdccae` 或其他绝对 commit；`source-revision.json` 是包内源码来源的证据。把快照初始化成独立干净 Git 基线后，在其上创建功能分支。`preserved-work/` 是隔离候选快照，绝不自动覆盖稳定源码；逐项审阅和验证后才可摘取需要的改动。没有远端时不推送、不配置远端、不发布。

用户给出的全局 AGENTS 规则可作为后续协作建议：先检查 branch、status 和交付规则；大项在隔离分支修改，保留现有改动，按变更执行匹配检查，准确区分测试、浏览器、设备、音频和数据库证据，功能完成后更新文档。此段是接续说明，不在仓库新增 AGENTS.md，也不自动向工具或模型写入新约束。

## 可复制的 Mac 接续代理提示词

~~~text
请在这份 MIMI Guitar Mac 迁移包中继续开发。先读 START-HERE.md、docs/mac-development-handoff.md、docs/mac-next-development-backlog.md，以及所选任务链接的原始计划和验收证据。先在包根运行 `node project/tools/verify-handoff.mjs --root .`，查看 `project/source-revision.json`、Git 状态、Mac 环境、媒体清单和数据库 dump/metadata；不要要求 Git HEAD 等于 Windows commit，也不要假设迁移计划已完成。

保持用户六轮决定：个人练琴；个人资料单设备本地并支持完整备份恢复；保留个人曲库和导入，不扩大社区采集；电脑/平板/手机关键流程可靠；待练、A-B、逐步提速、练习记录与继续上次；联网找谱、离线清楚显示缺资源。不要把计划或 Windows 通过记录说成 Mac 已验收。

选择 P0/P1/P2/P3 中一个有边界的 backlog 项，先说明其代码入口、依赖和完成门槛，然后从独立功能分支完成最小改动与匹配检查。保留用户原有修改，不读取/输出秘密，不接触 Windows 原数据库或覆盖其文件。不得升级依赖来绕过安装问题。恢复 PostgreSQL 只允许使用迁移工具创建的 `mimi-guitar-mac-dev` 隔离数据库；浏览器个人资料必须通过应用完整备份恢复。Mac/Safari/实际听音/真机证据与离线单测分别记录；不存在的证据标为未执行。

完成时列出变更文件、分支与提交、实际验证命令/退出码、数据库跳过原因、Mac 设备与声音的实测范围、尚未完成项。不要推送、创建 PR、发布或部署，除非我另行明确要求。
~~~

## 迁移后需要关闭的检查项

- [ ] 交付包完整性清单通过；媒体数量、字节数、SHA 与清单吻合。
- [ ] Node 24.x、npm ci、Prisma generate、Mac 单测、类型检查和构建结果已记录。
- [ ] Mac 数据库 dump/metadata 摘要与计数已通过校验，隔离恢复结果已明确记录；Mac 未恢复时仍保留为未执行。
- [ ] 浏览器 v1 或 v2 个人资料完整恢复，逐卷文件在设备可见，并通过打开/重新导出核对。
- [ ] 至少一条真实吉他谱和一条尤克里里谱可读；音源实际听音结果与资源状态分开记录。
- [ ] macOS Safari、目标手机/平板、长时播放与 1 GiB 备份等未测门槛没有被写成通过。
