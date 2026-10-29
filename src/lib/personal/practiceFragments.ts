import type { PersonalData, PracticeFragment, PracticeFragmentSpeed } from './types.ts';
import { mutatePersonalData } from './repository.ts';

export type { PracticeFragmentSpeed } from './types.ts';

export interface CreatePracticeFragmentInput {
  scoreId: string;
  scoreRevision: string;
  name: string;
  note: string;
  range: { startTick: number; endTick: number };
  speed: PracticeFragmentSpeed;
}

export type UpdatePracticeFragmentPatch = { name?: string; note?: string };

export class PracticeFragmentConflictError extends Error {
  readonly id: string;
  readonly expectedUpdatedAt: number;
  readonly actualUpdatedAt: number | null;

  constructor(id: string, expectedUpdatedAt: number, actualUpdatedAt: number | null) {
    super(actualUpdatedAt === null
      ? '练习片段已删除或不存在，请重新载入后再试'
      : '练习片段已在其他页面更新，请重新载入后再试');
    this.name = 'PracticeFragmentConflictError';
    this.id = id;
    this.expectedUpdatedAt = expectedUpdatedAt;
    this.actualUpdatedAt = actualUpdatedAt;
  }
}

const SHA256 = /^[a-f0-9]{64}$/;

function cloneFragment(fragment: PracticeFragment): PracticeFragment {
  return structuredClone(fragment);
}

function requireTimestamp(value: number, label: string): void {
  if (!Number.isFinite(value) || value < 0) throw new Error(`${label} 必须是非负有限时间戳`);
}

function normalizeName(value: unknown): string {
  if (typeof value !== 'string') throw new Error('片段名称必须是文本');
  const name = value.trim();
  if (!name || name.length > 120 || /[\u0000-\u001f\u007f]/.test(name)) throw new Error('片段名称必须为 1–120 个有效字符');
  return name;
}

function validateNote(value: unknown): string {
  if (typeof value !== 'string' || value.length > 5000) throw new Error('片段备注必须是 5000 字符以内的文本');
  return value;
}

function validateInput(input: CreatePracticeFragmentInput): void {
  if (!input || typeof input !== 'object') throw new Error('练习片段无效');
  if (typeof input.scoreId !== 'string' || !input.scoreId.trim()) throw new Error('曲谱编号无效');
  if (typeof input.scoreRevision !== 'string' || !SHA256.test(input.scoreRevision)) throw new Error('练习片段必须绑定可信的曲谱 SHA-256');
  normalizeName(input.name);
  validateNote(input.note);
  const { startTick, endTick } = input.range ?? {};
  if (!Number.isSafeInteger(startTick) || startTick < 0 || !Number.isSafeInteger(endTick) || endTick <= startTick) {
    throw new Error('A-B 区间必须是非负安全整数 tick 的半开区间');
  }
  const { nativeAnchorBpm, startBpm, targetBpm, stepBpm, lapsPerLevel } = input.speed ?? {};
  if (![nativeAnchorBpm, startBpm, targetBpm, stepBpm].every(Number.isFinite) ||
    nativeAnchorBpm < 1 || nativeAnchorBpm > 1000 || startBpm < 20 || startBpm > 300 || targetBpm < startBpm || targetBpm > 300 || stepBpm <= 0 ||
    startBpm / nativeAnchorBpm < 0.125 || startBpm / nativeAnchorBpm > 8 || targetBpm / nativeAnchorBpm < 0.125 || targetBpm / nativeAnchorBpm > 8 ||
    !Number.isSafeInteger(lapsPerLevel) || lapsPerLevel < 1) {
    throw new Error('提速参数超出有效范围');
  }
}

function nextTimestamp(now: number, previous?: number): number {
  requireTimestamp(now, '操作时间');
  return previous === undefined ? now : Math.max(now, previous + 1);
}

function newId(): string {
  if (!globalThis.crypto?.randomUUID) throw new Error('当前环境缺少安全随机数，无法创建练习片段');
  return globalThis.crypto.randomUUID();
}

/** Lists a score's reusable fragments, hiding tombstones unless explicitly requested. */
export function listPracticeFragments(
  data: Pick<PersonalData, 'practiceFragments'>,
  scoreId: string,
  includeDeleted = false,
): PracticeFragment[] {
  return data.practiceFragments
    .filter((fragment) => fragment.scoreId === scoreId && (includeDeleted || fragment.deletedAt === undefined))
    .map(cloneFragment)
    .sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id));
}

/** Creates only against the exact score bytes currently stored in the same IDB mutation. */
export async function createPracticeFragment(input: CreatePracticeFragmentInput, now = Date.now()): Promise<PracticeFragment> {
  if (!input || typeof input !== 'object') throw new Error('练习片段无效');
  const snapshot: CreatePracticeFragmentInput = {
    scoreId: input.scoreId,
    scoreRevision: input.scoreRevision,
    name: input.name,
    note: input.note,
    range: { startTick: input.range?.startTick, endTick: input.range?.endTick },
    speed: {
      nativeAnchorBpm: input.speed?.nativeAnchorBpm,
      startBpm: input.speed?.startBpm,
      targetBpm: input.speed?.targetBpm,
      stepBpm: input.speed?.stepBpm,
      lapsPerLevel: input.speed?.lapsPerLevel,
    },
  };
  validateInput(snapshot);
  snapshot.name = normalizeName(snapshot.name);
  requireTimestamp(now, '操作时间');
  const id = newId();
  const created = await mutatePersonalData((draft) => {
    const score = draft.scores.find((candidate) => candidate.id === snapshot.scoreId);
    if (!score || score.revision !== snapshot.scoreRevision) throw new Error('曲谱版本已变化或不在本机资料中；请重新载入曲谱后保存片段');
    if (draft.practiceFragments.some((fragment) => fragment.id === id)) throw new Error('生成了重复的练习片段编号，请重试');
    const timestamp = nextTimestamp(now);
    draft.practiceFragments.push({
      id,
      scoreId: snapshot.scoreId,
      scoreRevision: snapshot.scoreRevision,
      name: snapshot.name,
      note: snapshot.note,
      range: { ...snapshot.range },
      speed: { ...snapshot.speed },
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  });
  const fragment = created.practiceFragments.find((candidate) => candidate.id === id);
  if (!fragment) throw new Error('练习片段保存结果丢失');
  return cloneFragment(fragment);
}

/** Updates editable metadata with compare-and-swap to prevent stale tabs overwriting each other. */
export async function updatePracticeFragment(
  id: string,
  expectedUpdatedAt: number,
  patch: UpdatePracticeFragmentPatch,
  now = Date.now(),
): Promise<PracticeFragment> {
  if (typeof id !== 'string' || !id.trim()) throw new Error('练习片段编号无效');
  if (!Number.isFinite(expectedUpdatedAt) || expectedUpdatedAt < 0) throw new Error('练习片段预期版本无效');
  if (!patch || typeof patch !== 'object' || Array.isArray(patch) || Object.keys(patch).some((key) => key !== 'name' && key !== 'note') || Object.keys(patch).length === 0) {
    throw new Error('练习片段更新内容无效');
  }
  const normalizedPatch: UpdatePracticeFragmentPatch = {};
  if (Object.hasOwn(patch, 'name')) normalizedPatch.name = normalizeName(patch.name);
  if (Object.hasOwn(patch, 'note')) normalizedPatch.note = validateNote(patch.note);
  requireTimestamp(now, '操作时间');
  const updated = await mutatePersonalData((draft) => {
    const fragment = draft.practiceFragments.find((candidate) => candidate.id === id);
    if (!fragment || fragment.deletedAt !== undefined || fragment.updatedAt !== expectedUpdatedAt) {
      throw new PracticeFragmentConflictError(id, expectedUpdatedAt, fragment?.updatedAt ?? null);
    }
    Object.assign(fragment, normalizedPatch);
    fragment.updatedAt = nextTimestamp(now, fragment.updatedAt);
  });
  const fragment = updated.practiceFragments.find((candidate) => candidate.id === id);
  if (!fragment) throw new Error('练习片段更新结果丢失');
  return cloneFragment(fragment);
}

/** Deletes by retaining a timestamped tombstone for full-backup merge safety. */
export async function deletePracticeFragment(id: string, expectedUpdatedAt: number, now = Date.now()): Promise<void> {
  if (typeof id !== 'string' || !id.trim()) throw new Error('练习片段编号无效');
  if (!Number.isFinite(expectedUpdatedAt) || expectedUpdatedAt < 0) throw new Error('练习片段预期版本无效');
  requireTimestamp(now, '操作时间');
  await mutatePersonalData((draft) => {
    const fragment = draft.practiceFragments.find((candidate) => candidate.id === id);
    if (!fragment || fragment.deletedAt !== undefined || fragment.updatedAt !== expectedUpdatedAt) {
      throw new PracticeFragmentConflictError(id, expectedUpdatedAt, fragment?.updatedAt ?? null);
    }
    const deletedAt = nextTimestamp(now, fragment.updatedAt);
    fragment.updatedAt = deletedAt;
    fragment.deletedAt = deletedAt;
  });
}

/** Fail-closed guard used before a UI applies a saved loop and speed plan. */
export function validatePracticeFragmentApply(
  fragment: PracticeFragment,
  scoreId: string,
  scoreRevision: string,
  endTick: number,
): void {
  if (!fragment || typeof fragment !== 'object' || fragment.deletedAt !== undefined) throw new Error('该练习片段已删除，不能应用');
  if (fragment.scoreId !== scoreId || fragment.scoreRevision !== scoreRevision || !SHA256.test(scoreRevision)) {
    throw new Error('练习片段属于其他曲谱或旧版本；请重新选择区间');
  }
  if (!Number.isSafeInteger(endTick) || endTick < 0 || !Number.isSafeInteger(fragment.range.startTick) || !Number.isSafeInteger(fragment.range.endTick) ||
    fragment.range.startTick < 0 || fragment.range.endTick <= fragment.range.startTick || fragment.range.endTick > endTick) {
    throw new Error('练习片段区间已超出当前曲谱范围；请重新选择区间');
  }
  validateInput({
    scoreId: fragment.scoreId,
    scoreRevision: fragment.scoreRevision,
    name: fragment.name,
    note: fragment.note,
    range: fragment.range,
    speed: fragment.speed,
  });
}
