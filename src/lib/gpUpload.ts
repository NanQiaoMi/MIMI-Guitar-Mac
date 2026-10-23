import * as at from '@coderline/alphatab';
import { dirname } from 'node:path';
import { decodeIbeToJsonNode, encodeJsonToIbeNode } from './ibe.node.ts';

/** 服务端 Guitar Pro 上传处理：解析 → 元数据 → 自有 MIMI .ibe 编码 */

export interface GpMeta {
  title: string;
  artist: string | null;
  tempo: number | null;
  timeSig: string | null;
  capo: number;
  tuningText: string | null;
  sheetForm: number;
  hasTablature: boolean;
}

export interface ParsedGp {
  json: Record<string, unknown>;
  ibe: Uint8Array;
  meta: GpMeta;
}

export type GpStructureErrorCode = 'EMPTY_SCORE' | 'NO_TABLATURE' | 'NO_BARS' | 'NO_NOTES';

/** A parsed file can still be unusable as an editable guitar tablature. */
export class GpStructureError extends Error {
  readonly code: GpStructureErrorCode;

  constructor(code: GpStructureErrorCode, message: string) {
    super(message);
    this.name = 'GpStructureError';
    this.code = code;
  }
}

export interface EditableStringStructure {
  editableTrackCount: number;
  editableStaffCount: number;
  editableBarCount: number;
  editableNoteCount: number;
  firstTrack: at.model.Track;
  firstStaff: at.model.Staff;
}

export interface StagedUploadInput {
  scorePath: string;
  scoreBytes: Uint8Array;
  screenshotPath: string;
  screenshotUrl: string;
  recordData: (screenshotUrl: string | null) => Record<string, unknown>;
}

export interface StagedUploadDependencies {
  ensureDirectory(path: string): void | Promise<void>;
  createExclusiveFile(path: string, bytes: Uint8Array): void | Promise<void>;
  removeFile(path: string): void | Promise<void>;
  renderScreenshot(path: string): Promise<boolean>;
  createRecord(data: Record<string, unknown>): Promise<unknown>;
}

/** Stage owned files first, then create the DB row; clean only files created by this attempt. */
export async function stageUploadAndCreateRecord(
  input: StagedUploadInput,
  dependencies: StagedUploadDependencies,
): Promise<{ screenshotUrl: string | null }> {
  const createdFiles: string[] = [];
  const cleanup = async () => {
    for (const path of [...createdFiles].reverse()) {
      try {
        await dependencies.removeFile(path);
      } catch {
        // Preserve the original failure; cleanup is best-effort.
      }
    }
  };

  await dependencies.ensureDirectory(dirname(input.scorePath));
  try {
    await dependencies.createExclusiveFile(input.scorePath, input.scoreBytes);
    createdFiles.push(input.scorePath);

    let screenshotUrl: string | null = null;
    try {
      await dependencies.ensureDirectory(dirname(input.screenshotPath));
      // Reserve the path exclusively so the renderer cannot overwrite a prior upload.
      await dependencies.createExclusiveFile(input.screenshotPath, new Uint8Array());
      createdFiles.push(input.screenshotPath);
      if (await dependencies.renderScreenshot(input.screenshotPath)) {
        screenshotUrl = input.screenshotUrl;
      } else {
        await dependencies.removeFile(input.screenshotPath);
        createdFiles.splice(createdFiles.indexOf(input.screenshotPath), 1);
      }
    } catch {
      // Screenshot generation is optional, but only remove the path if this attempt reserved it.
      const screenshotIndex = createdFiles.indexOf(input.screenshotPath);
      if (screenshotIndex !== -1) {
        await dependencies.removeFile(input.screenshotPath);
        createdFiles.splice(screenshotIndex, 1);
      }
    }

    await dependencies.createRecord(input.recordData(screenshotUrl));
    return { screenshotUrl };
  } catch (error) {
    await cleanup();
    throw error;
  }
}

export function validateStoredEditableIbe(bytes: Uint8Array): void {
  try {
    const jsonScore = decodeIbeToJsonNode(bytes);
    const settings = new at.Settings();
    settings.player.enablePlayer = false;
    const score = at.model.JsonConverter.jsonToScore(JSON.stringify(jsonScore), settings);
    inspectEditableStringStructure(score);
  } catch (error) {
    if (error instanceof GpStructureError) throw error;
    throw new Error('原始曲谱文件损坏或无法解析，请重新上传。');
  }
}

export class ExistingTabError extends Error {
  constructor() {
    super('该曲谱已存在');
    this.name = 'ExistingTabError';
  }
}

/** Execute both catalog writes within the caller's database transaction. */
export async function createApprovedTabAtomically(
  transaction: (work: (tx: any) => Promise<void>) => Promise<unknown>,
  id: string,
  tabData: Record<string, unknown>,
): Promise<void> {
  await transaction(async (tx) => {
    const existing = await tx.tab.findUnique({ where: { id } });
    if (existing) throw new ExistingTabError();
    await tx.tab.create({ data: tabData });
    await tx.uploadRecord.update({ where: { id }, data: { status: 'approved', tabId: id } });
  });
}

/** Validate that AlphaTab produced at least one note-bearing string tablature staff. */
export function inspectEditableStringStructure(score: at.model.Score): EditableStringStructure {
  if (!score || !Array.isArray(score.tracks) || score.tracks.length === 0 ||
      !Array.isArray(score.masterBars) || score.masterBars.length === 0) {
    throw new GpStructureError('EMPTY_SCORE', '乐谱没有可用的小节或音轨，请换一个有效的 Guitar Pro 文件。');
  }

  const tabStaves = score.tracks.flatMap((track) =>
    (track.staves ?? [])
      .filter((staff) => !track.isPercussion && staff.isStringed && staff.showTablature &&
        Array.isArray(staff.tuning) && staff.tuning.length > 0)
      .map((staff) => ({ track, staff })),
  );
  if (tabStaves.length === 0) {
    throw new GpStructureError('NO_TABLATURE', '文件中没有带有效调弦的六线谱轨道，暂时无法作为吉他或尤克里里谱编辑。');
  }

  const withBars = tabStaves.map(({ track, staff }) => ({ track, staff, bars: staff.bars ?? [] }))
    .filter(({ bars }) => bars.length > 0);
  if (withBars.length === 0) {
    throw new GpStructureError('NO_BARS', '六线谱轨道中没有小节，请检查文件后重新上传。');
  }

  const playable = withBars.flatMap(({ track, staff, bars }) => {
    const stringCount = staff.tuning.length;
    let staffNoteCount = 0;
    for (const bar of bars) {
      for (const voice of bar.voices ?? []) {
        for (const beat of voice.beats ?? []) {
          for (const note of beat.notes ?? []) {
            if (Number.isInteger(note.string) && note.string >= 1 && note.string <= stringCount) {
              staffNoteCount++;
            }
          }
        }
      }
    }
    return staffNoteCount > 0 ? [{ track, staff, bars, noteCount: staffNoteCount }] : [];
  });
  const editableNoteCount = playable.reduce((sum, { noteCount }) => sum + noteCount, 0);
  if (editableNoteCount === 0 || playable.length === 0) {
    throw new GpStructureError('NO_NOTES', '六线谱中没有可编辑的弦上音符；只有空小节或休止符的文件不能入库。');
  }

  return {
    editableTrackCount: new Set(playable.map(({ track }) => track)).size,
    editableStaffCount: playable.length,
    editableBarCount: playable.reduce((sum, { bars }) => sum + bars.length, 0),
    editableNoteCount,
    firstTrack: playable[0].track,
    firstStaff: playable[0].staff,
  };
}

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/** 解析 GP 二进制 → alphaTab Score → JSON → MIMI .ibe；无法解析时抛出异常 */
export function parseGpToIbe(bytes: Uint8Array): ParsedGp {
  const settings = new at.Settings();
  settings.player.enablePlayer = false;
  const score = at.importer.ScoreLoader.loadScoreFromBytes(bytes, settings);
  const structure = inspectEditableStringStructure(score);
  const jsonStr = at.model.JsonConverter.scoreToJson(score);
  const json = JSON.parse(jsonStr) as Record<string, unknown>;
  const ibe = encodeJsonToIbeNode(json);

  const title = String(score.title || '').trim();
  const artist = score.artist ? String(score.artist).trim() || null : null;
  const tempo = typeof score.tempo === 'number' && score.tempo > 0 ? score.tempo : null;
  const firstMasterBar = score.masterBars[0];
  const timeSig = firstMasterBar
    ? `${firstMasterBar.timeSignatureNumerator}/${firstMasterBar.timeSignatureDenominator}`
    : null;

  const staff = structure.firstStaff;
  const capo = typeof staff.capo === 'number' ? staff.capo : 0;
  const hasTablature = true;

  let tuningText: string | null = null;
  if (staff.tuning.length > 0) {
    // alphaTab tuning 为从低到高的 MIDI 音高数组
    tuningText = Array.from(staff.tuning)
      .map((t) => NOTE_NAMES[((t % 12) + 12) % 12])
      .join(',');
  }

  const sheetForm = hasTablature ? 4 : 0; // 4 = 六线谱
  return { json, ibe, meta: { title, artist, tempo, timeSig, capo, tuningText, sheetForm, hasTablature } };
}

/** 从文件头判断是否像 Guitar Pro 文件（非强校验，最终以解析结果为准） */
export function looksLikeGp(bytes: Uint8Array): boolean {
  if (bytes.length < 4) return false;
  const head = new TextDecoder('latin1').decode(bytes.subarray(0, 4));
  return head.startsWith('FICHIER') || head.startsWith('gp') || (bytes[0] === 0x1f && bytes[1] === 0x8b);
}
