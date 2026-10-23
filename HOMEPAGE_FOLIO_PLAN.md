# 首页最新曲谱「纸页乐谱册」改造计划（HOMEPAGE_FOLIO_PLAN.md）

> 分支：feat/homepage-paper-folio。配套 DEV_LOG 记录。

## 一、现状诊断
- 首页「最新吉他谱」「最新尤克里里谱」两个区块目前是纵向 TabCard 列表（窄卡片：小封面 + 标题 + 徽章）。
- 问题（用户反馈）：排版死板、无特色；希望有「纸质翻书/撕页」的浏览体验。
- 现有可复用资产：paper-grain-bg 纸纹、paper-emboss 浮雕、letterpress-ink 压印、3D book 动效、font-display(Fraunces)、refero token。

## 二、设计目标
把两个区块做成「摊开的乐谱册」：
- 每一首曲谱 = 一张暖纸谱页（撕纸边缘 + 折角 + 活字压印 + 页码）。
- 左右两栏 = 书册左右两页（吉他页 / 尤克里里页），中间自然留白如书脊。
- 交互：鼠标悬停纸页掀起 3D（rotateX + 抬升 + 阴影加深）；「上一页/下一页」翻页按钮 + 页码小点；点击整页进入详情。
- 移动端退化为可横滑的纸页卡片，保留翻页按钮。

## 三、技术方案

### 3.1 新组件 PaperFolioSection.svelte（客户端交互）
Props：
- `tabs: TabItem[]`（与 TabCardGrid 的 TabItem 同构）
- `title: string`（区块标题，如「最新吉他谱」）
- `allHref: string`（更多 → 链接）
- `accent: 'guitar' | 'ukulele'`（决定书册烫金/墨色点缀与印章字）
- `initialIndex?: number`

状态：
- `pageIndex`（当前展示第几首，范围 0..tabs.length-1）
- `isHovered`（整页悬停 → 3D 掀起）

渲染结构（每页）：
```
<article class="folio-page">
  <!-- 纸张底纹 paper-grain-bg + 撕纸边缘 -->
  <!-- 顶部：曲名(大衬线) + 艺人 -->
  <!-- 中部：封面截图(或乐谱icon) + 热度 -->
  <!-- 底部：调性/谱型/难度 徽章 + 页码 “— 3 —” -->
</article>
```

### 3.2 纸页质感（CSS，新增 folio 样式）
- 撕纸边缘：`clip-path` 多边形做轻微不规则轮廓（底部/侧边带锯齿感），配合 mask 渐变。
- 折角：右下角伪元素三角（暖纸高光 + 阴影）。
- 纸张：`paper-grain-bg` + 顶部暖光 + 边缘发丝线（hairline）+ 活字压印文字（letterpress-ink）。
- 堆叠：当前页下方用 2-3 张半透明「衬纸」错位叠放（transform: translateY/rotate），制造一叠纸页的厚度。
- 3D 掀起：`transform: perspective + rotateX(-4deg) translateY(-6px) scale(1.01)`，阴影加深；还原时回弹。
- 翻页动效：翻页时当前页 `fade+slide` 过渡（Svelte transition），页码小点高亮。

### 3.3 首页接入（src/pages/index.astro）
- 两个 `<section>` 内联列表替换为 `<PaperFolioSection client:load tabs={latestGuitar} title="最新吉他谱" allHref="/tabs?sort=0" accent="guitar" />` 与 ukulele 对应。
- 保留区块标题「更多 →」链接。

### 3.4 移动端
- 纸页宽度自适应（min-w / 比例），翻页按钮始终可见；无横向溢出（scrollWidth 校验）。

## 四、验收标准（Playwright）
1. 首页存在 2 个 `.folio-page` 纸页组件，各显示曲名/艺人/徽章。
2. 撕纸边缘 clip-path 存在（computed clip-path 非 none）；折角伪元素存在。
3. 翻页：点击「下一页」→ 标题/艺人变化、页码变化、页码点高亮；「上一页」可回退；首/末页按钮禁用状态正确。
4. 悬停纸页有 3D transform 变化（getComputedStyle transform 含 perspective/rotateX）。
5. 移动端 390px 无横向溢出、console/pageerror 零报错。
6. 桌面端 console/pageerror 零报错。
7. 截图证据归档 tests/evidence/homepage-folio/。
8. 回归：node --test 单测、npx astro build、master 冒烟。

## 五、风险与说明
- SSR 传 tabs 数组进 Svelte 组件需 JSON 序列化（Astro 自动处理 client:load）。
- 撕纸边缘 clip-path 在 headless 截图可见性：用 computed style 断言而非视觉。
- 翻页按钮用原生 button，键盘可达；不破坏现有导航与链接。
- 不删除 TabCard/TabCardGrid，仅首页两个区块换用新组件。
