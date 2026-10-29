# MIMI Guitar 动效与视觉系统开发文档 V2 (Design & Motion System)

## 一、设计系统规范与视觉基准
严格遵循 `D:\designmd\refero-styles\Ui` 规范与现代顶级 Web 动效标准：

| 维度 | 规范标准 | 实现载体 |
| :--- | :--- | :--- |
| **色彩体系** | 极简单色调黑白灰（`#0a0a0a`, `#737373`, `#e5e5e5`, `#f5f5f5`, `#ffffff`）+ 音乐蓝点缀（`#41a1cf`） | `@theme` CSS 变量 |
| **圆角几何阶梯** | 交互胶囊/按钮/输入框 `18px`，卡片/面板/弹窗 `24px`，外层视口容器 `32px` | `--radius-pill`, `--radius-card` |
| **发丝边框与质感** | 1px 细发丝边框（`#e5e5e5`），磨砂玻璃拟态（`backdrop-filter: blur(16~24px)`），微双层柔和阴影 | `.glass-capsule`, `.glass-modal`, `.spotlight-card` |
| **物理动效引擎** | 物理弹簧阻尼模型（Spring Physics, `cubic-bezier(0.16, 1, 0.3, 1)`），GPU 硬件加速（`transform`, `opacity`） | Svelte 5 + Tailwind v4 + Canvas 2D |

---

## 二、六轮访谈核心决策记录

1. **页面覆盖**：全站系统级覆盖（首页、曲谱列表流、详情页控制舱、个人中心、全局路由与搜索）。
2. **动效基调**：Linear / Apple 级克制高级感，高帧率硬件加速，发丝微光跟踪，零主观打扰。
3. **播放控制舱**：底部悬浮磨砂胶囊 HUD，流体贝塞尔曲线声波可视化，音轨抽屉弹簧展开与 Solo/Mute 琥珀光。
4. **路由与微交互**：⌘K 全屏命令中心，共享元素微形变过渡，5段渐进发光 Pip 难度条，红心粒子爆炸与浮动 Toast。
5. **超级页脚与光影**：4列现代工程风 Mega Footer，24柱动态声波波浪，系统正常运行脉冲绿灯。
6. **Showcase 展台**：在 `/showcase` 增加实时参数调节器（Playground）与全家桶动效对比模块。

---

## 三、新增与重构核心组件清单

1. `src/components/player/FluidAudioWaveform.svelte`：高帧率 Canvas 2D 流体正弦/余弦声波律动组件。
2. `src/components/player/FloatingPlayerHUD.svelte`：滚动触发的底部悬浮磨砂胶囊播放控制台。
3. `src/components/CommandPalette.svelte`：⌘K 全局搜索与快捷操作命令面板。
4. `src/components/TabCardGrid.svelte`：支持 50ms 交错淡入与 FLIP 重排动画的曲谱卡片网格。
5. `src/components/showcase/*`：扩展全家桶展台模块与交互式参数调节器。
