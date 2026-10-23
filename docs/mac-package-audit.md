# Mac 交接包迁移范围与敏感边界审计

审计日期：2026-10-23（Asia/Shanghai）。本记录只审计 Git 元数据、路径、文件大小和允许的源码/配置文本；没有编辑原工作区，没有读取实际 `.env`、私钥、SSH 文件、浏览器 profile、容器环境或 Docker 数据，没有运行构建、测试或服务。

## 仓库与状态

| 范围 | 分支与 HEAD | 跟踪文件 | 工作区状态 |
| --- | --- | ---: | --- |
| 稳定树 `D:\MIMIguitarweb-master-merge` | `master`，`c0fdccae0842` | 949 | clean |
| 交接候选 `C:\Users\Legion\.codex\worktrees\guitar-personal-platform\MIMIguitarweb` | `chore/mac-development-handoff`，`f17bda9f21c4` | 950 | 本审计开始时 clean；之后有其他代理的交接文档、脚本与测试改动 |
| 原 WIP `D:\MIMIguitarweb` | `feature/complete-score-studio`，`f4ac8ece0d1d` | 599 | 未合并内容仍保留 |

候选 HEAD 以稳定 SHA `c0fdccae0842` 为祖先，当前差异只有已跟踪的 `docs/mac-handoff-plan.md`。原 WIP 普通 `git status --short` 有 402 条；展开未跟踪目录后的 `git status --porcelain=v1 --untracked-files=all` 有 461 条，其中 35 条是已跟踪文件变化、426 个是未跟踪文件。两个数字的差异来自未跟踪目录折叠，不代表多出 59 项修改。

原 WIP 的 35 个已跟踪变化包括 19 个应用/配置源码、14 张 `tests/evidence/` 图片、`tools/heal_database_scores.py` 和 `.gitignore`。426 个未跟踪文件按路径/类型/大小元数据分为：48 个源码文件（2,818,018 bytes）、187 个脚本/自动化文件（412,556 bytes）、180 个证据/浏览器捕获文件（103,503,717 bytes）、7 个压缩包或数据库文件（1,408,888,592 bytes）、2 个机器本地配置/大包（493,310,535 bytes）、1 个计划文档（4,381 bytes）和 1 个 `.claude/` 项（187 bytes）。其中 `.playwright-mcp/` 有 35 个浏览器捕获项、5,581,447 bytes。

普通 Git 状态不会列出忽略文件。本审计没有枚举或读取 `node_modules/`、`.astro/`、`dist/`、`.cache/`、构建缓存、Docker volume 或其他忽略目录；这些不属于迁移包输入。

## 源码和配置扫描

扫描目标是稳定树与候选树的跟踪源码/配置，以及原 WIP 当前树的跟踪、已改和未跟踪源码/配置；另扫描了原 WIP 已改源码/配置在 `f4ac8ece0d1d` 的基线文本。候选开始新增 Mac bootstrap 相关文件后，又扫描了 5 个新增脚本/测试文件。扫描只输出路径、行号和类别，不记录匹配值。

使用的启发式类别包括凭据字段后的静态字符串、常见提供商 token、JWT-like 字符串、Bearer 字面量、URL userinfo 和 URL 凭据查询参数。跳过动态 `process.env`、`import.meta.env`、`os.environ`、PowerShell `$env:` 等引用及明确的模板占位词。实际 `.env`、私钥扩展名、SSH/browser profile、容器环境、证据目录、生成文件和超大文件按路径排除；`public/_astro/` 第三方构建产物也未扫描。

稳定树与交接候选树各扫描 414 个允许的源码/配置文件。两边发现相同的 11 个凭据字段静态字符串候选：2 个在部署/数据库工具中，按硬编码运维凭据风险排除；另外 9 个行号命中分布在 7 个 `verify-*` 本地验收脚本中，代码上下文指向本地测试/fixture，但静态值没有作为独立证据证明是纯假值，因此也从迁移源码包排除。

| 类别 | 路径与行号 |
| --- | --- |
| 运维凭据候选 | `tools/apply_accelerated_nginx.py:109`；`tools/heal_database_scores.py:8` |
| 本地验收/fixture 候选 | `tools/verify-m4-shots.mjs:9`；`tools/verify-m4-ui.mjs:43,44`；`tools/verify-m4.mjs:12`；`tools/verify-m5.mjs:12`；`tools/verify-m6-final.mjs:32`；`tools/verify-m7-m2.mjs:48`；`tools/verify-m7-m5m6.mjs:44,64` |

原 WIP 当前树扫描了 486 个允许的源码/配置文件，并扫描了已改跟踪源码/配置的基线文本。共发现 38 个不同的路径/行号：22 个脚本上下文属于 VPS、部署、数据库、同步、上传或远端查询工具，按硬编码运维凭据候选排除；7 个脚本用途不足以证明静态值只是 fixture，也排除；9 个 `verify-*` 本地验收行与稳定树命中相同，按历史验收脚本排除。`tools/heal_database_scores.py:8` 在基线和当前工作树都命中同一位置，只计一个 WIP 路径/行号。

| 类别 | 路径与行号 |
| --- | --- |
| 运维凭据候选 | `deploy-vps.mjs:9`；`tools/apply_accelerated_nginx.py:109`；`tools/apply_nginx_config.py:5`；`tools/apply_vps_nginx.py:5`；`tools/check_nginx_storage.py:5`；`tools/check_vps_health.py:5`；`tools/check-vps-status.mjs:7`；`tools/deploy_code_update.py:18`；`tools/deploy_full_update.py:25`；`tools/export_vps_tabs.py:6`；`tools/fetch_tabs.py:5`；`tools/find_screenshots_vps.py:5`；`tools/heal_database_scores.py:8`；`tools/query_ids.py:5`；`tools/query_top_tabs.py:5`；`tools/query_top30.py:7`；`tools/query_vps_tabs.py:5`；`tools/sync_db_screenshots.py:7`；`tools/test_prisma_query.py:7`；`tools/update_nginx_domain.py:5`；`tools/update_nginx.py:5`；`tools/upload_screenshots_fast.py:8` |
| 其他静态凭据候选，类别未能确认 | `tools/check_null_scores.py:5`；`tools/check_screenshot_urls.py:5`；`tools/check_storage_contents.py:5`；`tools/find_tab.py:5`；`tools/find_wojide.py:5`；`tools/list_all_ukulele.py:5`；`tools/test_sql_exec.py:7` |
| 本地验收/fixture 候选 | `tools/verify-m4-shots.mjs:9`；`tools/verify-m4-ui.mjs:43,44`；`tools/verify-m4.mjs:12`；`tools/verify-m5.mjs:12`；`tools/verify-m6-final.mjs:32`；`tools/verify-m7-m2.mjs:48`；`tools/verify-m7-m5m6.mjs:44,64` |

扫描范围外，后续新增的 5 个 Mac/bootstrap 脚本和测试文件有一个测试 fixture 字段命中：`tests/mac-bootstrap.test.mjs:219`。它位于测试文件，不是运维脚本；动态环境变量引用没有作为静态凭据候选。扫描在其他允许源码中没有发现提供商 token、JWT-like、Bearer 字面量或 URL userinfo/凭据查询命中。以上是启发式筛查，不等于源码和测试数据已逐项人工认证。

### 建议从源码快照和 preserved-work 中排除的文件

以下是去重后的路径清单；原目录中的文件原样保留，只是不复制进交接包。排除原因是静态运维凭据候选、未能证明为纯 fixture 的静态值，或历史验收脚本中的本地固定凭据。不要将这些文件作为 Mac 默认启动/执行入口。

| 排除类别 | 路径 |
| --- | --- |
| 部署/数据库运维凭据候选 | `deploy-vps.mjs`；`tools/apply_accelerated_nginx.py`；`tools/apply_nginx_config.py`；`tools/apply_vps_nginx.py`；`tools/check_nginx_storage.py`；`tools/check_vps_health.py`；`tools/check-vps-status.mjs`；`tools/deploy_code_update.py`；`tools/deploy_full_update.py`；`tools/export_vps_tabs.py`；`tools/fetch_tabs.py`；`tools/find_screenshots_vps.py`；`tools/heal_database_scores.py`；`tools/query_ids.py`；`tools/query_top_tabs.py`；`tools/query_top30.py`；`tools/query_vps_tabs.py`；`tools/sync_db_screenshots.py`；`tools/test_prisma_query.py`；`tools/update_nginx_domain.py`；`tools/update_nginx.py`；`tools/upload_screenshots_fast.py` |
| 未能确认用途的静态凭据候选 | `tools/check_null_scores.py`；`tools/check_screenshot_urls.py`；`tools/check_storage_contents.py`；`tools/find_tab.py`；`tools/find_wojide.py`；`tools/list_all_ukulele.py`；`tools/test_sql_exec.py` |
| 历史本地验收/fixture 脚本 | `tools/verify-m4-shots.mjs`；`tools/verify-m4-ui.mjs`；`tools/verify-m4.mjs`；`tools/verify-m5.mjs`；`tools/verify-m6-final.mjs`；`tools/verify-m7-m2.mjs`；`tools/verify-m7-m5m6.mjs` |

## 历史、旧包与数据边界

稳定、候选和原 WIP 的可达历史元数据都约有 339 个提交、4,531 个可达 Git 对象和 50 个 refs。全历史源码/配置 blob 内容没有完成扫描；路径元数据历史筛查只见 `.env.example`，未见常见实际 `.env`、SSH/private-key 文件名或扩展名。这不足以证明历史提交中没有曾经提交的凭据。交付包应从 `c0fdccae0842` 创建全新快照仓库，不复制原仓库 `.git`、refs 或旧补丁历史；在包内元数据中记录 `baselineSHA: c0fdccae0842`。

原 WIP 的 7 个旧包/数据库文件及文件大小如下，均不应复制或解压：

- `db_screenshots.tar.gz` — 185,865,376 bytes
- `mimi-deploy.tar.gz` — 237,219,840 bytes
- `mimi-guitar-db-live.dump` — 1,240,700 bytes
- `mimi-release-live-20260818-2358.tar.gz` — 63,331 bytes
- `mimi-release-live-20260818-2359.tar.gz` — 472,458,535 bytes
- `mimi-src.tar.gz` — 470,437,909 bytes
- `screenshots_top.tar.gz` — 41,602,901 bytes

另排除原 WIP 的 `mimi.bundle`（493,307,865 bytes）、`nginx-mimi.conf`、`.claude/`、`.playwright-mcp/` 捕获和未审核的 `.zcode/plans/` 文件。它们可能是机器配置、部署包、浏览器状态或历史机器计划，本审计没有读取内容。忽略缓存、Docker volume、`.env` 和私钥均不进入包。

`mimi-guitar-db-live.dump` 只是原目录中的旧 dump 元数据，不作为当前曲库备份。交付所需 PostgreSQL 备份应由主流程重新只读导出并记录时间、schema/table 白名单、计数和 SHA-256；只保留曲库/文章与恢复必需的 schema/迁移记录，排除账号、口令哈希、服务端收藏和上传操作记录。恢复必须落到新建的隔离数据库。

## 可恢复工作建议

以 `c0fdccae0842` 稳定快照作为 `project/` 源码。将原 WIP 以独立 `preserved-work/` 目录/补丁保存，元数据写明基线 `f4ac8ece0d1d` 和分支 `feature/complete-score-studio`；安全源码候选逐文件复制或生成 source-only patch，先排除上述 36 个去重脚本。已改业务组件和新增业务源码可在排除列表外再做路径级 allowlist；不要将 WIP 自动应用到稳定源码。证据图片需先确认没有账号、个人数据或本机路径，再按历史证据标签单独保留。旧包、DB dump、机器配置和浏览器捕获不得作为可恢复输入。

本轮只读完成路径/状态/大小盘点和允许源码的静态候选扫描；没有建立数据库快照、解压包、验证镜像或执行任何脚本。Mac 真机行为、数据库恢复能力、媒体完整性和 ignored cache 盘点仍由主打包流程单独记录。
