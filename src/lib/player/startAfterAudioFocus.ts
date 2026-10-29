/** Start playback only if its user intent is still current after audio focus resolves. */
export async function startAfterAudioFocus(options: {
  claim: () => Promise<() => void>;
  isCurrent: () => boolean;
  start: () => boolean | void;
  onStarted: (release: () => void) => void;
}): Promise<boolean> {
  const release = await options.claim();
  if (!options.isCurrent()) {
    release();
    return false;
  }

  let started: boolean | void;
  try {
    started = options.start();
  } catch (error) {
    release();
    throw error;
  }
  if (started === false) {
    release();
    return false;
  }

  options.onStarted(release);
  return true;
}
