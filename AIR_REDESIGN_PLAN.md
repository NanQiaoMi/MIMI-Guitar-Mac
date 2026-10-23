# 乐谱册区块 Air 克制化重设计（AIR_REDESIGN_PLAN.md）

> 分支：feat/homepage-air-refine
> 设计规范：D:\designmd\refero-styles\Air（Air — midnight sky through glass sculpture）

## 一、背景与方向（用户已确认）
- 用户反馈：撕页等花哨动效「不好看」，主页动效与设计不够高级。
- 用户提供 Air 设计规范，并确认方向：**保留暖纸品牌**，按 Air 的克制原则重做乐谱册；**切换动效改为克制淡入错位（stagger）**。

## 二、Air 规范核心原则（本区块应用）
| Air 原则 | 现状 | 改造 |
|----------|------|------|
| No elevation（无阴影） | 卡片 shadow-sm、lift 阴影、呼吸 box-shadow | 全部移除；层次靠 1px 细边框 + 背景对比 |
| Don't use gradients | 页缘暖光渐变层、衬纸渐变 | 移除渐变层；纸色用平色 |
| 细边框（1px） | border hairline 已有 | 保留；hover 边框微亮（信号蓝 30%） |
| 小圆角（卡片 12px） | 12px ✓ | 保持 |
| 克制动效 | 撕页（纸角/纸屑/翻面/飘落）、3D 倾斜、扫光、呼吸、弹性点 | 全部移除；改为 page-out/page-in + 元素 stagger |
| 克制 hover | 3D 掀起 + 阴影加深 | 2D 微抬 translateY(-2px) + 边框微亮 + 封面 scale 1.02（CSS :hover，无需 JS 状态） |

## 三、保留的暖纸品牌元素
- 撕纸边缘 clip-path（静态装饰）、paper-grain-bg 纸纹、Fraunces 衬线标题 + 活字压印（letterpress-ink）
- 衬纸堆叠 ×2（去阴影、平色）、曲谱信息徽章（调性/谱型/难度/热度）、封面截图
- 上一页/下一页 + 页码点（去弹性，改简单过渡）、「更多 →」下划线链接（Air: underline link）

## 四、新动效设计（克制、有秩序）
1. **切换**：旧页 page-out 0.24s（淡出 + 上移 6px）→ pageIndex 切换（{#key} 重挂载）→ 新页 page-in 0.4s（淡入 + 上浮 10px，cubic-bezier(0.16,1,0.3,1)）。
2. **stagger 错位**：封面（0.04s）→ 标题（0.10s）→ 艺人（0.16s）→ 徽章行（0.22s），各 0.45s fade-up。
3. **hover**：CSS :hover——translateY(-2px) + border-color 信号蓝 35% + 封面 scale(1.02)，transition 0.3s。
4. 翻页中按钮禁用防连点；FLIP_MS=240（旧页淡出后切页）；reduced-motion 直接切页。

## 五、简化收益
- 删除：tear-corner/tear-piece/tear-face/tear-back/tear-shred/tear-remain、folio-shine、folio-idle-breathe、folio-lift/tilting、dot-pop、liner-nudge、hit 覆盖层、JS hover 状态、JS 点击导航（a 原生 href 恢复）。
- 组件从 684 行精简到约 380 行；动效从「花哨堆砌」变为「轻、平滑、有秩序」。

## 六、验收
1. 结构：face 卡片、衬纸 ≥2、撕纸边缘 clip-path、无任何 tear-* 元素、无扫光/呼吸动画。
2. 切换：page-out 触发 → 页码 1→2 → 新页 page-in + 元素 stagger（animation-delay 递增）。
3. hover：CSS :hover 生效——transform translateY(-2px)、border-color 变化、封面 scale(1.02)。
4. 按钮翻页中禁用、完成后恢复；上一页回退。
5. 移动端无溢出、console 零报错。
6. 回归：node --test、astro build、master 冒烟。
