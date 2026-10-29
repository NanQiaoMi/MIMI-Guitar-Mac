import { exporter, importer, model, Settings } from '@coderline/alphatab';
import { normalizeScoreJson, OUR_KEY, OUR_MAGIC, xorBytes } from '../ibe.ts';
import {
  createBlankProject,
  generateUid,
  normalizeStudioProject,
  projectToAlphaTex,
  STANDARD_TUNINGS,
  type DurationValue,
  type StudioBeat,
  type StudioBar,
  type StudioNote,
  type StudioProject,
  type StudioTrack,
} from './studioScoreModel.ts';

const MIN_STUDIO_FRET = 0;
const MAX_STUDIO_FRET = 24;
const IMPORT_EXTENSIONS = new Set(['ibe', 'gp', 'gp3', 'gp4', 'gp5', 'gpx', 'gp7', 'gp8', 'musicxml', 'xml', 'tex', 'alphatex', 'json']);

type JsonObject = Record<string, any>;
type StudioNotePlacement = { string: number; fret: number };

export interface StudioImportResult {
  project: StudioProject;
  warnings: string[];
  sourceFormat: string;
}

function record(value: unknown): JsonObject {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
}

function stringValue(value: unknown, fallback = ''): string {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

const UNKNOWN_IMPORTED_AUTHOR = '未知作者';

function normalizeImportedArtist(project: StudioProject): StudioProject {
  project.artist = stringValue(project.artist, UNKNOWN_IMPORTED_AUTHOR);
  return project;
}

function numberValue(value: unknown, fallback: number): number {
  const result = Number(value);
  return Number.isFinite(result) ? result : fallback;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function durationFor(value: unknown, warnings: Set<string>): DurationValue {
  const duration = Number(value);
  if ([1, 2, 4, 8, 16, 32].includes(duration)) return duration as DurationValue;
  warnings.add(`时值 ${String(value)} 不是工坊当前可编辑的基本时值，已近似转换；原谱已保留。`);
  const supported = [1, 2, 4, 8, 16, 32];
  return supported.reduce((best, candidate) => Math.abs(candidate - duration) < Math.abs(best - duration) ? candidate : best, 4) as DurationValue;
}

function keyFromSignature(value: unknown, type: unknown): string {
  const major = ['C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#', 'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Cb'];
  const minor = ['Am', 'Em', 'Bm', 'F#m', 'C#m', 'G#m', 'D#m', 'A#m', 'Dm', 'Gm', 'Cm', 'Fm', 'Bbm', 'Ebm', 'Abm'];
  const signature = clamp(Math.trunc(numberValue(value, 0)), -7, 7);
  const index = signature >= 0 ? signature : 7 + Math.abs(signature);
  return type === 1 ? (minor[index] ?? 'Am') : (major[index] ?? 'C');
}

function cleanLyrics(value: unknown): string | null {
  if (typeof value === 'string') return value || null;
  if (!Array.isArray(value)) return null;
  const text = value.map((part) => typeof part === 'string' ? part : stringValue(record(part).text)).join('');
  return text || null;
}

function boundedImportWarnings(warnings: Set<string>): string[] {
  const items = [...warnings];
  if (items.length <= 100) return items;
  return [
    ...items.slice(0, 99),
    `另外还有 ${items.length - 99} 条相似或逐小节转换提醒未展开；原始文件已保留。`,
  ];
}

function inferredDefaultTuning(sourceTrack: JsonObject): typeof STANDARD_TUNINGS.GUITAR_STANDARD | null {
  const name = stringValue(sourceTrack.name).toLowerCase();
  const program = numberValue(record(sourceTrack.playbackinfo).program, -1);
  if (/(ukulele|ukelele|uke|尤克里里)/i.test(name)) return STANDARD_TUNINGS.UKULELE_STANDARD;
  if (/(bass|贝斯|低音)/i.test(name) || (program >= 32 && program <= 39)) return STANDARD_TUNINGS.BASS_STANDARD;
  if (/(guitar|吉他)/i.test(name) || (program >= 24 && program <= 31)) return STANDARD_TUNINGS.GUITAR_STANDARD;
  return null;
}

function sourceTrackToStudioTrack(sourceTrack: JsonObject, staff: JsonObject, index: number, warnings: Set<string>): StudioTrack | null {
  const tuningRecord = record(staff.stringtuning);
  const tuningSource = Array.isArray(tuningRecord.tunings) ? tuningRecord.tunings : Array.isArray(staff.tuning) ? staff.tuning : [];
  // AlphaTab JSON stores tuning high-pitch-first, the same order as Studio.
  // AlphaTab note.string itself is low-pitch-first and is converted below.
  const tuning = tuningSource.map((note: unknown) => Number(note)).filter((note: number) => Number.isInteger(note) && note >= 0 && note <= 127);
  const inferredTuning = tuning.length === 0 ? inferredDefaultTuning(sourceTrack) : null;
  const resolvedTuning = inferredTuning?.notes ?? tuning;
  if (resolvedTuning.length < 1 || resolvedTuning.length > 12) return null;

  const trackName = stringValue(sourceTrack.name, `音轨 ${index + 1}`);
  if (inferredTuning) {
    warnings.add(`音轨「${trackName}」缺少原始调弦，已推断默认调弦「${inferredTuning.name}」；五线谱音符将尝试自动分配弦品，须核对指法；原谱已保留。`);
  }
  const playback = record(sourceTrack.playbackinfo);
  return {
    id: generateUid('trk'),
    name: trackName,
    program: clamp(Math.trunc(numberValue(playback.program, 25)), 0, 127),
    tuning: [...resolvedTuning],
    tuningName: stringValue(tuningRecord.name, inferredTuning?.name ?? '导入调弦'),
    capo: clamp(Math.trunc(numberValue(staff.capo, 0)), 0, 24),
    volume: clamp(numberValue(playback.volume, 15) / 15, 0, 1),
    pan: clamp((numberValue(playback.balance, 8) - 8) / 7, -1, 1),
    mute: playback.ismute === true,
    solo: playback.issolo === true,
  };
}

function midiPitchFromAlphaTab(note: JsonObject): number | null {
  const octave = Number(note.octave);
  const tone = Number(note.tone);
  if (!Number.isInteger(octave) || !Number.isInteger(tone) || tone < 0 || tone > 11) return null;
  const midi = octave * 12 + tone;
  return midi >= 0 && midi <= 127 ? midi : null;
}

function explicitPlacementFromAlphaTab(note: JsonObject, track: StudioTrack): StudioNotePlacement | null {
  const alphaTabString = Number(note.string);
  const fret = Number(note.fret);
  if (!Number.isInteger(alphaTabString) || alphaTabString < 1 || alphaTabString > track.tuning.length
    || !Number.isInteger(fret) || fret < MIN_STUDIO_FRET || fret > MAX_STUDIO_FRET) return null;
  return { string: track.tuning.length + 1 - alphaTabString, fret };
}

function inferredPlacementsForChord(sourceNotes: JsonObject[], track: StudioTrack): Map<number, StudioNotePlacement> {
  const reservedStrings = new Set<number>();
  const candidatesByNote = new Map<number, StudioNotePlacement[]>();
  const inferredNoteIndexes: number[] = [];
  for (let noteIndex = 0; noteIndex < sourceNotes.length; noteIndex++) {
    const note = sourceNotes[noteIndex];
    const explicit = explicitPlacementFromAlphaTab(note, track);
    if (explicit) {
      reservedStrings.add(explicit.string);
      continue;
    }
    const midi = midiPitchFromAlphaTab(note);
    const candidates = midi === null ? [] : track.tuning
      .map((openPitch, index) => ({ string: index + 1, fret: midi - openPitch - track.capo }))
      .filter((candidate) => candidate.fret >= MIN_STUDIO_FRET && candidate.fret <= MAX_STUDIO_FRET)
      .sort((left, right) => left.fret - right.fret || left.string - right.string);
    candidatesByNote.set(noteIndex, candidates);
    inferredNoteIndexes.push(noteIndex);
  }

  const placementByString = new Map<number, { noteIndex: number; placement: StudioNotePlacement }>();
  const assign = (noteIndex: number, visitedStrings: Set<number>): boolean => {
    for (const candidate of candidatesByNote.get(noteIndex) ?? []) {
      if (reservedStrings.has(candidate.string) || visitedStrings.has(candidate.string)) continue;
      visitedStrings.add(candidate.string);
      const previous = placementByString.get(candidate.string);
      if (!previous || assign(previous.noteIndex, visitedStrings)) {
        placementByString.set(candidate.string, { noteIndex, placement: candidate });
        return true;
      }
    }
    return false;
  };
  for (const noteIndex of inferredNoteIndexes) assign(noteIndex, new Set());

  const placements = new Map<number, StudioNotePlacement>();
  for (const { noteIndex, placement } of placementByString.values()) placements.set(noteIndex, placement);
  return placements;
}

function noteFromAlphaTab(
  note: JsonObject,
  track: StudioTrack,
  warnings: Set<string>,
  inferredPlacement: StudioNotePlacement | null
): StudioNote | null {
  const explicitPlacement = explicitPlacementFromAlphaTab(note, track);
  let string: number;
  let fret: number;
  if (explicitPlacement) {
    // Preserve existing tablature fingering exactly; only standard-notation notes
    // without a usable string/fret pair go through the inferred assignment below.
    string = explicitPlacement.string;
    fret = explicitPlacement.fret;
  } else if (inferredPlacement) {
    string = inferredPlacement.string;
    fret = inferredPlacement.fret;
    warnings.add(`音轨「${track.name}」的五线谱音符已按音高自动分配弦品，须核对指法；原谱已保留。`);
  } else {
    const midi = midiPitchFromAlphaTab(note);
    const detail = midi === null ? '缺少可用的五线谱音高' : `MIDI ${midi} 无法分配到未占用且 0–24 品范围内的弦`;
    warnings.add(`音轨「${track.name}」中有${detail}的音符，已从编辑副本省略；原谱已保留。`);
    return null;
  }
  if (note.isvisible === false) {
    warnings.add(`音轨「${track.name}」中有隐藏音符，编辑副本无法保留其隐藏状态；原谱已保留。`);
  }
  const unsupportedTechniques = [
    note.isletring === true ? '延音' : '',
    note.isstaccato === true ? '断奏' : '',
    note.islefthandtapped === true ? '左手点弦' : '',
    note.isfingering === true ? '指法标记' : '',
    numberValue(note.trillvalue, -1) >= 0 ? '颤音奏法' : '',
    Math.abs(numberValue(note.durationpercent, 1) - 1) > 0.001 ? '缩短音符时长' : '',
    numberValue(note.accentuated, 0) > 1 ? '强重音或 tenuto 级别' : '',
  ].filter(Boolean);
  for (const technique of unsupportedTechniques) {
    warnings.add(`音轨「${track.name}」包含工坊尚未建模的${technique}技巧，编辑副本已省略该效果；原谱已保留。`);
  }
  return {
    string,
    fret,
    tie: numberValue(note.tiedestinationnoteid, -1) >= 0,
    hammerPull: note.ishammerpullorigin === true || numberValue(note.hammerpulldestinationnoteid, -1) >= 0,
    slide: numberValue(note.slideintype, 0) !== 0 || numberValue(note.slideouttype, 0) !== 0,
    bend: numberValue(note.bendtype, 0) !== 0 || (Array.isArray(note.bendpoints) && note.bendpoints.length > 0),
    bendValue: clamp(Math.round(numberValue(record(note.bendpoints?.at?.(-1)).value, 2)), 1, 12),
    harmonic: numberValue(note.harmonictype, 0) !== 0,
    harmonicType: numberValue(note.harmonictype, 0) > 1 ? 'artificial' : 'natural',
    palmMute: note.ispalmmute === true,
    dead: note.isdead === true,
    vibrato: numberValue(note.vibrato, 0) !== 0,
    accent: numberValue(note.accentuated, 0) !== 0,
    ghost: note.isghost === true,
  };
}

function beatFromAlphaTab(sourceBeat: JsonObject, track: StudioTrack, warnings: Set<string>, barIndex: number): StudioBeat {
  const sourceNotes: JsonObject[] = Array.isArray(sourceBeat.notes) ? sourceBeat.notes.map(record) : [];
  const inferredPlacements = inferredPlacementsForChord(sourceNotes, track);
  const notes = sourceNotes.map((note, index) => noteFromAlphaTab(note, track, warnings, inferredPlacements.get(index) ?? null)).filter((note): note is StudioNote => note !== null);
  const brushType = numberValue(sourceBeat.brushtype, 0);
  const unsupportedBeatEffects = [
    sourceBeat.pop === true ? '拍弦' : '',
    sourceBeat.slap === true ? '击弦' : '',
    sourceBeat.tap === true ? '点弦' : '',
    sourceBeat.hasrasgueado === true ? '轮扫' : '',
    sourceBeat.fadein === true ? '渐入' : '',
    numberValue(sourceBeat.whammystyle, 0) !== 0 || (Array.isArray(sourceBeat.whammybarpoints) && sourceBeat.whammybarpoints.length > 0) ? '摇把变化' : '',
    numberValue(sourceBeat.gracetype, 0) !== 0 ? '装饰音' : '',
    sourceBeat.tremolospeed != null ? '震音拨弦' : '',
    numberValue(sourceBeat.crescendo, 0) !== 0 ? '渐强或渐弱' : '',
    numberValue(sourceBeat.dynamics, 5) !== 5 ? '力度变化' : '',
    brushType === 3 ? '上行琶音' : '',
    brushType === 4 ? '下行琶音' : '',
    brushType > 4 ? '其他刷弦类型' : '',
  ].filter(Boolean);
  for (const effect of unsupportedBeatEffects) {
    warnings.add(`音轨「${track.name}」含工坊尚未建模的${effect}效果，编辑副本已省略该效果；原谱已保留。`);
  }
  const dots = Math.max(0, Math.trunc(numberValue(sourceBeat.dots, 0)));
  if (dots > 1) warnings.add(`第 ${barIndex + 1} 小节包含双附点，编辑副本以单附点近似；原谱已保留。`);
  const tupletNumerator = Number(sourceBeat.tupletnumerator);
  const tupletDenominator = Number(sourceBeat.tupletdenominator);
  const triplet = tupletNumerator === 3 && tupletDenominator === 2;
  if (tupletNumerator > 0 && tupletDenominator > 0 && !triplet) {
    warnings.add(`第 ${barIndex + 1} 小节包含非三连音连音组，编辑副本暂按直拍表示；原谱已保留。`);
  }

  let brush: StudioBeat['brush'] = null;
  if (brushType === 1) brush = 'up';
  if (brushType === 2) brush = 'down';
  if ((brushType === 1 || brushType === 2) && numberValue(sourceBeat.brushduration, 0) > 0) {
    warnings.add(`音轨「${track.name}」有自定义刷弦时长；编辑副本保留上/下方向，并按 AlphaTex 默认刷弦时长近似；原谱已保留。`);
  }

  const chords = record(sourceBeat._chords);
  const chordId = sourceBeat.chordid == null ? '' : String(sourceBeat.chordid);
  const chordName = chordId ? stringValue(record(chords[chordId]).name, chordId) : null;
  const explicitLyrics = cleanLyrics(sourceBeat.lyrics);
  const textFallback = cleanLyrics(sourceBeat.text);
  if (!explicitLyrics && textFallback) {
    warnings.add('外部谱拍文字可能是演奏标记；拍文字按歌词保留，请核对演奏标记。原谱已保留。');
  }
  return {
    id: generateUid('beat'),
    duration: durationFor(sourceBeat.duration, warnings),
    isRest: sourceBeat.isempty === true || notes.length === 0,
    dot: dots > 0,
    triplet,
    notes,
    chordName,
    // AlphaTex `txt` is represented as AlphaTab beat.text. Preserve it when no
    // explicit lyrics are available, while warning that ordinary text may be an instruction.
    lyrics: explicitLyrics ?? textFallback,
    brush,
  };
}

/** Convert AlphaTab's normalized score JSON into the editable fretboard-first model. */
export function alphaTabJsonToStudioProject(value: unknown, source?: StudioProject['source']): StudioImportResult {
  const score = record(normalizeScoreJson(record(value)));
  const masterBars: JsonObject[] = Array.isArray(score.masterbars) ? score.masterbars.map(record) : [];
  const sourceTracks: JsonObject[] = Array.isArray(score.tracks) ? score.tracks.map(record) : [];
  if (masterBars.length === 0 || sourceTracks.length === 0) throw new Error('谱面没有可读取的小节或音轨');

  const warnings = new Set<string>();
  const tracks: StudioTrack[] = [];
  const trackSourcePairs: Array<{ track: StudioTrack; staff: JsonObject }> = [];
  for (let index = 0; index < sourceTracks.length; index++) {
    const sourceTrack = sourceTracks[index];
    const staves: JsonObject[] = Array.isArray(sourceTrack.staves) ? sourceTrack.staves.map(record) : [];
    const playableStaff = staves.find((staff) => {
      const tuning = record(staff.stringtuning).tunings;
      return Array.isArray(tuning) && tuning.length > 0;
    }) ?? staves[0];
    if (!playableStaff) {
      warnings.add(`音轨「${stringValue(sourceTrack.name, `音轨 ${index + 1}`)}」没有可编辑的弦乐谱表，已从编辑副本中略过；原谱已保留。`);
      continue;
    }
    const track = sourceTrackToStudioTrack(sourceTrack, playableStaff, index, warnings);
    if (!track) {
      warnings.add(`音轨「${stringValue(sourceTrack.name, `音轨 ${index + 1}`)}」没有可用调弦，已从编辑副本中略过；原谱已保留。`);
      continue;
    }
    if (staves.length > 1) warnings.add(`音轨「${track.name}」有 ${staves.length} 个谱表，编辑副本采用带调弦的主谱表；其他谱表仍保留在原文件中。`);
    if (Array.isArray(playableStaff.bars) && playableStaff.bars.length !== masterBars.length) {
      warnings.add(`音轨「${track.name}」有 ${playableStaff.bars.length} 小节，与全曲 ${masterBars.length} 小节不一致；缺少的小节将留空；原谱已保留。`);
    }
    tracks.push(track);
    trackSourcePairs.push({ track, staff: playableStaff });
  }
  if (tracks.length === 0) throw new Error('没有可编辑的弦乐音轨。请先在曲库中预览原谱或使用 Guitar Pro 弦乐谱。');

  for (const { track, staff } of trackSourcePairs) {
    const multiVoiceBars = Array.isArray(staff.bars)
      ? staff.bars.filter((bar) => Array.isArray(record(bar).voices) && record(bar).voices.length > 1).length
      : 0;
    if (multiVoiceBars > 0) {
      warnings.add(`音轨「${track.name}」有 ${multiVoiceBars} 个小节包含多个声部；编辑副本只包含每小节的主声部，其他声部仍保留在原文件中。`);
    }
  }

  const bars = masterBars.map((masterBar, barIndex) => {
    const timeSignatureNumerator = clamp(Math.trunc(numberValue(masterBar.timesignaturenumerator, 4)), 1, 32);
    const timeSignatureDenominator = clamp(Math.trunc(numberValue(masterBar.timesignaturedenominator, 4)), 1, 32);
    const tempoAutomation = Array.isArray(masterBar.tempoautomations) ? masterBar.tempoautomations.map(record).find((entry) => Number(entry.type) === 0) : undefined;
    const section = stringValue(record(masterBar.section).text) || null;
    const trackBeats: StudioBar['trackBeats'] = {};

    for (const { track, staff } of trackSourcePairs) {
      const sourceBar = record((Array.isArray(staff.bars) ? staff.bars : [])[barIndex]);
      const voices: JsonObject[] = Array.isArray(sourceBar.voices) ? sourceBar.voices.map(record) : [];
      const sourceBeats: JsonObject[] = Array.isArray(voices[0]?.beats) ? voices[0].beats.map(record) : [];
      const chords = record(staff.chords);
      trackBeats[track.id] = sourceBeats.map((beat) => beatFromAlphaTab({ ...beat, _chords: chords }, track, warnings, barIndex));
    }

    const alternateEndings = Math.max(0, Math.trunc(numberValue(masterBar.alternateendings, 0)));
    let volta: number | null = null;
    if (alternateEndings > 0) {
      const bit = Math.floor(Math.log2(alternateEndings & -alternateEndings));
      volta = bit + 1;
      if ((alternateEndings & (alternateEndings - 1)) !== 0) warnings.add(`第 ${barIndex + 1} 小节包含多个房子结尾标记，编辑副本仅保留第一项；原谱已保留。`);
    }

    return {
      id: generateUid('bar'),
      index: barIndex,
      timeSignatureNumerator,
      timeSignatureDenominator,
      tempo: tempoAutomation ? numberValue(tempoAutomation.value, null as unknown as number) : null,
      section,
      repeatStart: masterBar.isrepeatstart === true,
      repeatEnd: typeof masterBar.isrepeatend === 'boolean' ? masterBar.isrepeatend : numberValue(masterBar.repeatcount, 0) > 0,
      repeatCount: clamp(Math.trunc(numberValue(masterBar.repeatcount, 2)), 2, 8),
      volta,
      trackBeats,
    };
  });

  const firstMasterBar = masterBars[0];
  const tempo = numberValue(score.tempo, numberValue(record(firstMasterBar.tempoautomations?.[0]).value, 120));
  const warningList = boundedImportWarnings(warnings);
  const project = normalizeStudioProject({
    ...createBlankProject('guitar'),
    id: generateUid('adaptation'),
    title: stringValue(score.title, '导入乐谱'),
    artist: stringValue(score.artist, UNKNOWN_IMPORTED_AUTHOR),
    album: stringValue(score.album),
    words: stringValue(score.words),
    music: stringValue(score.music),
    key: keyFromSignature(firstMasterBar.keysignature, firstMasterBar.keysignaturetype),
    initialTempo: clamp(Math.round(tempo), 20, 400),
    timeSignatureNumerator: bars[0].timeSignatureNumerator,
    timeSignatureDenominator: bars[0].timeSignatureDenominator,
    tracks,
    bars,
    source,
    importWarnings: warningList,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  });
  return { project, warnings: warningList, sourceFormat: source?.format ?? 'AlphaTab score JSON' };
}

function isStudioProject(value: JsonObject): boolean {
  return Array.isArray(value.tracks) && Array.isArray(value.bars) && value.bars.every((bar) => Array.isArray(record(bar).trackBeats) === false && record(bar).trackBeats && typeof record(bar).trackBeats === 'object');
}

function isAlphaTabJson(value: JsonObject): boolean {
  return Array.isArray(value.tracks) && Array.isArray(value.masterbars);
}

function alphaTexToJson(text: string): JsonObject {
  const score = importer.ScoreLoader.loadAlphaTex(text);
  return JSON.parse(model.JsonConverter.scoreToJson(score)) as JsonObject;
}

function extensionOf(fileName: string): string {
  return fileName.split('.').pop()?.toLowerCase() ?? '';
}

/** Import supported source formats. The file bytes are persisted separately by the caller before replacing the editor state. */
export async function importStudioScoreFile(file: File): Promise<StudioImportResult> {
  const extension = extensionOf(file.name);
  if (!IMPORT_EXTENSIONS.has(extension)) {
    throw new Error(`暂不支持 .${extension || 'unknown'} 文件。可导入：.ibe、Guitar Pro、MusicXML、AlphaTex 和工坊 JSON；MIDI 尚未接入。`);
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!bytes.length) throw new Error('文件为空，未载入工程。');

  if (extension === 'json') {
    let parsed: JsonObject;
    try { parsed = record(JSON.parse(new TextDecoder().decode(bytes))); }
    catch { throw new Error('JSON 文件内容损坏，未载入工程。'); }
    if (isStudioProject(parsed)) {
      const project = normalizeImportedArtist(normalizeStudioProject(parsed));
      project.id = generateUid('imported');
      project.title = `${project.title || '导入乐谱'}（个人副本）`;
      project.source = { kind: 'file', id: project.id, fileName: file.name, format: extension, title: project.title };
      return { project, warnings: project.importWarnings ?? [], sourceFormat: '工坊 JSON' };
    }
    if (isAlphaTabJson(parsed)) {
      return alphaTabJsonToStudioProject(parsed, { kind: 'file', id: generateUid('source'), fileName: file.name, format: extension, title: stringValue(parsed.title) });
    }
    throw new Error('JSON 文件既不是工坊工程，也不是 AlphaTab 乐谱数据。');
  }

  let alphaTabJson: JsonObject;
  if (extension === 'tex' || extension === 'alphatex') {
    try { alphaTabJson = alphaTexToJson(new TextDecoder().decode(bytes)); }
    catch (error) { throw new Error(`AlphaTex 解析失败：${error instanceof Error ? error.message : String(error)}`); }
  } else if (extension === 'ibe') {
    try {
      const [{ installBrowserAr }, { decodeIbeToJsonBrowser }] = await Promise.all([
        import('../ar.browser'),
        import('../ibe.browser'),
      ]);
      installBrowserAr();
      alphaTabJson = await decodeIbeToJsonBrowser(bytes);
    } catch (error) {
      throw new Error(`无法读取 ${extension.toUpperCase()} 乐谱：${error instanceof Error ? error.message : String(error)}`);
    }
  } else {
    const settings = new Settings();
    settings.player.enablePlayer = false;
    settings.player.playerMode = 0;
    try {
      const score = importer.ScoreLoader.loadScoreFromBytes(bytes, settings);
      alphaTabJson = JSON.parse(model.JsonConverter.scoreToJson(score)) as JsonObject;
    } catch (error) {
      throw new Error(`无法读取 ${extension.toUpperCase()} 乐谱：${error instanceof Error ? error.message : String(error)}`);
    }
  }

  const result = alphaTabJsonToStudioProject(alphaTabJson, {
    kind: 'file',
    id: generateUid('source'),
    fileName: file.name,
    format: extension,
    title: stringValue(alphaTabJson.title),
  });
  result.project.title = `${result.project.title || '导入乐谱'}（个人副本）`;
  result.project.updatedAt = Date.now();
  return result;
}

export async function importStudioScoreBytes(
  bytes: Uint8Array,
  fileName: string,
  source: NonNullable<StudioProject['source']>
): Promise<StudioImportResult> {
  const extension = extensionOf(fileName);
  let alphaTabJson: JsonObject;
  if (extension === 'json') {
    const parsed = record(JSON.parse(new TextDecoder().decode(bytes)));
    if (isStudioProject(parsed)) {
      const project = normalizeImportedArtist(normalizeStudioProject(parsed));
      project.id = generateUid('adaptation');
      project.source = source;
      project.title = `${project.title || '曲目'}（个人改编）`;
      return { project, warnings: project.importWarnings ?? [], sourceFormat: '工坊 JSON' };
    }
    alphaTabJson = parsed;
  } else if (extension === 'tex' || extension === 'alphatex') {
    alphaTabJson = alphaTexToJson(new TextDecoder().decode(bytes));
  } else if (extension === 'ibe') {
    const [{ installBrowserAr }, { decodeIbeToJsonBrowser }] = await Promise.all([
      import('../ar.browser'),
      import('../ibe.browser'),
    ]);
    installBrowserAr();
    alphaTabJson = await decodeIbeToJsonBrowser(bytes);
  } else {
    const settings = new Settings();
    settings.player.enablePlayer = false;
    settings.player.playerMode = 0;
    try {
      const score = importer.ScoreLoader.loadScoreFromBytes(bytes, settings);
      alphaTabJson = JSON.parse(model.JsonConverter.scoreToJson(score)) as JsonObject;
    } catch (cause) {
      throw new Error(`无法读取 ${extension.toUpperCase()} 乐谱：${cause instanceof Error ? cause.message : String(cause)}`);
    }
  }
  const result = alphaTabJsonToStudioProject(alphaTabJson, source);
  result.project.title = `${result.project.title || source.title || '曲目'}（个人改编）`;
  return result;
}

export function studioProjectToAlphaTabScore(project: StudioProject): any {
  const score = importer.ScoreLoader.loadAlphaTex(projectToAlphaTex(project));
  for (let index = 0; index < (score.tracks?.length ?? 0); index++) {
    const track = score.tracks[index];
    const studioTrack = project.tracks[index];
    for (const staff of track.staves ?? []) {
      staff.showStandardNotation = true;
      staff.showTablature = true;
    }
    const playback = track.playbackInfo;
    if (playback && studioTrack) {
      playback.volume = Math.round(clamp(studioTrack.volume, 0, 1) * 15);
      playback.balance = Math.round(clamp(studioTrack.pan, -1, 1) * 7 + 8);
      playback.isMute = studioTrack.mute;
      playback.isSolo = studioTrack.solo;
    }
  }
  for (let index = 0; index < (score.masterBars?.length ?? 0); index++) {
    const sourceBar = project.bars[index];
    const masterBar = score.masterBars[index];
    if (sourceBar && masterBar) {
      masterBar.keySignature = keySignatureValue(project.key);
      masterBar.keySignatureType = /m$/i.test(project.key) ? 1 : 0;
    }
  }
  return score;
}

function keySignatureValue(key: string): number {
  const signatures: Record<string, number> = {
    C: 0, G: 1, D: 2, A: 3, E: 4, B: 5, 'F#': 6, 'C#': 7,
    F: -1, Bb: -2, Eb: -3, Ab: -4, Db: -5, Gb: -6, Cb: -7,
    Am: 0, Em: 1, Bm: 2, 'F#m': 3, 'C#m': 4, 'G#m': 5, 'D#m': 6, 'A#m': 7,
    Dm: -1, Gm: -2, Cm: -3, Fm: -4, Bbm: -5, Ebm: -6, Abm: -7,
  };
  return signatures[key] ?? 0;
}

function triggerDownload(bytes: BlobPart, mime: string, filename: string): void {
  const safeName = filename.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').slice(0, 180) || 'score';
  const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = safeName;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 2000);
}

export async function encodeStudioProjectToMimiIbe(project: StudioProject): Promise<Uint8Array> {
  if (typeof CompressionStream === 'undefined') throw new Error('当前浏览器不支持压缩，无法生成 .ibe。请导出 Guitar Pro 7 或工程 JSON。');
  const score = studioProjectToAlphaTabScore(project);
  const rawScore = JSON.parse(model.JsonConverter.scoreToJson(score)) as JsonObject;
  const normalized = normalizeScoreJson(rawScore);
  const masterBars: JsonObject[] = Array.isArray(normalized.masterbars) ? normalized.masterbars : [];
  const keySignature = keySignatureValue(project.key);
  for (let index = 0; index < Math.min(project.bars.length, masterBars.length); index++) {
    const sourceBar = project.bars[index];
    const masterBar = masterBars[index];
    // AlphaTab 1.8.4 JsonConverter omits key signatures and repeat-end state.
    // Restore the project fields explicitly before writing the local IBE cache.
    masterBar.keysignature = keySignature;
    masterBar.keysignaturetype = /m$/i.test(project.key) ? 1 : 0;
    masterBar.isrepeatstart = sourceBar.repeatStart === true;
    masterBar.isrepeatend = sourceBar.repeatEnd === true;
    // AlphaTab derives isRepeatEnd from repeatCount > 0. Studio keeps a UI
    // default of 2 even on ordinary bars; serializing it would repeat every bar.
    masterBar.repeatcount = sourceBar.repeatEnd ? sourceBar.repeatCount ?? 2 : 0;
    masterBar.alternateendings = sourceBar.volta ? 2 ** (sourceBar.volta - 1) : 0;
  }

  // Studio stores chord labels without fingering diagrams. AlphaTex's hidden
  // diagram placeholder keeps the label through IBE normalization, which
  // intentionally discards chord records with no string array.
  const serializedTracks: JsonObject[] = Array.isArray(normalized.tracks) ? normalized.tracks : [];
  for (let trackIndex = 0; trackIndex < Math.min(project.tracks.length, serializedTracks.length); trackIndex++) {
    const sourceTrack = project.tracks[trackIndex];
    const sourceStaves: JsonObject[] = Array.isArray(serializedTracks[trackIndex].staves) ? serializedTracks[trackIndex].staves : [];
    const staff = sourceStaves[0];
    if (!staff) continue;
    const staffBars: JsonObject[] = Array.isArray(staff.bars) ? staff.bars : [];
    staff.chords = record(staff.chords);
    for (let barIndex = 0; barIndex < Math.min(project.bars.length, staffBars.length); barIndex++) {
      const beats = project.bars[barIndex].trackBeats[sourceTrack.id] ?? [];
      const voices: JsonObject[] = Array.isArray(staffBars[barIndex].voices) ? staffBars[barIndex].voices : [];
      const serializedBeats: JsonObject[] = Array.isArray(voices[0]?.beats) ? voices[0].beats : [];
      for (let beatIndex = 0; beatIndex < Math.min(beats.length, serializedBeats.length); beatIndex++) {
        const name = beats[beatIndex].chordName?.trim();
        if (!name) continue;
        const chordId = `mimi_${barIndex}_${beatIndex}`;
        staff.chords[chordId] = {
          name,
          firstfret: 1,
          strings: Array.from({ length: sourceTrack.tuning.length }, () => 0),
          showname: true,
          showdiagram: false,
          showfingering: false,
        };
        serializedBeats[beatIndex].chordid = chordId;
      }
    }
  }
  const data = new TextEncoder().encode(JSON.stringify(normalized));
  const compressor = new CompressionStream('deflate');
  const compressed = new Uint8Array(await new Response(new Blob([data]).stream().pipeThrough(compressor)).arrayBuffer());
  const encrypted = xorBytes(compressed, OUR_KEY);
  const magic = new TextEncoder().encode(OUR_MAGIC);
  const output = new Uint8Array(magic.length + encrypted.length);
  output.set(magic, 0);
  output.set(new Uint8Array(encrypted.buffer, encrypted.byteOffset, encrypted.length), magic.length);
  return output;
}

export type StudioExportFormat = 'json' | 'ibe' | 'gp' | 'tex';

/** Export only formats backed by a real serializer; extensions match the actual payload. */
export async function exportStudioProjectFile(project: StudioProject, format: StudioExportFormat): Promise<void> {
  const safeTitle = project.title || '乐谱工程';
  if (format === 'json') {
    const normalized = normalizeStudioProject(project);
    triggerDownload(JSON.stringify(normalized, null, 2), 'application/json;charset=utf-8', `${safeTitle}.json`);
    return;
  }
  const score = studioProjectToAlphaTabScore(project);
  if (format === 'tex') {
    const text = new exporter.AlphaTexExporter().exportToString(score, new Settings());
    triggerDownload(text, 'text/plain;charset=utf-8', `${safeTitle}.tex`);
    return;
  }
  if (format === 'gp') {
    const bytes = new exporter.Gp7Exporter().export(score, new Settings());
    triggerDownload(bytes, 'application/octet-stream', `${safeTitle}.gp`);
    return;
  }
  const bytes = await encodeStudioProjectToMimiIbe(project);
  triggerDownload(bytes, 'application/octet-stream', `${safeTitle}.ibe`);
}
