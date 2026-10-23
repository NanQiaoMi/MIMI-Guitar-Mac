/**
 * Keep malformed or empty score documents away from AlphaTab's renderer.
 * A score does not need notes to be previewable, but it must contain at least
 * one track, staff, and bar so AlphaTab has something it can lay out.
 */
export class ScoreStructureError extends Error {
  constructor(message = '乐谱文件没有可显示的谱表或小节') {
    super(message);
    this.name = 'ScoreStructureError';
    this.code = 'SCORE_NOT_RENDERABLE';
  }
}

export function hasRenderableScore(value) {
  const tracks = value?.tracks;
  if (!Array.isArray(tracks) || tracks.length === 0) return false;

  return tracks.some((track) => {
    if (!Array.isArray(track?.staves) || track.staves.length === 0) return false;
    return track.staves.some((staff) =>
      Array.isArray(staff?.bars) && staff.bars.some((bar) => bar !== null && typeof bar === 'object')
    );
  });
}

export function assertRenderableScore(value) {
  if (!hasRenderableScore(value)) throw new ScoreStructureError();
  return value;
}

export function scoreLoadFailurePresentation(scoreUrl, stage = 'fetch', failure = {}) {
  if (typeof scoreUrl !== 'string' || !scoreUrl.trim()) {
    return {
      kind: 'missing',
      message: '此曲目目前没有可用的乐谱文件。',
      canRetry: false,
      canDownload: false,
    };
  }

  if (stage === 'fetch') {
    const kind = failure?.kind;
    const messages = {
      missing: '没有找到这份乐谱文件（404/410）。资源恢复后可重试；当前下载地址也不可用。',
      forbidden: '当前无法访问这份乐谱（401/403）。请确认登录状态和访问权限后重试。',
      server: '乐谱服务暂时出错，请稍后重试。',
      html: '乐谱地址返回了网页，未取得原谱文件。请检查资源路径后重试。',
      empty: '乐谱文件返回了空内容，请恢复完整文件后重试。',
      timeout: '乐谱加载超时，请稍后重试。',
    };
    return {
      kind: kind === 'missing' ? 'missing' : 'load',
      message: Object.hasOwn(messages, kind) ? messages[kind] : '乐谱请求未能完成，请确认连接后重试。',
      canRetry: true,
      canDownload: false,
    };
  }

  if (stage === 'decode') {
    return {
      kind: 'invalid',
      message: '文件已取回，但解码失败，暂时无法排版。原谱不会被修改，可下载留存后再试。',
      canRetry: true,
      canDownload: true,
    };
  }

  if (stage === 'convert') {
    return {
      kind: 'invalid',
      message: '文件已取回，但没有找到可显示的谱轨或小节。原谱不会被修改，可下载留存后再试。',
      canRetry: true,
      canDownload: true,
    };
  }

  if (stage === 'render') {
    return {
      kind: 'render',
      message: '文件已读取，但谱面排版没有完成。原谱不会被修改，可下载留存或稍后重试。',
      canRetry: true,
      canDownload: true,
    };
  }

  return {
    kind: 'load',
    message: '乐谱暂时无法加载，请稍后重试。',
    canRetry: true,
    canDownload: true,
  };
}

/** Return only a same-origin/root-relative URL for the original file link. */
export function safeScoreDownloadHref(scoreUrl, origin = '') {
  if (typeof scoreUrl !== 'string' || !scoreUrl.trim()) return '';
  const value = scoreUrl.trim();
  if (!origin) {
    return value.startsWith('/') && !value.startsWith('//') && !value.includes('\\') ? value : '';
  }

  try {
    const base = new URL(origin);
    const resolved = new URL(value, base);
    const isWebProtocol = resolved.protocol === 'http:' || resolved.protocol === 'https:';
    return isWebProtocol && resolved.origin === base.origin ? resolved.href : '';
  } catch {
    return '';
  }
}
/**
 * Apply a UI selection only after its async operation succeeds. On failure,
 * restore the previous selection and let the caller re-render that state.
 */
export async function runWithRollbackTransaction({
  previousValue,
  nextValue,
  commit,
  apply,
  rollback,
}) {
  try {
    await apply(nextValue);
    commit(nextValue);
    return { ok: true, error: null, rollbackError: null };
  } catch (error) {
    commit(previousValue);
    try {
      await rollback(previousValue);
      return { ok: false, error, rollbackError: null };
    } catch (rollbackError) {
      return { ok: false, error, rollbackError };
    }
  }
}
