import { hashBytes, readAsset } from './repository.ts';
import type { PersonalScore } from './types.ts';

export interface PlayableScoreAsset {
  bytes: Uint8Array;
  mimeType: string;
}

/** Reads an immutable personal score revision and abandons a result after selection changes. */
export async function readPlayableScoreAsset(
  score: PersonalScore,
  isCurrent: () => boolean = () => true,
): Promise<PlayableScoreAsset | null> {
  if (score.source === 'catalog') throw new Error('曲库曲谱不使用个人附件。');
  if (!score.assetId) throw new Error('这份个人谱缺少可播放版本。原件不会被删除。');

  const asset = await readAsset(score.assetId);
  if (!isCurrent()) return null;
  if (!asset) throw new Error('找不到本地可播放附件。可尝试从备份恢复。');
  const bytes = new Uint8Array(asset.bytes);
  const revision = await hashBytes(bytes);
  if (!isCurrent()) return null;
  if (asset.id !== score.assetId || revision !== score.revision) {
    throw new Error('本地练习谱附件与当前曲谱版本不一致，请从我的谱重新加入待练。');
  }
  return { bytes, mimeType: asset.mimeType };
}
