import type { StudioProject } from './studioScoreModel';

function cloneProject(project: StudioProject): StudioProject {
  return JSON.parse(JSON.stringify(project)) as StudioProject;
}

export interface StudioLyricsCommand {
  kind: 'align' | 'clear';
  projectId: string;
  trackId: string;
  expectedRevision: number;
  text?: string;
}

export interface StudioLyricsSummary {
  wordCount: number;
  availablePositions: number;
  existingLyrics: number;
}

/** Keep the studio's existing Chinese-character and English-word tokenization contract. */
export function tokenizeStudioLyrics(text: string): string[] {
  const tokens: string[] = [];
  const regex = /[\u4e00-\u9fa5]|([a-zA-Z0-9'’]+)/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text.trim())) !== null) tokens.push(match[0]);
  return tokens;
}

function beatsForTrack(project: StudioProject, trackId: string) {
  return project.bars.flatMap((bar) => bar.trackBeats[trackId] ?? []);
}

export function collectStudioLyrics(project: StudioProject, trackId: string): string {
  return beatsForTrack(project, trackId)
    .flatMap((beat) => (beat.lyrics ? [beat.lyrics] : []))
    .join(' ');
}

export function summarizeStudioLyrics(
  project: StudioProject,
  trackId: string,
  text: string,
): StudioLyricsSummary {
  const beats = beatsForTrack(project, trackId);
  return {
    wordCount: tokenizeStudioLyrics(text).length,
    availablePositions: beats.filter((beat) => !beat.isRest && beat.notes.length > 0).length,
    existingLyrics: beats.filter((beat) => typeof beat.lyrics === 'string' && beat.lyrics.length > 0).length,
  };
}

/** Apply one version-checked lyric command without mutating the current project. */
export function applyStudioLyricsCommand(
  project: StudioProject,
  currentRevision: number,
  command: StudioLyricsCommand,
): StudioProject {
  if (project.id !== command.projectId) {
    throw new Error('当前工程已变化。请保留草稿并重新载入目标工程的歌词。');
  }
  if (currentRevision !== command.expectedRevision) {
    throw new Error('工程内容已变化。请保留草稿并重新载入当前歌词后再操作。');
  }
  if (!project.tracks.some((track) => track.id === command.trackId)) {
    throw new Error('目标音轨已不存在。请保留草稿并重新选择音轨。');
  }

  if (command.kind === 'clear') {
    const next = cloneProject(project);
    for (const beat of beatsForTrack(next, command.trackId)) beat.lyrics = null;
    return next;
  }

  const tokens = tokenizeStudioLyrics(command.text ?? '');
  if (tokens.length === 0) throw new Error('请输入至少一个有效歌词字词。');

  const targetBeats = beatsForTrack(project, command.trackId);
  const positions = targetBeats.filter((beat) => !beat.isRest && beat.notes.length > 0);
  if (positions.length === 0) throw new Error('当前音轨没有可对齐的发声音符。');
  if (tokens.length > positions.length) {
    throw new Error(`歌词有 ${tokens.length} 个字词，但当前音轨只有 ${positions.length} 个可用拍位；请缩短歌词或增加音符。`);
  }

  // An explicit alignment replaces this track's previous lyric pass, including
  // any old trailing words after the new text has become shorter.
  const next = cloneProject(project);
  const nextBeats = beatsForTrack(next, command.trackId);
  const nextPositions = nextBeats.filter((beat) => !beat.isRest && beat.notes.length > 0);
  for (const beat of nextBeats) beat.lyrics = null;
  nextPositions.slice(0, tokens.length).forEach((beat, index) => {
    beat.lyrics = tokens[index];
  });
  return next;
}
