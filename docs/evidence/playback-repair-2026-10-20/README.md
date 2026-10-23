# 播放指针与真实试听修复验收

日期：2026-10-20，Asia/Shanghai。工作分支：`fix/playback-cursor-real-preview`。稳定基线：`master@662b69b6`。本轮已完成本地合并、回归与4336运行交接；听感和真机边界见下文。

## 根因与改动

| 问题 | 取得的证据 | 修复 |
| --- | --- | --- |
| 卡片试听与歌曲无关 | 原实现按调性播放固定四和弦，未读取曲谱 | 三种布局共用真实IBE试听；最多播放5秒，准备资源不占试听时长 |
| 试听串曲 | 真实“萱草花”ID曾映射“后来”，其他旧别名指向“晴天”；首页也有过期映射 | 删除替代映射，资源路径必须与曲谱ID相同；核对首页元数据与文件，不用其他曲目补位 |
| 红色指针极淡 | 实际DOM：宽300px、scaleX=0.01，边框计算0.8px且背景透明；边线最终约0.008px | 播放器范围改用实心背景，实际指针宽约3px；保留局部裁剪、层级及鼠标穿透 |
| 全屏仍被导航覆盖 | main单位矩阵transform建立fixed包含块；全屏卡片高度约14603px；elementsFromPoint导航位于谱面前方 | 播放器卡片自身进入原生fullscreen top layer；CSS回退清除main包含块并锁定视口高度 |
| 正常悬浮控制栏落到整页底部 | 页面入场动画使用both保留transform动画的包含块，正常阅读时HUD已显示但在视口外 | full/gentle页面入场仅backwards填充，结束后释放transform与层叠上下文 |
| 页顶进入全屏后无播放控制栏 | window/谱面均未滚动时，`maxScroll > 0`不成立，工具栏已隐藏而HUD仍隐藏 | 通过显式forceVisible使全屏始终显示HUD，退出后恢复滚动阈值 |
| 手稿点击无效 | 事件无接收端，SVG的bNN实际是beat.id；源小节序号也不能直接推演重复后的播放tick | 当前渲染score建立beat→源bar并注入标记；连接主播放器实际tickCache展开实例和seek receipt，确认后再提示成功 |
| 两个底部工具栏重叠 | main包含块释放后，手稿工具条与音频HUD原先同为fixed bottom-6 | 手稿工具条移至页网格前，在手稿section内sticky，给底部音频HUD留出空间 |
| 音频输出污染 | 详情与试听均覆写共享ScriptProcessor输出原型，试听还强制增益/音轨音量 | 恢复安装版本AlphaTab的官方输出与源谱动态 |
| 多轨错音源 | fast SF2自带0/24/25，AlphaTab取最后追加的同bank/program；按分类全轨加载uke会影响钢琴/鼓 | 共用完整、有序音源计划，先fast后独立GM；按四弦轨识别uke；冲突或加载失败明确报错 |
| 旧状态冒充播放就绪 | scoreLoaded/400ms不能确认MIDI已就绪，play返回值不能代替Playing事件 | 等待本次scoreLoaded→playerReady及真实Playing确认；取消、超时清理和失效旧引擎 |

## 真实资源抽样

通过本机已有IBE、Node解码与AlphaTab模型核验；未下载替换媒体、未写数据库。

| 曲谱 | ID | 实际音轨与音源计划 |
| --- | --- | --- |
| 晴天 | `1sdc49P3eKm` | 六弦program25 + 无调弦program0；`acoustic_guitar_fast.sf2` 后加载 `0.sf2` |
| 萱草花 | `1wmj8hqHnYf` | 尤克里里分类，四弦program25 + 四弦program0；`ukulele_fast.sf2` |
| 后来 | `1yDFAg9Z3mU` | 两条六弦program25；`acoustic_guitar_fast.sf2` |
| 稻香 | `20oEfH3di0w` | 两条六弦program25；`acoustic_guitar_fast.sf2` |
| 斑马斑马 | `1sdcWsfNEe0` | 六弦program25 + 无调弦program0；fast吉他后加载 `0.sf2` |

另核对首页9个Hero及4个Masterpiece的ID、曲名、scoreUrl与真实曲库一致，对应13个本地IBE均存在。缺少合适同调可核实资源的“说了再见”精选项撤下；完整曲库仍可检索原曲。静态参考和弦仅作为指法参考，实际音符以原谱为准。

本机 `24.sf2`、`25.sf2`、`acoustic_guitar_fast.sf2` 与 `ukulele_fast.sf2` 字节相同，均含bank0/program0、24、25；`0.sf2`包含Piano 1，`128.sf2`包含bank128标准鼓。按当前安装的AlphaTab 1.8.4 TinySoundFont实际查找顺序安排加载，不依文件名推断其只含一个program。

## 能力和验证边界

- 试听是按曲谱音符合成播放，不能声称是原唱录音或已经人工听音验收。
- XHE纯阅读、缺少资源、跨ID路径、无旋律音符、不可区分的同program音色冲突均应明确失败，不生成假旋律。
- 五秒片段从原谱开头开始；本轮不猜测首个旋律位置。开头存在较长休止的曲谱可能先听到静音，完整播放可从详情进入。
- 浏览器进度、Playing事件、资源清单与截图证明代码和交互链路，不证明扬声器的可闻性、音色自然度或长时间音质。
- 窄屏原生fullscreen结合浏览器视口模拟时，截图工具出现缩小画面和黑色余幅；该截图不计为手机全屏视觉通过。正常窄屏截图和DOM尺寸可核验，真实设备全屏仍待验证。
- 视口测试与Windows Chromium结果不能替代iPad/iPhone/Android真机、Safari音频及触摸测试；本轮未执行这些设备测试。
- 不修改已有真实曲库、本地收藏/练习记录、数据库迁移或媒体文件。

## 检查与交付

变更文件：`src/components/TabCardGrid.svelte`；首页`HeroShowcase.svelte`、`MasterpieceStage.svelte`、`RankingsShowcase.svelte`、`BentoGridFeatures.svelte`；播放器`ScorePlayer.svelte`、`FloatingPlayerHUD.svelte`、`VectorManuscriptRoll.svelte`；`src/lib/scoreAuditionRuntime.ts`、`scoreAuditionFacade.ts`、`scoreAuditionTypes.ts`；`src/lib/player/manuscriptBeatBars.mjs`、`manuscriptSeek.mjs`、`scoreAuditionReadiness.ts`、`scoreAuditionResources.ts`；`src/styles/global.css`、`motion.css`；5个试听/手稿测试文件；本验收记录、截图与修复计划。

全量最终源码测试 `npm test`：476项，469通过，7项数据库集成跳过，0失败；未对真实曲库运行写入型集成测试。

浏览器使用独立候选服务4337和代理自己的标签，本轮已取得下列交互证据：

| 检查 | 观察 |
| --- | --- |
| 晴天卡片原谱试听 | 真正进入Playing，最多5秒自动结束；资源清单仅请求当前IBE、fast吉他和0.sf2 |
| 萱草花旧串曲入口 | 请求自身`1wmj8hqHnYf.ibe`及`ukulele_fast.sf2`，没有请求“后来”文件 |
| 三种卡片布局 | 画廊、列表、展卷可启动同一引擎；列表可明确停止；XHE禁用且说明阅读能力 |
| 快速切换/跨标签焦点 | 切换后仅最后按钮显示播放；详情开始时另一标签试听取消，详情进度推进 |
| 指针 | 普通与全屏实际宽3px，实心朱砂背景、pointer-events:none，谱面保留z0/overflow裁剪 |
| 音源计划重建 | 两轨25+0→0+0→25+0后可开始/停止播放，界面无音源错误；没有据此宣称听感通过 |
| 原生全屏 | DOM `:fullscreen`匹配播放器卡片；卡片y0、高1280，页头不覆盖，音轨面板与HUD可点 |
| 页顶全屏HUD | pageScroll=0、scoreScroll=0时，正常HUD隐藏；进入全屏后aria-hidden=false且非inert |
| 全屏焦点 | 进入后AX/DOM焦点为“退出全屏”；Escape或退出按钮后恢复“全屏显示乐谱”入口 |
| 进度键盘焦点 | ArrowRight可操作悬浮进度条并得到seek更新；`:focus-visible`为true，轨道有蓝色outline |
| 手稿音符定位 | 注入984个真实beat标记；点击第9/10小节音符后，引擎确认tick30720/34560，页面小节与slider同步 |
| 手机正常视口 | 内容与body均375px，手稿工具条宽314.4px不溢出；播放指针可见，HUD宽352.875px、可暂停。原生全屏模拟截图未记视觉通过 |
| 平板正常视口 | 820×1180设置下内容与body均805px，main transform为none，播放器与控制栏不横向溢出；验证后已恢复默认视口 |
| 两个控制栏 | 主谱面时手稿工具条在区域外；手稿中工具条y510、高49.725，音频HUD y626.275、高67.475，留有约66.55px间距 |

最终候选检查：

- `npm run build`：通过，83.88秒。仍有已知的大块体积与Prisma浏览器external构建提示，未将这些提示写成错误。
- `npm run typecheck`：通过，TypeScript/ Astro / Svelte均0错误；Astro 40 hints，Svelte 57 warnings / 18 files。
- `git diff --cached --check`：通过，含新增helper和测试文件；没有提交忽略的构建日志、dist、缓存或资源副本。
- `npm run start:local` 与候选 `/api/readiness`：真实数据库16233曲谱、4项迁移就绪，IBE/XHE各20项抽样存在，核心音源就绪。抽样不等于全曲库均可播放。
- 原目录保护器：1025个受保护文件changed=0，原分支`feature/complete-score-studio@f4ac8ece`和402项状态保持不变。

## 主分支交付记录

- 计划提交：`848af493`；实现提交：`7cd42601`，35个文件；本地no-ff代码合并：`4847f4d4`。后续文档提交收录本节与正式服务截图，不改运行代码。
- 主分支 `npm test`：476项 / 469通过 / 7数据库集成跳过 / 0失败。
- 主分支 `npm run build`：通过，71.58秒。
- 主分支 `npm run typecheck`：通过，0错误；Astro 40 hints，Svelte 57 warnings / 18 files。
- 正式运行工作树为 `D:\MIMIguitarweb-master-merge`，通过其 `npm run start:local` 启动 `127.0.0.1:4336`；仅监听本机。候选4337与临时过渡进程已停止，未重启其他应用或Docker。
- 正式 `/api/readiness`：ready，16233条真实曲谱、4迁移、音源就绪，IBE/XHE各20抽样存在。实际4336详情谱面可加载，播放进度推进、指针/HUD可见，随后已暂停测试声音；该标签console无error/warn。
- 原 `D:\MIMIguitarweb`：1025受保护文件changed=0，原分支/head与402项状态不变；没有把原有未提交改动混入本次提交。
- 浏览器视口覆盖已恢复默认，临时窄屏标签已关闭。保留一张正式4336谱面的交付标签，不刷新用户已有practice/曲库标签或清除其本地资料。
- 未推送、未创建PR、未进行外部部署。下一步可刷新原4336页面复测；真实手机/平板的Safari/音频听感、长时间播放与纯离线体验仍需对应环境验收。

截图存于本目录，包含修复前、候选过程、正式4336截图及明确标注的模拟截图限制。`cursor-after.png`为正式服务实测截图。

## 继续检查与服务恢复

- 继续交付时发现原终端服务和Docker均已退出，4336无法连接。重新启动Docker后，当前后端日志明确报错：`Docker/run/dockerInference`残留套接字无法移除；另一个`docker-secrets-engine/engine.sock`同为零字节ReparsePoint。
- 只停止本轮启动且身份已确认的Docker进程；使用非递归重命名备份两个运行时目录，保留为`run.playback-recovery-20261020-1245`及`docker-secrets-engine.playback-recovery-20261020-1245`，然后启动原Docker Desktop。没有删除卷、VHDX、数据库、备份，也没有执行重置、重装、迁移或导入。
- Docker Engine 29.6.2恢复，原`mimi-guitar-pg`容器自动运行。`npm run start:local -- --check`通过：16233条曲谱。使用原构建从稳定工作树启动独立后台进程，只监听`127.0.0.1:4336`；启动器29556、监听进程47700，日志留在任务外部证据目录。这里是本次后台运行，没有配置开机自启，也不代表已根治Docker重启时的套接字问题。
- 恢复后`/api/readiness`为HTTP 200 / ready：4项迁移已应用、16233条真实曲谱、IBE/XHE各20项抽样存在、3项必需音源存在。没有把资源抽样写成全曲库播放通过。
- 正式4336自己的详情标签实际播放至00:15 / tick17281后暂停；指针实测宽3px、朱砂背景、鼠标穿透，main transform为none；滚动后指针与悬浮控制栏可见且层级正确。截图`restored-cursor.png`；该标签console error/warn均为空，交付时声音已暂停。
- gpt-6-luna/max子代理只读确认`PersonalPractice`键控挂载同一个`ScorePlayer`，曲谱切换、音色计划、seek、HUD与全屏焦点均复用修复链路。此次未操作用户practice标签或练习资料；该页面验证时可能写入断点/曲库版本记录，后续完整练习验收应使用隔离资料。此项是源码连线复核，不宣称再次执行了真实练习全流程。
- 文档合并后再次`npm test`：476项 / 469通过 / 7数据库集成跳过 / 0失败。服务恢复未修改运行源码；构建和类型检查结果沿用本节前已完成的主分支检查。
