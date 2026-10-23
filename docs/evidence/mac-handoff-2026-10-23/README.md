# Mac 完整开发迁移验收

2026-10-23 开始制作，2026-10-24（Asia/Shanghai）收口。稳定应用基线 `c0fdccae`，迁移分支 `chore/mac-development-handoff`。Mac 真机未在本环境执行。

## 实际携带范围

- 以稳定应用加本次 Mac 工具/指南为源码来源；全部既有开发计划、数据/播放契约、任务表和验收证据随源码保留。
- `docs/mac-development-handoff.md` 给环境、恢复、源码地图、origin/profile 与接续提示词；`docs/mac-next-development-backlog.md` 逐项列 P0/P1/P2/P3 的文件入口、依赖、边界、验证和完成条件。
- 标准媒体32595份、554546235字节。全量核对16233首曲谱的非空资源引用后，从原目录补齐稳定目录缺少的4份谱；包内 `project/public/storage` 为32599文件、555536315字节。另有标准GM Sonivox文件1351896字节及来源/许可。
- 原目录媒体共32605文件，相比稳定多10个；全部10个独立放入原媒体overlay，其中4个同时用于上述缺失引用补齐，没有替换稳定目录的已有文件。
- 曲库只读 custom dump：1235838字节，SHA-256 `7f709c83bf7d43d18d9a92ebf8b08a9dd1ddbbf6dc1cbe3173611f96168c71a1`。完整表结构，数据只有Tab16233、Article8、迁移4；User/Favorite/UploadRecord不携带数据。
- 原工作区35个已跟踪变更、426个未跟踪文件（普通状态折叠为402项，展开461项）；保留385个候选文件、34份修改基线和只包含这34个文件的binary/full-index差异，76个旧包、机器配置、含静态凭据候选等排除。保存的候选不自动应用到稳定工程。

## 数据库与媒体证据

1. 启动现存Docker时再次遇到`Docker/run/dockerInference`陈旧运行端点不可访问。通过官方CLI停止失败Desktop，仅保留重命名`Docker/run`与只有socket的`docker-secrets-engine`并重建端点目录。保留后缀`mac-handoff-recovery-20261023`；没有重置、删除或移动Docker数据库磁盘、卷、镜像或WSL发行版。
2. 既存`mimi-guitar-pg`恢复healthy后，只读导出并读取非敏感计数；没有在源库运行迁移/写入。
3. 在另建、无网络、数据为tmpfs的PostgreSQL16临时容器中实际`pg_restore --exit-on-error`成功，Tab/Article/迁移数量与快照相同，排除的三表为0。核验容器标签后清理该临时容器；不涉及源库删除。
4. 全量资源引用：scoreUrl12106（稳定12102、原目录补4）；xheUrl4127全部存在；screenshotUrl16220全部存在，另13条无截图引用。无外部URL、非法路径或两目录均缺失的非空引用。存在性覆盖与逐文件SHA不代表逐份乐谱成功解码或人工听音。

## 新增工具与保护

- `tools/mac-bootstrap.mjs`、`tools/lib/mac-bootstrap.mjs` 和 `docker-compose.mac.yml`：doctor/install/restore-catalog/build/dev/start。Node24.x，Darwin；只接受本地Unix socket Docker context，不自动切换context或安装系统软件。
- 新目标固定 `mimi-guitar-mac-dev`，容器`mimi-guitar-mac-dev-db`、卷`mimi-guitar-mac-dev-data`、loopback15433。既有目标/忙端口拒绝；先验证dump metadata/SHA/PGDMP，再校验新目标身份、空库、TOC数据白名单，单事务恢复后精确核对数量和迁移。不会clean/drop、复用Windows容器或清理失败资源。
- Mac本机随机开发口令留在`.env.mac.local`并只通过子进程env传递；`.gitignore`新增`.env.*`保护、保留`.env.example`模板例外。
- `tools/verify-handoff.mjs` 流式逐文件校验清单、长度和SHA，拒绝越界/重复大小写路径、非普通文件/链接以及损坏或缺失文件；最多4个并发流。
- 源码包省略审计发现的9份历史运维/验收凭据脚本及旧`docker-compose.yml`，`.env.example`生成去值模板；不带真实`.env`、原`.git`、旧bundle/dump/部署包、Windows依赖与构建缓存。具体路径、变换与来源记录在包顶层`reports/source-export.json`和`preserved-work/manifest.json`。
- `project/` 初始化独立、无远端的快照Git基线，`source-revision.json`记录原提交；不冒充原历史。包外ZIP SHA、ZIP CRC/内容与包内完整manifest分别验证。无需联网才能核对已有包内容，但安装npm依赖和拉取Docker镜像仍需网络。

## 检查与边界

- Mac bootstrap依赖注入行为测试12项通过，涵盖新目标、existing拒绝、故障保留、SHA/TOC/计数/迁移、远端DOCKER_HOST/context拒绝和doctor；本机没有执行Mac原生恢复脚本。
- 校验工具行为测试5项通过，包括同大小损坏、越界/重复路径、缺失与不符总量、链接和CLI参数。
- 候选全量`npm test`退出0：540项、533通过、7数据库集成因未指向独立测试库而跳过；不在真实曲库执行写入型集成测试。
- 候选`npm run build`退出0，86.03秒；构建退出后单独复核`npm run typecheck`退出0，TS/Astro/Svelte均0错误。既存大chunk/Prisma构建提示、40个Astro hints与Svelte57 warnings（18文件）保留，不把警告/跳过写成无条件全绿。主分支回归和压缩包校验结果由最终包报告记录。
- 压缩包和独立快照的最终提交/计数/校验摘要在包内报告和旁置ZIP摘要文件记录，避免把压缩包自身摘要写进自身形成递归。
- 原目录保护脚本在制作前与交付前检查1025个受保护文件和状态，必须无变化。候选/主分支均需本地提交、no-ff合并并保持clean；不推送/发布/上传。

浏览器IndexedDB中的个人谱、工程、收藏、待练、练习记录、A-B/提速/断点与附件不在项目或PG备份中，用户需在实际原浏览器`/settings/data`导出完整备份集。Mac上的原生安装、Safari、声卡/人工听音、手机平板与长时验收仍是P0及后续门槛，未执行。
