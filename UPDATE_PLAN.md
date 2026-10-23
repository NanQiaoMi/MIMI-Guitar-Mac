# 更新计划（UPDATE_PLAN.md）

> 历史文档：本文仅记录M7对齐任务，不是当前排期。最新目标和验收以[个人练习平台开发计划](docs/platform-development-plan.md)及[任务清单](docs/platform-backlog-and-acceptance.md)为准。

> 本文档是 M7「对齐原站功能+交互」的落地版，与 GAP_REPORT.md 配套。里程碑执行遵循「功能分支 → 验证 → 合并 master」与「开发→验证→记录→验收」流程，每次开发后更新 DEV_LOG.md。

## 目标与优先级
- P0：账号中心路由对齐（0=收藏/1=创作中心/2=浏览记录/3=资料）。
- P1：数据扩充 ≥10000 首；首页重构（热门三 tab + 风格 + 难度矩阵 + 搜索框）；/searchResults 搜索页；导航补上传/账号下拉/搜索框；免费下载 .ibe；分享曲谱。
- P2：详情页信息区补全（标题格式/难度/歌词/搭配和弦/调弦格式）；文章排序分页与发布；静态页（agreementPolicy/uploadpolicy/countact-us）；页脚补全；上传 type 参数。
- P3（本档不做，记录）：短信验证码登录、品牌插画、Cerulean 饱和卡片、生产部署、计费。

## 里程碑任务清单

### M7.0 文档落地 ✅
- [x] GAP_REPORT.md（差距矩阵+证据）
- [x] UPDATE_PLAN.md（本文档）
- [x] 分支 feat/m7-parity

### M7.1 数据扩充
- [ ] 增强 tools/migrate.mjs：--target、--resume（checkpoint）、跳过已入库 id、列表页遍历至足够新候选
- [ ] 后台运行扩充爬取至 ≥10000 首（限流 567 退避 + PACE）
- [ ] 验收：入库数达标、无未处理错误、抽样渲染一致、首页/列表计数真实

### M7.2 账号中心与导航对齐
- [ ] /account/0=我的收藏、/account/1=创作中心、/account/2=浏览记录、/account/3=个人资料（复用组件换映射）
- [ ] 导航：上传入口、我的账号下拉（4 项+退出）、全局搜索框、登录·注册
- [ ] 未登录访问账号中心显示空态（不整页跳登录）
- [ ] /upload?type=guitar|ukulele 参数
- [ ] 验收：URL 映射、登录/未登录行为、Playwright 零报错

### M7.3 搜索页对齐
- [ ] /searchResults 路由：type/searchValue/sort/sheetForm/difficulty/page
- [ ] 艺术家/歌曲名称切换、难度/类型/排序筛选、吉他/尤克里里/文章三 tab+计数
- [ ] /search?q= 重定向；首页与导航搜索框指向 /searchResults
- [ ] 验收：搜索「晴天」三 tab 计数、筛选分页、零报错

### M7.4 首页对齐
- [ ] 热门 今日/本周/本月 tab 切换
- [ ] 风格区块（6 种）+ 难度矩阵（5 难度 × 4 谱型 + 吉他/尤克里里切换 + 计数）
- [ ] 首页搜索框（保留编辑风 hero）
- [ ] 验收：区块数据/切换/计数正确、移动端无溢出

### M7.5 详情页与播放器补齐
- [ ] 标题格式对齐；信息区补 难度/歌词/搭配和弦/调弦格式
- [ ] 分享曲谱（复制链接弹窗）
- [ ] 免费下载 .ibe（/api/tabs/[id]/download，登录后可用）
- [ ] 验收：标题/信息区一致、分享复制、.ibe 下载可解析回原谱

### M7.6 社区与文章对齐
- [ ] /article 加 sort=new|hot + 分页；/community 别名
- [ ] 发布文章（登录态，Markdown 编辑器，写入 articles 表）
- [ ] 验收：排序/分页、发布→列表→详情全流程

### M7.7 静态页与页脚补全
- [ ] /agreementPolicy、/uploadpolicy、/countact-us 别名
- [ ] 页脚：版权/客服邮箱、备案占位、网文许可占位、协议链接
- [ ] 验收：全部链接 200、零报错

### M7.8 视觉细节微调（refero）
- [ ] 字距：heading-sm -0.04em、40-54px -0.02em；交互/标签 500 权重
- [ ] 播放器控件 outlined action 风格核对（hairline、Signal Blue 描边、Dusk 实心）
- [ ] 验收：截图对照 refero 规范

### M7.9 回归与收尾
- [ ] 全站 Playwright（新增路由×桌面/移动）+ astro build + node --test + 冒烟
- [ ] DEV_LOG.md / PLAN.md 更新；合并 master + 主分支回归；证据归档 tests/evidence/m7/

## 风险与说明
- 数据扩充为长时间任务（原站限流 567），后台运行 + 断点续爬；完成时间取决于原站限流。
- 备案/许可证用占位文案，不冒用原站信息。
- 登录保持密码方式；短信验证码登录记入 GAP_REPORT 已知差异。
