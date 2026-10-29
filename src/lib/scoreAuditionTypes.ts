export interface AuditionState {
  currentTabId: string | null;
  currentTab: any | null;
  isPlaying: boolean;
  isLoading: boolean;
  currentTime: number;
  endTime: number;
  progress: number;
  activeNotes: Array<{ string: number; fret: number }>;
  error: string | null;
}

export type AuditionListener = (state: AuditionState) => void;

export type ScoreAuditionPreviewStartResult =
  | { status: 'started' }
  | { status: 'cancelled' }
  | { status: 'failed'; error: string };

/** A cancellable short preview; promise settles when loading/start is resolved. */
export interface ScoreAuditionPreviewHandle {
  promise: Promise<ScoreAuditionPreviewStartResult>;
  cancel(): void;
}

export interface ScoreAuditionRuntime {
  getState(): AuditionState;
  subscribe(listener: AuditionListener): () => void;
  togglePlayTab(tab: any): Promise<void>;
  playTab(tab: any): Promise<void>;
  pause(): void;
  resume(): Promise<void>;
  stop(): void;
  seek(ratio: number): void;
  seekBySeconds(delta: number): void;
  prewarm(): Promise<void>;
}
