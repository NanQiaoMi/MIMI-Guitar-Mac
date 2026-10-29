import { chromium } from 'playwright-core';

const DEFAULT_URL = 'http://154.88.65.55:20056/tabs/1sdc49P3eKm';
const TARGET_URL = process.env.MIMI_URL || DEFAULT_URL;
const LOAD_TIMEOUT_MS = Number(process.env.MIMI_LOAD_TIMEOUT_MS || 45_000);
const PLAY_TIMEOUT_MS = Number(process.env.MIMI_PLAY_TIMEOUT_MS || 20_000);
const SAMPLE_COUNT = Number(process.env.MIMI_SAMPLE_COUNT || 8);
const SAMPLE_INTERVAL_MS = Number(process.env.MIMI_SAMPLE_INTERVAL_MS || 500);

function redactText(value) {
  return String(value ?? '')
    .replace(/(https?:\/\/)[^\s/@:]+:[^\s/@]+@/gi, '$1***:***@')
    .replace(/([?&](?:token|key|password|secret)=)[^&\s]+/gi, '$1***');
}

function redactUrl(value) {
  try {
    const url = new URL(value);
    url.username = '';
    url.password = '';
    url.search = '';
    return url.toString();
  } catch {
    return redactText(value);
  }
}

function finiteNumber(value) {
  return Number.isFinite(value) ? value : null;
}

function calculateAdvance(samples) {
  const usable = samples.filter((sample) => Number.isFinite(sample.wallElapsedMs) && Number.isFinite(sample.apiTimePositionMs));
  if (usable.length < 2) {
    return { measurable: false, sampleCount: usable.length };
  }

  const first = usable[0];
  const last = usable.at(-1);
  const wallDeltaMs = last.wallElapsedMs - first.wallElapsedMs;
  const apiDeltaMs = last.apiTimePositionMs - first.apiTimePositionMs;
  const configuredPlaybackSpeed = finiteNumber(last.playbackSpeed) ?? finiteNumber(first.playbackSpeed);

  return {
    measurable: wallDeltaMs > 0,
    sampleCount: usable.length,
    wallDeltaMs,
    apiDeltaMs,
    apiToWallRatio: wallDeltaMs > 0 ? apiDeltaMs / wallDeltaMs : null,
    configuredPlaybackSpeed,
  };
}

async function launchBrowser() {
  const extraArgs = process.env.MIMI_HOST_RESOLVER_RULES
    ? [`--host-resolver-rules=${process.env.MIMI_HOST_RESOLVER_RULES}`]
    : [];
  const baseOptions = {
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', ...extraArgs],
  };
  const candidates = [];

  if (process.env.MIMI_BROWSER) {
    candidates.push({
      label: 'MIMI_BROWSER',
      options: { ...baseOptions, executablePath: process.env.MIMI_BROWSER },
    });
  }
  candidates.push({ label: 'chrome', options: { ...baseOptions, channel: 'chrome' } });
  candidates.push({ label: 'msedge', options: { ...baseOptions, channel: 'msedge' } });

  const failures = [];
  for (const candidate of candidates) {
    try {
      const browser = await chromium.launch(candidate.options);
      return { browser, launcher: candidate.label, failures };
    } catch (error) {
      failures.push({ launcher: candidate.label, message: redactText(error?.message || error) });
    }
  }

  const detail = failures.map((failure) => `${failure.launcher}: ${failure.message}`).join('; ');
  throw new Error(`Unable to launch a Chromium browser. ${detail}`);
}

async function waitFor(page, predicate, timeout) {
  try {
    await page.waitForFunction(predicate, { timeout });
    return true;
  } catch {
    return false;
  }
}

async function readSnapshot(page, label, startedAtMs, detailed = true) {
  return page.evaluate(({ label, startedAtMs, detailed }) => {
    const probe = window.__mimiPlayerLifecycleProbe;
    const api = window.__api;
    const read = (fn) => {
      try {
        const value = fn();
        return Number.isFinite(value) ? value : value ?? null;
      } catch (error) {
        return { readError: String(error?.message || error) };
      }
    };
    const getApiId = (value) => {
      if (!value || !probe) return null;
      let id = probe.apiIds.get(value);
      if (!id) {
        id = ++probe.nextApiId;
        probe.apiIds.set(value, id);
      }
      return id;
    };
    const output = read(() => api?._player?._instance?.output);
    const context = output && typeof output === 'object' ? read(() => output.context) : null;
    const contextId = context && typeof context === 'object' && probe ? probe.contextIds.get(context) ?? null : null;
    const contexts = probe?.contexts?.map((item) => ({ ...item })) ?? [];
    const scriptProcessors = probe?.scriptProcessors?.map((item) => ({ ...item })) ?? [];
    const workers = probe?.workers?.map((item) => ({ ...item })) ?? [];
    const importantWorkerCommands = new Set([
      'alphaSynth.initialize',
      'alphaSynth.loadMidi',
      'alphaSynth.loadSoundFontBytes',
      'alphaSynth.play',
      'alphaSynth.pause',
      'alphaSynth.stop',
      'alphaSynth.destroy',
    ]);
    const importantWorkerMessages = new Set([
      'alphaSynth.ready',
      'alphaSynth.readyForPlayback',
      'alphaSynth.midiLoaded',
      'alphaSynth.midiLoadFailed',
      'alphaSynth.soundFontLoaded',
      'alphaSynth.soundFontLoadFailed',
      'alphaSynth.playerStateChanged',
      'alphaSynth.output.play',
      'alphaSynth.output.pause',
      'alphaSynth.output.destroy',
    ]);
    const workerCommands = (probe?.workerCommands ?? [])
      .filter((item) => importantWorkerCommands.has(item.cmd))
      .slice(-100)
      .map((item) => ({ ...item }));
    const workerMessages = (probe?.workerMessages ?? [])
      .filter((item) => importantWorkerMessages.has(item.cmd))
      .slice(-160)
      .map((item) => ({ ...item }));

    return {
      label,
      wallEpochMs: Date.now(),
      wallElapsedMs: Date.now() - startedAtMs,
      pageNowMs: performance.now(),
      api: {
        present: !!api,
        id: getApiId(api),
        hasScore: !!read(() => api?.score),
        playerState: read(() => api?.playerState),
        actualPlayerMode: read(() => api?.actualPlayerMode),
        configuredPlayerMode: read(() => api?.settings?.player?.playerMode),
        readyForPlayback: read(() => api?.isReadyForPlayback),
        playbackSpeed: read(() => api?.playbackSpeed),
        tickPosition: read(() => api?.tickPosition),
        timePositionMs: read(() => api?.timePosition),
        endTick: read(() => api?.score?.endTick),
      },
      apiTimePositionMs: read(() => api?.timePosition),
      playbackSpeed: read(() => api?.playbackSpeed),
      output: {
        present: !!output && typeof output === 'object',
        constructorName: read(() => output?.constructor?.name),
        contextId,
        contextState: read(() => context?.state),
        contextSampleRate: read(() => context?.sampleRate),
      },
      audioInstrumentation: detailed ? {
        audioContextCreateCount: contexts.length,
        createScriptProcessorCount: scriptProcessors.length,
        contexts,
        scriptProcessors,
        workers,
        workerCommands,
        workerMessages,
        patchErrors: probe?.patchErrors?.slice() ?? [],
      } : {
        audioContextCreateCount: contexts.length,
        createScriptProcessorCount: scriptProcessors.length,
        workerCount: workers.length,
        patchErrorCount: probe?.patchErrors?.length ?? 0,
      },
    };
  }, { label, startedAtMs, detailed });
}

async function findVisibleRetry(page) {
  const retry = page.locator('button:has-text("重试"):not([disabled])').first();
  try {
    return (await retry.count()) > 0 && await retry.isVisible();
  } catch {
    return false;
  }
}

async function collectPlaybackSamples(page, startedAtMs) {
  const samples = [];
  for (let index = 0; index < SAMPLE_COUNT; index += 1) {
    if (index > 0) await page.waitForTimeout(SAMPLE_INTERVAL_MS);
    samples.push(await readSnapshot(page, `playback-${index}`, startedAtMs, false));
  }
  return samples;
}

const browserEvents = {
  console: [],
  pageErrors: [],
  requestFailures: [],
};

let browser;
try {
  const launch = await launchBrowser();
  browser = launch.browser;
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const page = await context.newPage();

  await page.addInitScript(() => {
    if (window.__mimiPlayerLifecycleProbe) return;

    const probe = {
      contexts: [],
      scriptProcessors: [],
      workers: [],
      workerCommands: [],
      workerMessages: [],
      patchErrors: [],
      contextIds: new WeakMap(),
      apiIds: new WeakMap(),
      nextContextId: 0,
      nextApiId: 0,
      nextWorkerId: 0,
    };
    Object.defineProperty(window, '__mimiPlayerLifecycleProbe', {
      configurable: true,
      value: probe,
    });

    const recordContext = (context, source) => {
      if (!context || probe.contextIds.has(context)) return probe.contextIds.get(context);
      const id = ++probe.nextContextId;
      probe.contextIds.set(context, id);
      const entry = {
        id,
        source,
        createdAtMs: performance.now(),
        sampleRate: Number(context.sampleRate) || null,
        state: context.state || null,
        states: [{ atMs: performance.now(), state: context.state || null }],
      };
      probe.contexts.push(entry);
      try {
        context.addEventListener('statechange', () => {
          entry.state = context.state || null;
          entry.states.push({ atMs: performance.now(), state: context.state || null });
        });
      } catch (error) {
        probe.patchErrors.push(`AudioContext state listener: ${String(error?.message || error)}`);
      }
      return id;
    };

    const patchedPrototypes = new WeakSet();
    const patchPrototype = (prototype, source) => {
      if (!prototype || patchedPrototypes.has(prototype)) return;
      patchedPrototypes.add(prototype);
      const original = prototype.createScriptProcessor;
      if (typeof original !== 'function') return;
      try {
        Object.defineProperty(prototype, 'createScriptProcessor', {
          configurable: true,
          writable: true,
          value: function patchedCreateScriptProcessor(...args) {
            const contextId = recordContext(this, `${source}.createScriptProcessor`);
            probe.scriptProcessors.push({
              contextId,
              createdAtMs: performance.now(),
              bufferSize: Number(args[0]) || null,
              inputChannels: Number(args[1]) || null,
              outputChannels: Number(args[2]) || null,
            });
            return original.apply(this, args);
          },
        });
      } catch (error) {
        probe.patchErrors.push(`createScriptProcessor patch: ${String(error?.message || error)}`);
      }
    };

    const patchConstructor = (name) => {
      const NativeAudioContext = window[name];
      if (typeof NativeAudioContext !== 'function' || NativeAudioContext.__mimiLifecycleWrapped) return;
      patchPrototype(NativeAudioContext.prototype, name);
      try {
        function WrappedAudioContext(...args) {
          const target = new.target === WrappedAudioContext ? NativeAudioContext : new.target;
          const instance = Reflect.construct(NativeAudioContext, args, target);
          recordContext(instance, name);
          return instance;
        }
        WrappedAudioContext.prototype = NativeAudioContext.prototype;
        Object.setPrototypeOf(WrappedAudioContext, NativeAudioContext);
        Object.defineProperty(WrappedAudioContext, '__mimiLifecycleWrapped', { value: true });
        Object.defineProperty(window, name, {
          configurable: true,
          writable: true,
          value: WrappedAudioContext,
        });
      } catch (error) {
        probe.patchErrors.push(`${name} constructor patch: ${String(error?.message || error)}`);
      }
    };

    patchConstructor('AudioContext');
    patchConstructor('webkitAudioContext');

    const summarizeWorkerMessage = (message) => {
      if (!message || typeof message !== 'object') {
        return { type: typeof message, cmd: null };
      }
      return {
        type: 'object',
        cmd: typeof message.cmd === 'string' ? message.cmd : null,
        state: Number.isFinite(message.state) ? message.state : null,
        value: Number.isFinite(message.value) ? message.value : null,
        sampleRate: Number.isFinite(message.sampleRate) ? message.sampleRate : null,
        bufferTimeInMilliseconds: Number.isFinite(message.bufferTimeInMilliseconds)
          ? message.bufferTimeInMilliseconds
          : null,
      };
    };

    const NativeWorker = window.Worker;
    if (typeof NativeWorker === 'function' && !NativeWorker.__mimiLifecycleWrapped) {
      try {
        function WrappedWorker(...args) {
          const worker = new NativeWorker(...args);
          const workerId = ++probe.nextWorkerId;
          const entry = {
            id: workerId,
            url: String(args[0] ?? ''),
            createdAtMs: performance.now(),
            terminatedAtMs: null,
          };
          probe.workers.push(entry);

          const originalPostMessage = worker.postMessage;
          worker.postMessage = function patchedPostMessage(message, ...rest) {
            probe.workerCommands.push({
              workerId,
              atMs: performance.now(),
              direction: 'to-worker',
              ...summarizeWorkerMessage(message),
            });
            return originalPostMessage.call(this, message, ...rest);
          };

          worker.addEventListener('message', (event) => {
            probe.workerMessages.push({
              workerId,
              atMs: performance.now(),
              direction: 'from-worker',
              ...summarizeWorkerMessage(event.data),
            });
          });

          const originalTerminate = worker.terminate;
          worker.terminate = function patchedTerminate(...terminateArgs) {
            entry.terminatedAtMs = performance.now();
            return originalTerminate.apply(this, terminateArgs);
          };
          return worker;
        }
        WrappedWorker.prototype = NativeWorker.prototype;
        Object.setPrototypeOf(WrappedWorker, NativeWorker);
        Object.defineProperty(WrappedWorker, '__mimiLifecycleWrapped', { value: true });
        Object.defineProperty(window, 'Worker', {
          configurable: true,
          writable: true,
          value: WrappedWorker,
        });
      } catch (error) {
        probe.patchErrors.push(`Worker patch: ${String(error?.message || error)}`);
      }
    }
  });

  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') {
      browserEvents.console.push({ type: message.type(), text: redactText(message.text()) });
    }
  });
  page.on('pageerror', (error) => {
    browserEvents.pageErrors.push(redactText(error?.message || error));
  });
  page.on('requestfailed', (request) => {
    browserEvents.requestFailures.push({
      url: redactUrl(request.url()),
      error: redactText(request.failure()?.errorText || 'unknown'),
    });
  });

  const startedAtMs = Date.now();
  await page.goto(TARGET_URL, { waitUntil: 'domcontentloaded', timeout: LOAD_TIMEOUT_MS });

  const initialScoreLoaded = await waitFor(page, () => Boolean(window.__api?.score), LOAD_TIMEOUT_MS);
  const initial = await readSnapshot(page, 'initial', startedAtMs);

  const retry = {
    available: await findVisibleRetry(page),
    clicked: false,
    scoreLoadedAfterRetry: null,
    before: null,
    after: null,
    audioContextDelta: null,
    createScriptProcessorDelta: null,
  };

  if (retry.available) {
    retry.before = await readSnapshot(page, 'retry-before', startedAtMs);
    await page.locator('button:has-text("重试"):not([disabled])').first().click();
    retry.clicked = true;
    retry.scoreLoadedAfterRetry = await waitFor(page, () => Boolean(window.__api?.score), LOAD_TIMEOUT_MS);
    retry.after = await readSnapshot(page, 'retry-after', startedAtMs);
    retry.audioContextDelta = retry.after.audioInstrumentation.audioContextCreateCount - retry.before.audioInstrumentation.audioContextCreateCount;
    retry.createScriptProcessorDelta = retry.after.audioInstrumentation.createScriptProcessorCount - retry.before.audioInstrumentation.createScriptProcessorCount;
  }

  const scoreLoaded = retry.clicked ? retry.scoreLoadedAfterRetry : initialScoreLoaded;
  const readyForPlayback = scoreLoaded
    ? await waitFor(page, () => Boolean(window.__api?._player?.isReadyForPlayback), PLAY_TIMEOUT_MS)
    : false;
  const beforePlay = await readSnapshot(page, 'before-play', startedAtMs);

  const playback = {
    attempted: false,
    clicked: false,
    started: false,
    samples: [],
    advance: null,
  };

  if (scoreLoaded) {
    const playButton = page.locator('button[aria-label="播放"]:not([disabled])').first();
    const hasPlayButton = (await playButton.count()) > 0 && await playButton.isVisible().catch(() => false);
    playback.attempted = hasPlayButton;
    if (hasPlayButton) {
      await playButton.click();
      playback.clicked = true;
      playback.started = await waitFor(page, () => window.__api?.playerState === 1, PLAY_TIMEOUT_MS);
      if (playback.started) {
        playback.samples = await collectPlaybackSamples(page, startedAtMs);
        playback.advance = calculateAdvance(playback.samples);
      }
    }
  }

  const afterPlay = await readSnapshot(page, 'after-play', startedAtMs);
  const scriptProcessorCount = afterPlay.audioInstrumentation.createScriptProcessorCount;
  const timeCodeRatio = playback.advance?.apiToWallRatio;
  const checks = {
    initialScoreLoaded,
    scoreLoaded,
    readyForPlayback,
    playButtonClicked: playback.clicked,
    playbackStarted: playback.started,
    apiTimeAdvanced: Boolean(playback.advance?.measurable && playback.advance.apiDeltaMs > 0),
    exactlyOneScriptProcessor: scriptProcessorCount === 1,
    timeCodeMatchesWallClock: Number.isFinite(timeCodeRatio) && Math.abs(timeCodeRatio - 1) <= 0.2,
  };

  const result = {
    ok: checks.scoreLoaded
      && checks.playButtonClicked
      && checks.playbackStarted
      && checks.apiTimeAdvanced
      && checks.exactlyOneScriptProcessor
      && checks.timeCodeMatchesWallClock,
    script: 'tools/verify-player-lifecycle.mjs',
    targetUrl: redactUrl(TARGET_URL),
    startedAt: new Date(startedAtMs).toISOString(),
    launcher: launch.launcher,
    launchFailures: launch.failures,
    configuration: {
      loadTimeoutMs: LOAD_TIMEOUT_MS,
      playTimeoutMs: PLAY_TIMEOUT_MS,
      sampleCount: SAMPLE_COUNT,
      sampleIntervalMs: SAMPLE_INTERVAL_MS,
    },
    checks,
    initial,
    retry,
    beforePlay,
    playback,
    afterPlay,
    browserEvents,
  };

  console.log(JSON.stringify(result, null, 2));
  await context.close();
  if (!result.ok) process.exitCode = 1;
} catch (error) {
  console.log(JSON.stringify({
    ok: false,
    script: 'tools/verify-player-lifecycle.mjs',
    targetUrl: redactUrl(TARGET_URL),
    error: redactText(error?.stack || error?.message || error),
    browserEvents,
  }, null, 2));
  process.exitCode = 1;
} finally {
  await browser?.close().catch(() => {});
}
