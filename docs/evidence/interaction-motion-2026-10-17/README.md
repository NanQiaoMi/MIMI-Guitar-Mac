# 交互动效 P1 验收证据

2026-10-17，独立本地构建 `http://127.0.0.1:4334`，IAB Chromium。测试使用自制 16 小节、2 音轨、60 BPM 工程；原源码与 Git 状态保护清单零差异，生产资料未参与写入。主分支生成类型时曾经依赖联接刷新原目录中被忽略的 Vite/Astro 缓存，此后主分支已改用独立依赖；此例外详见本轮计划，不能称整个原目录完全没有写入。

## 截图

| 文件 | 验证范围 |
| --- | --- |
| [01](01-mobile-320.jpg)、[04](04-motion-mobile-390.jpg) | 320/390px 体验主区域布局；不是动态帧率证据。 |
| [02](02-search-mobile-reduced.jpg) | 最终 320×740 reduce 搜索弹层；输入获得焦点、分类、结果内部滚动及可见关闭。 |
| [03](03-practice-mobile-edit.jpg) | 320px 实际片段编辑，保留播放器和本地数据。 |
| [05](05-motion-tablet-portrait.jpg)、[06](06-motion-tablet-landscape.jpg)、[07](07-motion-desktop.jpg) | 768×1024、1024×768、1366×900 的体验页主区域。 |
| [08](08-motion-desktop-expanded.jpg) | 最终桌面完整体验页，设置展开与纸页示例。 |
| [09](09-search-desktop.jpg)、[10](10-search-short-viewport.jpg) | 修正最大尺寸后的桌面搜索和 320×400 短视口搜索。 |
| [11](11-paper-folio-mobile.jpg) | 最终移动纸页示例，分页可见，下一页显示第二首与对应链接。 |
| [12](12-practice-reload-boundary.jpg) | 初载后无需先播放即可应用片段，进度已可操作，应用后保持暂停。 |

截图证明所列时刻的可见状态。早于末尾纸页示例接线的主区域截图仍只证明其画面内区域；不把截图未包含的部分当作已验证。

## 运行时记录

- `viewport-observations.json`：四种主区域视口的 DOM 几何；`viewport-320-final.json`：末尾 320px 纸页分页、页头搜索的实际 44px 目标和无横向溢出。
- `navigation-observations.json`：体验页→我的谱→练习→备份、后退/前进的页面终态、无残留 dialog/滚动锁、回到练习仍暂停。没有记录跨文档动画的中间帧；未在本轮重做 hash、新标签、下载或工坊脏草稿离页流程。
- `browser-raf-final-normal.json`：可信点击后，分段底片出现多个中间 transform。
- `browser-raf-final-reduced.json`：普通及 reduce 两种采样，reduce 分支底片不出现空间中间状态。
- `browser-raf-reduce-during-dialog.json`：打开弹层期间由普通切换 reduce，样本显示偏好 false→true，弹层落定为不透明且无 transform。
- `reload-boundary-before-fix.json`：收口导航发现的初载播放器边界问题及继续上次后的对照；`reload-boundary-after-fix.json`：最终修复后首次就绪，两进度均 max 61440 / enabled，未先播放或恢复；随后应用片段并键盘定位，仍暂停且无错误。
- `final-playback-continuity.json`：最后安全 Worker 事件修复后再次实际播放；tick 从 246 继续推进至 29082，期间开关音轨/音色/搜索，之后正常暂停、结束并保存。时间筛选后的最终重载运行错误为 0；不把旧失败构建的历史日志删除或当作新错误。

RAF 夹具为 `tools/motion-frame-probe.html`，只在独立构建临时复制为本地 QA 入口；不接入产品导航，不写应用存储或调用隐藏播放器 API。宿主/iframe 取样存在约 1 秒间隔，事件到首 RAF 也有延迟，所以不能由这些文件推断稳定 60/120fps。最多保留三次有限采样，非长期性能监控。

## 验收限制

浏览器视口模拟不等同真机触摸、iOS/iPadOS Safari、Android、虚拟键盘或屏幕阅读器。实际扬声器声音、两小时桌面/三十分钟移动播放、耗电与持续帧时、大容量恢复和生产环境仍未验收。自动化检查、数据库可用性与 Git 收口的最终结果见 [本轮计划](../../interaction-motion-plan.md)。
