# 纸页乐谱册动效升级计划（FOLIO_MOTION_PLAN.md）

> 分支：feat/homepage-folio-motion

## 一、现状问题（用户反馈）
- 当前 PaperFolioSection 只有：hover 3D 掀起 + 翻页时微弱位移淡出。
- 无入场动画、无翻页书卷感、无鼠标交互反馈、无扫光/衬纸/页码点等细节动效 → 显得静止、没有特色。

## 二、动效设计

### 1. 书卷翻页（核心）
- 状态机：phase = 'idle' | 'exiting' | 'entering'，flipDir = -1 | 1。
- 点下一页：当前页从右往左 rotateY(0 → -70deg) 翻出（origin-left），350ms；随后新页从左侧 rotateY(55deg → 0) 翻入（400ms）。
- 点上一页：方向镜像（rotateY +70deg，新页从右翻入）。
- 翻页期间禁用按钮（避免连点竞态）；完成后恢复。
- 实现：CSS 关键帧 + class 切换（exit-next/enter-next/exit-prev/enter-prev），perspective 容器 preserve-3d。

### 2. 鼠标 3D 倾斜跟随（tilt）
- 纸页 onpointermove 计算相对中心偏移 → rotateX(-py*10deg) rotateY(px*14deg)，平滑过渡。
- 悬停时叠加 translateY 抬升 + 阴影加深；离开回正。

### 3. 暖光扫过（shine sweep）
- 纸页内叠加渐变高光层，悬停或翻页时从左上到右下斜扫一次（opacity/translate 关键帧）。

### 4. 入场动画
- 首屏加载：纸页 fade+scale+translateY 浮现（0.5s），标题墨迹 blur-up（1.4s ink-draw 感）。
- 每次翻页进入时重放入场（新页可见即播放）。

### 5. 衬纸滑动
- 翻页时衬纸层整体轻微上移/回弹（模拟抽纸），与主纸页动画同步。

### 6. 页码点弹性
- 当前页点切换时 pop 弹性缩放（scale 1 → 1.5 → 1）+ 信号蓝拉长。

### 7. 常驻微动效
- 静止时纸页有极轻微呼吸（box-shadow/亮度 0.9-1 循环 6s），避免完全静止感；尊重 prefers-reduced-motion。

## 三、实现要点
- 全部 CSS 关键帧 + Svelte 状态切换，无外部动画库。
- phase 用 $state，翻页用 setTimeout 分段（350ms 切页 / 400ms 进入完成），翻页中忽略重复点击。
- tilt 用 CSS 变量 --rx/--ry 实时更新，transition 平滑。
- prefers-reduced-motion 下禁用所有动画。

## 四、验收
1. 翻页：exit 关键帧触发（animation-name 断言）、新页 enter 关键帧触发、页码变化、按钮在翻页中禁用。
2. tilt：pointermove 后 transform 含 rotateX/rotateY 变化。
3. 扫光层存在，悬停时 animation 运行。
4. 页码点 pop 动画存在。
5. 移动端无溢出、console/pageerror 零报错。
6. 截图证据 tests/evidence/homepage-folio-motion/。
7. 回归：node --test、astro build、master 冒烟。
