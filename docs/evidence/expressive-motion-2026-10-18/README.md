# 全站动效与交互验收

日期：2026-10-18 至 2026-10-19；证据目录沿用起始日期 `expressive-motion-2026-10-18`。计划见 [expressive-motion-development-plan.md](../../expressive-motion-development-plan.md)。本地候选服务为 `127.0.0.1:4338`，独立 IAB Chromium 标签。原 4336 工坊标签没有导航、刷新或编辑。

## 实际变更

- 共享 `motionPreferences.ts`、无 UI 的 `MotionRuntime` 与 `/motion` 偏好区域。跟随系统/轻柔/静止只存当前浏览器，系统 reduce 优先；读取失败保守静止，写入失败当页仍生效。SSR、非法值、首屏脚本、跨标签与共享监听清理有行为测试。
- `motion.ts`、MotionDialog、分段控件与纸页共享有效模式。轻柔只淡入，静止即时到终态；wrapper 之外的谱面/播放动画不被结束。根 CSS 暂停隐藏页面的 CSS 时间线，保留功能定位 transform。
- `paperReveal` 不让已绘制的首屏 SSR 内容突然透明；焦点进入即落定。首页典藏与榜单在 idle 安装观察器，卡片入场有界；曲目选择即时提交，不等待翻转定时器。首页背景、两套粒子及展厅光标示例遵守偏好和清理边界。
- 曲库三个视图接共享短动效、选择状态及 44px 目标，保留服务端查询与演示提示。实测发现并修复 `sort=0` 被删除的旧缺陷：最新上传现在能正确选择，其他筛选零值仍表示清除。
- 我的谱拆分搜索与导入类别，搜索输入使旧请求失效；队列事务成功后重排。备注显式保存、取消、重试与冲突保留；冲突刷新当前资料，只提供取消草稿后重新编辑。
- 工坊快捷键新增搜索/分类、完整 Mac 组合别名；工具栏/混音台/指板目标扩大、窄屏换行，内部 tab 改淡入。已有四种 modal 和异步护栏没有重写。选中指板音符不再常驻脉冲。
- 备份保留真实准备/校验阶段，并允许重下清单和当前已准备卷；准备下一卷会替换当前 Blob，此限制在页面明确说明。未改变备份格式或恢复 CAS。
- 展厅容器移除只影响局部 CSS 的旧模拟开关，显示共享有效模式并链接全站设置；开场回放受实际模式控制，八组模块保留。移除机器设计目录、引擎版本和未经证明的帧率承诺。最终类型检查发现的计数回放旧函数引用已修复，交付前重新执行检查。

## 浏览器观察

原始观察：[browser-observations.json](browser-observations.json)。原始数据包含早期缺陷与桥接不支持的尝试；下文区分最终复核，不把空观察或早期失败算通过。

1. 轻柔刷新保留、静止仍可操作、系统 reduce 覆盖存储值。两个普通页面实际同步偏好；初次从探针父页读 iframe 根属性未取得桥接对象，后来以普通页面完成复核。
2. [frame-summary.json](frame-summary.json)、[frames-full.json](frames-full.json)、[frames-gentle.json](frames-gentle.json)、[frames-off.json](frames-off.json) 来自只读 [motion-frame-probe.html](../../../tools/motion-frame-probe.html)，它通过真实点击采样公开 DOM 的 transform/opacity/RAF 时钟，不注入个人数据或私有播放器状态。完整模式体验底片的 `viewIndicatorValues` 有 34 个不同位置；跨所有观察控件的不同值合计 35 个 (`distinctTransformCount`)，约 461ms/76 样本。轻柔/静止各只有一个底片终值。其他样本出现约 50ms 的间隔，只证明本条件下的过渡与偏好分支，不能宣称持续 60/120fps。
3. 自制谱通过真实文件选择器导入。初次两小节试听自然结束，未计为连续性通过；`self-authored-motion.json` 改为十六小节/双轨/60 BPM。随后反复切指板/调音台并打开、搜索、关闭帮助，仍显示 `⏸`、游标推进，公开 `.at-surface` backend ID 保持 2692，最终正常暂停。未检查可闻性或长时运行。
4. 快捷键搜索、分类、空结果清除和 Escape 返回触发器；手机弹层中各按钮高度 44px。窄屏初测发现工具栏时值组和邻接组溢出，已修为换行；最终 320px 工坊复测记录 `clientWidth=305`、`scrollWidth=305`、`openDialogs=0`（`studio-320-final-toolbar`），此前约 1px 的差值属于修复前的 `studio-320-settled`。Mac 组合查询发现 `Cmd S` 被去空格后误命中 `Cmd Shift Z`，改按完整 key 组合匹配并加入精确结果断言；最终 `Cmd S` 只显示 1 个保存快捷键。
5. 队列第二项上移后由人工 UI 观察确认重载顺序保留；结构化 JSON 的 `library-order-and-category` 只记录单次顺序，不单独证明重载前后变化。导入分类贝斯不会改在线搜索吉他。修改搜索输入会取消旧请求。备注保存重载保留；另页保存后，本页提交基准冲突保留原草稿且无无效重试，取消后显示另页新值。离页尝试后仍在原页、输入保留，桥未暴露可操作原生确认窗，未据此宣称原生弹窗通过。
6. 分卷真实准备清单和 1 卷，初次及再次发起后按钮仍可用，计数 1/1 不重复增加。页面始终写明应用不能确认设备最终保存；未核验文件落盘或重做完整恢复/大容量验收。
7. 曲库三个视图切换、初级筛选与最新上传复测：`/tabs?difficulty=2&no=1&sort=0` 对应最新 radio=true，前进/后退保留。联网数据库不可用，页面明确标演示；未作为真实目录排序数据库验收。
8. 最终展厅复测：静止模式显示共享状态、回放开场禁用、八组模块可选择；切到完整模式后跨标签实时同步。计数回放先显示计算中、再恢复目标值和可重播按钮，所检查模块的 console error 列表为空。最终重新加载确认页首已说明内置示例、不代表实时目录统计。验收标签已关闭，视口模拟已清除，4338 的测试偏好恢复跟随系统。

## 复建与边界

运行 `node docs/evidence/expressive-motion-2026-10-18/prepare-fixture.mjs` 生成自写十六小节 JSON，仅通过 UI 导入。夹具基于先前自写的两小节练习，重建小节/音符标识并设 60 BPM；没有第三方曲谱输入。

`__expressive-motion-qa.html` 只临时复制到候选 dist，不进入产品入口/最终主分支 dist。截图是浏览器实际界面。早期 CDP 模拟受 Windows 截图比例影响，最终截图改用明确的浏览器视口控制并覆盖了同名图片；所有临时视口/媒体模拟在结束前清除。

已有数据库用例在无专用数据库时继续跳过；构建/类型检查不能代替真实音频、触摸或 Safari。iOS/Android/iPad、虚拟键盘、屏幕阅读器、200% 系统字号、2 小时/30 分钟播放、生产联网曲库和 1 GiB 备份未执行。没有独立 Lint 脚本。

## 候选分支检查

2026-10-19，最终源码冻结后执行：

| 命令 | 实际结果 |
| --- | --- |
| `npm test` | exit 0；358 total / 351 pass / 7 数据库 skip / 0 fail |
| `npm run build` | exit 0；57.42s；保留既有 AlphaTab 大 chunk 及 Prisma browser external 告警 |
| `npm run typecheck`（构建完成后） | exit 0；TypeScript / Astro / Svelte 0 errors；41 Astro hints、57 Svelte warnings / 18 files |
| `git diff --check` | exit 0 |
| 原树保护脚本 | exit 0；1023 文件哈希差异 0；402 行 Git 状态差异 0 |

相对基线 58 条 Svelte warnings / 19 files、44 Astro hints 没有增加警告。中途类型检查发现的展厅计数旧函数引用已修复，以上为重新执行后的结果。

## 主分支交付

功能提交 `2cdde1f9`，计划提交 `1d6a910f`；由 `feature/expressive-motion-experience` 以 `--no-ff` 合入 master，功能合并提交 `e8ca5315`。完整文件清单见 [changed-files.txt](changed-files.txt)，结构化结果见 [verification.json](verification.json)。

在 `D:\MIMIguitarweb-master-merge` 实际执行 master 回归：`npm test` exit 0（358 / 351 pass / 7 skip / 0 fail）；`npm run build` exit 0（15.98s）；完成后 `npm run typecheck` exit 0（0 errors、57 Svelte warnings / 18 files、41 Astro hints）。`git diff --check` exit 0，功能合并后的工作树干净。最终交付记录只追加 docs，源代码保持与该回归版本一致。

4336 已重启到合并版本：health 200/alive，`/motion` 200 且包含全站偏好，`/studio` 200；临时 QA 路由 404，最终 dist 无 QA HTML。三个必要音源 HEAD 200，dist 文件 SHA-256 均与原目录来源一致。readiness 实际为 503/not_ready，database/catalog unavailable，soundfonts 3/3 ready；这是隔离测试数据库未运行的环境，不能当作生产目录已就绪。

结束保护复核 exit 0：1023 文件哈希差异 0、402 行 Git 状态差异 0。原目录仍在原功能分支，未清理、提交或改写其中的用户改动。原工坊浏览器页保留，没有导航、重载或编辑；QA 的两个独立标签和服务已关闭，视口已恢复。不推送、不创建 PR、不部署。
