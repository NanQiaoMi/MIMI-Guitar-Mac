# 首页纸纹质感与背景音符高级化计划（HOMEPAGE_PAPER_REFINE_PLAN.md）

> 分支：feat/homepage-paper-refine。配套 DEV_LOG 记录。

## 一、现状诊断（代码级）

### 1. 纸纹现状（src/styles/global.css body + .paper-grain-bg）
- 三层径向渐变：角落暖光（0.85/0.75）+ 中心椭圆暖光（中间亮边缘暖棕 0.10-0.16）。
- 两层 SVG 噪点：细纤维（baseFrequency 0.8, octaves 3, 灰 alpha 0.05）+ 粗绒面 mottle（baseFrequency 0.16, octaves 2, alpha 0.045）。
- 问题：颗粒均匀、无方向性；缺乏真实手工纸的「纤维丝缕」「云絮斑驳」「页缘受光/落影」层次；两层噪点叠加偏平，放大后像标准颗粒噪点而非纸张。

### 2. 背景音符现状（两处）
- Hero 卡片内 MusicNoteParticles（ambient 版）：28 个音符，signal 蓝 #41a1cf 纯色实心 fillText，opacity 0.22，14-32px，向上漂移 + 摆动 + 旋转 + 鼠标排斥。
- 问题：纯色实心符号直接浮在纸面上，像「贴纸」不是「印在纸上」；旋转/摆动快、密度高、透明度一致，缺层次与景深；与全站纸书卷审美脱节。
- FullscreenPaperWatermarks：12 个固定浮雕水印音符（𝄞𝄢♫✦𝄐♬♭♯♪𝄡♮）已具 paper-emboss 质感，属「印」的效果，保留并微调。

## 二、优化目标
1. 纸纹升级为「真实手工棉纸」：纤维方向性 + 云絮斑驳 + 页缘光影 + 微细孔隙，肉眼可见但不喧宾夺主，卡片/正文仍清晰。
2. 背景音符从「实心贴纸」改为「压印水印/浮尘墨点」：低饱和暖墨/淡金/信号蓝点缀、深浅层次（近大远小、明暗呼吸）、运动变缓变柔，融入纸面。
3. 全站（body 与 .paper-grain-bg）纸纹一致升级，Hero 与普通页共用同一套「纸基」。

## 三、具体实施方案

### A. 纸纹（global.css）
1. 新增一层「纤维丝缕」：SVG feTurbulence baseFrequency 0.02 0.6（非各向同性 → 拉丝方向），fractalNoise octaves 5，feColorMatrix 低 alpha（~0.05），作为 body/paper-grain-bg 的第一层噪点。
2. 保留细纤维（0.8, octaves 3, alpha 0.04）作为颗粒层。
3. 新增「云絮斑驳」：baseFrequency 0.012, octaves 2, 更大尺度柔和 alpha（~0.06），模拟手工纸浆云斑。
4. 页缘光影升级：顶部暖光更明显（+10%）、底部新增暖棕落影渐变、两侧保留，整体让纸面有「拱起受光」感。
5. 性能：全部为 data-uri SVG 静态背景，无 JS；三层噪点用 background-image 叠加（线性渐变在前、噪点在后的顺序固定）。

### B. 背景音符（Hero 内 MusicNoteParticles ambient 版）
1. 配色：默认暖墨 #4a3f33（纸张墨色）+ 淡金 #b89a5e + 少量 signal 蓝 #41a1cf 点缀（约 15%），替代纯蓝。
2. 质感：canvas 绘制时用「低透明实心 + 细描边 + 极淡投影」制造压印感；或直接降低 globalAlpha 并给符号加轻微 blur/shadow，仿「浮尘压印」。
3. 层次与景深：符号大小区间 10-34px；透明度按大小分层（小/远更淡 0.08-0.2，大/近略深 0.15-0.32）；每个音符带独立呼吸相位。
4. 运动：速度降为 0.45，摆动幅度略增但频率降低（更飘）、旋转幅度减半（更安静），鼠标排斥保留但力度柔和。
5. 减少数量：28 → 20（避免「满屏音符」的杂乱感）。

### C. FullscreenPaperWatermarks
- 保持纸色浮雕，微调：默认色 #1c1917 → 暖墨 #3a332b，opacity 0.08-0.15 区间略降；非播放态去掉 signal 色发光（仅播放时保留）。

## 四、验收标准（Playwright + 像素采样）
1. body 与 .paper-grain-bg computed background-image 层数 ≥ 5（原 4 → 新 ≥6，含新增纤维/云絮）。
2. Hero 音符 canvas：采样到暖墨色（R≈60-90, G≈50-80, B≈40-65）与淡金色像素，纯 #41a1cf 大面积实心占比下降（贴纸感消除）。
3. 音符数量 20（通过注入计数或在画布截图抽样验证密度）。
4. 移动端 390px 无横向溢出；console/pageerror 零报错。
5. 截图证据：desktop home + hero 特写 + mobile，归档 tests/evidence/homepage-paper/。
6. 回归：node --test（单测，排除浏览器脚本）、npx astro build 通过。

## 五、风险与说明
- 多层噪点 background-image 叠加不影响布局/滚动性能（静态位图，GPU 合成）。
- Canvas 音符质感改进仅影响 Hero 卡片区域，不影响其它页面。
- 颜色采样需注意 headless 渲染确定性：颜色值断言用区间而非精确值。
- 最终观感仍需用户在浏览器确认（截图只能验证结构与颜色范围）。
