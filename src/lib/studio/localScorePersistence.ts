/**
 * MIMI Guitar · local draft persistence
 * Edits and recovery snapshots use localStorage; imported original files use IndexedDB.
 */

import { normalizeStudioProject, type StudioProject } from './studioScoreModel.ts';

const DRAFT_KEY_PREFIX = 'mimi_studio_draft_';
export const STUDIO_DRAFT_KEY = 'mimi_studio_draft_score';

export interface DraftMeta {
  id: string;
  title: string;
  artist: string;
  updatedAt: number;
  trackCount: number;
  barCount: number;
}

/** Read primary drafts, falling back to backups left by earlier save attempts. */
function readStoredDrafts(): StudioProject[] {
  const primary = new Map<string, StudioProject>();
  const backups = new Map<string, StudioProject>();
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key || !key.startsWith(DRAFT_KEY_PREFIX) || key === STUDIO_DRAFT_KEY) continue;
      try {
        const raw = localStorage.getItem(key);
        if (!raw) continue;
        const project = normalizeStudioProject(JSON.parse(raw));
        const primaryKey = `${DRAFT_KEY_PREFIX}${project.id}`;
        if (key === primaryKey) primary.set(project.id, project);
        else if (key === `${primaryKey}_backup`) backups.set(project.id, project);
      } catch { /* one corrupt snapshot must not hide another valid draft */ }
    }
  } catch { /* retain snapshots read before storage became unavailable */ }
  for (const [id, project] of backups) if (!primary.has(id)) primary.set(id, project);
  return [...primary.values()];
}

/** 自动保存当前工程快照 */
export function saveDraftToStorage(project: StudioProject): boolean {
  if (typeof window === 'undefined') return false;
  try {
    const normalized = normalizeStudioProject(project);
    const newestSavedAt = readStoredDrafts().reduce((latest, draft) => Math.max(latest, draft.updatedAt ?? 0), 0);
    normalized.updatedAt = Math.max(Date.now(), newestSavedAt + 1);

    const serialized = JSON.stringify(normalized);
    const targetKey = `${DRAFT_KEY_PREFIX}${normalized.id}`;
    // A single setItem is the commit point. On quota/security failure the
    // browser preserves the previous bytes; a second backup write adds risk.
    localStorage.setItem(targetKey, serialized);
    return localStorage.getItem(targetKey) === serialized;
  } catch (e) {
    console.warn('[localScorePersistence] save draft failed:', e);
    return false;
  }
}

/** 加载最近编辑的工程草稿 */
export function loadLatestDraftFromStorage(): StudioProject | null {
  if (typeof window === 'undefined') return null;
  const drafts: StudioProject[] = [];
  try {
    drafts.push(...readStoredDrafts());
  } catch { /* retain any drafts already read */ }

  const newest = drafts.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0))[0];
  if (newest) return newest;

  // One-time migration for installations that only have the legacy direct snapshot.
  try {
    const directRaw = localStorage.getItem(STUDIO_DRAFT_KEY);
    if (!directRaw) return null;
    const legacy = normalizeStudioProject(JSON.parse(directRaw));
    if (!localStorage.getItem(`${DRAFT_KEY_PREFIX}${legacy.id}`)) {
      try { localStorage.setItem(`${DRAFT_KEY_PREFIX}${legacy.id}`, JSON.stringify(legacy)); } catch { /* keep legacy source readable */ }
    }
    return legacy;
  } catch {
    return null;
  }
}

/** 列出本地保存的所有草稿元数据 */
export function listLocalDrafts(): DraftMeta[] {
  if (typeof window === 'undefined') return [];
  const list: DraftMeta[] = [];
  try {
    for (const p of readStoredDrafts()) {
      list.push({
        id: p.id,
        title: p.title || '未命名乐谱',
        artist: p.artist || '原创作者',
        updatedAt: p.updatedAt || Date.now(),
        trackCount: p.tracks?.length || 1,
        barCount: p.bars?.length || 0,
      });
    }
  } catch {}
  return list.sort((a, b) => b.updatedAt - a.updatedAt);
}

/** 删除指定本地草稿 */
export function deleteDraftFromStorage(id: string): void {
  if (typeof window === 'undefined') return;
  try {
    const backupKey = `${DRAFT_KEY_PREFIX}${id}_backup`;
    const backupRaw = localStorage.getItem(backupKey);
    try {
      // An imported project ID may itself end in _backup; preserve that project.
      if (backupRaw && normalizeStudioProject(JSON.parse(backupRaw)).id === id) localStorage.removeItem(backupKey);
    } catch { /* an unreadable backup must not block deletion of the primary */ }
    localStorage.removeItem(`${DRAFT_KEY_PREFIX}${id}`);
    const directRaw = localStorage.getItem(STUDIO_DRAFT_KEY);
    if (directRaw && normalizeStudioProject(JSON.parse(directRaw)).id === id) localStorage.removeItem(STUDIO_DRAFT_KEY);
  } catch {}
}
