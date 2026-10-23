import { hashBytes, mutatePersonalData, readPersonalData } from './repository.ts';
import type { PersonalAsset } from './types.ts';
import { buildProjectPracticePayload } from './projectPractice.ts';
import { normalizeStudioProject, type StudioProject } from '../studio/studioScoreModel.ts';
import { appendPracticeQueueItem, setPracticeQueueStatus } from './practiceQueue.ts';

let lastProjectSaveAt = 0;
const loadedProjectVersions = new Map<string, number | null>();
let saveQueue: Promise<void> = Promise.resolve();

function projectMeta(project: StudioProject) {
  const normalized = normalizeStudioProject(project);
  normalized.updatedAt = Math.max(Date.now(), (normalized.updatedAt ?? 0) + 1, lastProjectSaveAt + 1);
  lastProjectSaveAt = normalized.updatedAt;
  return normalized;
}

function enqueueStudioProjectSave(
  project: StudioProject,
  original: { id: string; fileName: string; mimeType: string; bytes: Uint8Array } | undefined,
  addToPractice: boolean,
): Promise<void> {
  // Capture call-time inputs before waiting behind another same-page save.
  const capturedProject = normalizeStudioProject(project);
  const capturedOriginal = original ? { ...original, bytes: original.bytes.slice() } : undefined;
  const operation = saveQueue.then(async () => {
    const normalized = projectMeta(capturedProject);
    const expectedVersion = loadedProjectVersions.has(normalized.id) ? loadedProjectVersions.get(normalized.id)! : null;
    const scoreId = `project:${normalized.id}`;
    const beforeSave = await readPersonalData();
    const existingPracticeScore = beforeSave.scores.some((score) => score.id === scoreId);
    const shouldRefreshPracticeScore = addToPractice || existingPracticeScore;
    // Conversion, compression, and hashing finish before the IndexedDB transaction opens.
    // The transaction below still checks the version this editor originally loaded.
    const practicePayload = shouldRefreshPracticeScore
      ? await buildProjectPracticePayload(normalized, normalized.updatedAt)
      : null;
    const assetsById = new Map<string, PersonalAsset>();
    let originalRef: { id: string; fileName: string; mimeType: string; assetId: string; savedAt: number } | undefined;
    if (capturedOriginal) {
      const bytes = capturedOriginal.bytes;
      const assetId = await hashBytes(bytes);
      assetsById.set(assetId, { id: assetId, mimeType: capturedOriginal.mimeType || 'application/octet-stream', bytes: bytes.buffer as ArrayBuffer });
      originalRef = { id: capturedOriginal.id, fileName: capturedOriginal.fileName, mimeType: capturedOriginal.mimeType || 'application/octet-stream', assetId, savedAt: Date.now() };
    }
    if (practicePayload) assetsById.set(practicePayload.asset.id, practicePayload.asset);
    await mutatePersonalData((data) => {
      const index = data.projects.findIndex((entry) => entry.id === normalized.id);
      const currentVersion = index < 0 ? null : data.projects[index].updatedAt;
      if (currentVersion !== expectedVersion) {
        throw new Error(`工坊工程“${normalized.title || normalized.id}”已在其他页面更新。为防止覆盖，当前保存未写入；请重新载入并合并改动。`);
      }
      const scoreIndex = data.scores.findIndex((score) => score.id === scoreId);
      if (!addToPractice && existingPracticeScore && scoreIndex < 0) {
        throw new Error('这份工程的练习谱刚被移除；为避免保存不一致版本，请重新载入后再试。');
      }
      if (!practicePayload && scoreIndex >= 0) {
        throw new Error('这份工程刚加入练习；当前保存缺少对应的播放版本，请重新保存。');
      }
      if (index < 0) data.projects.push(normalized);
      else data.projects[index] = normalized;
      if (practicePayload) {
        const oldScore = scoreIndex >= 0 ? data.scores[scoreIndex] : null;
        const nextScore = { ...practicePayload.score, createdAt: oldScore?.createdAt ?? normalized.createdAt, updatedAt: normalized.updatedAt };
        if (scoreIndex < 0) data.scores.push(nextScore);
        else data.scores[scoreIndex] = { ...oldScore, ...nextScore };
        if (addToPractice) {
          const item = data.practiceItems.find((entry) => entry.scoreId === scoreId);
          if (!item) {
            data.practiceItems = appendPracticeQueueItem(data.practiceItems, { scoreId, status: 'todo', note: '', order: 0, updatedAt: normalized.updatedAt });
          } else if (item.status === 'archived') {
            data.practiceItems = setPracticeQueueStatus(data.practiceItems, scoreId, 'todo')
              .map((entry) => entry.scoreId === scoreId ? { ...entry, updatedAt: normalized.updatedAt } : entry);
          }
        }
      }
      if (originalRef) {
        const existing = data.originals.findIndex((entry) => entry.id === originalRef!.id);
        if (existing < 0) data.originals.push(originalRef);
        else data.originals[existing] = originalRef;
      }
    }, { assets: [...assetsById.values()] });
    loadedProjectVersions.set(normalized.id, normalized.updatedAt);
  });
  saveQueue = operation.catch(() => undefined);
  return operation;
}

export function saveStudioProject(project: StudioProject, original?: { id: string; fileName: string; mimeType: string; bytes: Uint8Array }): Promise<void> {
  return enqueueStudioProjectSave(project, original, false);
}

/** Save the current editor version and its playable IBE cache as one atomic personal-data change. */
export function saveStudioProjectForPractice(project: StudioProject): Promise<void> {
  return enqueueStudioProjectSave(project, undefined, true);
}

export async function listStudioProjects(): Promise<StudioProject[]> {
  return (await readPersonalData()).projects.map((project) => normalizeStudioProject(project));
}

export async function loadStudioProject(id: string): Promise<StudioProject | null> {
  const project = (await listStudioProjects()).find((entry) => entry.id === id) ?? null;
  rememberStudioProjectVersion(project);
  return project;
}

/** Record the version a page started editing; an unknown new ID is expected to be absent on first save. */
export function rememberStudioProjectVersion(project: StudioProject | null): void {
  if (project) loadedProjectVersions.set(project.id, project.updatedAt ?? 0);
}

export async function deleteStudioProject(id: string): Promise<void> {
  await mutatePersonalData((data) => {
    const linkedScore = data.scores.find((score) => score.projectId === id || (score.source === 'project' && score.sourceId === id));
    if (linkedScore) {
      throw new Error('这份工程已保存为练习谱，当前不支持删除关联工程。原始文件和当前练习版本会继续保留；你仍可打开工程继续编辑或练习。');
    }
    data.projects = data.projects.filter((project) => project.id !== id);
  });
}
