# 原生 macOS 构建与安装包

## 0.2.3 本轮产物（2026-10-25）

独立输出目录 `outputs/Native-Mac-0.2.3/` 已包含 `MIMI Guitar.app`、`MIMI-Guitar-macOS-universal2.dmg` 和 `BUILD-MANIFEST.txt`。版本 0.2.3（202610250756），最低 macOS 13.0，x86_64 + arm64。产品 Core -O / App -Osize；未定义诊断宏。

- Universal 构建、lipo、ad-hoc codesign、资源树、hdiutil verify 通过。DMG 只读挂载后的内外 App/Resources 逐文件相同；普通卸载成功。
- Resources 32,649 文件、592,819,671 B；storage 32,599 文件；16,233 首曲谱和 8 篇文章，SQLite integrity=ok。metadata schema_version=2，SQLite user_version=0。
- DMG 560,234,782 B（约 534.3 MiB）；SHA-256 `93b62392a953ffdcbd8b14877aad789198871ca862d107e45f470c81d355f59d`。
- 最终源码诊断 12/12、最终 App 资源复查 5/5 成功；实际产品完整路径启动，12 秒后仍运行。功能诊断不是全部产品 UI 验收，详见 [运行证据](RUNTIME-DIAGNOSTICS.zh-CN.md)。
- 原始报告 `../.build/runtime-audit-023/package-023-verification.json`；[机器可读汇总](diagnostics/0.2.3-results.json)。签名为 ad-hoc，未做 Developer ID 或 Apple 公证；arm64 未实机运行。

## 构建

在 macOS 主机、仓库根目录运行 Universal 2 打包脚本。脚本当前默认版本为 0.2.3，默认输出目录为本任务 outputs 下的 `Native-Mac-0.2.3/`：

```sh
bash native-macos/tools/build_macos_universal_app.sh
```

Universal 2 脚本调用单架构脚本两次，分别构建 x86_64 与 arm64，再合并为 Universal 2。脚本直接调用 `swiftc`，不依赖 `xcodebuild` 或 SwiftPM 构建图，并使用显式 macOS SDK。当前产品编译优化参数为静态 `MIMICore` archive 使用 `-O`、`MIMIGuitarMac` app 使用 `-Osize`；产品构建不定义 `MIMI_RUNTIME_DIAGNOSTICS` 诊断宏。单架构入口为 `bash native-macos/tools/build_macos_app.sh`，其架构默认取当前主机架构。

Universal 2 两个切片的目标分别为 `x86_64-apple-macosx13.0` 和 `arm64-apple-macosx13.0`，最低系统为 macOS 13.0。默认 SDK 为本机 Command Line Tools 的 macOS SDK；可通过 `MIMI_MAC_SDK`、`MIMI_MAC_VERSION`、`MIMI_MAC_BUILD_NUMBER` 或 `MIMI_MAC_OUTPUT_DIR` 覆盖。需要 macOS 主机、macOS SDK，以及 `bash`、`swiftc`、`ditto`、`codesign`、`plutil`、`shasum`、`find`、`xargs`、`sqlite3`、`python3`；Universal 2 另需 `lipo`，生成 DMG 还需 `hdiutil`。交叉编译成功只代表两个切片通过编译和资源合并检查，不等于在 Apple silicon 实机运行验收。

Universal 2 脚本默认产物为 `MIMI Guitar.app`、`MIMI-Guitar-macOS-universal2.dmg` 和 `BUILD-MANIFEST.txt`；单架构脚本的 DMG 名称为 `MIMI-Guitar-macOS-<架构>.dmg`。如果同名 App 或 DMG 已存在，脚本会停止；确认要替换时显式传入 `--replace`。`--no-dmg` 只构建 App。单架构构建中间文件放在 `native-macos/.build/package/`，Universal 2 临时文件放在 `native-macos/.build/universal2.*`。

### 0.2.2 已完成构建的历史记录

以下构建与验收结果属于 0.2.2，不代替上方 0.2.3 的结果。`release-final-build` 是 `-Osize` 独立诊断 App，不是发布包；10 项 `verified-final` 场景在源码诊断 App 中全部通过。随后 0.2.2 Universal `-O` 产品构建生成了 `.app` 和 DMG，结构校验通过。DMG 挂载后的内外 App/资源逐文件比对通过；使用同一诊断 binary 搭配最终 App 资源的 7/7 场景也通过，普通产品 App 启动烟雾检查通过。屏幕关闭时的失败重跑记录保留，屏幕活跃并临时 `caffeinate -di` 包装后同一场景恢复，不代表睡眠/唤醒功能全量通过。旧 `Native-Mac-Full/` 中的 0.2.1 包曾有播放失败，不可作为当前源码的交付包或功能验收证据：

- `MIMI Guitar.app`
- `MIMI-Guitar-macOS-universal2.dmg`
- `BUILD-MANIFEST.txt`

0.2.2 构建记录：版本 0.2.2（build 202610241829），最低 macOS 13.0，包含 x86_64 与 arm64。内容库有 16,233 首曲谱、8 篇文章，storage 有 32,599 个文件；Resources 共 32,649 个文件、592,813,534 B。App 大小约 700,755,968 B，DMG 为 563,044,527 B（约 537 MiB）。`lipo`、各架构/合并/最终 codesign、资源树检查、`hdiutil verify` 和 DMG 挂载后的内外 App/资源逐文件比对均通过。DMG 内 SQLite 完整性、曲谱/文章计数和 Applications 链接检查通过；构建清单记录 Universal 可执行文件 SHA-256 `10e9d7aa86757568355c7f176c2824f14d145887699302a483da97a8479ed5ef` 和 DMG SHA-256 `c5ceb4af88585455777a36c1d710d7100ff1918cee577bca8ab7d6ecbc2dd8e2`。首次卸载因诊断 Python 仍持有只读 SQLite 连接而返回 busy；进程退出释放后普通 detach 成功，未强制卸载，原始负例报告保留。签名为 ad-hoc，不含 Developer ID，也未公证。使用最终 App 资源的 7 次唤醒状态复查全部通过（含一次 staging 对照）；实际产品 App 已按完整路径启动，12.08 秒后仍保持运行。正常启动检查不代表完整视觉与交互验收。

`--no-dmg` 只构建 app。若这些命名的 app 或 DMG 已存在，脚本会停止；确认要替换时显式传入 `--replace`。构建中间文件放在 `native-macos/.build/package/`。

## 随包资源

构建时把现有本地数据和运行资源复制到 app，不启动数据库、不重建目录，也不在线下载：

| App bundle 路径 | 来源 |
| --- | --- |
| `Contents/Resources/AppIcon.icns` | 基于原站 favicon 的原生多尺寸图标 |
| `Contents/Resources/Content/catalog.sqlite` | `native-macos/Data/catalog.sqlite` |
| `Contents/Resources/Content/storage/` | `public/storage/` |
| `Contents/Resources/Content/soundfonts/` | `public/soundfonts/` |
| `Contents/Resources/Player/alphaTab.js` | `public/alphaTab.js` |
| `Contents/Resources/Player/_astro/` | 当前项目的 AlphaTab core/worker/worklet 本地文件 |
| `Contents/Resources/Player/ar.es.js` | `src/lib/vendor/ar.es.js` |
| `Contents/Resources/Player/font/` | `public/font/` 的 9 个白名单字体文件 |
| `Contents/Resources/Player/` | IBE、练习与吉他音频 bundle、页面和样式、AlphaTab 与集成库许可证 |
| `Contents/Resources/Studio/` | 工坊运行时 bundle、页面和样式 |
| `Contents/Resources/Design/` | 原站字体、纸张纹理和和弦数据 |
| `Contents/Resources/Licenses/SONiVOX/` | SoundFont 的本地 LICENSE、NOTICE 与来源说明 |

当前内容库为 16,233 首曲目和 8 篇文章；随包 storage 有 32,599 个文件。SQLite 元数据记录导出时间、来源 revision、行摘要和资源引用检查计数。构建脚本检查 Player/Studio HTML 的全部本地 script/stylesheet 入口依赖，包括 `guitar-audio.bundle.js`，避免复制白名单漏掉已引用脚本。构建清单另外记录 app 资源 SHA-256、签名后可执行文件和 DMG 的 SHA-256、架构、最低系统、大小及数据库完整性检查结果。

运行时使用系统 SwiftUI、AppKit、WebKit 与 SQLite。播放器页面由自定义 `mimiplayer:` scheme 提供本地资源；正常启动不依赖 Node、Docker、PostgreSQL、HTTP 服务或网络。

Player 和 Studio 的音频合成使用本地 Blob Worker：页面先通过各自资源白名单读取随包 `alphaTab.js`，再用其完整内容建立 Worker，避免 Worker 内部通过 `importScripts` 访问自定义 scheme。页面 CSP 只允许 `worker-src blob:`，资源读取仍限定自身来源。`core.useWorkers = false` 仅关闭谱面排版 Worker，不能替代音频合成 Worker；重新禁用后会破坏音频初始化。

### 图标和运行时源码

`AppIcon.icns` 沿用 `public/favicon.svg` 的标识，包含 16–1024 像素的多尺寸图像。可在项目根运行 `swift native-macos/tools/generate_app_icon.swift` 重建。

四个 JavaScript bundle 随工程保存。原生打包脚本复制并校验这些成品，不执行 npm 安装或在线构建。修改 `ibe-entry.ts`、`practice-runtime-entry.ts`、`guitar-audio-entry.ts`、`studio-runtime-entry.ts` 或其共享 TypeScript 依赖后，需要先重建对应 bundle。当前 IBE/Studio bundle 用 esbuild 0.27.7、browser/iife、ES2020、inline legal comments 构建；共享代码中的 `ar.es.js?raw` 用仅针对该文件的文本加载插件处理。PDF/PNG 的完整排版与限制来自 `src/lib/printScore.ts`；PDF 页面交给系统 CoreGraphics 合成为 A4 文件。

## 本地安装（0.2.3）

打开 [0.2.3 DMG](../../../Native-Mac-0.2.3/MIMI-Guitar-macOS-universal2.dmg)，将 MIMI Guitar 拖到 Applications。更新前先保存并退出旧版，再从应用程序打开新版，版本应为 0.2.3。完整步骤及本轮改动见 [安装说明](../../../Native-Mac-0.2.3/安装说明.zh-CN.md)。打包脚本使用 ad-hoc 签名，没有 Developer ID 证书，也没有公证；本机包检查不等于已完成可公开分发的 Gatekeeper 安装流程。

个人数据保存在 `~/Library/Application Support/com.mimi.guitar.mac/`。成功发布的文章正文另存于该目录的 `published-articles.json`，按已配置的服务地址隔离，以便成功发布后可以立即在原生版阅读。新安装的原生数据库为空；它不会读取网页 IndexedDB，也不会自动导入浏览器收藏、待练、片段、练习会话或备份。

## 迁移范围与验收边界

- 本目录承载完整界面和功能迁移；具体页面/状态按 [FULL-PARITY-MATRIX.zh-CN.md](FULL-PARITY-MATRIX.zh-CN.md) 记录。0.2.3 的结构恢复、播放和保存证据不代表全清单已验收。
- SwiftUI/AppKit 承担窗口、导航、工具栏、控件与个人资料；随包 AlphaTab JavaScript 在系统 WebKit 中渲染/合成乐谱。IBE、Guitar Pro（gp、gp3–gp8、gpx）和 MusicXML 有相应路径；XHE 仅文字谱。MIDI 与独立 .gpif 不在注册/导入范围。
- 0.2.3 已复查代表性 IBE/GP5/MusicXML、实际 Player/Practice 播放、Studio 编辑/保存/试听，以及主要和次要页面快照。未覆盖全曲库、全部格式变体、全控件或物理设备听感；未恢复原网页服务用于同状态像素比较。
- 性能结论来自独立 -Osize 诊断，和产品 Core -O / App -Osize 分开：曲库尾部延迟和工坊编辑有改善，首页没有测出整体改善。FPS、WebKit/GPU/WindowServer 全部开销、能耗和长期稳定未测。完整方法与逐轮数据见 [运行记录](RUNTIME-DIAGNOSTICS.zh-CN.md)。
- Finder/拖入、原生保存/打印/分享面板、完整备份恢复、并发/中断/强制退出、睡眠恢复、Retina 和 Apple silicon 实机仍须逐项验收。源码诊断或 App 启动不能代替这些结果。
- 构建脚本执行双架构编译、HTML 本地入口依赖、哈希/资源、Info.plist、只读 SQLite、codesign、lipo 和 hdiutil verify；未新增或运行自动化测试套件。
- 本包为 ad-hoc 签名，未做 Developer ID 或 Apple 公证。字体再分发边界沿用 Design/Fonts/NOTICE-Fonts.zh-CN.md：其中 FZXiaoBiaoSong.TTF 的来源授权尚未证实，不能描述为已获公开发行许可。
