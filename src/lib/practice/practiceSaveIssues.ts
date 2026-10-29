import { samePracticeSessionWriteContext, type PracticeSessionWriteContext } from './practiceProgress.ts';

export interface PracticeSaveIssueOwner {
  scoreKey: string;
  generation: number;
  sessionContext: PracticeSessionWriteContext | null;
}

export interface PracticeSaveIssue<K extends string = string> extends PracticeSaveIssueOwner {
  id: number;
  kind: K;
  message: string;
  retry?: () => Promise<unknown>;
}

export function samePracticeSaveIssueOwner(
  left: PracticeSaveIssueOwner,
  right: PracticeSaveIssueOwner,
): boolean {
  return left.scoreKey === right.scoreKey && left.generation === right.generation &&
    (left.sessionContext === null
      ? right.sessionContext === null
      : samePracticeSessionWriteContext(left.sessionContext, right.sessionContext));
}

/** Keep one latest visible issue per kind while preserving a unique retry token. */
export function upsertPracticeSaveIssue<T extends PracticeSaveIssue>(
  issues: readonly T[],
  issue: T,
): T[] {
  return [...issues.filter((candidate) => candidate.kind !== issue.kind), issue];
}

/** Clear only the issue owned by this operation; an older retry cannot erase a replacement. */
export function clearPracticeSaveIssue<T extends PracticeSaveIssue>(
  issues: readonly T[],
  kind: T['kind'],
  owner: PracticeSaveIssueOwner,
  issueId?: number,
): T[] {
  return issues.filter((candidate) => candidate.kind !== kind ||
    !samePracticeSaveIssueOwner(candidate, owner) ||
    (issueId !== undefined && candidate.id !== issueId));
}

export function practiceSaveIssueIsCurrent(
  issue: PracticeSaveIssue,
  currentOwner: PracticeSaveIssueOwner,
  issues: readonly PracticeSaveIssue[],
): boolean {
  return samePracticeSaveIssueOwner(issue, currentOwner) &&
    issues.some((candidate) => candidate.id === issue.id && candidate.kind === issue.kind);
}
