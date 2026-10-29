import { mutatePersonalData } from './repository.ts';
import { isSafeLocalPath } from './validation.ts';
import type { PersonalScore } from './types.ts';
import { appendPracticeQueueItem, setPracticeQueueStatus } from './practiceQueue.ts';

export interface CatalogScoreInput {
  id: string;
  title: string;
  artist?: string | null;
  category: string;
  format?: string | null;
  scoreUrl?: string;
}

export function toCatalogScore(input: CatalogScoreInput, now = Date.now()): PersonalScore {
  if (!input.id.trim() || !input.title.trim()) throw new Error('曲谱编号或标题缺失，未写入个人资料');
  const category = input.category === 'ukulele' ? 'ukulele' : input.category === 'bass' ? 'bass' : 'guitar';
  const format = input.format === 'gp' || input.format === 'xhe' || input.format === 'project' ? input.format : 'ibe';
  return {
    id: `catalog:${input.id}`,
    source: 'catalog',
    sourceId: input.id,
    revision: 'unverified',
    title: input.title.trim(),
    artist: input.artist?.trim() ?? '',
    category,
    format,
    ...(input.scoreUrl && isSafeLocalPath(input.scoreUrl) ? { scoreUrl: input.scoreUrl } : {}),
    createdAt: now,
    updatedAt: now,
  };
}

export async function addCatalogFavorite(input: CatalogScoreInput, favorite = true): Promise<void> {
  if (!favorite) {
    await mutatePersonalData((draft) => { draft.favorites = draft.favorites.filter((id) => id !== `catalog:${input.id}`); });
    return;
  }
  const score = toCatalogScore(input);
  await mutatePersonalData((draft) => {
    const existingIndex = draft.scores.findIndex((item) => item.id === score.id);
    if (existingIndex < 0) draft.scores.push(score);
    else {
      const existing = draft.scores[existingIndex];
      draft.scores[existingIndex] = { ...score, ...existing, title: score.title, artist: score.artist, category: score.category, format: score.format, scoreUrl: score.scoreUrl, updatedAt: score.updatedAt };
    }
    const index = draft.favorites.indexOf(score.id);
    if (favorite && index < 0) draft.favorites.push(score.id);
    if (!favorite && index >= 0) draft.favorites.splice(index, 1);
  });
}

export async function addCatalogPractice(input: CatalogScoreInput): Promise<void> {
  const score = toCatalogScore(input);
  await mutatePersonalData((draft) => {
    const existingIndex = draft.scores.findIndex((item) => item.id === score.id);
    if (existingIndex < 0) draft.scores.push(score);
    else {
      const existing = draft.scores[existingIndex];
      draft.scores[existingIndex] = { ...score, ...existing, title: score.title, artist: score.artist, category: score.category, format: score.format, scoreUrl: score.scoreUrl, updatedAt: score.updatedAt };
    }
    const practiceItem = draft.practiceItems.find((item) => item.scoreId === score.id);
    if (!practiceItem) {
      draft.practiceItems = appendPracticeQueueItem(draft.practiceItems, { scoreId: score.id, status: 'todo', note: '', order: 0, updatedAt: Date.now() });
    } else if (practiceItem.status === 'archived') {
      draft.practiceItems = setPracticeQueueStatus(draft.practiceItems, score.id, 'todo')
        .map((item) => item.scoreId === score.id ? { ...item, updatedAt: Date.now() } : item);
    }
  });
}
