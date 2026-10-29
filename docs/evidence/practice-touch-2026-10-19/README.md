# 练习衔接与触摸体验验收

日期：2026-10-19。计划见 [practice-touch-continuity-plan.md](../../practice-touch-continuity-plan.md)。稳定基线 `2097463d`，实施分支 `feature/practice-touch-continuity`。

## 环境与资料

使用独立工作树的生产构建、`127.0.0.1:4338` 与 agent 创建的 IAB 标签，仅操作先前自写曲谱与测试个人资料。十六小节夹具见 [self-authored-motion.json](../expressive-motion-2026-10-18/self-authored-motion.json)，通过上轮真实文件选择器导入，没有注入应用私有状态或 IndexedDB。原目录/服务数据与测试源分开；不导航、刷新或编辑原工坊标签。

当前 Docker daemon 不可连接；本轮没有启动既有容器、修改卷、连接真实曲库或执行迁移。数据库测试跳过与真实目录 readiness 分开记录。

## 优化前观察

原始公开 DOM 观察见 [browser-observations.json](browser-observations.json)，优化前截图见 [practice-before-mobile.png](practice-before-mobile.png)。

- 390×844：clientWidth/scrollWidth 同为375，无横溢出；个人练习面板高1044.74px，初次两小节谱的谱面 top1778.66px。选择十六小节谱后面板同高，top 因工具条内容变化而变化，不能把单个 top 视为所有曲谱常数。
- 主播放进度 input 的实际命中框高4px；选择练习曲谱 select 高33.95px。
- 打开变调夹菜单，在触发器按 Escape，菜单仍展开、`aria-expanded=true`；这是浏览器实测的修复前结果。
- 尝试通过 IAB 的 CDP 发送触摸取消，但 `Input.dispatchTouchEvent` 不受支持，未发出触摸事件；临时 Touch Emulation 已立即清除。不能声称已用真实触摸复现 pointercancel。该缺陷的触发与后果来自源码路径审查，修复将用控制器行为测试和浏览器正常提交路径分别验证。

## 实施与最终验收

三名 `gpt-6-luna / max` 子代理按计划独占写范围。主代理补事务内 note 比较、集成复核、浏览器和 Git；两个代理分别交叉审查写入与切谱并发路径。没有迁移或数据 schema 变更。

### 已完成的实际练习流程

1. **紧凑布局与触控**：最终实际视口320/390/768/1024/1366的 clientWidth 与 scrollWidth 相等，均无页面横溢出；进度条及选曲框均为44px。390×844初始面板约279px，相比基线1044.74px明显缩短；details 默认关闭，隐藏 HUD 同时具有 `aria-hidden=true` 与 `inert`。这里是初始状态的面板高度，开始会话后备注和断点会增加内容。
2. **变调夹**：所有选项不小于44px；Escape关闭后 expanded=false，焦点返回触发器。键盘选择2品后标签更新、菜单关闭，焦点仍回到触发器。此处只验证控件与渲染路径，不声称可闻性。
3. **折叠与连续性**：十六小节自写谱实际开始播放。输入会话备注、片段名和步长7，折叠后仍显示“暂停”、tick前进至26462，再展开保留全部草稿。折叠前后公开 `.at-surface` 的 backend ID 同为3285，之后正常暂停。没有用应用私有引擎状态注入替代真实播放。
4. **选段与参数**：暂停后设置 A=26881；通过进度条 PageUp 正常提交到33025；设置 B=33600，提速计划显示当前60 BPM、0/3圈、上限90。该步骤验证键盘跳转及计划接续，没有在本轮重跑自动完成多圈提速的长流程；既有行为测试仍覆盖提速逻辑。
5. **双页备注冲突**：本页输入A，另一页显式保存B；本页保存后显示冲突，草稿A保留。选曲到两小节谱时护栏拒绝，select、URL和原播放器仍指向十六小节谱；取消编辑载入B。第二次以A2/B2复核“结束并保存”：冲突不完成会话；取消后再结束才显示已完成，回顾保留B2。截图见 [note-conflict-mobile.png](note-conflict-mobile.png)。
6. **正常切谱与断点**：新会话暂停后输入备注，直接选两小节谱；护栏先保存，URL正确切换，回顾可见新备注；切回十六小节谱仍有该备注。随后短时播放/暂停产生已保存断点tick6473；重新加载后点“继续上次并保持暂停”，进度恢复6473且按钮保持“播放”，备注仍在。
7. **跨页归档恢复**：另一页归档十六小节谱，原页清除选曲与谱面、保留请求URL并说明已归档；回顾指向恢复管理。首页“我的练习手记”滚动进入后完成 client:visible 加载，两条记录均显示已归档并链接 `/library`。在已归档分区恢复后，原练习页自动重新选择同曲、恢复一个谱面节点及保存的备注，回顾链接回到该曲练习；没有手动刷新原练习页。
8. **工坊开关**：真实页面三个按钮的名称为节拍器、预备拍、整首乐谱循环；逐一点击后 aria-pressed 从false变true，再点击还原false。代码审查确认已有 AlphaTab 1.8.4 公开属性接入，此次没有新增音频桥接，未以按钮状态宣称声音已试听。

原始记录中保留了未计作通过的尝试：首次批量 viewport 只调整了当前另一标签，读取到的练习页仍是390，随后在实际生效标签重做五种尺寸；首页手记滚动前的加载占位，以及尚未确认 hydration 时的首个和弦键盘尝试都没有计作通过。恢复按钮同时存在于工坊工程与已归档区，最终按已归档分区定位执行。

### 集成检查与后续记录

第一轮完整类型检查出现离开护栏空会话参数错误及两条新增警告，已修正，并恢复被透明样式覆盖的4px细轨道。此后完整检查为0 errors、57条既有 Svelte warnings / 18 files、41 Astro hints。窄屏末轮另外修正流动根字号导致的约40px按钮，以及未收录和弦无反馈；最终源码冻结后重新执行全部检查，结果另见交付表。

初始候选截图见 [practice-after-mobile.png](practice-after-mobile.png)，最终收起设置的截图见 [practice-final-controls-mobile.png](practice-final-controls-mobile.png)。原生 summary 用 Enter 关闭后，焦点仍在 SUMMARY、播放按钮仍为“播放”；Space 的一次工具尝试未改变展开状态，不将它计作键盘通过或真实设备证据。

完整模式的追加失败单独保留：[chord-before-full-clip.png](chord-before-full-clip.png)。Hero 弹层虽然写入视口 top=316.8px，实际 top=-90.2px；其父级 backdrop-filter=blur(12px)、overflow=hidden 创建了固定定位包含块。轻柔模式下的成功不能覆盖这个失败。最终修复采用组件顶级兄弟弹层。

### 最终和弦与控件复核

- 完整模式、320×812：Hero 弹层实际 top=316.80px、bottom=449.43px、left=81.38px、right=188.53px，父级为 ASTRO-ISLAND；四个按钮均44×44px，clientWidth=scrollWidth=305。首次激活仍显示，第二次激活关闭；Escape 的退场动画完成后节点数为0，未把动画中的暂留DOM当作关闭失败。
- 首次键盘跳到远处控件还触发一次定位竞态：浏览器尚未滚动，锚点离屏就被关闭。已改为初次尚未定位时保持隐藏，等待现有 scroll/resize 定位；已定位锚点滚出时照常关闭。最后生产构建从scrollY=0、锚点top=2576.32px开始，只按一次Enter即显示G#m的未收录说明；弹层left=49.55、right=156.31、top=283.33、bottom=408.20，完整位于320×812视口。见 [chord-after-full-mobile.png](chord-after-full-mobile.png)。没有凭空新增指法。
- 轻柔、静止两种模式再次打开Hero的D指法图，实际边界都在视口内；关闭后等待节点退出。这里只证明偏好分支和功能定位，没有恒定帧率承诺。
- 最后构建的1366px曲库：固定G预览后以键盘切到列表，列表aria-checked=true、弹层节点数0，没有失去锚点后残留。
- 最后构建的320px待练条目：上移、下移、开始、归档、移出、状态select、备注input全部实测44px；clientWidth=scrollWidth=305。其余搜索/导入表单未在此项扩大修改范围。
- 两个验收页最终 console error 列表均为空；测试会话已通过UI结束，4338偏好已还原跟随系统，视口覆盖已reset，两个自建标签及QA服务已关闭。

## 候选分支检查

最终源码冻结后运行，均观察到进程退出码：

| 命令 | 结果 |
| --- | --- |
| `npm test` | exit0；383 total / 376 pass / 7数据库skip / 0fail，较稳定基线增加25项通过测试 |
| `npm run build` | exit0；41.51s；既有AlphaTab大chunk与Prisma browser external告警保留 |
| `npm run typecheck`（build完成后） | exit0；TypeScript/Astro/Svelte 0errors；57条Svelte warnings / 18files、41条Astro hints，与基线相同 |
| `git diff --check` | exit0；提交前与实际master均复核，无空白错误 |

没有独立Lint脚本；未宣称执行额外Lint。

## 主分支交付与服务

计划提交 `77e74084`、`9aabc763`；练习逻辑提交 `4c290610`，和弦与工坊控件提交 `65860e47`，验收文档提交 `7d53c518`。实施分支 `feature/practice-touch-continuity` 以 `--no-ff` 合入 master，功能合并提交为 `106e50bb`。完整变更见 [changed-files.txt](changed-files.txt)，结构化结果见 [verification.json](verification.json)。最后的交付补充仅改文档，源码与下述回归版本一致。

在 `D:\MIMIguitarweb-master-merge` 实际运行 master：`npm test` exit0（383 total / 376 pass / 7数据库skip / 0fail）；`npm run build` exit0（12.23s）；随后 `npm run typecheck` exit0（TypeScript/Astro/Svelte 0errors，57条Svelte warnings / 18files、41条Astro hints）。既有告警未增加；代码合并后工作树干净，`git diff --check` exit0。

4336已重启到合并后的构建：health 200/alive，`/practice`、`/studio`、`/motion`均200；动效页包含全站偏好，临时QA路由404且最终dist不含QA HTML。三个必要音源HEAD均200，大小分别1205140、1205140、400880 bytes，dist SHA-256与原资源一致。

readiness真实结果为503/not_ready，database/catalog unavailable，音源3/3 ready。隔离数据库没有启动，迁移状态不可用；该预览不证明在线目录、生产数据库或整个平台已达到生产就绪。未启动既有容器、修改卷或连接用户真实数据库。

结束保护复核exit0：1023文件哈希差异0、402行Git状态差异0。原目录仍为 `feature/complete-score-studio@f4ac8ece`；没有清理、提交或覆盖用户原有改动。两个自建浏览器标签、QA服务已关闭，偏好恢复跟随系统，视口和触摸模拟已清除；4336本地预览继续运行。没有推送、创建PR或部署。

## 下一步验收顺序

1. 在iPhone/iPad Safari与Android真机复核真实pointercancel、纵向滚动、44px命中、虚拟键盘及原生离页提示。
2. 在明确隔离的专用数据库环境运行7项数据库测试，再核对目录与readiness；不以演示曲库代替真实内容验收。
3. 完成30分钟/2小时播放、自动多圈提速及实际可闻性验收，再决定后续能力扩展。

## 独立验证边界

本轮浏览器可验证公开控件状态、键盘和普通点击、布局、焦点、谱面节点与短时播放；它们不能证明可闻声音、真实触摸取消、iPhone/iPad Safari 或 Android 真机、屏幕阅读器、虚拟键盘及持续30分钟/2小时播放。动态效果样本与截图不支持恒定60/120fps承诺。未执行的项目在交付时继续明确列出。
