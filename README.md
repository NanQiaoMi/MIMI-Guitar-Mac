# MIMI Guitar

> GitHub 公开源码快照：包含 Astro/Svelte Web 项目和 `native-macos/` SwiftUI/AppKit 客户端。原生构建步骤见 [macOS 构建说明](native-macos/BUILDING.zh-CN.md)，公开仓库边界见 [源码发布说明](docs/github-source-distribution.md)。
>
> 此仓库不包含本机数据库、曲库媒体、安装包和授权尚未核实的方正字体。Web 演示可按下方步骤启动；完整原生应用打包前须另外准备曲库和所需资源。历史文档中的构建与验收记录不代表此源码快照已在全部设备通过验收。

吉他与尤克里里曲库、乐谱播放和制谱 Web 项目，最初参考 [guistudy.com](https://guistudy.com/)（谱全了）。当前增加个人曲库、待练、命名 A-B 练习片段、逐步提速、续练、练习回顾和备份恢复。实际实现、验证及未完成的稳定版门槛见[实施记录](docs/platform-implementation.md)。

## 技术栈

- 前端：Astro 5（SSR）+ Svelte 5 岛屿 + Tailwind CSS v4
- 乐谱引擎：官方 AlphaTab（@coderline/alphatab），自研 `.ibe` 解码与播放器定制层
- 后端：Astro 服务端 + Prisma + PostgreSQL（Docker）
- 验收：Node 单测 + Playwright 自动化

## 快速开始

使用 Node.js 24。个人导入和练习资料不依赖账号或服务端数据库写入。

```bash
npm ci
npm run prisma:generate
npm run dev          # http://localhost:4321
```

需要完整联网曲库时，另行准备 PostgreSQL 与谱/音源资源。已有本机 `mimi-guitar-pg` 容器的日常启动使用 `npm run start:local -- --check` 检查，再运行 `npm run start:local`；详细步骤和故障分类见[本机曲库启动指南](docs/local-catalog-startup.md)。检查不创建数据库或运行迁移。仅在明确新建隔离开发库时使用 `npm run db:up` 与 `npx prisma migrate deploy`，不要用它们代替已有曲库的恢复。没有数据库时页面明确显示演示降级；仓库不包含既有曲库媒体文件，不能把演示列表当作已恢复完整曲库。

新工作树也需要独立准备媒体资源。若本机已有原资源，可从其 `public/storage` 只读复制四个公开目录（scores、xhe、screenshots、soundfonts）；个人上传的upload目录不在复制范围。下面的源、目标均须替换成实际绝对路径，且是互不嵌套的两个项目目录：

```bash
# 默认仅预检，已有同名不同内容会失败，不会覆盖或删除文件。
npm run resources:prepare -- --source "D:/existing-project/public/storage" --target "D:/new-project/public/storage"
npm run resources:prepare -- --source "D:/existing-project/public/storage" --target "D:/new-project/public/storage" --apply
npm run build
npm run resources:check -- --source "D:/existing-project/public/storage" --public "D:/new-project/public/storage" --dist "D:/new-project/dist/client/storage"
npm run start
```

准备和核验逐文件检查SHA-256，拒绝链接/junction、空文件、未知类型及路径越界；完整清单写入忽略的 `tools/.cache/score-resources/`。核验失败退出非零，需先恢复缺失资源再交付。`npm run build`、health200或音源齐全不能代替该检查，尤其要确认实际服务的 `dist/client/storage` 包含原谱。媒体不提交Git，不会因检出或合并自动出现。上述命令只处理本地目录；远端发布也必须明确配送媒体，当前仅打包server与client/_astro的旧发布脚本不构成完整媒体交付。

## 个人练习

1. 到 `/library` 搜索真实曲库并加待练，或导入 `.ibe/.gp/.gp3/.gp4/.gp5/.gpx`。个人导入单文件最多30 MiB，原件独立保管。
2. 在 `/practice` 加入待练，设 A/B 和提速参数后可保存命名片段及独立备注；应用时定位 A 点并保持暂停。明确开始练习后，可选择逐步提速、暂停、结束和填写本次练习备注。重新打开后先确认版本，再点击“继续上次”，不会自动发声。
3. 到 `/settings/data` 生成备份，再选择文件校验/恢复。v1单文件 JSON 保持兼容，最多64 MiB；v2使用一个最多64 MiB的JSON清单和最多128个二进制分卷，每卷负载最多8 MiB，所有文件连同卷头最多1 GiB。统一限制单附件30 MiB、引用附件总量927 MiB、500份引用附件和10,000个资料实体；写入与恢复合并都会检查实际分卷数。v2须逐个点击下载清单和每卷；页面只能确认下载已发起，不能确认文件已保存在设备。1 GiB是格式上限，完整1 GiB尚未在真机实测。

所有个人资料属于当前浏览器和站点地址；换浏览器、端口或设备需用备份迁移。未下载的谱和音源在断网时仍可能不可用；首期不承诺整个站点离线。

个人资料 schema 2 增加练习片段，仍可恢复 schema 1 的 v1/v2 旧备份。新备份应使用本版或后续兼容程序恢复；旧程序会拒绝 schema 2。片段绑定实际谱面内容，谱面换版后需重新选区另存。

## 验证

`/api/health` 只报告进程存活；`/api/readiness` 另检查数据库、migration、曲库抽样资源和三个固定基础音源。readiness 不扫描整个媒体库、不联网，且不会返回服务器本地路径；数据库不可用时曲库状态保持未知/不可用。

`npm test` 只发现 `tests/*.test.mjs`。`npm run typecheck` 顺序检查 TypeScript、Astro 和 Svelte；`npm run build` 验证生产构建。数据库不可用时部分旧测试会跳过，必须独立记录。

数据库集成检查使用专用本机数据库 `mimi_platform_test`：设置该库的 `DATABASE_URL`、重放 migrations 后运行 `npm run test:db`。该命令会写入自制目录夹具，拒绝对其他数据库执行；连接失败不允许跳过。`.github/workflows/validate.yml` 配置了独立PostgreSQL服务，但本地配置文件不代表已在GitHub成功运行。

## 文档

- [本机曲库启动指南](./docs/local-catalog-startup.md) — 已有数据库的检查、启动、连接冲突与恢复边界
- [曲库连接恢复计划](./docs/catalog-runtime-recovery-plan.md) — 本轮原因、分工、验证与未完成项
- [练习架构与命名片段迭代](./docs/architecture-and-fragments-plan.md) — 控制器职责、版本兼容、合并边界与验收
- [个人练习平台开发计划](./docs/platform-development-plan.md) — 六轮需求确认、架构、阶段与边界
- [本轮实施与验证](./docs/platform-implementation.md) — 6-luna代理分工、交付范围、证据和后续门槛
- [个人数据契约](./docs/personal-data-contract.md) — 本地实体、事务、迁移与备份边界
- [练习播放契约](./docs/practice-playback-contract.md) — 播放状态、完成记录与断点续练
- [工坊格式与谱面定位](./docs/studio-format-and-hit-testing.md) — 格式边界、导出和真实谱面定位证据
- [现状审计（2026-10-15）](./docs/platform-audit-2026-10-15.md) — 代码证据、测试结果、页面截图与已知问题
- [任务与验收清单](./docs/platform-backlog-and-acceptance.md) — 实施顺序、依赖、故障与三端验收
- [PLAN.md](./PLAN.md) — 历史复刻阶段计划
- [DEV_LOG.md](./DEV_LOG.md) — 开发记录与验收日志
