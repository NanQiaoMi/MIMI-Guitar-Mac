import type { PracticeFragment } from '../personal/types.ts';
import { validatePracticeFragmentApply } from '../personal/practiceFragments.ts';
import { createSpeedPlan, speedMultiplierAtAnchor } from './practiceProgress.ts';

export interface PracticeFragmentApplication {
  fragment: PracticeFragment;
  nativeAnchorBpm: number;
  playbackRatio: number;
}

/** Coordinates the durable pause boundary before changing any loop or speed. */
export async function applyPracticeFragmentSafely(options: {
  scoreId: string;
  scoreRevision: string;
  expectedUpdatedAt: number;
  load: () => Promise<PracticeFragment | null>;
  isCurrent: () => boolean;
  endTick: () => number;
  nativeTempoAtTick: (tick: number) => number | null;
  pauseAndSave: () => Promise<boolean>;
  clearPlan: () => Promise<void>;
  apply: (application: PracticeFragmentApplication) => void;
}): Promise<void> {
  const assertCurrent = () => {
    if (!options.isCurrent()) throw new Error('曲谱或练习状态已变化，片段未应用；请重试。');
  };
  async function readApplication(): Promise<PracticeFragmentApplication> {
    assertCurrent();
    const fragment = await options.load();
    assertCurrent();
    if (!fragment || fragment.updatedAt !== options.expectedUpdatedAt) throw new Error('片段已修改或删除，请载入最新内容后再应用。');
    validatePracticeFragmentApply(fragment, options.scoreId, options.scoreRevision, options.endTick());
    const nativeAnchorBpm = options.nativeTempoAtTick(fragment.range.startTick);
    if (nativeAnchorBpm === null) throw new Error('无法确认 A 点原生速度，请等待谱面就绪或重新选区。');
    createSpeedPlan(options.scoreRevision, fragment.speed.startBpm, fragment.speed.targetBpm,
      fragment.speed.stepBpm, fragment.speed.lapsPerLevel, nativeAnchorBpm, fragment.range);
    speedMultiplierAtAnchor(fragment.speed.targetBpm, nativeAnchorBpm);
    return { fragment, nativeAnchorBpm, playbackRatio: speedMultiplierAtAnchor(fragment.speed.startBpm, nativeAnchorBpm) };
  }

  await readApplication(); // Reject stale or invalid input before pausing.
  if (!await options.pauseAndSave()) throw new Error('暂停或本地保存未完成，片段尚未应用；请重试保存。');
  await readApplication(); // A different tab may have edited while storage was pending.
  await options.clearPlan();
  const application = await readApplication();
  assertCurrent();
  options.apply(application); // Synchronous; never starts audio or creates a session.
}
