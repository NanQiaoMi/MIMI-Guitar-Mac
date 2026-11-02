# MIMI Guitar

<p align="center">
  <strong>专为吉他与尤克里里乐手、创作者打造的高性能互动乐谱系统与跨平台桌面应用</strong>
</p>

<p align="center">
  <a href="https://github.com/NanQiaoMi/MIMI-Guitar-Mac/releases"><img src="https://img.shields.io/badge/Release-v0.2.4%20(Universal%202)-0969da.svg" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-13.0+-black.svg" alt="macOS 13.0+" />
  <img src="https://img.shields.io/badge/Architecture-Universal%202%20(Apple%20Silicon%20%2B%20Intel)-6f42c1.svg" alt="Universal 2" />
  <img src="https://img.shields.io/badge/Web-Astro%205%20%2B%20Svelte%205-1a7f37.svg" alt="Web Stack" />
  <img src="https://img.shields.io/badge/License-MIT-gray.svg" alt="License" />
</p>

<p align="center">
  <a href="#-核心功能">核心功能</a> •
  <a href="#-系统架构">系统架构</a> •
  <a href="#-快速开始">快速开始</a> •
  <a href="#-macos-原生构建">原生构建</a> •
  <a href="#-开源许可">开源许可</a>
</p>

---

## 📌 项目介绍

**MIMI Guitar** 是一套面向吉他与尤克里里演奏者、乐理学习者和制谱创作者的数字乐谱解决方案。项目采用现代化的软件工程架构与优雅的纸质书卷视觉风格，提供 **Web 端应用** 与 **macOS 原生桌面端** 双重体验：

- **高性能乐谱引擎**：基于深度定制的 AlphaTab 与 Web Audio API，实现毫秒级时钟调度与连续平滑自动滚屏（Continuous Follow-Scroll），彻底告别切小节跳帧与指针微抖。
- **全格式与音频合成**：支持 Guitar Pro 全系列、MusicXML 及自研高压缩乐谱格式；内置经典 GM 采样音源，支持各声部独立混音、Capo 变调与 50%~200% 高保真无级变速。
- **专业演练套件**：专为突破指法瓶颈打造的 A-B 循环攻坚、渐进式递增提速训练器（Speed Trainer）以及练习日志留痕。
- **全离线与本地优先**：原生 macOS 版开箱内置 16,000+ 首曲目数据库，不依赖网络与外部服务即可离线秒开；个人数据支持符合规范的分卷备份与跨设备无损迁移。

---

## 🌟 核心功能

### 1. 交互式乐谱播放器
- **全格式解析**：支持 Guitar Pro（`.gp`, `.gp3`–`.gp8`, `.gpx`）、`.musicxml`、自研 `.ibe` 矢量谱及 `.xhe` 和弦谱。
- **声学合成与混音**：各音轨独立控制（音量 / 静音 / 独奏）、实时节拍器对拍伴奏、Capo 变调夹移调运算。
- **自适应视觉卷轴**：高清晰度矢量乐谱排版，配合纸质墨韵底纹，支持全屏沉浸演练模式。

### 2. 动态指板与和弦系统
- **动态指法映射**：播放时琴颈位置毫秒级同步点亮当前声部所处品位与音符。
- **和弦库与即时试听**：内置常用大调、小调与扩展和弦图谱，点击指板或和弦卡片即可触控发声对照。

### 3. 个人智能练琴套件 (Practice Suite)
- **A-B 循环攻坚**：自由选定乐句小节设置循环区间，支持保存为命名练习片段与独立备忘。
- **阶梯式提速训练器**：设定循环遍数与速度步进（例如每练习 2 次平稳提速 5%），科学建立肌肉记忆。
- **练琴历史与续练**：自动记录各曲目累计练琴时长与速度达成度，防误触退出保护，一键“继续上次”。

### 4. 制谱工坊与排版导出 (Score Studio)
- **交互式制谱**：支持电脑键盘与虚拟指板双向录入音符，实时校验小节节拍与音值。
- **多轨混音与歌词排版**：双轨对齐的歌词抽屉，和弦调色板快捷插拔，本地草稿实时容灾暂存。
- **高清矢量导出**：支持标准乐谱格式导出及 CoreGraphics 高清矢量 A4 PDF 打印。

### 5. 原生 macOS 桌面深度优化
- **双架构支持**：Universal 2 架构，原生适配 Apple Silicon (M1/M2/M3/M4) 与 Intel 芯片。
- **极速离线体验**：内置 SQLite 曲库索引与随包媒体，采用专有方案本地解析，脱离网络秒级响应。

---

## 🏗️ 系统架构

```
┌──────────────────────────────────────────────────────────────┐
│                       MIMI Guitar 核心                       │
├──────────────────────────────┬───────────────────────────────┤
│       🌐 Web 端架构           │       🍎 macOS 原生桌面端      │
│  • Astro 5 (SSR / 路由)      │  • SwiftUI / AppKit 窗口系统  │
│  • Svelte 5 (Runes 交互岛屿) │  • WebKit 自定义协议方案桥    │
│  • Tailwind CSS v4 样式系统  │  • 原生菜单 / 手势 / 打印     │
│  • Prisma ORM + PostgreSQL   │  • 内置 SQLite 离线曲库       │
├──────────────────────────────┴───────────────────────────────┤
│                   🎼 共享乐谱与音频处理中枢                   │
│  • 定制 AlphaTab 1.8.4 渲染管线 (Canvas / SVG 矢量排版)       │
│  • Web Audio API + Blob Worker 多音轨采样实时合成             │
│  • rAF 驱动的平滑连续跟谱控制器与动态虚拟指板                 │
│  • 本地数据存储与 RFC 标准分卷备份/恢复引擎                   │
└──────────────────────────────────────────────────────────────┘
```

### 技术选型矩阵

| 维度 | 技术栈 | 作用与特点 |
| :--- | :--- | :--- |
| **前端框架** | Astro 5 + Svelte 5 | 兼顾 SSR 首屏极速加载与 Svelte Runes 响应式零运行时交互开销 |
| **样式与设计** | Tailwind CSS v4 | 极简书卷质感排印，支持标准减弱动效（prefers-reduced-motion） |
| **乐谱引擎** | AlphaTab 1.8.4 (Custom) | 深度定制排版流水线，消除切节抖动与重绘性能瓶颈 |
| **音频管线** | Web Audio API + SONiVOX | 支持独立音轨混音、Capo 变调、50%~200% 无级变速与 Blob Worker 合成 |
| **桌面运行时** | SwiftUI + AppKit + WebKit | 纯原生窗口外壳与系统事件分发，Universal 2 双架构支持 |
| **数据存储** | SQLite 3 (原生) / PostgreSQL (Web) | 原生内置曲库毫秒级全文检索，网页端采用 Prisma 6 ORM |

---

## 🚀 快速开始

### 方式一：下载 macOS 原生桌面版（推荐）

直接下载预编译好的 Universal 2 DMG 镜像，无需任何开发环境依赖：

1. 从 [GitHub Releases](https://github.com/NanQiaoMi/MIMI-Guitar-Mac/releases) 下载最新版本 `MIMI-Guitar-macOS-universal2.dmg`。
2. 双击打开镜像，将 `MIMI Guitar.app` 拖入 `Applications` 文件夹即可完成安装。

> [!TIP]
> **macOS 安全提示**：如初次打开提示未经验证，请在访达（Finder）中按住 `Control` 键单击应用并选择“打开”。

---

### 方式二：本地运行 Web 开发环境

#### 1. 前置要求
- **Node.js**：`>= 24.0.0`
- **Docker Desktop**（可选，用于运行本地 PostgreSQL 曲库服务）

#### 2. 安装与启动
```bash
# 进入工程目录
cd project

# 安装依赖
npm ci

# 生成 Prisma 客户端
npm run prisma:generate

# 启动本地开发服务 (http://localhost:4321)
npm run dev
```

#### 3. 生产环境构建与验证
```bash
# 静态类型检查
npm run typecheck

# 单元测试运行
npm test

# 生产环境打包
npm run build
```

---

## 🔨 macOS 原生构建

若需从源码构建 macOS 原生 Universal 2 应用程序与 DMG 安装包：

```bash
cd project

# 1. 编译乐谱渲染核心 Bundle
node native-macos/tools/build_score_rendering_bundle.mjs

# 2. 编译 Universal 2 原生 App 与 DMG 镜像
# 构建脚本直接调用 swiftc 交叉编译 x86_64 与 arm64，产物输出至 outputs/Native-Mac-<版本>/
bash native-macos/tools/build_macos_universal_app.sh --replace
```

---

## 📄 开源许可

- **项目源码**：采用 [MIT License](LICENSE) 协议开源。
- **乐谱底层**：感谢 [@coderline/alphatab](https://github.com/CoderLine/alphaTab) 开源社区的技术底座支持。
- **音源资产**：集成采样音源遵循开放分发许可规范（详见 `docs/third-party/`）。
- **设计规范**：视觉排版遵循现代编辑设计系统规范。
