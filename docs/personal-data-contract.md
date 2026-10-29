# 个人数据集成契约

本文件约束本轮并行开发；类型以 `src/lib/personal/types.ts` 为准。数据和原件必须在同一 IndexedDB 事务提交，成功在 `oncomplete` 后通知。所有修改在 `mutatePersonalData` 中读取最新版本，不能用组件缓存覆盖整个资料。

当前个人资料 schema 为 2，新增独立 `practiceFragments`；StudioProject 的 schema 仍是 1，IndexedDB store 版本仍是 3。`PersonalDataSnapshot` 保留原始 schema 1/2 形状，validator 不修改输入；仓库读取旧资料后只在返回值补齐新 schema。备份预检先核验原始 data、原始 counts 和 SHA，再合并升级；不能在验摘要之前给旧 payload 补数组。v1/v2 指备份文件格式，与个人资料 schema 分开编号。manifest 和 data 的 schema 必须一致；旧程序不支持 schema 2 时应明确拒绝。

命名片段保存 scoreId、实际谱面 SHA-256、名称/独立备注、展开后的半开 tick 区间及可复用提速参数；不保存运行时圈数。名称和备注修改、删除都带 expectedUpdatedAt，在事务内拒绝旧标签覆盖。删除写入墓碑并随全量备份保存，恢复旧快照不复活；墓碑也占实体预算。移出待练不删除片段。片段冲突与谱面版本冲突使用稳定身份合并，并同步重映射曲谱引用。具体回归和已执行结果见[本轮记录](architecture-and-fragments-plan.md)。

仓库 `src/lib/personal/repository.ts` 对外提供：

```ts
readPersonalData(): Promise<PersonalData>
mutatePersonalData(mutator: (draft: PersonalData) => void, options?: PersonalMutationOptions): Promise<PersonalData>
readAsset(id: string): Promise<PersonalAsset | null>
subscribePersonalData(callback: () => void): () => void
hashBytes(bytes: Uint8Array): Promise<string>
```

mutator 必须同步；摘要/解析/联网在事务前完成。`expectedRevision` 用于恢复预检和乐观冲突判断，修改后 revision递增。传入的assets与资料一起原子落盘，id为SHA-256；校验引用完整。广播只通知重新读取，不把事件当成成功依据。服务端没有IndexedDB时不读写；UI明确加载失败，不回退到内存假成功。

score.id区分 `catalog:<id>` 与 `private:<originalHash>`；revision绑定实际可播放文件hash。不能把链接地址当永久版本。库谱初次加入可暂记 `unverified`，实际播放器加载后更新hash并使旧断点失效。私有谱保管原始asset和可播放IBE asset，完整GP音轨优先直接转AlphaTab JSON封装，不能经工坊单声部模型造成未经提示的丢失。

收藏和待练通过一次事务写score与引用；删除待练不删除原件或历史会话。练习保存采用稳定session/slice ID与单调sequence幂等upsert；旧检查点不能覆盖新检查点。断点只在真实谱版本、引擎就绪且有效时恢复，不自动播放。

`PlayerResume.speed` 为目标 BPM（20–300），不是播放倍率。引擎倍率由目标 BPM / 原生锚点 BPM 计算，保留原谱 tempo map。`tick` 与循环 `[startTick,endTick)` 使用引擎展开演奏位置；不能直接把反复小节的谱面 tick 当作第二次演奏的位置。有效练习时长是前台、持有独占音频焦点、引擎实际播放时的单调时钟差；不代表识别了用户真实演奏。

统一原件引用的id与旧工坊source.id一致；assets按hash共享。旧localStorage工程/历史及mimi-studio-originals只读迁移，不删除旧值。迁移中断可重试、损坏条目单列，不能标完成后静默漏项。工坊逐步切换到异步仓库接口，legacy同步函数仅为迁移与救援兼容。

备份必须覆盖 `PersonalData` 全部字段与被引用 asset，使用 schemaVersion、计数、大小和 SHA-256 预检。恢复先完整校验及预览，再按 `expectedRevision` 原子提交；预览后任何其他写入都会令预览失效并要求重新校验。生成、浏览器下载已发起、文件已保存在设备、恢复校验和恢复提交是不同状态。取消、缺卷、混合快照、篡改、配额不足或 revision 冲突都不能改变当前资料。取消或失败只清理本次 restore staging；过期 staging 可回收，但永不删除当前资料引用的 assets 或原件。

备份支持两个兼容格式：

- `mimi-personal-backup` v1 是单文件 JSON，附件用 Base64，完整文件最多 64 MiB。现有 v1 导出和恢复继续可用；超限时拒绝生成。
- `mimi-personal-backup-volume` v2 由一个 JSON manifest 和 0–128 个原生二进制 `.mibak2` 分卷组成。manifest 包含完整资料快照、实体/附件计数、附件分块目录和快照 SHA-256。每卷头记录格式版本、snapshot ID、序号/总卷数、负载长度、负载 SHA-256 和分块清单；manifest 与卷头必须完全匹配。每个附件分为不超过 8 MiB 的块，并单独校验块及完整附件 SHA-256。缺卷、重复卷、序号错误、混入其他 snapshot、长度错误、摘要不匹配或未声明数据都会在恢复前拒绝。

v2 的格式硬预算为：完整文件合计最多 1 GiB（包括 manifest、所有卷头和负载），manifest 最多 64 MiB，单卷负载最多 8 MiB、最多 128 卷，单附件最多 30 MiB，引用附件合计最多 927 MiB，最多 500 个被引用附件和 10,000 个资料实体。927 MiB 为附件负载预算，给 64 MiB manifest、128 个最大 256 KiB 卷头及前缀预留空间，并额外留 1 MiB 余量；因此附件、分卷数量和总文件上限可以同时成立。卷数按附件 ID 排序后分成 8 MiB 块，再以与导出一致的 next-fit 规则计算。仓库写入还限制资料 JSON 在 UTF-8 下不超过 60 MiB，为 manifest 与分块元数据预留 4 MiB。单次写入统一拒绝超过 30 MiB 的附件和不合法 MIME；引用附件字节或按规则计算的卷数若增长并越过上限，会在提交前返回明确错误。旧资料若已超过上限会保留，减少引用允许逐步整理；增长若继续越过预算会被拒绝，完整备份也会明确说明限制。

旧资料若仍超过任一备份预算，附件引用总字节或数量不得增长，即使新附件能放进已超限的最后一卷也会拒绝。等量等数附件替换、普通元数据编辑及减少引用仍可逐步整理；合并恢复与普通保存共用同一守卫。

个人 IndexedDB 从版本 2 升级到版本 3 时，会用 `assets` cursor 为既有附件逐条补充紧凑的 `{ id, size, mimeType }` metadata store，不读取整个附件集合到 JavaScript 内存，也不改写/删除原件。后续新增附件、metadata 和资料根记录在同一事务写入；版本切换会关闭旧页面的数据库连接并提示刷新。普通练习检查点若不改变附件引用集合，不读取附件 metadata；引用集合变化时只读取所需 metadata 计算字节/卷预算，不读取附件正文。缺失或无效的 metadata 会 fail closed。

v2 生成先校验资料及 revision，再使用 metadata 预估附件总量和准确卷数，之后逐附件/分块计算摘要并一次只构建一个卷；生成前后及每次按需生成分卷时都会复核 revision。界面每次只准备一个卷，给清单和每卷单独的下载入口，不触发连续自动下载。界面只显示下载已发起，不能证明浏览器已落盘；浏览器可能阻止后续文件下载。生成/恢复可取消。

v2 恢复先检查 manifest、所有选定分卷、序号和所有摘要。逐卷读取，每次最多读一个 8 MiB 负载，并逐附件暂存；已有同 hash 附件会校验并复用，不覆盖或删除。全量验证成功后才显示预览。确认恢复时以新 revision CAS，在一个 IndexedDB readwrite transaction 中先按 manifest metadata 复核合并后的字节/卷预算，再通过 staging cursor 逐条写入缺失 assets 与 metadata、删除本次 staging 并写入根资料；最后事务不等待 Blob 解码或 `arrayBuffer()`。取消、配额失败、损坏分卷、预算增长超限或并发修改会 abort 整个事务。空闲失败 staging 只按自己的 session 或过期时限回收，不触碰其他标签的 staging。

1 GiB 是协议允许的总文件硬上限，不是已验证容量承诺；本轮没有进行完整 1 GiB 真机读写测试。附件预算、卷大小、总文件大小和实体/manifest上限都必须继续在 UI 中明确呈现。

`PlayerResume` 对旧资料保持向后兼容，以下字段均为可选：`playbackRatio` 是播放速度倍率，必须为有限数 `[0.125, 8]`；`trackMix` 每个音轨 index 唯一且为 `0–1023`，音量 `0–100`、program `0–127`，mute/solo 为布尔值；`display.fontScale` 为 `0.6–1.6`，`chordMode` 为 `name|diagram`，`scoreDisplayMode` 为 `mixed|tab`，其余显示开关为布尔值。逐步提速目标 BPM 仍是 `20–300`；`nativeAnchorBpm` 是源谱 BPM，允许有限正值至 `1000`，以容纳原始谱面较快 tempo。恢复旧记录时缺少这些字段不构成错误。

2026-10-18 兼容补充：`useSourceCapo?: boolean` 为 true 时保留原谱每条 staff 的变调夹，不把主轨的数值覆盖到其他轨；为 false 或缺失时沿用已保存 `capo` 数值的绝对覆盖语义。旧断点的 0 不重新解释为“使用原谱”。`capo` 支持整数 -1–24，其中 -1 对应已有的降半调调弦控件。新字段参与断点内容去重并包含在 v1/v2 原有摘要协议内，无需改 schema 版本。

待练排序使用一个事务内的归一化顺序：活动队列在前、归档在后，两组保持稳定相对顺序，order 全局连续；恢复归档追加到活动队尾。移出待练保留曲谱、原件、历史会话和断点。曲库 placeholder 升为真实 SHA 仅能由当前选择代次的播放器完成字节/解码校验后授权；父层核对 sourceId/URL/format/asset 身份，精确匹配的晋升不重新挂载正在使用的播放器，真实资源或版本变化仍重新加载。

服务健康状态分成两种：`/api/health` 仅报告进程存活，不访问依赖；`/api/readiness` 检查 PostgreSQL、磁盘 migration 目录与已应用 migration、曲库状态，并只抽样至多 20 条曲谱和 20 条 XHE 本地引用。`unsampled` 单独报告抽样范围外的引用；抽样内缺失或不支持的路径会标记为 incomplete。Readiness 另行 stat 三个固定基础音源（acoustic guitar、ukulele 与 fallback）；此检查不扫描媒体目录、不联网，数据库不可用时仍单独返回音源状态。响应不包含服务器本地路径或原始错误。完整 DB readiness 仍需用专用 `mimi_platform_test` 跑 migrations 与 `npm run test:db` 验证；没有该数据库时只能报告未执行，不能把 liveness 或静态检查当作数据库通过。
