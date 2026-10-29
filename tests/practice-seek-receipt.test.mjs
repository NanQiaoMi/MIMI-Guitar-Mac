import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seekWithReceipt } from '../src/lib/practice/seekReceipt.ts';

function setup() {
  let listener;
  let disposed = 0;
  let sought = false;
  const controller = new AbortController();
  const options = { tick: 4800, isCurrent: () => true, signal: controller.signal,
    subscribe: fn => { listener = fn; return () => { disposed++; }; }, seek: () => { sought = true; } };
  return { options, controller, emit: value => listener(value), get disposed() { return disposed; }, get sought() { return sought; } };
}

test('seek receipt subscribes first and ignores stale time, wrong tick and ordinary playback events', async () => {
  const h = setup(); const result = seekWithReceipt(h.options);
  assert.equal(h.sought, true);
  h.emit({ isSeek: false, currentTick: 4800, currentTime: 12000 });
  h.emit({ isSeek: true, currentTick: 9000, currentTime: 12000 });
  h.emit({ isSeek: true, currentTick: 4800, currentTime: NaN });
  h.emit({ isSeek: true, currentTick: 4801, currentTime: 2500 });
  assert.deepEqual(await result, { tick: 4800, timeMs: 2500 });
  assert.equal(h.disposed, 1);
});

test('a synchronous engine seek event is captured with listeners removed exactly once', async () => {
  const h = setup(); h.options.seek = () => h.emit({ isSeek: true, currentTick: 4800, currentTime: 2500 });
  assert.equal((await seekWithReceipt(h.options)).timeMs, 2500);
  assert.equal(h.disposed, 1);
});

test('score disposal cancels an outstanding seek without producing a saved position', async () => {
  const h = setup(); const result = seekWithReceipt(h.options); h.controller.abort();
  await assert.rejects(result, /已取消/); assert.equal(h.disposed, 1);
});

test('an unconfirmed seek times out and cleans up its listener', async () => {
  const h = setup(); h.options.timeoutMs = 10;
  await assert.rejects(seekWithReceipt(h.options), /引擎确认/); assert.equal(h.disposed, 1);
});

test('invalid context never asks the engine to seek', async () => {
  const h = setup(); h.options.isCurrent = () => false;
  await assert.rejects(seekWithReceipt(h.options), /已取消/); assert.equal(h.sought, false); assert.equal(h.disposed, 0);
});
