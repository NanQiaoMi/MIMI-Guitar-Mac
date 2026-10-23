# MIMI Guitar 详细项目开发文档（v0.1 草稿）

> 状态：**草稿 v0.1**，待「六轮深度访谈」确认后迭代定稿。
> 定位：以 `D:\MIMIguitarweb` 现有实现（M0–M7 已完成并合入 master）为基线，覆盖技术栈选型、交互逻辑细节、边界与异常场景、潜在技术难点与盲区，输出可落地、可验收的开发文档。
> 所有「待确认」决策点均标注为 `【待确认·RnQn】`，对应附录 A 的访谈问题；未确认前按推荐默认值执行。

---

## 1. 文档说明与阅读方式

### 1.1 读者与用途

- 开发者/维护者：按第 7–9 章实现与排障，按第 10–11 章执行里程碑与验收。
- 决策者：第 4、6、9、12 章给出取舍依据与风险清单；附录 A 是待确认决策点。

### 1.2 与既有文档的关系

| 文档 | 关系 |
|---|---|
| PLAN.md | 里程碑总览（M0–M7 已交付） |
| UPDATE_PLAN.md | M7 落地版任务清单 |
| GAP_REPORT.md | 本地站 vs 原站差距矩阵 |
| DEV_LOG.md | 开发与验收日志 |
| **本文档** | 面向「生产化 + 持续迭代」的详细开发规范，作为上述文档的执行细化 |

### 1.3 术语

- `.ibe`：本项目的乐谱二进制格式。原站格式 = XOR(`guitartabspro`, 偏移 len%10) → AR 解压 → alphaTab JSON；自有格式 = `MIMI` 魔数 + deflate + XOR(`mimi-guitar-2026`)。
- XHE 谱：原站网页文本谱（无音频），当前库中有 192 首，`scoreUrl` 为空、仅 `xheUrl`。
- sf2：SoundFont 2 音源，按 alphaTab program（乐器编号）加载，program 128 = 鼓组。

---

## 2. 项目概览与目标

### 2.1 项目目标

在 `D:\MIMIguitarweb` 从零复刻 guistudy.com（「谱全了」）全站功能，乐谱**显示与播放**为核心，视觉采用 refero「General Intelligence Company」编辑风格体系。范围（用户已确认）：

- 前台：首页 / 列表 / 详情 / 播放器 / 搜索 / 文章 / 静态页。
- 用户系统：注册登录、收藏、浏览记录、个人资料。
- 上传创作中心：Guitar Pro → `.ibe` 全流程。
- 权限模型：全开放（游客可用全部浏览功能；登录用于收藏/历史/上传）。
- 数据：迁移原站热门子集；**版权风险已记录，商用前须替换为授权内容**。

### 2.2 本文档的增量目标

1. 把已验证的功能固化为可维护的工程规范（交互细节、边界、异常处理）。
2. 识别并消除「演示可用」与「生产可用」之间的差距（部署、安全、性能、合规）。
3. 给出分阶段、可验收的落地计划。

---

## 3. 现状盘点

### 3.1 已完成里程碑（M0–M7）

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M0 | 工程初始化：Git、脚手架、PG、文档基线 | 完成 |
| M1 | 数据管线：`.ibe` 解码、迁移、入库、上传生成 | 完成 |
| M2 | 播放器：渲染 + 全控制（循环/变调夹/速度/多轨/PDF/打印） | 完成 |
| M3 | 前台：首页/列表/详情/搜索/文章/静态页 | 完成 |
| M4 | 用户系统：注册登录、收藏/历史/资料 | 完成 |
| M5 | 上传创作中心 | 完成 |
| M6 | 设计打磨与性能（refero 落地、移动端、无障碍基础、安全加固、性能基线） | 完成 |
| M7 | 对齐原站功能+交互（账号路由、搜索页、首页、详情、社区、静态页、视觉微调、数据扩充） | 完成（数据扩充按用户指示暂停） |

### 3.2 当前分支与未提交改动

- 当前分支：`fix/player-cursor-follow`（未提交，工作区有改动）。
- 未提交内容（WIP）：播放器增强
  - `src/components/player/ScorePlayer.svelte`：音源加载状态机（`soundfontLoading/soundfontReady/pendingPlay`）、播放进度条与拖动跳转、当前小节/拍指示、sf2 加载失败提示条、`applyScoreChange`（播放中改谱面：暂停→应用→恢复位置→继续）。
  - `src/lib/playerMath.ts`（新）：`playbackSpeedFor` / `clampTick` / `formatTime` 纯函数。
  - `src/lib/playerSettings.ts`：`scrollMode=Continuous` + `scrollElement='#score-scroll'` 原生跟随滚动（替代手写 scrollIntoView）。
  - `src/styles/global.css`：进度条等样式。
  - `tests/player-math.test.mjs`（新）与证据图更新。

> 结论：本文档将把该 WIP 纳入正式交互规范（见 7.1），并要求其在合入 master 前完成验证。

### 3.3 数据现状

- DB 曲谱总数：**5267 首**（吉他 4400 / 尤克里里 867）。
- 可播放：5075 首带 `.ibe`；**192 首为 XHE 纯文本谱（无音频）**。
- 数据扩充目标 ≥10000 首，已按用户指示暂停；断点状态保留于 `tools/migrate-state-m7.json`（已 gitignore），可随时续跑：
  `node tools/migrate.mjs --ids tools/migrate-candidates.json --pace 1100 --state tools/migrate-state-m7.json`
- 入库方式：`upsert` 幂等，按 id 去重，重跑不会重复入库。

### 3.4 已知差距与缺口（来自 GAP_REPORT + 代码核对）

| # | 缺口 | 影响 | 对应章节 |
|---|---|---|---|
| G1 | 生产部署未做（无应用 Dockerfile、无 CI/CD、无对象存储、无 CDN） | 无法上线 | 9.2 / 10 |
| G2 | `.ibe` 存放在 `public/storage`，可直连访问；「登录后下载」门禁可被绕过 | 商业规则失效 | 7.5 / 8 |
| G3 | 打印/PDF 水印仍为「@谱全了」（原站品牌） | 品牌/法律风险 | 9.1 |
| G4 | 上传审核为「上传者本人可模拟通过/拒绝」 | 内容质量与合规风险 | 7.7 / 9 |
| G5 | 音源依赖原站远程 sf2（p.insstudy.com），且 49/51 号音源缺失 | 可用性/授权风险 | 7.1 / 9 |
| G6 | 长曲渲染体积大（Dream Theater 283MB / 2.7s），无虚拟滚动 | 移动端/弱网体验差 | 8 / 9 |
| G7 | 文章无作者字段、非真正 Markdown 渲染（仅 `whitespace-pre-line`） | 社区功能不完整 | 7.8 |
| G8 | XHE 纯文本谱无播放兜底（`scoreUrl` 为空直接进播放器） | 详情页报错 | 7.1 / 8 |
| G9 | 限流为进程内存、信任 `x-forwarded-for` 首值 | 多实例/防绕过不足 | 9.3 |
| G10 | 无障碍 axe 自动审计未执行 | 合规验收缺失 | 11 |
---

## 4. 技术栈选型决策

### 4.1 现状技术栈（已落地）

| 层 | 选型 | 说明 |
|---|---|---|
| 前端框架 | Astro 5 SSR（node standalone） | SSR 列表/详情 + 岛屿交互 |
| 组件 | Svelte 5 | 与原站一致 |
| 样式 | Tailwind CSS v4 + refero token | `src/styles/global.css` 承载设计 token |
| 乐谱引擎 | `@coderline/alphatab` 1.8.4（官方） | 渲染/播放/导入；`.ibe` 解码自研 |
| 压缩库 | vendored `ar.es.js`（浏览器 eval / Node vm 注入） | 兼容原站 AR 压缩 |
| 后端 | Astro 服务端 + Prisma | 单进程 SSR + API |
| 数据库 | PostgreSQL 16（Docker，端口 5433） | |
| 认证 | JWT（cookie `mimi_token`，HS256，scrypt 口令哈希） | 单 token、7 天 |
| PDF | jsPDF 4（SVG→Canvas→JPEG→PDF） | A4 分页 + 水印 |
| 验收 | Node test + Playwright（系统 Chrome） | 证据存 `tests/evidence/` |

### 4.2 待确认决策

- 【待确认·R1Q2】核心栈是否维持现状（推荐维持，深度打磨）。
- 【待确认·R1Q3】乐谱引擎策略（推荐加固现有方案：本地化音源 + 解码回退 + 上传自生成格式闭环）。

### 4.3 引擎技术说明（供决策）

#### `.ibe` 解码管线（浏览器 + Node 双端）

```
.ibe 字节
  → 自有格式?（MIMI 魔数）→ XOR(OUR_KEY) → inflate → JSON
  → 否则原站格式 → XOR("guitartabspro", len%10 偏移) → AR 解压 → JSON
  → 递归归一化（键小写化、tempoAutomation→tempoautomations、chords 键保留、注入顶层 tempo）
  → model.JsonConverter.jsonToScore
```

要点：

- `registerArLoader` 抽象 AR 加载；浏览器用 eval 注入，Node 用 `fs + vm`。
- 归一会把原站驼峰 schema 映射为官方 1.8.4 全小写 schema——这是兼容性关键，也是未来原站改版时的首要风险点（9.4）。
- 上传自生成 `.ibe` 使用自有格式（`MIMI` 魔数），与解码自闭环，不依赖原站格式。

#### 播放器设置要点

- `layoutMode=Page`、`staveProfile=Tab`、`scrollMode=Continuous`、`scrollElement='#score-scroll'`、`scrollOffsetY=-200`。
- 默认 `display.scale=0.84`、`stretchForce=0.66`、`rhythmHeight=25`、`masterVolume=0.7`。
- 轨道处理：跳过 `@$Strumming$@` / `@$Chords$@` 轨道；乐器名映射 `GM_INSTRUMENTS`。

---

## 5. 系统架构

### 5.1 现状拓扑

```
浏览器 ── SSR(4321) ── PostgreSQL(5433, Docker)
  │  └─ /render 页（Playwright 无头 Chrome 截图用）
  ├─ public/storage/scores（.ibe + 截图，gitignore）
  ├─ public/storage/soundfonts（脚本拉取）
  └─ public/storage/upload（上传产物）
音源：浏览器直连 https://p.insstudy.com/puquanle/soudfont/{program}.sf2
```

### 5.2 目标拓扑（生产化，见 10）

【待确认·R4Q2】部署范围。推荐最小生产形态：

```
Nginx/CDN ── Astro node(container) ── PostgreSQL(container/托管)
  ├─ 对象存储或挂载卷：/storage（scores/upload/screenshots/soundfonts）
  ├─ Redis（可选，多实例限流/缓存）
  └─ Chrome（截图 worker，独立容器）
```

关键约束：

- `renderScreenshot` 依赖系统 Chrome（`CHROME_PATH` 或默认路径），容器内需内置 Chromium。
- 截图服务通过 `SITE_URL` 回访自身 `/render?file=...`，多实例时需保证可回访。

---

## 6. 数据模型

### 6.1 现状模型（Prisma）

| 模型 | 关键字段 | 备注 |
|---|---|---|
| User | email/phone(唯一)、passwordHash、nickname、avatarUrl | 无 role 字段 |
| Tab | title、artist、category、difficulty(0-5)、style、key、tuning、sheetForm(0-4/7)、bpm、timeSig、capo、tuningText、heat、uploader、publishDate、format、scoreUrl、xheUrl、screenshotUrl、description、tags(JSON 字符串) | 索引：category+筛选组、category+heat、category+createdAt、artist、title |
| Favorite | userId+tabId 唯一 | 级联删除 |
| UploadRecord | userId、title、artist、fileName、scoreUrl、screenshotUrl、metaJson、tabId、status(pending/approved/rejected) | id = 存储 id（URL 稳定） |
| Article | title、content、category、views | **无作者/无 user 关联** |

### 6.2 演进建议（待确认·R5Q2）

优先候选：

1. `Article.authorId → User`（文章归属），`Article.updatedAt`；可加 `publishedAt` 与 `status`。
2. 服务端浏览历史表 `History(userId, tabId, lastViewedAt)`（当前为 localStorage，跨设备不互通）。
3. `Tab.source`（migrated/uploaded）来源标记（见 R5Q3）。
4. `User.role`（user/admin）以支撑真实审核（见 R5Q1）。
5. 上传去重：`Tab.sourceHash`（.ibe 内容哈希）防重复上架。
6. 搜索基建（若换 Meilisearch 则新增独立索引，不动 Prisma 表结构）。

### 6.3 索引与查询

- 列表查询 `queryTabs`：category + 可选 difficulty/style/key/tuning/sheetForm + 排序（publishDate desc / heat desc）+ 分页（90/页）。
- 搜索：title/artist/all 三字段，Prisma `contains + insensitive`（中文为子串匹配，1 万行内足够；后续量级大再上 Meilisearch）。
- 首页热度：今日/本周/本月按 `publishDate` 窗口 + heat 排序，数据不足回退总热度。
- 【待确认·R3Q2】数据量与质量策略直接影响首页/搜索计数真实性。
---

## 7. 核心交互逻辑细节

### 7.1 播放器（核心）

#### 加载流程（含 WIP 状态机）

1. 进入详情页 → `client:load` 挂载 ScorePlayer。
2. `fetch(scoreUrl)` → `.ibe` 解码 → 归一化 JSON → `jsonToScore`。
3. `buildTracks()`：过滤 Strumming/Chords 轨道，默认只显示 `defaultTrack`。
4. 加载 sf2（按 program 去重；`loadSoundfonts()` 非阻塞）：
   - 单个失败 → 提示「音源加载失败：HTTP n / program p」，不阻塞；
   - 15s 超时兜底：事件未完成也放行播放；
   - 加载完成前播放按钮显示「音源加载中…」，点击记为 `pendingPlay`，就绪后自动播放。
5. 渲染：`renderScore(score, visibleTracks)`，`masterVolume=0.7`。

#### 控制项

| 控制 | 实现要点 | 边界/异常 |
|---|---|---|
| 播放/暂停/重来 | `api.playPause/stop`；停止回顶部 | 音源未就绪时排队播放 |
| 速度 | `playbackSpeed = targetBpm / baseTempo`（只改速率，不改谱面 tempo） | baseTempo<=0 回退 1 |
| 循环 | 点击音符设 startTick/endTick → playbackRange+isLooping | **反向点击处理待确认（R2Q2）** |
| 变调夹/字体/数字谱 | 改谱面属性 → `renderScore` | 播放中经 `applyScoreChange`：暂停→应用→恢复 tick→继续 |
| 多轨 | 轨道面板开关、静音/独奏/音量 | 切换轨道同样走 `applyScoreChange` |
| 乐器 | GM 128 中文映射 | 音源缺失仅提示 |
| 进度条 | range 拖动 → `tickPosition = clampTick`；循环区间高亮 | 拖动中 `seeking` 冻结位置回写 |
| 位置指示 | 当前小节/拍、`mm:ss` 时间 | 播放结束复位 |
| 打印 | 隐藏容器重渲染 + `window.print()` | 水印品牌问题（R4Q1） |
| PDF | 分页 SVG→JPEG→jsPDF（A4） | 长谱内存风险（R3Q1） |

#### 光标跟随（当前 WIP 主题）

- 【待确认·R2Q1】期望行为三选一：
  - 推荐：音符级平滑跟随 + 用户手动滚动时暂停自动跟随 + 播放结束回顶部；
  - 仅页面级翻页（换行/换页跳转）；
  - 跟随 + 手动优先（需手动恢复跟随）。
- 当前实现：`scrollMode=Continuous` + `scrollElement='#score-scroll'` 原生跟随；容器 `max-h-[calc(100vh-16rem)] overflow-y-auto`。

#### XHE 纯文本谱（G8）

- `scoreUrl` 为空时：显示「该谱为网页文本谱，暂不支持播放」，隐藏播放控制，仅展示文本/链接；不得进入解码流程报错。

### 7.2 首页

结构（M7.4 已对齐原站）：

1. Hero + 全局搜索框（→ `/searchResults`）。
2. 热门：今日/本周/本月三 tab（`HotTabs.svelte`，publishDate 窗口 + heat 前 10，不足回退总热度）。
3. 风格区：流行/民谣/摇滚/乡村/金属/配乐 6 项 + 计数（→ `/tabs?style=N`）。
4. 难度矩阵：零基础~专业 × 弹唱/指弹/和弦/六线谱 20 格 + 计数 + 吉他/尤克里里切换（`DifficultyMatrix.svelte`，counts 来自 DB groupBy；六线谱列聚合 sheetForm 4 与 7）。
5. 最新吉他谱 / 最新尤克里里谱。

边界：今日/本周/本月窗口需按 Asia/Shanghai 时区计算（当前环境时区为 Asia/Shanghai，部署到 UTC 主机时须显式处理）。

### 7.3 列表与筛选

- 路由：`/tabs`、`/ukulele`，URL 参数 `difficulty/style/key/tuning/sheetForm/sort/no`（SSR 直查 DB）。
- `sheetForm=4` 同时命中 4 与 7（六线谱归并）。
- 分页 90/页；无效页回退到 1。

### 7.4 搜索

- 路由：`/searchResults?type=guitar|ukulele&searchValue=&sort=&sheetForm=&difficulty=&page=`；`/search?q=` 302 重定向。
- 字段切换：艺人名/歌曲名称（`field=title|artist|all`）。
- 三 tab（吉他/尤克里里/文章）带计数；文章 tab 无难度/谱型筛选。
- 【待确认·R2Q3】tab 切换时筛选条件保留策略：
  - 推荐：保留共有筛选；切到文章 tab 时忽略乐器专属筛选；返回保留。
  - 备选：切换即重置；或各 tab 独立记忆。
- 空关键词：推荐展示「全部/推荐」（可在 R2Q3 轮一并确认）。

### 7.5 详情页

- 标题格式：`tabTitle()`（`{title}{乐器}_{artist}_{key}调{难度}{类型}谱|高清{类型}谱`）。
- 信息区：调性/难度/速度/拍号/Capo/调弦/热度/上传者/日期/调音模式/标签/歌词/搭配和弦。
- 操作：收藏、分享（复制链接）、下载、打印、PDF。
- 下载 `.ibe`：`/api/tabs/[id]/download`，登录后 200 + attachment；未登录 401。
- **G2 门禁绕过**：文件本体在 `public/storage/scores/`，可被直连下载。【待确认·R4 关联】推荐将文件移出 public，改经鉴权接口流出。
- 相关推荐：同 category、排除自身、heat desc 前 10。

### 7.6 账号体系

- 路由：`/account/0=我的收藏`、`1=创作中心`、`2=浏览记录`、`3=个人资料`；侧边栏含上传与退出。
- 未登录访问：显示空态（不整页跳登录）。
- 登录/注册：手机号或邮箱 + 密码；`/login`、`/register`、`/account/reset`。
- JWT：cookie `mimi_token`，httpOnly + sameSite=lax；本地 `secure:false`（部署 HTTPS 须置 true）。
- 浏览记录：localStorage 为主，服务端可选同步（未实现）。
- 短信验证码：`sms.ts` 为本地 mock；生产需接真实短信服务或维持密码登录。

### 7.7 上传创作中心

流程：

```
/upload?type=guitar|ukulele（需登录）
  → 校验：非空、≤30MB、category 合法
  → parseGpToIbe：alphaTab 解析 GP → JSON → 自有 MIMI .ibe
  → 写 public/storage/upload/{id}.ibe
  → 服务端截图（renderScreenshot，失败不阻断）
  → UploadRecord(pending) + metaJson
  → 上传者创作中心查看状态
```

- 支持格式：`.gp3/.gp4/.gp5/.gpx/.gp`；解析失败 422。
- 审核：当前 `POST /api/upload/[id]/review` 允许**上传者本人** approve/reject，approve 后建 Tab 并置 `status=approved`。【待确认·R5Q1】推荐改为管理员审核（加 `User.role` 与管理页），或至少限制「本人只能撤回，不能自批上架」。
- 截图：依赖系统 Chrome + `SITE_URL`；失败仅提示「预览缺失」，不阻断上传。

### 7.8 文章社区

- 列表：`/article`（`/community` 302 别名），`sort=new|hot` + 分页；`views` 计数。
- 发布：`/publishArticle`（登录态），`POST /api/articles`（title≤100、content≥10）。
- 详情：`/article/[id]`，`whitespace-pre-line` 纯文本展示（**并非真正 Markdown 渲染**）。
- 缺口：无作者、无编辑/删除、无审核、无 Markdown 渲染、无文章内图片。均属社区增强（R5/R6 可纳入优先级）。

### 7.9 静态页与页脚

- 已实现：/about /help /contact（/countact-us 别名）/policy /agreementPolicy /uploadpolicy /copyrightPolicy /licenses。
- 页脚：了解谱全了/内容/协议/版权/客服邮箱 + 备案与网文许可**占位文案**（不冒用原站真实证号）。

---

## 8. 边界与异常场景清单

> 每项含：场景 / 现状 / 风险 / 对策 / 决策点。

| # | 场景 | 现状 | 风险 | 对策 | 决策点 |
|---|---|---|---|---|---|
| B1 | 长谱/大文件（Dream Theater 283MB、2.7s） | 全量渲染 | 移动端卡顿、内存溢出 | 懒加载 + 虚拟滚动/分页渲染；或上传时生成分页快照 | R3Q1 |
| B2 | 数据量不足 10000（当前 5267） | 暂停扩充 | 首页/搜索计数失真、今日热榜空洞 | 质量优先（以可播放 .ibe 为准）或续爬 | R3Q2 |
| B3 | sf2 远程不可用/缺失（49/51） | WIP 提示条 | 播放无声 | 本地缓存 + 降级提示；或换开源音源 | R3Q3 / R1Q3 |
| B4 | XHE 纯文本谱（192 首） | 无播放兜底 | 详情页报错 | 播放器空谱态 + 文本展示 | 按 7.1 默认执行 |
| B5 | 登录下载门禁被绕过 | 文件在 public | 商业规则失效 | 移出 public + 鉴权接口流出 | R4 关联 |
| B6 | 反向点击设循环 | 未定义 | 循环区间异常 | 交换起止 / 取消 / 重置起点 | R2Q2 |
| B7 | 用户拖动进度条中位置回写 | WIP seeking | 跳动 | seek 期间不回写 | 按 7.1 默认执行 |
| B8 | 播放中改谱面（变调夹等） | WIP applyScoreChange | 位置丢失 | 暂停→应用→恢复 tick→继续 | 按 7.1 默认执行 |
| B9 | 今日/周/月窗口跨时区 | Asia/Shanghai 假设 | UTC 主机上日期错位 | 显式时区计算 | 按 7.2 默认执行 |
| B10 | 上传超 30MB / 解析失败 | 422 拒绝 | 无 | 已实现；补充 zip 解压炸弹防护 | 按 9.3 默认执行 |
| B11 | 上传重复曲目 | 无去重 | 脏数据 | Tab 内容哈希去重 | R5Q2 |
| B12 | 文章无作者/无审核 | 直接上架 | 社区治理缺失 | 作者关联 + 审核（管理员） | R5Q1/R5Q2 |
| B13 | 截图服务不可用 | 失败不阻断 | 预览缺失 | 队列 + 重试 | 按 9.2 默认执行 |
| B14 | 多实例部署 | 内存限流失效 | 认证/限流漂移 | Redis 或粘性会话 | R4Q2/R4Q3 |
| B15 | 无搜索结果 / 空关键词 | 展示空态 | 体验差 | 空关键词展示全部或推荐 | R2Q3 |
| B16 | 移动端 390px 溢出 | 已修 grid | 回归风险 | 每里程碑 Playwright 移动端回归 | 按 11 默认执行 |

---

## 9. 潜在技术难点与盲区

### 9.1 版权与品牌合规（最高风险）

- 迁移数据本身来自原站爬取（仅限学习演示，商用前须替换为授权内容）。
- **打印/PDF 水印仍写死「@谱全了」**（`src/lib/printScore.ts`）——直接冒用原站品牌。【待确认·R4Q1】推荐全部替换为 MIMI Guitar 品牌水印，并对迁移内容标注「学习演示」。
- 页脚备案/许可为占位文案（正确）。
- sf2 音源来自原站 CDN，授权状态不明。【待确认·R1Q3】推荐替换为开源音源（GeneralUser GS 等）或本地化自购授权。

### 9.2 生产部署

- 现状无应用容器、无 CI/CD、无对象存储、无反向代理、无 HTTPS。
- 推荐最小闭环（见 5.2、10 的 M8.1）：应用 + PG 容器化，/storage 挂载卷，Nginx + HTTPS，内置 Chromium 的截图 worker。
- 扩展路径（M8.3+）：对象存储 + CDN + Redis 限流 + 多实例。

### 9.3 安全加固清单

| 项 | 现状 | 建议 |
|---|---|---|
| 上传校验 | 大小 + 解析兜底；`looksLikeGp` 存在但未在 upload.ts 使用 | 强制魔数校验；对 GP(zip) 做解压炸弹防护 |
| JWT | cookie httpOnly + lax；secure=false | 生产 HTTPS 置 secure=true；评估 refresh 轮换 |
| 限流 | 进程内存 + 信任 x-forwarded-for 首值 | 生产换 Redis；x-forwarded-for 需代理白名单 |
| 文件访问 | `/storage` 在 public 可直连 | 移出 public + 鉴权接口 |
| 渲染页 | `/render?file=` 仅校验 `/storage/` 前缀 | 加路径规范化（防 `../`）与授权 |
| 文章 | 纯文本渲染（Astro 自动转义） | 若引入 Markdown 渲染须做 XSS 过滤 |
| 密钥 | 生产强制 `JWT_SECRET` | 全部密钥入 secrets，不入库 |
| CSRF | cookie sameSite=lax | 对写操作评估 CSRF token（跨站表单场景） |
| 审计 | 无 | 上传审核、登录失败等关键操作记录日志 |

### 9.4 引擎兼容性（技术债）

- `.ibe` 解码依赖对原站 schema 的逆向与归一化；原站改版即可能批量失效（迁移期 fail=4 已有先例）。
- 缓解：解码失败时给出可读错误与「上报/回退文本谱」；上传链路走自有格式，不受原站影响。
- 建议为解码器补充覆盖真实样本的回归测试集（fixtures），并把 `tests/ibe.test.mjs` 扩为多版本样本。

### 9.5 性能预算

- M6 基线：晴天 1.4s/44MB、Dream Theater 2.7s/283MB、上传曲 1.6s/102MB（首屏，7/6/5 个 SVG）。
- 播放器大 chunk 有已知构建警告。
- 对策：长谱虚拟滚动（R3Q1）、sf2 本地缓存（R3Q3）、按需加载、`preload` 关键资源、CDN 静态缓存。
---

## 10. 分阶段实施计划（生产化路线，v0.1 建议）

> 里程碑编号延续 M8 起；每阶段均需「开发 → 验证 → 记录 DEV_LOG → 合入 master → 主分支回归」。

### M8.0 收口当前 WIP

- 完成并验证 `fix/player-cursor-follow`（播放器增强 + playerMath 单测 + Playwright 证据）。
- 决策：R2Q1（光标跟随行为）、R2Q2（循环边界）在此里程碑落地。
- 验收：`node --test` 全绿、`astro build` 通过、桌面/移动播放器证据、console 零报错。

### M8.1 生产化最小闭环

- 应用 Dockerfile（node dist + 内置 Chromium）与 docker-compose 全栈（app+pg）。
- Nginx/反代 + HTTPS（本地可用 mkcert/自签演示）；cookie secure 开关。
- /storage 移出 public：`SCORE_STORAGE_DIR` 生效；下载改经鉴权接口；render 页加路径规范化。
- 文章/上传/渲染等写操作安全项（9.3）落地。
- 水印品牌替换（R4Q1 结论）。
- 验收：容器内冒烟、关键页面 200、登录下载闭环、无直连绕过。

### M8.2 数据与内容治理

- 数据扩充决策落地（R3Q2）：续爬至目标 或 转为质量优先并补充授权内容。
- 上传审核闭环（R5Q1）：管理员角色 + 审核页 + 去重。
- 文章作者与治理（R5Q2 子项）。
- 验收：审核→上架全流程、重复拦截、数据计数真实。

### M8.3 性能与扩展

- 长谱虚拟滚动/分页渲染（R3Q1）。
- sf2 本地化/开源音源切换（R3Q3/R1Q3）+ 缓存策略。
- 搜索/限流基建升级（Meilisearch / Redis，视 R4Q2 而定）。
- 验收：M6 基线对比不劣化，长谱与弱网场景有证据。

### M8.4 合规与发布

- 授权内容替换或「学习演示」声明强化；无障碍 axe 审计（G10）。
- 正式部署、监控（日志/错误上报）、备份策略（PG + storage 卷）。
- 验收：全站回归 + 上线检查清单。

---

## 11. 验收与测试策略

### 11.1 测试资产现状

- 单测：`node --test`（ibe、player-math、search、sheetform、upload、smoke，当前 19/19）。
- Playwright 验证脚本：`tools/verify-*.mjs`，证据存 `tests/evidence/`。
- 每里程碑：`astro build` + 冒烟 + 桌面/移动截图 + console 零报错。

### 11.2 验收总纲

1. 静态/单测 → 编译/打开目标页 → console/network → 自动化关键流程 → 截图 → 必要时真机预览。
2. 未执行项必须显式记录（如真机、axe），不得当作通过。
3. 合并 master 后跑主分支回归；基线失败须记录且不得扩大。

### 11.3 里程碑验收清单（模板）

- [ ] `npm run build` 通过（大 chunk 警告记录）
- [ ] `node --test` 全绿
- [ ] Playwright 桌面 1440 + 移动 390：目标路由 200、无横向溢出、console/pageerror 零
- [ ] 证据截图归档 `tests/evidence/mX/`
- [ ] DEV_LOG 记录决策、问题与验证结果

---

## 12. 风险与合规汇总

| 风险 | 等级 | 缓解 |
|---|---|---|
| 迁移数据版权 | 高 | 仅学习演示；商用前替换授权内容；来源标记（R5Q3） |
| 水印冒用原站品牌 | 高 | R4Q1：替换为自有品牌 |
| sf2 远程依赖与授权 | 中 | R1Q3/R3Q3：本地化 + 开源音源 |
| `.ibe` 格式兼容 | 中 | 自有格式闭环 + 解码回归样本 + 失败回退 |
| 长谱性能 | 中 | 虚拟滚动 + 性能预算 |
| 无生产部署 | 中 | M8.1 容器化闭环 |
| 上传审核缺失 | 中 | R5Q1：管理员审核 |
| 无障碍未审计 | 低 | M8.4 axe 审计 |

---

## 13. 附录 A：六轮深度访谈脚本

> 每轮 2–3 题，每题给出推荐项与备选项；根线程使用「询问选择工具」逐轮发起。记录决策后回填附录 C。

### 第 1 轮：技术栈选型与文档定位

**Q1（doc_scope）文档定位**
问题：「这份完整可落地的详细项目开发文档应主要覆盖哪个范围？」
- 生产化路线图 (Recommended)：以 M0–M7 为基线，写清部署/性能/安全/运维，可直接指导落地。
- 全站正式规格书：从需求到验收重写为自洽完整规格。
- M8 新功能规划：聚焦下一阶段新功能。

**Q2（stack_policy）核心栈**
问题：「核心技术栈（Astro SSR + Svelte 5 + AlphaTab 1.8.4 + Prisma/PG）是否维持现状？」
- 维持现状深度打磨 (Recommended)
- 局部替换升级（Meilisearch/对象存储/Redis）
- 整体重构（Next.js/React 或自研引擎）

**Q3（engine_policy）乐谱引擎**
问题：「播放器依赖逆向 .ibe 解码 + 原站远程 sf2 音源，这是全站最脆弱环节，文档应如何定策略？」
- 加固现有方案 (Recommended)：本地化音源、解码回退、上传自生成闭环。
- 替换开源音源：GeneralUser GS 等，消除授权风险。
- 远期自研引擎：脱离 AlphaTab。

### 第 2 轮：交互逻辑细节

**Q1（player_cursor）光标跟随**
问题：「播放器光标跟随（当前 WIP）的期望行为是？」
- 音符级平滑跟随 + 手动滚动暂停跟随 + 结束回顶 (Recommended)
- 仅换行/换页级跳转
- 跟随 + 手动优先（需手动恢复）

**Q2（loop_edge）循环反向点击**
问题：「两次点击设循环起止，若第二击早于第一击应如何处理？」
- 自动交换起止 (Recommended)
- 视为取消循环
- 第二击重置起点（需第三次结束）

**Q3（tab_switch_filters）搜索 tab 切换**
问题：「搜索结果在吉他/尤克里里/文章三 tab 间切换时，筛选条件如何保留？」
- 保留共有筛选，文章 tab 忽略乐器专属筛选 (Recommended)
- 切换即重置所有筛选
- 各 tab 独立记忆筛选

### 第 3 轮：边界与异常场景

**Q1（long_score）长谱策略**
问题：「超长谱（如 283MB/2.7s）在移动端与弱网下应如何处理？」
- 懒加载 + 虚拟滚动/分页渲染 (Recommended)
- 维持全量渲染 + 性能预算限制
- 上传时服务端预生成分页快照

**Q2（data_target）数据量与质量**
问题：「数据扩充停在 5267/10000（含 192 首无音频文本谱），边界怎么定？」
- 质量优先，放弃凑数硬指标 (Recommended)
- 恢复爬虫续爬至 10000
- 转向正版/授权内容源

**Q3（offline_audio）音源异常**
问题：「sf2 远程音源在弱网/离线时播放无声，处理策略？」
- 本地缓存 + 降级提示（可静音模式） (Recommended)
- 仅错误提示
- 内置轻量通用音源兜底

### 第 4 轮：潜在技术难点与盲区

**Q1（watermark_brand）水印与品牌**
问题：「打印/PDF 水印目前写死『@谱全了』（原站品牌），如何处理？」
- 全面替换为 MIMI Guitar 品牌水印 + 迁移内容标注学习演示 (Recommended)
- 维持现状（仅演示）
- 下架迁移数据，仅保留用户上传

**Q2（deploy_target）生产部署范围**
问题：「生产化做到哪一步？」
- 单机 Docker 闭环（app+pg+反代+HTTPS，本地卷） (Recommended)
- 上云三件套（对象存储+CDN+Redis，横向扩展）
- 暂不部署（仅本地交付）

**Q3（security_baseline）安全基线**
问题：「安全加固做到什么程度？」
- 补全基线（上传魔数/zip 炸弹、/storage 移出 public、render 路径规范化、cookie secure、限流 Redis 化） (Recommended)
- 维持现状（演示足够）
- 引入 OAuth/第三方登录等更强方案

### 第 5 轮：数据与业务深度

**Q1（review_loop）上传审核闭环**
问题：「当前上传可由上传者本人模拟通过/拒绝，真实审核如何闭环？」
- 管理员角色 + 审核页（user/admin） (Recommended)
- 自动审核（解析成功即上架）
- 暂不做审核（仅入库 pending）

**Q2（model_evolution）数据模型演进**
问题：「模型演进优先补哪些？」
- 按需扩展：文章作者、服务端历史、上传去重哈希 (Recommended)
- 保持最小模型
- 引入全文检索索引（Meilisearch）

**Q3（content_source）内容来源治理**
问题：「迁移数据与用户上传内容如何区分治理？」
- 双层来源标记 source=migrated|uploaded + 展示与运营区分 (Recommended)
- 不区分来源
- 彻底去迁移化（只留用户上传）

### 第 6 轮：确认与收口

**Q1（doc_format）文档形态**
问题：「定稿文档的形态与详略？」
- 可执行规范 + 里程碑任务拆解（含验收标准） (Recommended)
- 技术设计文档为主
- 现状/差距验收报告为主

**Q2（priority）首期优先级**
问题：「若只能先保一个方向，M8 首期优先哪个？」
- 生产化最小闭环（部署+安全+合规） (Recommended)
- 播放器体验与性能（光标/长谱/音源）
- 数据与内容治理（扩充/审核/来源）

**Q3（iteration）迭代节奏**
问题：「初稿后如何迭代？」
- 先完整初稿，再按板块反馈修改 (Recommended)
- 先大纲后展开
- 一次性定稿

---

## 14. 附录 B：关键文件与接口索引

### 核心模块

| 模块 | 文件 |
|---|---|
| `.ibe` 解码/编码 | `src/lib/ibe.ts`、`ibe.node.ts`、`ibe.browser.ts`、`ar.node.ts`、`ar.browser.ts` |
| 播放器 | `src/components/player/ScorePlayer.svelte`、`playerSettings.ts`、`playerMath.ts` |
| 打印/PDF | `src/lib/printScore.ts` |
| GP 上传 | `src/lib/gpUpload.ts`、`src/pages/api/upload.ts`、`src/pages/api/upload/[id]/review.ts` |
| 截图 | `src/lib/screenshot.ts`、`src/pages/render.astro` |
| 查询/筛选 | `src/lib/tabQuery.ts`、`tabMeta.ts` |
| 认证 | `src/lib/auth.ts`、`api.ts`、`rateLimit.ts`、`sms.ts` |
| 数据 | `prisma/schema.prisma`、`src/lib/db.ts` |

### API 一览

| 方法/路径 | 说明 |
|---|---|
| GET `/api/tabs` | 列表（筛选/排序/分页） |
| GET `/api/tabs/[id]` | 详情元数据 |
| GET `/api/tabs/[id]/download` | 登录后下载 .ibe |
| POST `/api/auth/register/login/logout/reset/send-code` | 认证 |
| GET `/api/auth/me` | 当前用户 |
| GET/POST/DELETE `/api/favorites`、`/api/favorites/[tabId]` | 收藏 |
| GET/POST `/api/history` | 浏览记录 |
| POST `/api/upload` | GP 上传 |
| POST `/api/upload/[id]/review` | 审核（当前本人可操作） |
| GET `/api/search?q=` | 搜索 |
| GET/POST `/api/articles` | 文章 |

### 环境变量

`DATABASE_URL`、`PORT`、`SCORE_STORAGE_DIR`（当前代码中 upload/download 仍硬编码 `public/storage`，M8.1 需让该配置真正生效）、`JWT_SECRET`（生产强制）、`SITE_URL`、`CHROME_PATH`。

---

## 15. 附录 C：决策记录

> 六轮访谈完成后回填。格式：
>
> | 决策点 | 选择 | 理由 | 对文档的影响 |
> |---|---|---|---|
> | R1Q1 doc_scope | | | |
> | R1Q2 stack_policy | | | |
> | ... | | | |