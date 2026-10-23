import assert from 'node:assert/strict';
import test from 'node:test';
import { createEmptyPersonalData, validatePersonalData } from '../src/lib/personal/validation.ts';

function fixture(speedPlan) {
  const data = createEmptyPersonalData();
  data.scores.push({
    id: 'catalog:fixture', source: 'catalog', sourceId: 'fixture', revision: 'rev-1',
    title: 'Fixture', artist: 'Test', category: 'guitar', format: 'gp',
    scoreUrl: '/fixture.gp', createdAt: 1, updatedAt: 1,
  });
  data.sessions.push({
    id: 'session:fixture', scoreId: 'catalog:fixture', scoreRevision: 'rev-1',
    state: 'paused', startedAt: 1, updatedAt: 1, timezone: 'UTC', slices: [], note: '', speedPlan,
  });
  return data;
}

const basePlan = {
  revision: 'rev-1', startBpm: 60, targetBpm: 90, stepBpm: 5,
  lapsPerLevel: 2, currentBpm: 60, completedLaps: 0,
};

test('speed plan validator accepts legacy plans and valid optional tempo/range anchors', () => {
  assert.doesNotThrow(() => validatePersonalData(fixture(basePlan)));
  assert.doesNotThrow(() => validatePersonalData(fixture({
    ...basePlan, nativeAnchorBpm: 400, loopRange: { startTick: 0, endTick: 960 },
  })));
});

test('speed plan validator rejects invalid optional anchor and unfolded range', () => {
  assert.throws(() => validatePersonalData(fixture({ ...basePlan, nativeAnchorBpm: 1001 })), /nativeAnchorBpm/);
  assert.throws(() => validatePersonalData(fixture({ ...basePlan, nativeAnchorBpm: 0 })), /nativeAnchorBpm/);
  assert.throws(() => validatePersonalData(fixture({ ...basePlan, loopRange: { startTick: 10, endTick: 10 } })), /loopRange/);
  assert.throws(() => validatePersonalData(fixture({ ...basePlan, loopRange: { startTick: -1, endTick: 20 } })), /loopRange/);
});
