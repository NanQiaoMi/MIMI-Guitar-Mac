# AGENTS.md — MIMI Guitar (Web + macOS 原生双端仓库指南)

本文件面向人类开发者与 AI Agent，提供仓库结构地图、常用验证/构建命令与工程红线。修改架构、核心模块或构建/测试命令时，必须在同一 PR 中同步更新本文件。

---

## 1. 项目定位与双端架构

- **Web 端**：Astro 5 + Svelte 5 + Tailwind v4 + Prisma（PostgreSQL 16）+ AlphaTab 1.8.4。负责全量曲谱库展示、在线播放器、练习室（A-B 循环 / 提速计划 / 个人数据备份）与创作工坊（Studio）。
- **macOS 原生端（`native-macos/`）**：SwiftUI + AppKit + WebKit + SQLite（通过 `CSQLite` 绑定）。最低支持 macOS 13.0，支持 `x86_64` + `arm64` Universal 2 打包；通过自定义 `mimiplayer:` scheme 提供本地播放器资源，**运行时不依赖 Node、Docker 或 PostgreSQL**。

---

## 2. 目录地图

```text
MIMI-Guitar-Mac/
├── src/                         # Web 端源码
│   ├── pages/                   # Astro 页面路由与 API 端点
│   ├── components/              # Svelte 5 / Astro 组件（播放器、练习室、工坊等）
│   ├── lib/                     # 业务逻辑、IBE/XHE 编解码、个人备份、播放器核心
│   ├── layouts/                 # 页面布局
│   └── styles/                  # 全局样式与纸纹主题
├── prisma/                      # PostgreSQL Schema 与数据库迁移
├── public/                      # 静态资源、AlphaTab 脚本、字体、storage（已 gitignore）
├── tests/                       # Node 内置测试（node --test tests/*.test.mjs）
├── tools/                       # 构建校验、资源检查、本地启动、数据库测试等 CLI
├── docs/                        # 架构计划、恢复文档与验收证据（docs/evidence/）
├── .github/workflows/           # CI 工作流（validate.yml：Web 端检查与构建）
├── native-macos/                # macOS 原生端（SwiftPM / swiftc 构建）
│   ├── Sources/
│   │   ├── MIMICore/            # 曲库 SQLite 读取、个人存储、IBE/核心模型
│   │   ├── MIMIGuitarMac/       # SwiftUI/AppKit 窗口、菜单、播放器桥接与视图
│   │   └── CSQLite/             # 系统 SQLite C 模块桥接
│   ├── Resources/               # 原生端嵌入的 Player / Studio / Design / 字体资源
│   └── tools/                   # macOS 原生构建与 bundle 生成脚本
├── DEV_LOG.md                   # 历史开发里程碑与端到端验收记录
└── package.json                 # Web 端脚本与依赖（要求 Node >=24.0.0 <25）
```

### 关键进度与构建文档入口
- 全局历史进度：`DEV_LOG.md`
- Mac 接续开发 Backlog：`docs/mac-next-development-backlog.md`
- macOS 原生端实施与验收状态：`native-macos/IMPLEMENTATION-STATUS.zh-CN.md`
- macOS 原生端打包与资源说明：`native-macos/BUILDING.zh-CN.md`

---

## 3. 常用开发、测试与构建命令

### Web 端（仓库根目录执行，要求 Node 24.x）
- 启动开发服务：`npm run dev`
- 生成 Prisma Client：`npm run prisma:generate`
- 运行单元/集成测试：`npm test`（部分库用例依赖可访问的测试库）
- 运行隔离数据库测试：`npm run test:db`
  - 注意：`tools/test-database.mjs` 强制校验 `DATABASE_URL` 必须指向本地名为 `mimi_platform_test` 的数据库，严禁指向生产或用户真实曲库。
- 全量类型与模板检查（TS + Astro + Svelte）：`npm run typecheck`
- 生产构建：`npm run build`
- 检查静态曲谱资源完整性：`npm run resources:check`

### macOS 原生端（仓库根目录执行，依赖 Xcode Command Line Tools / macOS SDK）
- 重新生成主谱渲染 bundle（修改播放器/渲染入口或共享依赖后执行）：
  ```sh
  node native-macos/tools/build_score_rendering_bundle.mjs
  ```
- 单架构构建（默认当前主机架构）：
  ```sh
  bash native-macos/tools/build_macos_app.sh
  ```
- Universal 2（`x86_64` + `arm64`）打包与 DMG 生成：
  ```sh
  bash native-macos/tools/build_macos_universal_app.sh
  ```
  - 常用参数与环境变量：`MIMI_MAC_BUILD_JOBS=4` 指定并行编译数；`--no-dmg` 仅构建 `.app`；`--replace` 覆盖已有同名产物。

---

## 4. 核心开发与 Git 规范（红线）

1. **Git 分支与 PR 纪律**
   - 严禁直接在 `main` 分支编码、提交或推送；所有改动必须基于最新 `origin/main` 拉出规范前缀分支（`feat/`、`fix/`、`ci/`、`docs/`、`refactor/` 等）。
   - 推送并创建 PR 后，必须跟踪 `.github/workflows/validate.yml` 至全绿；禁止未获人工确认擅自合并 PR。
2. **敏感信息与大文件隔离**
   - 严禁提交 `.env`、`.env.mac.local`、密钥凭证、构建产物（`dist/`、`.astro/`）或大体积本地媒体库（`public/storage/`）。
3. **数据库安全边界**
   - `npm run test:db` 与本地恢复脚本仅允许操作隔离测试/开发实例（如 `mimi_platform_test` 或 `mimi-guitar-mac-dev`），严禁执行破坏性 `--clean` / `DROP` 误伤已有数据。
4. **文档同步**
   - 涉及架构调整、核心模块变更或启动/构建命令变化时，必须在同一 PR 内同步更新 `AGENTS.md` 及对应状态文档。
