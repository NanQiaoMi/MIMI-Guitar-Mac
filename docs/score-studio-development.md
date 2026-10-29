# 制谱工坊：功能、格式与维护说明

## 产品约定

制谱工坊用于新建吉他、尤克里里、贝斯谱，以及在既有乐谱上创建个人改编版本。曲库原谱保持不变；编辑内容先保存到当前浏览器或导出到用户设备，不会自动上传、同步到账户或公开发布。

编辑数据以“弦、品位、时值”为中心。五线谱和六线谱由同一批音符联动显示。当前提供鼠标和键盘逐拍录入，不提供与 TAB 分离的五线谱音高输入，也未接入 MIDI。

## 用户工作流

### 从空白谱开始

1. 点击“新建”，选择吉他、尤克里里或贝斯预设。
2. 在谱面上点击小节和拍位，或用方向键、Tab 移动编辑光标。
3. 选择音符时值，再用数字键录品位；在虚拟指板上点击也可录入。
4. 用工具栏添加附点、三连音、休止符、和弦、歌词及演奏技巧。小节拍数提示会标出欠拍或超拍。
5. 按空格试听，使用撤销/重做修正。
6. 编辑会写入本机草稿箱；Ctrl+S 可手动保存。用“保存 / 导出”生成工程文件、演奏文件、长图或 PDF。

### 基于曲库乐谱改编

1. 在曲目详情页选择“基于此谱改编”。
2. 工坊读取曲库原始文件，并转换当前可编辑的弦乐谱表。
3. 新工程使用“（个人改编）”标题，并记录曲库编号。保存只创建个人草稿，不修改曲库记录。
4. 导出菜单中的“下载导入时的原始文件”可取回服务端原谱。

如果转换器无法表示部分内容，会显示黄色转换报告。原文件继续可下载；用户应在确认预览内容后再把转换文件用于后续工作。

### 导入本机文件

1. 打开“草稿”并选择“导入谱面或工程文件”。
2. 文件解析成功后，原始字节先写入浏览器 IndexedDB，再替换当前编辑工程。
3. 如果解析失败或无法备份原文件，当前工程保持不变，并显示错误原因。
4. 原件下载从草稿箱上方的“保存 / 导出”菜单操作。清理浏览器网站数据会删除本机草稿和原件备份。

单文件上限为 30 MB。草稿使用 localStorage；浏览器空间不足时会明确提示，建议马上导出工程 JSON。

## 支持格式

| 操作 | 格式 | 说明 |
| --- | --- | --- |
| 导入 | 工坊工程 JSON | 保留可继续编辑的工程模型；旧版无 schemaVersion 的 JSON 会升级到版本 1。 |
| 导入 | AlphaTab 乐谱 JSON | 适用于 AlphaTab 结构化 score JSON。 |
| 导入 | `.ibe` | 支持 MIMI 自有 IBE 和曲库传统 AR IBE。 |
| 导入 | Guitar Pro `.gp3`、`.gp4`、`.gp5`、`.gpx`、`.gp`、`.gp7`、`.gp8` | 由 AlphaTab `ScoreLoader` 读取；实际可读范围受文件版本、损坏情况和 AlphaTab 支持范围影响。 |
| 导入 | MusicXML `.musicxml`、`.xml` | 由 AlphaTab 读取后转换为工坊弦乐模型。 |
| 导入 | AlphaTex `.tex`、`.alphatex` | 由 AlphaTab AlphaTex importer 读取。 |
| 导出 | 工坊工程 `.json` | 推荐作为可继续编辑的个人工程备份。 |
| 导出 | MIMI `.ibe` | 写入 MIMI magic、deflate 压缩与自有 XOR 编码。 |
| 导出 | Guitar Pro `.gp` | AlphaTab GP7 exporter 输出。 |
| 导出 | AlphaTex `.tex` | 可读的 AlphaTab 乐谱文本。 |
| 导出 | PNG、PDF | 从当前排版画布生成长图或 A4 分页文件。 |

当前没有 MIDI 导入、MusicXML 导出、服务器发布或账户同步功能。界面不应显示这些功能已经可用。

## 转换边界与原谱保护

工坊内部编辑模型包含多个弦乐音轨、每轨调弦/乐器/混音/变调夹、逐小节拍号/速度/段落/反复/房子，以及单一主声部的音符、和弦、歌词、附点、三连音、扫弦和若干演奏技巧。

以下内容可能无法完整表达，导入转换时会产生警告：

- 非弦乐音轨和没有调弦的谱表；
- 一个音轨中的其他谱表或复音声部；
- 超出当前弦数、24 品或基本时值的内容；
- 非三连音连音组、双附点、多个房子结尾；
- 模型尚未覆盖的延音、断奏、指法、装饰音、摇把、力度变化等效果。

重复的声部/演奏效果警告按音轨和类型归并；双附点、特殊连音和房子结尾等仍指出具体小节。报告最多展示 100 条，超出的条数会在最后一条提示中说明；原始谱仍可下载。不得把“已导入”解读成与 Guitar Pro / MusicXML 原文件无损往返。

本机文件原件位于 IndexedDB 数据库 `mimi-studio-originals` 的 `scoreFiles` object store；个人工程位于 localStorage。曲库原件仍由原曲库下载地址提供。删除个人草稿不会覆盖曲库原谱。

## 编辑和播放快捷键

| 按键 | 操作 |
| --- | --- |
| `0`–`9` | 输入品位；`0` 是空弦。输入 `1` 或 `2` 后继续输入第二位可录入 10–24 品。 |
| `↑` / `↓` | 在当前音轨琴弦间移动。 |
| `←` / `→`、`Tab` / `Shift+Tab` | 上一拍 / 下一拍。最后一拍继续前进会追加一小节。 |
| `Alt+1`–`Alt+6` | 全、二、四、八、十六、三十二分音符。 |
| `.`、`/`、`R` | 切换附点、三连音、休止符。 |
| `Delete` / `Backspace` | 删除当前拍、当前弦上的音符。 |
| `Shift+Delete` | 删除当前拍。 |
| `Insert` / `Shift+Insert` | 插入小节 / 插入一拍。 |
| `H`、`S`、`B`、`N`、`P`、`X`、`V`、`L` | 击勾弦、滑音、推弦、泛音、闷音、死音、颤音、延音线。 |
| `Space` | 播放 / 暂停。 |
| `Ctrl+Z` / `Ctrl+Y` | 撤销 / 重做。 |
| `Ctrl+S` | 保存到本机草稿箱。 |

重复循环目前是全曲循环；尚无自定义 A-B 小节范围循环。AlphaTab 原生播放器未就绪时会退回 Web Audio 简化试听，该备用引擎不等同于完整 SoundFont 轨道混音。

## 代码结构

- `src/lib/studio/studioScoreModel.ts`：StudioProject 模型、版本升级、纯编辑函数和 AlphaTex 文本生成。
- `src/lib/studio/studioScoreBridge.ts`：AlphaTab JSON / AlphaTex 与工坊模型转换，以及 IBE、GP7、AlphaTex、JSON 导出。
- `src/lib/studio/localScorePersistence.ts`：localStorage 草稿保存、恢复、迁移和草稿列表。
- `src/lib/studio/studioOriginalFileStore.ts`：IndexedDB 原始文件保管与下载。
- `src/components/studio/ScoreStudioApp.svelte`：编辑器状态、输入、保存、导入及导出协调。
- `src/components/studio/ScoreCanvas.svelte`：AlphaTab 预览、五线谱与 TAB 渲染、光标和播放交互。
- `src/components/studio/StudioGuide.svelte`、`ShortcutHelpModal.svelte`：应用内教程及快捷键说明。
- `src/pages/api/tabs/[id].ts`：曲库改编入口的只读曲目元数据。
- `src/pages/api/tabs/[id]/download.ts`：提供曲库原件下载。

`StudioProject.schemaVersion` 当前为 1。缺少版本字段的旧草稿按版本 1 归一化；遇到其他显式版本会拒绝载入，避免静默破坏未知格式。

## 维护与验收

修改转换逻辑时至少运行：

```powershell
node --test tests/studio-score-bridge.test.mjs tests/studio-local-persistence.test.mjs
npm run build
```

桥接测试覆盖真实 IBE 样本转弦乐工程、联动谱表和反复记号、GP7 导出回读、MIMI IBE 编解码及 schema 迁移。持久化测试覆盖旧草稿迁移、删除最新草稿后恢复上一份快照、避免快照重复显示和配额异常返回失败。

手工验收应从本机 `/studio` 页面完成：新建一个预设，输入音符/休止符，切换时值，撤销重做，试听并等待双谱表排版完成，保存后刷新恢复；另用 `.ibe` 和一个 GP/MusicXML 文件导入，检查转换警告、下载原件、个人副本另存及 PNG/PDF 导出。没有实际打开浏览器并完成这些步骤时，不得报告手工验收通过。
