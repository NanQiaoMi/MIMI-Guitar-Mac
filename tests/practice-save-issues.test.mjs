import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  clearPracticeSaveIssue,
  practiceSaveIssueIsCurrent,
  samePracticeSaveIssueOwner,
  upsertPracticeSaveIssue,
} from '../src/lib/practice/practiceSaveIssues.ts';

const session = { scoreId: 'score-1', scoreRevision: 'rev-1', sessionId: 'session-1' };
const owner = { scoreKey: 'score-1:rev-1', generation: 4, sessionContext: session };

test('a late retry can clear only its own issue token, never a replacement of the same kind', () => {
  const first = { ...owner, id: 1, kind: 'note', message: 'first' };
  const replacement = { ...owner, id: 2, kind: 'note', message: 'replacement' };
  const issues = upsertPracticeSaveIssue([first], replacement);

  assert.deepEqual(issues, [replacement]);
  assert.deepEqual(clearPracticeSaveIssue(issues, 'note', owner, first.id), [replacement]);
  assert.equal(practiceSaveIssueIsCurrent(first, owner, issues), false);
  assert.equal(practiceSaveIssueIsCurrent(replacement, owner, issues), true);
  assert.deepEqual(clearPracticeSaveIssue(issues, 'note', owner, replacement.id), []);
});

test('retry ownership becomes stale after a score, generation, or session change', () => {
  assert.equal(samePracticeSaveIssueOwner(owner, { ...owner }), true);
  assert.equal(samePracticeSaveIssueOwner(owner, { ...owner, scoreKey: 'score-2:rev-2' }), false);
  assert.equal(samePracticeSaveIssueOwner(owner, { ...owner, generation: 5 }), false);
  assert.equal(samePracticeSaveIssueOwner(owner, {
    ...owner,
    sessionContext: { ...session, sessionId: 'session-2' },
  }), false);
  assert.equal(samePracticeSaveIssueOwner({ scoreKey: '', generation: 1, sessionContext: null }, {
    scoreKey: '', generation: 1, sessionContext: null,
  }), true);
});
