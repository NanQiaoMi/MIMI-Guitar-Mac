/** Queue entries are ordered independently inside the active and archived groups. */
export interface PracticeQueueEntry {
  scoreId: string;
  status: string;
  order: number;
}

function sortableOrder(order: number): number {
  return Number.isFinite(order) ? order : Number.POSITIVE_INFINITY;
}

/**
 * Return a stable, contiguous queue: active items first, archived items after them.
 * The input is never mutated, so callers can assign the returned array atomically.
 */
export function normalizePracticeQueue<T extends PracticeQueueEntry>(items: readonly T[]): T[] {
  return items
    .map((item, index) => ({ item, index }))
    .sort((a, b) => {
      const aArchived = a.item.status === 'archived';
      const bArchived = b.item.status === 'archived';
      if (aArchived !== bArchived) return aArchived ? 1 : -1;
      const byOrder = sortableOrder(a.item.order) - sortableOrder(b.item.order);
      return byOrder || a.index - b.index;
    })
    .map(({ item }, order) => ({ ...item, order }));
}

/** Append to the active queue and return the complete normalized queue. */
export function appendPracticeQueueItem<T extends PracticeQueueEntry>(items: readonly T[], item: T): T[] {
  const normalized = normalizePracticeQueue(items);
  const activeCount = normalized.filter((entry) => entry.status !== 'archived').length;
  const appended = { ...item, order: activeCount };
  return normalizePracticeQueue([...normalized, appended]);
}

/** Move an item between active and archived groups; restored items join the active tail. */
export function setPracticeQueueStatus<T extends PracticeQueueEntry>(
  items: readonly T[],
  scoreId: string,
  status: T['status'],
): T[] {
  const normalized = normalizePracticeQueue(items);
  const index = normalized.findIndex((entry) => entry.scoreId === scoreId);
  if (index < 0) return normalized;

  const current = normalized[index];
  if (current.status === status) return normalized;

  const next = normalized.slice();
  const activeCount = normalized.filter((entry) => entry.status !== 'archived').length;
  const wasArchived = current.status === 'archived';
  const willBeArchived = status === 'archived';
  next[index] = {
    ...current,
    status,
    order: wasArchived === willBeArchived ? current.order : willBeArchived ? normalized.length : activeCount,
  };
  return normalizePracticeQueue(next);
}

/** Move an active item one slot up (-1) or down (+1); archived items cannot be moved. */
export function movePracticeQueueItem<T extends PracticeQueueEntry>(
  items: readonly T[],
  scoreId: string,
  direction: -1 | 1,
): T[] {
  const normalized = normalizePracticeQueue(items);
  const active = normalized.filter((entry) => entry.status !== 'archived');
  const index = active.findIndex((entry) => entry.scoreId === scoreId);
  const destination = index + direction;
  if (index < 0 || destination < 0 || destination >= active.length) return normalized;

  const reordered = active.slice();
  [reordered[index], reordered[destination]] = [reordered[destination], reordered[index]];
  const reorderedActive = reordered.map((entry, order) => ({ ...entry, order }));
  const archived = normalized.filter((entry) => entry.status === 'archived');
  return normalizePracticeQueue([...reorderedActive, ...archived]);
}

/** Keep an explicit active score selection; otherwise choose the first active queue entry. */
export function preferredPracticeScoreId<T extends PracticeQueueEntry>(items: readonly T[], requestedId = ''): string {
  if (requestedId) return requestedId;
  const active = normalizePracticeQueue(items).filter((entry) => entry.status !== 'archived');
  return active[0]?.scoreId ?? '';
}

/** A small generation guard for async reads whose newest request must win. */
export function createGenerationGuard() {
  let generation = 0;
  return {
    next(): number { return ++generation; },
    invalidate(): number { return ++generation; },
    isCurrent(token: number): boolean { return token === generation; },
  };
}

/** Share one latest-wins read path between the initial load and later subscriptions. */
export function createLatestReadCoordinator<T>(
  read: () => Promise<T>,
  apply: (value: T, isInitial: boolean) => void,
  onError?: (cause: unknown, isInitial: boolean) => void,
) {
  const guard = createGenerationGuard();
  let applied = false;
  let disposed = false;

  return {
    async refresh(): Promise<void> {
      if (disposed) return;
      const generation = guard.next();
      try {
        const value = await read();
        if (disposed || !guard.isCurrent(generation)) return;
        const isInitial = !applied;
        apply(value, isInitial);
        applied = true;
      } catch (cause) {
        if (disposed || !guard.isCurrent(generation)) return;
        onError?.(cause, !applied);
      }
    },
    dispose(): void {
      disposed = true;
      guard.invalidate();
    },
  };
}

export interface CatalogVerificationIdentity {
  id: string;
  source: string;
  sourceId: string;
  format: string;
  category?: string;
  scoreUrl?: string;
  assetId?: string;
  revision: string;
}

/** Accept only the exact current catalog selection's unverified-to-SHA promotion. */
export function isVerifiedCatalogPromotion<T extends CatalogVerificationIdentity>(
  current: T | null,
  verified: T,
  currentSelectionGeneration: number,
  verifiedSelectionGeneration: number,
): boolean {
  return currentSelectionGeneration === verifiedSelectionGeneration
    && current !== null
    && current.source === 'catalog'
    && verified.source === 'catalog'
    && current.revision === 'unverified'
    && /^[a-f0-9]{64}$/.test(verified.revision)
    && current.id === verified.id
    && current.sourceId === verified.sourceId
    && current.format === verified.format
    && current.category === verified.category
    && current.scoreUrl === verified.scoreUrl
    && current.assetId === verified.assetId;
}

/** Match a subscribed record to the exact player-issued verification stamp. */
export function matchesCatalogVerificationRecord<T extends CatalogVerificationIdentity>(
  unverified: T,
  verified: T,
  record: T,
  currentSelectionGeneration: number,
  verifiedSelectionGeneration: number,
): boolean {
  return isVerifiedCatalogPromotion(unverified, verified, currentSelectionGeneration, verifiedSelectionGeneration)
    && record.id === verified.id
    && record.source === verified.source
    && record.sourceId === verified.sourceId
    && record.format === verified.format
    && record.category === verified.category
    && record.scoreUrl === verified.scoreUrl
    && record.assetId === verified.assetId
    && (record.revision === verified.revision || record.revision === 'unverified');
}
