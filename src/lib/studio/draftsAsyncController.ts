export type DraftCommitKind = 'load' | 'import' | 'delete';

export type DraftReadTicket = {
  session: number;
  revision: number;
};

export type DraftCommitTicket = {
  session: number;
  operation: number;
  kind: DraftCommitKind;
  draftId?: string;
};

/**
 * Wait for any already-issued editor save before taking the snapshot to load.
 * The caller owns the commit ticket and supplies its validity check so stale
 * dialog sessions cannot read or adopt a project after the boundary settles.
 */
export async function loadDraftAfterBoundary<T>(
  beforeLoad: (() => Promise<void>) | undefined,
  readProject: () => Promise<T | null>,
  isCurrent: () => boolean,
  adoptProject: (project: T) => void | boolean | Promise<void | boolean>,
): Promise<'adopted' | 'stale'> {
  await beforeLoad?.();
  if (!isCurrent()) return 'stale';

  const project = await readProject();
  if (!isCurrent()) return 'stale';
  if (!project) throw new Error('草稿在保存完成后已不存在，请刷新列表后重试。');

  const adopted = await adoptProject(project);
  if (!isCurrent()) return 'stale';
  if (adopted === false) throw new Error('当前工程尚未替换，草稿仍保留在本机。');
  return 'adopted';
}

/**
 * Owns the async identity rules for the drafts dialog. List reads are
 * replaceable; once a project replacement or deletion starts, the dialog
 * cannot close until that operation settles.
 */
export class DraftsAsyncController {
  private session = 0;
  private open = false;
  private readRevision = 0;
  private operationRevision = 0;
  private activeCommit: DraftCommitTicket | null = null;
  private disposed = false;

  openSession(): number | null {
    if (this.disposed) return null;
    if (!this.open) {
      this.open = true;
      this.session += 1;
      this.readRevision += 1;
    }
    return this.session;
  }

  closeSession(session: number): boolean {
    if (!this.isSessionCurrent(session)) return true;
    if (this.activeCommit) return false;
    this.open = false;
    this.session += 1;
    this.readRevision += 1;
    return true;
  }

  isSessionCurrent(session: number): boolean {
    return !this.disposed && this.open && this.session === session;
  }

  beginRead(session: number): DraftReadTicket | null {
    if (!this.isSessionCurrent(session) || this.activeCommit) return null;
    this.readRevision += 1;
    return { session, revision: this.readRevision };
  }

  isReadCurrent(ticket: DraftReadTicket): boolean {
    return this.isSessionCurrent(ticket.session)
      && this.activeCommit === null
      && this.readRevision === ticket.revision;
  }

  beginCommit(kind: DraftCommitKind, session: number, draftId?: string): DraftCommitTicket | null {
    if (!this.isSessionCurrent(session) || this.activeCommit) return null;
    this.readRevision += 1;
    const ticket: DraftCommitTicket = {
      session,
      operation: ++this.operationRevision,
      kind,
      ...(draftId ? { draftId } : {}),
    };
    this.activeCommit = ticket;
    return ticket;
  }

  isCommitCurrent(ticket: DraftCommitTicket): boolean {
    return !this.disposed
      && this.open
      && this.session === ticket.session
      && this.activeCommit === ticket;
  }

  finishCommit(ticket: DraftCommitTicket): boolean {
    if (this.activeCommit !== ticket) return false;
    this.activeCommit = null;
    return true;
  }

  get isCommitting(): boolean {
    return this.activeCommit !== null;
  }

  dispose(): void {
    this.disposed = true;
    this.open = false;
    this.session += 1;
    this.readRevision += 1;
    this.activeCommit = null;
  }
}
