import test from 'node:test';
import assert from 'node:assert/strict';
import { createFretboardAuditionLifecycle } from '../src/lib/player/fretboardAuditionLifecycle.ts';

function session() {
  return { active: true, releases: 0, release() { this.releases += 1; } };
}

test('invalidating a visible fretboard audition releases its session and rejects late completion', () => {
  const lifecycle = createFretboardAuditionLifecycle();
  const token = lifecycle.begin();
  const active = session();
  assert.equal(lifecycle.attach(token, active, true), true);
  assert.equal(lifecycle.isCurrent(token, true), true);

  lifecycle.invalidate();
  assert.equal(active.releases, 1);
  assert.equal(lifecycle.isCurrent(token, true), false);

  const late = session();
  assert.equal(lifecycle.attach(token, late, true), false);
  assert.equal(late.releases, 1);
  lifecycle.finish(active);
  lifecycle.finish(late);
  assert.equal(active.releases, 1);
  assert.equal(late.releases, 1);
});

test('hidden state and disposal prevent an acquired session from attaching', () => {
  const lifecycle = createFretboardAuditionLifecycle();
  const hiddenToken = lifecycle.begin();
  const hidden = session();
  assert.equal(lifecycle.attach(hiddenToken, hidden, false), false);
  assert.equal(hidden.releases, 1);

  const attachedToken = lifecycle.begin();
  const attached = session();
  assert.equal(lifecycle.attach(attachedToken, attached, true), true);
  lifecycle.dispose();
  lifecycle.dispose();
  assert.equal(lifecycle.isCurrent(attachedToken, true), false);
  assert.equal(attached.releases, 1);

  const pending = session();
  assert.equal(lifecycle.attach(attachedToken, pending, true), false);
  assert.equal(pending.releases, 1);
});

test('beginning a new audition releases the previous session exactly once', () => {
  const lifecycle = createFretboardAuditionLifecycle();
  const firstToken = lifecycle.begin();
  const first = session();
  assert.equal(lifecycle.attach(firstToken, first, true), true);

  const secondToken = lifecycle.begin();
  assert.equal(first.releases, 1);
  assert.equal(lifecycle.isCurrent(firstToken, true), false);
  assert.equal(lifecycle.isCurrent(secondToken, true), true);

  const second = session();
  assert.equal(lifecycle.attach(secondToken, second, true), true);
  lifecycle.finish(second);
  assert.equal(second.releases, 1);
});
