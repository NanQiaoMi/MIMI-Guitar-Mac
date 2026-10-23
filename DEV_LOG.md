# 开发记录（DEV_LOG.md）

> 规则：每次开发完成后必须及时更新本节，不积压；验收必须有明确标准与证据（测试结果/截图/控制台日志）。未通过不进下一步。

## 2026-10-19 原谱404与本地资源交付修复

- 用户反馈谱面加载失败。独立4336详情页真实复现：`/storage/scores/1sdc49P3eKm.ibe` 404，主播放器和画卷同时失败；稳定public/dist仅132个音源文件，原目录原谱存在且15份演示谱均可解码。上轮仅检查音源与页面200不足以验证原谱交付。
- `fix/score-resource-delivery` 从稳定 `a140638e` 创建，计划见 `docs/score-resource-delivery-plan.md`。三名既有gpt-6-luna/max代理完成只读审查，资源工具草稿期间遇额度限制；主代理接手全部后续实现、修复草稿缺陷并实际验证，未把代理中断算作通过。
- 增加显式资源准备/检查CLI：只读本地scores/xhe/screenshots/soundfonts，先全量预检哈希与冲突，仅向独立目标追加；拒绝junction、嵌套路径、未知类型和空资源，不覆盖/删除已有文件，不复制upload，不联网。验证source/public/实际dist及演示引用，媒体与清单缓存不入Git。原候选storage只移除链接本身，建立独立副本；原目录保护仍零差异。
- 主播放器/画卷共享结构化文件请求，区分404/410、权限、5xx、HTML200、空文件、网络/超时与解码/排版。失败取件不再建议下载同一失效地址，明确重试使用reload；已获取原件的解码错误仍保留下载。画卷重试释放旧实例及回调，超时/卸载作废迟到结果。
- 最终候选 `npm test` exit0：432 total/425 pass/7数据库skip/0fail；`npm run build` exit0/45.24s；构建资源check exit0：32,595文件/554,546,235 bytes/source-public-dist无哈希差异；随后typecheck exit0/0errors，既有Svelte57warnings/18files、Astro40hints。首轮2处请求参数类型声明错误已修复后重新构建检查。
- 实际候选浏览器：晴天20主谱SVG、21页画卷；尤克里里16主谱SVG。只临时移开候选dist的同一原谱验证404，哈希核对恢复后两处重试成功；原public和用户文件未动。独立域名经文件选择器导入测试IBE、加入待练、进入练习、tick从110推进到111193并暂停。15演示谱+3音源+截图+文本谱共20次HTTP取件均200且原件哈希一致。真实设备、可闻性、长期音频和真实数据库恢复未执行，master回归/4336最终交付另记证据。
- 本地no-ff合并 `1e72c391` 后master全量回归exit0：432/425通过/7数据库skip，build60.93s，实际dist逐文件核验32,595文件与source/public一致、typecheck零错误与既有57条Svelte警告。4336已重启，20项原件取件200且哈希一致，原错误标签两处重试恢复；新客户端20主谱SVG/21页画卷/无error。health200而readiness因隔离不可达数据库保持503。QA4338及本轮临时标签已清理，保留恢复详情供查看；原用户练习标签未刷新，原1023保护文件及402状态行零差异。证据见 `docs/evidence/score-resource-delivery-2026-10-19/README.md`。

## 2026-10-19 页面导航速度与稳定过渡

- 基线 `master@939cf5f7`，实施 `feature/fast-page-navigation`，三名既有gpt-6-luna/max子代理独占目录/动效/试听与保存边界，主代理集成及实测。完整计划见 `docs/fast-page-navigation-plan.md`，证据见 `docs/evidence/fast-navigation-2026-10-19/README.md`。
- 主要等待来自不可达目录数据库：普通目录每次约2秒、全部分类搜索8277ms。公开读单次共享连接探测+10秒退避，首页/分类/文章独立读并行，共用榜单回退，分页越界修正；真实Prisma初始化异常缺code，补精确错误名/连接消息分类，认证/写/readiness及明确P2024不纳入。最终HTTP冷探测2013ms保留，连续吉他谱约5–11ms、全部搜索7.87ms；演示与不可用始终明示，未知文章断连返回503。
- 保留MPA和原生离页保护；只为无Cookie匿名四个目录顶层页意图预取，private10秒+Vary Cookie，其余no-store。慢网/Save-Data额外抑制Astro的tap例外；按压不改布局或拦默认导航。首次试听才加载约1.23MB AlphaTab/解码器/音源；pagehide停止pending播放，工坊pending/failed保存与待组合品位输入有原生离页护栏。
- 稳定基线和候选在当前Chrome155/IAB均会出现原生VT“Page already revealed”跳过，新增早期pagereveal观察及main轻入场回退，不全局吞错。最终真实full动画0.28s且观测中opacity0.929/0.940；gentle0.14s，off无动画。预取后练习到曲库在完整URL确认下410ms（含工具等待，不是帧率或严格统计样本）。四种宽度无横溢出，菜单、列表、命令面板、首次试听/暂停/离页返回、工坊保存切页返回核验。
- 最终候选 `npm test` exit0：419 total/412 pass/7数据库skip/0fail；`npm run build` exit0/38.87s；随后 `npm run typecheck` exit0/零错误，Svelte既有57warnings/18files、Astro40hints。没有独立Lint脚本。首次集成类型错误与实际退避未生效均修复后重跑，未将失败算作通过。
- 本地no-ff合入master `f605bd98`，master再次 `npm test` / `npm run build` / `npm run typecheck` 均exit0：419/412通过/7数据库skip/0fail，build11.66s，零类型错误与既有57条Svelte警告。4336已重启为新构建，health200；readiness503如实保留数据库/目录不可用，3/3音源200。合并后HTTP热吉他谱4.60ms、窗口内搜索7.21ms，冷探测2031.24ms仍保留。
- 用户原目录1023保护文件与402行Git状态最终差异0；本轮临时4338服务和自建浏览器标签已清理，保留4336运行且未刷新用户标签。无真实数据库/卷/迁移修改，无远程推送/PR/部署。真实Safari/Android/iOS、pending/error浏览器故障注入、生产数据库恢复与恒定帧率未执行。详见上述证据目录的交付记录。

## 总体进度看板

| 里程碑 | 状态 | 说明 |
|--------|------|------|
| M0 工程初始化 | ✅ 完成 | Git 基线、Astro 5+Svelte 5+Tailwind v4、PG(Docker 5433)、Prisma 迁移、PLAN/DEV_LOG |
| M1 数据管线 | ✅ 完成（1624 首入库） | ibe 解码/迁移/入库全部完成；上传生成管线已具备（MIMI 格式编解码单测通过） |
| M2 播放器 | ✅ 完成（自动化验收通过） | 谱面渲染+全套控制+循环/变调夹/速度/多轨/PDF/打印，吉他+尤克里里双端零报错 |
| M3 前台 | ✅ 完成（自动化验收通过） | 首页/列表/详情/搜索/文章/静态页；筛选/排序/分页/搜索/播放器回归零报错 |
| M4 用户系统 | ✅ 完成（自动化验收通过） | 认证/收藏/浏览记录/个人资料；重置密码与登录跳转 |
| M5 上传创作中心 | ✅ 完成（自动化验收通过） | GP 上传→解析→.ibe→截图→审核占位→公开展示；播放器音源清单优化 |
| M6 设计打磨与性能 | ✅ 完成（自动化验收通过） | 全站 refero 视觉验收、移动端适配、无障碍、安全加固、性能基准；最终全站 39/39 验收通过 |
| M7 对齐原站功能+交互 | ✅ 完成（分支 feat/m7-parity 合入 master） | 账号路由/导航/搜索页/首页结构/详情信息区与分享下载/社区文章/静态页页脚/视觉微调；数据扩充完成：11955 首入库（断点保留，可续爬） |
| M8 谱面显示补齐（歌词/和弦图/调性/旋律对齐） | ✅ 完成（分支 feat/score-details-lyrics-chords-key） | 双轨渲染、歌词、和弦名+和弦图、key 头部行+转调提示、数字谱 OFF/ON 旋律对齐；verify-score-details 7/7 |
| M8.1 和弦名位置修复 | ✅ 完成（分支 fix/chord-positions 合入 master） | 根因：ChordDiagrams=true 把唯一和弦集中渲染到首个 system 上方；改为 EffectChordNames 后按 system/拍对齐参考站；verify-score-details 7/7 |
| M8.2 和弦指法图完全显示 | ✅ 完成（分支 fix/chord-diagrams-overlay 合入 master） | 自绘覆盖层：每处和弦名上方显示完整指法图，与歌词共存、可开关；verify-score-details 8/8 |
| M8.3 和弦图表条（不压谱、完整显示） | ✅ 完成（分支 fix/chord-chart-strip 合入 master） | 弃用自绘覆盖层（几何越界+压谱）；改为谱面上方专用和弦图表条（15 卡完整指法图，滚动容器外不压谱）；enableLazyLoading=false 修复谱面完整渲染；数字谱标记直接调用修复；verify-score-details 8/8 |
| M8.4 和弦显示模式切换（仅字母 / 字母+完整指法图逐位内联） | ✅ 完成（分支 feat/chord-inline-mode） | 用户改需求：不要顶部图表条，指法图固定到对应谱面位置；原生逐拍 ChordDiagramGlyph（globalDisplayChordDiagramsInScore）实现，歌词共存；模式切换保留播放位置；移除图表条；verify-score-details 8/8 |
| M8.5 谱面字体统一 Cascadia Code + 文字重叠修复 | ✅ 完成（分支 feat/score-font-cascadia） | 全部谱面文字换 Cascadia Code（CJK 回退微软雅黑，@font-face 自托管）；修复头部标题裁剪/Tab 品数堆叠/段落标记与和弦名碰撞；段落标记因官方 1.8.4 无法分离而隐藏（已知取舍）；验证 8+10+9+41+38 全绿 |
| M8.6 播放器音频生效（转调/变调夹/乐器切换 → MIDI 重生成） | ✅ 完成（分支 fix/player-audio-midi） | 显式 loadMidiForScore 重生成播放 MIDI + readyForPlayback 就绪等待；capo/降半调/整曲转调/乐器切换后音频真正生效；verify-player-audio 12/12，8+10+9+41+38 全绿 |
| M8.7 谱面显示模式切换（吉他谱+简谱 / 全部六线谱） | ✅ 完成（分支 feat/second-track-jianpu） | 多六弦音轨曲谱不再「两排六线谱」：主音轨六线谱+其余音轨简谱（对齐参考站），可切换回全部六线谱；AlphaTab 全音符休止符简谱崩溃已数据层守卫；verify-track-mode 6/6（新增）+ 50+8+10+9+12+41 全绿 + build 通过 |
| M8.8 全音符休止符修复（简谱渲染崩溃） | ✅ 完成（分支 fix/whole-rest-numbered-renderer） | 次级音轨全音符休止符（duration=1）触发 AlphaTab 1.8.4 简谱渲染器崩溃 → 在 JSON 层（JsonConverter 前）替换为 4 个四分休止克隆，空小节简谱显示 0 0 0 0（对齐参考站）；mixed/tab 切换重建 score 保留播放位置与混音；verify-track-mode 6/6 + coverage 60/60 + 全量回归 58+8+10+9+12+41 + build 通过 |
| M8.11 数字谱语义修正（关闭不再隐藏和弦品数） | ✅ 完成（分支 fix/number-tab-jianpu-visibility 合入 master） | 六线谱和弦品数始终完整；数字谱开关只控制简谱（numbered）谱表显隐；清理 markChordNotes/CSS 隐藏死代码；verify-player-display 11/11 |
| M8.12 谱面字体与歌词间距（中文/数字→方正小标宋简体；歌词下移） | ✅ 完成（分支 fix/score-font-fzxbs-song 合入 master） | 中文（标题/艺人/歌词）与数字（品数/简谱/小节号/指法）改用方正小标宋简体（打包 /font/FZXiaoBiaoSong.TTF）；和弦名等拉丁保持 Cascadia Code；effectBandPaddingBottom 22→40 将歌词带整体下移约 30px；11+8+6+9+12+41+58 全绿 + build 通过 |
| M8.13 乐器切换音频竞态修复 | ✅ 完成（分支 fix/instrument-switch-audio） | 根因：waitForPlaybackReady 旧 MIDI 已就绪立即 resolve，play 抢跑于新 MIDI 加载；改用 _instance.midiLoaded 精确等待 + 音源按 program 去重/串行化；verify-instrument-switch 6/6 + 全量回归 58+12+9+11+8+41 + build |
| M8.14 音轨控件 UI 响应式 + 谱面模式切换放开 | ✅ 完成（分支 fix/track-ui-mode-switch 合入 master） | 静音/独奏/音量/显隐/乐器切换 Svelte 响应式修复（不可变更新）；吉他谱+简谱/全部六线谱单吉他轨也可切换（默认 mixed）；音量滑杆统一 0-100；verify-track-controls 7/7（新增）+ verify-track-mode 6/6 + 全量回归 58+12+9+11+8+41 + build |
| M8.15 乐器切换真实生效（同步 Instrument 自动化） | ✅ 完成（分支 fix/instrument-automation 合入 master） | 根因：GP 谱首拍 Instrument 自动化覆盖新音色；applyTrackInstrument 同步全部 Instrument 自动化；verify-track-controls 8/8 + 全量回归 58+6+6+11+8+9+12+41 + build |
| M8.16 关闭音轨=静音 + 音效链路审计 | ✅ 完成（分支 fix/track-off-silence 合入 master） | 关闭音轨同步静音/重开恢复（toggleTrack+applyTrackMix）；审计确认推弦/揉弦/闷音/琶音等技巧 数据→MIDI→合成器 链路完整；verify-track-controls 8/8 + 全量回归 58+6+6+11+8+9+12+41 + build |
| M8.17 XHE 文本谱渲染（JSON 和弦锚点谱 + 纯文本谱） | ✅ 完成（分支 fix/xhe-score-display 合入 master） | 根因：XHE 记录 scoreUrl=null → 播放器 fetch(null) 解码失败「Corrupted Huffman」；详情页按 format=xhe 改用 XheScoreViewer：JSON 格式渲染和弦图/歌词/HEADLINE/RHYTHM/TAB（70 个吉他和弦数据库，指法对拍参考站），纯文本格式 <pre> 等宽渲染；ScorePlayer/下载接口加 null 守卫；verify-xhe 24/24 + 全量 77/77 + build
| M10 性能与稳定性优化 + 谱面纸页展示 | ✅ 完成（分支 perf/score-load-presentation 合入 master） | 定位「进乐谱很久/卡加载中」根因：片头首访全屏遮挡 + 播放器容器未就绪早退导致 loading 恒 true；修复：片头仅首页自动播（内容页保留手动触发）、播放器 container 响应式等待 + 25s 看门狗 + 失败重试按钮、音源字节并行抓取+串行喂入；谱面容器升级「纸页」质感（暖纸渐变/活字页眉/页脚水印）；详情页截图图移动端溢出修复；实测生产详情页 1.3s 出谱；全量 82/82 + build
| M10.1 开屏动画纸色主题 + 真实质感吉他弦 | ✅ 完成（分支 fix/intro-paper-guitar 合入 master） | 开屏从暗色影院风改为全站一致的暖纸书卷风格（paper-grain 背景/纸色页缘/暖金+signal 光束）；琴弦改为真实原声吉他质感（青铜暖色、圆柱受光渐变、纸面投影、墨色锚点+金环）；标题墨→金渐变、全部文字适配纸色；移动端无溢出、控制台零报错 |
| M10.2 开屏艺术细节（删印章 + 镂刻页边/五线谱/墨线花饰/音孔罗塞特） | ✅ 完成（分支 fix/intro-artistic-refine 合入 master） | 删除红色「米米」印章；新增镂刻页边（发丝线+四角菱形+音符）、淡印五线谱谱带、标题墨线花饰（SVG 描画）、口号装饰分隔线；琴弦收窄为居中吉他构图（琴枕/琴桥竖条 + 音孔罗塞特同心环）；移动端无溢出、console 零报错 |
| M10.3 开屏质感增强（纸纤维动效/扫光/水印/罗塞特/闪光尘） | ✅ 完成（分支 fix/intro-texture 合入 master） | 修复悬浮光点遗留的琥珀/青色（改暖纸尘+signal+金色闪光星芒）；纸纤维颗粒缓慢漂移、暖光扫过纸面；音孔罗塞特珍珠点纹+立体音孔+拨弦暖光呼吸；中心压印「谱」水印+顶部品牌小字；进度条金色菱形游标；移动端无溢出、console 零报错 |
| M10.4 开屏蒙版入场 + MIMI 水印 + 全局纸纹增强 | ✅ 完成（分支 fix/intro-veil-paper 合入 master） | 开屏改为中间向上下两侧分开的蒙版（两块 50vh 暖纸面板先覆盖再展开，退出合拢）；水印「谱」改「MIMI」；全局 body/paper-grain-bg 增加细纤维+粗绒面斑驳双层纸纹 + 柔和暖色页缘 vignette；移动端无溢出、首页与 /tabs console 零报错 |
| M10.5 开屏听感与材质（回响/共鸣/落定音效/木纹音板/纸斑/水印淡入） | ✅ 完成（分支 fix/intro-audio-material 合入 master） | 拨弦加共享暖房回响 + 琴体共鸣低频；蒙版全开时纸面落定音效；音孔背后淡木纹音板；纸面陈年纸斑；MIMI 水印随蒙版淡入；花饰圆点呼吸脉冲；console 与 warning 均零报错 |
| M10.6 开屏电影感（推镜/拨弦暖脉冲/面板纸渐变/收束琶音/标题暖光） | ✅ 完成（分支 fix/intro-cinematic 合入 master） | 画布缓慢推镜 1→1.03；拨弦全页暖光脉冲；蒙版面板暖纸渐变；退出时轻柔收束琶音；标题聚焦背后暖光托底（修移动端 120% 溢出）；移动端无溢出、console 零报错 |
| M10.7 开屏音频可听化（音量提升 + 手势解锁 + 信号链修复） | ✅ 完成（分支 fix/intro-audio-audible 合入 master） | 根因：getOrCreateReverbBus 返回 input GainNode，但调用处误写 reverb.input（GainNode 无该属性）→ connect(undefined) 抛错中断整条音频链，拨弦从未连到 destination 故无声；修复 connect(reverb) + 主增益 0.055→0.2 等全链路音量提升 + 首次手势自动 resume（pointerdown/touchstart/keydown）+ 恢复 panner 立体声；verify-intro-audio 17/17 + 全量 82/82 + build |
| M10.8 首页纸纹质感升级 + 背景音符高级化（分支 feat/homepage-paper-refine 合入 master） | ✅ 完成 | 纸纹：body/paper-grain-bg 从 2 层噪点升级为 8 层（页缘光影渐变 + 纤维丝缕方向性 + 细颗粒 + 云絮斑驳 + 粗绒面）；背景音符：修复 canvas 高度塌陷根因（容器 relative h-full 与 absolute inset-0 冲突 + contain:strict → 10px 细带），音符改为压印水印质感（暖墨/淡金/古铜/信号蓝点缀调色板、细描边+投影、景深分层、运动更柔）、数量 28→20；verify-homepage-paper 14/14 + 单测 76/76 + build |
| M10.9 首页最新曲谱「纸页乐谱册」（分支 feat/homepage-paper-folio 合入 master） | ✅ 完成 | 最新吉他/尤克里里谱从竖排卡片改为「摊开乐谱册」：每首曲谱一张暖纸谱页（撕纸边缘 clip-path + 衬纸堆叠厚度 + 折角纸纹 + Fraunces 衬线活字压印 + 页码 — n / N —）；鼠标悬停纸页 3D 掀起；上一页/下一页 + 页码点翻页交互；修复 Svelte 5 派生值非响应式 bug（current/cat/isFirst/isLast 改 $derived）；verify-homepage-folio 18/18 + 单测 76/76 + build |
| M10.10 纸页乐谱册动效体系（分支 feat/homepage-folio-motion 合入 master） | ✅ 完成 | 书卷翻页状态机（idle→exiting→entering + 方向，exit 320ms rotateY±70° 翻出 + enter 400ms 从对侧翻入，翻页中按钮禁用防连点）；鼠标 3D 倾斜跟随（--rx/--ry CSS 变量 + rotateX/rotateY 矩阵，离开回正）；悬停/翻页暖光斜扫（shine-sweep）；标题墨迹入场（title-ink blur-up）；衬纸翻页微动（liner-nudge 抽纸感）；页码点弹性（dot-pop scale 1.6）；常驻纸页呼吸（box-shadow/亮度 6s）；prefers-reduced-motion 全部降级；verify-homepage-folio-motion 27/27 + 单测 76/76 + build |
| M10.11 纸页乐谱册「撕页」效果（分支 feat/folio-tear-off，待合入） | ✅ 完成（待合并） | 用户反馈真实翻页效果不好 → git revert（913da9f/a356eb3）回到 M10.10 基线后全新设计：**撕页**——旧页被从右上角掀起（掀角 → 撕扯抖动 → 沿之字形撕口撕下），撕下的大块沿弧线旋转飘落淡出、左上残片原地淡出，下层目标页浮现承接；上一页镜像（左上角撕起飘向左下）；保留 hover 3D 倾斜（hit 覆盖层防命中震荡）、扫光、页码点、呼吸、reduced-motion；verify-homepage-folio-motion 39/39 + 单测 76/76 + build；V2 优化（feat/folio-tear-v2）：撕口动态展开（tear-rip 0.42s 19 顶点 clip-path 从右上角小裂缝插值到全撕口，与残片同步）+ 撕下纸片 3D 姿态/投影/左右摆动飘落 + 残片颤动 + 撕口毛边高光 + 锯齿加密，verify 40/40；V3 升级（feat/folio-tear-v3）：完整撕纸流程——纸角捏起（corner-lift）+ 撕口变速展开（纤维阻力后撕开）+ 残片拉扯鼓起（scaleX）+ 纸屑飞散 ×5 + 撕下块卷曲剥离（scaleX 1.05）+ 翻面飘落（rotateY 170° 露纸背，双面结构），verify 54/54；Air 克制化重做（feat/homepage-air-refine，遵循 D:/designmd/refero-styles/Air 规范，用户确认方向）：移除全部花哨动效（撕页/纸屑/翻面/扫光/呼吸/3D 倾斜/弹性点）与阴影/渐变，改为克制动效——page-out 淡出 0.24s → {#key} 重挂载 → page-in 淡入 0.4s + 元素 stagger（封面/标题/艺人/徽章 0.04-0.22s 错位）；hover 改 CSS :hover 2D 微抬 -2px + 边框信号蓝微亮 + 封面 scale 1.02；保留暖纸品牌（撕纸边缘装饰/纸纹/衬线活字压印/衬纸/徽章），组件 684→289 行；verify 29/29 + 18/18；交叉淡化切换（feat/folio-switch-crossfade）：点击立即切页（新页 {#key} 挂载淡入），旧页快照 folio-ghost 叠层 0.32s 淡出后移除——消除「旧页淡出后空窗再淡入新页」的空白间隙，全程无空白；快照页码保持旧页码；verify 33/33 + 18/18 |

## 任务步骤清单

- [x] M0-1 环境检查（Node/Git/Docker/npm 源）
- [x] M0-2 工程脚手架（Astro SSR + Svelte + Tailwind v4 + AlphaTab 依赖）
- [x] M0-3 PostgreSQL(Docker 5433) + Prisma 初始化与首迁移
- [x] M0-4 编写 PLAN.md 与 DEV_LOG.md
- [x] M0-5 Git 初始化 + 基线提交
- [x] M1-1 `.ibe` 解码工具链（XOR + AR + BinaryImporter）单测
- [x] M1-2 迁移爬虫（列表→详情→.ibe/截图→入库）＋全量 1624 首入库
- [x] M1-3 上传生成管线（MIMI 格式 encode/decode，单测通过；GP→ibe 接入留待 M5）
- [x] M2-1 播放器定制层（NierApi 等价：ibe 双格式解码 + 官方 AlphaTab 渲染）
- [x] M2-2 全套播放控制与循环/变调夹/速度/多轨/PDF/打印（自动化验收通过）
- [x] M3-1 首页排行榜
- [x] M3-2 列表页筛选/排序/分页
- [x] M3-3 详情页信息区与相关推荐
- [x] M3-4 搜索与文章（含静态页）
- [x] M4-1 认证（注册/登录/找回密码）
- [x] M4-2 收藏/浏览记录/个人资料
- [x] M5-1 上传创作中心（GP 上传→解析→.ibe→截图→审核占位→公开展示）
- [x] M6-1 全站 refero 视觉验收与性能
- [x] M8-2 和弦名位置修复（ChordDiagrams=false + EffectChordNames=true，按 system 对齐参考站）
- [x] M8-3 和弦指法图完全显示（自绘覆盖层，位置对齐、与歌词共存、可开关）
- [x] M8-4 和弦图表条（弃用覆盖层：谱面上方 15 卡完整指法图、滚动容器外不压谱；enableLazyLoading=false 完整渲染；数字谱标记修复）
- [x] M8-5 和弦显示模式切换（仅字母/字母+完整指法图逐位内联，原生渲染+歌词共存，移除顶部图表条）
- [x] M8-6 谱面字体统一 Cascadia Code（@font-face 自托管+CJK 回退；标题/艺人/歌词/和弦名/品数/数字谱/小节号等全部替换）
- [x] M8-7 文字重叠修复（头部标题裁剪/Tab 品数堆叠/段落标记碰撞/系统间距；标记因官方 1.8.4 限制隐藏）
- [x] M8-8 播放器音频生效（waitForPlaybackReady + withRenderPreservingPosition reloadMidi；转调/变调夹/乐器切换接入；verify-player-audio 12/12）
- [x] M8-9 谱面显示模式切换（方案 C：主音轨六线谱+其余音轨简谱，可切全部六线谱；全音符休止符数据守卫；verify-track-mode 6/6）
- [x] M10-1 片头仅首页自动播放（Base.astro 传 autoPlay，内容页保留手动触发）；M10-2 播放器加载健壮性（container 响应式等待/25s 看门狗/重试按钮）；M10-3 音源并行抓取；M10-4 谱面纸页展示 + 详情页移动端截图溢出修复（verify 82/82 + build）
- [x] M10-5 开屏动画纸色主题 + 真实质感吉他弦（分支 fix/intro-paper-guitar；verify 截图 + console 零报错 + build 通过）
- [x] M10-6 开屏艺术细节：删印章 + 镂刻页边/五线谱/墨线花饰/音孔罗塞特（分支 fix/intro-artistic-refine；console 零报错 + build 通过）
- [x] M10-7 开屏质感增强：纸纤维动效/扫光/水印/罗塞特/闪光尘 + 光点暖色修复（分支 fix/intro-texture；console 零报错 + build 通过）
- [x] M10-8 开屏蒙版入场（中间向上下展开）+ 水印改 MIMI + 全局双层纸纹与暖色页缘（分支 fix/intro-veil-paper；console 零报错 + build 通过）
- [x] M10-9 开屏听感与材质：回响/共鸣/落定音效/木纹音板/纸斑/水印淡入（分支 fix/intro-audio-material；console+warning 零报错 + build 通过）
- [x] M10-10 开屏电影感：推镜/拨弦暖脉冲/面板纸渐变/收束琶音/标题暖光（分支 fix/intro-cinematic；console 零报错 + build 通过）
- [x] M8-10 XHE 文本谱渲染（JSON 和弦锚点谱：和弦图/歌词/HEADLINE/RHYTHM/TAB；纯文本谱 <pre>；详情页 format=xhe 分支；ScorePlayer/下载接口 null 守卫；verify-xhe 24/24）
- [x] M8-10 全音符休止符 JSON 层替换（次级音轨 whole-rest → 4×quarter-rest，规避 NumberedBarRenderer 崩溃；mixed/tab 切换重建 score + 保留播放位置/混音；verify-track-coverage 60/60）
- [x] M8-11 数字谱语义修正：TAB 品数始终完整 + 简谱行显隐（showNumbered）；移除 CSS 隐藏与 markChordNotes 死代码；verify-player-display 11/11 + 全量回归
- [x] M8-12 谱面字体：方正小标宋简体（中文+数字）+ 歌词间距下移（effectBandPaddingBottom）；打包字体 + CJK/拉丁分组字体；全量回归通过
- [x] M8-13 乐器切换竞态修复：waitForMidiLoaded（_instance.midiLoaded）+ withRenderPreservingPosition/setScoreDisplayMode 先订阅后重生成；音源去重+串行化；verify-instrument-switch 6/6 + 全量回归
- [x] M8.14 音轨控件响应式修复 + 谱面模式切换放开（新增 verify-track-controls 7/7；verify-track-mode T4 改为单吉他轨可切换；全量回归通过）
- [x] M8.15 乐器切换真实生效（同步 Instrument 自动化；verify-track-controls 扩展至 8/8；全量回归通过）
- [x] M8.16 关闭音轨=静音/重开=恢复；音效链路审计（推弦 per-note 弯音、闷音力度已验证）

## 日志模板

```md
### YYYY-MM-DD ｜ 里程碑-步骤
- 本次目标：
- 完成内容：
- 验证方式与结果（证据）：
- 遇到的问题与决策：
- 下一步：
```

---

## 日志
### 2026-08-17 ｜ 乐谱册切换改交叉淡化（分支 feat/folio-switch-crossfade）
- 本次目标：用户反馈「点击切换卡片上的界面完全消失」——旧方案先淡出旧页（240ms 空窗）再淡入新页，切换瞬间卡片区域空白，观感断裂。
- 完成内容（src/components/PaperFolioSection.svelte）：
  - 交叉淡化：go() 点击立即 pageIndex=next（{#key} 重挂载，新页 page-in 0.4s 淡入上浮 + 元素 stagger），同时把旧页快照（ghost: TabItem + ghostPage 旧页码）渲染为绝对定位叠层 .folio-ghost（z-3），0.32s 淡出上移后 setTimeout 移除。
  - 新页与快照交叉：快照从 opacity 1 淡出、新页从 0 淡入，任意时刻卡片区域都有内容——无空白间隙。
  - 快照页码参数化：snippet pageContent(t, pageNo)，新页传 pageIndex+1、快照传 ghostPage+1（旧页码），避免快照显示新页码。
  - 快照内部禁用动画（.folio-ghost * animation none）且 pointer-events none，不可交互。
  - 删除 page-out 机制（旧页不再自身淡出，被快照替代）。FLIP_MS=340。
- 验证方式与结果（证据）：
  - verify-homepage-folio-motion.mjs 更新为 33/33 PASS：新增「点击后 120ms 快照立即出现（无空白）」「快照内容为旧页」「快照页码为旧页码 1 / N」「新页 page-in 同时播放」「340ms 后快照消失、页码 1→2、按钮恢复」；原结构/hover/stagger/移动端/零报错断言保留。
  - verify-homepage-folio.mjs 18/18、node --test 76/76、npx astro build 通过。
- 遇到的问题与决策：
  - 快照页码若沿用全局 pageIndex 会显示新页码（内容与页码不符）→ snippet 页码参数化，快照传旧页码。
- 下一步：合并 master 后主分支回归与冒烟；观感请用户确认。

### 2026-08-17 ｜ 乐谱册 Air 克制化重做（分支 feat/homepage-air-refine）
- 本次目标：用户连续多轮反馈撕页/翻页等花哨动效「不好看」，提供 Air 设计规范（D:/designmd/refero-styles/Air）要求遵循；经方向确认：保留暖纸品牌，按 Air 克制原则重做；动效改为克制淡入错位。
- Air 规范应用（乐谱册区块）：
  - No elevation：卡片/衬纸全部 box-shadow 移除，层次靠 1px 细边框 + 背景对比；页面渐变层移除（Air: Don't use gradients），纸色平色化。
  - 克制动效：删除 tear-corner/tear-piece/tear-face/tear-back/tear-shred/tear-remain、folio-shine 扫光、folio-idle-breathe 呼吸、folio-lift/tilting 3D 倾斜、dot-pop 弹性、liner-nudge、hit 覆盖层、JS hover 状态与 JS 点击导航（a 原生 href 恢复）。
  - 新切换：旧页 page-out 0.24s（淡出+上移 6px）→ 240ms 后 pageIndex 切换（{#key} 重挂载）→ 新页 page-in 0.4s（淡入+上浮 10px，cubic-bezier(0.16,1,0.3,1) backwards 不 fill 结束态）；元素 stagger：封面 0.04s → 标题 0.10s → 艺人 0.16s → 徽章 0.22s fade-up。
  - hover：CSS :hover（无需 JS）——translateY(-2px) + border-color rgba(43,127,255,0.35) + 封面 scale(1.02)，transition 0.3s。
  - 按钮/页码点：rounded-lg 8px（Air 按钮半径）、hover 边框微亮；页码点去弹性改 0.3s 简单过渡。
  - 保留暖纸品牌：撕纸边缘 clip-path（静态装饰）、paper-grain-bg 纸纹、Fraunces 衬线标题 + letterpress-ink 活字压印、衬纸 ×2（平色细边框）、调性/谱型/难度/热度徽章、「更多 →」下划线链接（Air: underline link）。
  - 组件 684 → 289 行。
- 验证方式与结果（证据）：
  - verify-homepage-folio-motion.mjs 重写为克制化断言 29/29 PASS：无 tear-* 元素、卡片无阴影、page-in/page-out 动画、stagger delay 递增、hover 2D 微抬 -2px + 边框信号蓝 + 封面缩放、移开回正、页码点无弹性、移动端无溢出、零报错。
  - verify-homepage-folio.mjs 适配新结构 18/18 PASS。回归：node --test 76/76、npx astro build 通过。
- 遇到的问题与决策：
  - CSS 顺序坑：.folio-page 的 animation 规则写在 .page-out 之后（同特异性后定义获胜）导致 page-out 被覆盖 → 选择器提为 .folio-page.page-out。
  - page-in fill both 的结束态 transform 会常驻压住 hover 微抬 → 改 backwards（结束不 fill）。
- 下一步：合并 master 后主分支回归与冒烟；观感请用户确认，可继续调 stagger 节奏/边框色/圆角。

### 2026-08-16 ｜ 撕页效果 V3 升级（分支 feat/folio-tear-v3）
- 本次目标：用户反馈撕页「很简陋」——撕口直切、纸片平飘、无撕扯过程感。
- 完成内容（src/components/PaperFolioSection.svelte）：
  - 完整撕纸流程（总 1.1s）：①纸角捏起——tear-corner 三角元素（clip-path）从右上角掀起 rotateZ -16° + 阴影，0.42s 后随撕下块同步飘落；②撕口变速展开——tear-rip cubic-bezier(0.72,0.06,0.88,0.34) 先慢后快（纤维阻力→突然撕开），19 顶点 clip-path 插值；③拉扯——撕口展开期间 face 残片 scaleX(1.012) 鼓起；④纸屑飞散——5 片纸屑（tear-shred，不规则 clip-path）从撕口起点沿线飞散，各自随机方向/旋转/延迟；⑤卷曲剥离——撕下块 scaleX 1.03→1.05（纸片弯曲拉伸）；⑥翻面飘落——tear-piece 双面结构（tear-face 内容 + tear-back 纸背 rotateY180 + MIMI 水印，各自 clip-path，容器 preserve-3d 不拍平），飘落中 rotateY 0→172° 翻面露纸背 + 左右摆动轨迹 + 渐小渐淡。
  - FLIP_MS=1300；reduced-motion 新增 corner/shred 禁用。
- 验证方式与结果（证据）：
  - verify-homepage-folio-motion.mjs 更新为 54/54 PASS：纸角出现 + corner-lift 动画、双面结构（tear-face/back 存在 + backface hidden）、tear-rip 在双面层运行 + clip-path 多边形、纸屑 ≥3、飘落中 tear-fall + matrix3d（含翻面）+ corner-fall、翻页完成全部元素消失、上一页镜像（tear-corner-prev/tear-shred-prev）、tilt/扫光/页码点/移动端/零报错。
  - 回归：node --test 76/76、npx astro build 通过。
- 遇到的问题与决策：
  - clip-path 是 grouping property，直接放在 preserve-3d 容器上会拍平子元素 3D（翻面失效）→ clip-path 移到 tear-face/tear-back 各自层，容器只做 transform。
  - 一次性批量替换 CSS 时 remain-tear 块被 indexOf 锚点误插损坏（Svelte 报 CSS identifier 错误）→ 重写整块后恢复。
- 下一步：合并 master 后主分支回归与冒烟；观感请用户确认。

### 2026-08-16 ｜ 撕页效果 V2 优化（分支 feat/folio-tear-v2）
- 本次目标：用户反馈撕页「还不是很好看」，继续优化质感与过程感。
- 完成内容（src/components/PaperFolioSection.svelte）：
  - 撕口动态展开：原静态撕口改为 tear-rip 0.42s 关键帧——19 顶点 clip-path 从「右上角小裂缝」插值到「全撕口」，tear-piece（撕下块）与 face（残片）的撕口同步展开，缝隙露出下层新页，撕开过程可见。
  - 撕下纸片立体化：tear-fall 0.68s（延迟 0.42s）——撕扯抖动 ×2 → 3D 姿态飘起（rotateZ -12° + rotateX 6°）→ 左右摆动下落（120px→96px→190px 摆弧）+ rotateX 至 18° + scale 0.9 + 淡出；飘落全程带 inset 白色毛边高光 + 外部纸影（阴影随距离变化）。
  - 残片颤动：remain-tear 同步展开后 remain-shake 0.5s 颤动（±1.5px 微转）再 remain-fade 淡出，不再生硬消失。
  - 撕口锯齿加密（13→16 个撕口点），更细密真实；总时长 0.42+0.68=1.1s，FLIP_MS=1130。
- 验证方式与结果（证据）：
  - verify-homepage-folio-motion.mjs 更新为 40/40 PASS：tear-rip 展开动画 + 展开中 clip-path 多边形、残片三动画（remain-tear/shake/fade）、飘落中 tear-fall + transform matrix、翻页完成状态恢复、上一页镜像、tilt/扫光/页码点/移动端/零报错。证据截图 tear-start（撕口展开中）/ tear-mid（飘落中）更新。
  - 回归：node --test 76/76、npx astro build 通过。
- 遇到的问题与决策：
  - 上一页断言偶发失败：等待 1000ms 只比动画 1.1s 少——动画总时长 1.1s > 等待 → 改为 1350ms 后稳定。
  - clip-path 插值要求两多边形顶点数一致且顺序对应（19 顶点），小撕口版顶点聚于右上角、终点沿左缘下滑，插值自然。
- 下一步：合并 master 后主分支回归与冒烟；观感请用户确认。

### 2026-08-16 ｜ 纸页乐谱册「撕页」效果（分支 feat/folio-tear-off）
- 本次目标：用户反馈真实翻页（书脊 rotateY 翻转）效果不好，要求「完全重新设计，有创意有新意」。
- 执行方式：
  - git revert（a356eb3、913da9f -m 1）回退真实翻页全部改动（组件/验证脚本/DEV_LOG/计划文档回到 M10.10 动效版基线，27/27 + 18/18 通过后确认干净）。
  - 全新设计「撕页」：与乐谱册撕纸边缘设计语言呼应——切换时旧页像被手指从右上角掀起、沿对角线之字形撕口撕下。
- 完成内容（src/components/PaperFolioSection.svelte）：
  - 撕下块 .tear-piece：翻页时条件渲染（snippet 复用页面内容），clip-path 之字形 15 顶点撕口（下一页从右上角 (100%,0) 撕到 (0%,16%)，含右下大块；上一页水平镜像），tear-fall 0.92s 动画——掀角（rotateZ -2.5°）→ 撕扯抖动 ×2（translateX ±5px）→ 沿弧线飘落（先上后下 translate(16px,-14px)→(95px,150px)→(175px,400px)，rotateZ 至 -34°，scale 0.92，淡出）。
  - 残片 .tear-remain：face 切成撕口另一侧的左上小块，remain-fade 0.55s 原地淡出（上一页为右上小块 tear-remain-prev）。
  - 下层承接：under 目标页 under-settle 浮现（scale 0.985→1 + 亮度回升），FLIP_MS=940ms 后角色互换。
  - 保留 hover 3D 倾斜（事件绑在无 transform 的 folio-hit 覆盖层上，face 3D 变换不影响命中，无震荡）+ 扫光 + 页码点 + 呼吸 + reduced-motion 直切。
- 验证方式与结果（证据）：
  - tools/verify-homepage-folio-motion.mjs 重写为撕页断言（39/39 PASS）：撕下块出现 + 之字形撕口 clip-path + tear-fall 动画 + 残片类 + 按钮禁用 + 下层就位；飘落 transform matrix；翻页完成页码 1→2、face 恢复完整、撕下块/下层消失、按钮恢复、呼吸恢复；上一页镜像（tear-piece-prev/tear-fall-prev/tear-remain-prev、翻回页码 1）；tilt 3D 矩阵 + 回正；扫光；dot-pop；桌面/移动端零报错、移动端无溢出。证据 tests/evidence/homepage-folio-motion/（tear-start 掀角帧 / tear-mid 飘落帧 / folio-flipped / folio-idle / folio-tilt / desktop-top / mobile）。
  - 回归：node --test 76/76、npx astro build 通过。
- 遇到的问题与决策：
  - 撕口用固定 15 顶点静态 clip-path（不做插值动画），撕开过程用「掀角 + 撕扯抖动」表现——可靠且视觉生动；飘落轨迹先上后下成弧线，更像真实纸片。
  - 撕下块与 face 同为 snippet 渲染（两份内容），图片同 URL 浏览器缓存无额外加载。
- 下一步：合并 master 后跑主分支回归与冒烟；观感请用户确认，可调撕口锯齿密度/飘落弧线/时长。

### 2026-08-16 ｜ 纸页乐谱册动效体系（分支 feat/homepage-folio-motion）
- 本次目标：用户反馈纸页乐谱册「没有什么动画和其他的效果」，在 M10.9 的 hover 掀起 + 弱位移翻页基础上做一套完整的纸页动效体系。
- 完成内容（src/components/PaperFolioSection.svelte，纯 CSS 关键帧 + Svelte 状态机，无外部动画库）：
  - 书卷翻页状态机：phase = 'idle' | 'exiting' | 'entering' + flipDir = ±1。下一页：旧页 320ms 从右往左 rotateY(0→-70°) translateX(-24px) 翻出（exit-next，origin 左侧书脊感）、随后新页 400ms 从左侧 rotateY(55°→0) 翻入（enter-next）；上一页方向镜像（exit-prev / enter-prev，rotateY 正负互换）。翻页中 go() 直接 return 忽略连点，按钮 disabled 同步禁用。
  - 鼠标 3D 倾斜跟随：onpointermove 按相对中心偏移写 CSS 变量 --rx/--ry（rotateX(-py*10°) rotateY(px*14°)），folio-tilting 叠加 perspective 矩阵实时倾斜；悬停时 folio-lift 抬升 translateY(-8px) scale(1.012) + 阴影加深 + 信号蓝描边；mouseleave 归零回正。
  - 暖光扫过：.folio-shine 渐变光带 translateX(-120%) 待命，悬停或翻页时 shine-sweep 1.1s 从左下到右上斜扫。
  - 入场动画：纸页常驻 folio-idle-breathe（6s box-shadow/亮度微浮动，避免完全静止）；标题 title-ink 0.9s blur-up 墨迹显现；衬纸 liner-nudge 翻页时抽纸上移回弹；页码点 dot-pop scale 1→1.6→1 弹性。
  - 无障碍：@media (prefers-reduced-motion: reduce) 下全部 animation/transition 关闭。
- 验证方式与结果（证据）：
  - 新增 tools/verify-homepage-folio-motion.mjs（27/27 PASS）：常驻呼吸动画 + 阴影、title-ink、衬纸 ≥2；翻页状态机——exit-next 130ms 采样触发、翻页中按钮禁用、enter-next 触发、翻页时扫光激活、页码 1→2、完成后按钮恢复 + 回到 idle 呼吸、exit-prev 触发、翻回页码 1；倾斜——--rx/--ry 更新、matrix3d 生效、倾斜时呼吸暂停、离开归零；悬停扫光 shine-sweep 激活；页码点 dot-pop；桌面/移动端 console 与 pageerror 零报错、移动端 390px 无溢出。证据 tests/evidence/homepage-folio-motion/（desktop-top / flip-next-mid 翻页中帧 / folio-idle / folio-tilt / mobile）。
  - 回归：node --test 76/76、npx astro build 通过。
- 遇到的问题与决策：
  - 验证脚本最初 2 项失败（倾斜 matrix3d 无、扫光不激活）均为脚本时序/合成事件问题而非组件 bug：①上一页翻回后只等 500ms，但完整周期 320+400=720ms，phase 仍在 entering，tilting 类需 idle 才生效 → 等待改为 800ms；②合成 mouseleave 把 isHovered 置 false 后真实鼠标仍停在元素上，后续 hover() 不再触发 mouseenter → 先在 mouse.move 移开真实鼠标再触发 mouseleave。组件本身无需修改。
  - 翻页时旧页 rotateY 旋转轴未用 transform-origin 单独指定（默认 center），书脊感靠 translateX(-24px) 位移补偿，避免 preserve-3d 下 origin-left 与 tilting 叠加时的视觉跳动。
- 下一步：合并 master 后跑主分支回归与全站冒烟；如需更沉浸可加触摸滑动翻页（pointer swipe）或书脊阴影贴图（另立任务）。

### 2026-08-16 ｜ 首页最新曲谱「纸页乐谱册」（分支 feat/homepage-paper-folio，已合入 master）
- 本次目标：用户反馈首页「最新吉他谱 / 最新尤克里里谱」排版死板无特色，希望有纸质翻书/撕页的浏览体验。
- 完成内容：
  - 新增 PaperFolioSection.svelte：把两个区块从纵向 TabCard 列表改为「摊开的乐谱册」——左右两栏各一册，每首曲谱渲染为一张暖纸谱页。
  - 纸页质感：撕纸边缘（clip-path 多边形微锯齿上下缘）、2 张衬纸错位旋转堆叠制造纸叠厚度、paper-grain-bg 纸纹底、暖光渐变、hairline 发丝边、Fraunces 衬线标题 + letterpress-ink 活字压印、页码「— n / N —」、调性/谱型/难度/热度徽章、曲谱封面截图或占位图标。
  - 交互：鼠标悬停纸页 3D 掀起（perspective rotateX + 抬升 + 阴影加深）；上一页/下一页按钮（首末页正确禁用）+ 页码小点（当前页拉长高亮）翻页切换；点击整页进入详情；翻页时有位移淡出过渡。
  - 接入首页（src/pages/index.astro）：两个 section 替换为 <PaperFolioSection client:load …>，移除不再使用的 TabCard import。
  - 修复 Svelte 5 响应式 bug：current / cat / isFirst / isLast 最初为普通 const，pageIndex 变化后页面内容不更新（页码变但曲目不换、上一页按钮恒禁用）；统一改为 $derived 后修复。
- 验证方式与结果（证据）：
  - 新增 tools/verify-homepage-folio.mjs（18/18 PASS）：2 个纸页册区块、曲名/艺人/徽章、衬纸 ≥2、撕纸 clip-path、翻页按钮 2 个、页码点 ≥5、页码格式；翻页交互——下一页链接变化/页码 1→2、上一页回退、首页时上一页禁用；悬停 3D transform；移动端 390px 无溢出；console/pageerror 零报错。证据 tests/evidence/homepage-folio/（desktop-top/desktop-folio/mobile）。
  - 回归：node --test 76/76、npx astro build 通过。
  - 合并后 master 冒烟通过。
- 遇到的问题与决策：
  - 同名字曲（如多首 Canon Rock）导致「下一页曲名变化」断言不稳定 → 改为断言链接 href 变化（id 不同）为主，曲名变化为辅助。
  - 验证脚本点击 disabled 上一页按钮超时 → 修正为先翻到第二页再点上一页。
- 下一步：最终观感请用户在浏览器确认；如需更强的翻书感可加 rotateY 翻页转场或拖拽撕页交互（另立任务）。

### 2026-08-16 ｜ 首页纸纹质感升级 + 背景音符高级化（分支 feat/homepage-paper-refine，已合入 master）
- 本次目标：用户反馈「主页面的纸质纹理还不是很好，继续优化设计；背景的音符很生硬，增加高级感」。
- 完成内容：
  - 纸纹升级（src/styles/global.css body 与 .paper-grain-bg）：原 2 层均匀噪点 → 8 层手工纸体系——页缘光影（顶部受光 + 底部暖棕落影 + 中心椭圆受光 + 线性渐变）、纤维丝缕（非各向同性 feTurbulence 0.02/0.55 拉丝方向 + 5 octaves）、细颗粒（0.9）、云絮斑驳（0.011/0.016 大尺度柔和）、粗绒面（0.16）。全部 data-uri 静态背景，无 JS。
  - 背景音符高级化（src/components/ambient/MusicNoteParticles.svelte + Hero.svelte）：
    - 修复关键根因：组件容器 class 同时含 relative h-full w-full 与传入的 absolute inset-0（Tailwind 顺序冲突），叠加 contain:strict 的 size containment → 容器高度塌陷为 0、canvas 仅 10px，音符全部挤在顶部一条细带里（这正是「生硬」的根源）。改为容器自身 absolute inset-0 后 Hero 与 showcase 音符铺满整卡。
    - 质感：新增调色板（暖墨 42% / 灰褐 20% / 淡金 18% / 古铜 12% / 信号蓝点缀 8%）替代纯信号蓝；绘制改「压印水印」——细描边 + 极淡暖灰投影 + 低饱和实心，像印在纸上而非贴纸。
    - 层次：景深三分层（远 9-18px 更淡 68% / 中 15-25px 22% / 近 22-34px 略深 10%）；运动更安静（速度 0.55→0.42、旋转幅度减半、摆动更缓）；数量 28→20。
- 验证方式与结果（证据）：
  - 新增 tools/verify-homepage-paper.mjs（14/14 PASS）：body 背景 ≥6 层且含 4 组 SVG 噪声 + linear-gradient 页缘光影；Hero canvas 像素采样——暖墨/灰褐占比显著、淡金/古铜点缀存在、信号蓝占比克制；canvas 高度 505px（修复前 10px）、音符纵向分布均匀（底 396→顶 8 自然衰减）；移动端 390px 无横向溢出；console/pageerror 零报错。证据 tests/evidence/homepage-paper/（desktop-home/desktop-hero/mobile/desktop-full/hero-closeup）。
  - 回归：node --test 76/76、npx astro build 通过；showcase 页面同组件 canvas 同步修复（505px 高、零报错）。
- 遇到的问题与决策：
  - 首次用正则/文本块替换 global.css 背景时误删 .paper-emboss/.letterpress-ink 等中文注释块（marker 定位过宽），已 git checkout 恢复并改为行级精确替换（UTF-8 安全）后成功。
  - 音符像素采样初版全 0：原因是 canvas 高度塌陷（10px）而非颜色问题，定位到容器 contain:strict 与定位冲突后修复，采样随即通过。
- 下一步：最终观感请用户在浏览器确认；如需更强纸感可继续调纤维/云絮 alpha，或把 Hero 音符做成可配置的「印墨浓度」。

### 2026-08-16 ｜ 开屏音频可听化修复（分支 fix/intro-audio-audible，已合入 master）
- 本次目标：用户反馈开屏拨弦「听不到声音」。实测确认为两个叠加根因：①信号链断裂——getOrCreateReverbBus 返回的是 input GainNode，但调用处误写 noteMasterGain.connect(reverb.input)（GainNode 无 .input 属性，值为 undefined）→ 每次拨弦在 connect 处抛 TypeError「Overload resolution failed」，try 块中断，声音节点创建后从未连接 destination → 开屏音频实际无声；②即便链路连通，原音量也过低（主增益 0.055、氛围 0.018、纸面落定 0.016），几乎不可闻。
- 完成内容（src/components/ambient/MasterpieceIntro.svelte）：
  - 核心修复：reverb.input → reverb（连接返回的 input GainNode），拨弦信号链完整连通（点击声→琴体滤波→主增益→panner→destination + 共享回响总线）。
  - 音量全链路提升：拨弦主增益 0.055→0.2、指弹点击 0.02→0.04、琴体共鸣 0.05→0.09、氛围噪声 0.018→0.05、纸面落定 0.016→0.04、回响湿声 0.09→0.12、收束琶音 0.5→0.75。
  - 浏览器自动播放策略：新增 bindAudioUnlock——首次 pointerdown/touchstart/keydown 时 resume AudioContext（被动监听、幂等绑定）；getOrCreateAudioContext 的 resume 加 .catch 防未处理 rejection；拨弦/纸面落定在 suspended 状态直接返回（不静默报错，解锁后自动恢复）。
  - 恢复 panner 立体声空间感（此前排查时被临时移除）：noteMasterGain→panner→destination，多弦 pan 按弦位 -0.45~+0.45 分布。
  - catch 块记录 [pluck-audio] 诊断日志，便于后续排障。
- 验证方式与结果（证据）：
  - 新增 tools/verify-intro-audio.mjs（17/17 PASS）：源码断言音量参数/解锁/signal 链；Playwright 注入 AudioContext 探针——振荡器 30 个全部创建（6 次拨弦×5 谐波）、destination 总线峰值 0.247（真实输出，修复前为 0）、panner pan 值多弦不同、控制台零报错、移动端 390px 无溢出。证据 tests/evidence/intro-audio/（desktop-strings/desktop-title/mobile）。
  - 修复前后对照：修复前 _aerr 探针捕获 6 次 [pluck-audio] Overload resolution failed；修复后零报错且 busPeak>0.2。
  - 回归：node --test 82/82（含历史遗留浏览器脚本，串行模式）、npx astro build 通过。
  - 合并后 master 冒烟通过。
- 遇到的问题与决策：
  - panner 曾被误判为问题源移除（对照实验证明 panner 直连峰值 0.5 正常），实际根因是 reverb.input；已恢复立体声并保留诊断日志。
  - node --test 全量并行会同时启动 4 个历史遗留浏览器截图脚本（tests/test-*.mjs）导致 Chrome 资源竞争卡住；串行（--test-concurrency=1）下 82/82 通过。该问题为历史遗留，另立任务处理（建议把截图脚本移出 tests/ 或改为 tools/verify 风格）。
- 下一步：headless 无法试听，最终听感请用户在浏览器确认；如需更柔和的拨弦可微调 0.2 主增益与 0.12 湿声比例。

### 2026-08-16 ｜ 开屏电影感与细节增强（分支 fix/intro-cinematic，已合入 master）
- 本次目标：用户反馈「继续优化一下细节和质感」。
- 完成内容：
  - 画布缓慢推镜：整个乐器画面从 1.0 缓缓推近到 1.03（围绕画面中心，5s 内线性到位），开篇更有电影感，与蒙版展开叠加出纵深。
  - 拨弦暖脉冲：每次拨弦时全页泛起极淡暖光（与弦振幅同步的径向脉冲，峰值 0.10），拨弦瞬间整个画面「呼吸」一下。
  - 蒙版面板材质：两块 50vh 面板改为暖纸渐变（上板 to-bottom、下板 to-top，分离缝处受光更亮），不再是平涂色。
  - 收束琶音：退出（跳过/自动结束）时以 70ms 间隔低音量（0.5）重拨六弦，形成轻柔的「合卷」和弦收束，与开场琶音首尾呼应。
  - 标题暖光：标题聚焦时背后出现暖光托底（径向暖光 + blur），把标题从纸面「抬」起来。
- 验证方式与结果（证据）：
  - npx astro build 通过；Playwright 实测：两块面板 gradient 生效（to-bottom / to-top）、标题暖光 div 存在、console 零报错；4 帧截图 tests/evidence/intro-cinematic/（900/2100/3500/4400 + mobile）。
  - 修复：标题暖光原用 w-[120%]+居中，导致移动端横向溢出（390→400）；改为 inset-x-0 后 390/390 无溢出。
  - 合并后 master 冒烟通过。
- 遇到的问题与决策：120% 宽居中元素即使被 overflow-hidden 裁剪，scrollWidth 仍会增长导致溢出判定；改 inset-x-0 定位解决。临时脚本已清理。
- 下一步：如需进一步，可在用户试听后微调收束琶音音量/间隔，或把推镜幅度做成可配置（另立任务）。

### 2026-08-16 ｜ 开屏听感与材质质感增强（分支 fix/intro-audio-material，已合入 master）
- 本次目标：用户反馈「继续优化一下细节和质感」。
- 完成内容：
  - 拨弦听感：新增共享暖房回响总线（0.19s 反馈延时 + 低通阻尼 + 湿声 0.09，按 AudioContext 惰性建一次，多弦共享）；每根弦叠加琴体共鸣低频 thump（82-110Hz 正弦快速衰减，spruce top knock）。
  - 蒙版全开瞬间（T+1.5s）播放轻柔「纸面落定」音效（低通噪声渐变 0.7s，音量 0.016）。
  - 材质：音孔背后新增极淡暖木音板（径向暖色渐变椭圆 + 4 条木纹弧，透明度 0.09-0.13）；纸面新增 4 处陈年纸斑（淡暖色径向斑驳）。
  - MIMI 水印与品牌小字改为随蒙版淡入（opacity transition 1600/1400ms），不再是静态常显。
  - 标题墨线花饰中点加呼吸脉冲（animate-pulse）。
- 验证方式与结果（证据）：
  - npx astro build 通过；Playwright 实测：纸斑层存在、水印容器 opacity transition 生效、花饰圆点带 animate-pulse、音板采样为暖木色（153,140,115）；5 帧截图 tests/evidence/intro-material/（parting 400/1100、strings 2000、title 3400、full 4300、mobile）；console 与 warning 均零报错（音频图构建无警告）。
  - 合并后 master 冒烟通过。
- 遇到的问题与决策：headless 无法直接试听，音频验证为「构建无报错 + 节点图与既有可用音频同构」；最终听感需用户在浏览器确认。临时脚本已清理。
- 下一步：如需进一步，可在用户试听后微调回响湿声/共鸣音量，或把「纸面落定」与首页 hero 入场衔接（另立任务）。

### 2026-08-16 ｜ 开屏蒙版入场 + MIMI 水印 + 全局纸纹增强（分支 fix/intro-veil-paper，已合入 master）
- 本次目标：用户反馈「谱字换成 MIMI」「要有一个从中间向上下两侧移动的蒙版开屏」「增加更多全局页面的纸质纹理，让页面更柔和」。
- 完成内容：
  - 水印：「谱」改为「MIMI」（Fraunces 衬线、淡金压印、旋转 -5°、min(17vw,220px)）。
  - 开屏蒙版入场：原 12.5vh 上下 letterbox 改为两块 50vh 暖纸面板——先覆盖全屏，T+0.08s 起从中心向上下两侧展开（1400ms ease，分离边缘带金/蓝发丝线 + 柔和投影），露出琴弦与标题；退出（手动跳过/自动 4.95s）时面板合拢回中心再整体淡出，形成「开卷-合卷」的对称效果。
  - 全局纸纹：body 与 .paper-grain-bg 升级为 细纤维(0.05) + 粗绒面斑驳(mottle 0.045) 双层 SVG 噪点 + 顶部/底部暖光 + 柔和暖色页缘 vignette，全站页面更柔软有纸感。
- 验证方式与结果（证据）：
  - npx astro build 通过；Playwright 实测蒙版位移：t+350ms 顶板 -64px(14%)、t+900ms -372px(82%)、t+1600ms 后 -450px(50vh 全开)，展开/合拢时序正确；水印文本=MIMI（Fraunces）；body 背景含 mottle 双层纸纹；首页与 /tabs 控制台零报错；390px 移动端无横向溢出。
  - 截图证据 tests/evidence/intro-veil/（veil-parting 350/900、veil-open 1600、title 3200、full 4200、mobile、closed）。合并后 master 冒烟通过。
- 遇到的问题与决策：首次探针误读 style.transform（目标值）而非 computed transform，动画进度显示不准确；改用 getComputedStyle().transform 后确认展开曲线正常。临时脚本已清理。
- 下一步：如需进一步，可评估开屏合拢与首页 hero 的无缝衔接、或把全局纸纹做成可按页面深度的动态淡入（另立任务）。

### 2026-08-16 ｜ 开屏质感增强（分支 fix/intro-texture，已合入 master）
- 本次目标：用户反馈「继续优化一下细节和质感」。在纸色 + 艺术细节基础上，让纸张与乐器更有材料质感与呼吸感。
- 完成内容：
  - 修复遗留问题：悬浮光点此前仍是琥珀/青色（首轮补丁因 CRLF 报错未落盘）；改为暖纸尘（182,152,102 / 130,112,90）+ signal 蓝点缀，约 18% 为金色闪光粒子（十字星芒 + 更大柔焦），不再与纸面冲突。
  - 纸张生命感：纸纤维颗粒叠加缓慢漂移动画（grain-shift，7s alternate）；新增缓慢暖光斜切扫过纸面（light-sweep，6.5s 循环，z-6 位于画布之下）。
  - 音孔罗塞特升级：外圈珍珠点纹内嵌（60 点，金/淡金交替）、音孔改为上下立体高光渐变、内脊圈；拨弦时音孔随弦振幅呼吸暖光（clusterGlow 径向渐变）。
  - 压印水印：中心大型「谱」字压印水印（淡金、旋转 -7°、opacity 0.07，paper-emboss）+ 顶部品牌小字「MIMI GUITAR · FOLIO EDITION」。
  - 进度条前端新增金色菱形游标（带浅金描边与柔光）。
- 验证方式与结果（证据）：
  - npx astro build 通过；dev server 实测：grain-shift / light-sweep 动画均在运行、水印「谱」与品牌小字存在、菱形游标存在、罗塞特珍珠环像素为暖金（197,174,116）；旧琥珀/青光点颜色已完全移除；桌面/移动截图 tests/evidence/intro-texture/（intro-strings/title/full/mobile）；console/pageerror 零报错；390px 无横向溢出。
  - 合并后 master 冒烟通过。
- 遇到的问题与决策：无阻塞问题；全部按行级补丁应用（CRLF 文件先转 LF）。临时脚本已清理。
- 下一步：如需进一步，可评估片头尾帧与首页 hero 无缝衔接、或把「谱」水印做成随光线动态浮现的压印动画（另立任务）。

### 2026-08-16 ｜ 开屏艺术细节优化（分支 fix/intro-artistic-refine，已合入 master）
- 本次目标：用户反馈「将红色的米米删除」「整个效果还差一点艺术感」，要求继续设计优化。
- 完成内容：
  - 删除红色「米米」印章：移除模板块、isSealStamped 状态、T+3.35s 落印时序与 playSealStampFoley 音效函数。
  - 新增镂刻页边（Engraved Folio Border）：暖色双发丝线边框 + 四角旋转菱形 + 顶部/底部 ♫ 音符，随 letterbox 淡入（z-[22]，位于画布之上、内容之下）。
  - 背景淡印五线谱谱带：顶部/底部各一条 staff-lines（repeating-linear-gradient 五线谱纹样 + mask 渐隐），纸面更有「乐谱」气质。
  - 标题墨线花饰：标题下方新增 SVG 曲线 + 中点圆点，isTitleFocused 时用全局 animate-ink-draw 描画动画。
  - 口号装饰分隔线：口号上方新增「发丝线 + 菱形 + ♪ 音符」装饰行，随口号一起淡入。
  - 琴弦构图收窄为居中吉他式：弦长改为宽度的 60%（居中），两端新增琴枕/琴桥木质竖条，弦簇背后新增音孔罗塞特同心环（4 圈暖金/木色 + 中心音孔底），更接近真实吉他观感。
- 验证方式与结果（证据）：
  - npx astro build 通过；dev server 实测：印章文字「米米」已消失、staff-lines 2 条、页边与花饰 SVG 存在、口号文本完整；canvas 弦带采样为暖青铜色；桌面/移动截图 tests/evidence/intro-artistic/（intro-strings/title/full/mobile）；console/pageerror 零报错；移动端 390px 无横向溢出。
  - 合并后 master 冒烟通过。
- 遇到的问题与决策：首版补丁脚本误用 must() 返回值（搜索串）作为索引做切片，导致文件前 470 行被误删；已 git checkout 恢复并改为 indexOf 精确切片后重新应用，补丁成功。临时脚本已清理。
- 下一步：如需进一步强化，可评估片头与详情页谱面火花轨迹联动、或新增片头尾帧与首页 hero 的无缝衔接（另立任务）。

### 2026-08-16 ｜ 开屏动画纸色主题 + 真实质感吉他弦（分支 fix/intro-paper-guitar，已合入 master）
- 本次目标：用户反馈「开屏背景想要和主题一致的纸质色」「现在的吉他效果不好看」。将开屏从暗色电影风整体改为与全站（M10 纸页体系）一致的暖纸书卷风，并重做琴弦质感。
- 完成内容：
  - 背景：根容器 #07080a → paper-grain-bg（暖纸 #fbfaf7 + 径向暖光 + 棉纸纤维）；暗色 vignette → 暖纸页缘光影；电影颗粒 → 纸面纤维（multiply）；letterbox 黑边 → 纸色页缘（金/蓝发丝线）；光束 amber→cyan → 暖金 + signal 蓝。
  - 琴弦：6 根弦改为真实原声吉他质感 —— 低音粗深（#51422f）、高音细亮（#a19368）青铜暖色系；圆柱受光渐变（shade 上亮下暗）+ 暖色捕光高光 + 纸面投影；拨动时金色辉光增强、静止时收敛为细发丝；锚点改为墨色圆点 + 金环（桥/枕质感）；新增弦簇后暖色光晕，让弦「落在纸面上」。
  - 文字：标题 MIMI GUITAR 白→金改为墨→暗金渐变；副标题/口号/技术信息全部转暖墨色 + letterpress 压印；跳过按钮改纸玻璃（paper/70 + hairline）；进度条暖金→signal；朱砂印章、播放/交互/时序全部保留。
- 验证方式与结果（证据）：
  - npx astro build 通过；dev server 实测：根容器 computed background rgb(251,250,247) + 纸纹径向渐变、标题渐变 rgb(47,40,30)→rgb(201,164,95)、口号暖墨色、canvas 弦带采样为暖青铜色；桌面/移动截图 tests/evidence/intro-paper/（intro-strings/title/full/mobile）；console/pageerror 零报错；移动端 390px 无横向溢出。
  - 合并后 master 冒烟：首页片头正常出现、背景纸色、零报错。
- 遇到的问题与决策：文件为 CRLF 行尾，多行替换需按行处理；Svelte 模板中 SVG 含转义引号，改为只替换 class 属性避免破坏。临时调试脚本已清理。
- 下一步：如需进一步强化开屏，可评估「片头弦拨动与谱面火花轨迹」联动、或加轻量落尘粒子密度档位（另立任务）。

### 2026-08-16 ～ M10 性能与稳定性优化 + 谱面纸页展示（分支 perf/score-load-presentation）
- 本次目标：用户反馈「点击进入乐谱需要的时间非常长」「完成 UI 设计后一直卡在 乐谱与音频引擎加载中…」，并要求吉他谱展示更有艺术特色。
- 完成内容：
  - 根因定位（实测证据）：DOM 295ms 加载完，但播放器 loadScore 首次访问 12s 才触发（Vite 冷编译 + 大模块图）；热缓存 0.9-1.7s；首访会话片头（MasterpieceIntro）全屏遮挡约 6s；播放器 loadScore 存在容器未就绪即早退且 loading 恒 true 的缺陷。
  - MasterpieceIntro：新增 autoPlay prop（默认 true）；Base.astro 改为仅首页（currentPath === '/'）自动播，内容页不遮挡但仍可经导航/页脚按钮或 mimi:play-intro 事件手动触发。
  - ScorePlayer 稳定性：loadScore 增加 container 响应式等待（$effect 依赖 container，未就绪不早退、就绪自动重跑）；25s 加载看门狗（超时显示错误+重试）；错误层新增「重试」按钮（retryLoad）。
  - 音源加载：sf2 字节并行抓取（Promise.all），再串行喂给 AlphaTab，避免多音轨曲谱串行网络耗时，同时规避并发 loadSoundFont 竞态。
  - 谱面纸页展示：谱面容器暖纸渐变 + 发丝框 + 柔和阴影；页眉改用活字印刷风衬线（调性/速度/曲名 + ♩ 装饰 + 暖色分界线）；页脚「曲名 ✦ MIMI Guitar · 谱页」；与既有 Cascadia/方正小标宋字体、和弦图、歌词渲染兼容。
  - 移动端：详情页谱面预览截图图 max-w-md → w-full max-w-md，修复 390px 下 100px 横向溢出。
- 验证方式与结果（证据）：
  - 生产构建实测（Playwright + astro preview）：详情页首访 1.3s 出谱、片头不遮挡（intro=false）、console 零报错；首页首访片头正常播放。
  - dev 实测：详情页热加载 1.8s、移动端页面宽度 390=390 无整页溢出；证据 tests/evidence/perf/*.png。
  - 回归：node --test（--test-concurrency=4）82/82 全绿（默认并发下 Playwright 用例偶发超时为既有资源竞争，单独跑均通过）；npx astro build 通过。
- 遇到的问题与决策：
  - node --test 默认并发跑多个 Playwright 用例会互相抢 dev server/浏览器资源导致超时，单独/受限并发均通过 → 属既有测试基础设施脆弱性，未在本次改动范围。
  - 片头产品定位为「品牌开场」，故保留首页自动播+全站手动触发，而非整体移除。
  - 谱面展示增强以「纸页质感」落地（与全站 paper-craft 语言一致），不重排 AlphaTab SVG 内部元素，保证谱面可读性与此前字体/和弦/歌词修复不回退。
- 下一步：如需进一步压首屏，可评估生产包 code-split（AlphaTab 主包 ~1.3MB）与 .ibe 解码 Web Worker 化（另立任务）；片头在首页已做 session 记忆。
### 2026-08-14 ～ M8.12 谱面字体与歌词间距（中文/数字→方正小标宋简体；歌词下移）
- 本次目标：用户要求谱面「中文和数字」改用方正小标宋简体，并把歌词再往下移（此前歌词紧贴上方数字行）。
- 完成内容：
  - 字体来源：本机已装 方正小标宋简.TTF（C:\Users\Legion\AppData\Local\Microsoft\Windows\Fonts），打包复制到 public/font/FZXiaoBiaoSong.TTF 自托管（与 CascadiaCode.ttf 同模式，跨机可用）。
  - global.css：新增 @font-face（font-family 方正小标宋简体）。
  - playerSettings.ts：新增 CJK_FONT（方正小标宋简体 优先）与 SCORE_FONT（Cascadia Code 优先）两组字体：
    - 中文/数字类（标题/艺人/歌词 wordsFont+EffectLyrics/品数 tablatureFont/简谱 numberedNotationFont/小节号/指法/和弦图数字）→ CJK_FONT；
    - 拉丁类（和弦名 EffectChordNames/滑音/方向/演奏记号等）→ SCORE_FONT（保持 Cascadia Code，符合「中文和数字」的字面要求）。
  - 歌词下移：AlphaTab 无独立歌词偏移设置；确认 display.effectBandPaddingBottom 控制 effect 带之间/底部间距（官方 1.8.4 设置，非 hack），从 22 → 40，歌词行相对原始位置下移约 30px（歌词 Y 338.9→369.1），同时系统间垂直留白略增。
  - 修复：dev server 对启动后新增的 public 文件（FZXiaoBiaoSong.TTF）404 → 重启 dev server 后正常；Svelte 补丁残留 } 与全局样式字节校验。
- 验证方式与结果（证据）：
  - 运行时断言：SVG 歌词/品数/简谱 font-family 首项=方正小标宋简体，和弦名=“Cascadia Code” 首位；document.fonts 状态 loaded；字体请求 200（3835244B）。
  - 歌词 Y：338.9 → 369.1（下移约 30px），scrollH 6413 → 7003。
  - 本地视觉 API（gpt-5）复核：数字行与歌词间距「舒适、清晰分离」；中文字符与数字呈宋体衬线风格（stroke contrast + serif finishing），非黑体。
  - 回归：verify-player-display 11/11、verify-score-details 8/8、verify-track-mode 6/6、verify-player-fix 9/9、verify-player-audio 12/12、verify-m7-final 41/41、node --test 58/58、npx astro build 通过；全程 console/pageerror 零报错。
- 遇到的问题与决策：
  - 方正小标宋简体未随系统字体枚举被发现 → 从用户字体目录复制并自托管；@font-face 用 ASCII 文件名规避 URL 编码。
  - 歌词没有独立可用的 CSS 类/原生偏移 → 采用官方 display.effectBandPaddingBottom（effect 带间距），避免 JS 标记与源码 hack。
  - 视觉模型对 10.92px 小字号字体判断不稳定 → 用 document.fonts.check + 网络 200 + 放大截图复核确认字体真实生效。
- 下一步：合入 master 后主分支回归冒烟；如需打印/PDF 也应用相同字体与间距（printScore 复用同一 Settings，应自动生效，待抽验）。

### 2026-08-14 ～ M8.11 数字谱语义修正：关闭后不再隐藏和弦品数
- 本次目标：修复「关闭数字谱后符号（和弦品数）消失」问题——六线谱和弦品数必须始终完整显示，数字谱开关只控制简谱（numbered）谱表的显隐。
- 完成内容：
  - 实测确认：参考站默认（数字谱 OFF）= 45 SVG/236 文本，TAB 和弦品数完整；ON = 561 文本（新增数字记号层）。本地旧逻辑用 CSS 隐藏 .at-chord-note（仅保留每拍最上方音符），语义错误。
  - 新语义：TAB 和弦品数始终完整；数字谱开关控制 stave.showNumbered（简谱行显隐）。numberTab 默认改为 true（与当前默认外观一致）。
  - ScorePlayer.svelte：新增 applyNumberTab(sc)；buildScoreFromJson 在 !numberTab 时全轨 showNumbered=false；toggleNumberTab 改走 withRenderPreservingPosition 重渲染（保留播放位置）。移除失效的 at-number-tab 容器类绑定。
  - 清理死代码：删除 markChordNotes/ensureChordMarker/MutationObserver 机制与 global.css 中 .at-chord-note{visibility:hidden} 三条规则（此前会把和弦品数全部隐藏）。
  - 修复补丁引入的编译错误：#score-scroll div 标签未闭合（> 丢失导致 {#if} 被解析为属性）、buildScoreFromJson 重复 capo 赋值行。
  - 测试更新：verify-player-display A1/A2/A3 改为新语义（默认简谱可见+品数完整；关闭后简谱隐藏且品数列数不变、scrollHeight 6413→4484；重新打开恢复）；verify-score-details S5 同步更新。
- 验证方式与结果（证据）：
  - node tools/verify-player-display.mjs：11/11 PASS（A2 关闭后 showNumbered 全 false、品数 506 列保持不变、数字 2570→2158、scrollH 6413→4484；A3 恢复）。
  - node tools/verify-score-details.mjs：8/8 PASS（S5 before hasNumbered=true/digits=2912/scrollH=6413 → after false/2500/4484）。
  - 回归：node --test 58/58、verify-track-mode 6/6、verify-player-fix 9/9、verify-player-audio 12/12（A8 数字谱不刷新 MIDI）、verify-m7-final 41/41、npx astro build 通过。
  - 截图证据：tests/evidence/display/a1-number-default.png / a2-number-off.png / a3-number-on.png。
- 遇到的问题与决策：
  - 首个补丁把 #score-scroll 的 > 与 at-number-tab 类一起移除，导致 div 未闭合 → Svelte 编译错误（页面 500）；已补回 >。
  - 断言最初用「首个 SVG 高度」判断简谱行，但首个 SVG 是头部小图（高度不变）→ 改用容器 scrollHeight。
  - 旧的 CSS 隐藏规则在移除 at-number-tab 类后仍会永久隐藏和弦品数 → 必须整体删除并移除 markChordNotes 死代码。
- 下一步：合入 master 后主分支回归冒烟；持续对照参考站核对其余谱面细节。


### 2026-08-14 ｜ M8.7 谱面显示模式切换（吉他谱+简谱 / 全部六线谱）
- 本次目标：解决「多六弦音轨曲谱显示成两排六线谱」的问题，对齐参考站（1 六线谱 + 1 简谱行 + 歌词），并保留两种模式可切换（用户选择方案 C）。
- 完成内容：
  - 根因确认：《安和桥》有 2 个六弦吉他音轨（均为 program 25），旧逻辑按调弦渲染导致两排六线谱；《晴天》是吉他+钢琴，本就 六线谱+简谱。
  - 新增 src/lib/scoreDisplayMode.mjs：SCORE_DISPLAY_MODES(mixed/tab)、resolveStaveDisplay、applyScoreDisplayMode、countTabTracks、canUseMixedMode、hasWholeRestCrash；全部纯函数。
  - ScorePlayer.svelte：默认 mixed（主音轨六线谱+其余音轨简谱），控制条新增「吉他谱+简谱 / 全部六线谱」分段切换（纯显示变更，保留播放位置，不重生成 MIDI）；晴天型（仅 1 吉他轨）切换禁用。
  - 打印/PDF 共用同一 score 对象，随当前模式输出。
  - AlphaTab 1.8.4 边界定位：次音轨含全音符休止符（duration=1）时转简谱会触发 NumberedBarRenderer.calculateBeamingOverflows 崩溃（beatOfHighestNote 读 null）；已用「二分清空小节 + 按 duration 变异」实测锁定（Hello 谱 track1 原声钢琴，R1x2）。数据层守卫：含全音符休止符的次音轨保持六线谱，且 canUseMixedMode=false 时默认全部六线谱并禁用混合切换（带 title 提示）。
- 验证方式与结果（证据）：
  - node --test：50/50（新增 score-display-mode 12 项）。
  - node tools/verify-track-mode.mjs：6/6（安和桥混合默认/全六线谱切换/切回/晴天禁用/移动端/Hello 守卫，截图 tests/evidence/track-mode/）。
  - 回归：verify-score-details 8/8、verify-player-display 10/10、verify-player-fix 9/9（T8 Hello 0 报错）、verify-player-audio 12/12、verify-m7-final 41/41、npx astro build 通过。
  - 视觉比对：本地 t1-mixed-default 与参考站 ref-anheqiao（本地视觉 API gpt-5）确认结构一致（和弦名→1 六线谱→1 简谱行→歌词）。
- 遇到的问题与决策：
  - apply_patch 工具仍不可用 → 用 PowerShell Out-File + Node 补丁脚本写文件（UTF-8 无 BOM + CRLF）。
  - 中文经 PowerShell 管道传给 node stdin 会乱码 → 所有带中文的写入改走 Out-File（PowerShell 内部管道保真）。
  - 简谱渲染崩溃根因不是连音休止符（最初假设），而是全音符休止符；二分清空 + duration 变异定位到 duration=1。
- 下一步：主分支回归与合并后冒烟；若后续发现其他 AlphaTab 简谱渲染边界，可加运行时回退兜底。


### 2026-08-13 ｜ M0 工程初始化
- 本次目标：完成工程初始化，建立可运行的骨架与文档基线。
- 完成内容：
  - 环境确认：Node v24.16.0、npm 11.13.0、Git 2.54、Docker 29.6.2（PostgreSQL 以容器运行，端口 5433）。
  - 创建 Astro 5.18.2 SSR 工程（@astrojs/node 9.5.5 + @astrojs/svelte 7.2.5 + Tailwind CSS v4 via @tailwindcss/vite）。
  - 全局样式落地 refero「General Intelligence Company」token（Parchment/Paper/Linen/Mist/Signal Blue 等 14 色、Fraunces 标题 + Inter 正文、圆角体系、无阴影/毛玻璃原则）。
  - 验证页：首页（编辑风导航+hero）+ Svelte 5 岛屿组件（Hero.svelte 点击计数器）。
  - PostgreSQL 容器 mimi-guitar-pg 启动并 healthy；Prisma 6.19.3 首迁移 `init` 完成，Prisma Client 生成。
  - 编写 PLAN.md（十章节）与 DEV_LOG.md（本文件）。
- 验证方式与结果：
  - `npx astro build`：✅ 服务端 entrypoint + 客户端 107 模块全部构建成功。
  - `docker compose up -d postgres`：✅ 容器 healthy。
  - `npx prisma migrate dev --name init`：✅ 数据库同步，Prisma Client 生成。
  - 已知问题：PowerShell 写入文件的 UTF-8 BOM 导致 package.json JSON 解析失败 → 已统一重写为无 BOM UTF-8 并复验构建通过。
- 遇到的问题与决策：
  - apply_patch 工具在当前环境每次调用均被中止 → 改用 PowerShell `[System.IO.File]::WriteAllText`（无 BOM UTF-8）写入文件。
  - @astrojs/svelte 6.0.2 仅支持 Astro 4 → 改用 7.2.5（peer astro ^5）。
- 下一步：M1 数据管线 —— `.ibe` 解码工具链与迁移爬虫。

### 2026-08-13 ｜ M1 数据管线（完成）
- 本次目标：建立 `.ibe` 解码工具链与迁移入库管线，完成全量数据迁移。
- 完成内容：
  - 逆向确认 `.ibe` 格式：XOR（密钥 `guitartabspro`，自 `len%10` 偏移循环）→ AR 解压 → **alphaTab JSON 谱面**（非 Guitar Pro 二进制）。
  - 编写 `src/lib/ibe.ts`（xor/normalize/AR 加载注入）、`ar.node.ts`（Node fs+vm 加载 ar.es）、`ibe.node.ts`（zlib deflate 自有 MIMI 格式编解码）。
  - 关键适配：站点 JSON 为 alphaTab 1.3 时代驼峰键 schema，官方 1.8.4 为全小写键 → 编写递归归一化（`showNumberedNotation→shownumbered`、`tempoAutomation→tempoautomations` 特殊处理；chords 映射键保留；顶层 tempo 注入 masterBars[0].tempoAutomations）。
  - 迁移爬虫 `tools/migrate.mjs`：首页排行榜+列表页采集候选 → 详情页括号匹配提取 sheetInfo（ins 序列化 `[tag,value]` 解码）→ 下载 `.ibe`/截图 → 解码校验 → PostgreSQL 入库；带限流(567)退避重试与节奏控制。
  - 数据库：5 首验证批次入库成功（晴天/老男孩/卡农/风吹麦浪/后来），元数据完整（调性/拍号/BPM/Capo/调音/难度/类型/热度）。
  - 全量迁移完成：**1624 首入库**（吉他 1500 + 尤克里里 124），`.ibe` 与截图全部落盘 `public/storage/`。
  - 上传侧：自有 MIMI 格式（魔数+deflate+XOR）encode/decode 单测通过，供 M5 上传管线复用。
- 验证方式与结果：
  - `node --test`：4/4 通过（xor 往返、真实样本解码、官方 alphaTab 解析、MIMI 往返）。
  - 全量迁移日志 `tools/migrate-full.out.log`：1624 首，无未处理错误。
- 遇到的问题与决策：
  - alphaTab 官方 1.8.4 `json` 桶为空、`ScoreLoader` 不认站点 JSON → 用 `model.JsonConverter` + 键名归一化解决。
  - 站点限流（HTTP 567）→ 退避重试 + 1200ms 节奏；爬取耗数小时但全部完成。
- 下一步：M2 播放器（谱面渲染 + 全套控制）。

### 2026-08-13 ｜ M2 播放器（完成）
- 本次目标：实现与原站一致的核心播放器：谱面渲染、播放控制、循环、变调夹、速度、节拍器、多轨、乐器切换、PDF/打印；吉他与尤克里里双端自动化验收。
- 完成内容：
  - 播放器定制层 `src/components/player/ScorePlayer.svelte`：ibe 双格式解码（原站 AR + 自有 MIMI）→ `model.JsonConverter.jsonToScore` → `renderScore`；display 配置对齐原站（scale 0.84、stretchForce 0.66、Tab 谱、padding 20、scrollElement #score-scroll、scrollOffsetY -200）。
  - 浏览器端 AR 加载器 `ar.browser.ts`（?raw + eval）、ibe 浏览器解码 `ibe.browser.ts`（DecompressionStream deflate）。
  - 播放控制：播放/暂停/重来、速度 30–300（改 tempo 自动化 + playbackSpeed）、预备拍（countInVolume）、节拍器（metronomeVolume）、变调夹（staff.capo 重渲染）、字体缩放（display.scale）、数字谱（showNumbered）、音轨显隐/静音/独奏/音量、GM 128 乐器切换（按需加载 `{program}.sf2`）、打印/PDF。
  - 循环：两次点击音符设 startTick/endTick → playbackRange + isLooping；**修复 alphaTab 默认点击音符会清空 playbackRange 的问题**（playbackRangeChanged 粘性重放）。
  - 打印/PDF `printScore.ts`：隐藏容器重渲染（关闭 cursor/player/交互）→ SVG 分页 A4 → Canvas → JPEG → jsPDF 拼接，水印 `作者@谱全了`，文件名取页面标题。
  - 详情页 `/tabs/[id].astro`、`/ukulele/[id].astro`：SSR 元数据（调性/速度/拍号/Capo/调弦/热度/上传者/标签/相关推荐）+ ScorePlayer。
  - Vite 配置：`optimizeDeps.exclude: ['@coderline/alphatab']`，修复 dev 下 alphaTab worker 404（worker URL 相对 node_modules 解析）。
- 验证方式与结果（Playwright + 系统 Chrome，证据在 `tests/evidence/`）：
  - 吉他页 `/tabs/1sdc49P3eKm`：HTTP 200、谱面渲染（8 个 SVG）、播放/光标可见、速度→150、节拍器/预备拍勾选、变调夹→2、数字谱、音轨/乐器面板、循环（range {1920,6720} + isLooping + 循环中横幅）、PDF 下载（晴天.pdf 187KB 含谱面）、重来；**console 零报错、pageerror 零**。
  - 尤克里里页 `/ukulele/1wmj8hqHnYf`（萱草花）：HTTP 200、渲染、播放、光标、重来，零报错。
  - `node --test` 4/4 通过；`npx astro build` 通过。
- 遇到的问题与决策：
  - Svelte 组件容器仅在 `{:else}` 渲染导致 onMount 时 container 为 undefined → 改为容器常驻 + 加载/错误覆盖层。
  - 官方 1.8.4 `Score.tempo` 只读 → 改 `masterBars[0].tempoAutomations[0].value` + updateSettings + playbackSpeed。
  - 官方 API 事件/属性与 fork 基本一致（masterVolume/playbackRange/isLooping/tickCache/beatMouseUp 等均在 api 上）→ 组件直接使用官方 API。
  - 变调夹用 `staff.capo`（官方语义）而非 transpositionPitches 数组。
  - 打印渲染竞争：postRenderFinished 会在初次空渲染提前触发 → 改为轮询等待真实 SVG 内容；分页高度 NaN 防御。
  - sf2 请求在 Chromium 网络面板显示 ERR_ABORTED（缓冲区经 postMessage 转移所致），实际下载与加载成功、无 console 报错——记为本项目已知外观问题。
  - **重要环境教训**：exec 的 `shell_command` 返回字符串含 `Exit code/Wall time/Output:` 头，直接 read→replace 写回会污染文件。此后一律用 Node 脚本或整文件重写，避免二次污染。
- 下一步：M3 前台（首页排行榜、列表筛选/排序/分页、搜索、文章、首页改造）。
### 2026-08-13 ｜ M3 前台（完成）
- 本次目标：实现前台页面：首页排行榜、列表筛选/排序/分页、搜索、文章与静态页。
- 完成内容：
  - src/lib/tabQuery.ts：DIFFICULTY/STYLE/FORM/KEY/TUNING 选项 + queryTabs()（分页 90，sort 0=最新/1=最热，keyword ILIKE，URL 参数 SSR）+ buildListHref()。
  - src/components/FilterBar.astro 与 TabCard.astro：筛选条（难度/类型/调性/调弦/谱型/排序）与曲谱卡片。
  - 首页 index.astro：编辑风 hero + 热门排行/最新上架/吉他精选/尤克里里精选（DB 实时数据）。
  - 列表页 /tabs 与 /ukulele：URL 参数筛选（difficulty/style/key/tuning/sheetForm）+ 排序 + 分页（no）。
  - 搜索页 /search：q 参数 → 吉他 + 尤克里里双结果区与空态。
  - 详情页 /tabs/[id] 与 /ukulele/[id]：修复难度标签（difficulty=0 不再显示「全部」），meta 行统一拼接。
  - 文章：/article 列表 + /article/[id] 详情；种子 4 篇演示文章（入门/TAB/变调夹/播放器原理）。
  - 静态页：/about、/help、/policy、/copyrightPolicy、/licenses、/contact（refero 编辑风 + 合规说明）；footer 增加「联系我们」。
- 验证方式与结果（Playwright + 系统 Chrome，证据在 tests/evidence/m3-*.png）：
  - 首页/列表/搜索/文章/静态页/详情共 15 个 URL 全部 HTTP 200，console 零报错、pageerror 零。
  - 筛选生效：/tabs?difficulty=2&sheetForm=1 → 53 张卡；分页生效：sort=1&no=2 正常换页；搜索「晴天」→ 8 条结果。
  - 详情页（晴天）播放器回归：8 SVG 渲染 + 播放/高亮光标 + 零报错。
  - npx astro build 通过；node --test 回归通过。
- 遇到的问题与决策：
  - search.astro 误用 Svelte 模板语法（{#if}、{:else}）导致构建失败 → 全部改为 Astro JSX 风格（条件 && 表达式 / 三元）。
  - 原站确认 difficulty=0 = 「全部」（筛选语义）；DB 中 42 首 difficulty=0 实为未标注 → 列表/详情统一不显示难度标签（与原站一致）。
  - PowerShell here-string 中的换行转义经 exec 模板字面量会被解释为真实换行（破坏正则）→ 改用双反斜杠写入。
  - 文章页 h1 定位到 Astro dev-toolbar「No islands detected.」为 Playwright 穿透 shadow DOM 所致，非页面错误。
- 下一步：M4 用户系统（注册/登录/收藏/浏览记录）。
### 2026-08-13 ｜ M4 用户系统（完成）
- 本次目标：实现用户系统：注册/登录/找回密码、收藏、浏览记录、个人资料与账号中心页面。
- 完成内容：
  - 认证库 src/lib/auth.ts：内置 node:crypto 实现 scrypt 密码哈希 + HMAC-SHA256 JWT（无第三方依赖），7 天会话。
  - API 辅助 src/lib/api.ts：JSON 响应、请求体解析、会话 cookie 读写、currentUser 解析。
  - 认证 API：/api/auth/register、login、logout、me、send-code（短信 mock）、reset。
  - 收藏 API：/api/favorites 列表、/api/favorites/[tabId] 状态 GET / 添加 POST / 取消 DELETE；未登录 GET 返回 200+favorited:false，变更需登录。
  - 页面：/login、/register、/account/reset（重置密码）；账号中心 /account/0 资料、/account/1 收藏、/account/2 创作中心（占位）、/account/3 浏览记录；/upload 占位页。
  - 组件：AuthForm（登录/注册表单）、ResetForm（发送验证码+重置）、LogoutButton、FavoriteButton（详情页收藏切换）、TrackHistory（本地浏览记录）、FavoriteList、HistoryList。
  - 详情页接入：收藏按钮 + 浏览记录写入（localStorage 键 guitarHistoryList / ukulekeHistoryList，去重上限 50）。
  - 导航：Base.astro 依据登录态显示「我的」/「登录」。
- 验证方式与结果（Playwright + 系统 Chrome，证据在 tests/evidence/m4-*.png）：
  - 后端流程：注册 200、/api/auth/me 200（cookie 会话）、收藏增/查/列 200（晴天入列）、登出后 me 401。
  - UI 流程：登录表单提交跳转 /account/0（个人资料）；错误密码内联提示「账号或密码错误」；重复注册 409「该账号已注册」；重置密码（send-code 返回 6 位 mock 码 → reset 200 → 新密码登录 200）。
  - 收藏交互：登录态点击「☆ 收藏 1」→「★ 已收藏 2」；未登录点击跳转 /login?returnUrl=...。
  - 浏览记录：详情页访问后 localStorage 写入 97 字节记录；/account/3 正常渲染。
  - 全部页面/流程 console 零真实报错；npx astro build 通过；node --test 5/5 通过。
- 遇到的问题与决策：
  - Playwright 测试中点击收藏后 textContent 超时——实为未登录点收藏按设计跳转登录页（测试预期错误，功能正确）。
  - PowerShell 数组传参存在展开问题（嵌套数组被拍平）→ 改用 Node 脚本做文件补丁。
  - API 文件深层路径（api/favorites/[tabId].ts）相对导入需 ../../../ 三级，构建时修正。
  - 密码哈希与 JWT 使用内置 crypto，避免额外依赖；短信验证码为内存 mock（生产需替换）。
- 下一步：M5 上传创作中心（上传流程、审核、我的作品）。
### 2026-08-13 ｜ M5 上传创作中心（完成）
- 本次目标：实现 Guitar Pro 上传创作中心：上传 → 服务端解析 → 生成 .ibe → 渲染预览图 → 审核占位 → 公开展示。
- 完成内容：
  - 服务端 GP 处理 src/lib/gpUpload.ts：ScoreLoader 解析 GP 二进制 → JsonConverter.scoreToJson → 自有 MIMI .ibe 编码（deflate+XOR）；提取标题/艺人/速度/拍号/Capo/调弦/谱型元数据。
  - 截图渲染页 src/pages/render.astro + src/lib/screenshot.ts：无头 Chrome 加载 render 页渲染 .ibe 并截取首页 SVG 为预览图。
  - 上传 API /api/upload：multipart（request.formData()，无新依赖）→ 解析校验 → 落盘 public/storage/upload → 渲染截图 → 写入 UploadRecord（pending）。
  - 审核占位 API /api/upload/[id]/review：approve 创建 Tab 公开展示 / reject 置为已拒绝（真实上线应由管理员审核）。
  - UI：/upload 页 + UploadForm（文件/分类/标题）；创作中心 /account/2 显示我的作品（缩略图/状态/模拟通过/拒绝）。
  - 数据库迁移 upload_meta：UploadRecord 增加 screenshotUrl、metaJson、tabId 字段。
  - 播放器音源优化：sf2 用清单（index.json）替代 HEAD 探测，消除缺失音源（如 49/51）的 404 控制台报错，缺失回退 0.sf2。
  - 测试夹具：从 alphaTab 官方仓库下载 canon.gp5（Canon Rock, JerryC）与 chords.gp5。
- 验证方式与结果（Playwright + 系统 Chrome，证据在 tests/evidence/m5-*.png）：
  - 单元测试 tests/upload.test.mjs 4/4：canon 元数据、chords 解析、MIMI 往返、非法文件抛错。
  - 端到端：上传 canon.gp5 → 201（截图生成）；模拟通过 → 200；详情页 /tabs/{id} 播放器渲染 6 SVG、h1 Canon Rock；上传 chords.gp5 → 模拟拒绝 → 200；/account/2 展示两条作品。
  - Canon Rock 详情页（含缺失音源 49/51）零 404、零 console 报错。
  - npx astro build 通过；node --test 9/9 通过（含冒烟）。
- 遇到的问题与决策：
  - render 页容器宽度 0 导致 alphaTab 跳过渲染 → 客户端脚本显式设置宽度（Astro style 属性内表达式不生效）。
  - 上传记录曾用 cuid id 而 API 返回存储 id → 审核按 id 查不到 → 改为 UploadRecord.id 使用存储 id（URL 稳定）。
  - 原站不存在 49/51.sf2 → 播放器音源加载改清单 + 回退，避免 404。
  - 服务端渲染截图需与 dev server 同端口互访（SITE_URL 可配置）。
  - DEV_LOG 的 here-string 结尾无换行导致分隔符被接行 → 记录工具已改为显式追加换行并修复。
- 下一步：M6 设计打磨与性能（全站 refero 视觉验收、长谱/多轨性能、移动端适配、无障碍、安全审查）。
### 2026-08-13 ｜ M6 设计打磨与性能（完成）
- 本次目标：全站 refero 视觉落地收尾、移动端适配、无障碍、安全加固、性能基准与最终全站验收。
- 完成内容：
  - 移动端适配：修复全部 grid 无显式列数被内容撑宽导致横向溢出的 bug（tabs 页卡片曾达 574px，批量补 grid-cols-1，12 个文件）；新增汉堡菜单 MobileMenu.svelte（sm:hidden）；Base.astro 导航重构为 w-full max-w-[1200px] + 移动端 px-4。
  - 无障碍：global.css 增加 :focus-visible 键盘聚焦 outline 与 img max-width:100%；AuthForm/ResetForm 补 label 与 role="alert" 错误提示。
  - 安全加固：新增 src/lib/rateLimit.ts（内存滑动窗口限流）；登录/注册/send-code 限流 10 次/分钟；render 截图页路径守卫（/storage/ 前缀校验）；生产环境强制 JWT_SECRET。
  - 设计系统：新增 --color-danger（#b3261e）token，替换 AuthForm/ResetForm/UploadForm 三处硬编码 text-red-600。
  - 性能基准（Playwright 实测）：晴天（基准）首屏谱面 1.4s/总 1.5s/7 SVG/44MB；Dream Theater 长曲 2.7s/总 2.8s/6 SVG/283MB；Canon Rock 上传谱 1.6s/总 1.7s/5 SVG/102MB；三者 console 与 pageerror 均零。
- 验证方式与结果（Playwright + 系统 Chrome，证据在 tests/evidence/m6/）：
  - 最终全站验收 tools/verify-m6-final.mjs：39/39 通过（17 条公开路由 × 桌面 1440/移动 390 状态码 200 + 无横向溢出 + console/pageerror 零 + 4 个登录态账号中心页 + 晴天详情播放器渲染 7 SVG）；截图 final-home/tabs/article/login/detail-d.png。
  - 移动端审计（390px）：8 个关键页面无横向溢出、无超宽元素；移动端导航隐藏、汉堡菜单可用（截图 mobile-menu.png）。
  - 回归：npx astro build 通过（仅播放器大 chunk 已知警告）；node --test 9/9 通过（ibe 4 + upload 4 + smoke 1）。
- 遇到的问题与决策：
  - 移动端横向溢出根因是 grid 容器未指定列数、内容（卡片 min-width 由内容撑开）把容器撑到 574px → 给所有此类 grid 显式 grid-cols-1（桌面由断点类控制），一次性修复 12 个文件。
  - rateLimit 采用进程内内存滑动窗口（单实例够用），生产多实例需换 Redis——记为已知限制。
  - 无障碍 axe 自动审计未做（环境无工具），以键盘聚焦样式 + 表单 label 手工补齐，记为已知待完善项。
- 下一步：全部里程碑完成；合并 M6 至 master 并跑主分支回归，随后全项目收尾。

---

- **合并与主分支回归（master a319da3）**：M1+M2 以 --no-ff 合入 master；主分支 node --test 4/4、astro build 通过；浏览器冒烟（首页/吉他详情/尤克里里详情）全部 200 且 console 零报错。注：切换分支后需清 .astro 与 node_modules/.vite 缓存重启 dev server，否则出现 504 Outdated Optimize Dep 与 Svelte 水合报错。

---

- **合并与主分支回归（master 7841d89）**：M6 以 --no-ff 合入 master；主分支 astro build 通过、node --test 9/9 通过；清缓存重启 dev server 后浏览器冒烟（首页/吉他详情 8 SVG/尤克里里详情 9 SVG）全部 200 且 console 零报错。

---

- **全项目收尾（M0–M6 全部完成）**：六个里程碑全部完成并合入 master；PLAN.md 覆盖全部十章节（功能矩阵/技术栈/数据模型/谱面显示与播放器架构/设计系统/接口/风险/测试）；每步验收证据存于 tests/evidence/ 与本文件。未做项：无障碍 axe 自动审计、生产部署（Docker/CDN/对象存储）、正式音源授权、计费/会员系统——均在 PLAN.md 中标注为后续可选项。

---

## 待确认 / 已知问题

1. sf2 请求 Chromium 网络面板显示 ERR_ABORTED（功能不受影响，声音正常加载），待确认是否可在生产规避。
2. 原站登录/上传内部实现为功能等价复刻，未逐字节复刻。
3. 替代字体（Fraunces/Inter）视觉近似 refero 专有字体但非完全一致。
4. 数据版权：迁移内容为学习演示用途，正式商用前需替换为授权内容。

---

## M7 进度（对齐原站功能+交互，分支 feat/m7-parity）

### M7.0 文档落地 ✅
- GAP_REPORT.md（差距矩阵+实测证据）、UPDATE_PLAN.md（落地版任务清单）已交付；分支 feat/m7-parity 已建。

### M7.1 数据扩充（进行中）
- 迁移工具升级为「候选清单 + checkpoint 断点续爬」架构（tools/migrate.mjs）：预枚举候选 10235 条（tools/migrate-candidates.json），按 id 去重、done/failed 集合断点续爬、567/429 指数退避 + 抖动节奏。
- 冒烟测试通过（3 条：2 ok / 1 skip）；全量后台爬取已启动（PID 41248：--ids migrate-candidates.json --pace 1100 --state migrate-state-m7.json，日志 tools/migrate-m7.out.log）。
- 目标：吉他+尤克里里合计 ≥10000 首入库（候选 7568 条待新增，扣除已入库）。
- 备注：曾出现多个 migrate 进程竞争（含旧的 target/pace 版本与一次冒烟测试），已统一收敛为单一进程；日志与 state 文件已隔离。

### M7.2 账号中心与导航对齐 ✅（commit 82390f0）
- 账号路由重排为原站顺序：/account/0=我的收藏、1=创作中心、2=浏览记录、3=个人资料；新增 AccountNav.astro（4 项 + 上传 + 退出登录）。
- 未登录访问账号中心显示空态（收藏/创作/资料）或正常可用（浏览记录），不再整页跳登录。
- 导航对齐：全局搜索框（→ /searchResults）、上传下拉（吉他谱/尤克里里谱）、我的账号下拉（4 项 + 退出登录）、登录·注册按钮；MobileMenu 同步补全并支持登录态。
- /upload 增加登录守卫与 ?type=guitar|ukulele 参数（UploadForm 接收 category prop）。
- 验收：Playwright 33/33（公开路由×桌面/移动 + 登录态账号页 + 上传重定向），astro build 通过，node --test 9/9；证据 tests/evidence/m7/account-*.png、m7-home.png。


### M7.3 搜索页对齐 /searchResults ✅（本次收尾：dev server 缓存导致的 500 已通过重启修复）
- 新路由 /searchResults（参数 type/searchValue/sort/sheetForm/difficulty/page）；保留 /search?q= 302 重定向到该路由。
- 筛选：艺术家/歌曲名称切换（field=title|artist）、全部难度、全部谱型、最热/最新排序；吉他/尤克里里/文章三 tab 含计数；结果卡片含艺人/难度/热度/谱型。
- tabQuery.ts 新增 searchField 支持（title/artist/all）；首页与导航搜索框均指向 /searchResults。
- 验收：Playwright 桌面/移动 3 项全过（三 tab 计数正确、tab 切换、难度筛选、/search?q= 重定向、无 console 报错、无溢出）；新增 tests/search.test.mjs 5/5（title/artist/OR/难度谱型叠加/分页一致性）；证据 m7-search-d.png / m7-search-m.png。
- 说明：页面首次访问曾返回 500，实为 dev server 旧缓存（重启后正常），非代码问题；astro build 可编译通过。

### M7.4 首页对齐 ✅（commit 2b4c9?，见 git log）
- 热门区块改「今日/本周/本月」三 tab（HotTabs.svelte，按 publishDate 窗口取热度前 10，不足时回退总热度榜）。
- 新增风格区块：流行/民谣/摇滚/乡村/金属/配乐 6 项 + 计数（link /tabs?style=N）。
- 新增难度矩阵：零基础~专业 × 弹唱/指弹/和弦/六线谱 20 分区，吉他/尤克里里切换（DifficultyMatrix.svelte，计数来自 DB groupBy）。
- 首页顶部加搜索框（→ /searchResults）；底部改为 最新吉他谱 / 最新尤克里里谱。
- 风格数据回填：tools/backfill-style.mjs 从原站风格列表页反推 style（6 风格 × 吉/尤 × 3 页，命中更新 1540 条）。
- 验收：Playwright 桌面/移动均 200、无溢出、无 console 报错、island 交互可用（HotTabs/DifficultyMatrix）；证据 tests/evidence/m7/m7-home-new.png。

### M7.5 详情页与播放器补齐 ✅（验证通过，代码来自并行子代理 + 我的修正）
- 标题格式对齐 tabTitle()（{title}{乐器}_{artist}_{key}调_{难度}{类型}谱_高清{类型}谱）；信息区补 难度、调弦格式（①=E ②=B…）、难度描述、搭配和弦。
- 新增 分享曲谱（ShareButton，复制链接 + 回显"已复制链接"）与 免费下载（DownloadButton → /api/tabs/[id]/download，登录后返回 .ibe 附件，未登录跳登录）。
- 修正 api/tabs/[id]/download.ts 中文乱码（错误提示"请先登录"）。
- 验收：详情页内容项全部命中；登录后下载 200 + content-disposition 正确（21277 字节 .ibe）；未登录下载 302→/login；分享按钮复制成功（剪贴板含当前 URL）；证据 m7-detail-new.png。

### M7.6 社区/文章对齐 ✅（验证通过，代码来自并行子代理）
- /article 支持 sort=new|hot + 分页（9/页）+「发布文章」入口；/community 302 别名到 /article。
- /publishArticle 发布页（登录态，Markdown 输入）+ /api/articles POST；Article 表新增 views 字段（迁移已应用）。
- 验收：文章列表/排序/分页 200，发布→详情全流程通过（发布 200 → 详情 200 含标题）。

### M7.7 静态页与页脚补全 ✅（commit 82390f0）
- 新增 /agreementPolicy（用户协议）、/uploadpolicy（上传政策）、/countact-us（联系我们别名页）。
- 页脚重构为 refero 编辑风四栏（了解谱全了/内容/协议/曲谱分类）+ 版权/客服邮箱 + 备案/网文许可占位文案（不冒用原站真实号码）。

### M7.8 refero 视觉细节微调 ✅
- 字阶细节落地：heading-sm -0.04em、40-54px（heading/heading-lg/display）-0.02em、caption/body-sm（交互与标签主尺寸）500 权重、行高 1.3/1.1。
- 复核结论：text-body-sm 在本项目主要承载交互/标签（导航、按钮、下拉、矩阵链接），500 权重符合「交互/标签默认 500」规范；正文段落占比小，保持统一不拆分。
- 播放器控件 outlined 风格核对通过：.btn = 1px hairline 描边 + 500 字重；.btn-signal = Signal Blue 仅描边（激活态）；Dusk 实心用于 chip-active 与循环横幅；无装饰阴影。

### M7.9 回归与收尾 ✅（本次收尾）
- 修复：api/tabs/[id]/download.ts 中文乱码（错误提示「请先登录」，注释同步修复）；/searchResults 500 实为 dev server 旧缓存，重启后正常。
- 新增：tools/verify-m7-search.mjs（搜索页 Playwright 3/3）、tests/search.test.mjs（搜索查询单测 5/5）。
- 全量验证：node --test 14/14（含 smoke-test）；astro build 通过；M7.2 33/33、M7.3 3/3、M7.4 2/2、M7.5/M7.6 通过（分享/下载/文章全流程）、M7.7 静态页与页脚、M7.8 视觉复核通过。
- 清理：删除临时探测脚本与 smoke/枚举 JSON（db-ids/enum-*/sheet-*/probe-*/patch-migrate/xhe-*/migrate-state-smoke* 等 32 项）；migrate-state-m7.json 加入 .gitignore。
- 数据扩充（M7.1）：后台爬虫持续运行中（候选 10235，已完成 N/10235，fail=0），完成后入库数预计 ≥12000，达到 ≥10000 目标；最终入库数与抽样渲染验收见合并后记录。
- 分支 feat/m7-parity 合并 master 后跑主分支回归（astro build + node --test + 关键页面 200）。

- **合并与主分支回归（master b8a4ebf）**：M7 以 --no-ff 合入 master（5 个功能提交：c1f3daa/82390f0/92199e7/0b2bbe0/e92c2cf）。主分支 astro build 通过、node --test 14/14 通过；清缓存重启 dev server 后浏览器冒烟（首页/吉他详情 8 SVG/尤克里里详情 9 SVG）与 12 条 M7 新路由（searchResults/community/publishArticle/agreementPolicy/uploadpolicy/countact-us/account/3/upload 等）全部 200 且 console 零报错。
- **数据扩充（M7.1）仍在后台运行**：合并时点已完成 939/10235 候选（ok=917），DB 约 3600 首；爬虫完成后入库预计 ≥12000，达到 ≥10000 目标。候选清单文件为临时爬取产物（未入库、未提交），如需重启爬虫可重新枚举列表页生成。

### 2026-08-13 ｜ M7 收尾补充：sheetForm=7 归入六线谱 ✅（master 07225b1）
- 本次目标：修复原站新枚举 sheetForm=7（六线谱）在本地的显示与筛选。
- 完成内容：
  - src/lib/tabQuery.ts：formLabel() 增补 7→六线谱；queryTabs 筛选 sheetForm=4/7 时使用 { in: [4,7] }（六线谱筛选同时命中两值）。
  - src/lib/tabMeta.ts：FORM_LABELS 增补 7→六线（详情页标题拼出「六线谱」）。
  - src/pages/index.astro：难度矩阵聚合时 sheetForm=7 并入 4（六线谱列统计真实）。
  - src/components/DifficultyMatrix.svelte：六线谱列计数同时累加 d:4 与 d:7（双保险，避免重复计数）。
  - 新增 tests/sheetform.test.mjs（5 项）与 tools/verify-sheetform7.mjs（Playwright 6 项）。
- 验证方式与结果（证据）：
  - node --test tests/sheetform.test.mjs 5/5；全量 node --test 19/19（含 smoke-test）。
  - Playwright 6/6：详情页 /tabs/oOEeEQKJ 标题与标签含「六线谱」、/tabs?sheetForm=4 命中 sheetForm=7 曲目、首页矩阵六线谱列计数=300（含 7）、console 零报错；截图 tests/evidence/m7/sheetform7-*.png。
  - npx astro build 通过；分支 fix/sheetform-7 → --no-ff 合入 master（07225b1）后主分支回归：node --test 19/19、tools/verify-m7-final.mjs 41/41 全过。
- 遇到的问题与决策：
  - PowerShell 直接 Invoke-WebRequest 匹配中文因编码错乱不可靠 → 改用 Playwright 读 DOM 文本验证。
  - queryTabs 含无扩展名 import（./db），Node 原生 ESM 无法直接加载 → 单测改为按修复语义直接查库断言（in [4,7]），纯函数仍直接导入。
- 下一步：等待 M7.1 爬虫完成（见下），随后跑 tools/accept-data.mjs 最终数据验收并归档。

### 2026-08-13 ｜ M7.1 数据扩充（进行中 · 进度更新）
- 爬虫 PID 41248 持续运行（--ids tools/migrate-candidates.json --pace 1100 --state tools/migrate-state-m7.json，日志 tools/migrate-m7.out.log），checkpoint 断点续爬。
- 至 15:25 已完成约 1935/10235 候选（ok≈1900，fail=4，skip 为已入库重复），DB 曲谱数约 5000（爬前 2373）；预计剩余约 3.5 小时。
- 候选清单 tools/migrate-candidates.json 曾因误删重建（4000 个）；运行中进程持有旧清单（10235），若中断需以 --ids tools/migrate-candidates.json 续跑（按 id 去重跳过已完成）。
- 状态文件 tools/migrate-state-m7.json 已加入 .gitignore，勿删除。
- 验收计划：爬完后运行 tools/accept-data.mjs（>10000 首、首页矩阵与搜索计数真实、抽样渲染比对），通过后更新 PLAN.md/DEV_LOG.md 并归档证据。

### 2026-08-13 ｜ M7.1 数据扩充（用户要求暂停）
- 用户指示「先不跑了」→ 已安全停止爬虫进程（PID 41248，Stop-Process 强制结束）。
- 停止时点：候选处理至 checkpoint 2700/10235（state done=2593，failed=4；进程被杀时在内存中处理到约 2707，该 7 条未及写 state，但 DB 已 upsert，重跑会幂等跳过/补处理）。
- 停止时 DB 共 5267 首（吉他 4400 / 尤克里里 867）；其中 5075 首带 .ibe（可播放），192 首为 XHE 网页文本谱（原站本就无音频，正常）。
- 与计划目标（≥10000 首）的差距：数据扩充未完成，当前约为目标的一半；断点状态保留于 tools/migrate-state-m7.json 与 migrate-candidates.json（均未提交，.gitignore 排除 state），随时可用原命令续跑：
  `node tools/migrate.mjs --ids tools/migrate-candidates.json --pace 1100 --state tools/migrate-state-m7.json`
- 决策：接受暂停，不删除任何已入库数据与断点文件；恢复时按上述命令续跑即可（id 去重，不会重复入库）。
- 下一步：等用户决定是否恢复爬取；若恢复则跑完后再执行 tools/accept-data.mjs 数据验收。

### 2026-08-13 —— 播放器修复：光标/跟随滚动/实时位置/稳定性/sf2 音源 ✅（分支 fix/player-cursor-follow）
- 本次目标：修复用户反馈的播放器四类问题——(1) 播放无指针/光标；(2) 无实时播放位置跟随；(3) 缺少实时位置指示；(4) 播放稳定性差、音源无声。根因经代码审阅 + 浏览器实测确认后全部修复并验收。
- 完成内容：
  - 光标不可见：AlphaTab 1.8.4 npm 包不附带 CSS，光标元素由库内联定位但无颜色 → 在 src/styles/global.css 补充原生光标类样式（refero Signal Blue 视觉：.at-cursor-bar 淡蓝底、.at-cursor-beat 实色细条、.at-highlight 音符高亮、.at-selection 循环区间），计算样式验证通过。
  - 跟随滚动失效：src/lib/playerSettings.ts 将 scrollMode 由 Off 改为 Continuous（scrollElement=#score-scroll、scrollOffsetY=-200），删除 ScorePlayer 中 120ms 节流的手写 scrollIntoView 兜底；保留播放结束回顶。
  - 无位置指示：控制条下方新增进度区（可拖拽 seek 的进度条 + mm:ss 时间 + 第 N 小节·第 M 拍），数据来自 playerPositionChanged / playedBeatChanged；循环激活时进度条上以 mist 半透明高亮显示 startTick..endTick 区间。
  - 稳定性/无声：
    - 新增 tools/analyze-sf2.mjs 与 tools/convert-sf2-mono.mjs：72 个 sf2 中 14 个纯立体声（sampleType 2/4）+ 1 个混合，AlphaSynth 只支持 bit0 单声道导致采样被跳过（钢琴等音色完全无声）→ 立体声 L/R 对按 start/end 配对混合为单声道、sampleType 置 1、重建 smpl/shdr 与 igen 索引；转换后 72/72 全部单声道（stereoOnly=0），备份于 tools/sf2-backup-20260813（已加入 .gitignore）。
    - 音源加载 await 化：loadSoundFontAwait 以 soundFontLoaded 事件确认完成（顺序加载、20s 超时、失败给出 soundError 提示）；就绪前播放按钮禁用并显示「音源加载中…」，首次点击排队待就绪后自动起播。
    - 播放中修改谱面（变调夹/字体/数字谱/乐器）走 withRenderPreservingPosition：记录 tickPosition → pause → 应用/重渲染 → 恢复位置 → 续播，不再重置进度。
    - 变速只改 api.playbackSpeed = v/baseTempo，移除对 tempo 自动化的修改（避免双重生效）。
    - 新增 api.error 兜底日志；畸形和弦（firstFret/strings 为 null）导致 Chord.uniqueId 抛错中断渲染 → 在 playerSettings 用 notation.elements.set(ChordDiagrams/EffectChordNames, false) 关闭和弦图（注意：elements 是 Map，方括号赋值无效，必须 .set()），并符合原站「关闭和弦展示」配置。
  - 新增纯函数工具 src/lib/playbackSpeed.mjs（clampTick/computePlaybackSpeed/formatTime）供组件与单测共用。
- 验证方式与结果（证据）：
  - Playwright 专项 tools/verify-player-fix.mjs 9/9 通过：T1 光标可见+signal 蓝样式、T2 播放推进且光标移动/小节拍号/时间、T3 跟随滚动（seek 80% 后 scrollTop 959/2055）、T4 进度条 seek 生效并续播、T5 播放中改 capo 不重置位置（tick 1181→2571 且按钮=暂停）、T6 变速只改 playbackSpeed（tempo 69 不变，playbackSpeed=1.739）、T7 循环区间高亮（playbackRange 0..20160、banner=循环中、进度条高亮 div 存在）、T8 四首不同谱面播放无 unsupported sample 警告且零 console 报错（含此前崩溃的 1yOhtb1c9I0）、T9 全量 72 个 sf2 加载零 unsupported 警告；截图 tests/evidence/player-fix/。
  - 单测：node --test 25/25（含新增 tests/player-math.test.mjs 3/3、tests/sf2-convert.test.mjs 3/3、smoke-test）；npx astro build 通过；回归 tools/verify-m7-final.mjs 41/41。
  - 已确认的调试结论：循环高亮此前「count=0」是验收脚本按无空格字符串匹配、而 Svelte 渲染样式带空格（rgba(65, 161, 207, ...)）导致误报，非功能缺失。
- 遇到的问题与决策：
  - apply_patch 对部分文件偶发 abort → 改用直接传字符串字面量可稳定应用；DEV_LOG 行尾 CRLF/LF 混用导致上下文匹配失败 → 用 Node 脚本按无 BOM UTF-8 追加。
  - sf2 子代理（/root/sf2_convert）子任务误交付 DEVELOPMENT_DOC.md（与本次无关）→ 保留为未跟踪文件，不纳入本次提交；转换本身由 sf2_convert 完成并复核通过。
  - 多进程并发写 verify 脚本造成版本混乱 → 以磁盘最终版为准统一为 9 项验收，删除调试探针临时文件（_probe-*/_grep-*）。
- 下一步：走分支合并流程——提交 fix/player-cursor-follow → --no-ff 合入 master → 主分支回归（node --test + astro build + verify-m7-final + 冒烟）；随后按用户需求决定是否恢复 M7.1 数据爬取与 PLAYER_FIX_PLAN 中后续项。


- 收尾（master 2e1229f）：fix 分支 59069f5 已 --no-ff 合入 master；主分支回归 node --test 25/25、npx astro build 通过、tools/verify-player-fix.mjs 9/9、tools/verify-m7-final.mjs 41/41。切分支后清 .astro 与 node_modules/.vite 缓存并重启 dev server，规避陈旧模块缓存导致的验收脚本挂起。

### 2026-08-13 —— 播放器对齐：变调夹/降半调调弦 + 整曲转调 + 音符高亮 + 数字谱 + 显示细节 ✅（分支 fix/player-transpose-highlight-numbered）
- 本次目标：实现用户反馈的四项播放器功能并对齐参考站行为——(1) 变调夹改为参考站下拉（含降半调调弦）；(2) 新增整曲转调 ±12（参考站无此控件，标注「有意差异」）；(3) 播放音符高亮（signal 蓝）+ 光标对齐参考站红色；(4) 数字谱真实开关；并修复谱面显示细节。
- 完成内容：
  - 调研结论（实测参考站 DOM/JS，非臆测）：
    - 参考站「数字谱」= 切换 fork 属性 avoidInChordFretNumber：OFF=236 文本（单行简谱+节奏，bar 组无品数文本）、ON=561 文本（每根弦品数 1,2,0,3...）；官方 1.8.4 无该属性 → 用「CSS 显隐和弦品数字 + MutationObserver 标记」等价复刻。
    - 参考站变调夹下拉 = 降半调调弦(-1)/不夹(0)/1~6品，来自 globalConst 数组；实测选 3品/降半调后谱面品数完全不变（2,0,3,0,3,0 原样），只改变发声音高 → 正确语义是 staff.capo（只影响音高、不改显示），而非 staff.transpositionPitch（会改显示品数，且降半调时 0 品变负数导致数字消失）。
    - 参考站播放指示：无逐音符高亮，光标为红色竖线 rgb(210,109,109)、3px，小节块极淡；逐音符高亮为本项目增强（用户要求），用 signal 蓝 #41a1cf。
    - 参考站显示资源：titleFont 24px Arial、subTitleFont 16px、wordsFont 14px、effectFont italic 12px Georgia、barNumberColor rgba(0,0,0,.5)（本地默认红 #C80000，已改）、barSeparatorColor rgba(44,44,44,1)；关闭 ScoreWords/Music/GuitarTuning/TrackNames/EffectCapo/EffectTempo/ScoreAlbum 等冗余信息。
  - 实现（src/lib/pitch.mjs 新增纯函数 + ScorePlayer.svelte + playerSettings.ts + global.css）：
    - 变调夹：按钮+下拉（8 项与参考站一致，role=listbox/option、键盘可达），选中即写入 st.capo=所选值（含降半调=-1），只改变发声音高、谱面显示不变；播放中切换经 withRenderPreservingPosition 保留位置。
    - 整曲转调：新增 −/数值/+ 控件（±12 取整 clamp），写入 st.transpositionPitch=-transpose（显示+播放整体移调），与变调夹独立叠加。
    - 音符高亮：.at-highlight 命中 SVG <g>，补 fill/stroke=#41a1cf（SVG 不认 background）；光标改参考站红 .at-cursor-beat rgb(210,109,109)/3px、.at-cursor-bar 极淡；暂停保留高亮、停止/结束清除。
    - 数字谱：容器 class at-number-tab 控制 .at-chord-note（同一 x 拍内的和弦品数）显隐，ON=592 全部显示、OFF=0；不重渲染、不打断播放。
    - 稳定性：新增 enqueueRender 串行化 renderScore（AlphaTab 并发重渲染会崩溃，快速连点变调夹/转调/字体/乐器时排队执行）。
- 验证方式与结果（证据）：
  - 新增 tools/verify-player-display.mjs 10/10：A1 数字谱默认隐藏 0/592、A2 开启 592/592、A3 变调夹 8 项与参考站一致、A4 3品显示不变且 st.capo=3、A5 降半调显示不变且 st.capo=-1、A6 转调+2 品数+2 且 transpositionPitch=-2 且 UI=+2、B1 播放高亮 fill/stroke=rgb(65,161,207)+光标红 rgb(210,109,109)+tick 推进、B2 播放中 2品不重置（tick 3039→4526 仍 Playing）、B3 播放中+1 转调不重置（tick 4535→5975）、B4 停止后高亮清除；截图 tests/evidence/display/。
  - 参考站对照实测：ref-halfdown.png/ref-capo3.png 证明选降半调/3品后品数 2,0,3,0,3,0 不变（capo 按钮文本正确更新为「降半调调弦/3品」）。
  - 回归：tools/verify-player-fix.mjs 9/9（T1 改为断言参考站红样式、T5 改为点开下拉选 3品且 st.capo=3；补 browser.close 汇总避免进程挂起）；node --test 30/30（含新增 pitch.test.mjs 5/5）；npx astro build 通过；tools/verify-m7-final.mjs 41/41。
- 遇到的问题与决策：
  - 初版把变调夹/降半调做成 staff.transpositionPitch=-shift（品数 +3），实测与参考站「显示不变」不符且降半调产生负品数（0→null）→ 改回 staff.capo=所选值，转调单独走 staff.transpositionPitch；语义已用参考站实时抓取证据锁定。
  - 官方 1.8.4 无 avoidInChordFretNumber/slim/useTieSlim 等 fork 属性 → 数字谱用 CSS 等价复刻，显示资源用能生效的 alignRenderingResources 对齐（Font 对象直接改 size/families、Color 用 raw 位运算 + updateRgba()）。
  - verify-player-fix.mjs 此前无 browser.close 导致进程挂起超时 → 补汇总与 close。
- 下一步：清理临时探针工具与超大参考 bundle（保留参考截图证据）→ 提交 fix/player-transpose-highlight-numbered → --no-ff 合入 master → 主分支回归（node --test + astro build + verify-player-display + verify-player-fix + verify-m7-final + 冒烟）。


### 2026-08-13 —— 谱面显示补齐：歌词 / 和弦图 / 调性 / 旋律对齐 ✅（分支 feat/score-details-lyrics-chords-key）
- 本次目标：实现用户反馈的四项谱面显示能力并复刻参考站行为——(1) 旋律简谱（单音品数）与歌词显示；(2) 伴奏和弦（和弦名 + 和弦图/指法图增强）；(3) 调性（key）显示（头部 key 行 + 转调提示）；(4) 旋律与伴奏对齐、谱面显示细节。
- 调研结论（实测参考站 DOM，非臆测）：
  - 参考站渲染双轨：track 0「伴奏」吉他六线谱 + track 1「旋律」数字谱，两轨 showTab=true；旋律轨含 334 拍歌词。
  - 参考站 staveProfile=3（Nier 定制 Tab）、ChordDiagrams=true、EffectChordNames=false；每 system 垂直布局：和弦名 y≈6 → 小节号 y≈50 → 六线谱 y≈83-101 → 旋律数字行 y≈152.9 → 歌词 y≈174.7；头部 SVG 内 key = G 4/4（y≈55.6）与 ♩= 69（y≈69.04）。
  - 参考站有 lazy loading（24 个 placeholder，仅可见区渲染 SVG，滚动时动态渲染/卸载）。
  - 本地根因：歌词在 track 1（旋律轨），旧实现只渲染 track 0（吉他轨）→ 歌词完全不显示；StaveProfile.Tab 只含 TabBarRenderer，旋律轨 tuning 为空导致 Tab 工厂 canCreate 失败；JsonConverter 把 masterbars[0].keysignature 从 1 变成 0。
- 完成内容：
  - src/lib/ibe.ts：新增 normalizeLyrics()（beat.lyrics 保持字符串数组，1.8.4 LyricsGlyph 用 fillText(line)，对象数组会渲染失败）、sanitizeChords()（丢弃 firstfret 非正整数或 strings 非有效数组的畸形和弦并清空 beat.chordid 引用，避免 Chord.uniqueId 崩溃）、extractScoreMeta()（读 keysignature/keysignaturetype/拍号）；fixScoreContent 归一化后执行歌词映射与和弦清洗。
  - src/lib/keyName.mjs（新增）：MAJOR_KEYS / relativeMinor / keySignatureName(sig, type)，含单测。
  - src/lib/playerSettings.ts：ChordDiagrams=true、EffectChordNames=false、EffectLyrics=true；staveProfile 由 Tab 改为 Default（本地官方包 Tab profile 缺 Numbered/Score 工厂）。
  - src/components/player/ScorePlayer.svelte：双轨渲染（有 tuning→Tab、无 tuning→Numbered）；新增「和弦图」开关按钮；key 头部行（key = G 4/4 ♩= 69）；转调提示（原调 → 新调）；markChordNotes() 给和弦顶部旋律音加 at-chord-note-top class（数字谱 OFF 时保留顶部单音）；播放中切换走 withRenderPreservingPosition。
  - src/styles/global.css：数字谱 OFF 时隐藏 .at-chord-note 但保留 .at-chord-note-top。
  - /tabs/[id].astro 与 /ukulele/[id].astro：传 scoreKey / timeSig。
- 验证方式与结果（证据）：
  - 新增 tools/verify-score-details.mjs 7/7：S1 歌词渲染（22 字含「故事的小黄花」）、S2 滚动到底懒加载歌词（94 字）、S3 和弦名 13 + 和弦图 195 rect、S4 头部 key=G 4/4 ♩=69 + 转调提示、S5 数字谱 OFF 59/163 可见（含 31 个和弦顶部旋律音）ON 163/163、S6 移动端 390 无溢出、S7 ukulele 歌词 87 字；截图 tests/evidence/score-details/。
  - 单测：node --test 38/38（含新增 tests/lyrics-chords-key.test.mjs 8/8）。
  - 回归：npx astro build 通过；tools/verify-player-display.mjs 10/10；tools/verify-player-fix.mjs 9/9；tools/verify-m7-final.mjs 41/41。
- 遇到的问题与决策：
  - 本地 1.8.4 官方包 StaveProfile.Tab 不含 Numbered/Score 工厂（参考站是 Nier 定制版）→ 不能直接照抄 staveProfile=3，改用 Default profile + staff 级标志实现等效效果（有 tuning→Tab、无 tuning→Numbered）。
  - JsonConverter 把 keysignature 变 0 → 数据层读原始 JSON extractScoreMeta。
  - 对象数组歌词在 1.8.4 渲染失败 → 保持字符串数组。
  - lazy loading 下歌词总数非全量（离屏 system 被卸载）→ 验收用「初始可见区 + 滚动到底」双断言，不断言全量数字。
  - 畸形和弦一律数据层清洗丢弃，绝不带病渲染。
- 下一步：清理临时探针 → 提交 feat/score-details-lyrics-chords-key → --no-ff 合入 master → 主分支回归（node --test + astro build + 三项 verify + 冒烟）。

- 收尾（master）：feat/score-details-lyrics-chords-key（提交 a398c8b）已 --no-ff 合入 master；主分支回归 node --test 38/38（含 smoke 页 200）、npx astro build 通过。DEVELOPMENT_DOC.md（规划草稿）按先前决策保留未跟踪，未纳入提交。


### 2026-08-13 —— M7.1 数据扩充（恢复爬取，进行中）
- 用户指示「继续恢复爬取」→ 重新枚举候选清单并恢复后台爬虫。
- 前置调研（实测，非臆测）：
  - 原候选清单 tools/migrate-candidates.json 因误删只剩 4000 条；断点 tools/migrate-state-m7.json 完好（done=2593，failed=4）。
  - 参考站列表分页：每个列表视图上限 40 页 × 50 条 = 2000 条；/tabs 与 /ukulele 的 sort=0(最新)/sort=1(最热) 与难度 1-5 视图为不同 ID 集合，需多视图合并才够量。
  - 主列表结构 <ul class="w-full"><li><a href="/tabs|ukulele/{ID}">，据此精确提取主列表 ID（排除侧栏推荐）。
- 完成内容：
  - 新增 tools/enum-candidates.mjs：遍历 tabs/ukulele × (sort0/sort1) + tabs × 难度1-5 共 9 个视图，断页自动停止，限流退避，与旧候选合并去重；两列表都出现的 ID 标 unknown（让迁移尝试两个路径）。
  - tools/migrate.mjs：loadCandidates 保留 unknown hint（fetchSheetAt 已支持 tabs/ukulele 双路径回退）。
  - 重新枚举结果：候选 14675（guitar=8675 ukulele=4000 unknown=2000）；与 DB 比对：已入库 3674、待迁移 11001、DB 当前 5267。
  - 后台启动（PID 47876，日志 tools/migrate-m7b.out.log，窗口隐藏，断点续爬）：
    node tools/migrate.mjs --ids tools/migrate-candidates.json --pace 1100 --state tools/migrate-state-m7.json
  - 启动后已确认稳定：ok 从 2593 连续增长（至 2635+），无新增失败（fail 保持 4）。
- 验证方式与结果：
  - 候选枚举 14675 已写盘；migrate 启动日志正确显示「候选 14675，已在库 5267，已完成 2593」。
  - 抽样日志显示新增热门曲目入库正常（我记得-赵雷、海阔天空-beyond、Perfect - Ed Sheeran 等，热度 7 万+）。
- 遇到的问题与决策：
  - 原候选仅 4000 条不足 10000 目标 → 多视图合并枚举扩展到 14675。
  - 枚举视图 kind 曾误写为 tabs（非 guitar）→ 生成后归一化为 guitar，migrate 侧亦兼容。
  - 全部爬完预计约 10 小时（pace 1100 + .ibe 下载），完成后 DB 预计 1.6 万+，远超 ≥10000 目标。
- 下一步：等爬虫完成（期间可继续其他工作）→ tools/accept-data.mjs 数据验收（>10000 首、首页矩阵/搜索计数真实、抽样渲染比对）→ 更新 PLAN.md/DEV_LOG.md 并归档证据。


### 2026-08-14 —— M7.1 数据扩充（用户指示停止，收尾记录）
- 用户指示「差不多了不要爬取了」→ 安全停止爬虫（PID 47876）。停止时点：候选 9545/14675（65%）。
- 停时最终数据（PostgreSQL 实测）：
  - DB 共 11955 首（吉他 7934 / 尤克里里 4021）；带 .ibe 可播放 8129，XHE 网页文本谱 3826。
  - 累计成功 9263（含首轮 2593）、失败 27、跳过 2935；成功率 99.7%，远超 ≥10000 目标。
- 数据验收（快速核验，页面实测）：
  - 首页/吉他列表/尤克里里列表/搜索/新曲详情/经典曲详情全部 HTTP 200、无错误标记，响应 21-168ms。
  - 搜索新入库「Canon Rock」命中；新曲详情 /tabs/1ed4dcd505e5 正常渲染。
  - 注：计划中提及的 tools/accept-data.mjs 实际未创建，故验收以上述快速核验 + 既有 verify 套件回归代替。
- 遇到的问题与决策：
  - 数据量已达目标上限的约 1.2 倍，接受提前停止；不删除任何数据与断点文件。
  - 断点保留：tools/migrate-state-m7.json（done=9263/fail=27）与 tools/migrate-candidates.json（14675 条），随时可恢复续爬剩余约 5000 候选（id 去重幂等）。
- 下一步：PLAN.md 更新 M7.1 状态为完成；如后续需要可恢复续爬或另立数据扩充任务。
### 2026-08-14 ｜ 和弦名位置修复：按 system 对齐参考站（分支 fix/chord-positions）
- 本次目标：修复用户反馈「和弦位置不正确，都统一放到了上方」。
- 完成内容：
- 根因定位：playerSettings.ts 中 ChordDiagrams=true + EffectChordNames=false，AlphaTab 1.8.4 会启用 ChordDiagramContainerGlyph 把所有谱面唯一和弦集中渲染到第一个 system 上方——正是「统一放上方」的原因。数据层完整（晴天 15 个和弦、93 拍 chordid 引用全部有效），纯渲染配置问题。
- 修复：ChordDiagrams → false、EffectChordNames → true；和弦名按拍/按 system 分布，第一行序列与参考站完全一致（Em7,Cadd9,G6,Em7,Cadd9,G6,Em,Em7,Cmaj7,Cadd9）。
- ScorePlayer.svelte 移除「和弦图」切换按钮（参考站不渲染和弦图网格，只显示文字名），清理未使用 NotationElement 导入。
- verify-score-details.mjs：S3 断言改为「按 system 分布 + 第一行序列对齐」；S5 数字谱断言改为全 #score-scroll 容器统计（旧 surface.children[4] 选择器随布局偏移失效）。
- verify-m7-final.mjs：截图页 waitUntil networkidle → load（Astro Dev Toolbar 性能审计会 fetch 页面全部截图，数据量 11955 后每页 90 图，networkidle 永不达成；生产构建无此行为，属开发模式测试适配）。
- 验证方式与结果（证据）：
- verify-score-details 7/7、verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build 通过。
- master 合并后主分支回归：node --test 38/38、verify-m7-final 41/41。
- 证据截图 tests/evidence/score-details/、tests/evidence/player-fix/、tests/evidence/player-display/、tests/evidence/m7/。
- 遇到的问题与决策：
- S3 补丁正则含裸 / 导致语法错误 → 改为 [/] 字符类修复。
- /tabs?difficulty=2 的 networkidle 超时 → CDP initiator 定位为 Astro Dev Toolbar audit perf 规则（fetch 全部截图），非产品缺陷；脚本改 waitUntil:load。
- 清理 25 个 _probe-* / _patch / _s3-block 临时探针文件；DEVELOPMENT_DOC.md 按惯例保持未跟踪。
- 下一步：无（本次修复已验收合并）。其余谱面显示差异按需另立任务。
### 2026-08-14 ｜ 和弦指法图完全显示：自绘覆盖层（分支 fix/chord-diagrams-overlay）
- 本次目标：用户反馈「和弦需要完全显示，不只是 Em7/Cadd9 文字名」——在每处和弦位置显示完整指法图。
- 完成内容：
- A/B 实测定位：alphaTab 1.8.4 的 globalDisplayChordDiagramsInScore=true 会丢弃歌词渲染（SVG 内歌词节点不存在），与 ChordDiagrams 元素无关——「谱内逐拍和弦图 + 歌词」在该版本无法共存（版本级限制）。
- 方案：自绘指法图覆盖层。保持 alphaTab 原配置（歌词 + 逐 system 和弦名正常），渲染完成后按 DOM 中和弦名文本匹配模型和弦，把迷你指法图（6 弦 × 4 品、按点/空弦○/闷音×、首品标记）插入对应位置上方（class .at-custom-chord-diagram）。
- 播放器新增「和弦图」开关（默认开、btn-signal 高亮），切换即时增删覆盖层、不重渲染、不打断播放。
- 覆盖层挂在 MutationObserver（复用现有 renderFinished 监听）与 ensureChordMarker 初始化，转调/变调夹/字体缩放等重渲染后自动重建。
- 验证方式与结果（证据）：
- verify-score-details 8/8（新增 S8：28 图 + 76 按点 + 歌词 22 共存、OFF→0、ON 恢复、零报错）；S1 歌词 22 / S2 97、S3 和弦名行序列对齐参考站全部保持。
- verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build 通过。
- 几何检查：指法图与下行谱表线最小间距 27px 无重叠；变调夹重渲染后 28→28 自动重建。
- master 合并后回归：node --test 38/38、verify-score-details 8/8、verify-m7-final 41/41。
- 证据 tests/evidence/score-details/chord-diagrams-custom.png、s8-chord-diagrams.png。
- 遇到的问题与决策：
- 直接启用 alphaTab 谱内和弦图会破坏歌词（实测 cjk 22→2）→ 放弃原生机制，改自绘覆盖层（用户优先要「完全显示」且歌词不能丢）。
- playerSettings 最终保持 ChordDiagrams=false（避免顶部列表容器与歌词冲突），覆盖层不依赖 alphaTab 和弦图机制。
- 打印/PDF 走独立 printScore 渲染，暂不含自绘指法图（已知差异，如需可后续接入）。
- 下一步：无（已验收合并）。若需打印/PDF 也显示指法图或针对特定谱面做尺寸适配，可另立任务。
### 2026-08-14 ｜ 和弦图表条：不压谱、完整显示（分支 fix/chord-chart-strip）
- 本次目标：修复用户反馈「和弦图挡住谱子、且显示不完全」；对照参考站布局确认参考站只显示和弦名（无谱内指法图），用户要求完整指法图 → 采用谱面上方专用和弦图表条（增强项）。
- 完成内容：
- 根因复盘（弃用 M8.2 自绘覆盖层）：覆盖层挂在每处和弦名上方，而和弦名行即 system 顶部，指法图向上偏移 46px 后超出 SVG 顶部 50px 边界 → 被裁剪、残留部分压住上一行元素（几何越界）。参考站无谱内指法图，故改为在 #score-scroll 滚动容器外、谱面上方渲染和弦图表条（15 张卡片：56×46 指法图 + 和弦名，flex-wrap 自适应），天然不压谱、完整显示。
- 核心渲染修复：图表条位于滚动容器上方会改变可视视口，AlphaTab 1.8.4 默认 enableLazyLoading=true 依赖视口判定补齐离屏 partial → 图表条可见时谱面渲染不完整（86 bar/3 SVG/歌词 2）。在 playerSettings.ts 设 s.core.enableLazyLoading=false 强制一次性完整渲染（984 bar/23 SVG/歌词 319）。
- 数字谱标记修复：enableLazyLoading=false 后所有 SVG 在 renderFinished 前一次性注入 DOM，MutationObserver 捕获不到新增节点 → markChordNotes() 从未执行、数字谱开关失效。修复：renderFinished 时直接调用 markChordNotes()（observer 保留兜底重渲染）。
- 开关：播放器「和弦图」按钮仅切图表条 hidden，不重渲染、不打断播放；转调/变调夹重渲染后 setTimeout 重建图表条（15 卡）。
- 几何验证（Playwright）：桌面 1440 与移动 390 均 15 卡、SVG 56×46 无裁剪、无横向溢出、chart 底 = 谱面顶（无重叠）；toggle OFF/ON 谱面保持完整（23 SVG/319 歌词）。
- 验证方式与结果（证据）：
- verify-score-details 8/8（S8 重写为图表条语义：15 卡/容器外/无重叠/谱面完整/开关生效；S5 数字谱 OFF visible 1007<total 2623、ON 全显）。
- verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build 通过。
- 证据 tests/evidence/score-details/chart-strip-vp1440.png、chart-strip-vp390.png、s8-chord-chart-strip.png。
- 遇到的问题与决策：
- 原生谱内和弦图（ChordDiagrams/globalDisplayChordDiagramsInScore）在此版本会丢歌词（M8.2 已 A/B 实测）→ 不启用；图表条方案与歌词/逐 system 和弦名共存。
- 打印/PDF 走独立 printScore 渲染，暂不含图表条（已知差异，如需要可后续接入）。
- 下一步：无（已验收合并）。若需打印/PDF 显示指法图或针对特定谱面尺寸适配图表条，可另立任务。
### 2026-08-14 ｜ 和弦显示模式切换：仅字母 / 字母+完整指法图逐位内联（分支 feat/chord-inline-mode）
- 本次目标：用户改需求——「和弦图应该固定到对应的乐谱位置，不是只放一条在最上方；几种模式可切换：仅字母 / 字母+完整指法图+字母标识」。
- 完成内容：
- 根因/机制调研：alphaTab 1.8.4 的 EffectChordNames 带在 globalDisplayChordDiagramsInScore=true 时创建 ChordDiagramGlyph（逐拍内联：字母+完整指法图），false 时创建纯文字 TextGlyph；顶部容器由 ChordDiagrams 元素 + globalDisplayChordDiagramsOnTop 控制（本项目已关）。实测开启 inScore 标志后歌词完整保留（319 条，与 M8.2 的「原生谱内和弦图丢歌词」结论不同——当时组合含顶部容器，本次只开 inScore 且 ChordDiagrams=false）。
- 实现：移除 M8.3 顶部和弦图表条（#chord-chart / buildChordChart / chordDiagramSvg）；新增 chordMode 状态（默认 'diagram'=字母+指法图），控制条改「仅字母 / 字母+指法图」分段切换；切换时 score.stylesheet.globalDisplayChordDiagramsInScore 置位 + withRenderPreservingPosition 重渲染（保留播放位置）；初始渲染前同样置位。
- 渲染效果（晴天）：93 个和弦名散布 21 行（逐位正确），指法图随名内联（rects 4463 vs 仅字母 3254），谱高 5543 vs 4001；无重叠、无越界（原生布局保留空间）；移动端无横向溢出（55 SVG 重排）。
- 验证方式与结果（证据）：
- verify-score-details 8/8（S8 重写为模式切换语义：默认 diagram 逐拍内联+歌词共存+全谱渲染；切仅字母 rects/谱高下降且歌词/字母数不变；切回完全恢复；无图表条、零报错）。
- verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build 通过。
- 证据 tests/evidence/score-details/mode-diagram.png、mode-name.png、mode-vp1440.png、mode-vp390.png、s8-chord-mode-toggle.png。
- 遇到的问题与决策：
- M8.2 自绘覆盖层几何越界压谱、M8.3 顶部图表条不满足「固定到对应谱面位置」→ 原生逐拍机制是唯一同时满足「逐位+完整指法图+歌词共存」的路径，且布局引擎自动避让无重叠。
- 默认模式选 'diagram'（用户核心诉求为完整显示），可一键切回 '仅字母' 对齐参考站。
- 打印/PDF 走独立 printScore 渲染，暂不含逐位指法图（已知差异，如需要可后续接入）。
- 下一步：无（已验收合并）。如需打印/PDF 也显示指法图或对指法图做 refero 风格化（当前为标准音乐字体），可另立任务。
### 2026-08-14 ｜ 谱面字体统一 Cascadia Code + 文字重叠修复（分支 feat/score-font-cascadia）
- 本次目标：用户反馈谱面字体不好看 → 全部换成电脑里的 Cascadia Code；谱面各处文字与谱面有重叠 → 详细优化。
- 完成内容：
- 字体（全谱面统一 Cascadia Code 正体，CJK 回退微软雅黑）：
  - 复制 C:/Windows/Fonts/CascadiaCode.ttf → public/font/CascadiaCode.ttf（387,948B）；src/styles/global.css 注册 @font-face（font-weight 100 900；AlphaTab 会经 document.fonts 等待加载后再渲染）。
  - src/lib/playerSettings.ts 新增 SCORE_FONT；标题 22/副标题 15/艺人 15/歌词 13/和弦名 11/品数 13/数字谱 12/小节号与指法图数字等全部换 Cascadia Code。
  - 根因：RenderingResources 构造时 elementFonts 用 withSize() 复制默认字体副本，res.effectFont（共享静态实例）的修改不会传导到副本 → 必须逐项改 elementFonts map 条目（含 ScoreArtist/ScoreCopyright/EffectChordNames/EffectLyrics 等）。
- 重叠修复：
  - 头部标题裁剪：标题用 dominant-baseline:hanging，字形越 y=0 被 SVG 默认 overflow:hidden 裁剪 → #score-scroll svg { overflow: visible } + display.padding 顶部 36。
  - Tab 品数堆叠：14px 字体 vs 10.9px 弦距 → 盒重叠 -3px；engravingSettings.tabLineSpacing 13.5→17（实测弦距 14.3px）+ 品数 13px → 堆叠间隙 +1px。
  - 段落标记（主歌/副歌）与首拍和弦名：官方 1.8.4 同槽固定 y（marker 10/和弦 15.5，字号与 padding 均无法分离；参考站用魔改 alphatab-ins.min-fix.js 规避）→ 隐藏 EffectMarker，保证无文字重叠（已知取舍，可后续自绘覆盖层恢复）。
  - 数字谱旋律数字 12px；系统间距：firstSystemPaddingTop 10 / systemPaddingTop 8 / systemPaddingBottom 14 / lastSystemPaddingBottom 8 / notationStaffPaddingBottom 6 / effectBandPaddingBottom 6。
- 验证方式与结果（证据）：
  - 4 谱面（晴天/知足/小幸运/ukulele）× 桌面+移动：谱面全部文字 font-family=Cascadia Code；控制台/页面错误零；正文文字-文字重叠 0（数字谱节奏数字 5×3px 微重叠为 AlphaTab 固有，参考站 42 处、本地 9 处，本地更优）。
  - 回归：verify-score-details 8/8、verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build 通过（dist/client/font/CascadiaCode.ttf 已打包）。
  - 证据 tests/evidence/font/final/qingtian-desktop.png、qingtian-mobile.png、zhizu-desktop.png。
- 遇到的问题与决策：
  - effectFont 系文字改字体必须改 elementFonts map 条目（源码确认 withSize 复制）；已加注释说明。
  - 段落标记无法用官方 1.8.4 配置与和弦名分离（marker/chord y 固定，effectBandPaddingBottom 对同槽无效）→ 隐藏标记；参考站为魔改版，恢复标记需自绘覆盖层或魔改源码（另立任务）。
  - 用户明确要 Cascadia Code（参考站实际用 Georgia 和弦名/Arial 品数），属于有意差异。
- 下一步：提交合并 master 并跑主分支冒烟。可选：恢复段落标记（自绘覆盖层）、数字谱节奏数字进一步优化。

### 2026-08-14 ｜ 播放器音频生效：转调/变调夹/乐器切换 → 显式重生成播放 MIDI（分支 fix/player-audio-midi）
- 本次目标：用户确认「转调是否真的改变音色、和弦声音是否正确」——修复同一 score 对象重渲染后播放 MIDI 不重生成的根因，确保变调夹/降半调/整曲转调/乐器切换后实际播放音高与谱面一致。
- 完成内容：
  - 根因（代码+浏览器实测确认）：AlphaTab 1.8.4 的 renderScore 对同一 score 对象重渲染时 _internalRenderTracks 仅在新对象分支触发 MIDI 生成，音频类变更（变调夹/降半调/整曲转调/乐器切换）后播放 MIDI 仍是旧调 → 音频不生效。
  - 方案 A（主选，已采用）：新增 waitForPlaybackReady()（监听 api._player.readyForPlayback + isReadyForPlayback 即时判断 + 8s 超时兜底）；withRenderPreservingPosition 扩展 opts.reloadMidi —— 流程改为 记录位置 → 暂停 → 应用/重渲染 → 显式 api.loadMidiForScore() → 等就绪 → 恢复位置 → 续播。
  - 接入点：selectCapo / changeTranspose（applyTransposition）与 changeInstrument（乐器切换）传 { reloadMidi: true }；纯显示类（字体缩放/和弦模式/数字谱）不触发重生成。
  - 探测确认的机制：loadMidiForScore 内部 generator.applyTranspositionPitches=false（MIDI 文件保持原调）；capo 直接进入 MIDI noteKey（3品=每音 +3、降半调=每音 -1）；整曲转调经 generator.transpositionPitches → player.applyTranspositionPitches(map) 在合成器 worker 侧实时移调（+1→{0..3}:1，归零→{0..3}:0）。
- 验证方式与结果（证据）：
  - 新增 tools/verify-player-audio.mjs 12/12 PASS：基线 MIDI 捕获、变调夹 3品 noteKey 精确 +3、降半调 -1、整曲转调 +1/+2 移调表、归零、和弦音程保持（转调 +2 各音符平移一致）、纯显示操作不误刷新 MIDI、播放中切变调夹/转调位置保留且续播、乐器切换 program 生效且进入重生成 MIDI、全程 console/pageerror 零报错。
  - 回归：verify-score-details 8/8、verify-player-display 10/10、verify-player-fix 9/9、verify-m7-final 41/41、node --test 38/38、npx astro build 通过。
  - 证据 tests/evidence/audio/audio-final.png。
- 遇到的问题与决策：
  - 备选方案 B（api.changeTrackTranspositionPitch 实时移调）不打断播放，但需显示/音频双数据源严格同步、易双重移调，作为 A 失败时的回退（已对比，未启用）。
  - 音轨显隐目前隐藏轨道仍会发声（参考站行为待确认），本档不处理，另立任务。
  - 验收脚本初版 A6/A9/A10/A11 为脚本自身 bug（applied 读取时机、isPlaying 属性不存在、乐器面板未展开、等待超时不足），已修复后 12/12。
- 下一步：提交合并 master 并跑主分支冒烟。

### 2026-08-14 ｜ 谱面间距修复：和弦名/指法图/数字谱/歌词离谱表太近（分支 fix/score-chord-spacing）
- 本次目标：用户反馈「F（和弦名 G/F、D/F# 里的 F）和文字离谱表太近、太挤」。因当前会话模型无法直接读取图片，改用用户提供的本地 OpenAI 兼容视觉 API（http://127.0.0.1:3000/v1，模型 gpt-5）分析用户截图定位问题。
- 完成内容：
  - 视觉模型定位：用户截图为《花海》（key A，Capo 2）。问题区域有两处——①谱表下方数字谱/力度记号/歌词间距太紧；②和弦名 G/F、D/F# 与指法图、下方谱表叠得太近。
  - 根因：本地谱表最后一行数字(y=197)到歌词(y=229)仅约 32px，而参考站同曲谱表到数字谱约 70px（宽松得多）；主要受 notationStaffPaddingBottom（谱表底部留白）过小影响。
  - 修复（src/lib/playerSettings.ts）：notationStaffPaddingBottom 10→30（谱表下方留白）、effectBandPaddingBottom 20→22、firstSystemPaddingTop 10→18、systemPaddingTop 8→16、systemPaddingBottom 14→18、lastSystemPaddingBottom 8→12（给和弦名/指法图上下留出呼吸空间）。
- 验证方式与结果（证据）：
  - 花海实测：谱表(y=191)到歌词(y=247)间距 32px→56px。
  - 视觉 API 复检当前渲染：G/F、D/F# 和弦名与指法图间距 8-12px、指法图与下方谱表 25-30px、谱表与歌词 35-45px；整体评分 8.5-9/10，判定「comfortable and production-ready」，建议不再增加纵向间距。
  - 回归：verify-score-details 8/8、verify-player-display 10/10、verify-player-fix 9/9、node --test 38/38。
- 遇到的问题与决策：
  - 当前模型不支持图片输入，view_image 返回空；改用本地视觉 API（用户提供）分析截图，中文提示词经代理乱码改英文提示词。
  - 参考站无指法图（仅和弦名），本地因用户要求显示指法图导致系统更高；间距以「视觉舒适」为准而非逐像素对齐参考站。
- 下一步：提交合并 master 并跑主分支冒烟。
### 2026-08-14 ｜ 全音符休止符修复：JSON 层替换 + 谱面模式切换重建（分支 fix/whole-rest-numbered-renderer）
- 本次目标：M8.7 遗留的「次级音轨含全音符休止符（duration=1）时，简谱（numbered）渲染触发 AlphaTab 1.8.4 崩溃（NumberedBarRenderer.calculateBeamingOverflows → beatOfHighestNote 读 null）」问题，让全部多六线谱曲目都能安全使用混合模式；简谱空小节对齐参考站显示 0 0 0 0。
- 完成内容：
  - 根因确认（代码 + 浏览器实测）：
    - 归一化 JSON 中全音符休止符为 { duration: 1, notes: [] }，无 isrest 键（此前 b.isRest 判定永不命中）；
    - 简谱渲染器对整小节休止的 beam helper（beats.length===1 且 duration=1 不满足 duration>=Half 分支）读取 beatOfHighestNote（null）崩溃；四分休止（duration=4>=2）走安全分支；Tab 渲染器对全音符休止天然安全（Hotel California 单轨实测零报错）；
    - 头部 1500 首审计：113 首含全音符休止，其中 74 首在首调弦轨（Tab 安全）、47 首在次级调弦轨（混合模式简谱会崩溃）。
  - src/lib/scoreDisplayMode.mjs：重写 replaceWholeRestsInSecondaryTracks —— 在 model.JsonConverter.jsonToScore 之前，把非首调弦音轨的全音符休止替换为 4 个四分休止克隆（text/automations 仅保留在首个克隆，删除重复 id，返回替换数）；JsonConverter 会经 Beat.updateDurations/Voice.finish 重算 duration/displayStart/playbackStart，故仅 duration 关键。
  - src/components/player/ScorePlayer.svelte：
    - 新增 scoreJsonRaw（解码后的原始 JSON）与 buildScoreFromJson(mode)：mixed 模式先做全音符休止替换再转换，tab 模式用原始 JSON（Tab 天然安全）；
    - 切换谱面显示模式改为重建 score（新对象渲染自动触发 MIDI 重生成）→ 等 waitForPlaybackReady → 恢复位置/续播；rebuildTrackState/applyTrackMix 保留用户的乐器/显隐/静音/独奏/音量设置；
    - scoreLoaded 改为用当前 capoMode（而非初始 capo prop），并用 scoreLoadedOnce 只初始化一次 tempo/speed，避免模式切换重置用户设置。
- 验证方式与结果（证据）：
  - 浏览器实测：Hello（1yOhtb1c9I0，整休止×2）与平凡之路（20kyMNGJsLB，整休止×20）mixed 模式从「0 system + beatOfHighestNote 崩溃」修复为 34/24 system、零报错；mixed→全部六线谱→切回全程零报错；
  - 视觉 API 复核平凡之路：空小节简谱显示 0 0 0 0，与参考站一致；
  - node --test 58/58（新增 8 项 replaceWholeRests 单测：isrest/notes 判空、text 保留首个、主轨不动、无调弦/单轨不动、quarter/eighth 不动、null 安全、幂等）；
  - node tools/verify-track-mode.mjs 6/6；node tools/verify-track-coverage.mjs 60/60（60 首多轨曲目全零报错）；
  - 回归：verify-score-details 8/8、verify-player-display 10/10、verify-player-fix 9/9（含 Hello 播放零警告）、verify-player-audio 12/12、verify-m7-final 41/41、npx astro build 通过；
  - 证据 tests/evidence/track-mode/{hello-mixed-fixed,pingfan-local-fixed,pingfan-ref,t6-hello-alltab,t6-hello-back-mixed}.png。
- 遇到的问题与决策：
  - 起初尝试模型层剥离整休止（prepareNumberedStave），会引发 MIDI 生成崩溃与空小节空白 → 放弃，改 JSON 层替换；
  - 全音符休止在 Tab 渲染天然安全 → ALL_TAB 模式用原始 JSON（正确整休止），仅 mixed 模式替换；
  - 若首调弦轨含整休止（74 首）→ Tab 天然安全，无需处理；后续如需首轨简谱再扩展。
- 下一步：合并 master 后跑主分支冒烟回归；可选：整休止在 all-tab 模式的 Tab 显示样式微调。



### 2026-08-14 ～ 乐器切换无效果修复：MIDI 重生成竞态 + 音源去重（分支 fix/instrument-switch-audio）
- 本次目标：用户反馈「乐器切换仍无效果、切换不生效」。实测确认为播放中切换乐器存在 MIDI 加载竞态与音源累积问题。
- 完成内容：
  - 根因（浏览器实测 + 源码确认）：
    - 竞态：withRenderPreservingPosition 中 waitForPlaybackReady() 因旧 MIDI 已就绪立即 resolve，play 在 worker 完成新 MIDI 加载前约 140ms 抢跑（实测 loadMidi t=6136 → play t=6141 → midiLoaded t=6282），导致新音色/时间线可能未生效、播放不稳定。
    - 订阅陷阱：AlphaTab 1.8.4 的 _player.midiLoaded / loadedMidiInfo 在 AlphaSynthWebWorkerApi 存在递归 getter（return this.loadedMidiInfo），订阅会抛 RangeError（已实测），不能用作等待点。
    - 音源累积：每次切换用 append=true 重复加载 sf2，_loadedSoundFonts 无限增长；loadingSounds 守卫在快速连续切换时静默跳过新音源加载。
  - 修复（src/components/player/ScorePlayer.svelte）：
    - 新增 waitForMidiLoaded()：监听 _player._instance.midiLoaded（worker API 层安全 emitter，实测订阅不抛错、每次 worker 完成 MIDI 加载精确触发一次），8s 超时兜底。
    - withRenderPreservingPosition reloadMidi 流程改为：先订阅 waitForMidiLoaded → loadMidiForScore() → await loaded → 恢复位置 → 续播；setScoreDisplayMode（新对象 renderScore 内部重生成 MIDI）同样先订阅再 render。
    - 移除 waitForPlaybackReady（两处调用点均替换）。
    - loadSoundfonts 重构：按 program 去重（loadedPrograms 只加载新增音源，避免 _loadedSoundFonts 累积）+ 串行化（soundLoadChain 排队，快速切换不跳过）。
- 验证方式与结果（证据）：
  - 新增 tools/verify-instrument-switch.mjs 6/6 PASS：播放中切乐器 → 严格序号断言 loadMidi(8) → midiLoaded(12) → setTickPosition(13) → play(14)；program 更新 25→41；播放恢复；本次仅加载新增 41.sf2（258138B，去重生效）；console/pageerror 零报错。证据 tests/evidence/instrument-switch/。
  - 修复前后时序对比：修复前 play 早于 midiLoaded 141ms；修复后 play 严格在 midiLoaded 之后（同毫秒微任务）。
  - 回归：node --test 58/58、verify-player-audio 12/12、verify-player-fix 9/9、verify-player-display 11/11、verify-score-details 8/8、verify-m7-final 41/41、npx astro build 通过。
- 遇到的问题与决策：
  - 不能使用 _player.midiLoaded（RangeError），改用 _player._instance.midiLoaded；此为 1.8.4 构建缺陷，已在代码注释说明。
  - 未采用 api.resetSoundFonts()（worker 侧会触发 soundFontLoaded，破坏现有事件匹配），改用 program 去重 + 串行化，效果等同且无事件错位风险。
- 下一步：合并 master 后跑主分支冒烟回归。

### 2026-08-14 ｜ 音轨控件 UI 响应式修复 + 谱面模式切换放开（分支 fix/track-ui-mode-switch）
- 本次目标：用户反馈三连——「乐器切换还是没效果」「吉他谱+简谱 / 全部六线谱无法切换」「音轨控制基本没用」。实测定位到两个根因：①音轨控件直接原地修改 tracks[i] 属性，Svelte 5 传统模式不追踪深层属性变更 → UI 不刷新（命令其实已发出，所以「看起来没用」）；②谱面模式按钮因 canMixed 要求 ≥2 条调弦轨、「全部六线谱」要求 ≥2 条而被禁用（晴天等单吉他轨+钢琴谱面无法切换）。
- 完成内容（src/components/player/ScorePlayer.svelte）：
  - 音轨控件改为不可变更新：toggleTrack / toggleMute / toggleSolo / changeVolume / changeInstrument 均用 tracks = tracks.map(...) 重建数组，Svelte 响应式立即刷新按钮文字 / 音量滑杆 / select / 显隐 checkbox。
  - changeInstrument 同时把 track.playbackInfo.program / name / shortName 写到 score 对象，沿用 withRenderPreservingPosition({reloadMidi:true}) 重生成 MIDI + 加载新音源。
  - 音量滑杆统一 0-100 百分比：buildTracks 初始值按 playbackInfo.volume(0-16)/16*100；changeVolume / applyTrackMix 传 changeTrackVolume(v/100)（AlphaTab mixVolume 为线性增益、1.0=满，文档示例 1.5/0.5），修复原先「初始 0-16、滑杆 max=200、/100 缩放」三重不一致导致的音量控制错乱。
  - 谱面模式：canMixed 语义改为「≥1 条调弦轨」；「吉他谱+简谱」「全部六线谱」在单吉他轨谱面也可用（resolveStaveDisplay 本就支持单调弦轨：有调弦渲染六线、无调弦渲染简谱）；默认模式改为始终 mixed（对齐参考站 1 六线 + 1 简谱 + 歌词）；单轨谱面 mixed 与 all-tab 渲染等价（切换仅改变按钮高亮与模式语义，属预期）。
- 验证方式与结果（证据）：
  - 修复前探针：静音按钮点击后文字不翻转（setChannelMute ch0/ch1 已发出）；修复后 静音→取消静音→静音 翻转、setChannelMute true→false 收发。
  - 新增 tools/verify-track-controls.mjs 7/7 PASS：C2 静音翻转+命令收发、C3 独奏翻转+命令收发、C4 音量 50→setChannelVolume 0.5 且 UI 保持 50、C5 显隐勾选、C6 乐器切换 UI select 25→41 + program 41 + 41.sf2(258138B) 加载 + loadMidi 重生成、C7 全程零报错。证据 tests/evidence/track-controls/。
  - tools/verify-track-mode.mjs 6/6 PASS：T4 由「晴天按钮禁用」改为「单吉他轨两按钮可用、mixed→all-tab→mixed 往返零报错」。
  - 回归：node --test 58/58、verify-instrument-switch 6/6、verify-player-display 11/11、verify-score-details 8/8、verify-player-fix 9/9、verify-player-audio 12/12、verify-m7-final 41/41、npx astro build 通过。
- 遇到的问题与决策：
  - 乐器切换 select 值此前「看起来在更新」是副作用（loadingSounds 等状态变化触发重渲染时读到新值）；真正的响应式缺陷在静音/独奏/音量/显隐上暴露，统一改不可变更新后全部稳定刷新。
  - 音量单位确认：changeTrackVolume → setChannelVolume → channelSetMixVolume（线性增益 1.0=满）；统一 0-100% → /100 传入。
  - 单吉他轨谱面 mixed 与 all-tab 渲染等价（无调弦轨只能渲染简谱），属预期行为，不视为缺陷。
- 下一步：合并 master 后跑主分支冒烟回归；音轨显隐后隐藏轨道仍发声（参考站行为待确认）另立任务。
### 2026-08-14 ｜ 乐器切换真实生效：同步 Instrument 自动化（分支 fix/instrument-automation）
- 本次目标：用户再次反馈「乐器选择还是没有作用」。上一轮只验证了数据链路（下拉框/program/sf2/MIDI 重生成），未验证再生 MIDI 里的实际音色号。
- 根因（浏览器实测，抓取 worker 的 alphaSynth.loadMidi 内 Program Change 事件）：
  - 切换乐器后重新生成的 MIDI 里同一通道出现两条 Program Change：先是新音色 41，随后又被旧音色 25 覆盖（晴天两条音轨首拍都带 Instrument 自动化，value 分别为 25/0）。
  - AlphaTab MidiFileGenerator 顺序：先按音轨 playbackInfo.program 发出初始 Program Change，再逐拍处理 Instrument 自动化（_generateNonTempoAutomation）。GP 谱首拍常冗余写死原音色，改 playbackInfo.program 后自动化仍会覆盖回旧音色 → 听感无变化。
  - 同类问题：setScoreDisplayMode 用 buildScoreFromJson 从 JSON 重建 score 后，rebuildTrackState 只恢复 playbackInfo.program、不恢复自动化 → 切换显示模式后音色同样会回落。
- 修复（src/components/player/ScorePlayer.svelte）：
  - 新增 applyTrackInstrument(track, program)：设置 playbackInfo.program/name/shortName，并把该音轨所有 AutomationType.Instrument(2) 自动化的 value 统一改为新 program。
  - changeInstrument 与 rebuildTrackState 都改用该 helper，保证播放 MIDI 与显示模式切换后音色一致。
- 验证方式与结果（证据）：
  - 探针抓取 loadMidi 的 Program Change：修复前切换 25→41 后 MIDI 为 [ch0/1=41, ch2/3=0, ch0/1=25]（旧音色覆盖）；修复后为 [ch0/1=41, ch2/3=0]，仅新音色；score 自动化 value=41。
  - 切「全部六线谱」后再次抓 MIDI：仍为 [ch0/1=41, ch2/3=0]（不回落 25），自动化 value=41。
  - tools/verify-track-controls.mjs 扩展至 8/8 PASS：C6 新增断言（program/自动化/select/sf2/MIDI 全链路 + 无旧音色覆盖），C7 新增断言（切谱面模式后乐器保持）。
  - 回归：node --test 58/58、verify-track-mode 6/6、verify-instrument-switch 6/6、verify-player-display 11/11、verify-score-details 8/8、verify-player-fix 9/9、verify-player-audio 12/12、verify-m7-final 41/41、npx astro build 通过。
- 遇到的问题与决策：
  - 抓取 MIDI Program Change 需解析 JsonConverter.midiFileToJsObject 的 Map 序列化结构（data.midi 非 MidiFile 对象），兼容 Map/plain object 两种形态。
  - 决策：切换乐器 = 整轨统一新音色（同步所有 Instrument 自动化）；保留自动化结构（不删除），避免破坏原谱中真正的乐曲中途换乐器场景。
- 下一步：合并 master 后跑主分支冒烟回归；音色听感最终需用户在浏览器确认（无头环境无法渲染音频）。
### 2026-08-14 ｜ 关闭音轨=静音 + 音效链路审计（分支 fix/track-off-silence）
- 本次目标：用户反馈①「还有很多音效没有实现」②「关闭音轨后没有反应」。
- 关闭音轨修复（src/components/player/ScorePlayer.svelte）：
  - 根因：toggleTrack 只调 api.renderTracks 隐藏谱面显示，未发送 setChannelMute，隐藏音轨仍发声（探针实证：取消勾选后谱面 18→10 段但播放继续、无任何静音命令）。
  - 修复：toggleTrack 隐藏时 changeTrackMute(true)、重开时按用户静音状态恢复；applyTrackMix 统一按 !tr.show || tr.muted 设置静音，保证模式切换重建谱面后隐藏轨仍静音。
  - verify-track-controls C5 扩展：取消勾选 → setChannelMute ch0/ch1=true；重开 → false。8/8。
- 音效链路审计（结论：数据→MIDI→合成器三层均完整，未发现缺失实现）：
  - 数据层：解码 8125 个 .ibe，扫描到含推弦/揉弦/闷音/琶音/震音等技巧的谱（如 1H9WW324T 天地龙鳞 20 推弦+40 揉弦、1H9RahleH 5 闷音、1sdc71abklk 230 琶音+6 震音）。
  - MIDI 层：天地龙鳞生成的 loadMidi 含 5926 个 PerNotePitchBend（type 96）事件；闷音音符力度 63 vs 普通 79（力度差真实存在）；力度字段为 Beat/Note.dynamics（此前探针误读 dynamic 得出错误结论）。
  - 合成器层：AlphaSynth 对 type 96 走 channelSetPerNotePitchWheel → updatePitchRatio 计入 pitchWheel（推弦/揉弦/滑音会真实变调）；闷音靠力度层。
  - 说明：技巧效果是否「听感明显」取决于源谱数据（晴天等简单流行歌本身无推弦/滑音）与 sf2 采样质量；无头环境无法渲染音频，最终听感需浏览器确认。
- 验证方式与结果（证据）：node --test 58/58、verify-track-controls 8/8、verify-track-mode 6/6、verify-instrument-switch 6/6、verify-player-display 11/11、verify-player-audio 12/12、verify-score-details 8/8、verify-player-fix 9/9、verify-m7-final 41/41、npx astro build 通过。
- 下一步：合并 master 后跑主分支冒烟回归；如需更强的吉他技巧听感（更真实闷音/推弦音色），可评估替换高质量 sf2 或启用 MIDI 效果层（另立任务）。

### 2026-08-14 ｜ 乐器效果补齐：全 129 GM 音源覆盖（M9.1/M9.2，分支 feat/player-instrument-fx）
- 本次目标：用户反馈「很多乐器的效果都没有实现」。根因定位：本地 public/storage/soundfonts/ 仅有 72/129 个 {program}.sf2，缺失的 57 个音色（风琴/弦乐/铜管/木管/合成器/世界乐器/音效等）在 resolveSf2() 中回退 0.sf2（钢琴）→ 切换乐器或播放多乐器谱时大量音色被钢琴替代。
- 完成内容：
  - CDN 实测：https://p.insstudy.com/puquanle/soudfont/{program}.sf2 对 0–128 全部返回 200（此前 DEV_LOG 记录「原站不存在 49/51.sf2」已过时）。
  - 新增 tools/fetch-sf2.mjs：0–128 全量下载（4 并发 + 3 次退避重试）→ 复用 convertSf2 立体声转单声道 → 原子写回 public/storage/soundfonts/ → 重建 index.json（129 项）。下载 129/129 成功、0 失败；转换后 analyze 无 sampleType 2/4 残留。
  - 新增 tools/verify-instrument-fx.mjs（12/12 PASS）：index.json 覆盖 0-128 全量；逐一切换此前缺失的代表性音色 17/40/49/56/64/73/108/128 → 断言加载对应 {p}.sf2 且不再回退 0.sf2、score program 正确；鼓组 128.sf2 正常加载；console/pageerror 零报错。证据 tests/evidence/instrument-fx/。
- 验证方式与结果（证据）：
  - 全量扫描 8125 谱音轨 program 分布：25(钢弦吉他) 最常用、0(钢琴伴奏)/24(尼龙) 次之、53 人声/71 单簧管等少量；含鼓组(Drumkit, ch 9/9)谱确认存在并走 128.sf2。
  - node --test 58/58、verify-instrument-switch 6/6、verify-track-controls 8/8（回归基线不破坏）。
- 遇到的问题与决策：
  - public/storage/ 在 .gitignore 中（大二进制不入库）：音源文件仅落本地磁盘，不随分支提交；fetch-sf2.mjs 作为可复现脚本入库。
  - 128.sf2 本地 700,572B = CDN 918,922B 的 mono 版本（此前已转换），本次重下后仍为 700,572B，确认一致无回归。
- 下一步：M9.3 鼓组/打击乐核对；M9.4 贝斯击勾 tap/slap/pop MIDI 效果调研与实现；M9.5 技巧音效可闻性抽查 + 试听清单；M9.6 回归收尾合入 master。
### 2026-08-14 ｜ 贝斯击勾 MIDI 力度增强 + 鼓组核对（M9.3/M9.4，分支 feat/player-instrument-fx）
- 本次目标：用户反馈「很多乐器的效果都没有实现」的后两项——鼓组音源核对与贝斯击勾（tap/slap/pop）无 MIDI 效果问题。
- 完成内容：
  - 贝斯击勾（src/lib/bassArticulation.mjs + ScorePlayer.svelte）：
    - AlphaTab 1.8.4 MidiFileGenerator 只对 tap/slap/pop 渲染 S/P/T 字母、不生成 MIDI 力度/音色差异（全量扫描 8125 谱：tap=41/slap=15/pop=13 谱含此数据）。
    - 利用官方文档明确支持「inspect or modify the midi events」的 api.midiLoad 事件：订阅后在 MIDI 进合成器前，对 slap/pop/tap 拍（经 tickCache.getBeatStart 定位刻度）的 NoteOn 事件提升力度——slap +22 / pop +18 / tap +10，clamp 0-127。纯函数 bassArticulationBoost/applyVelocityBoostToMidi 独立成模块可单测。
    - 关键坑：AlphaTab 生成的是 format 0 MIDI（单 track、事件自带 .track 字段），不能按 midiFile.tracks[trackIndex] 取轨，必须遍历所有事件按 ev.track 匹配。
    - 组件保留测试钩子 `window.__disableBassBoost`（默认 false 不生效）供对照实验。
  - 鼓组核对：本地 128.sf2 700,572B = CDN 918,922B 的 mono 版本（此前已转换，本次重下后一致）；含 Drumkit 轨（ch 9/9 → program 128 映射）的谱正常加载 128.sf2。
- 验证方式与结果（证据）：
  - 单测 tests/bass-articulation.test.mjs 5/5：力度增量、format0/format1 匹配、clamp、空 map 安全。
  - 新增 tools/verify-bass-articulation.mjs 4/4 PASS：oOEvk5YC（Just The Two Of Us，132 slap + 61 pop）——「增强开 vs 关」对照生成 MIDI，193/193 击勾拍力度差精确等于增强值（slap 79→101、pop 79→97、ghost slap 63→85）；console/pageerror 零报错。证据 tests/evidence/bass-articulation/。
  - 回归：node --test 63/63、npx astro build 通过、verify-instrument-switch 6/6、verify-track-controls 8/8、verify-player-fix 9/9（T9 全量 sf2 零 unsupported 警告：loaded 129）、verify-player-display 11/11、verify-player-audio 12/12、verify-score-details 8/8、verify-instrument-fx 12/12。
- 遇到的问题与决策：
  - 击勾拍力度验证先按「预测基础力度」断言失败（ghost 音符真实基础力度 63 ≠ 模型推导 78），改为「增强开关对照」后 193/193 精确通过。
  - 决策：击勾增强按数据驱动（仅含 slap/pop/tap 的谱生效），不新增 UI 开关；如需可后续加。
- 下一步：M9.5 技巧音效可闻性抽查 + 试听清单（bend/harmonic/palmMute/letRing/slide 代表谱）；M9.6 回归收尾合入 master。
### 2026-08-14 ｜ 技巧音效可闻性抽查 + 试听清单（M9.5，分支 feat/player-instrument-fx）
- 本次目标：在音源全量补齐 + 击勾增强基础上，抽查代表谱的 MIDI 事件特征，证明演奏技巧「数据→MIDI→合成器」链路在真实谱面上可闻。
- 完成内容：新增 tools/verify-technique-fx.mjs（9/9 PASS），对 8 首代表谱生成 MIDI 并断言事件特征：
  - 天地龙鳞（王力宏）：推弦+揉弦 → 5926 个 PerNotePitchBend（type 96）
  - 真的爱你前奏（Beyond）：推弦 → 212 个 per-note 弯音 + 力度 63-79 分层
  - 李白（李荣浩）：滑音 → 405 个 per-note 弯音
  - 死别：闷音 → 5 个 122-tick 短音符（AlphaTab 闷音=时值缩短，非力度，已确认实现正确）
  - 祝你生日快乐：延音（Let Ring）→ 最长音符 569,280 ticks
  - 知足（五月天）：泛音+延音 → 正常发声、力度 111-127
  - 类似爱情（萧亚轩）：琶音 → 正常发声
  - Just The Two Of Us（Grover Washington Jr.）：全乐队 13 轨 + 鼓 + 贝斯击勾 → 6377 NoteOn、力度 63-101（含击勾增强 101）
  - 全程 console/pageerror 零报错；证据 tests/evidence/technique-fx/。
- 试听清单（用户在浏览器最终确认听感，headless 无法渲染音频）：
  1. 天地龙鳞 1H9WW324T：前奏推弦/揉弦应有音高起伏（弯音）
  2. 真的爱你前奏 1H9TYl5rJ：推弦上行 + 闷音短促
  3. 李白 1H9ReAmpR：滑音过渡
  4. 死别 1H9SkFiMP：闷音节奏短促
  5. 知足 1H9RlDwKT：泛音清亮 + 延音
  6. Just The Two Of Us oOEvk5YC：贝斯 slap/pop 明显更亮更响（101 vs 63/79）、鼓组/萨克斯/长笛/电钢琴等音色齐全
- 遇到的问题与决策：闷音验证指标初版误用「低力度」，实际 AlphaTab 闷音=静态短时值；改为 minDur 断言后通过。部分谱 minDur 为负是 NoteOff 匹配伪影（per-note 弯音键位差），不影响断言项。
- 下一步：M9.6 全量回归 + 合并 master。
### 2026-08-14 ｜ 曲谱数据爬取完成（M7.1 收尾）
- 本次目标：用户要求「继续完成爬取」。此前爬取停在断点（done=9290/failed=27，DB 11955 首）。
- 执行方式：
  - 断点续爬单线程实测速率仅 ~9 首/分钟（剩余 4288 需约 8 小时）→ 停止后把剩余候选（4242，已排除 done/failed/已在库）随机拆成 3 份，3 个独立 worker 并行爬取（pace 1000，各自 state 文件）。
  - 全程约 1.5 小时完成；无限流（567/429 零出现），失败均为个别页面 sheetInfo JSON 解析异常（页面上报格式问题，非网络/限流）。
- 完成结果：
  - DB 曲谱总数 11955 → **16233**（+4278）：吉他 12212 / 尤克里里 4021；GP 格式 12106 / XHE 4127。
  - 存储：12101 个 .ibe、4122 个 xhe JSON、16210 张截图。
  - 候选覆盖：14675 候选 → **14640 在库（99.8%）**，仅 35 个失败（多为 uo/1Oy6 开头、页面无有效 sheetInfo 或已下线）。
  - 断点合并：migrate-state-m7.json（done=13522，failed=37，含三 worker 增量）为最终记录。
- 验证方式与结果（证据）：
  - 新入库曲谱抽查：/tabs/1H9UCBPb3（机场雷雨）详情页播放器就绪（2 音轨、console/pageerror 零报错），截图 tests/evidence/m7/crawl-final-smoke.png；/tabs 列表 HTTP 200。
  - 数据一致性：DB tab 数 = 各格式之和；.ibe/xhe 文件数略少于 DB（个别记录 scoreUrl 指向但本地文件缺失，属历史遗留，不影响功能）。
- 遇到的问题与决策：
  - 单线程过慢（8h）→ 3 路并行把耗时压到 ~1.5h；并行不共享 state 文件避免写冲突，末尾合并；upsert 幂等保证无重复。
  - 35 个失败不重试（页面本身无有效数据），如需可在后续专项补抓。
- 下一步：用户确认后，可将全站数据规模（16233）纳入首页/列表/搜索的分页与性能回归。

### 2026-10-20 ｜ 真实曲库恢复与日常启动检查

- 按 [恢复计划](docs/catalog-runtime-recovery-plan.md)，两名 `gpt-6-luna / max` 子代理负责启动工具、数据库依赖审查与独立复审；主代理完成Docker恢复、数据保全与实际运行验证。
- Docker启动在两个零字节IPC端点处失败。停止失败实例并保留改名两处运行目录后，引擎恢复；只启动已有数据库容器。原库16233条曲谱、8篇文章可读。完整备份可解析、整体schema diff为空后，对齐已存在结构的缺失迁移记录，五业务表前后内容摘要无变化。
- 新增 `start:local` 和 `--check`，区分日常曲库启动与允许降级的普通start；验证既有容器/卷/端口、五模型52列/迁移/非空曲库及应用同连接只读访问。错误分类脱敏、等待有界，不自动创建、迁移或恢复数据库。
- 候选最终测试446项（439通过、7旧数据库测试未执行）；14项启动定向测试与语法检查通过。构建和类型检查通过，保留57条既有Svelte警告。32595个公开媒体文件的public/dist交付摘要一致；实际4336已返回readiness200、搜索catalog与原谱200。
- master代码合并 `bb642266` 后，回归仍439通过/7未执行/0失败，构建71.33秒、类型检查0错误，媒体摘要一致。真实启动器已接管4336，Windows Ctrl+C实测无残留测试服务。全库标准路径引用存在，4条非标准score引用未纳入核验；没有宣称全库解码/真机/重启持久性通过。
- 文件、命令、Git交付、数据库保护、截图及浏览器边界见 [验收记录](docs/evidence/catalog-runtime-2026-10-20/README.md)。日常命令见 [启动指南](docs/local-catalog-startup.md)。

### 2026-10-19 ｜ 练习衔接、触摸控件与和弦预览

- 目标与分工：按 [详细计划](docs/practice-touch-continuity-plan.md)，三名 `gpt-6-luna / max` 子代理分别负责播放与练习、队列与记录、和弦与控件；主代理集成、真实浏览器验收和 Git 交付。保留原工作区的既有改动。
- 练习：设置默认折叠且保留子树；主进度条与选曲有明确 44px 命中区；拖动提交和取消分开处理，取消恢复引擎最新确认位置，覆盖曲末与 A-B 回绕。变调夹补 Escape/焦点返回，隐藏 HUD 使用 inert。
- 保存：备注使用显式保存/取消、首次编辑基准和事务内比较；跨页冲突保留草稿，阻止切曲或错误结束。切曲护栏等待保存并丢弃过期选择；归档再恢复会在原 URL 自动重新打开曲谱。回顾和首页手记按曲谱的当前可用状态提供对应入口。
- 和弦：统一 hover/focus/点击固定、Escape/点外关闭、边缘翻转和卸载清理，复用既有动效偏好。缺失指法使用明确说明；320px 流动字号下的按钮改为固定 44px，窄屏允许换行。没有新增未经核实的指法数据。
- 工坊：三个播放开关补名称及按下状态；静态核实已有 AlphaTab 原生接入，不增加重复桥接。浏览器状态验证不能代替声音可闻性验证。
- 实际检查、截图、候选与主分支提交见 [验收记录](docs/evidence/practice-touch-2026-10-19/README.md)。数据库、真实触摸、真机、屏幕阅读器和长时播放分别记录边界，不把跳过项目写成通过。
