# 项目开发计划（PLAN.md）——「谱全了」全站复刻

> 历史记录：下文保留2026年8月复刻阶段的目标与完成声明，不代表当前工作区完整验收。2026-10-15起，下一阶段以[个人练习平台开发计划](docs/platform-development-plan.md)、[现状审计](docs/platform-audit-2026-10-15.md)与[任务验收清单](docs/platform-backlog-and-acceptance.md)为依据；优先个人本地练习与备份，公开社区/账号同步后置。

## 1. 项目概述与目标

在 `D:\MIMIguitarweb` 从零复刻 [guistudy.com](https://guistudy.com/)（谱全了）的全部功能，乐谱的**显示与播放**为核心。视觉采用 refero「General Intelligence Company」编辑风设计系统（严格落地、替代字体、全站套用）。

- 范围（用户确认）：全站全功能 —— 前台（首页/列表/详情/播放器/搜索/文章）+ 用户系统（注册登录/收藏/浏览记录/资料）+ 上传创作中心。
- 技术栈（用户确认）：与原站一致 —— Astro 5 SSR + Svelte 5 岛屿 + Tailwind v4 + 官方 AlphaTab（@coderline/alphatab）；后端 Node + PostgreSQL + Prisma。
- 数据（用户确认）：迁移原站热门子集（1000–2000 首，吉他/尤克里里）。⚠️ 版权风险：原站有版权政策，迁移数据仅用于学习演示，商用前须替换为授权内容。
- 权限（用户确认）：全开放 —— 游客可用全部功能，登录仅用于收藏/浏览记录/上传同步（与原站不同，按此实现）。
- 音源（用户确认）：沿用原站按乐器程序号分发的 sf2 文件。
- 验收（用户确认）：每步 Playwright 自动化验收 + 截图证据 + 控制台零报错，写入 DEV_LOG.md。

## 2. 目标站点逆向分析结论

### 2.1 站点结构
| 页面 | 说明 |
|------|------|
| `/` | 首页：热门/今日/本周/本月排行榜、推荐列表 |
| `/tabs`、`/tabs/[id]` | 吉他谱列表与详情（含播放器） |
| `/ukulele`、`/ukulele/[id]` | 尤克里里谱列表与详情 |
| `/article`、`/article/[id]` | 文章列表与详情 |
| `/search` | 搜索 |
| `/upload` | 上传 |
| `/account/0-3` | 我的账号 / 我的收藏 / 创作中心 / 浏览记录 |
| `/login`、`/register` | 登录注册 |
| 静态页 | /about /help /policy /agreementPolicy /copyrightPolicy /licenses /contact |

### 2.2 技术栈（逆向确认）
- 前端：Astro SSR + Svelte（Melt UI）+ Tailwind；Vite 构建；Swup 页面转场。
- 乐谱引擎：自研 fork 的 AlphaTab 1.3.0（全局 `window.nier`），含 `NierApi`、`JcxScoreAdapter`、`BinaryImporter`、`JsonConverter`。
- 谱面数据：`.ibe` 文件 = XOR 加密（密钥 `guitartabspro`，自 `文件长度 % 10` 偏移起循环异或）→ AR 压缩（公开库 `ar.es.70ff2b48.js`，暴露 `window.ar`）→ **alphaTab JSON 谱面**（站点为 alphaTab 1.3 驼峰 schema，官方 1.8.4 为全小写，已实现归一化）。
- 音频：Web Audio 合成（alphaSynth），按声部 program 动态加载 SoundFont2：`https://p.insstudy.com/puquanle/soudfont/{program}.sf2`（program 128 = 鼓组）。
- API：基址 `/api`，路径形如 `/appbiz/...`、`/auth/...`；RUM 上报 `rum-api.insstudy.com`。

### 2.3 播放器功能清单（逆向确认）
- 控制：播放/暂停、重来（stop）、速度（30–300 BPM）、预备拍、节拍器、循环。
- 变调夹：`transpositionPitches` 转调后重渲染（非原生 capo 字段）。
- 显示：字体缩放（`display.scale` 重渲染）、数字谱开关（`avoidInChordFretNumber` 重渲染）。
- 循环：两次点击音符/小节设定 startTick/endTick → `playbackRange` + `isLooping`，`.at-loop-start`/`.at-loop-end` 标记。
- 高亮滚动：cursor 高亮（`.at-cursor-beat`），滚动容器 `#swup-container`、`scrollOffsetY:-200`，播放结束回顶。
- 多轨：声部显示/独奏/静音/音量（masterVolume 0.7）；乐器切换弹窗用 128 号 GM 中文映射表；跳过 `@$Strumming$@`/`@$Chords$@` 轨。
- 打印/下载：打印 = 隐藏容器重渲染 + `window.print()`；PDF = SVG 按 A4 分页 → Canvas → JPEG → jsPDF，水印 `@谱全了+上传者`，文件名取页面标题。
- 元数据：上传者、难度、类型、调弦（六线）、Capo、调性、速度、拍号、热度、日期、标签、相关推荐。

### 2.4 列表页筛选（URL 参数，SSR）
`/tabs?difficulty=0-5&style=101-109&key=C..B&tuning=Standard..&sheetForm=0-4&sort=0/1&no=页码`
- difficulty：0全部 1零基础 2初级 3中级 4高级 5专业
- style：101摇滚 102金属 103流行 105民谣 107乡村 109配乐
- sheetForm：1弹唱 2指弹 3和弦 4六线

## 3. 技术栈选型（已确认）

| 层 | 选型 | 理由 | 备选 |
|----|------|------|------|
| 前端框架 | Astro 5 SSR | 与原站一致，SSR 列表/详情 + 岛屿交互 | Next.js |
| 组件 | Svelte 5 | 与原站一致 | React |
| 样式 | Tailwind CSS v4 | refero token 以 Tailwind v4 theme 落地 | CSS Modules |
| 乐谱引擎 | @coderline/alphatab 1.8.4（官方） | 开源 MIT；含 Guitar Pro 解析、SVG 渲染、Web Audio 播放、SoundFont 支持 | 原站定制 fork（黑盒，弃用） |
| 压缩 | ar.es 公开库（vendored） | 与原站 `.ibe` 格式兼容 | 标准 deflate（需改上传/迁移两端） |
| 后端 | Astro 服务端 + Prisma | 单进程 SSR + API，本地优先 | 独立 Fastify 服务 |
| 数据库 | PostgreSQL 16（Docker） | 用户确认；中文全文检索后续可加 | SQLite（演示） |
| ORM | Prisma 6 | 类型安全、迁移管理 | Drizzle |
| 认证 | JWT（access+refresh） | 简单可控 | OAuth（后续） |
| PDF | jsPDF 4 | 与原站一致的分页方案 | pdfmake |
| 验收 | Node test + Playwright | 计划要求 | Vitest |

## 4. 数据模型（Prisma schema，已建）

- **User**：email/phone（唯一）、passwordHash、nickname、avatarUrl。
- **Tab**：id、title、artist、category(guitar/ukulele)、difficulty(0-5)、style、key、tuning、sheetForm(0-4)、bpm、timeSig、capo、tuningText、heat、uploader、publishDate、scoreUrl(.ibe)、screenshotUrl、description、tags(JSON)。
- **Favorite**：userId+tabId 唯一。
- **UploadRecord**：userId、title、artist、fileName、scoreUrl、status(pending/approved/rejected)。
- **Article**：title、content、category。
- 索引：category+筛选组合、category+heat、category+createdAt、artist、title。

## 5. 谱面数据管线

### 5.1 `.ibe` 解码（浏览器 + Node 双端）
```
.ibe 字节 → XOR 解密（密钥 "guitartabspro"，自 len%10 偏移循环）→ AR 解压（ar.es）→ alphaTab JSON（驼峰→小写归一化）→ `model.JsonConverter.jsonToScore` → Score
```
### 5.2 迁移爬虫（tools/migrate.mjs，Node）
1. 爬 `/tabs`、`/ukulele` 列表页（sort=热度 分页）收集曲谱 id 与元数据。
2. 请求详情页提取 sheetInfo：scoreUrl、title、artist、bpm、capo、defaultTrack、type、难度/类型/调性/调音/拍号/热度/上传者/日期/标签。
3. 下载 `.ibe` 与截图到 `public/storage/scores/`。
4. 解码校验（与官方截图对比渲染结果）。
5. 入库（Tab 表），`.ibe` 用自有密钥重新加密保存（或直接保存解码后的 gp 二进制 + 运行时可解密的自有密钥）。
### 5.3 上传管线（后端 API）
Guitar Pro 上传 → 校验/解析（alphaTab Node）→ AR 压缩 → XOR 加密生成 `.ibe` → 服务端渲染截图（Playwright 无头）→ 入库 UploadRecord + Tab（审核通过后）。

## 6. 系统架构与目录结构

```
D:\MIMIguitarweb
├── astro.config.mjs / package.json / tsconfig.json
├── docker-compose.yml            # PostgreSQL
├── prisma/schema.prisma
├── PLAN.md / DEV_LOG.md / README.md
├── public/
│   ├── storage/scores/           # .ibe + 截图（gitignore）
│   ├── storage/soundfonts/       # {program}.sf2（脚本拉取）
│   └── storage/gp/               # 上传原始 gp 备份
├── src/
│   ├── styles/global.css         # Tailwind v4 + refero token
│   ├── lib/                      # prisma 客户端、ibe 编解码、配置
│   ├── components/               # Svelte 组件（播放器、列表项等）
│   ├── layouts/                  # Astro 布局
│   └── pages/
│       ├── index.astro
│       ├── tabs/index.astro, tabs/[id].astro
│       ├── ukulele/index.astro, ukulele/[id].astro
│       ├── article/index.astro, article/[id].astro
│       ├── search.astro / upload.astro
│       ├── account/[section].astro
│       ├── login.astro / register.astro
│       └── api/...               # 后端 API 端点
├── tools/                        # 迁移、音源拉取、截图等 Node 脚本
└── tests/                        # Node 单测
```

## 7. API 设计

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/tabs` | 列表筛选（SSR 也可直查 DB） |
| GET | `/api/tabs/[id]` | 详情元数据 |
| POST | `/api/auth/register` / `login` / `refresh` / `logout` | 认证（邮箱/手机+密码，验证码本地 mock） |
| GET/POST/DELETE | `/api/favorites` | 收藏 CRUD |
| GET/POST | `/api/history` | 浏览记录（localStorage 为主，可选服务端同步） |
| POST | `/api/upload` | 上传 gp（multipart） |
| GET | `/api/search?q=` | 搜索（PG ILIKE，标题/艺人） |
| GET | `/api/articles` | 文章列表 |

## 8. 分阶段实施计划（里程碑）

| 里程碑 | 内容 | 验收标准 |
|--------|------|----------|
| M0 ✅ | 工程初始化：Git、脚手架、PG、PLAN/DEV_LOG | `astro build` 通过；PG 健康；基线提交 |
| M1 ✅ | 数据管线：ibe 解码/迁移/入库/上传生成 | 1000-2000 首入库；解码渲染与官方截图一致；单测通过 |
| M2 ✅ | 播放器：渲染+全控制+循环/变调夹/速度/多轨/PDF/打印 | Playwright 交互验收；控制台零报错 |
| M3 ✅ | 前台：首页/列表/详情/搜索/文章/静态页 | Playwright 验收：15 页面全部 200 零报错；筛选/分页/搜索生效；截图证据 |
| M4 ✅ | 用户系统：注册登录/收藏/历史/资料 | Playwright 验收：注册/登录/重置/收藏/登出全流程通过，零报错 |
| M5 ✅ | 上传创作中心 | Playwright 验收：GP 上传→解析→.ibe→截图→审核→详情播放全流程通过 |
| M6 ✅ | 设计打磨与性能 | 全站 refero 视觉验收；长谱/多轨性能；移动端；无障碍；安全 |
| M7 ✅ | 对齐原站功能+交互：账号路由/导航/搜索页/首页结构/详情信息区与分享下载/社区文章/静态页页脚/视觉微调/数据扩充 | Playwright 全站验收（新增路由×桌面/移动零报错）；搜索三 tab 计数与筛选、下载 .ibe、文章发布全流程通过；数据扩充完成：11955 首入库（吉他 7934/尤克里里 4021，可播放 8129），达成 ≥10000 目标；astro build + node --test 全绿 |
| M8 ✅ | 谱面显示补齐：歌词（旋律轨）显示、和弦名+和弦图（指法图增强）、调性 key 头部行与转调提示、旋律/数字谱对齐（双轨渲染：有 tuning→Tab、无 tuning→Numbered） | verify-score-details 7/7（歌词/和弦/调性/数字谱/移动端/ukulele）；node --test 38/38；astro build 通过；播放器与 M7 回归 10/10+9/9+41/41 |
| M9 ✅ | 乐器/技巧音效补齐：全 129 GM 音源覆盖（0-128 sf2 从原站 CDN 下载+立体声转单声道+index.json）、贝斯击勾 tap/slap/pop MIDI 力度增强（官方 midiLoad 事件后处理）、鼓组核对、技巧音效可闻性抽查（推弦/滑音/闷音/延音/泛音/琶音/全乐队） | verify-instrument-fx 12/12、verify-bass-articulation 4/4（193/193 力度差精确）、verify-technique-fx 9/9、node --test 63/63、astro build 通过、全量播放器回归不破坏 |

## 9. 边界与风险清单

- 版权合规：迁移原站数据仅学习演示；商用前替换为授权内容（风险最高）。
- 音源授权：原站 sf2 为公开静态资源；预留切换开源音源（GeneralUser GS）替换点。
- `.ibe` 格式兼容：解码算法来自逆向，需用真实样本持续验证；上传管线生成文件需自测可播。
- 中文搜索：PG ILIKE 在 1-2k 数据量足够；预留 Meilisearch。
- 性能：长谱/多轨渲染用懒加载、虚拟滚动；SoundFont 按需加载并缓存。
- 兼容性：桌面优先（用户确认），移动端适配后置；音频需用户手势后启动（浏览器策略）。
- 安全：JWT 存储、密码哈希（bcrypt/argon2）、上传文件类型校验、路径穿越防护。

## 10. 测试与验收总纲

- 单元测试：`tests/`（ibe 编解码、迁移解析、API 基础）。
- 自动化验收：Playwright（打开页面→交互→截图→控制台零报错）。
- 主分支回归：每里程碑合入后跑全量冒烟（`astro build` + 关键页面加载）。
- 记录：全部写入 DEV_LOG.md；未通过不进入下一步。
