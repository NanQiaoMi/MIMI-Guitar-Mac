import { encodeStudioProjectToMimiIbe } from '../studio/studioScoreBridge.ts';
import type { StudioProject } from '../studio/studioScoreModel.ts';
import type { PersonalAsset, PersonalScore } from './types.ts';
import { hashBytes } from './repository.ts';

const MAX_PLAYABLE_SCORE_BYTES = 30 * 1024 * 1024;
const PROJECT_SCORE_MIME = 'application/vnd.mimi.score';

export interface ProjectPracticePayload {
  score: PersonalScore;
  asset: PersonalAsset;
}

function projectCategory(project: StudioProject): PersonalScore['category'] {
  const primary = project.tracks.find((track) => track.tuning.length > 0);
  if (!primary) throw new Error('工程没有可用于练习的弦乐音轨。');
  if (primary.program >= 32 && primary.program <= 39) return 'bass';
  if (primary.tuning.length === 4 && primary.tuning.every((pitch) => pitch >= 55) && primary.program >= 24 && primary.program <= 31) {
    return 'ukulele';
  }
  return 'guitar';
}

/** Build the complete playable IBE asset and its content-addressed personal score record. */
export async function buildProjectPracticePayload(project: StudioProject, now = Date.now()): Promise<ProjectPracticePayload> {
  const bytes = await encodeStudioProjectToMimiIbe(project);
  if (bytes.byteLength === 0) throw new Error('工坊没有生成可播放的 IBE 谱，未加入练习。');
  if (bytes.byteLength > MAX_PLAYABLE_SCORE_BYTES) {
    throw new Error('工程练习版超过 30 MiB，未加入待练；原工程和原始文件仍保存在草稿箱。');
  }

  const assetId = await hashBytes(bytes);
  const exactBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  return {
    score: {
      id: `project:${project.id}`,
      source: 'project',
      sourceId: project.id,
      projectId: project.id,
      revision: assetId,
      title: project.title.trim() || '未命名乐谱',
      artist: project.artist.trim(),
      category: projectCategory(project),
      format: 'ibe',
      assetId,
      createdAt: project.createdAt,
      updatedAt: now,
    },
    asset: { id: assetId, mimeType: PROJECT_SCORE_MIME, bytes: exactBytes },
  };
}
