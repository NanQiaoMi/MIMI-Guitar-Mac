/**
 * 离线/开发环境内置的高质量乐谱与文章演示数据
 * 确保在数据库服务不可用时，全站所有页面、播放器、和弦图谱与搜索功能依然 100% 完美可用
 */

export interface DemoTab {
  id: string;
  title: string;
  artist: string;
  category: 'guitar' | 'ukulele';
  difficulty: number;
  sheetForm: number;
  style?: number;
  key: string;
  bpm?: number;
  timeSig?: string;
  tuning?: string;
  heat: number;
  format: 'gp' | 'xhe';
  scoreUrl: string;
  screenshotUrl?: string;
  tags: string;
  publishDate: Date;
  viewCount?: number;
  favCount?: number;
}

export const DEMO_TABS: DemoTab[] = [
  {
    id: '1sdiYSwWo2S',
    title: '明天你好',
    artist: '牛奶咖啡',
    category: 'ukulele',
    difficulty: 1,
    sheetForm: 4,
    style: 101,
    key: 'C',
    bpm: 80,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 10240,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdiYSwWo2S.ibe',
    screenshotUrl: '/storage/screenshots/1sdiYSwWo2S.jpg',
    tags: '["牛奶咖啡","治愈","流行","尤克里里"]',
    publishDate: new Date('2026-01-16T08:00:00Z'),
  },
  {
    id: '1sdc49P3eKm',
    title: '晴天',
    artist: '周杰伦',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 101,
    key: 'G',
    bpm: 80,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 12650,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdc49P3eKm.ibe',
    tags: '["周杰伦","经典","流行","六线谱"]',
    publishDate: new Date('2026-01-15T08:00:00Z'),
  },
  {
    id: '1sdiivPR3YW',
    title: '老男孩',
    artist: '筷子兄弟',
    category: 'guitar',
    difficulty: 1,
    sheetForm: 4,
    style: 103,
    key: 'C',
    bpm: 80,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 9780,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdiivPR3YW.ibe',
    tags: '["筷子兄弟","民谣","经典","六线谱"]',
    publishDate: new Date('2026-01-14T08:00:00Z'),
  },
  {
    id: '1sdjKw3nhA0',
    title: '反方向的钟',
    artist: '周杰伦',
    category: 'guitar',
    difficulty: 3,
    sheetForm: 4,
    style: 101,
    key: 'B',
    bpm: 86,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 9720,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdjKw3nhA0.ibe',
    tags: '["周杰伦","流行","经典","指弹"]',
    publishDate: new Date('2026-01-13T08:00:00Z'),
  },
  {
    id: '1yDFAg9Z3mU',
    title: '后来',
    artist: '刘若英',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 101,
    key: 'Eb',
    bpm: 75,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 8340,
    format: 'gp',
    scoreUrl: '/storage/scores/1yDFAg9Z3mU.ibe',
    tags: '["刘若英","经典","指弹独奏"]',
    publishDate: new Date('2026-01-12T08:00:00Z'),
  },
  {
    id: '1sdixfUd4Vc',
    title: '卡农',
    artist: 'Johann Pachelbel',
    category: 'guitar',
    difficulty: 4,
    sheetForm: 2,
    style: 105,
    key: 'D',
    bpm: 80,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 7120,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdixfUd4Vc.ibe',
    tags: '["古典","独奏","指弹","卡农"]',
    publishDate: new Date('2026-01-10T08:00:00Z'),
  },
  {
    id: '1yDFB6u7GnQ',
    title: '达尔文',
    artist: '林俊杰',
    category: 'guitar',
    difficulty: 3,
    sheetForm: 4,
    style: 101,
    key: 'Gb',
    bpm: 68,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 6890,
    format: 'gp',
    scoreUrl: '/storage/scores/1yDFB6u7GnQ.ibe',
    tags: '["林俊杰","蔡健雅","流行","指弹"]',
    publishDate: new Date('2026-01-09T08:00:00Z'),
  },
  {
    id: '1sdcV2zsRCC',
    title: '大海',
    artist: '张雨生',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 101,
    key: 'Eb',
    bpm: 80,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 6210,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdcV2zsRCC.ibe',
    tags: '["张雨生","经典","流行"]',
    publishDate: new Date('2026-01-07T08:00:00Z'),
  },
  {
    id: '1sdbywiXwXY',
    title: '平凡之路',
    artist: '朴树',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 103,
    key: 'A',
    bpm: 85,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 6870,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdbywiXwXY.ibe',
    tags: '["朴树","民谣","弹唱","经典"]',
    publishDate: new Date('2026-01-08T08:00:00Z'),
  },
  {
    id: '1yOhtb1c9I0',
    title: 'Hello',
    artist: 'Adele',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 101,
    key: 'G',
    bpm: 82,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 5870,
    format: 'gp',
    scoreUrl: '/storage/scores/1yOhtb1c9I0.ibe',
    tags: '["Adele","欧美","经典","流行"]',
    publishDate: new Date('2026-01-06T08:00:00Z'),
  },
  {
    id: '20yD5s1qZ06',
    title: '斑马斑马',
    artist: '宋冬野',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 103,
    key: 'G',
    bpm: 65,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 6210,
    format: 'gp',
    scoreUrl: '/storage/scores/20yD5s1qZ06.ibe',
    tags: '["宋冬野","民谣","经典"]',
    publishDate: new Date('2026-01-07T08:00:00Z'),
  },
  {
    id: '20kPMjR5xHF',
    title: '稻香',
    artist: '周杰伦',
    category: 'guitar',
    difficulty: 1,
    sheetForm: 4,
    style: 101,
    key: 'G',
    bpm: 70,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 6890,
    format: 'gp',
    scoreUrl: '/storage/scores/20kPMjR5xHF.ibe',
    tags: '["周杰伦","流行","扫弦"]',
    publishDate: new Date('2026-01-09T08:00:00Z'),
  },
  {
    id: '1sdikNKaVJg',
    title: '成都',
    artist: '赵雷',
    category: 'guitar',
    difficulty: 1,
    sheetForm: 4,
    style: 103,
    key: 'D',
    bpm: 76,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 7350,
    format: 'gp',
    scoreUrl: '/storage/scores/1sdikNKaVJg.ibe',
    tags: '["赵雷","民谣","流行","成都"]',
    publishDate: new Date('2026-01-11T08:00:00Z'),
  },
  {
    id: '21LT7VB9EGY',
    title: '加州旅馆',
    artist: 'Sungha Jung',
    category: 'guitar',
    difficulty: 4,
    sheetForm: 2,
    style: 105,
    key: 'C',
    bpm: 80,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 9200,
    format: 'gp',
    scoreUrl: '/storage/scores/21LT7VB9EGY.ibe',
    tags: '["Eagles","指弹","神作","加州旅馆"]',
    publishDate: new Date('2026-01-05T08:00:00Z'),
  },
  {
    id: '1wcinbxar8D',
    title: '真的爱你',
    artist: 'Beyond',
    category: 'guitar',
    difficulty: 2,
    sheetForm: 4,
    style: 101,
    key: 'C',
    bpm: 84,
    timeSig: '4/4',
    tuning: 'Standard',
    heat: 8800,
    format: 'gp',
    scoreUrl: '/storage/scores/1wcinbxar8D.ibe',
    tags: '["Beyond","摇滚","经典","粤语"]',
    publishDate: new Date('2026-01-04T08:00:00Z'),
  },
];

export interface DemoArticle {
  id: string;
  title: string;
  category: string;
  content: string;
  views: number;
  createdAt: Date;
}

export const DEMO_ARTICLES: DemoArticle[] = [
  {
    id: 'art-player',
    title: '把乐谱变成声音：MIMI 交互播放器深度剖析与跟练指南',
    category: '软件教程',
    content: `# 导言：为什么数字互动乐谱能让练琴效率倍增？

在传统纸质谱或静态 PDF 练琴时，琴友们往往面临三大痛点：听不出实际节奏与拍点、遇到生僻音符反复数格子、复杂小节难以跟上原速。

MIMI Guitar 的核心交互播放器基于开源引擎 AlphaTab 深度重构，配合 Web Audio 原生合成与高保真真实采样，将传统的静态乐谱升级为全维度、可交互、可视觉化的智能练琴工作台。

---

## 核心构造：播放器四大交互视窗

1. 顶部流体波形条（Fluid Audio Waveform）：实时动态声浪预览。
2. 60FPS 垂直/水平自适应曲谱视窗（Manuscript Canvas）：平滑跟谱无缝滚动。
3. 浮动控制舱（Floating Player HUD）：集中调速、变调夹、节拍器与 A-B 循环。
4. 底部木质虚拟指板（Virtual Fretboard）：指位光标与音符火花实时映射。

---

## 高效跟练技巧

- 变速不调音（0.5x~1.5x）：慢速抠细节，音准音色不变。
- A-B 区间循环攻坚：精准突破 2~4 个难点小节。
- 变调夹即时试听：无需真夹即可预览调高效果。
- 虚拟指板即时试听：点击品位即响真琴原声。

> [!TIP] 建议
> 练琴前开启预备拍，从容做好第一指位准备。`,
    views: 8420,
    createdAt: new Date('2026-08-15T09:00:00Z'),
  },
  {
    id: 'art-studio',
    title: '制谱工坊 PRO 快速上手：从零创作你的第一首数字吉他谱',
    category: '软件教程',
    content: `# 创作你的乐章：制谱工坊 PRO 简介

全键盘驱动 + 视听即时联动，像打字一样流畅写谱。

---

## 四步制谱全流程

1. 新建工程设置调号拍号与 BPM。
2. 键盘极速录入音符：方向键移动，数字 0~24 录入品位，数字 1~6 切换时值，空格试听。
3. 和弦调色板与指板库快速置入标准指型。
4. 歌词抽屉排版与段落蓝图结构化编配。

> [!NOTE] 导出支持
> 支持一键导出 Guitar Pro (.gp) 格式或本软件数字谱。`,
    views: 6310,
    createdAt: new Date('2026-08-14T14:30:00Z'),
  },
  {
    id: 'art-practice',
    title: '片段练习法：如何利用「我的练习」攻克高难度指弹小节',
    category: '琴房心得',
    content: `# 为什么整首通弹效率低？

从头通弹容易强化错误肌肉记忆。攻破瓶颈的关键在于难点小节切片。

---

## 攻坚三步法

1. 精准切片（Measure Slicing）：将难点小节存入独立练习题库。
2. 阶梯提速（BPM Ladder）：从 60 BPM 起步，每次达标自动提升 3~5 BPM。
3. 练琴日志复盘：离线精确记录练习时长与循环遍数。

> [!TIP] 每日 20 分钟建议
> 5分钟热身，10分钟攻坚单一片段，5分钟整曲合奏。`,
    views: 5980,
    createdAt: new Date('2026-08-13T16:00:00Z'),
  },
  {
    id: 'art-tab',
    title: '如何读懂六线谱（TAB 谱）：从零基础到盲按指板',
    category: '乐理视奏',
    content: `# 六线谱的本质：琴弦物理镜像

六条线对应吉他 1 弦到 6 弦。口诀：上细下粗，抬头看谱低头弹弦。

---

## 技巧符号解构

- 0 表示空弦，数字表示品位，纵向为和弦。
- h (Hammer-on) 击弦
- p (Pull-off) 勾弦
- / (Slide) 滑音
- b (Bend) 推弦
- ~ (Vibrato) 颤音

先读节奏打拍子，再上手摸琴弦。`,
    views: 9820,
    createdAt: new Date('2026-08-12T10:00:00Z'),
  },
  {
    id: 'art-capo',
    title: '变调夹（Capo）神技与人声定调公式：唱准每一首歌',
    category: '演奏技巧',
    content: `# 变调夹：一把吉他唱遍全天下的秘密武器

临时移动琴枕，用最熟悉的指型唱准每一个调。

---

## 速查公式

- D 调：C 调指法 Capo 2 品
- E 调：C 调指法 Capo 4 品
- F 调：C 调指法 Capo 5 品（女生翻唱男生歌首选）
- A 调：G 调指法 Capo 2 品

注意靠近品丝 2mm 夹持，夹好后轻拨校音。`,
    views: 8150,
    createdAt: new Date('2026-08-11T11:20:00Z'),
  },
  {
    id: 'art-barre',
    title: '大横按（F 和弦）突破指南：告别虎口酸痛的杠杆力学',
    category: '演奏技巧',
    content: `# 为什么大横按又痛又发闷？

横按靠的是手臂下沉重力，而不是虎口死捏！

1. 食指微侧 15 度用骨质触弦。
2. 手肘自然下沉向后拉，解放大拇指。
3. 先在 5 品练 A 横按，再逐品移回 1 品。

坚持 7 天，虎口不再酸痛，和弦清脆如铃。`,
    views: 10560,
    createdAt: new Date('2026-08-10T15:00:00Z'),
  },
  {
    id: 'art-ukulele',
    title: '尤克里里与吉他双修：四弦与六弦视奏与编配异同',
    category: '乐理视奏',
    content: `# 尤克里里与吉他一脉相承

尤克里里相当于吉他 Capo 5 品后的前 4 根琴弦，高 G 回入定弦清脆跳跃。

- 吉他 D 指型 ➡️ 尤克里里 G 和弦
- 吉他 G 1弦指型 ➡️ 尤克里里 C 和弦
- 顶部导航点击「尤克里里」无缝切换四线谱。`,
    views: 6780,
    createdAt: new Date('2026-08-09T18:20:00Z'),
  },
  {
    id: 'art-backup',
    title: '离线优先与数据安全：个人谱库、备份卷与本地 SQLite 架构指南',
    category: '琴房心得',
    content: `# 数据属于用户：本地优先架构哲学

- 本机 SQLite 毫秒级零延迟读取。
- 离线 IndexedDB 草稿自动暂存。
- 「数据与备份」一键导出独立 JSON 备份卷，换机迁移零丢失。`,
    views: 5210,
    createdAt: new Date('2026-08-08T12:00:00Z'),
  },
  {
    id: 'art-1',
    title: '吉他新手如何选一把趁手的入门琴？',
    category: '选琴指南',
    content: `选琴三要素：
1. 面单琴优先：共鸣越弹越通透。
2. 弦距调节：12 品弦距建议 2.5mm~2.8mm。
3. 桶型选择：D 桶浑厚适合扫弦，GA/OM 桶平衡适合指弹。`,
    views: 8920,
    createdAt: new Date('2026-01-10T10:00:00Z'),
  },
];
