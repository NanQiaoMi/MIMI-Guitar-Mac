import test from 'node:test';
import assert from 'node:assert/strict';
import { createVectorManuscriptLifecycle } from '../src/lib/player/vectorManuscriptLifecycle.mjs';

test('retry releases the previous renderer, request and callbacks before replacing it', () => {
  const lifecycle = createVectorManuscriptLifecycle();
  const first = lifecycle.begin();
  let destroyed = 0;
  let cleared = 0;
  first.attach({ destroy() { destroyed++; } });
  first.track(() => cleared++);
  const next = lifecycle.begin();
  assert.equal(first.signal.aborted, true);
  assert.equal(first.isCurrent(), false);
  assert.equal(lifecycle.isCurrent(first.generation), false);
  assert.equal(next.isCurrent(), true);
  assert.equal(destroyed, 1);
  assert.equal(cleared, 1);
  first.dispose();
  assert.equal(next.isCurrent(), true);
  assert.equal(destroyed, 1);
  lifecycle.dispose();
  assert.equal(next.signal.aborted, true);
});

test('failure or timeout disposal prevents late renderer attachment and survives throwing cleanup', () => {
  const lifecycle = createVectorManuscriptLifecycle();
  const attempt = lifecycle.begin();
  let released = 0;
  attempt.track(() => { throw new Error('old cleanup'); });
  attempt.track(() => released++);
  attempt.attach({ destroy() { released++; throw new Error('already failed'); } });
  attempt.dispose();
  attempt.attach({ destroy() { released++; } });
  assert.equal(attempt.isCurrent(), false);
  assert.equal(released, 3);
  lifecycle.dispose();
  assert.equal(released, 3);
});
