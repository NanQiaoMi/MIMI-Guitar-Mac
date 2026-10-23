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
    id: 'art-1',
    title: '吉他新手如何选一把趁手的入门琴？',
    category: '选琴指南',
    content: `对于初学吉他的朋友来说，选琴往往是第一道门槛。一把手感好、音色清澈的吉他能让你的练琴热情事半功倍。

1. 面单琴 vs 合板琴：预算允许的情况下，首选「单板吉他」，其面板随着弹奏开声，共鸣会越来越通透。
2. 弦距调节：出厂吉他的弦距若过高，容易按弦手指疼痛，建议将 12 品弦距调至 2.5mm~2.8mm 左右。
3. 桶型选择：D 桶型适合扫弦伴奏，低音浑厚；GA 桶型或 OM 桶型腰身更收拢，适合指弹与弹唱兼顾。`,
    views: 8920,
    createdAt: new Date('2026-01-10T10:00:00Z'),
  },
  {
    id: 'art-2',
    title: '从五线谱到六线谱：吉他指法快速视奏技巧',
    category: '视奏教程',
    content: `六线谱（Tablature）是吉他专属的指位记谱法。从上到下依次代表吉他的 1 弦（最细）到 6 弦（最粗）。

数字代表对应弦品位：
- 数字 0：空弦
- 数字 1：第 1 品
- 连线与滑音（Slide / Hammer-on）：注意手指的击弦与勾弦发力点。

每天坚持视奏练习 15 分钟，能迅速建立手指与谱面品位的直觉反射。`,
    views: 7430,
    createdAt: new Date('2026-01-08T14:30:00Z'),
  },
  {
    id: 'art-3',
    title: '大横按（F 和弦）按不住？试试这三个突破要领',
    category: '和弦进阶',
    content: `许多吉他初学者都会在 F 和弦遇到瓶颈，只要掌握正确的力学原理，横按其实非常省力：

1. 食指侧面贴弦：不要用手指正面的软肉，而是用食指稍稍往左倾斜的骨质侧面按弦。
2. 肘部下沉借力：依靠手臂的自然下垂重力带动食指贴紧琴颈，而不是单纯靠虎口死死捏紧。
3. 拇指放于琴颈中间：确保拇指正对中指位置，为手掌提供稳定的力学支点。`,
    views: 11200,
    createdAt: new Date('2026-01-05T09:15:00Z'),
  },
];
