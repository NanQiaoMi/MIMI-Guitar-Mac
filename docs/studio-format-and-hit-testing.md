# 工坊格式、练习版本与谱面定位

更新：2026-10-16。AlphaTab 版本：1.8.4。本文记录本轮代码行为与单测证据；Node 测试不能代替真实浏览器、触摸设备或打印驱动验收。

## 格式支持矩阵

| 方向 | 格式 | 当前行为与证据 |
| --- | --- | --- |
| 导入 | `.ibe` | 解码原站 IBE 和 MIMI IBE，再转换成工坊编辑模型。`tests/studio-score-bridge.test.mjs` 读取 `qingtian.ibe` 并核对曲目、小节、音符和转换警告。 |
| 导入 | Guitar Pro `.gp3`、`.gp4`、`.gp5`、`.gpx`、`.gp7`、`.gp8` | 通过 AlphaTab `ScoreLoader.loadScoreFromBytes` 解析；当前真实文件锚点是 `canon.gp5`。测试核对调弦 `[64, 59, 55, 50, 45, 40]`，以及源音符 `string=5, fret=19, realValue=78` 在 Studio 中变为第 2 弦、19 品，并能重新生成同一音高。其他 GP 版本接受同一解析路径，但本轮未分别提供 GP3/4/GPX/GP7/GP8 文件夹具。 |
| 导入 | MusicXML `.musicxml`、`.xml` | 通过 AlphaTab ScoreLoader。内联最小 MusicXML 夹具验证标准吉他调弦、B 弦第 7 品 F♯4（MIDI 66）、四分音符时值和 TAB 弦号。未验证复杂谱表、连音、扩展技法或多声部 MusicXML。 |
| 导入 | `.tex`、`.alphatex` | 通过 AlphaTab AlphaTex 解析。测试回读小节数、可编辑音符、反复开始和本工具写出的歌词文字。普通 `beat.text` 可能是演奏指示，缺少明确歌词字段时会按歌词保存并提示“拍文字按歌词保留，请核对演奏标记”；同一工程只显示一次该提醒。 |
| 导入 / 导出 | JSON | 导入支持原生 StudioProject JSON 和 AlphaTab score JSON；导出的是原生 StudioProject JSON。测试使用完整语义快照回读，不把仅能解析 JSON 当作通过。 |
| 导出 | MIMI IBE | 由 StudioProject 转为完整 AlphaTab 谱并封装为 MIMI IBE。测试解码后比较调弦、每个音符音高/弦/品、混合时值、附点、三连音、休止、和弦名、歌词、调号、反复与房子结尾。 |
| 导出 | Guitar Pro `.gp` | 实际内容是 AlphaTab Guitar Pro 7 导出。测试由 AlphaTab ScoreLoader 重新读取，再比较 Score 语义快照，包括音高、调弦、时值、和弦文字、歌词、调号和反复信息。 |
| 导出 | AlphaTex `.tex` | 实际内容由 AlphaTab AlphaTexExporter 生成。当前回读测试覆盖小节数、音符、反复开始和自制歌词；它不证明所有 Studio 字段都有 AlphaTex 等价表达。 |
| 不支持 | MIDI | 工坊文件导入明确拒绝 MIDI；它不在当前工坊导入器支持范围内。 |

Studio 是面向吉他谱的单声部编辑模型：每条可编辑音轨取第一个带有效调弦的谱表和每小节第一个声部；一拍可同时有多个弦上的音符。多声部、其他谱表、未建模音轨或不兼容时值不会被假装为完整可编辑副本，导入提醒会说明被省略或近似的部分，源文件仍单独保留。模型时值包括全音符到三十二分音符；单附点和 3:2 三连音可编辑，多重附点及其他连音比例会近似并提醒。弯音、滑音、击勾弦、泛音、闷音、死音、颤音、重音、幽灵音等已建模状态会进入编辑副本；复杂奏法的精确 GP/MusicXML 表达未在本轮逐项验证。

AlphaTab 1.8.4 的调弦数组在 GP 锚点中按高弦到低弦排列，Studio 继续使用同一顺序，不能反转数组。AlphaTab 内部 `Note.string` 是相反的编号方向，因此 Studio 弦号按 `弦数 + 1 - AlphaTab 弦号` 映射；真实 GP5 锚点证明转换后的音高仍为 78。MusicXML 夹具另以 AlphaTab 源 `Note.realValue=66` 作音高校验，避免只靠本工具自我往返抵消弦序错误。旧版已存工程没有足够字段判断弦序来源；受影响工程应从其保留的原始文件重新导入为副本，不自动猜测或批量反转。

AlphaTab `JsonConverter` 对部分母小节元数据存在丢失边界。IBE 写出后会显式恢复工程的调号、反复结束/次数及房子结尾；和弦名称通过隐藏的有效和弦记录跨过 IBE 清洗器。GP7 回读使用 AlphaTab `ScoreLoader` 直接检查 Score 对象，不使用会丢这些字段的 JsonConverter 作为唯一证据。原件不被导出流程覆盖。

普通小节写入 `repeatcount=0`；只有真正的反复结束小节写入工程的次数。AlphaTab 从 `repeatCount > 0` 推导反复结束，不能把 Studio UI 默认次数 2 写进所有小节。实际 MIDI 生成回归验证普通 4 小节恰为 15,360 tick；前两小节反复 3 次、另两小节一次恰为 30,720 tick。官方 GP JSON 缺少显式反复结束标记时，从实际次数恢复结束状态。文件和原始字节导入均按 GP/MusicXML/IBE 类型选择解析器。

## 工程加入练习及版本行为

工作室“保存并加入待练”和“我的谱”工程行都会先根据当前 StudioProject 生成完整可播放 IBE，并在写事务前计算 SHA-256。个人谱 ID 为 `project:<project.id>`，`source` 为 `project`，同时保存 `projectId`、`assetId` 与相同内容摘要的 `revision`；练习项引用该谱 ID。工程、可播放谱、播放附件和已导入原件在一个 IndexedDB 事务中一起提交。转换或摘要失败时不会显示成功；编辑器内存中的工程仍可导出。

保存按工程编辑器最初加载的 `updatedAt` 做比较并交换。转换/摘要期间不会绕过该版本检查；同页保存按队列顺序处理，且每次调用立即捕获当时的工程与原件快照，排队时后续编辑不会混入旧保存。其他标签已改工程时拒绝覆盖。后续保存已关联的工程会生成新的 IBE 附件并更新练习谱的 revision 与 assetId；既有会话/续练检查点仍引用旧谱版本，不套用新版 tick。当前不允许直接删除仍关联练习谱的工程，错误文案提示保留原件和已保存播放版本。

个人练习读取私有工程附件而不请求曲库下载接口。加载中若用户切换曲谱，过期异步结果会被忽略，旧 Blob URL 在替换或卸载时撤销。曲库谱仍走其原有真实资源路径。

## AlphaTab bounds 与坐标换算

Studio 开启 AlphaTab `core.includeNoteBounds`，选拍使用 `renderer.boundsLookup.getBeatAtPos(x, y)`，定位到单个音符时再用 `getNoteAtPos` 取得真实弦号。没有命中 bounds 时保持未命中，不按小节宽度平均猜拍位，也不按 SVG 竖线猜小节。AlphaTab 原生鼠标参数以整个 `canvasElement.element` 为坐标原点；Studio 将浏览器坐标换为 `clientX - surfaceRect.left`、`clientY - surfaceRect.top`，保留 CSS 像素的小数部分，不使用设备像素比换算。

`partialRender` 可为不同系统创建各自 SVG，但 renderer 的 bounds 坐标仍相对完整渲染表面。点击第二/第三系统时不能减去子 SVG 的局部原点，否则纵坐标会回到系统局部值而命中错误。`tests/studio-score-bounds.test.mjs` 覆盖完整表面原点为 `(180, 130)`、后续系统原点偏移 `(25, 850)`、命中点 `(50.5, 860.25)`、AlphaTab 弦号到 Studio 弦号映射及无命中行为。此项是 bounds helper 的合成单测；真实长谱点击、缩放与触摸仍需浏览器/设备验证。

## 导出失败与资源限制

PDF 逐页先将 SVG 编码成 JPEG，再添加到 PDF；任一页没有有效 `image/jpeg` 数据时立即 reject，且不会调用 `pdf.save`。全部页面都成功编码、添加后才保存；PDF 动态导入、渲染器销毁和隐藏容器清理均在错误路径覆盖。工坊 UI 只有 Promise 成功返回后才显示导出结果，失败显示错误。

导出渲染器使用独立滚动容器设置，等待当前谱的完整 `postRenderFinished`，不以首个 SVG 出现或固定延迟当作全部排版结束。独立 SVG 内嵌 Bravura、Cascadia 与中文字体，并内联音乐符号的字体样式，避免离开网页 CSS 后出现方框。字体缺失/损坏/超时会拒绝导出，可联网后重试。播放器按当前显示音轨导出；单个系统超过 A4 高度时明确拒绝，不能下载截断页。并发导出受隐藏容器所有权限制。

PNG 长图保持 794 像素宽、每页 1123 像素高，页面 JPEG 编码和最终 PNG 编码任一失败都会 reject，失败时不发起下载。上限为高度 16,384 像素和总面积 16,000,000 像素，因此当前每张图最多 14 页；更长谱应导出分页 PDF。下载提示只说明浏览器已发起下载，不能证明设备最终写入文件。

`tests/print-score-export.test.mjs` 注入第二页编码失败，确认错误可见且 PDF 从未保存；另覆盖所有页面编码成功才保存、空页面拒绝。该单测没有验证实际浏览器 Canvas、jsPDF 下载管理器、打印窗口或设备文件系统。

本轮工作区单测证据来自 `studio-score-bridge.test.mjs`、`studio-format-roundtrip.test.mjs`、`studio-score-bounds.test.mjs`、`studio-personal-persistence.test.mjs` 和 `print-score-export.test.mjs`。完整页面 build、浏览器长谱点击、PNG/PDF 实际下载和手机/平板真机结果以协调者本轮 fresh build 验收记录为准。

## 2026-10-16 fresh build 浏览器证据

以下是此前 fresh build、独立端口 4330 上已实际观察的工坊行为：

- 等待 AlphaTab 首帧就绪后再渲染，避免初始化期间的空白帧；移除 scoreLoaded 内嵌套 renderTracks 重绘后，反复重开、编辑并恢复标题仍只留下当前谱面的 4 个 SVG 片段，没有旧默认谱的残留片段。
- 音源 readiness 按全部音轨准备；四弦贝斯 program 33 使用独立乐器映射，不被识别为尤克里里。全部音轨音源准备完成前不切入原生播放；缺音源时显示未就绪，单独重试不会自动发声。
- 12 小节、吉他与贝斯双轨夹具在第二系统点击后定位到第 7 小节、第 2 拍、第 2 弦；谱面保持 4 个 SVG 片段。
- 导出的 GP 文件由 AlphaTab 实际回读；PDF 共 3 页 A4，经 Poppler 逐页检查；PNG 输出实测为 794 × 3369 像素。

这些是指定夹具与页面的浏览器/文件证据，不表示所有 GP/MusicXML 技法均无损，也不替代真机音频或打印驱动验收。最近新增的 Base 导航、搜索和练习收口尚未重跑浏览器测试，不能由上述工坊证据推断其通过。真实 iOS、Android、Safari、长时运行和完整 1 GiB 媒体压力测试仍未执行。