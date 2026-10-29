# GitHub 源码发布说明

日期：2026-10-29。目标仓库：`NanQiaoMi/MIMI-Guitar-Mac`（公开）。

本仓库是独立的源码快照，包含当前 Web、原生 macOS 源码、现有回归检查和项目文档。开发仓库的旧提交历史未导入，避免已排除的资源随历史公开；开发目录与未提交改动保留。

## 未附带内容

- `.env` 与本机配置、依赖目录、构建缓存、`.app` 和 `.dmg`。
- 本机 PostgreSQL、`native-macos/Data/catalog.sqlite` 和 `public/storage/` 曲库媒体。数据库结构与迁移脚本保留；曲库导出方法见 `native-macos/Data/README.md`。
- `FZXiaoBiaoSong.TTF` 与 `FZXiaoBiaoSong.woff2`：原项目未附再分发授权，公开快照不携带二进制文件。本地原件保留。需要这些文件的原生资源校验须先按原说明准备合法资源；此快照不承诺直接生成完整安装包。
- 父目录的宣传片工程、数据库备份和其他交付档案。

第三方代码、字体与音源沿用各自许可和署名，相关声明保留。此轮没有为项目另行授予开源许可证。

## 使用与验证范围

Web 开发使用 Node.js 24，执行 `npm ci`、`npm run prisma:generate` 和 `npm run dev`。完整曲库需要独立数据库及媒体。macOS 构建入口为 `native-macos/tools/build_macos_universal_app.sh`，所需 SDK、资源和实际验收边界见构建说明。

GitHub Actions 沿用 `.github/workflows/validate.yml`，运行数据库集成检查、现有回归检查、类型检查和生产构建。实际远端运行结果以 Actions 页面为准；该流程不验证原生 App、Apple silicon 真机或安装体验。

## 本次快照的实际检查

- TypeScript、Astro、Svelte 类型检查退出码 0；Astro 40 条 hints，Svelte 57 条 warnings，均为 0 errors。
- Astro 生产构建退出码 0，保留大型 chunk 警告。
- Node 全量回归：550 通过、3 失败、7 跳过。失败来自 `guitar-sample-playback`、`sample-note-renderer`、`verified-score-soundfont` 所需的 `public/storage/soundfonts/ukulele_fast.sf2` 缺失；不是测试全部通过。7 项跳过与未配置的数据库有关。
- CI 中也未配置该音源的配送，因此资源相关回归预计仍会失败；没有跳过或削弱这些检查。需要独立准备 SHA-256 为 `e57ba29a8040ed9afd336e0ebe2bb39090369cd1bd14e1e476f01be9e5089b38` 的原始音源才能运行相应场景。
- 常见密钥特征扫描无匹配；暂存内容没有环境配置、SQLite 数据、构建缓存、依赖符号链接或超过 10 MiB 的文件。该扫描不等于完整安全审计。
- 现有文件包含空白格式诊断；本次保留源码与第三方文件原格式，未作全仓格式重写。
- 未运行数据库集成验收、原生 macOS 编译、App 启动或实机交互验收。
