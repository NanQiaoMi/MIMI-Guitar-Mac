import type { StudioProject } from '../studio/studioScoreModel.ts';

export type PracticeStatus = 'todo' | 'practicing' | 'mastered' | 'archived';

export interface PersonalScore {
  id: string;
  source: 'catalog' | 'private' | 'project';
  sourceId: string;
  revision: string;
  title: string;
  artist: string;
  category: 'guitar' | 'ukulele' | 'bass';
  format: 'ibe' | 'gp' | 'xhe' | 'project';
  scoreUrl?: string;
  assetId?: string;
  originalAssetId?: string;
  projectId?: string;
  warnings?: string[];
  createdAt: number;
  updatedAt: number;
}

export interface PracticeItem {
  scoreId: string;
  status: PracticeStatus;
  note: string;
  order: number;
  updatedAt: number;
}

export interface PracticeFragmentSpeed {
  /** Native tempo at A, used to derive the AlphaTab playback multiplier. */
  nativeAnchorBpm: number;
  startBpm: number;
  targetBpm: number;
  stepBpm: number;
  lapsPerLevel: number;
}

/** A reusable, score-version-bound A/B range and speed-plan template. */
export interface PracticeFragment {
  id: string;
  scoreId: string;
  /** SHA-256 of the playable score bytes, never a catalog placeholder. */
  scoreRevision: string;
  name: string;
  note: string;
  /** Unfolded AlphaTab ticks; the interval is half-open [startTick, endTick). */
  range: { startTick: number; endTick: number };
  /** Runtime progress is intentionally kept on PracticeSession.speedPlan. */
  speed: PracticeFragmentSpeed;
  createdAt: number;
  updatedAt: number;
  /** Soft-delete tombstone retained so backup merge cannot resurrect the item. */
  deletedAt?: number;
}

export interface PlayerResume {
  scoreId: string;
  scoreRevision: string;
  tick: number;
  timeMs: number;
  /** Target tempo in BPM (20–300), not an AlphaTab playback multiplier. */
  speed: number;
  /** Native AlphaTab playback multiplier (0.125–8), when captured by newer players. */
  playbackRatio?: number;
  /** Per-track AlphaTab mix snapshot; omitted by older records. */
  trackMix?: Array<{
    index: number;
    muted: boolean;
    soloed: boolean;
    volume: number;
    program: number;
    /** Distinguishes an explicit GM choice from an equal-number source preset. */
    instrumentOverride?: boolean;
  }>;
  /** Score appearance snapshot; omitted by older records. */
  display?: {
    fontScale: number;
    chordMode: 'name' | 'diagram';
    scoreDisplayMode: 'mixed' | 'tab';
    numberTab: boolean;
    showFretboard: boolean;
  };
  capo: number;
  /** True keeps each staff's original capo; absent retains legacy absolute capo semantics. */
  useSourceCapo?: boolean;
  transpose: number;
  loop: { startTick: number; endTick: number } | null;
  trackIndexes: number[];
  metronome: boolean;
  countIn: boolean;
  updatedAt: number;
}

export interface PracticeSlice {
  id: string;
  sequence: number;
  epoch: string;
  startedAt: number;
  durationMs: number;
}

export interface SpeedPlan {
  revision: string;
  /** Native tempo at A; needed to restore a plan across tempo-map changes. */
  nativeAnchorBpm?: number;
  /** Unfolded playback interval this plan was created for. */
  loopRange?: { startTick: number; endTick: number };
  startBpm: number;
  targetBpm: number;
  stepBpm: number;
  lapsPerLevel: number;
  currentBpm: number;
  completedLaps: number;
}

export interface PracticeSession {
  id: string;
  scoreId: string;
  scoreRevision: string;
  state: 'active' | 'paused' | 'interrupted' | 'completed';
  startedAt: number;
  updatedAt: number;
  endedAt?: number;
  timezone: string;
  slices: PracticeSlice[];
  note: string;
  speedPlan?: SpeedPlan;
}

export interface OriginalReference {
  id: string;
  fileName: string;
  mimeType: string;
  assetId: string;
  savedAt: number;
}

export interface PersonalAsset {
  id: string;
  bytes: ArrayBuffer;
  mimeType: string;
}

interface PersonalDataFields {
  revision: number;
  scores: PersonalScore[];
  favorites: string[];
  practiceItems: PracticeItem[];
  resumes: PlayerResume[];
  sessions: PracticeSession[];
  projects: StudioProject[];
  originals: OriginalReference[];
  history: Array<{ id: string; title: string; artist?: string; url: string; time: number; category?: string }>;
  settings: Record<string, string | number | boolean>;
  migrationCompleted: boolean;
}

/** Current in-memory and IndexedDB representation. */
export interface PersonalData extends PersonalDataFields {
  schemaVersion: 2;
  practiceFragments: PracticeFragment[];
}

/** Raw schema-1 shape retained only at backup validation boundaries. */
export interface LegacyPersonalDataV1 extends PersonalDataFields {
  schemaVersion: 1;
}

export type PersonalDataSnapshot = PersonalData | LegacyPersonalDataV1;

export interface PersonalMutationOptions {
  expectedRevision?: number;
  assets?: PersonalAsset[];
}
