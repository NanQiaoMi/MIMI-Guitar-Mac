import assert from 'node:assert/strict';
import test from 'node:test';
import { createFolioFlipController } from '../src/lib/ui/folioMotion.ts';

function createClock() {
  let nextId = 0;
  const jobs = new Map();
  return {
    jobs,
    schedule(callback, delayMs) {
      const id = ++nextId;
      jobs.set(id, { callback, delayMs, cancelled: false });
      return id;
    },
    cancel(id) {
      const job = jobs.get(id);
      if (job) job.cancelled = true;
    },
    fire(id) {
      const job = jobs.get(id);
      assert.ok(job, `expected timer ${id}`);
      job.callback();
    },
  };
}

function makeController(clock, onActiveChange = () => {}) {
  return createFolioFlipController({
    duration: 360,
    fallbackPadding: 100,
    schedule: clock.schedule,
    cancel: clock.cancel,
    onActiveChange,
  });
}

test('animation events unlock only the active card animation and cancel its fallback', () => {
  const clock = createClock();
  const states = [];
  const controller = makeController(clock, (active) => states.push(active));
  const card = {};
  const generation = controller.start('flip-page-next');
  const timerId = [...clock.jobs.keys()][0];

  assert.equal(generation, 1);
  assert.equal(clock.jobs.get(timerId).delayMs, 460);
  assert.equal(controller.isActive(), true);
  assert.equal(controller.handleAnimationEvent({
    type: 'animationend', target: {}, currentTarget: card, animationName: 'flip-page-next',
  }, () => false), false, 'bubbled child animations are ignored');
  assert.equal(controller.handleAnimationEvent({
    type: 'animationend', target: card, currentTarget: card, animationName: 'spine-fade',
  }, () => false), false, 'unrelated animation names are ignored');
  assert.equal(controller.handleAnimationEvent({
    type: 'animationend', target: card, currentTarget: card, animationName: 'flip-page-next',
  }, () => true), false, 'a same-name newer animation remains locked');
  assert.equal(controller.isActive(), true);

  assert.equal(controller.handleAnimationEvent({
    type: 'animationend', target: card, currentTarget: card, animationName: 'flip-page-next',
  }, () => false), true);
  assert.equal(controller.isActive(), false);
  assert.equal(clock.jobs.get(timerId).cancelled, true);
  assert.deepEqual(states, [true, false]);
  controller.destroy();
});

test('generation guards stale timers and same-name cancelled events during a newer turn', () => {
  const clock = createClock();
  const controller = makeController(clock);
  const card = {};
  const oldGeneration = controller.start('flip-page-next');
  const oldTimer = [...clock.jobs.keys()][0];

  const currentGeneration = controller.start('flip-page-next');
  const currentTimer = [...clock.jobs.keys()][1];
  assert.ok(currentGeneration > oldGeneration);
  assert.equal(clock.jobs.get(oldTimer).cancelled, true);

  // Model a late event from an old turn while the new same-direction animation is live.
  assert.equal(controller.handleAnimationEvent({
    type: 'animationcancel', target: card, currentTarget: card, animationName: 'flip-page-next',
  }, () => true), false);
  assert.equal(controller.isActive(), true);

  // A cleared timeout may still be queued by the host; its generation cannot unlock the new turn.
  clock.fire(oldTimer);
  assert.equal(controller.isActive(), true);
  assert.equal(controller.getGeneration(), currentGeneration);

  clock.fire(currentTimer);
  assert.equal(controller.isActive(), false, 'the bounded fallback settles when no animation event arrives');
  controller.destroy();
});

test('immediate settle supports reduced motion and hidden pages; destroy clears timers', () => {
  const clock = createClock();
  const states = [];
  const controller = makeController(clock, (active) => states.push(active));

  controller.start('flip-page-prev');
  const firstTimer = [...clock.jobs.keys()][0];
  assert.equal(controller.settle(), true);
  assert.equal(clock.jobs.get(firstTimer).cancelled, true);
  assert.equal(controller.isActive(), false);

  controller.start('flip-page-next');
  const secondTimer = [...clock.jobs.keys()][1];
  controller.destroy();
  assert.equal(clock.jobs.get(secondTimer).cancelled, true);
  assert.equal(controller.isActive(), false);
  assert.deepEqual(states, [true, false, true, false]);

  const stateCount = states.length;
  clock.fire(secondTimer);
  assert.equal(states.length, stateCount, 'callbacks after unmount cannot update component state');
});