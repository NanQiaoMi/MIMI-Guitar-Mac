# 纸页乐谱册「撕页」效果设计（FOLIO_TEAR_OFF_PLAN.md）

> 分支：feat/folio-tear-off（基于回退真实翻页后的 master：c605a7f）

## 一、背景与方向
- 用户反馈：真实翻页（书脊 rotateY 翻转）效果不好 → 已 `git revert`（913da9f、a356eb3），回到 M10.10 动效版基线（27/27 + 18/18 通过）。
- 用户要求：完全重新设计翻页效果，要有创意有新意。
- 设计方向：**撕页**——与乐谱册「撕纸边缘」设计语言呼应。旧页像被手指从右上角掀起、沿对角线之字形撕裂，撕下的大块旋转飘落淡出，残片留在原地淡出，新页从下层浮现。

## 二、撕页动画设计（下一页）
1. **掀角（0-10%）**：撕下块右上角掀起（translate 微移 + rotateZ -2.5°），撕口已存在（静态 clip-path 之字形锯齿）。
2. **撕扯（10-33%）**：页面左右抖动 2 次（translateX ±5px），模拟撕扯。
3. **撕下飘落（33-100%）**：撕下块沿弧线飘落（先上后下：translate(16px,-14px) → (95px,150px) → (175px,400px)），rotateZ 至 -34°，scale 0.92，opacity 0，0.92s。
4. **残片**：face 用 clip-path 切成左上小块（撕口锯齿边），0.55s 原地淡出。
5. **下层承接**：under 目标页 under-settle 浮现（scale 0.985→1 + 亮度回升）。
6. 上一页：镜像（左上角撕起、飘向左下、残片右上小块、tear-fall-prev 反向）。

## 三、实现要点
- 撕口 clip-path：15 顶点之字形多边形（固定顶点数，静态存在，撕开过程用抖动表现）。
  - 下一页撕下块：(100%,0) → 之字形 13 点 → (0%,16%) → (0%,100%) → (100%,100%)；残片为左上小块。
  - 上一页：水平镜像（撕口从 (0%,0) 到 (100%,16%)）。
- 结构：tear-piece（翻页时条件渲染的撕下块副本，snippet 渲染 current 内容）+ face（残片类）+ under（承接）+ hit（交互覆盖层，翻页中 hit-lock 禁点）。
- 保留 hover 3D 倾斜 + hit 覆盖层方案（face 3D 变换不影响事件命中，无震荡）。
- FLIP_MS=940ms；reduced-motion 直接切页。

## 四、验收
1. 结构：初始无 tear-piece/under；hit 存在。
2. 翻页中：tear-piece 出现（内容=当前页）、face 有 tear-remain（残片）、clip-path 锯齿生效、tear-fall 动画运行、under 目标页就位、按钮禁用。
3. 飘落：tear-piece transform matrix 变化。
4. 翻页后：页码 1→2、face 恢复（无残片类）、tear-piece/under 消失、按钮恢复、呼吸恢复。
5. 上一页：tear-piece-prev + tear-fall-prev、翻回页码 1。
6. 保留 tilt/shine/dot/移动端/零报错。
7. 截图：掀角帧、飘落帧、翻后、idle、tilt、mobile。
8. 回归：node --test、astro build、master 冒烟。

## 五、V2 优化（feat/folio-tear-v2，用户反馈「还不是很好看」）
- 撕口动态展开：撕口不再静态存在——tear-rip 0.42s 关键帧把 19 顶点 clip-path 从「右上角小裂缝」插值到「全撕口」（tear-piece 与 face 残片同步展开，缝隙露出下层新页），撕开过程可见。
- 撕下纸片立体化：飘落中加 rotateX（0→18°）3D 姿态 + 投影（inset 白色毛边高光 + 外部纸影）+ 左右摆动轨迹（右→左→右），更像真实纸片。
- 残片颤动：撕口展开后残片 remain-shake 0.5s 颤动（±1.5px 微动）再淡出，不再生硬消失。
- 撕口锯齿加密（13→16 个撕口点），更细密真实。
- 总时长 0.42s 撕口 + 0.68s 飘落 = 1.1s，FLIP_MS=1130。
- 验收沿用 V1 39 项框架，新增 tear-rip 展开断言与更充分时序余量。

## 六、V3 升级（feat/folio-tear-v3，用户反馈「撕纸效果很简陋」）
- 完整撕纸流程（总 1.1s + 缓冲）：
  1. 捏角（0-0.42s）：右上角纸角元素（三角 clip-path）被掀起旋转（rotateZ -16° + 阴影），模拟手指捏起纸角；
  2. 拉扯：撕口展开期间 face 残片 scaleX(1.012) 鼓起（纸被拉扯的张力）；
  3. 变速撕开：tear-rip 用 cubic-bezier(0.7,0.05,0.85,0.35) 先慢后快（纤维阻力→突然撕开），19 顶点 clip-path 插值，撕口边白色毛边（inset 高光）；
  4. 纸屑飞散：5 片纸屑从撕口起点沿线飞散（各自随机方向/旋转/延迟）；
  5. 剥离卷曲：撕下块剥离时 scaleX 1.03-1.05（纸片卷曲拉伸）；
  6. 翻面飘落：tear-piece 双面结构（face 内容 + back 纸背 rotateY180），飘落中 rotateY 0→170° 翻面显示纸背，轨迹左右摆动 + 飘忽 + 渐小渐淡。
- 双面结构：tear-face/.tear-back 各自 clip-path 撕口多边形（容器 preserve-3d 不拍平，规避 clip-path grouping 拍平子元素 3D）。
- FLIP_MS=1300；验收沿用框架，新增纸角/纸屑/翻面断言。
