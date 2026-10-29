/** A failed file response is distinct from an IBE decode or layout failure. */
export class ScoreRequestError extends Error {
  constructor(message, { kind = 'network', status = 0, cause } = {}) {
    super(message, cause === undefined ? undefined : { cause });
    this.name = 'ScoreRequestError';
    this.kind = kind;
    this.status = status;
  }
}

/**
 * Fetch the actual source bytes. Explicit retries revalidate a previous failure.
 * @param {string} scoreUrl
 * @param {{signal?: AbortSignal, retry?: boolean, fetchImpl?: typeof fetch}} [options]
 */
export async function fetchScoreBytes(scoreUrl, { signal, retry = false, fetchImpl = fetch } = {}) {
  try {
    const response = await fetchImpl(scoreUrl, { signal, cache: retry ? 'reload' : 'default' });
    if (!response.ok) {
      const status = response.status;
      const kind = status === 404 || status === 410 ? 'missing'
        : status === 401 || status === 403 ? 'forbidden'
        : status >= 500 ? 'server' : 'response';
      throw new ScoreRequestError(`谱面请求失败：HTTP ${status}`, { kind, status });
    }
    const contentType = response.headers.get('content-type') ?? '';
    if (/text\/html|application\/xhtml\+xml/i.test(contentType)) {
      throw new ScoreRequestError('谱面地址返回了网页内容', { kind: 'html', status: response.status });
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (signal?.aborted) throw signal.reason ?? new DOMException('The request was aborted', 'AbortError');
    if (!bytes.length) throw new ScoreRequestError('谱面响应为空', { kind: 'empty', status: response.status });
    const prefix = new TextDecoder().decode(bytes.subarray(0, 256)).replace(/^\uFEFF/, '').trimStart();
    if (/^(?:<!doctype\s+html|<html(?:\s|>)|<head(?:\s|>))/i.test(prefix)) {
      throw new ScoreRequestError('谱面地址返回了网页内容', { kind: 'html', status: response.status });
    }
    return bytes;
  } catch (cause) {
    // Leave cancellation to the caller's generation/timeout boundary.
    if (signal?.aborted || cause?.name === 'AbortError' || cause instanceof ScoreRequestError) throw cause;
    throw new ScoreRequestError('谱面请求未能完成', { kind: cause?.name === 'TimeoutError' ? 'timeout' : 'network', cause });
  }
}
