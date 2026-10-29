/**
 * 128 款 General MIDI 标准全乐器库与分类体系
 * 覆盖钢琴、吉他、贝斯、管弦乐、合成器、民族特色与打击特效
 */

export interface GMInstrumentInfo {
  program: number;
  name: string;
  enName: string;
  category: string;
  icon: string;
}

export const GM_CATEGORIES = [
  '常用吉他与弹拨',
  '钢琴与键盘',
  '贝斯族',
  '弦乐与管弦',
  '铜管与木管',
  '合成主音与铺底',
  '民族特色乐器',
  '打击乐与特效',
] as const;

export const ALL_GM_INSTRUMENTS: GMInstrumentInfo[] = [
  // 钢琴 (0-7)
  { program: 0, name: '原声大钢琴', enName: 'Acoustic Grand Piano', category: '钢琴与键盘', icon: '🎹' },
  { program: 1, name: '亮音大钢琴', enName: 'Bright Acoustic Piano', category: '钢琴与键盘', icon: '🎹' },
  { program: 2, name: '电钢琴 (柔和)', enName: 'Electric Grand Piano', category: '钢琴与键盘', icon: '🎹' },
  { program: 3, name: '酒吧钢琴', enName: 'Honky-tonk Piano', category: '钢琴与键盘', icon: '🎹' },
  { program: 4, name: '电钢琴 1 (Rhodes)', enName: 'Electric Piano 1', category: '钢琴与键盘', icon: '🎹' },
  { program: 5, name: '电钢琴 2 (DX7/合唱)', enName: 'Electric Piano 2', category: '钢琴与键盘', icon: '🎹' },
  { program: 6, name: '羽管键琴 (大键琴)', enName: 'Harpsichord', category: '钢琴与键盘', icon: '🎹' },
  { program: 7, name: '古钢琴 (Clavinet)', enName: 'Clavinet', category: '钢琴与键盘', icon: '🎹' },

  // 色彩打击乐 (8-15)
  { program: 8, name: '钢片琴', enName: 'Celesta', category: '打击乐与特效', icon: '🔔' },
  { program: 9, name: '钟琴 (铁琴)', enName: 'Glockenspiel', category: '打击乐与特效', icon: '🔔' },
  { program: 10, name: '八音盒', enName: 'Music Box', category: '打击乐与特效', icon: '🔔' },
  { program: 11, name: '颤音琴 (电颤琴)', enName: 'Vibraphone', category: '打击乐与特效', icon: '🔔' },
  { program: 12, name: '马林巴木琴', enName: 'Marimba', category: '打击乐与特效', icon: '🪵' },
  { program: 13, name: '木琴 (Xylophone)', enName: 'Xylophone', category: '打击乐与特效', icon: '🪵' },
  { program: 14, name: '管钟 (Tubular Bells)', enName: 'Tubular Bells', category: '打击乐与特效', icon: '🔔' },
  { program: 15, name: '扬琴 (Dulcimer)', enName: 'Dulcimer', category: '民族特色乐器', icon: '🪕' },

  // 风琴 (16-23)
  { program: 16, name: '音栓管风琴 (Drawbar Organ)', enName: 'Drawbar Organ', category: '钢琴与键盘', icon: '🎹' },
  { program: 17, name: '打击感风琴 (Percussive Organ)', enName: 'Percussive Organ', category: '钢琴与键盘', icon: '🎹' },
  { program: 18, name: '摇滚风琴 (Rock Organ)', enName: 'Rock Organ', category: '钢琴与键盘', icon: '🎹' },
  { program: 19, name: '教堂管风琴 (Church Organ)', enName: 'Church Organ', category: '钢琴与键盘', icon: '🎹' },
  { program: 20, name: '簧风琴 (Reed Organ)', enName: 'Reed Organ', category: '钢琴与键盘', icon: '🎹' },
  { program: 21, name: '手风琴 (Accordion)', enName: 'Accordion', category: '钢琴与键盘', icon: '🪗' },
  { program: 22, name: '口琴 (Harmonica)', enName: 'Harmonica', category: '铜管与木管', icon: '🎵' },
  { program: 23, name: '探戈手风琴 (Bandoneon)', enName: 'Tango Accordion', category: '钢琴与键盘', icon: '🪗' },

  // 吉他族 (24-31)
  { program: 24, name: '古典尼龙弦吉他', enName: 'Acoustic Guitar (nylon)', category: '常用吉他与弹拨', icon: '🪵' },
  { program: 25, name: '民谣钢弦木吉他', enName: 'Acoustic Guitar (steel)', category: '常用吉他与弹拨', icon: '🎸' },
  { program: 26, name: '爵士空心电吉他', enName: 'Electric Guitar (jazz)', category: '常用吉他与弹拨', icon: '🎸' },
  { program: 27, name: '清音电吉他 (Clean)', enName: 'Electric Guitar (clean)', category: '常用吉他与弹拨', icon: '⚡' },
  { program: 28, name: '闷音电吉他 (Muted)', enName: 'Electric Guitar (muted)', category: '常用吉他与弹拨', icon: '⚡' },
  { program: 29, name: '过载摇滚电吉他 (Overdrive)', enName: 'Overdriven Guitar', category: '常用吉他与弹拨', icon: '🔥' },
  { program: 30, name: '失真重金属电吉他 (Distortion)', enName: 'Distortion Guitar', category: '常用吉他与弹拨', icon: '🔥' },
  { program: 31, name: '吉他自然泛音 (Harmonics)', enName: 'Guitar Harmonics', category: '常用吉他与弹拨', icon: '✨' },

  // 贝斯族 (32-39)
  { program: 32, name: '原声木贝斯 (Acoustic Bass)', enName: 'Acoustic Bass', category: '贝斯族', icon: '🎻' },
  { program: 33, name: '指弹电贝斯 (Finger Bass)', enName: 'Electric Bass (finger)', category: '贝斯族', icon: '🎸' },
  { program: 34, name: '拨片电贝斯 (Pick Bass)', enName: 'Electric Bass (pick)', category: '贝斯族', icon: '🎸' },
  { program: 35, name: '无品电贝斯 (Fretless Bass)', enName: 'Fretless Bass', category: '贝斯族', icon: '🎸' },
  { program: 36, name: '击弦贝斯 1 (Slap Bass 1)', enName: 'Slap Bass 1', category: '贝斯族', icon: '💥' },
  { program: 37, name: '击弦贝斯 2 (Slap Bass 2)', enName: 'Slap Bass 2', category: '贝斯族', icon: '💥' },
  { program: 38, name: '合成贝斯 1 (Synth Bass 1)', enName: 'Synth Bass 1', category: '贝斯族', icon: '🎛️' },
  { program: 39, name: '合成贝斯 2 (Synth Bass 2)', enName: 'Synth Bass 2', category: '贝斯族', icon: '🎛️' },

  // 弦乐独奏 (40-47)
  { program: 40, name: '小提琴 (Violin)', enName: 'Violin', category: '弦乐与管弦', icon: '🎻' },
  { program: 41, name: '中提琴 (Viola)', enName: 'Viola', category: '弦乐与管弦', icon: '🎻' },
  { program: 42, name: '大提琴 (Cello)', enName: 'Cello', category: '弦乐与管弦', icon: '🎻' },
  { program: 43, name: '低音提琴 (Contrabass)', enName: 'Contrabass', category: '弦乐与管弦', icon: '🎻' },
  { program: 44, name: '震音弦乐 (Tremolo Strings)', enName: 'Tremolo Strings', category: '弦乐与管弦', icon: '🎻' },
  { program: 45, name: '拨奏弦乐 (Pizzicato Strings)', enName: 'Pizzicato Strings', category: '弦乐与管弦', icon: '🎻' },
  { program: 46, name: '管弦乐竖琴 (Orchestral Harp)', enName: 'Orchestral Harp', category: '弦乐与管弦', icon: '🪕' },
  { program: 47, name: '定音鼓 (Timpani)', enName: 'Timpani', category: '打击乐与特效', icon: '🥁' },

  // 合奏与人声 (48-55)
  { program: 48, name: '弦乐合奏 1 (慢弓 Strings 1)', enName: 'String Ensemble 1', category: '弦乐与管弦', icon: '🎻' },
  { program: 49, name: '弦乐合奏 2 (快弓 Strings 2)', enName: 'String Ensemble 2', category: '弦乐与管弦', icon: '🎻' },
  { program: 50, name: '合成弦乐 1 (Synth Strings 1)', enName: 'Synth Strings 1', category: '合成主音与铺底', icon: '🎛️' },
  { program: 51, name: '合成弦乐 2 (Synth Strings 2)', enName: 'Synth Strings 2', category: '合成主音与铺底', icon: '🎛️' },
  { program: 52, name: '合唱人声 (Choir Aahs)', enName: 'Choir Aahs', category: '弦乐与管弦', icon: '🗣️' },
  { program: 53, name: '人声伴唱 (Voice Oohs)', enName: 'Voice Oohs', category: '弦乐与管弦', icon: '🗣️' },
  { program: 54, name: '合成人声 (Synth Voice)', enName: 'Synth Voice', category: '合成主音与铺底', icon: '🎛️' },
  { program: 55, name: '管弦打击乐强奏 (Orchestra Hit)', enName: 'Orchestra Hit', category: '打击乐与特效', icon: '💥' },

  // 铜管乐器 (56-63)
  { program: 56, name: '小号 (Trumpet)', enName: 'Trumpet', category: '铜管与木管', icon: '🎺' },
  { program: 57, name: '长号 (Trombone)', enName: 'Trombone', category: '铜管与木管', icon: '🎺' },
  { program: 58, name: '大号 (Tuba)', enName: 'Tuba', category: '铜管与木管', icon: '🎺' },
  { program: 59, name: '弱音小号 (Muted Trumpet)', enName: 'Muted Trumpet', category: '铜管与木管', icon: '🎺' },
  { program: 60, name: '法国圆号 (French Horn)', enName: 'French Horn', category: '铜管与木管', icon: '📯' },
  { program: 61, name: '铜管合奏组 (Brass Section)', enName: 'Brass Section', category: '铜管与木管', icon: '🎺' },
  { program: 62, name: '合成铜管 1 (Synth Brass 1)', enName: 'Synth Brass 1', category: '合成主音与铺底', icon: '🎛️' },
  { program: 63, name: '合成铜管 2 (Synth Brass 2)', enName: 'Synth Brass 2', category: '合成主音与铺底', icon: '🎛️' },

  // 簧管木管 (64-79)
  { program: 64, name: '高音萨克斯 (Soprano Sax)', enName: 'Soprano Sax', category: '铜管与木管', icon: '🎷' },
  { program: 65, name: '中音萨克斯 (Alto Sax)', enName: 'Alto Sax', category: '铜管与木管', icon: '🎷' },
  { program: 66, name: '次中音萨克斯 (Tenor Sax)', enName: 'Tenor Sax', category: '铜管与木管', icon: '🎷' },
  { program: 67, name: '上低音萨克斯 (Baritone Sax)', enName: 'Baritone Sax', category: '铜管与木管', icon: '🎷' },
  { program: 68, name: '双簧管 (Oboe)', enName: 'Oboe', category: '铜管与木管', icon: '🎵' },
  { program: 69, name: '英国管 (English Horn)', enName: 'English Horn', category: '铜管与木管', icon: '🎵' },
  { program: 70, name: '大管 / 巴松管 (Bassoon)', enName: 'Bassoon', category: '铜管与木管', icon: '🎵' },
  { program: 71, name: '单簧管 / 黑管 (Clarinet)', enName: 'Clarinet', category: '铜管与木管', icon: '🎵' },
  { program: 72, name: '短笛 (Piccolo)', enName: 'Piccolo', category: '铜管与木管', icon: '🪈' },
  { program: 73, name: '长笛 (Flute)', enName: 'Flute', category: '铜管与木管', icon: '🪈' },
  { program: 74, name: '竖笛 / 直笛 (Recorder)', enName: 'Recorder', category: '铜管与木管', icon: '🪈' },
  { program: 75, name: '排箫 (Pan Flute)', enName: 'Pan Flute', category: '铜管与木管', icon: '🪈' },
  { program: 76, name: '吹瓶音 (Blown Bottle)', enName: 'Blown Bottle', category: '打击乐与特效', icon: '🍾' },
  { program: 77, name: '尺八 (Shakuhachi)', enName: 'Shakuhachi', category: '民族特色乐器', icon: '🪈' },
  { program: 78, name: '爱尔兰哨笛 (Whistle)', enName: 'Whistle', category: '民族特色乐器', icon: '🪈' },
  { program: 79, name: '陶笛 / 埙 (Ocarina)', enName: 'Ocarina', category: '民族特色乐器', icon: '🪈' },

  // 合成主音 (80-87)
  { program: 80, name: '方波主音 (Lead 1 - Square)', enName: 'Lead 1 (square)', category: '合成主音与铺底', icon: '🎛️' },
  { program: 81, name: '锯齿波主音 (Lead 2 - Sawtooth)', enName: 'Lead 2 (sawtooth)', category: '合成主音与铺底', icon: '🎛️' },
  { program: 82, name: '汽笛风琴主音 (Lead 3 - Calliope)', enName: 'Lead 3 (calliope)', category: '合成主音与铺底', icon: '🎛️' },
  { program: 83, name: '吹管主音 (Lead 4 - Chiff)', enName: 'Lead 4 (chiff)', category: '合成主音与铺底', icon: '🎛️' },
  { program: 84, name: '吉他合成主音 (Lead 5 - Charang)', enName: 'Lead 5 (charang)', category: '合成主音与铺底', icon: '🎛️' },
  { program: 85, name: '人声主音 (Lead 6 - Voice)', enName: 'Lead 6 (voice)', category: '合成主音与铺底', icon: '🗣️' },
  { program: 86, name: '五度主音 (Lead 7 - Fifths)', enName: 'Lead 7 (fifths)', category: '合成主音与铺底', icon: '🎛️' },
  { program: 87, name: '贝斯混合主音 (Lead 8 - Bass + Lead)', enName: 'Lead 8 (bass + lead)', category: '合成主音与铺底', icon: '🎛️' },

  // 合成铺底 (88-95)
  { program: 88, name: '新世纪音色 (Pad 1 - New Age)', enName: 'Pad 1 (new age)', category: '合成主音与铺底', icon: '🌌' },
  { program: 89, name: '温暖温暖铺底 (Pad 2 - Warm)', enName: 'Pad 2 (warm)', category: '合成主音与铺底', icon: '🌌' },
  { program: 90, name: '复音合成器 (Pad 3 - Polysynth)', enName: 'Pad 3 (polysynth)', category: '合成主音与铺底', icon: '🌌' },
  { program: 91, name: '合唱铺底 (Pad 4 - Choir)', enName: 'Pad 4 (choir)', category: '合成主音与铺底', icon: '🌌' },
  { program: 92, name: '弓弦铺底 (Pad 5 - Bowed)', enName: 'Pad 5 (bowed)', category: '合成主音与铺底', icon: '🌌' },
  { program: 93, name: '金属质感铺底 (Pad 6 - Metallic)', enName: 'Pad 6 (metallic)', category: '合成主音与铺底', icon: '🌌' },
  { program: 94, name: '光晕氛围铺底 (Pad 7 - Halo)', enName: 'Pad 7 (halo)', category: '合成主音与铺底', icon: '🌌' },
  { program: 95, name: '扫频铺底 (Pad 8 - Sweep)', enName: 'Pad 8 (sweep)', category: '合成主音与铺底', icon: '🌌' },

  // 合成特效 (96-103)
  { program: 96, name: '雨声特效 (FX 1 - Rain)', enName: 'FX 1 (rain)', category: '打击乐与特效', icon: '🌧️' },
  { program: 97, name: '电影原声氛围 (FX 2 - Soundtrack)', enName: 'FX 2 (soundtrack)', category: '打击乐与特效', icon: '🎬' },
  { program: 98, name: '水晶音色 (FX 3 - Crystal)', enName: 'FX 3 (crystal)', category: '打击乐与特效', icon: '💎' },
  { program: 99, name: '太空大气 (FX 4 - Atmosphere)', enName: 'FX 4 (atmosphere)', category: '打击乐与特效', icon: '🪐' },
  { program: 100, name: '明亮星光 (FX 5 - Brightness)', enName: 'FX 5 (brightness)', category: '打击乐与特效', icon: '⭐' },
  { program: 101, name: '小妖精回音 (FX 6 - Goblins)', enName: 'FX 6 (goblins)', category: '打击乐与特效', icon: '👾' },
  { program: 102, name: '回音水滴 (FX 7 - Echoes)', enName: 'FX 7 (echoes)', category: '打击乐与特效', icon: '💧' },
  { program: 103, name: '科幻脉冲 (FX 8 - Sci-fi)', enName: 'FX 8 (sci-fi)', category: '打击乐与特效', icon: '🚀' },

  // 民族乐器 (104-111)
  { program: 104, name: '西塔尔琴 (Sitar)', enName: 'Sitar', category: '民族特色乐器', icon: '🪕' },
  { program: 105, name: '班卓琴', enName: 'Banjo', category: '常用吉他与弹拨', icon: '🪕' },
  { program: 106, name: '三味线 (Shamisen)', enName: 'Shamisen', category: '民族特色乐器', icon: '🪕' },
  { program: 107, name: '日本筝 / 古筝 (Koto)', enName: 'Koto', category: '民族特色乐器', icon: '🪕' },
  { program: 108, name: '卡林巴拇指琴 (Kalimba)', enName: 'Kalimba', category: '民族特色乐器', icon: '🔔' },
  { program: 109, name: '风笛 (Bagpipe)', enName: 'Bagpipe', category: '民族特色乐器', icon: '📯' },
  { program: 110, name: '民族小提琴 (Fiddle)', enName: 'Fiddle', category: '民族特色乐器', icon: '🎻' },
  { program: 111, name: '印度唢呐 (Shanai)', enName: 'Shanai', category: '民族特色乐器', icon: '🎺' },

  // 打击乐器 (112-119)
  { program: 112, name: '碰铃 / 叮当铃 (Tinkle Bell)', enName: 'Tinkle Bell', category: '打击乐与特效', icon: '🔔' },
  { program: 113, name: '阿哥哥铃 (Agogo)', enName: 'Agogo', category: '打击乐与特效', icon: '🔔' },
  { program: 114, name: '钢鼓 (Steel Drums)', enName: 'Steel Drums', category: '打击乐与特效', icon: '🥁' },
  { program: 115, name: '木鱼 / 木块 (Woodblock)', enName: 'Woodblock', category: '打击乐与特效', icon: '🪵' },
  { program: 116, name: '太鼓 (Taiko Drum)', enName: 'Taiko Drum', category: '打击乐与特效', icon: '🥁' },
  { program: 117, name: '通通鼓 (Melodic Tom)', enName: 'Melodic Tom', category: '打击乐与特效', icon: '🥁' },
  { program: 118, name: '合成电子鼓 (Synth Drum)', enName: 'Synth Drum', category: '打击乐与特效', icon: '🥁' },
  { program: 119, name: '反转镲片 (Reverse Cymbal)', enName: 'Reverse Cymbal', category: '打击乐与特效', icon: '💥' },

  // 声音特效 (120-128)
  { program: 120, name: '吉他品丝噪音 (Guitar Fret Noise)', enName: 'Guitar Fret Noise', category: '打击乐与特效', icon: '🔊' },
  { program: 121, name: '呼吸声 (Breath Noise)', enName: 'Breath Noise', category: '打击乐与特效', icon: '🌬️' },
  { program: 122, name: '海浪声 (Seashore)', enName: 'Seashore', category: '打击乐与特效', icon: '🌊' },
  { program: 123, name: '鸟鸣 (Bird Tweet)', enName: 'Bird Tweet', category: '打击乐与特效', icon: '🐦' },
  { program: 124, name: '电话铃声 (Telephone Ring)', enName: 'Telephone Ring', category: '打击乐与特效', icon: '☎️' },
  { program: 125, name: '直升机 (Helicopter)', enName: 'Helicopter', category: '打击乐与特效', icon: '🚁' },
  { program: 126, name: '掌声 (Applause)', enName: 'Applause', category: '打击乐与特效', icon: '👏' },
  { program: 127, name: '枪声 (Gunshot)', enName: 'Gunshot', category: '打击乐与特效', icon: '🔫' },
  { program: 128, name: '标准爵士/摇滚打击乐架子鼓组', enName: 'Standard Drum Kit', category: '常用吉他与弹拨', icon: '🥁' },
];

/** 兼容旧代码的元组格式 */
export const GM_INSTRUMENTS: Array<[number, string]> = ALL_GM_INSTRUMENTS.map((x) => [x.program, x.name]);

export function getInstrumentByProgram(program: number): GMInstrumentInfo {
  return ALL_GM_INSTRUMENTS.find((i) => i.program === program) || ALL_GM_INSTRUMENTS[25];
}
