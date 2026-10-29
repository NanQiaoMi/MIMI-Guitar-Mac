import type { PersonalData, PersonalDataSnapshot } from './types.ts';
import { normalizeStudioProject } from '../studio/studioScoreModel.ts';

export const PERSONAL_SCHEMA_VERSION = 2;

export class PersonalDataValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PersonalDataValidationError';
  }
}

export function createEmptyPersonalData(): PersonalData {
  return {
    schemaVersion: PERSONAL_SCHEMA_VERSION,
    revision: 0,
    scores: [],
    favorites: [],
    practiceItems: [],
    practiceFragments: [],
    resumes: [],
    sessions: [],
    projects: [],
    originals: [],
    history: [],
    settings: {},
    migrationCompleted: false,
  };
}

function requireArray<T>(value: unknown, name: string): asserts value is T[] {
  if (!Array.isArray(value)) throw new PersonalDataValidationError(`${name} 必须是数组`);
}

function requireId(value: unknown, name: string): asserts value is string {
  if (typeof value !== 'string' || !value.trim() || value.length > 512) {
    throw new PersonalDataValidationError(`${name} 必须是非空字符串`);
  }
}

function requireFiniteNumber(value: unknown, name: string, min = Number.MIN_SAFE_INTEGER): asserts value is number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min) {
    throw new PersonalDataValidationError(`${name} 必须是有效数值`);
  }
}

export function isSafeLocalPath(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 2048 || !value.startsWith('/') || value.startsWith('//') || /[\\\u0000-\u001f\u007f]/.test(value)) return false;
  try {
    const decoded = decodeURIComponent(value);
    if (decoded.startsWith('//') || /[\\\u0000-\u001f\u007f]/.test(decoded)) return false;
    const parsed = new URL(value, 'https://mimi.invalid');
    return parsed.origin === 'https://mimi.invalid' && parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

function canonicalProject(value: unknown): string {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalProject).join(',')}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record).filter((key) => record[key] !== undefined).sort().map((key) => `${JSON.stringify(key)}:${canonicalProject(record[key])}`).join(',')}}`;
}

function validateStrictStudioProject(project: Record<string, unknown>): void {
  const assertKeys = (value: Record<string, unknown>, allowed: string[], label: string) => {
    if (Object.keys(value).some((key) => !allowed.includes(key))) throw new Error(`${label} 包含不支持的字段`);
  };
  const projectKeys = ['schemaVersion', 'id', 'title', 'artist', 'album', 'words', 'music', 'tabber', 'key', 'initialTempo', 'timeSignatureNumerator', 'timeSignatureDenominator', 'tracks', 'bars', 'source', 'importWarnings', 'createdAt', 'updatedAt'];
  assertKeys(project, projectKeys, '工程');
  if (project.schemaVersion !== undefined && project.schemaVersion !== 1) throw new Error('工程 schemaVersion 无效');
  for (const field of ['id', 'title', 'artist', 'key'] as const) {
    if (typeof project[field] !== 'string' || !project[field].trim() || project[field].length > 500) throw new Error(`工程 ${field} 无效`);
  }
  for (const field of ['album', 'words', 'music', 'tabber'] as const) {
    if (project[field] !== undefined && (typeof project[field] !== 'string' || project[field].length > 5000)) throw new Error(`工程 ${field} 无效`);
  }
  for (const field of ['initialTempo', 'timeSignatureNumerator', 'timeSignatureDenominator', 'createdAt', 'updatedAt'] as const) {
    if (typeof project[field] !== 'number' || !Number.isFinite(project[field])) throw new Error(`工程 ${field} 无效`);
  }
  if (!Number.isInteger(project.initialTempo) || Number(project.initialTempo) < 20 || Number(project.initialTempo) > 400) throw new Error('工程初始速度超出范围');
  for (const field of ['timeSignatureNumerator', 'timeSignatureDenominator'] as const) if (!Number.isInteger(project[field]) || Number(project[field]) < 1 || Number(project[field]) > 32) throw new Error(`工程 ${field} 超出范围`);
  if (!Array.isArray(project.tracks) || !Array.isArray(project.bars)) throw new Error('工程音轨或小节无效');
  if (project.tracks.length > 64 || project.bars.length > 10_000) throw new Error('工程音轨或小节数量超过安全上限');
  for (const [index, rawTrack] of project.tracks.entries()) {
    if (!rawTrack || typeof rawTrack !== 'object' || Array.isArray(rawTrack)) throw new Error(`音轨 ${index} 无效`);
    const track = rawTrack as Record<string, unknown>;
    assertKeys(track, ['id', 'name', 'program', 'tuning', 'tuningName', 'capo', 'volume', 'pan', 'mute', 'solo'], `音轨 ${index}`);
    if (typeof track.id !== 'string' || !track.id.trim() || typeof track.name !== 'string' || track.name.length > 500 || typeof track.tuningName !== 'string' || track.tuningName.length > 500) throw new Error(`音轨 ${index} 文本无效`);
    if (!Number.isInteger(track.program) || Number(track.program) < 0 || Number(track.program) > 127 || !Array.isArray(track.tuning) || track.tuning.some((v) => !Number.isInteger(v) || Number(v) < 0 || Number(v) > 127)) throw new Error(`音轨 ${index} 乐器或调弦无效`);
    if (!Number.isInteger(track.capo) || Number(track.capo) < 0 || Number(track.capo) > 24 || typeof track.volume !== 'number' || track.volume < 0 || track.volume > 1 || typeof track.pan !== 'number' || track.pan < -1 || track.pan > 1 || typeof track.mute !== 'boolean' || typeof track.solo !== 'boolean') throw new Error(`音轨 ${index} 控制参数超出范围`);
  }
  for (const [index, rawBar] of project.bars.entries()) {
    if (!rawBar || typeof rawBar !== 'object' || Array.isArray(rawBar)) throw new Error(`小节 ${index} 无效`);
    const bar = rawBar as Record<string, unknown>;
    assertKeys(bar, ['id', 'index', 'timeSignatureNumerator', 'timeSignatureDenominator', 'tempo', 'section', 'repeatStart', 'repeatEnd', 'repeatCount', 'volta', 'trackBeats'], `小节 ${index}`);
    if (typeof bar.id !== 'string' || !bar.id.trim() || !Number.isInteger(bar.index) || !Number.isInteger(bar.timeSignatureNumerator) || Number(bar.timeSignatureNumerator) < 1 || Number(bar.timeSignatureNumerator) > 32 || !Number.isInteger(bar.timeSignatureDenominator) || Number(bar.timeSignatureDenominator) < 1 || Number(bar.timeSignatureDenominator) > 32) throw new Error(`小节 ${index} 拍号或 ID 无效`);
    if (bar.tempo !== undefined && bar.tempo !== null && (typeof bar.tempo !== 'number' || !Number.isFinite(bar.tempo) || bar.tempo <= 0)) throw new Error(`小节 ${index} 速度无效`);
    if (bar.section !== undefined && bar.section !== null && (typeof bar.section !== 'string' || bar.section.length > 500)) throw new Error(`小节 ${index} 段落名无效`);
    if (bar.repeatCount !== undefined && (!Number.isInteger(bar.repeatCount) || Number(bar.repeatCount) < 2 || Number(bar.repeatCount) > 8)) throw new Error(`小节 ${index} 反复次数无效`);
    if (bar.volta !== undefined && bar.volta !== null && (!Number.isInteger(bar.volta) || Number(bar.volta) < 1 || Number(bar.volta) > 8)) throw new Error(`小节 ${index} 房子标记无效`);
    if (bar.trackBeats && typeof bar.trackBeats === 'object' && !Array.isArray(bar.trackBeats)) {
      let beatCount = 0;
      let noteCount = 0;
      for (const [trackId, rawBeats] of Object.entries(bar.trackBeats as Record<string, unknown>)) {
        if (!(project.tracks as Array<Record<string, unknown>>).some((track) => track.id === trackId)) throw new Error(`小节 ${index} 引用了未知音轨`);
        if (!Array.isArray(rawBeats)) throw new Error(`小节 ${index} 音轨数据无效`);
        beatCount += rawBeats.length;
        if (beatCount > 100_000) throw new Error('工程单小节拍数超过安全上限');
        for (const [beatIndex, rawBeat] of rawBeats.entries()) {
          if (!rawBeat || typeof rawBeat !== 'object' || Array.isArray(rawBeat)) throw new Error(`小节 ${index} 拍无效`);
          const beat = rawBeat as Record<string, unknown>;
          assertKeys(beat, ['id', 'duration', 'isRest', 'dot', 'triplet', 'notes', 'chordName', 'lyrics', 'brush'], `小节 ${index} 拍 ${beatIndex}`);
          if (typeof beat.id !== 'string' || !beat.id.trim() || typeof beat.isRest !== 'boolean' || typeof beat.dot !== 'boolean' || typeof beat.triplet !== 'boolean' || !Array.isArray(beat.notes)) throw new Error(`小节 ${index} 拍字段无效`);
          noteCount += beat.notes.length;
          if (noteCount > 100_000) throw new Error('工程单小节音符数超过安全上限');
          for (const [noteIndex, rawNote] of beat.notes.entries()) {
            if (!rawNote || typeof rawNote !== 'object' || Array.isArray(rawNote)) throw new Error(`小节 ${index} 音符无效`);
            assertKeys(rawNote as Record<string, unknown>, ['string', 'fret', 'tie', 'hammerPull', 'slide', 'bend', 'bendValue', 'harmonic', 'harmonicType', 'palmMute', 'dead', 'vibrato', 'accent', 'ghost'], `小节 ${index} 音符 ${noteIndex}`);
          }
        }
      }
    }
  }
  if (project.source !== undefined) {
    if (!project.source || typeof project.source !== 'object' || Array.isArray(project.source)) throw new Error('工程来源无效');
    const source = project.source as Record<string, unknown>;
    assertKeys(source, ['kind', 'id', 'fileName', 'format', 'title'], '工程来源');
    const supportedSourceFormats = new Set(['ibe', 'gp', 'gp3', 'gp4', 'gp5', 'gpx', 'gp7', 'gp8', 'musicxml', 'xml', 'tex', 'alphatex', 'json', 'unknown']);
    if (!['file', 'library'].includes(String(source.kind)) || typeof source.id !== 'string' || !source.id.trim() || source.id.length > 512 || typeof source.fileName !== 'string' || !source.fileName.trim() || source.fileName.length > 500 || /[\u0000-\u001f\u007f]/.test(source.fileName) || typeof source.format !== 'string' || !supportedSourceFormats.has(source.format.toLowerCase()) || (source.title !== undefined && (typeof source.title !== 'string' || source.title.length > 500))) throw new Error('工程来源字段无效');
  }
}

export function validatePersonalData(value: unknown, options: { strictProjects?: boolean } = {}): asserts value is PersonalDataSnapshot {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new PersonalDataValidationError('个人数据必须是对象');
  const data = value as Record<string, unknown>;
  if (data.schemaVersion !== 1 && data.schemaVersion !== PERSONAL_SCHEMA_VERSION) {
    throw new PersonalDataValidationError(`不支持的个人数据 schemaVersion：${String(data.schemaVersion)}`);
  }
  const isLegacySchema1 = data.schemaVersion === 1;
  if (isLegacySchema1 && Object.hasOwn(data, 'practiceFragments')) {
    throw new PersonalDataValidationError('schemaVersion 1 不支持 practiceFragments；请保留原始备份结构');
  }
  requireFiniteNumber(data.revision, 'revision', 0);
  for (const field of ['scores', 'favorites', 'practiceItems', 'resumes', 'sessions', 'projects', 'originals', 'history'] as const) {
    requireArray(data[field], field);
  }
  if (!isLegacySchema1) requireArray(data.practiceFragments, 'practiceFragments');
  if (!data.settings || typeof data.settings !== 'object' || Array.isArray(data.settings)) {
    throw new PersonalDataValidationError('settings 必须是对象');
  }
  for (const [key, item] of Object.entries(data.settings as Record<string, unknown>)) {
    if (!key || !['string', 'number', 'boolean'].includes(typeof item) || (typeof item === 'number' && !Number.isFinite(item))) {
      throw new PersonalDataValidationError(`settings.${key} 必须是字符串、有限数值或布尔值`);
    }
  }
  if (typeof data.migrationCompleted !== 'boolean') throw new PersonalDataValidationError('migrationCompleted 必须是布尔值');

  const scores = data.scores as Array<Record<string, unknown>>;
  const scoreIds = new Set<string>();
  for (const [index, score] of scores.entries()) {
    requireId(score.id, `scores[${index}].id`);
    if (scoreIds.has(score.id)) throw new PersonalDataValidationError(`scores 中存在重复 ID：${score.id}`);
    scoreIds.add(score.id);
    requireId(score.source, `scores[${index}].source`);
    requireId(score.sourceId, `scores[${index}].sourceId`);
    requireId(score.revision, `scores[${index}].revision`);
    requireId(score.title, `scores[${index}].title`);
    if (typeof score.artist !== 'string' || score.artist.length > 500) throw new PersonalDataValidationError(`scores[${index}].artist 无效`);
    if (score.title.length > 500) throw new PersonalDataValidationError(`scores[${index}].title 超长`);
    if (!['catalog', 'private', 'project'].includes(String(score.source))) throw new PersonalDataValidationError(`scores[${index}].source 无效`);
    if (!['guitar', 'ukulele', 'bass'].includes(String(score.category))) throw new PersonalDataValidationError(`scores[${index}].category 无效`);
    if (!['ibe', 'gp', 'xhe', 'project'].includes(String(score.format))) throw new PersonalDataValidationError(`scores[${index}].format 无效`);
    requireFiniteNumber(score.createdAt, `scores[${index}].createdAt`, 0);
    requireFiniteNumber(score.updatedAt, `scores[${index}].updatedAt`, 0);
    if (score.scoreUrl !== undefined) {
      if (!isSafeLocalPath(score.scoreUrl)) {
        throw new PersonalDataValidationError(`scores[${index}].scoreUrl 必须是站点内的安全路径`);
      }
    }
    for (const field of ['assetId', 'originalAssetId', 'projectId'] as const) {
      if (score[field] !== undefined) requireId(score[field], `scores[${index}].${field}`);
    }
  }
  const uniqueStrings = new Set<string>();
  for (const [index, id] of (data.favorites as unknown[]).entries()) {
    requireId(id, `favorites[${index}]`);
    if (uniqueStrings.has(id)) throw new PersonalDataValidationError(`favorites 中存在重复 ID：${id}`);
    uniqueStrings.add(id);
    if (!scoreIds.has(id)) throw new PersonalDataValidationError(`favorites[${index}] 引用了不存在的曲谱：${id}`);
  }
  uniqueStrings.clear();
  for (const [index, item] of (data.practiceItems as Array<Record<string, unknown>>).entries()) {
    requireId(item.scoreId, `practiceItems[${index}].scoreId`);
    if (uniqueStrings.has(item.scoreId)) throw new PersonalDataValidationError(`practiceItems 中存在重复曲谱：${item.scoreId}`);
    uniqueStrings.add(item.scoreId);
    if (!scoreIds.has(item.scoreId)) throw new PersonalDataValidationError(`practiceItems[${index}] 引用了不存在的曲谱：${item.scoreId}`);
    if (!['todo', 'practicing', 'mastered', 'archived'].includes(String(item.status))) throw new PersonalDataValidationError(`practiceItems[${index}].status 无效`);
    if (typeof item.note !== 'string') throw new PersonalDataValidationError(`practiceItems[${index}].note 必须是字符串`);
    requireFiniteNumber(item.order, `practiceItems[${index}].order`);
    requireFiniteNumber(item.updatedAt, `practiceItems[${index}].updatedAt`, 0);
  }
  uniqueStrings.clear();
  for (const [index, resume] of (data.resumes as Array<Record<string, unknown>>).entries()) {
    requireId(resume.scoreId, `resumes[${index}].scoreId`);
    if (uniqueStrings.has(resume.scoreId)) throw new PersonalDataValidationError(`resumes 中存在重复曲谱：${resume.scoreId}`);
    uniqueStrings.add(resume.scoreId);
    if (!scoreIds.has(resume.scoreId)) throw new PersonalDataValidationError(`resumes[${index}] 引用了不存在的曲谱：${resume.scoreId}`);
    requireId(resume.scoreRevision, `resumes[${index}].scoreRevision`);
    for (const field of ['tick', 'timeMs', 'speed', 'capo', 'transpose', 'updatedAt'] as const) requireFiniteNumber(resume[field], `resumes[${index}].${field}`, field === 'transpose' ? Number.MIN_SAFE_INTEGER : field === 'capo' ? -1 : 0);
    if (Number(resume.speed) < 20 || Number(resume.speed) > 300) throw new PersonalDataValidationError(`resumes[${index}].speed 超出 20–300 BPM 范围`);
    if (resume.playbackRatio !== undefined && (typeof resume.playbackRatio !== 'number' || !Number.isFinite(resume.playbackRatio) || resume.playbackRatio < 0.125 || resume.playbackRatio > 8)) {
      throw new PersonalDataValidationError(`resumes[${index}].playbackRatio 超出 0.125–8 范围`);
    }
    if (resume.trackMix !== undefined) {
      requireArray(resume.trackMix, `resumes[${index}].trackMix`);
      if (resume.trackMix.length > 1024) throw new PersonalDataValidationError(`resumes[${index}].trackMix 最多保存 1024 条音轨混音`);
      const mixIndexes = new Set<number>();
      for (const [mixIndex, rawMix] of resume.trackMix.entries()) {
        if (!rawMix || typeof rawMix !== 'object' || Array.isArray(rawMix)) throw new PersonalDataValidationError(`resumes[${index}].trackMix[${mixIndex}] 无效`);
        const mix = rawMix as Record<string, unknown>;
        if (!Number.isSafeInteger(mix.index) || Number(mix.index) < 0 || Number(mix.index) > 1023 || mixIndexes.has(Number(mix.index))) {
          throw new PersonalDataValidationError(`resumes[${index}].trackMix[${mixIndex}].index 必须唯一且在 0–1023 范围`);
        }
        mixIndexes.add(Number(mix.index));
        if (typeof mix.muted !== 'boolean' || typeof mix.soloed !== 'boolean') throw new PersonalDataValidationError(`resumes[${index}].trackMix[${mixIndex}] 静音/独奏设置无效`);
        requireFiniteNumber(mix.volume, `resumes[${index}].trackMix[${mixIndex}].volume`, 0);
        if (Number(mix.volume) > 100) throw new PersonalDataValidationError(`resumes[${index}].trackMix[${mixIndex}].volume 超出 0–100 范围`);
        if (!Number.isSafeInteger(mix.program) || Number(mix.program) < 0 || Number(mix.program) > 127) throw new PersonalDataValidationError(`resumes[${index}].trackMix[${mixIndex}].program 超出 0–127 范围`);
        if (mix.instrumentOverride !== undefined && typeof mix.instrumentOverride !== 'boolean') {
          throw new PersonalDataValidationError(`resumes[${index}].trackMix[${mixIndex}].instrumentOverride 必须为布尔值`);
        }
      }
    }
    if (resume.display !== undefined) {
      if (!resume.display || typeof resume.display !== 'object' || Array.isArray(resume.display)) throw new PersonalDataValidationError(`resumes[${index}].display 无效`);
      const display = resume.display as Record<string, unknown>;
      requireFiniteNumber(display.fontScale, `resumes[${index}].display.fontScale`, 0.6);
      if (Number(display.fontScale) > 1.6) throw new PersonalDataValidationError(`resumes[${index}].display.fontScale 超出 0.6–1.6 范围`);
      if (!['name', 'diagram'].includes(String(display.chordMode))) throw new PersonalDataValidationError(`resumes[${index}].display.chordMode 无效`);
      if (!['mixed', 'tab'].includes(String(display.scoreDisplayMode))) throw new PersonalDataValidationError(`resumes[${index}].display.scoreDisplayMode 无效`);
      if (typeof display.numberTab !== 'boolean' || typeof display.showFretboard !== 'boolean') throw new PersonalDataValidationError(`resumes[${index}].display 开关必须为布尔值`);
    }
    if (resume.useSourceCapo !== undefined && typeof resume.useSourceCapo !== 'boolean') throw new PersonalDataValidationError(`resumes[${index}].useSourceCapo 必须为布尔值`);
    if (!Number.isInteger(resume.capo) || Number(resume.capo) > 24) throw new PersonalDataValidationError(`resumes[${index}].capo 超出 -1–24 范围（-1 为降半调调弦）`);
    if (!Number.isInteger(resume.transpose) || Number(resume.transpose) < -48 || Number(resume.transpose) > 48) throw new PersonalDataValidationError(`resumes[${index}].transpose 超出 -48–48 半音范围`);
    if (resume.loop !== null) {
      if (!resume.loop || typeof resume.loop !== 'object') throw new PersonalDataValidationError(`resumes[${index}].loop 无效`);
      const loop = resume.loop as Record<string, unknown>;
      requireFiniteNumber(loop.startTick, `resumes[${index}].loop.startTick`, 0);
      requireFiniteNumber(loop.endTick, `resumes[${index}].loop.endTick`, 0);
      if (loop.endTick <= loop.startTick) throw new PersonalDataValidationError(`resumes[${index}].loop 必须包含至少一个 tick`);
    }
    requireArray(resume.trackIndexes, `resumes[${index}].trackIndexes`);
    if ((resume.trackIndexes as unknown[]).some((trackIndex) => !Number.isSafeInteger(trackIndex) || Number(trackIndex) < 0)) {
      throw new PersonalDataValidationError(`resumes[${index}].trackIndexes 必须是非负整数`);
    }
    if (typeof resume.metronome !== 'boolean' || typeof resume.countIn !== 'boolean') throw new PersonalDataValidationError(`resumes[${index}] 播放设置无效`);
  }
  uniqueStrings.clear();
  for (const [index, session] of (data.sessions as Array<Record<string, unknown>>).entries()) {
    requireId(session.id, `sessions[${index}].id`);
    if (uniqueStrings.has(session.id)) throw new PersonalDataValidationError(`sessions 中存在重复 ID：${session.id}`);
    uniqueStrings.add(session.id);
    requireId(session.scoreId, `sessions[${index}].scoreId`);
    if (!scoreIds.has(session.scoreId)) throw new PersonalDataValidationError(`sessions[${index}] 引用了不存在的曲谱：${session.scoreId}`);
    requireId(session.scoreRevision, `sessions[${index}].scoreRevision`);
    if (!['active', 'paused', 'interrupted', 'completed'].includes(String(session.state))) throw new PersonalDataValidationError(`sessions[${index}].state 无效`);
    requireFiniteNumber(session.startedAt, `sessions[${index}].startedAt`, 0);
    requireFiniteNumber(session.updatedAt, `sessions[${index}].updatedAt`, 0);
    requireId(session.timezone, `sessions[${index}].timezone`);
    if (typeof session.note !== 'string' || session.note.length > 5000) throw new PersonalDataValidationError(`sessions[${index}].note 必须是 5000 字以内的字符串`);
    if (session.endedAt !== undefined) requireFiniteNumber(session.endedAt, `sessions[${index}].endedAt`, 0);
    if (session.speedPlan !== undefined) {
      if (!session.speedPlan || typeof session.speedPlan !== 'object') throw new PersonalDataValidationError(`sessions[${index}].speedPlan 无效`);
      const plan = session.speedPlan as Record<string, unknown>;
      for (const field of ['startBpm', 'targetBpm', 'stepBpm', 'currentBpm'] as const) requireFiniteNumber(plan[field], `sessions[${index}].speedPlan.${field}`, 0);
      for (const field of ['lapsPerLevel', 'completedLaps'] as const) requireFiniteNumber(plan[field], `sessions[${index}].speedPlan.${field}`, 0);
      requireId(plan.revision, `sessions[${index}].speedPlan.revision`);
      if ([plan.startBpm, plan.targetBpm, plan.currentBpm].some((bpm) => Number(bpm) < 20 || Number(bpm) > 300) || Number(plan.stepBpm) <= 0 || Number(plan.lapsPerLevel) < 1 || !Number.isInteger(plan.lapsPerLevel) || !Number.isInteger(plan.completedLaps)) {
        throw new PersonalDataValidationError(`sessions[${index}].speedPlan 参数超出范围`);
      }
      if (plan.nativeAnchorBpm !== undefined && (typeof plan.nativeAnchorBpm !== 'number' || !Number.isFinite(plan.nativeAnchorBpm) || plan.nativeAnchorBpm <= 0 || plan.nativeAnchorBpm > 1000)) {
        throw new PersonalDataValidationError(`sessions[${index}].speedPlan.nativeAnchorBpm 超出 0–1000 BPM 范围`);
      }
      if (plan.loopRange !== undefined) {
        const range = plan.loopRange as Record<string, unknown> | null;
        if (!range || typeof range !== 'object' || !Number.isInteger(range.startTick) || !Number.isInteger(range.endTick) || Number(range.startTick) < 0 || Number(range.endTick) <= Number(range.startTick)) {
          throw new PersonalDataValidationError(`sessions[${index}].speedPlan.loopRange 无效`);
        }
      }
    }
    requireArray(session.slices, `sessions[${index}].slices`);
    const sliceIds = new Set<string>();
    const sliceSequences = new Set<string>();
    for (const [sliceIndex, slice] of (session.slices as Array<Record<string, unknown>>).entries()) {
      requireId(slice.id, `sessions[${index}].slices[${sliceIndex}].id`);
      if (sliceIds.has(slice.id)) throw new PersonalDataValidationError(`sessions[${index}] 存在重复 slice ID：${slice.id}`);
      sliceIds.add(slice.id);
      requireId(slice.epoch, `sessions[${index}].slices[${sliceIndex}].epoch`);
      for (const field of ['sequence', 'startedAt', 'durationMs'] as const) requireFiniteNumber(slice[field], `sessions[${index}].slices[${sliceIndex}].${field}`, 0);
      const seqKey = `${slice.epoch}\0${slice.sequence}`;
      if (sliceSequences.has(seqKey)) throw new PersonalDataValidationError(`sessions[${index}] 存在重复检查点 sequence`);
      sliceSequences.add(seqKey);
    }
  }
  if (!isLegacySchema1) {
    const fragmentIds = new Set<string>();
    const fragments = data.practiceFragments as Array<Record<string, unknown>>;
    for (const [index, fragment] of fragments.entries()) {
      const label = `practiceFragments[${index}]`;
      if (!fragment || typeof fragment !== 'object' || Array.isArray(fragment)) throw new PersonalDataValidationError(`${label} 必须是对象`);
      requireId(fragment.id, `${label}.id`);
      if (fragmentIds.has(fragment.id)) throw new PersonalDataValidationError(`practiceFragments 中存在重复 ID：${fragment.id}`);
      fragmentIds.add(fragment.id);
      requireId(fragment.scoreId, `${label}.scoreId`);
      if (!scoreIds.has(fragment.scoreId)) throw new PersonalDataValidationError(`${label} 引用了不存在的曲谱：${fragment.scoreId}`);
      if (typeof fragment.scoreRevision !== 'string' || !/^[a-f0-9]{64}$/.test(fragment.scoreRevision)) {
        throw new PersonalDataValidationError(`${label}.scoreRevision 必须是小写 SHA-256`);
      }
      if (typeof fragment.name !== 'string' || fragment.name.trim() !== fragment.name || !fragment.name.trim() || fragment.name.length > 120 || /[\u0000-\u001f\u007f]/.test(fragment.name)) {
        throw new PersonalDataValidationError(`${label}.name 必须是 1–120 字符的有效名称`);
      }
      if (typeof fragment.note !== 'string' || fragment.note.length > 5000) throw new PersonalDataValidationError(`${label}.note 必须是 5000 字符以内的字符串`);
      if (!fragment.range || typeof fragment.range !== 'object' || Array.isArray(fragment.range)) throw new PersonalDataValidationError(`${label}.range 无效`);
      const range = fragment.range as Record<string, unknown>;
      if (!Number.isSafeInteger(range.startTick) || Number(range.startTick) < 0 || !Number.isSafeInteger(range.endTick) || Number(range.endTick) <= Number(range.startTick)) {
        throw new PersonalDataValidationError(`${label}.range 必须是非负安全整数 tick 的半开区间`);
      }
      if (!fragment.speed || typeof fragment.speed !== 'object' || Array.isArray(fragment.speed)) throw new PersonalDataValidationError(`${label}.speed 无效`);
      const speed = fragment.speed as Record<string, unknown>;
      for (const field of ['nativeAnchorBpm', 'startBpm', 'targetBpm', 'stepBpm'] as const) requireFiniteNumber(speed[field], `${label}.speed.${field}`, 0);
      if (!Number.isSafeInteger(speed.lapsPerLevel) || Number(speed.lapsPerLevel) < 1) throw new PersonalDataValidationError(`${label}.speed.lapsPerLevel 必须是正整数`);
      const nativeAnchorBpm = Number(speed.nativeAnchorBpm);
      const startBpm = Number(speed.startBpm);
      const targetBpm = Number(speed.targetBpm);
      const stepBpm = Number(speed.stepBpm);
      if (nativeAnchorBpm < 1 || nativeAnchorBpm > 1000 || startBpm < 20 || startBpm > 300 || targetBpm < startBpm || targetBpm > 300 || stepBpm <= 0 ||
        startBpm / nativeAnchorBpm < 0.125 || startBpm / nativeAnchorBpm > 8 || targetBpm / nativeAnchorBpm < 0.125 || targetBpm / nativeAnchorBpm > 8) {
        throw new PersonalDataValidationError(`${label}.speed 参数超出有效范围`);
      }
      requireFiniteNumber(fragment.createdAt, `${label}.createdAt`, 0);
      requireFiniteNumber(fragment.updatedAt, `${label}.updatedAt`, 0);
      if (Number(fragment.updatedAt) < Number(fragment.createdAt)) throw new PersonalDataValidationError(`${label}.updatedAt 不能早于 createdAt`);
      if (fragment.deletedAt !== undefined) {
        requireFiniteNumber(fragment.deletedAt, `${label}.deletedAt`, 0);
        if (Number(fragment.deletedAt) > Number(fragment.updatedAt)) throw new PersonalDataValidationError(`${label}.deletedAt 不能晚于 updatedAt`);
      }
    }
  }
  requireArray(data.projects, 'projects');
  uniqueStrings.clear();
  for (const [index, project] of (data.projects as Array<Record<string, unknown>>).entries()) {
    requireId(project.id, `projects[${index}].id`);
    if (uniqueStrings.has(project.id)) throw new PersonalDataValidationError(`projects 中存在重复 ID：${project.id}`);
    uniqueStrings.add(project.id);
    try {
      if (options.strictProjects) validateStrictStudioProject(project);
      const normalized = normalizeStudioProject(project);
      if (normalized.id !== project.id) throw new Error('工程 ID 被规范化');
      if (options.strictProjects && canonicalProject(normalized) !== canonicalProject(project)) {
        const comparable = structuredClone(normalized) as unknown as Record<string, unknown>;
        if (!Object.hasOwn(project, 'schemaVersion')) delete comparable.schemaVersion;
        comparable.bars = normalized.bars.map((bar, barIndex) => {
          const rawBar = (project.bars as Array<Record<string, unknown>>)[barIndex];
          const copy = structuredClone(bar) as unknown as Record<string, unknown>;
          for (const [key, defaultValue] of Object.entries({ repeatStart: false, repeatEnd: false, repeatCount: 2, volta: null, tempo: null, section: null })) {
            if (!Object.hasOwn(rawBar, key) && (bar as unknown as Record<string, unknown>)[key] === defaultValue) delete copy[key];
          }
          const beats = copy.trackBeats as Record<string, Array<Record<string, unknown>>>;
          const rawBeats = rawBar.trackBeats as Record<string, Array<Record<string, unknown>>>;
          for (const trackId of Object.keys(beats)) for (const [beatIndex, beat] of beats[trackId].entries()) {
            if (!Object.hasOwn(rawBeats[trackId][beatIndex], 'brush') && beat.brush === null) delete beat.brush;
          }
          return copy;
        });
        if (canonicalProject(comparable) !== canonicalProject(project)) throw new Error('工程包含无法往返的字段');
      }
    } catch (error) {
      throw new PersonalDataValidationError(`projects[${index}] 无法校验：${error instanceof Error ? error.message : String(error)}`);
    }
  }
  uniqueStrings.clear();
  for (const [index, original] of (data.originals as Array<Record<string, unknown>>).entries()) {
    requireId(original.id, `originals[${index}].id`);
    if (uniqueStrings.has(original.id)) throw new PersonalDataValidationError(`originals 中存在重复 ID：${original.id}`);
    uniqueStrings.add(original.id);
    requireId(original.fileName, `originals[${index}].fileName`);
    requireId(original.mimeType, `originals[${index}].mimeType`);
    requireId(original.assetId, `originals[${index}].assetId`);
    requireFiniteNumber(original.savedAt, `originals[${index}].savedAt`, 0);
  }
  for (const [index, entry] of (data.history as Array<Record<string, unknown>>).entries()) {
    requireId(entry.id, `history[${index}].id`);
    requireId(entry.title, `history[${index}].title`);
    requireId(entry.url, `history[${index}].url`);
    if (!isSafeLocalPath(entry.url)) throw new PersonalDataValidationError(`history[${index}].url 必须是站点内的安全路径`);
    requireFiniteNumber(entry.time, `history[${index}].time`, 0);
  }
}

export function normalizePersonalData(value: unknown): PersonalData {
  if (value === undefined || value === null) return createEmptyPersonalData();
  validatePersonalData(value);
  const snapshot = value as PersonalDataSnapshot;
  if (snapshot.schemaVersion === PERSONAL_SCHEMA_VERSION) return snapshot;
  return { ...snapshot, schemaVersion: PERSONAL_SCHEMA_VERSION, practiceFragments: [] };
}
