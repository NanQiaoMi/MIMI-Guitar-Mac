import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAudioContextRegistry } from '../src/lib/audioUnlocker.ts';

function fakeContext(resume) {
  return { state: 'suspended', resumeCalls: 0, resume() { this.resumeCalls++; return resume(); } };
}

test('register after unlock resumes once without recursive registration', () => {
  const registry = createAudioContextRegistry();
  registry.unlockAll();
  const ctx = fakeContext(() => Promise.resolve());
  const disposeA = registry.register(ctx);
  const disposeB = registry.register(ctx);
  assert.equal(registry.size, 1);
  assert.equal(ctx.resumeCalls, 1);
  disposeA();
  assert.equal(registry.size, 0);
  disposeB();
  assert.equal(registry.size, 0);
});

test('synchronous throw and asynchronous resume rejection are contained', async () => {
  const registry = createAudioContextRegistry();
  const syncThrow = fakeContext(() => { throw new Error('blocked synchronously'); });
  assert.doesNotThrow(() => registry.unlock(syncThrow));

  const rejected = fakeContext(() => Promise.reject(new Error('blocked asynchronously')));
  assert.doesNotThrow(() => registry.unlock(rejected));
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(syncThrow.resumeCalls, 1);
  assert.equal(rejected.resumeCalls, 1);
});
