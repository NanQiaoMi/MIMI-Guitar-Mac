/**
 * Audio Focus Manager
 * Coordinates audio playback across multiple tabs and components to ensure
 * only one audio source plays at a time.
 */

type FocusHolder = {
  id: string;
  release: () => void;
};

class AudioFocusManager {
  private currentHolder: FocusHolder | null = null;
  private channel: BroadcastChannel | null = null;

  constructor() {
    if (typeof BroadcastChannel !== 'undefined') {
      this.channel = new BroadcastChannel('mimi-audio-focus');
      this.channel.addEventListener('message', (event) => {
        if (event.data?.type === 'claim' && event.data.id !== this.currentHolder?.id) {
          this.releaseCurrentFocus();
        }
      });
    }
  }

  claim(id: string, onRelease: () => void): () => void {
    this.releaseCurrentFocus();

    this.currentHolder = {
      id,
      release: onRelease,
    };

    this.channel?.postMessage({ type: 'claim', id });

    return () => {
      if (this.currentHolder?.id === id) {
        this.currentHolder = null;
      }
    };
  }

  private releaseCurrentFocus() {
    if (this.currentHolder) {
      this.currentHolder.release();
      this.currentHolder = null;
    }
  }
}

export const audioFocusManager = new AudioFocusManager();
