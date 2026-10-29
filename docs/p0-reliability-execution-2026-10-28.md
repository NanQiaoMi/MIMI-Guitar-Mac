# MIMI Guitar 可靠性优化：分工、执行与验收

日期：2026-10-28（Asia/Shanghai）。本记录承接优化任务，先校准当前实现，再按风险组织增量修复。它与[当前进度报告](../project/PROGRESS_REPORT_WEEK1.md)取代原计划中未经复核的完成百分比、错误数和时间估算。

## 目标与完成条件

本批目标是修复实际发现的音频解锁、草稿保存、备份校验和错误提示问题，使当前工作区可以通过现有检查。完成条件是生产调用链上的行为被直接验证、检查退出码明确、既有改动保留；不以新增文件数量衡量完成度。

本批没有更换框架、升级依赖或引入另一套状态/数据层。长期功能与性能目标在测量后重新排序，不能直接沿用 10 月 15 日审计。

## 基线保护与模型分工

真正的 Git 根目录是父工作区下的 `project/`。起点为 `master@10b900a`，已有源码、计划、测试和原生应用的未提交改动。本轮建立 `codex/p0-reliability-20261028` 分支，保留原改动；开工时的 20 份 Web 改动另存于系统临时目录，原生应用目录没有纳入编辑范围。

主智能体负责范围、依赖、接口、关键实现、审查和最终验收。三个子智能体全部使用用户指定的 `gpt-6-luna / max`，按独立文件所有权执行；同一文件没有交给多个子智能体同时改写。

| 工作单元 | 负责人 | 文件所有权/输入 | 交付与验收 |
| --- | --- | --- | --- |
| 接入盘点 | Luna A，只读 | 新增音频焦点、事务、备份、错误模块及现有调用点 | 区分生产模块与未接入原型；指出测试复制实现和摘要契约错误 |
| 打印类型与 Mac 夹具 | Luna B | `printScore.ts`；之后独立负责 `score-resource-files.test.mjs` | 保留已有打印扩展，持有非空 renderer；canonical tempdir，保留符号链接拒绝测试 |
| 音频安全回归 | Luna C | `audio-unlock-safety.test.mjs` | 直接导入生产注册表，先复现第四个 context 未解锁，再验证修复 |
| 草稿保存回归 | Luna C | `studio-local-persistence.test.mjs` | 单次写入、配额失败原字节不变、遗留备份合并/回退及显式删除 |
| 备份真实回归 | Luna A | `backup-integrity.test.mjs` | 使用真实导出器生成双分卷，验证篡改、缺卷、乱序、计数、引用与只读边界 |
| 错误响应兼容 | Luna B | `errorBoundary.ts`、`FavoriteList.svelte`、`error-boundary.test.mjs` | 旧字符串/新对象错误均可读；HTTP 成功但 `ok:false` 不移除收藏 |
| 音频/草稿关键实现 | 主智能体 | `audioUnlocker.ts`、`localScorePersistence.ts` | 每个 context 独立去重，单键原子提交，保留其他工程 |
| 备份整合及交叉复核 | 主智能体实现，Luna A 只读复核 | `backupVolumes.ts`、`backupIntegrity.ts` | 结构、摘要、卷头、数据块、附件校验共用；保持恢复暂存与清理边界 |
| 进度校准 | Luna C/Luna B 分别维护周报/路线图；主智能体收口 | 两份独立文档 | 删除无证据数字，未来里程碑改为待验收，最终检查结果由主智能体填入 |

## 实施顺序与结果

1. **先建立基线**。系统 PATH 没有 node/npm，但工作环境附带 Node 24.22.1，无须安装或升级。实际 `tsc` 有 17 项诊断：新增备份校验 13 项、打印 4 项。初始定向测试 32 通过、1 失败；首次全量另发现 5 项 Mac 临时目录夹具失败。
2. **先修行为，再修类型**。音频原实现的全局深度计数覆盖整个异步 resume 生命周期，使第四个独立 context 被跳过。现在使用每个 context 的 pending 集合防重入，后台恢复也经过相同注册表。同步异常或异步拒绝后允许下一次重试。
3. **修正遗留草稿辅助模块的提交边界**。每份草稿使用一次 `localStorage.setItem` 提交，配额失败时由浏览器保持旧值，不再写额外备份键。已有 `_backup` 仍可回读：有效主键优先，坏主键或缺失主键才回退，列表按 ID 合并。显式删除清理匹配 ID 的遗留备份，并保留 ID 恰好带 `_backup` 后缀的其他工程。
4. **统一备份规则**。将生产恢复流程的校验抽为共享函数，清单摘要依据去掉 `snapshotSha256` 的 canonical 内容计算，分卷摘要覆盖负载，另校验块与完整附件。只读诊断不打开 IndexedDB 写事务。结构预检不声称摘要已验证；统计使用 UTF-8 包装清单的实际字节数，并以 `selectedSizesMatch` 明确仅比较数量/长度，删除误导性的完整性分数。
5. **保留恢复安全边界**。恢复预览只暂存校验过的附件；开始暂存后发生异常会清理本次暂存；尚未暂存的结构/摘要错误直接返回。最终提交仍执行 revision 检查，并保留其他本地更改。
6. **修正错误展示**。收藏列表读取新旧错误消息，显式失败不会被当成成功。数据库分类不再扫描 `relation`、`constraint` 等普通消息片段。此响应封装只用于已接入的收藏路径，不宣称所有 API 已统一。
7. **统一验收**。先通过定向回归，再运行全量测试、三种类型检查、生产构建和浏览器冒烟，记录跳过与警告。

## 实际验收证据

所有命令在当前仓库执行，使用 `/Users/mimi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node`，而非不存在的系统 node/npm。依赖版本没有改变。

| 检查 | 实际命令（以下以 `NODE24` 表示上述绝对路径） | 最终结果 |
| --- | --- | --- |
| 全量单测 | `NODE24 --test --test-reporter=tap tests/*.test.mjs` | 566 项：559 pass、0 fail、7 skip，exit 0 |
| TS/Astro/Svelte | `NODE24 tools/check-project.mjs` | exit 0，三者均 0 errors；Astro 40 hints，Svelte 57 warnings / 18 files |
| 生产构建 | `NODE24 node_modules/astro/astro.js build` | exit 0；保留 Prisma 浏览器 external 与 AlphaTab 大分包警告，不称零警告 |
| 空资料备份页面 | 生产构建在本机临时端口运行，浏览器打开 `/settings/data`，点击“准备 v2 分卷文件” | 修订号 1、空资料、清单已生成、0 个附件卷；该页面的浏览器 error 日志为空 |
| 差异保护 | CRLF 感知的 `git diff --check` 及开工快照逐文件 SHA-256 对照 | 本轮未负责的既有 Web 改动保持一致；没有提交、推送、部署或修改原生应用 |

7 项 skip 是 5 项数据库搜索测试和 2 项谱型数据库测试。当前没有运行独立数据库集成验收，不能用退出码 0 代替它们通过。

完整输出保存在忽略目录 `tools/.cache/p0-reliability-20261028/`：`tests.tap`、`typecheck.log`、`build.log`、`sync.log`、`baseline-preservation.json`；[浏览器备份准备截图](../tools/.cache/p0-reliability-20261028/backup-ui.png)对应当前构建。浏览器使用独立本机端口和不可连接的本机测试数据库 URL，没有操作既有曲库或个人资料。只验证空资料准备，不宣称浏览器已下载、恢复了含附件的备份。临时服务与验证标签已关闭。

## 接入边界与后续批次

当前工坊 `ScoreStudioApp.svelte` 实际导入 `src/lib/personal/studioPersistence.ts`，保存经 `repository.ts` 的 IndexedDB 事务；本批 localStorage 修复属于遗留兼容辅助模块，未替换当前工坊后端。现有生产焦点实现是 `src/lib/player/audioFocus.ts`，个人数据事务实现是 `src/lib/personal/repository.ts`。之前新增的 `audioFocusManager.ts` 与 `transactionalStore.ts` 仍未接入，本轮保留原文件，不把它们算作新能力。`backupIntegrity.ts` 是诊断入口，产品恢复通过同一 `backupVolumes.ts` 校验核心执行。既有 `.github/workflows/validate.yml` 未查询远端状态。

后续依赖按下表执行；先核实现有能力，只有发现可复现缺口才安排修改。

| 顺序 | 主智能体决策与整合 | 可分派给 Luna 的独立工作 | 验收条件与依赖 |
| --- | --- | --- | --- |
| 2：服务端真实失败 | 核对 DB 不可用、未知 ID、OMR/上传/文章入口开关与真实持久化边界 | 分别只读审查曲库/上传/文章；确认缺口后按路由划写所有权 | 失败无假成功、不显示替代内容、不丢草稿；只在隔离本机测试数据上验证；不触发付费外部模型 |
| 3：现有练习闭环 | 在既有会话、片段、提速、revision 机制上收敛验收 | 反复/跳房子夹具、刷新续练、多标签竞争专项 | 位置和有效时长正确；恢复保持暂停；并发冲突可见；不另造会话系统 |
| 4：性能基线 | 定义设备、谱源、网络与统计口径，再选择体积/渲染瓶颈 | 资源清单、构建体积归因、可重复的首屏/长谱场景 | 先记录现状及重复测量，再设预算；目前未测 Lighthouse、60 FPS 或覆盖率 |
| 5：真机与大容量 | 组织 iOS Safari / Android、长期播放和完整备份迁移验收 | 测试清单、样本校验和结果整理 | 当前环境无真机，不预先标通过；1 GiB 格式上限不等于设备可用容量 |
| 6：必要的架构工作 | 用前述证据决定是否重构，而非照单引入 XState/tRPC/Vitest | 有独立收益的局部提取与文档 | 兼容已有数据与 API、可回归、无重复状态源；涉及格式变更先确认迁移契约 |

本批完成不表示全部 P0–P3、全设备兼容、数据库回归或性能目标已经完成。
