# 页面导航性能与过渡验收

日期：2026-10-19。基线 `master@939cf5f7`，实施分支 `feature/fast-page-navigation`。范围与写所有权见 [开发计划](../../fast-page-navigation-plan.md)。

## 环境与边界

在隔离工作树生产构建的 `127.0.0.1:4338` 与独立 IAB 标签验证。现有浏览器请求带Cookie，保守策略已将预取设为false；没有读取或清除这些Cookie。匿名流程另用 `navigation-20261019.localhost:4338`，保持用户登录资料和原用户标签 `4336/practice` 不被导航、刷新或编辑。工坊测试只使用此前通过UI导入的自写验收谱。

两轮均使用同一不可达的隔离数据库地址、2秒连接超时；不连接用户真实数据库、不启动既有容器或修改卷。数据库恢复与真实目录性能需要另行验证；本轮不能把演示数据当作在线目录就绪。原目录有402行已有状态，1023文件保护清单仍需交付时复核。

HTTP耗时由PowerShell Stopwatch包围实际 `Invoke-WebRequest`，包含本机客户端开销。浏览器文档耗时来自CDP Network.responseReceived的 `timing.receiveHeadersEnd`；点击墙钟包含工具等待、水合与UI定位，不能等同于纯服务器耗时，也不能证明帧率。

浏览器只通过cua_repl的正常导航/控件操作，公开DOM只读与网络观测；未注入应用单例、localStorage或IndexedDB。IAB只读DOM环境不提供performance API，Animation.enable也不可用，未绕过限制采集私有运行时或动画帧率。

## 优化前实测

原始数据：[主路由两轮](http-baseline.json)、[补充路径](http-baseline-extra.json)、[合法全部分类搜索](http-baseline-search.json)、[浏览器观测](browser-observations.json)。

| 路径 | HTTP基线 | 观察 |
| --- | --- | --- |
| `/practice`、`/library`、`/motion`、`/studio` | 热请求3–13ms | 本地页本身无数据库目录等待 |
| `/`、`/tabs`、`/ukulele`、`/article` | 连续两轮约2008–2027ms | 每次重复等待连接失败 |
| `/searchResults?searchValue=晴天&type=all` | 8277.4ms | 分类与文章读串行积累连接等待 |
| `/api/search?q=晴天` | 2016.8ms | 返回带demo来源的结果 |
| `/tabs/1sdc49P3eKm` | 2048.9ms | 演示详情回退 |
| 不存在的文章详情ID | 2015.9ms / 404 | 无法区分断连与确实不存在 |

补充路径记录中的 `/searchResults?q=晴天` 不是该页支持的搜索参数，仅作为空搜索页观察，未用它计算搜索性能改善。

练习页点顶栏吉他谱，文档响应头2053.887ms，至列表控件可用墙钟3113ms。首页文档响应头2037.183ms；未点试听已请求AlphaTab模块（构建文件1,227,556 bytes）、解码器和吉他音源，且公开DOM已经出现隐藏试听host。基线控制台无error/warn。截图见 [首页优化前](home-before.png)。

## 实施与验证结果

三名既有gpt-6-luna/max子代理按独占范围实现公开目录读、导航与试听/保存边界。主代理审查、修复集成问题并做HTTP与浏览器验证。导航交叉审查指出Astro的Save-Data/2g tap预取例外，已经用不拦原生事件的capture守卫修复；音频交叉审查的一次工具传输失败不计为审查通过，主代理随后完成代码与运行路径复核。

### 实际HTTP改善

同一独立预览、同一不可达隔离数据库、同一2秒连接/池超时。没有更改数据库环境来制造前后差异。可复现脚本见 [measure-http.mjs](measure-http.mjs)；同一Node客户端完整基线见 [http-baseline-node.json](http-baseline-node.json)，候选见 [http-candidate.json](http-candidate.json)。PowerShell最初基线与Node结果分别保留，不混淆客户端开销。

| 路径/条件 | 候选HTTP耗时 | 来源与缓存 |
| --- | --- | --- |
| 首页冷连接探测 | 2040.95ms | demo；保留真实等待 |
| 首页第二次 | 5.84ms | demo |
| 吉他谱连续两次 | 15.03 / 5.70ms | demo |
| 尤克里里连续两次 | 7.73 / 5.88ms | demo |
| 专栏连续两次 | 7.33 / 3.02ms | 明确标出演示内容 |
| 全部分类搜索，退避窗口内 | 7.61ms | demo；no-store |
| 未知文章ID，数据库不可用 | 5.01ms / 503 | no-store，区分404 |
| 含Cookie的吉他谱请求 | 4.88ms | no-store + Vary: Cookie |

原生HTTP客户端没有浏览器HTML缓存，连续访问改善来自服务器减少重复连接等待。匿名四个顶层读页实际收到 `private, max-age=10` 与 `Vary: Cookie`；带查询参数、带Cookie、个人页和错误响应no-store。

退避到期后再次请求全部搜索，实测2236.24ms；接着吉他谱11.64ms、尤克里里9.26ms，均保留demo标记，见 [http-after-cooldown.json](http-after-cooldown.json)。不能用窗口内7.61ms替代到期恢复探测的真实等待。真实数据库恢复只做了注入测试，未在生产数据库验证。

### 浏览器实际流程

- 匿名练习页键盘焦点触发吉他谱预取，请求类型Other、状态200、响应头约2017ms。完整URL确认的最终一次练习→吉他谱，预取响应头2013.111ms，Enter到目标URL/DOM就绪及AX返回410ms，画廊控件可见，随后切列表的aria-checked=true，能再切回画廊。包含工具等待，不是恒定页面性能。原基线为带Cookie主机的鼠标点击，不能把这两次当成严格同条件统计样本。
- 另一次吉他→尤克里里记录265ms只到AX调用返回，后续才单独确认目标URL；不将265ms当作完整切页终点。观测到资源缓存事件，但没有拿到HTML的 `fromPrefetchCache=true` 字段，不宣称已证明该字段命中。
- 首页未试听：公开DOM无隐藏试听host；完整网络窗口无AlphaTab/IBE/runtime/SF2请求。首次点试听后才请求对应chunk、实际成都原谱和吉他音源，按钮变为“暂停真实乐谱播放”；正常暂停成功。再次试听后离开至我的谱、后退返回首页，无播放状态和隐藏host，不自动续播。本轮不声称可闻性或长期音频稳定性。
- 320/390/768/1366四种宽度，clientWidth与scrollWidth分别同为305/375/753/1351，无横溢出。390移动菜单展开后从真实“站点导航”进入练习，菜单aria-expanded=false、按压标记0。截图见 [移动菜单](navigation-mobile-menu.png)。
- 通过动效页真实radio选择轻柔/静止，完整导航到练习后data-motion分别gentle/off；轻柔位移0px、时长140ms。返回偏好页并还原跟随系统。真实系统reduce设备未执行，以控制器测试和CSS限制分别覆盖。
- 画廊/列表切换、命令面板中的“平台首页”导航均成功。工坊自写项目改临时标题，等界面确认保存，切练习后返回仍有临时标题，随后恢复原名并确认保存。未人为制造浏览器配额/挂起IDB；pending/error原生离页提示主要由保存边界行为测试覆盖。

### 原生动画兼容性与回退

实际Chrome155/IAB偶发 `InvalidStateError: ... Page already revealed`。另开只读标签复核未修改的 `master@939cf5f7`，已确认练习→我的谱→练习也出现同样两条错误；其后备份URL等待超时未计通过。候选早期也记录相同跳过，不能以CSS存在宣称每次原生动画都成功。

为此新增head早期pagereveal监听：只观察当前原生ready promise，成功由浏览器过渡；无过渡/拒绝时为main作opacity0.88到1、6px入场，轻柔仅140ms淡入，off/reduce关闭。pagehide使迟到结果失效，BFCache恢复重新处理。此方案遵循 [Chrome事件时序](https://developer.chrome.com/docs/web-platform/view-transitions/cross-document)，不会全局屏蔽错误或拦截导航。

最终构建另开空白匿名域名 `navigation-final-20261019.localhost:4338` 验证：练习→我的谱→练习均有data-navigation-entry=fallback，main实际animation为navigation-entry-full/0.28s，观测时opacity分别0.929143与0.939704，document.visibilityState=visible，说明实际入场在进行。两次导航仍记录同样的浏览器原生跳过错误，数量与相同步骤稳定基线一致；本次没有掩盖浏览器诊断。当前IAB只读DOM不提供getAnimations，未采集帧率。

偏好回退首轮在组件水合前直接点击，实际仍为full，没有计通过。最终以“当前实际效果”状态出现作为可操作依据，先确认radio使根data-motion变更，再完成跨页：gentle实际navigation-entry-gentle/0.14s，off为animation:none/0s且无fallback属性。随后还原跟随系统。最终静态截图见 [桌面页](navigation-final-desktop.png)，不把静态截图当作帧率证据。

### 未计为通过的测试尝试

第一轮完整类型检查有两处TS错误及一处Astro可选status错误，均修复后重新构建检查。第一版退避识别也未在真实HTTP生效：Prisma初始化连接池超时没有code/errorCode；补精确异常名/连接文本后，实际异常recognized=true，并新增排除P2024、认证、通用查询超时的回归测试。

一次浏览器脚本错误等待不存在的“画廊视图”按钮（实际为“画廊”radio），阻塞验证通道；重置控制会话后确认页面早已到达曲库，没有把超时算作成功。后续全部使用限时控件操作与完整URL确认。偏好页首个点击未确认导航、命令面板尝试不存在的“我的练习”选项均不计通过；最后按真实可用控件重做。没有绕过浏览器限制或操作用户标签。

### 检查与Git交付

最终源码冻结在 `1cda02f4`；完整候选命令均观察到退出码0：

| 命令 | 结果 |
| --- | --- |
| `npm test` | 419 total / 412 pass / 7数据库skip / 0fail，比稳定基线新增36项通过测试 |
| `npm run build` | 38.87s；既有AlphaTab大chunk、Prisma browser external告警保留 |
| `npm run typecheck`（build完成后） | TypeScript/Astro/Svelte 0 errors；Svelte 57既有warnings / 18 files；Astro 40 hints |
| `git diff --cached --check` | exit0，包含新增文件 |

没有独立Lint脚本，不宣称额外执行Lint。最终相同脚本的HTTP复核见 [http-final.json](http-final.json)：冷首页2013.10ms，连续吉他谱11.24/5.04ms，窗口内全部搜索7.87ms，Cookie吉他谱no-store/5.40ms。

计划提交 `cf5d40d9` / `1d99456b`，目录查询 `956a446c`，按需试听及离页边界 `5aee5801`，无错误码初始化超时修复 `0a01eae8`，导航及动画回退 `1cda02f4`。完整文件清单见 [changed-files.txt](changed-files.txt)。

### 稳定分支交付与清理

`feature/fast-page-navigation` 已以 `--no-ff` 本地合入 `D:\MIMIguitarweb-master-merge` 的 `master`，源码与候选证据合并提交为 `f605bd98ee8b1e26adcf59994cdec1e1c86f129f`。合并后顺序执行 `npm test` → `npm run build` → `npm run typecheck`，执行会话已结束且退出码0：419 total / 412 pass / 7数据库skip / 0fail；build11.66s；TypeScript/Astro/Svelte 0 errors、Svelte既有57 warnings / 18 files、Astro40 hints。之后仅补本节等交付文档，不变更已回归的源码。

已重启稳定预览 `http://127.0.0.1:4336`，不刷新用户当前标签。health200/alive；readiness503/not_ready，数据库及目录不可用如实报告。练习/工坊/动效/吉他目录均200；匿名目录包含预取与入场回退脚本，含Cookie请求no-store。三个必要音源HEAD均200，acoustic_guitar_fast.sf2与ukulele_fast.sf2各1,205,140 bytes，0.sf2为400,880 bytes。预览使用隔离不可达数据库，不是生产数据库恢复证据。

合并后同一Node脚本结果见 [http-master.json](http-master.json)：首页冷探测2031.24ms，吉他目录4.85/4.60ms，窗口内全部搜索7.21ms，Cookie吉他目录6.90ms/no-store。readiness独立真实探测仍等待2014.35ms并503，没有被目录退避跳过。精简稳定预览仅准备必要音源，目录演示曲目的全部乐谱/截图资源并未在此树补齐；本轮实际试听与浏览器验证在具有原只读资源链接的独立4338候选完成，不将两种资源环境混淆。

本轮自建浏览器标签已关闭，各自视口覆盖已还原；用户及既有标签保留。临时4338服务已主动停止，稳定4336继续运行。保护脚本在当前PowerShell7执行exit0：1023文件哈希差异0、402行Git状态差异0；原分支和既有未提交内容保留。曾误用Windows PowerShell5运行保护脚本，因JSON数组解析差异失败，未把该失败当作文件变更或通过，随后在正确运行时复核成功。没有推送、PR、部署或真实数据库变更。机器可读汇总见 [verification.json](verification.json)。

## 已知限制与下一步

冷启动/恢复探测仍需真实等待，不宣称所有请求瞬时完成。未执行真实Safari/iOS/Android触摸或长时间跨页音频验证；服务器多进程/生产数据库恢复应另做部署环境验证。
