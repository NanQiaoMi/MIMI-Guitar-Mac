import type { PersonalData, PracticeSession } from '../personal/types.ts';

export interface PracticeDaySummary { date: string; durationMs: number }
export interface RecentPracticeSummary {
  id: string;
  scoreId: string;
  scoreStatus: 'active' | 'archived' | 'not-in-queue' | 'missing';
  title: string;
  artist: string;
  state: string;
  note: string;
  durationMs: number;
  updatedAt: number;
}
export interface PracticeSummary {
  today: PracticeDaySummary;
  last7Days: PracticeDaySummary[];
  recent: RecentPracticeSummary[];
  timeZone: string;
  warnings: string[];
}
export interface PracticeSummaryDiagnostics {
  formatterCount: number;
  dateKeyCalls: number;
  boundarySearches: number;
  boundaryCacheHits: number;
}

function dateKey(timestamp: number, formatter: Intl.DateTimeFormat, diagnostics: PracticeSummaryDiagnostics): string {
  diagnostics.dateKeyCalls++;
  const parts = formatter.formatToParts(timestamp);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function addCalendarDays(key: string, amount: number): string {
  const [year, month, day] = key.split('-').map(Number);
  const next = new Date(Date.UTC(year, month - 1, day + amount));
  return `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, '0')}-${String(next.getUTCDate()).padStart(2, '0')}`;
}

/** Find the first instant whose local date is after key, including 23/25-hour DST days. */
function nextLocalDayStart(timestamp: number, key: string, formatter: Intl.DateTimeFormat, boundaries: Map<string, number>, diagnostics: PracticeSummaryDiagnostics): number {
  const cached = boundaries.get(key);
  if (cached !== undefined) {
    diagnostics.boundaryCacheHits++;
    return cached;
  }
  diagnostics.boundarySearches++;
  let low = timestamp;
  let high = timestamp + 24 * 60 * 60 * 1000;
  while (dateKey(high, formatter, diagnostics) <= key) {
    low = high;
    high = timestamp + (high - timestamp) * 2;
  }
  while (high - low > 1) {
    const mid = low + Math.floor((high - low) / 2);
    if (dateKey(mid, formatter, diagnostics) > key) high = mid;
    else low = mid;
  }
  boundaries.set(key, high);
  return high;
}

function sessionSliceDurations(session: PracticeSession, warnings: string[]): Map<string, { durationMs: number; startedAt: number }> {
  const unique = new Map<string, { durationMs: number; startedAt: number }>();
  for (const slice of session.slices ?? []) {
    const id = typeof slice?.id === 'string' ? slice.id : '';
    const duration = Number(slice?.durationMs);
    const start = Number(slice?.startedAt);
    if (!id || !Number.isFinite(duration) || duration <= 0 || !Number.isFinite(start) || start < 0) {
      warnings.push(`练习记录 ${session.id || '(无编号)'} 中有无效时段，未计入汇总`);
      continue;
    }
    if (unique.has(id)) continue;
    unique.set(id, { durationMs: duration, startedAt: start });
  }
  return unique;
}

function stateLabel(state: unknown): string {
  const labels: Record<string, string> = { active: '进行中', paused: '已暂停', interrupted: '已中断', completed: '已完成' };
  return typeof state === 'string' ? labels[state] ?? '未知状态' : '未知状态';
}

function formatDurationMs(slices: Map<string, { durationMs: number; startedAt: number }>): number {
  return [...slices.values()].reduce((total, slice) => total + slice.durationMs, 0);
}

export function summarizePractice(
  data: Pick<PersonalData, 'sessions' | 'scores'> & Partial<Pick<PersonalData, 'practiceItems'>>,
  options: { now?: number; timeZone?: string; recentLimit?: number; onDiagnostics?: (diagnostics: Readonly<PracticeSummaryDiagnostics>) => void } = {},
): PracticeSummary {
  const now = options.now ?? Date.now();
  const timeZone = options.timeZone ?? Intl.DateTimeFormat().resolvedOptions().timeZone ?? 'UTC';
  const formatter = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
  const diagnostics: PracticeSummaryDiagnostics = { formatterCount: 1, dateKeyCalls: 0, boundarySearches: 0, boundaryCacheHits: 0 };
  const boundaries = new Map<string, number>();
  const todayKey = dateKey(now, formatter, diagnostics);
  const startKey = addCalendarDays(todayKey, -6);
  const daily = new Map<string, number>();
  for (let i = 0; i < 7; i++) daily.set(addCalendarDays(startKey, i), 0);
  const warnings: string[] = [];
  const uniqueAcrossSessions = new Set<string>();

  const sessions = Array.isArray(data.sessions) ? data.sessions : [];
  for (const session of sessions) {
    if (!session || typeof session.id !== 'string') {
      warnings.push('存在无法识别的练习记录，未计入汇总');
      continue;
    }
    for (const [sliceId, slice] of sessionSliceDurations(session, warnings)) {
      const uniqueKey = `${session.id}\0${sliceId}`;
      if (uniqueAcrossSessions.has(uniqueKey)) continue;
      uniqueAcrossSessions.add(uniqueKey);
      let cursor = slice.startedAt;
      const end = cursor + slice.durationMs;
      const firstDay = dateKey(cursor, formatter, diagnostics);
      const lastDay = dateKey(end - 1, formatter, diagnostics);
      if (lastDay < startKey || firstDay > todayKey) continue;
      if (firstDay === lastDay) {
        if (daily.has(firstDay)) daily.set(firstDay, daily.get(firstDay)! + slice.durationMs);
        continue;
      }
      if (firstDay < startKey) cursor = nextLocalDayStart(cursor, addCalendarDays(startKey, -1), formatter, boundaries, diagnostics);
      let remaining = Math.max(0, end - cursor);
      while (remaining > 0) {
        const key = dateKey(cursor, formatter, diagnostics);
        if (key > todayKey) break;
        const boundary = nextLocalDayStart(cursor, key, formatter, boundaries, diagnostics);
        const segment = Math.min(remaining, boundary - cursor);
        if (daily.has(key)) daily.set(key, daily.get(key)! + segment);
        cursor += segment;
        remaining -= segment;
      }
    }
  }

  const scores = new Map((Array.isArray(data.scores) ? data.scores : []).map((score) => [score.id, score]));
  const practiceItems = new Map((Array.isArray(data.practiceItems) ? data.practiceItems : []).map((item) => [item.scoreId, item]));
  const recent = sessions.filter((session): session is PracticeSession => Boolean(session && typeof session.id === 'string'))
    .map((session) => {
      const scoreId = typeof session.scoreId === 'string' ? session.scoreId : '';
      const score = scores.get(scoreId);
      const practiceItem = practiceItems.get(scoreId);
      if (!score) warnings.push(`练习记录 ${session.id} 所关联的曲谱缺失`);
      const slices = sessionSliceDurations(session, warnings);
      return {
        id: session.id,
        scoreId,
        scoreStatus: !score ? 'missing' as const
          : practiceItem?.status === 'archived' ? 'archived' as const
            : practiceItem ? 'active' as const : 'not-in-queue' as const,
        title: score?.title || '曲谱已不可用',
        artist: score?.artist || '',
        state: stateLabel((session as PracticeSession).state),
        note: typeof session.note === 'string' ? session.note : '',
        durationMs: formatDurationMs(slices),
        updatedAt: Number.isFinite(session.updatedAt) ? session.updatedAt : 0,
      };
    })
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, Math.max(0, options.recentLimit ?? 12));

  const last7Days = [...daily].map(([date, durationMs]) => ({ date, durationMs }));
  options.onDiagnostics?.(diagnostics);
  return { today: daily.get(todayKey) === undefined ? { date: todayKey, durationMs: 0 } : { date: todayKey, durationMs: daily.get(todayKey)! }, last7Days, recent, timeZone, warnings: [...new Set(warnings)] };
}
