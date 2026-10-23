export type CatalogSearchSource = 'catalog' | 'demo' | 'unavailable';

export interface CatalogSearchResult {
  source: CatalogSearchSource;
  tabs: any[];
  error?: string;
}

/** A per-palette request owner; stale responses cannot escape after query/category changes. */
export class CatalogSearchClient {
  private generation = 0;
  private controller: AbortController | null = null;
  private readonly fetcher: typeof fetch;

  constructor(fetcher?: typeof fetch) {
    this.fetcher = fetcher ?? ((input, init) => globalThis.fetch(input, init));
  }

  cancel(): void {
    this.generation++;
    this.controller?.abort();
    this.controller = null;
  }

  async search(query: string, category: 'all' | 'guitar' | 'ukulele', limit = 12): Promise<CatalogSearchResult | null> {
    const q = query.trim();
    if (!q) {
      this.cancel();
      return { source: 'catalog', tabs: [] };
    }

    const generation = ++this.generation;
    this.controller?.abort();
    const controller = new AbortController();
    this.controller = controller;
    try {
      const queryParams = new URLSearchParams({ q, category, limit: String(limit) });
      const url = `/api/search?${queryParams.toString()}`;
      const response = await this.fetcher(url, { signal: controller.signal });
      let payload: any;
      try { payload = await response.json(); }
      catch { payload = null; }
      if (generation !== this.generation) return null;
      if (!response.ok || payload?.ok !== true || !['catalog', 'demo'].includes(payload?.source)) {
        return {
          source: 'unavailable',
          tabs: [],
          error: payload?.error === 'catalog_unavailable'
            ? '曲库服务暂不可用，未能完成搜索。'
            : typeof payload?.error === 'string' ? payload.error : '曲库服务暂不可用，未能完成搜索。',
        };
      }
      return {
        source: payload.source,
        tabs: Array.isArray(payload.tabs) ? payload.tabs : [],
      };
    } catch {
      if (generation !== this.generation || controller.signal.aborted) return null;
      return {
        source: 'unavailable',
        tabs: [],
        error: '无法连接曲库服务，请检查网络后重试。',
      };
    } finally {
      if (generation === this.generation) this.controller = null;
    }
  }
}
