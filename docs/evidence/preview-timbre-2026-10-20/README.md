# 试听时长与音色一致性验收

日期：2026-10-20，Asia/Shanghai。分支：`fix/preview-length-timbre-consistency`；稳定基线：`eb83f850`。本记录随实现和验证更新，未完成项目保持明确标记。

## 根因和处理

| 已取得证据 | 对应更新 |
| --- | --- |
| 卡片与facade都写死5秒上限 | 默认30秒，可选60秒；加载不计入时长，明确停止及完整乐谱入口 |
| 原24/25及两份fast文件同字节，内部为三份Ukulele preset | 标准GM改用安装包内完整Sonivox；尤克里里仅使用其需要的专用预设 |
| 原89.sf2只装program90，不能提供所选program89 | 标准GM完整源含真实89与90，不再按数字文件名猜内容 |
| 类别和四弦猜测覆盖明确选择的钢琴/吉他 | 区分源谱flavor和用户显式GM覆盖，提供恢复原谱音色 |
| 和弦/指板使用随机建模，与谱面SF2不同 | 使用相同已验证SF2与AlphaTab公开引擎生成PCM |
| 虚拟指板子组件与父回调各发声一次 | 每次交互仅一条发声路径，显式使用当前轨道音色 |
| 工坊仍覆盖共享ScriptProcessor输出原型，另有旧fast路由 | 移除全局音频输出覆写，工坊按其明确GM选择使用相同完整音源 |
| 关闭指板、离页或重载时仍可能留下异步采样请求 | 统一管理指板试听代次与session，关闭、切换、pagehide和销毁均取消旧声音 |

## 音源身份

- 本地只读扫描131份SF2，未写原媒体。完整审计脚本和原始报告保留在任务外部证据目录。
- 新标准音源来自已安装`@coderline/alphatab@1.8.4/dist/soundfont/sonivox.sf2`，1351896字节；SHA-256为`4978cf37e7164206f2d22dc4fdf4020ffe040787210bf781e31bdc79961f59ef`。使用本地包内容，没有下载其他音频替代。
- 该文件有128份bank0 GM及4份bank128鼓预设。旧Ukulele源仅用于明确的原谱尤克里里发声；通过隔离预设避免其额外0/24/25覆盖标准GM轨道。
- 程序编号、预设身份、真实引擎PCM和人的听感是不同证据；不能用文件名、按钮变色或Playing事件替代乐器自然度验收。

## 验证进度

- 时长facade定向行为测试：18项通过；覆盖30/60秒、无效参数、加载不计时、自然结束、旧计时器与句柄取消。
- readiness定向行为测试：8项通过；必需音源改为完整GM与Ukulele两份，缺GM时不就绪。
- 真实AlphaTab离线渲染已覆盖标准GM、bank128鼓组、隔离Ukulele的0/24/25、休止、预设缺失、无效输入和中途取消。采用公开API，无音频设备访问。
- 最终候选全量`npm test`：523项 / 516通过 / 7数据库集成跳过 / 0失败。额外3项验证指板关闭、迟到session、销毁与重复释放。
- 源谱与固定GM的断点标记可向后兼容；旧记录无标记时仅把不同于源program的值解释为用户覆盖，保守保留相同值的原谱音色。新布尔标记在校验、导出恢复数据和续练准备中保留。
- 交叉复审发现并修复了泛型加载完成事件的竞态：每API在真实worker加载回执前保持串行barrier，调用方取消不释放barrier，超时/失败后的实例拒绝复用；`soundfont-load-receipt.test.mjs`覆盖迟到通知、取消、超时、独立实例和失败。
- 含指板取消补丁的最终候选`npm run build`、`npm run typecheck`均以0退出，构建64.95秒；TS/Astro/Svelte均0错误。Astro仍有40 hints，Svelte仍有18文件57 warnings，构建保留既存大chunk和Prisma提示。

## Windows真实浏览器验收

候选验收使用隔离的`127.0.0.1:4337`；交接后仅在代理自己的4336曲库标签验证卡片试听，未改动用户4336个人资料。以下是界面及引擎状态证据，不代表人工听音验收。

| 场景 | 实际结果 |
| --- | --- |
| 晴天 `1sdc49P3eKm`，默认30秒 | 观察到10/30秒继续播放，之后自动回到未播放；无控制台错误。`preview-30s.png`记录播放过程 |
| 切为60秒 | 所有卡片可访问标签同步，观察到29/60秒继续播放；`preview-60s.png`记录控件、停止及完整乐谱入口 |
| 播放中改时长 | 旧片段取消，播放状态和停止入口消失，不自动开启新片段 |
| 画廊、列表、展卷 | 三种布局均显示同一30/60秒策略；展卷实际启动并手动停止成功 |
| 晴天原谱钢弦→GM24尼龙→GM0钢琴→原谱 | 标签、选择值和播放进度同步；播放中切换先暂挂再恢复；暂停时恢复原谱不自行播放。`source-timbre.png`记录恢复结果 |
| 和弦试听 | 原谱钢弦状态下点击G和弦试听，没有未处理错误；采用真实SF2/PCM链路的行为由引擎测试覆盖 |
| 尤克里里萱草花 `1wmj8hqHnYf` | 两轨分别明确显示原谱尤克里里钢弦/原声，显式GM24尼龙覆盖可以播放 |
| 尤克里里同预设冲突 | 主轨改GM0钢琴、另一轨保留Ukulele0时明确提示bank0/program0冲突并暂停。主轨恢复原谱后错误解除且可继续播放，没有静默替换另一轨音色 |
| 最终构建375px窄屏 | 观察到准备提示不消耗时长，之后16/30秒实际播放；停止控件可用，document宽度与scrollWidth均360px（375px视口扣滚动条），无横向溢出。`preview-mobile.png`记录准备与换行；测试后已恢复视口 |
| 最终构建指板取消 | 打开指板、点击1弦空弦后立即关闭，指板状态回到未显示，无控制台错误。取消迟到发声的session行为由新增3项测试验证；没有声卡采集证据 |
| 正式4336的60秒周期 | 观察到准备提示后34/60秒实际播放，未手动停止，之后自动回到未播放并移除试听状态；无控制台错误。`stable-preview-60s.png`来自正式服务。交付时已无测试声音并保留曲库标签 |

## 本地运行恢复

- 续接时原服务进程和Docker引擎均已停止。Docker当前日志报`initializing Inference manager`无法移除`Docker/run/dockerInference`，与此前Secrets Engine的陈旧AF_UNIX端点问题同类。
- 参考[Docker公开问题记录](https://github.com/docker/desktop-feedback/issues/554)中的父目录保留恢复方法，先通过官方CLI停止已失败Desktop，核对绝对路径后只重命名运行端点目录`Docker/run`和仅有`engine.sock`的`docker-secrets-engine`，并重新创建空运行目录。保留目录后缀为`timbre-recovery-20261020-1655`；没有删除或重建镜像、卷、WSL发行版及数据库文件。
- 启动后既存`mimi-guitar-pg`为healthy，候选readiness为ready，曲库16233条、4迁移已应用、2份必需音源存在。资源readiness仅抽样20份score和20份XHE，不等于全曲库媒体完整性审计。
- 主分支回归完成后，4336已切回`D:\MIMIguitarweb-master-merge`的正式构建。最终交接时监听PID22784、启动器PID43180，均为本任务通过`tools/start-local-catalog.mjs`隐藏启动的Node进程；PID仅记录本次观察，不作为后续停进程的依据。

## 提交、文件与最终回归

- 工作分支：`fix/preview-length-timbre-consistency`；实现提交依次为`6e27d765`（计划）、`572752c4`（30/60秒）、`ebc4a82b`（readiness）、`069af3f4`（统一音源/覆盖与取消）。通过`--no-ff`合入稳定`master`的提交为`39d17f48`。验收补充为后续仅文档提交，未更改该构建的运行代码。
- 主分支`npm test`：退出0，523项、516通过、7数据库集成跳过、0失败；`npm run build`：退出0，58.65秒；之后顺序运行`npm run typecheck`：退出0，TS/Astro/Svelte均0错误，Astro40 hints、Svelte18文件57 warnings与候选相同。保留既存大chunk/Prisma提示，不把跳过与提示计为全绿设备验收。
- `git diff --check`及暂存检查通过。原目录保护校验：1025个文件、changed0、状态未变，原`feature/complete-score-studio@f4ac8ece`及其402项状态均保留。
- 最终readiness：ready、曲谱16233、迁移4/4、必需音源2/2；正式dist的Sonivox哈希与来源固定值一致。服务错误日志为空。首次人工听音与真机验收仍在下述边界内。

| 变更文件组 | 作用 |
| --- | --- |
| `TabCardGrid.svelte`、`scoreAuditionFacade.ts`、`scorePreviewDuration.ts` | 卡片30/60秒、加载不计时、显示进度、停止及完整乐谱入口 |
| `verifiedScoreSoundfont.ts`、`scoreAuditionResources.ts`、`scoreAuditionRuntime.ts`、`soundfontLoadReceipt.ts`、`public/soundfonts/sonivox.sf2` | 固定身份、预设计划、串行回执与失败恢复 |
| `ScorePlayer.svelte`、`TabMetadataDeck.svelte`、`scoreInstrumentOverrides.ts`、`gmInstruments.ts` | 原谱/GM覆盖与恢复、主轨作用域、正确名称 |
| `guitarSound.ts`、`sampleNoteRenderer.ts`、两份`VirtualFretboard.svelte`、`PlayerShowcase.svelte`、`fretboardAuditionLifecycle.ts` | 共用采样PCM、单次发声和取消/清理 |
| `ScoreCanvas.svelte`、readiness API/helper | 工坊移除全局输出覆写、使用相同GM；检查实际必需音源 |
| `personal/types.ts`、`personal/validation.ts`、`practice/practiceProgress.ts`及相关测试 | 覆盖标记与原谱断点向后兼容 |
| `tests/*soundfont*`、`sample-note-renderer`、`guitar-sample-playback`、`fretboard-session-lifecycle`等测试与`tools/render-instrument-comparison.mjs` | 真引擎离线PCM、时序/取消/冲突验证及可复现音色对照工具 |
| 本计划/证据目录、`docs/third-party/sonivox-soundfont` | 验收截图、已知边界、来源和许可 |

## 验收边界

- 保留原数据库与本地个人资料；写入型数据库集成不在真实曲库执行。
- 浏览器只在代理标签测试，不操作用户practice中的断点、队列或备注。
- Windows浏览器和离线PCM不能替代iOS/Android真机、扬声器听感与长时间音质；这些项目尚未执行。
- 尚未实现相同bank/program在同一引擎同时映射为两种flavor；遇到这类混合音轨必须恢复原谱或调整另一条音轨，系统会明确提示。音源预设身份与GM映射已经核验，不能据此承诺采样自然度等同真实录音。
- 音源方案遵循[AlphaTab多音源加载说明](https://www.alphatab.net/docs/guides/multiple-soundfonts/)及[loadSoundFont替换/追加接口](https://docs.alphatab.net/docs/reference/api/loadsoundfont)，具体行为以安装的1.8.4源码与实际引擎测试为准。
