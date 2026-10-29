# MIMI Guitar 深度优化计划

制定日期：2026-10-28
当前基线：Mac 迁移包 (2026-10-23)
目标：构建稳定、高性能、可靠的个人练习平台

> **2026-10-28 校准**：本计划主要来自 10 月 15 日历史审计，部分功能随后已有实现，不能直接视作当前缺失项。当前分工、修复和验收见[本批执行记录](docs/p0-reliability-execution-2026-10-28.md)及[当前进度报告](project/PROGRESS_REPORT_WEEK1.md)。原时间表与架构选型保留作候选，需根据实际缺口及测量重排。

## 执行摘要

本计划基于 2026-10-15 现状审计和 Mac 接续开发 Backlog，将优化工作分为五个优先级层次（P0-P4），涵盖数据可靠性、性能、用户体验、架构重构和长期可维护性。预计总工作量约 8-12 周（单人），可并行处理不同模块。

### 关键指标目标

| 指标 | 当前状态 | 目标 |
|------|---------|------|
| 可靠性问题 | 历史审计 21 个条目，当前未逐项复核 | 0 个已确认阻断问题 |
| 首屏加载时间 | 未测量 | < 1.5s (桌面) / < 2.5s (移动) |
| 播放器响应延迟 | 未测量 | < 100ms (交互) / < 200ms (音频启动) |
| TypeScript 类型检查 | 本批 TS/Astro/Svelte 均 0 errors，仍有警告/提示 | 保持严格检查，逐项评估警告 |
| 测试覆盖率 | 未测量；本批替换两份复制实现的测试 | 核心路径 > 80% |
| 移动端可用性 | 部分功能受限 | 完整功能等价 |

---

## P0：数据可靠性与核心阻断修复（2-3 周）

**目标**：消除数据丢失、状态不一致和关键操作假成功问题，建立可信基线。

### P0.1 音频系统稳定性 [3-4 天]

**问题**：音频解锁递归溢出（A01）、跨标签焦点混乱（A15）

**实施**：
1. `src/lib/audioUnlocker.ts`
   - 引入解锁状态锁，防止递归 `register→unlock→register`
   - 区分"已请求解锁"与"context 已 running"
   - 按 context 独立去重 pending resume，避免把全局并发数量当作递归深度（本批已修正）
   
2. 统一音频焦点管理
   - 创建 `src/lib/audioFocusManager.ts`
   - 跨标签通信：BroadcastChannel 协调
   - 一次仅一个播放器持有焦点
   - 用户切换时自动暂停非活跃播放器

3. 验收
   - 单测：模拟 suspended → running 转换，验证无溢出
   - 浏览器：平板尺寸工坊连续解锁 10 次
   - 跨标签：详情页→工坊→试听，验证互斥暂停

**文件**：
- `src/lib/audioUnlocker.ts`（重构）
- `src/lib/audioFocusManager.ts`（新建）
- `tests/audio-unlock-safety.test.mjs`（新建）

---

### P0.2 本地存储原子性 [2-3 天]

**问题**：草稿写失败静默损坏（A02）、多存储源不原子

**实施**：
1. IndexedDB 事务包装
   - `src/lib/personal/transactionalStore.ts`
   - 单次操作内：读取→校验→写入→验证，整体回滚
   - 配额失败时保留上一版本，不返回 null

2. 草稿版本链
   - 每次保存记录时间戳和 checksum
   - 保留最近 3 个有效版本
   - 损坏时回退到最近有效版本

3. localStorage + IndexedDB 同步
   - 写入顺序：IndexedDB（主）→ localStorage（元数据）
   - 启动时校验一致性，优先 IndexedDB

4. 验收
   - 单测：模拟配额不足，验证回滚
   - 浏览器：工坊连续保存 20 次，断点检查版本链完整
   - 恢复测试：删除最新版，验证自动降级

**文件**：
- `src/lib/personal/transactionalStore.ts`（新建）
- `src/lib/studio/localScorePersistence.ts`（重构）
- `tests/storage-atomicity.test.mjs`（新建）

---

### P0.3 数据备份完整性 [3-4 天]

**问题**：单工程导出不是整机恢复（A03）、v2 分卷未真机验收

**实施**：
1. 完整备份范围
   - 收藏、待练、练习会话、A-B 片段、提速计划、断点
   - 工坊草稿、原件附件、浏览历史
   - 用户偏好（音量、速度、显示设置）

2. 备份完整性校验
   - 每个实体类型独立 checksum
   - 分卷间依赖关系验证
   - 恢复前结构完整性预检

3. 容量测试
   - 构造 1 GiB 边界测试数据
   - 真机下载验证（iOS Safari / Android Chrome）
   - 恢复性能基准（< 30s for 500MB）

4. 验收
   - 单测：v1/v2 序列化→反序列化往返
   - 浏览器：导出 500 MB 数据集，完整恢复，Diff 为空
   - 移动端：在 iOS Safari 导出分卷，验证全部下载

**文件**：
- `src/lib/personal/backup.ts`（扩展）
- `src/lib/personal/backupIntegrity.ts`（新建）
- `tests/backup-recovery.test.mjs`（扩展）
- `tools/generate-backup-fixtures.mjs`（新建）

---

### P0.4 错误处理与降级 [2-3 天]

**问题**：DB 错误静默降级（A07）、未知 ID 替换内容（A04）、API 异常假成功（A05）

**实施**：
1. 统一错误边界
   - `src/lib/errorBoundary.ts`
   - 区分可恢复（显示降级提示）与不可恢复（阻断操作）
   - 前端明确展示"演示模式"标识

2. API 响应契约
   ```typescript
   type ApiResponse<T> = 
     | { ok: true; data: T }
     | { ok: false; error: { code: string; message: string; recoverable: boolean } }
   ```
   - 所有 API 返回此结构
   - 异常不静默变成空数组/ok:true

3. 404/错误页优化
   - 未知曲谱/文章：显式 404 页面，不替换内容
   - 提供返回首页/搜索入口

4. 验收
   - 单测：每个 API 路由的错误分支覆盖
   - 浏览器：DB 不可用时访问所有页面，验证降级提示
   - 断网测试：离线状态操作，验证友好提示

**文件**：
- `src/lib/errorBoundary.ts`（新建）
- `src/lib/api.ts`（重构响应类型）
- `src/pages/api/*`（统一错误处理）
- `src/pages/404.astro`（优化）

---

### P0.5 TypeScript 类型安全 [2-3 天]

**历史问题**：10 月 15 日审计的 9 处 TS 错误不能作为当前错误清单。本批开工实际为新增备份校验 13 处及打印 4 处，均已修复；strict 配置和 Svelte/Astro 检查在原代码中已存在。以下保留作历史实施参考。

**实施**：
1. 逐项修复当前错误
   - `MasterBar.timeSignature`：使用 `MasterBar.timeSignatureDenominator/Numerator`
   - `firstKeyLabel`：补充定义或移除引用
   - `Environment.defaultRenderers`：更新到 AlphaTab 1.8.4 API
   - `NotationElement.EffectDecrescendo`：检查枚举值映射
   - `AlphaTabApi.beatChanged`：事件绑定方式更新
   - 其他：逐一对齐实际 API

2. 启用严格模式
   ```json
   // tsconfig.json
   {
     "strict": true,
     "noUncheckedIndexedAccess": true,
     "noImplicitReturns": true
   }
   ```

3. 添加 Svelte 类型检查
   - `npm run typecheck:svelte` → `svelte-check --fail-on-warnings`

4. 验收
   - `npm run typecheck` → 0 错误
   - 构建输出无 TS 警告
   - VSCode 无红色波浪线

**文件**：
- `tsconfig.json`（严格化）
- `src/lib/*` 中 9 处错误位置
- `package.json`（添加 typecheck:svelte）

---

## P1：核心功能完善与练习闭环（3-4 周）

**目标**：完成个人练习平台核心业务流程，建立可靠的状态管理。

### P1.1 练习会话模型 [4-5 天]

**问题**：播放状态丢失（A12）、无会话和恢复模型

**实施**：
1. 会话数据结构
   ```typescript
   interface PracticeSession {
     id: string;
     tabId: string;
     trackIndex: number;
     createdAt: Date;
     lastActiveAt: Date;
     totalDuration: number;  // 有效练习时长（秒）
     playbackState: {
       currentTick: number;
       bpm: number;
       isLooping: boolean;
       loopRange: { startTick: number; endTick: number } | null;
       transposition: number;
     };
     progressiveSpeed: {
       targetBpm: number;
       currentBpm: number;
       increment: number;
       milestones: { bpm: number; completedAt: Date }[];
     } | null;
     notes: string;  // 本次练习备注
   }
   ```

2. 持久化策略
   - IndexedDB 存储会话
   - 每 10 秒自动保存状态
   - 页面卸载前强制保存

3. "继续上次"逻辑
   - 打开详情页：检测最近会话（< 7 天）
   - 显示"继续上次练习"卡片
   - 恢复：加载状态→定位到 currentTick→暂停等待用户

4. 计时逻辑
   - 仅播放期间计入有效时长
   - 暂停/空闲不计时
   - 显示：本次 XX 分钟 / 累计 XX 小时

5. 验收
   - 单测：会话序列化/反序列化
   - 浏览器：练习 15 分钟→刷新→继续，状态完整
   - 多曲谱：验证会话独立性

**文件**：
- `src/lib/practice/sessionManager.ts`（新建）
- `src/lib/practice/models.ts`（新建）
- `src/components/PracticeSessionCard.svelte`（新建）
- `src/components/ScorePlayer.svelte`（集成会话）
- `tests/practice-session.test.mjs`（新建）

---

### P1.2 A-B 循环精确化 [3-4 天]

**问题**：getBeatStart 语义不足（A11）、缺反复/occurrence 支持

**实施**：
1. 精确拍位计算
   - 封装 `src/lib/playback/beatTiming.ts`
   - 考虑反复记号、跳房子、D.C./D.S.
   - 返回实际演奏顺序的 tick 序列

2. 选区UI增强
   - 触摸：长按进入选区模式→拖动端点
   - 鼠标：Shift+点击设置起点/终点
   - 可视化：高亮选区，显示小节号

3. 保存片段
   - 命名片段（"前奏"、"副歌"等）
   - 存储：tabId + 片段名 + startTick + endTick + bpm + notes
   - 快速切换：片段列表→一键加载

4. 验收
   - 单测：复杂反复结构的 tick 计算
   - 浏览器：带反复记号的谱选 A-B，验证实际播放范围
   - 移动端：触摸选区流畅性

**文件**：
- `src/lib/playback/beatTiming.ts`（新建）
- `src/lib/practice/fragmentManager.ts`（新建）
- `src/components/LoopRangeSelector.svelte`（新建）
- `tests/beat-timing.test.mjs`（新建）

---

### P1.3 渐进提速 [2-3 天]

**问题**：无自动提速逻辑

**实施**：
1. 提速方案
   - 用户设置：起始 BPM、目标 BPM、每次增量（5/10/15）
   - 触发条件：完整循环 N 次（用户可配，默认 3）
   - 自动提速：达到条件→弹窗确认→增加 BPM→重置计数

2. 里程碑记录
   - 每个 BPM 首次完成时记录
   - 显示：时间轴图表（BPM vs 日期）

3. UI 反馈
   - 当前：XX BPM，已完成 X/3 次
   - 下一个：+5 BPM（还需 2 次）
   - 历史最高：XX BPM

4. 验收
   - 单测：提速条件判断
   - 浏览器：循环 3 次→验证自动提速
   - 边界：目标 BPM 达到后禁用提速

**文件**：
- `src/lib/practice/progressiveSpeed.ts`（新建）
- `src/components/ProgressiveSpeedPanel.svelte`（新建）
- `src/components/SpeedMilestones.svelte`（新建）

---

### P1.4 播放器状态可靠性 [3-4 天]

**问题**：seek 检查错误（A13）、音源加载假 ready（A14）

**实施**：
1. 音源加载状态机
   ```
   idle → loading → loaded → ready
          ↓ timeout/error
          failed
   ```
   - 加载超时：15 秒
   - 失败重试：3 次，指数退避
   - UI 显示加载进度（x/y 音源）

2. Seek 验证
   - 使用 `api.score.duration`（tick）而非 `Score.endTick`
   - 边界检查：0 ≤ tick ≤ duration
   - 失败时显示"无法跳转"提示

3. 播放状态同步
   - `api.play()` 异步，等待实际开始
   - 状态机：idle → starting → playing → paused/stopped
   - UI 根据实际状态更新按钮

4. 断网处理
   - 检测网络状态（online/offline）
   - 已缓存音源：离线可播放
   - 未缓存：显示"需要网络"提示

5. 验收
   - 单测：状态机转换覆盖
   - 浏览器：断网播放已缓存谱
   - 音源失败：验证重试与提示

**文件**：
- `src/lib/player/soundfontLoader.ts`（新建）
- `src/lib/player/playbackStateMachine.ts`（新建）
- `src/lib/scoreAuditionEngine.ts`（重构）
- `tests/soundfont-loading.test.mjs`（新建）

---

### P1.5 移动端可用性 [3-4 天]

**问题**：无游客本地资料入口（A18）、部分按钮无可访问名称、画布超出首屏

**实施**：
1. 移动导航重构
   - 添加"我的练习"入口（游客可访问）
   - 登录/注册：改为"同步到云端"（可选）
   - 汉堡菜单：分组清晰（发现/练习/设置）

2. 可访问性修复
   - 所有按钮添加 `aria-label`
   - 图标按钮：提供文本替代
   - 循环/重来按钮：明确名称

3. 响应式优化
   - 工坊画布：移动端默认适配宽度
   - 播放器控制：纵向布局（< 768px）
   - 虚拟键盘避让：播放器固定在顶部

4. 触摸交互
   - 长按：显示上下文菜单
   - 滑动：切换曲谱/片段
   - 双指缩放：调整谱面显示

5. 验收
   - Lighthouse 移动端评分：> 90
   - 屏幕阅读器：完整流程可导航
   - 真机测试：iPhone / Android 各一台

**文件**：
- `src/components/MobileMenu.svelte`（重构）
- `src/components/ScoreCanvas.svelte`（响应式）
- `src/styles/mobile.css`（新建）
- `docs/accessibility-audit.md`（新建）

---

## P2：性能优化与用户体验（2-3 周）

**目标**：显著提升加载速度、播放流畅度和交互响应，减少资源消耗。

### P2.1 首屏加载优化 [4-5 天]

**当前**：未优化，估计 2-4 秒
**目标**：< 1.5s（桌面）/ < 2.5s（移动）

**实施**：
1. 代码分割
   - 路由级懒加载：`pages/` 每个路由独立 chunk
   - 组件级：播放器/工坊/编辑器按需加载
   - Astro 岛屿：`client:visible` / `client:idle`

2. 资源优化
   - AlphaTab：仅加载必要模块（不含 PDF 生成）
   - 字体：子集化（仅保留中文常用字 + 拉丁）
   - 图片：WebP + 响应式尺寸

3. 预加载策略
   - 关键 CSS：内联到 `<head>`
   - 音源：首页预连接（`<link rel="preconnect">`）
   - 演示谱：Service Worker 预缓存

4. 缓存策略
   - HTML：no-cache
   - JS/CSS：1 年 + 哈希
   - 媒体：1 年（不可变）
   - API：协商缓存

5. 验收
   - Lighthouse：性能 > 95
   - WebPageTest：First Contentful Paint < 1s
   - 真实用户监控（RUM）：3G 网络 < 3s

**文件**：
- `astro.config.mjs`（优化构建）
- `src/layouts/Base.astro`（资源优先级）
- `public/sw.js`（Service Worker，新建）
- `tools/performance-budget.mjs`（新建）

---

### P2.2 播放器性能 [3-4 天]

**问题**：长谱/多轨卡顿

**实施**：
1. 渲染优化
   - 虚拟滚动：仅渲染可见小节（±2 页）
   - Canvas 分层：静态谱面 + 动态高亮
   - 节流滚动：requestAnimationFrame

2. 音频优化
   - Web Worker：音频解码异步化
   - AudioWorklet：低延迟播放
   - 音源压缩：Opus 格式（减少 50%）

3. 内存管理
   - LRU 缓存：最多 5 个谱面
   - 音源池：复用 AudioBuffer
   - 自动释放：非活跃 > 5 分钟

4. 性能监控
   - 关键指标：FPS、内存、音频延迟
   - 警告阈值：FPS < 30 / 内存 > 500MB
   - 自动降级：禁用特效、减少多轨

5. 验收
   - 基准测试：500 小节谱面 60 FPS
   - 长时播放：2 小时无内存泄漏
   - 低端设备：iPhone SE 2016 可用

**文件**：
- `src/lib/player/virtualRenderer.ts`（新建）
- `src/workers/audioDecoder.worker.ts`（新建）
- `src/lib/performance/memoryManager.ts`（新建）
- `tests/performance/player-benchmark.test.mjs`（新建）

---

### P2.3 数据库查询优化 [2-3 天]

**问题**：分页/筛选性能未测量

**实施**：
1. 索引优化
   - 覆盖索引：category + difficulty + heat
   - 部分索引：WHERE difficulty > 0
   - 全文索引：title + artist（GIN）

2. 查询优化
   - N+1 问题：批量预加载关联
   - 分页：游标替代 OFFSET（> 1000 条）
   - 筛选：推 WHERE 到数据库

3. 缓存层
   - Redis：热门列表（TTL 5 分钟）
   - CDN：静态页面（1 小时）
   - 浏览器：API 响应（协商缓存）

4. 监控
   - 慢查询日志：> 100ms
   - Prisma 查询分析：`npx prisma studio`
   - 性能基准：每路由 p99 延迟

5. 验收
   - 列表页：10,000 条数据 < 100ms
   - 搜索：中文分词 < 200ms
   - 并发：100 用户无降级

**文件**：
- `prisma/schema.prisma`（索引）
- `src/lib/cache/redis.ts`（新建，可选）
- `tools/query-benchmark.mjs`（新建）

---

### P2.4 工坊编辑器优化 [3-4 天]

**问题**：全量 tex 重渲染（A17）、触摸漂移风险

**实施**：
1. 增量渲染
   - 仅重渲染变化小节
   - Diff 算法：识别新增/删除/修改
   - 批量更新：debounce 300ms

2. 触摸精度
   - 坐标校准：缩放/滚动补偿
   - Hit Testing：严格边界检查
   - 视觉反馈：点击位置标记

3. 撤销/重做优化
   - 命令模式：每个操作封装
   - 历史栈：最多 50 步
   - 内存优化：增量快照

4. 实时协作（可选）
   - WebSocket：操作事件同步
   - CRDT：冲突自动合并
   - 光标：显示其他用户位置

5. 验收
   - 性能：100 小节编辑 < 16ms
   - 准确性：触摸偏移 < 5px
   - 稳定性：连续编辑 1 小时无崩溃

**文件**：
- `src/lib/studio/incrementalRenderer.ts`（新建）
- `src/lib/studio/touchCalibration.ts`（新建）
- `src/lib/studio/commandHistory.ts`（重构）
- `tests/studio-performance.test.mjs`（新建）

---

## P3：架构重构与可维护性（3-4 周）

**目标**：建立清晰的层次结构、统一的状态管理和完善的测试体系。

### P3.1 状态管理统一 [4-5 天]

**问题**：localStorage/IndexedDB/组件状态混乱

**实施**：
1. Svelte Stores 架构
   ```
   src/stores/
   ├── auth.ts          # 用户状态
   ├── practice.ts      # 练习会话
   ├── library.ts       # 个人曲库
   ├── player.ts        # 播放器状态
   └── ui.ts            # UI 偏好
   ```

2. 持久化层
   - 中间件：自动同步 Store ↔ IndexedDB
   - 选择性持久化：`writable(value, { persist: 'idb' })`
   - 冲突解决：last-write-wins + timestamp

3. 状态机
   - XState：复杂状态（播放器、上传）
   - 可视化：状态图生成文档
   - 测试：覆盖所有转换

4. 验收
   - 单测：所有 Store 的 CRUD
   - 集成测试：跨组件状态同步
   - 性能：状态更新 < 10ms

**文件**：
- `src/stores/*`（新建）
- `src/lib/persistence/storeMiddleware.ts`（新建）
- `src/lib/stateMachines/*`（新建）
- `tests/stores/*.test.mjs`（新建）

---

### P3.2 API 层重构 [3-4 天]

**问题**：错误处理不统一、类型不安全

**实施**：
1. tRPC 集成
   - 类型安全：前后端共享 schema
   - 自动验证：Zod schema
   - 批量查询：减少往返

2. API 规范
   ```typescript
   // src/server/routers/tabs.ts
   export const tabsRouter = router({
     list: procedure
       .input(z.object({
         category: z.enum(['guitar', 'ukulele']),
         page: z.number().min(1),
         pageSize: z.number().min(10).max(100),
       }))
       .query(({ input }) => {
         // 实现
       }),
   });
   ```

3. 中间件
   - 认证：JWT 验证
   - 日志：请求/响应记录
   - 限流：Redis + Sliding Window
   - 错误转换：统一错误码

4. 验收
   - 单测：每个 procedure 的成功/失败路径
   - 集成测试：E2E 流程
   - 性能：批量查询减少 50% 请求

**文件**：
- `src/server/trpc.ts`（新建）
- `src/server/routers/*`（新建）
- `src/lib/trpcClient.ts`（新建）
- 迁移现有 `src/pages/api/*`

---

### P3.3 测试体系完善 [4-5 天]

**问题**：假绿、覆盖率不足（A19）

**实施**：
1. 单元测试
   - 框架：Vitest（替代 Node test）
   - 覆盖率：> 80%（核心逻辑）
   - Mock：统一 fixture 管理

2. 集成测试
   - Playwright：关键流程
   - 场景：注册→导入→练习→备份→恢复
   - 断言：状态一致性、无控制台错误

3. 视觉回归
   - Percy / Chromatic
   - 基准截图：所有页面 × 3 尺寸
   - 自动对比：PR 触发

4. 性能测试
   - Lighthouse CI：每次构建
   - 基准：P95 延迟不退化
   - 预算：JS < 300KB、图片 < 500KB

5. CI/CD
   ```yaml
   # .github/workflows/ci.yml
   test:
     - npm run typecheck
     - npm run test:unit
     - npm run test:integration
     - npm run build
   ```

6. 验收
   - 代码覆盖率：80%+
   - CI 绿灯：所有 PR 必须通过
   - 测试速度：< 5 分钟

**文件**：
- `vitest.config.ts`（新建）
- `tests/integration/*`（重构）
- `tests/fixtures/*`（统一）
- `.github/workflows/ci.yml`（新建）

---

### P3.4 文档与规范 [2-3 天]

**实施**：
1. 代码文档
   - TSDoc：所有公开 API
   - 决策记录：ADR（Architecture Decision Records）
   - 示例：Storybook（Svelte 组件）

2. 开发指南
   - 贡献指南：`CONTRIBUTING.md`
   - 代码风格：ESLint + Prettier 配置
   - Git 工作流：分支策略、提交规范

3. 用户文档
   - 快速开始：5 分钟教程
   - 功能手册：每个模块详细说明
   - 故障排查：常见问题 FAQ

4. API 文档
   - Swagger / OpenAPI
   - 交互式示例
   - 错误码参考

**文件**：
- `docs/architecture/*`（新建）
- `docs/api/*`（新建）
- `CONTRIBUTING.md`（新建）
- `.storybook/*`（新建）

---

## P4：高级功能与生态（长期）

**目标**：引入 AI 辅助、社区功能、跨平台支持。

### P4.1 AI 辅助练习 [可选]

- 实时指法建议（计算机视觉 + 姿势识别）
- 错音检测（音频分析 + 谱面对比）
- 个性化练习计划（强化学习）

### P4.2 社区功能 [可选]

- 作品分享：录音 + 谱面同步
- 协作编曲：多人实时编辑
- 评论/点赞：社交互动

### P4.3 跨平台 [可选]

- PWA：离线完整功能
- Tauri：桌面应用（Mac/Windows/Linux）
- React Native：原生移动端

---

## 实施路线图

### 第 1-3 周：P0 数据可靠性
```
Week 1: P0.1 音频 + P0.2 存储
Week 2: P0.3 备份 + P0.4 错误处理
Week 3: P0.5 类型安全 + 集成测试
```

### 第 4-7 周：P1 练习闭环
```
Week 4: P1.1 会话模型 + P1.2 A-B 精确化
Week 5: P1.3 渐进提速 + P1.4 播放器可靠性
Week 6-7: P1.5 移动端可用性
```

### 第 8-10 周：P2 性能优化
```
Week 8: P2.1 首屏加载 + P2.2 播放器性能
Week 9: P2.3 数据库 + P2.4 工坊编辑器
Week 10: 性能基准测试与调优
```

### 第 11-14 周：P3 架构重构
```
Week 11: P3.1 状态管理
Week 12: P3.2 API 层
Week 13: P3.3 测试体系
Week 14: P3.4 文档与发布准备
```

---

## 资源需求

### 人力
- 全栈开发：1 人（主力）
- UI/UX：0.5 人（兼职，P1.5 移动端）
- QA：0.5 人（兼职，P3.3 测试）

### 基础设施
- 开发环境：Mac + Docker Desktop
- CI/CD：GitHub Actions（免费额度）
- 监控：Sentry（开源版）
- 性能：Lighthouse CI（免费）

### 第三方服务（可选）
- 音源 CDN：Cloudflare R2
- 数据库：Supabase（PostgreSQL）
- 认证：Clerk / Auth0
- 分析：Plausible（隐私友好）

---

## 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| AlphaTab API 变更 | 高 | 低 | 版本锁定，定期升级测试 |
| 浏览器兼容性 | 中 | 中 | Polyfill，持续跨浏览器测试 |
| 性能目标未达成 | 中 | 中 | 分阶段验证，及时调整方案 |
| 移动端音频限制 | 高 | 中 | 降级方案，明确提示用户 |
| IndexedDB 配额不足 | 中 | 低 | 主动清理，提供云端备份 |

---

## 成功指标

### 技术指标
- ✅ 0 个 P0/P1 阻断问题
- ✅ TypeScript 严格模式零错误
- ✅ 测试覆盖率 > 80%
- ✅ Lighthouse 性能 > 95

### 用户体验指标
- ✅ 首屏加载 < 1.5s
- ✅ 播放器响应 < 100ms
- ✅ 移动端 Lighthouse 可访问性 100

### 业务指标
- ✅ 练习会话完成率 > 70%
- ✅ 备份成功率 > 99%
- ✅ 用户留存率（7 天）> 40%

---

## 附录

### A. 技术栈版本
- Node.js: 24.x
- Astro: 5.18.2
- Svelte: 5.56.8
- AlphaTab: 1.8.4
- PostgreSQL: 16
- Prisma: 6.19.3

### B. 相关文档
- [现状审计](docs/platform-audit-2026-10-15.md)
- [Mac 接续 Backlog](docs/mac-next-development-backlog.md)
- [个人数据契约](docs/personal-data-contract.md)
- [练习播放契约](docs/practice-playback-contract.md)

### C. 关键决策
1. **为什么不使用原站 fork 的 AlphaTab？**
   - 官方版本持续维护，文档完善
   - 避免黑盒依赖，降低长期风险

2. **为什么选择 IndexedDB 而非服务端存储？**
   - 隐私优先：数据不离开设备
   - 离线优先：无需网络即可练习
   - 简化架构：减少服务端复杂度

3. **为什么采用单体架构？**
   - 当前规模不需要微服务
   - 降低运维复杂度
   - 便于本地开发与调试

---

**文档版本**：v1.0
**最后更新**：2026-10-28
**维护者**：项目核心团队
