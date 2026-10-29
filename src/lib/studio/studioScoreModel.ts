/**
 * MIMI Guitar · 在线打谱工坊核心乐谱数据模型与原子化编辑引擎
 * 
 * 核心设计：
 * 1. 结构化 TypeScript 强类型乐谱模型 (StudioProject -> StudioTrack -> StudioBar -> StudioBeat -> StudioNote)
 * 2. 纯函数式的无损编辑与不可变快照（支持无限级 Undo / Redo 操作栈）
 * 3. 毫秒级双向转译：StudioProject <-> AlphaTex (AlphaTab 原生极速渲染) <-> IBE / JSON / GP5
 * 4. 自动时值拍数检查（检查小节溢出/欠缺）与首调简谱自动推导
 */

export type DurationValue = 1 | 2 | 4 | 8 | 16 | 32;

export interface StudioNote {
  string: number; // 1 (最细高音E弦) 到 6 (最粗低音E弦)
  fret: number; // 0 (空弦) 到 24 品
  tie?: boolean; // 延音线
  hammerPull?: boolean; // 击弦/勾弦 (H/P)
  slide?: boolean; // 滑音 (Slide)
  bend?: boolean; // 推弦 (Bend)
  bendValue?: number; // 半音 (1: 半音, 2: 全音)
  harmonic?: boolean; // 泛音
  harmonicType?: 'natural' | 'artificial';
  palmMute?: boolean; // 闷音 (P.M.)
  dead?: boolean; // 死音 (X)
  vibrato?: boolean; // 颤音 (~)
  accent?: boolean; // 重音 (>)
  ghost?: boolean; // 幽灵音 ((x))
}

export interface StudioBeat {
  id: string;
  duration: DurationValue; // 1: 全音符, 2: 二分, 4: 四分, 8: 八分, 16: 十六分, 32: 三十二分
  isRest: boolean; // 是否为休止符
  dot: boolean; // 附点音符 (1.5x)
  triplet: boolean; // 三连音 (2/3x)
  notes: StudioNote[]; // 该拍上的所有发音琴弦与品位
  chordName?: string | null; // 该拍和弦标注 (如 C, Em7, G/B)
  lyrics?: string | null; // 该拍对应的歌词字词
  brush?: 'up' | 'down' | null; // 扫弦箭头
}

export interface StudioBar {
  id: string;
  index: number;
  timeSignatureNumerator: number; // 拍号分子 (如 4)
  timeSignatureDenominator: number; // 拍号分母 (如 4)
  tempo?: number | null; // 该小节 BPM (若为空则沿用前节)
  section?: string | null; // 段落标签 ('前奏' | '主歌' | '副歌' | '间奏' | '尾奏' | 'Solo' 等)
  repeatStart?: boolean; // 前反复记号 |:
  repeatEnd?: boolean; // 后反复记号 :|
  repeatCount?: number; // 反复次数 (默认 2)
  volta?: number | null; // 房子标记 (1, 2)
  // 每个小节支持多轨独立音符数据，键为 track.id，值为 StudioBeat 数组
  trackBeats: Record<string, StudioBeat[]>;
}

export interface StudioTrack {
  id: string;
  name: string;
  program: number; // General MIDI 编号: 25(木吉他), 24(尼龙吉他), 27(清音电吉他), 29(失真), 33(贝斯), 24(尤克里里), 0(钢琴), 128(鼓)
  tuning: number[]; // 琴弦标准 MIDI 音高，从 1 弦到 6 弦，例如吉他: [64, 59, 55, 50, 45, 40] (E4, B3, G3, D3, A2, E2)
  tuningName: string;
  capo: number; // 变调夹品数 (0 为无变调夹)
  volume: number; // 0.0 ~ 1.0
  pan: number; // -1.0 (左) ~ 1.0 (右)
  mute: boolean;
  solo: boolean;
}

export interface StudioProject {
  /** Native project schema; missing values from older files are upgraded to version 1. */
  schemaVersion?: 1;
  id: string;
  title: string;
  artist: string;
  album?: string;
  words?: string; // 作词
  music?: string; // 作曲
  tabber?: string; // 制谱人
  key: string; // 调性 (C, G, D, A, E, F, Dm, Am 等)
  initialTempo: number; // 默认 120
  timeSignatureNumerator: number; // 默认 4
  timeSignatureDenominator: number; // 默认 4
  tracks: StudioTrack[];
  bars: StudioBar[];
  /** Import source metadata for a personal copy. The linked source is never overwritten. */
  source?: {
    kind: 'library' | 'file';
    id: string;
    fileName: string;
    format: string;
    title?: string;
  };
  /** Import conversion notes which the user should review before exporting. */
  importWarnings?: string[];
  createdAt: number;
  updatedAt: number;
}

export interface CursorPosition {
  trackIndex: number;
  barIndex: number;
  beatIndex: number;
  stringIndex: number; // 1 ~ 6
}

// 辅助：生成唯一 ID
export function generateUid(prefix = 'id'): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 9)}_${Date.now().toString(36)}`;
}

// 标准调弦预设
export const STANDARD_TUNINGS = {
  GUITAR_STANDARD: { name: '标准吉他 (E A D G B E)', notes: [64, 59, 55, 50, 45, 40] },
  GUITAR_DROP_D: { name: '降 D 调弦 (D A D G B E)', notes: [64, 59, 55, 50, 45, 38] },
  GUITAR_DADGAD: { name: 'DADGAD 调弦 (D A D G A D)', notes: [62, 57, 55, 50, 45, 38] },
  GUITAR_HALF_STEP_DOWN: { name: '降半音调弦 (Eb Ab Db Gb Bb Eb)', notes: [63, 58, 54, 49, 44, 39] },
  UKULELE_STANDARD: { name: '标准尤克里里 (G C E A)', notes: [69, 64, 60, 67] }, // 1弦A4(69), 2弦E4(64), 3弦C4(60), 4弦G4(67)
  BASS_STANDARD: { name: '标准4弦贝斯 (E A D G)', notes: [43, 38, 33, 28] },
};

/** 创建空白初始工程 */
export function createBlankProject(type: 'guitar' | 'ukulele' | 'bass' | 'band' = 'guitar'): StudioProject {
  const isUkulele = type === 'ukulele';
  const isBass = type === 'bass';

  let defaultName = '原声吉他';
  let defaultProgram = 25;
  let defaultTuning = [...STANDARD_TUNINGS.GUITAR_STANDARD.notes];
  let defaultTuningName = STANDARD_TUNINGS.GUITAR_STANDARD.name;
  let defaultTitle = '我的吉他新作品';

  if (isUkulele) {
    defaultName = '尤克里里';
    defaultProgram = 24;
    defaultTuning = [...STANDARD_TUNINGS.UKULELE_STANDARD.notes];
    defaultTuningName = STANDARD_TUNINGS.UKULELE_STANDARD.name;
    defaultTitle = '我的尤克里里新作品';
  } else if (isBass) {
    defaultName = '电贝斯';
    defaultProgram = 33;
    defaultTuning = [...STANDARD_TUNINGS.BASS_STANDARD.notes]; // [43, 38, 33, 28] (E1 A1 D2 G2)
    defaultTuningName = STANDARD_TUNINGS.BASS_STANDARD.name;
    defaultTitle = '我的贝斯新作品';
  }

  const defaultTrack: StudioTrack = {
    id: generateUid('trk'),
    name: defaultName,
    program: defaultProgram,
    tuning: defaultTuning,
    tuningName: defaultTuningName,
    capo: 0,
    volume: 1.0,
    pan: 0,
    mute: false,
    solo: false,
  };

  const tracks = [defaultTrack];
  if (type === 'band') {
    tracks.push({
      id: generateUid('trk_rhythm'),
      name: '节奏吉他',
      program: 25,
      tuning: [...STANDARD_TUNINGS.GUITAR_STANDARD.notes],
      tuningName: STANDARD_TUNINGS.GUITAR_STANDARD.name,
      capo: 0,
      volume: 0.8,
      pan: -0.3,
      mute: false,
      solo: false,
    });
    tracks.push({
      id: generateUid('trk_bass'),
      name: '电贝斯',
      program: 33,
      tuning: [...STANDARD_TUNINGS.BASS_STANDARD.notes],
      tuningName: STANDARD_TUNINGS.BASS_STANDARD.name,
      capo: 0,
      volume: 0.9,
      pan: 0.2,
      mute: false,
      solo: false,
    });
  }

  // 默认生成 4 个四四拍空白小节（每小节初始 4 个四分休止符）
  const bars: StudioBar[] = [];
  for (let i = 0; i < 4; i++) {
    const barId = generateUid('bar');
    const trackBeats: Record<string, StudioBeat[]> = {};
    
    for (const trk of tracks) {
      const beats: StudioBeat[] = [];
      for (let b = 0; b < 4; b++) {
        beats.push({
          id: generateUid('beat'),
          duration: 4,
          isRest: true,
          dot: false,
          triplet: false,
          notes: [],
          chordName: null,
          lyrics: null,
        });
      }
      trackBeats[trk.id] = beats;
    }

    bars.push({
      id: barId,
      index: i,
      timeSignatureNumerator: 4,
      timeSignatureDenominator: 4,
      tempo: i === 0 ? 120 : null,
      section: i === 0 ? '前奏' : null,
      trackBeats,
    });
  }

  return {
    schemaVersion: 1,
    id: generateUid('proj'),
    title: defaultTitle,
    artist: '原创制作者',
    album: '',
    words: '',
    music: '',
    tabber: 'MIMI Guitar 琴友',
    key: 'C',
    initialTempo: 120,
    timeSignatureNumerator: 4,
    timeSignatureDenominator: 4,
    tracks,
    bars,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

/** 深度克隆工程对象（保证状态不可变与可撤销） */
export function cloneProject(project: StudioProject): StudioProject {
  return JSON.parse(JSON.stringify(project));
}

/** Validate and upgrade native project JSON, including files created before schemaVersion was added. */
export function normalizeStudioProject(value: unknown): StudioProject {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('工程文件不是有效的 JSON 对象');
  }
  const raw = value as Record<string, unknown>;
  if (!Array.isArray(raw.tracks) || raw.tracks.length === 0 || !Array.isArray(raw.bars) || raw.bars.length === 0) {
    throw new Error('工程文件缺少音轨或小节数据');
  }
  if (raw.schemaVersion != null && raw.schemaVersion !== 1) {
    throw new Error(`暂不支持工程格式版本 ${String(raw.schemaVersion)}`);
  }

  const tracks: StudioTrack[] = raw.tracks.map((entry, index) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error(`第 ${index + 1} 条音轨无效`);
    const track = entry as Record<string, unknown>;
    const tuning = Array.isArray(track.tuning) ? track.tuning.map(Number) : [];
    if (tuning.length < 1 || tuning.length > 12 || tuning.some((n) => !Number.isInteger(n) || n < 0 || n > 127)) {
      throw new Error(`第 ${index + 1} 条音轨的调弦数据无效`);
    }
    const program = Number(track.program ?? 25);
    if (!Number.isInteger(program) || program < 0 || program > 127) throw new Error(`第 ${index + 1} 条音轨的乐器编号无效`);
    return {
      id: typeof track.id === 'string' && track.id ? track.id : generateUid('trk'),
      name: typeof track.name === 'string' ? track.name : `音轨 ${index + 1}`,
      program,
      tuning,
      tuningName: typeof track.tuningName === 'string' ? track.tuningName : '自定义调弦',
      capo: clampInteger(track.capo, 0, 24, 0),
      volume: clampNumber(track.volume, 0, 1, 1),
      pan: clampNumber(track.pan, -1, 1, 0),
      mute: track.mute === true,
      solo: track.solo === true,
    };
  });

  const bars: StudioBar[] = raw.bars.map((entry, barIndex) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error(`第 ${barIndex + 1} 小节无效`);
    const bar = entry as Record<string, unknown>;
    const numerator = clampInteger(bar.timeSignatureNumerator, 1, 32, 4);
    const denominator = clampInteger(bar.timeSignatureDenominator, 1, 32, 4);
    const rawBeats = bar.trackBeats && typeof bar.trackBeats === 'object' && !Array.isArray(bar.trackBeats)
      ? bar.trackBeats as Record<string, unknown>
      : {};
    const trackBeats: Record<string, StudioBeat[]> = {};

    for (const track of tracks) {
      const list = rawBeats[track.id];
      if (!Array.isArray(list)) throw new Error(`第 ${barIndex + 1} 小节缺少「${track.name}」音轨数据`);
      trackBeats[track.id] = list.map((beatValue, beatIndex) => {
        if (!beatValue || typeof beatValue !== 'object' || Array.isArray(beatValue)) {
          throw new Error(`第 ${barIndex + 1} 小节第 ${beatIndex + 1} 拍无效`);
        }
        const beat = beatValue as Record<string, unknown>;
        const duration = Number(beat.duration);
        if (![1, 2, 4, 8, 16, 32].includes(duration)) {
          throw new Error(`第 ${barIndex + 1} 小节第 ${beatIndex + 1} 拍时值无效`);
        }
        const notesRaw = Array.isArray(beat.notes) ? beat.notes : [];
        const notes: StudioNote[] = notesRaw.map((noteValue, noteIndex) => {
          if (!noteValue || typeof noteValue !== 'object' || Array.isArray(noteValue)) {
            throw new Error(`第 ${barIndex + 1} 小节第 ${beatIndex + 1} 拍第 ${noteIndex + 1} 个音符无效`);
          }
          const note = noteValue as Record<string, unknown>;
          const string = Number(note.string);
          const fret = Number(note.fret);
          if (!Number.isInteger(string) || string < 1 || string > track.tuning.length || !Number.isInteger(fret) || fret < 0 || fret > 24) {
            throw new Error(`第 ${barIndex + 1} 小节第 ${beatIndex + 1} 拍有超出弦数或品位范围的音符`);
          }
          return {
            string, fret,
            tie: note.tie === true,
            hammerPull: note.hammerPull === true,
            slide: note.slide === true,
            bend: note.bend === true,
            bendValue: clampInteger(note.bendValue, 1, 12, 2),
            harmonic: note.harmonic === true,
            harmonicType: note.harmonicType === 'artificial' ? 'artificial' : 'natural',
            palmMute: note.palmMute === true,
            dead: note.dead === true,
            vibrato: note.vibrato === true,
            accent: note.accent === true,
            ghost: note.ghost === true,
          };
        });
        return {
          id: typeof beat.id === 'string' && beat.id ? beat.id : generateUid('beat'),
          duration: duration as DurationValue,
          isRest: beat.isRest === true || (beat.isRest !== false && notes.length === 0),
          dot: beat.dot === true,
          triplet: beat.triplet === true,
          notes,
          chordName: typeof beat.chordName === 'string' ? beat.chordName : null,
          lyrics: typeof beat.lyrics === 'string' ? beat.lyrics : null,
          brush: beat.brush === 'up' || beat.brush === 'down' ? beat.brush : null,
        };
      });
    }

    const tempo = bar.tempo == null ? null : Number(bar.tempo);
    return {
      id: typeof bar.id === 'string' && bar.id ? bar.id : generateUid('bar'),
      index: barIndex,
      timeSignatureNumerator: numerator,
      timeSignatureDenominator: denominator,
      tempo: tempo != null && Number.isFinite(tempo) && tempo > 0 ? tempo : null,
      section: typeof bar.section === 'string' && bar.section ? bar.section : null,
      repeatStart: bar.repeatStart === true,
      repeatEnd: bar.repeatEnd === true,
      repeatCount: clampInteger(bar.repeatCount, 2, 8, 2),
      volta: bar.volta == null ? null : clampInteger(bar.volta, 1, 8, 1),
      trackBeats,
    };
  });

  const trackIds = new Set(tracks.map((track) => track.id));
  for (let i = 0; i < bars.length; i++) {
    bars[i].index = i;
    const rawBar = raw.bars[i] as Record<string, unknown>;
    const rawTrackBeats = rawBar.trackBeats as Record<string, unknown> | undefined;
    if (rawTrackBeats && Object.keys(rawTrackBeats).some((id) => !trackIds.has(id))) {
      throw new Error(`第 ${i + 1} 小节包含未知音轨数据`);
    }
  }

  return {
    schemaVersion: 1,
    id: typeof raw.id === 'string' && raw.id ? raw.id : generateUid('proj'),
    title: typeof raw.title === 'string' ? raw.title : '未命名乐谱',
    artist: typeof raw.artist === 'string' ? raw.artist : '',
    album: typeof raw.album === 'string' ? raw.album : undefined,
    words: typeof raw.words === 'string' ? raw.words : undefined,
    music: typeof raw.music === 'string' ? raw.music : undefined,
    tabber: typeof raw.tabber === 'string' ? raw.tabber : undefined,
    key: typeof raw.key === 'string' ? raw.key : 'C',
    initialTempo: clampInteger(raw.initialTempo, 20, 400, 120),
    timeSignatureNumerator: clampInteger(raw.timeSignatureNumerator, 1, 32, 4),
    timeSignatureDenominator: clampInteger(raw.timeSignatureDenominator, 1, 32, 4),
    tracks,
    bars,
    source: normalizeSourceReference(raw.source),
    importWarnings: Array.isArray(raw.importWarnings) ? raw.importWarnings.filter((v): v is string => typeof v === 'string').slice(0, 100) : undefined,
    createdAt: validTimestamp(raw.createdAt),
    updatedAt: validTimestamp(raw.updatedAt),
  };
}

function clampInteger(value: unknown, min: number, max: number, fallback: number): number {
  const number = Number(value);
  return Number.isInteger(number) ? Math.min(max, Math.max(min, number)) : fallback;
}

function clampNumber(value: unknown, min: number, max: number, fallback: number): number {
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(max, Math.max(min, number)) : fallback;
}

function validTimestamp(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : Date.now();
}

function normalizeSourceReference(value: unknown): StudioProject['source'] {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const source = value as Record<string, unknown>;
  if ((source.kind !== 'library' && source.kind !== 'file') || typeof source.id !== 'string' || typeof source.fileName !== 'string') return undefined;
  return {
    kind: source.kind,
    id: source.id,
    fileName: source.fileName,
    format: typeof source.format === 'string' ? source.format : 'unknown',
    title: typeof source.title === 'string' ? source.title : undefined,
  };
}

/** 计算单个 Beat 的绝对时值（以四分音符为 1.0 计量） */
export function getBeatAbsoluteDuration(beat: StudioBeat): number {
  const baseValue = 4 / beat.duration; // 4分音符=1.0, 8分音符=0.5, 2分音符=2.0, 全音符=4.0
  let duration = baseValue;
  if (beat.dot) duration *= 1.5;
  if (beat.triplet) duration *= (2 / 3);
  return duration;
}

/** 计算单个小节当前所有 Beat 的总时值及是否合法 */
export function evaluateBarTiming(bar: StudioBar, trackId: string): {
  totalDuration: number;
  expectedDuration: number;
  isFull: boolean;
  isOverflow: boolean;
  isUnderflow: boolean;
} {
  const beats = bar.trackBeats[trackId] || [];
  let totalDuration = 0;
  for (const b of beats) {
    totalDuration += getBeatAbsoluteDuration(b);
  }
  // 期望时值: (分子 / 分母) * 4
  const expectedDuration = (bar.timeSignatureNumerator / bar.timeSignatureDenominator) * 4;
  const diff = Math.abs(totalDuration - expectedDuration);
  const isFull = diff < 0.001;
  const isOverflow = totalDuration > expectedDuration + 0.001;
  const isUnderflow = totalDuration < expectedDuration - 0.001;

  return { totalDuration, expectedDuration, isFull, isOverflow, isUnderflow };
}

// -------------------------------------------------------------
// 原子化乐谱编辑操作函数群（每次操作返回全新 Immutable Project）
// -------------------------------------------------------------

/** 1. 在当前位置设置/更新音符品数（0-24） */
export function setNoteFret(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  stringNum: number,
  fret: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  const beat = beats[beatIndex];
  beat.isRest = false; // 敲入品位后自动变为发音音符

  // 查找或添加该琴弦上的音符
  const existingNoteIdx = beat.notes.findIndex((n) => n.string === stringNum);
  if (existingNoteIdx >= 0) {
    beat.notes[existingNoteIdx].fret = fret;
    beat.notes[existingNoteIdx].dead = false;
  } else {
    beat.notes.push({
      string: stringNum,
      fret,
    });
    // 按琴弦顺序升序排列
    beat.notes.sort((a, b) => a.string - b.string);
  }

  next.updatedAt = Date.now();
  return next;
}

/** 2. 删除当前琴弦音符（若所有弦被删空，则自动转为休止符） */
export function deleteNote(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  stringNum?: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  const beat = beats[beatIndex];
  if (stringNum !== undefined) {
    beat.notes = beat.notes.filter((n) => n.string !== stringNum);
  } else {
    beat.notes = [];
  }

  if (beat.notes.length === 0) {
    beat.isRest = true;
  }

  next.updatedAt = Date.now();
  return next;
}

/** 3. 修改当前 Beat 的音符时值 (1, 2, 4, 8, 16, 32) */
export function setBeatDuration(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  duration: DurationValue
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  beats[beatIndex].duration = duration;
  next.updatedAt = Date.now();
  return next;
}

/** 4. 切换附点 (Dot) */
export function toggleBeatDot(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  beats[beatIndex].dot = !beats[beatIndex].dot;
  next.updatedAt = Date.now();
  return next;
}

/** 5. 切换三连音 (Triplet) */
export function toggleBeatTriplet(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  beats[beatIndex].triplet = !beats[beatIndex].triplet;
  next.updatedAt = Date.now();
  return next;
}

/** 6. 切换休止符 / 发音状态 */
export function toggleBeatRest(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  const beat = beats[beatIndex];
  beat.isRest = !beat.isRest;
  if (beat.isRest) {
    beat.notes = [];
  }

  next.updatedAt = Date.now();
  return next;
}

/** 7. 切换音符演奏技巧 (Tie / HammerPull / Slide / Bend / Harmonic / PalmMute / Dead / Vibrato) */
export function toggleNoteTechnique(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  stringNum: number,
  technique: 'tie' | 'hammerPull' | 'slide' | 'bend' | 'harmonic' | 'palmMute' | 'dead' | 'vibrato' | 'accent' | 'ghost'
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  const beat = beats[beatIndex];
  let note = beat.notes.find((n) => n.string === stringNum);
  if (!note && !beat.isRest) {
    // 若当前弦没有音符则自动创建 0 品
    note = { string: stringNum, fret: 0 };
    beat.notes.push(note);
  }
  if (!note) return project;

  if (technique === 'tie') note.tie = !note.tie;
  else if (technique === 'hammerPull') note.hammerPull = !note.hammerPull;
  else if (technique === 'slide') note.slide = !note.slide;
  else if (technique === 'bend') note.bend = !note.bend;
  else if (technique === 'harmonic') note.harmonic = !note.harmonic;
  else if (technique === 'palmMute') note.palmMute = !note.palmMute;
  else if (technique === 'dead') note.dead = !note.dead;
  else if (technique === 'vibrato') note.vibrato = !note.vibrato;
  else if (technique === 'accent') note.accent = !note.accent;
  else if (technique === 'ghost') note.ghost = !note.ghost;

  next.updatedAt = Date.now();
  return next;
}

/** Set the current beat's brush direction; clicking the selected direction clears it. */
export function setBeatBrush(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  direction: 'up' | 'down' | null
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  const beat = beats?.[beatIndex];
  if (!beat) return project;

  if (direction === null) {
    if (beat.brush == null) return project;
    beat.brush = null;
  } else {
    if (beat.isRest || beat.notes.length === 0) return project;
    beat.brush = beat.brush === direction ? null : direction;
  }

  next.updatedAt = Date.now();
  return next;
}

/** 8. 设置 Beat 和弦名称 */
export function setBeatChord(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  chordName: string | null
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  beats[beatIndex].chordName = chordName;
  next.updatedAt = Date.now();
  return next;
}

/** 9. 设置 Beat 歌词 */
export function setBeatLyrics(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number,
  lyrics: string | null
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || !beats[beatIndex]) return project;

  beats[beatIndex].lyrics = lyrics;
  next.updatedAt = Date.now();
  return next;
}

/** 10. 在当前小节插入新 Beat */
export function insertBeatInBar(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  afterBeatIndex: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  if (!bar.trackBeats[track.id]) {
    bar.trackBeats[track.id] = [];
  }
  const beats = bar.trackBeats[track.id];

  const refBeat = beats[afterBeatIndex] || beats[beats.length - 1];
  const newBeat: StudioBeat = {
    id: generateUid('beat'),
    duration: refBeat ? refBeat.duration : 4,
    isRest: true,
    dot: false,
    triplet: false,
    notes: [],
    chordName: null,
    lyrics: null,
  };

  const insertIdx = Math.max(0, Math.min(beats.length, afterBeatIndex + 1));
  beats.splice(insertIdx, 0, newBeat);
  next.updatedAt = Date.now();
  return next;
}

/** 11. 删除指定 Beat（若仅剩 1 拍则安全重置为空休止符） */
export function deleteBeatInBar(
  project: StudioProject,
  trackIndex: number,
  barIndex: number,
  beatIndex: number
): StudioProject {
  const next = cloneProject(project);
  const track = next.tracks[trackIndex];
  if (!track) return project;
  const bar = next.bars[barIndex];
  if (!bar) return project;
  const beats = bar.trackBeats[track.id];
  if (!beats || beats.length === 0) return project;
  if (beatIndex < 0 || beatIndex >= beats.length) return project;

  if (beats.length <= 1) {
    // 至少保留一拍结构：将该拍重置为干净的空白休止符
    beats[0].notes = [];
    beats[0].isRest = true;
    beats[0].chordName = null;
    beats[0].lyrics = null;
    beats[0].dot = false;
    beats[0].triplet = false;
    beats[0].brush = null;
  } else {
    beats.splice(beatIndex, 1);
  }

  next.updatedAt = Date.now();
  return next;
}

/** 12. 插入全新小节（在指定位置后） */
export function insertBarAfter(project: StudioProject, afterBarIndex: number): StudioProject {
  const next = cloneProject(project);
  const prevBar = next.bars[afterBarIndex] || next.bars[next.bars.length - 1];

  const newBarId = generateUid('bar');
  const trackBeats: Record<string, StudioBeat[]> = {};

  for (const trk of next.tracks) {
    const beats: StudioBeat[] = [];
    const count = prevBar ? prevBar.timeSignatureNumerator : 4;
    for (let b = 0; b < count; b++) {
      beats.push({
        id: generateUid('beat'),
        duration: 4,
        isRest: true,
        dot: false,
        triplet: false,
        notes: [],
        chordName: null,
        lyrics: null,
      });
    }
    trackBeats[trk.id] = beats;
  }

  const newBar: StudioBar = {
    id: newBarId,
    index: afterBarIndex + 1,
    timeSignatureNumerator: prevBar ? prevBar.timeSignatureNumerator : 4,
    timeSignatureDenominator: prevBar ? prevBar.timeSignatureDenominator : 4,
    tempo: null,
    section: null,
    trackBeats,
  };

  next.bars.splice(afterBarIndex + 1, 0, newBar);
  // 重新标定小节 index
  next.bars.forEach((b, idx) => (b.index = idx));
  next.updatedAt = Date.now();
  return next;
}

/** 13. 删除指定小节 */
export function deleteBar(project: StudioProject, barIndex: number): StudioProject {
  const next = cloneProject(project);
  if (next.bars.length <= 1) return project; // 至少保留一小节

  next.bars.splice(barIndex, 1);
  next.bars.forEach((b, idx) => (b.index = idx));
  next.updatedAt = Date.now();
  return next;
}

/** 14. 复制并追加指定小节 */
export function duplicateBar(project: StudioProject, barIndex: number): StudioProject {
  const next = cloneProject(project);
  const srcBar = next.bars[barIndex];
  if (!srcBar) return project;

  const clonedBar: StudioBar = JSON.parse(JSON.stringify(srcBar));
  clonedBar.id = generateUid('bar');
  // 为所有 Beat 分配新 ID
  for (const trkId in clonedBar.trackBeats) {
    for (const b of clonedBar.trackBeats[trkId]) {
      b.id = generateUid('beat');
    }
  }

  next.bars.splice(barIndex + 1, 0, clonedBar);
  next.bars.forEach((b, idx) => (b.index = idx));
  next.updatedAt = Date.now();
  return next;
}

/** 15. 设置小节拍号与段落标记 */
export function updateBarMeta(
  project: StudioProject,
  barIndex: number,
  patch: Partial<Pick<StudioBar, 'timeSignatureNumerator' | 'timeSignatureDenominator' | 'tempo' | 'section' | 'repeatStart' | 'repeatEnd' | 'repeatCount' | 'volta'>>
): StudioProject {
  const next = cloneProject(project);
  const bar = next.bars[barIndex];
  if (!bar) return project;

  Object.assign(bar, patch);
  next.updatedAt = Date.now();
  return next;
}

// -------------------------------------------------------------
// AlphaTex 转译器：将 StudioProject 转为 AlphaTab 原生极速渲染标记
// -------------------------------------------------------------

export function projectToAlphaTex(project: StudioProject): string {
  const lines: string[] = [];
  let previousTimeSignature = '';

  // 元数据版头
  lines.push(`\\title "${escapeAlphaTexText(project.title || '精校曲谱')}"`);
  if (project.artist) lines.push(`\\artist "${escapeAlphaTexText(project.artist)}"`);
  lines.push(`\\tempo ${project.initialTempo || 120}`);
  lines.push(`\\ks ${alphaTexKey(project.key)}`);
  lines.push(`\\ts ${project.timeSignatureNumerator || 4} ${project.timeSignatureDenominator || 4}`);

  // 遍历每一个音轨
  project.tracks.forEach((track, trackIndex) => {
    lines.push(`\\track "${track.name || '吉他'}"`);
    if (track.program !== undefined && track.program !== null) {
      lines.push(`\\instrument ${track.program}`);
    }
    if (track.capo > 0) lines.push(`\\capo ${track.capo}`);

    // 调弦
    const tuningStr = track.tuning
      .map((m) => {
        const octave = Math.floor(m / 12) - 1;
        const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
        return `${noteNames[m % 12]}${octave}`;
      })
      .join(' ');
    lines.push(`\\tuning ${tuningStr}`);

    // 乐谱音符起始点
    lines.push('.');

    // 遍历小节
    project.bars.forEach((bar) => {
      const beats = bar.trackBeats[track.id] || [];
      const beatTokens: string[] = [];

      // 小节级拍号、段落标记与速度变化，按需保留变拍号。
      let barHeader = '';
      // Master-bar metadata is shared by every track in AlphaTex. Emit it once
      // on the first staff so later tracks cannot create duplicate repeats or
      // time-signature changes.
      if (trackIndex === 0) {
        const timeSignature = `${bar.timeSignatureNumerator}/${bar.timeSignatureDenominator}`;
        if (timeSignature !== previousTimeSignature) {
          barHeader += `\\ts ${bar.timeSignatureNumerator} ${bar.timeSignatureDenominator} `;
          previousTimeSignature = timeSignature;
        }
        if (bar.section) {
          const sanitizedSection = bar.section.trim();
          if (sanitizedSection) {
            barHeader += `\\section "${escapeAlphaTexText(sanitizedSection)}" `;
          }
        }
        if (bar.tempo) {
          barHeader += `\\tempo ${bar.tempo} `;
        }
        if (bar.repeatStart) barHeader += '\\ro ';
        if (bar.repeatEnd) barHeader += `\\rc ${bar.repeatCount || 2} `;
        if (bar.volta) barHeader += `\\ae (${bar.volta}) `;
      }

      if (beats.length === 0) {
        beatTokens.push('r.1'); // 空小节填全休止符
      } else {
        beats.forEach((beat) => {
          // 节拍级属性 (和弦、歌词、三连音、扫弦、附点)
          const beatAttrs: string[] = [];
          if (beat.chordName) {
            beatAttrs.push(`ch "${escapeAlphaTexText(beat.chordName.trim())}"`);
          }
          if (beat.lyrics) {
            beatAttrs.push(`txt "${escapeAlphaTexText(beat.lyrics.trim())}"`);
          }
          if (beat.triplet) {
            beatAttrs.push('tu 3');
          }
          if (beat.brush === 'up') {
            beatAttrs.push('su');
          } else if (beat.brush === 'down') {
            beatAttrs.push('sd');
          }
          if (beat.dot) {
            beatAttrs.push('d');
          }

          const beatAttrStr = beatAttrs.length > 0 ? `{${beatAttrs.join(' ')}}` : '';

          let token = '';
          if (beat.isRest || beat.notes.length === 0) {
            token = `r.${beat.duration}${beatAttrStr}`;
          } else {
            // 音符级技巧解析
            const noteTokens = beat.notes.map((n) => {
              const fretStr = n.dead ? 'x' : `${n.fret}`;
              const noteTechs: string[] = [];
              if (n.tie) noteTechs.push('t');
              if (n.hammerPull) noteTechs.push('h');
              if (n.slide) noteTechs.push('ss');
              if (n.bend) noteTechs.push(`b (${n.bendValue || 2})`);
              if (n.harmonic) noteTechs.push('nh');
              if (n.palmMute) noteTechs.push('pm');
              if (n.vibrato) noteTechs.push('v');
              if (n.accent) noteTechs.push('ac');
              if (n.ghost) noteTechs.push('g');
              const techStr = noteTechs.length > 0 ? `{${noteTechs.join(' ')}}` : '';
              // AlphaTex notation uses high-pitch-first physical string labels,
              // even though the resulting AlphaTab Note.string is low-first.
              return `${fretStr}.${n.string}${techStr}`;
            });

            token = `(${noteTokens.join(' ')}).${beat.duration}${beatAttrStr}`;
          }

          beatTokens.push(token);
        });
      }

      let barLine = beatTokens.join(' ');
      if (barHeader) {
        barLine = barHeader + barLine;
      }

      barLine += ' |';

      lines.push(barLine);
    });
  });

  return lines.join('\n');
}

function escapeAlphaTexText(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[\r\n]+/g, ' ');
}

function alphaTexKey(key: string): string {
  return /m$/i.test(key) ? `${key.slice(0, -1)}minor` : key;
}

