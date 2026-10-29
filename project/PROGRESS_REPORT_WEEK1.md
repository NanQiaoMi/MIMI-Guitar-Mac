# MIMI Guitar 优化进度报告（Week 1）

**报告日期**：2026-10-28（Asia/Shanghai）  
**报告范围**：本分支当前工作区中已落地的可靠性修正及实际验证结果。

本报告不沿用旧审计中的完成百分比、覆盖率估计或问题总数作为当前状态。

## 仓库与运行环境

- 仓库根目录：`/Users/mimi/project/mimimusic/MIMI-Guitar-Mac-20261023/project`。
- 本轮起始基线为 `HEAD 10b900a`。原 `master` 上已有的未提交工作予以保留；当前工作在 `codex/p0-reliability-20261028` 分支。
- `node` 不在系统 `PATH` 中；测试使用 Bundled Node.js `v24.22.1`。
- 本轮未提交、推送或部署。

## 本轮实现

- **音频解锁**：`src/lib/audioUnlocker.ts` 按 context 去重 pending resume，并在同步重入时阻止重复调用；移除影响多个独立 context 的全局并发 3 个限制。安全回归测试直接导入生产注册表，不再复制实现。
- **遗留草稿兼容**：`src/lib/studio/localScorePersistence.ts` 成功保存只写一次目标 localStorage key，不新建 `_backup`。读取和列表按草稿 ID 合并遗留备份；有效主键优先，主键缺失或损坏时可从有效备份恢复；显式删除同时清除主键与遗留备份。
- **备份校验**：v2 校验复用真实摘要、分卷、数据块和附件校验路径。诊断保持只读，不写 IndexedDB，也不伪造 `integrityScore`；长度匹配只标为 `selectedSizesMatch`，不代表卷内容已验证。
- **打印处理**：修正 `printScore` 的渲染器引用类型，保留已有原生运行时和导出扩展。
- **收藏失败提示**：前端兼容旧字符串与新结构化错误，HTTP 200 但 `ok:false` 不会移除条目；数据库分类改用明确名称/代码。

## 验证记录

| 项目 | 实际结果 |
| --- | --- |
| 开工时独立 `tsc` | 17 项诊断：`backupIntegrity` 13 项、`printScore` 4 项。 |
| 当前独立 `tsc` | 退出码 0；集成检查结果见下方。 |
| 初始定向测试 | 33 项，32 通过、1 失败。 |
| 当前定向测试 | 44 项，44 通过、0 跳过、退出码 0；覆盖音频解锁、本地草稿、`backupIntegrity` 和 `personal-backup*`。 |
| 首次全量测试 | 6 项失败：5 项受 macOS `/var` 系统 symlink 测试夹具影响，另 1 项为草稿原子写行为。 |
| symlink 夹具专项复验 | 改用 canonical tempdir 后，6/6 通过。 |
| 最终全量测试 | `Node24 --test --test-reporter=tap tests/*.test.mjs`：566 项、559 通过、0 失败、7 项数据库跳过，exit 0。 |
| TS/Astro/Svelte 集成 typecheck | `Node24 tools/check-project.mjs`：exit 0、均 0 errors；Astro 40 hints；Svelte 57 warnings / 18 files。 |
| Build | `Node24 node_modules/astro/astro.js build`：exit 0；保留 AlphaTab 大分包与 Prisma 浏览器 external 警告。 |
| 浏览器冒烟 | 当前生产构建 `/settings/data` 空资料生成 v2 清单成功、0 个附件卷；该页面 error 日志为空。没有验证实际下载或含附件恢复。 |

没有测量测试覆盖率，因此不报告覆盖率百分比。

`.github/workflows/validate.yml` 在本轮前已存在；未查询远端运行结果，不将 CI 描述为本轮新建或已通过。

## 尚未验证

- iOS / Android 真机、1 GiB 备份、长时间运行、性能基线和覆盖率均未测。
- 完整浏览器端到端、数据库集成、声音输出与跨浏览器流程未完成；7 项数据库测试仍为跳过。
- 当前工坊实际保存使用 `src/lib/personal/studioPersistence.ts` → `repository.ts` 的 IndexedDB 事务；本批 localStorage 修正属于遗留辅助模块，不表示切换了当前工坊的保存后端。
- `src/lib/player/audioFocus.ts` 是现有音频焦点实现；新加的 `src/lib/audioFocusManager.ts` 尚未接入生产流程，不计作已交付功能。个人数据仓库 `src/lib/personal/repository.ts` 已有事务式更新；`src/lib/personal/transactionalStore.ts` 尚未接入，不计作已交付功能。

## 后续候选

以下是后续核验方向，不代表本轮确认的故障清单：

1. 当前分支的全量测试、集成 typecheck、build 已完成；下一步补隔离数据库和完整交互验收。
2. 对数据库降级、OMR/上传和文章发布链路做针对性复核；先核对现有 API、仓库和页面实现，再按可复现缺口安排修复。
3. 练习会话、A-B 和提速功能已存在于个人数据模型、`PracticePanel` 与 practice 模块。后续应在现有实现上验证恢复、并发写入和边界行为，不另建一套会话架构。
4. P2/P3 性能与移动体验先补可重复的桌面/移动测量，再依据数据排序优化；当前没有性能或覆盖率基线可用于判定目标达成。

本批分工、命令、验收边界和后续依赖见[执行与验收记录](../docs/p0-reliability-execution-2026-10-28.md)。日志保存在忽略目录 `tools/.cache/p0-reliability-20261028/`。
