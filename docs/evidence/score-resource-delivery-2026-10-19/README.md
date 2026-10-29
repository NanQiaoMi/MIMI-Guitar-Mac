# 原谱加载与资源交付验收

日期：2026-10-19。基线 `master@a140638e`，修复 `fix/score-resource-delivery`；计划 `8709dece`、资源工具 `09a1ae6c`、播放器与重试 `eb4f61fc`。

## 原因与修复范围

用户看到的网络提示在独立4336详情页复现：晴天原谱 `/storage/scores/1sdc49P3eKm.ibe` 返回404，主播放器和画卷都失败。原public文件存在；稳定public与dist仅132个soundfonts文件。见 [HTTP基线](baseline.json)、[浏览器错误](browser-before.json)、[原错误截图](before.png)。页面200、引擎存在、三个音源可用不足以证明谱面能打开；这是上一轮本地预览资源交付缺口。

准备工具将现有本地scores/xhe/screenshots/soundfonts只读复制到候选和稳定树的普通public/storage，保留独立副本；排除upload。逐文件SHA-256预检，已有冲突前置失败，无删除或覆盖；拒绝junction、源目标重合/嵌套、未知格式和空文件。候选原junction只移除链接本身，未操作原目录。构建后再次核对实际dist，额外检查演示目录及基础音源引用。完整大清单保存在忽略的tools/.cache，不将媒体入Git。

播放器与画卷共享文件请求边界：区分404/410、401/403、5xx、HTML200、空文件和网络/超时；未取得原件不再给同址下载链接，成功取回后的解码/结构/排版错误仍允许留存原件。明确重试使用reload；主播放器超时会取消本代加载，画卷重试/失败/卸载会释放旧实例和回调。

## 已观察到的验证

| 检查 | 候选结果 |
| --- | --- |
| `npm test` | exit0，432 total / 425 pass / 7数据库skip / 0fail |
| `npm run build` | exit0，45.24s；既有AlphaTab大chunk及Prisma external告警保留 |
| `npm run resources:check -- --source <original-storage> --public <candidate-public-storage> --dist <candidate-dist-storage>` | exit0；source/public/dist各32,595文件、554,546,235 bytes；missing/extra/different均0 |
| `npm run typecheck`，build之后 | exit0；TypeScript/Astro/Svelte零错误，Svelte既有57warnings/18files，Astro40hints |

资源分类：scores12,122、xhe4,122、screenshots16,219、soundfonts132。源库存摘要与准备前一致，摘要及结果见 [verification.json](verification.json)。不把文件存在或哈希一致等同于完整曲库/数据库恢复。

只读HTTP验证脚本见 [verify-http.mjs](verify-http.mjs)：`node docs/evidence/score-resource-delivery-2026-10-19/verify-http.mjs http://127.0.0.1:4338 D:/MIMIguitarweb/public/storage`。15份演示IBE、3音源、1截图、1文本谱共20次取件均200且哈希与原件一致；15份IBE实际解码并验证谱表结构，见 [http-candidate.json](http-candidate.json)。

实际浏览器：晴天主播放器20个SVG、画卷21页；尤克里里16个SVG，无加载alert且播放控件可用。只临时移开候选dist的晴天原谱制造真实404，准确提示、失效下载链接数0；原件按原哈希恢复后，分别点击“重试加载”和“重试排版”，恢复20个SVG与21页，不清浏览器缓存。未操作原目录或用户文件，见 [重试回执](retry-recovery-browser.json)、[尤克里里回执](ukulele-browser.json)。

在全新独立测试域名，通过真实filechooser导入仓库测试IBE，界面确认原件与播放版本已保存并加入待练；经“开始练习”进入个人谱，主谱面20个SVG，显式播放后tick从110推进至111193，再显式暂停为“播放”按钮。见 [练习回执](practice-browser.json)、[练习截图](practice-rendered.png)。这是独立测试资料，未向用户的127.0.0.1:4336资料库写入。

## 修正与限制

三名既有gpt-6-luna/max代理完成只读审查，工具草稿期间额度中断；主代理接手、修复草稿的缺失项结构和并发建目录问题并完成验证，不宣称代理完成全部实现。首轮类型检查有两处signal类型声明遗漏，修复后重新全量测试/构建/检查通过。首次用AX中文“选择文件”名称查询DOM文件输入，实际DOM名为“Choose File”，等待超时导致控制会话重置；按实际DOM名称及Promise.all重做成功，未将失败计为通过。

未执行真实数据库恢复、数据库集成7项、Safari及手机/平板真机、音频可闻性与长时间稳定性。个人upload目录未复制；旧远端发布脚本仅含server与client/_astro，本轮未执行或修改远端发布，不宣称线上资源恢复。

## master交付与最终清理

修复已本地no-ff合入master，源码与候选证据合并提交 `1e72c391187d83323b276106b65e2fd4765054f9`。master顺序执行全量测试、build、构建资源check、typecheck，完整会话退出码0：432 total/425 pass/7数据库skip/0fail；build60.93s；资源source/public/dist各32,595文件/554,546,235 bytes/missing-extra-different均0；TypeScript/Astro/Svelte零错误、既有57条Svelte警告/18files、Astro40hints。源库存摘要与候选准备前一致。之后只补交付文档与截图，不改已回归源码。

4336已重启并保留运行。15演示原谱及其它抽样共20项HTTP请求均200且哈希与原件一致，见 [http-master.json](http-master.json)。练习、工坊、吉他/尤克里里详情均200；health200/alive，readiness仍503/not_ready、数据库和目录不可用，音源3/3 ready，见 [master-service.json](master-service.json)。资源交付修复没有把数据库降级伪装成完整曲库。

原先报错的独立4336标签直接点击两处重试，不刷新/清缓存即恢复主谱与21页画卷，见 [原标签恢复](master-browser.json)；其窄视口产生47个主谱SVG，不能与桌面20个当作同宽度布局统计。另开新的4336标签确认最新客户端实际排版20个主谱SVG、21页画卷、播放控件可用，无加载alert、控制台error0，见 [新客户端](master-fresh-browser.json)、[恢复后截图](master-rendered.png)。原用户练习标签未导航、刷新或修改资料。

本轮QA标签9/10/11/12已关闭，保留已恢复的4336详情标签8供查看；既有标签1/2/3保留，没有动效/视口/网络模拟覆盖。临时4338服务主动停止，临时移开的候选文件已按原哈希恢复，无残留held文件。独立测试域名的导入夹具与用户127.0.0.1:4336资料隔离，没有清理用户浏览器资料。

最终原目录保护脚本在PowerShell7执行exit0：1023文件哈希差异0、402行Git状态差异0；原分支 `feature/complete-score-studio@f4ac8ece` 保留。未推送、创建PR、部署、改真实数据库或操作原上传目录。完整变更文件见 [changed-files.txt](changed-files.txt)；机器可读结果见 [verification.json](verification.json)。下一步独立恢复真实数据库及进行真机验证。
