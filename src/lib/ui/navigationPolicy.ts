export const NAVIGATION_PREFETCH_PATHS = Object.freeze([
  '/',
  '/tabs',
  '/ukulele',
  '/article',
] as const);

export const NAVIGATION_HTML_CACHE_MAX_AGE_SECONDS = 10;

export type NavigationPrefetchStrategy = 'hover' | 'false' | undefined;

export interface NavigationCachePolicyInput {
  url: URL | string;
  method: string;
  status: number;
  authenticated: boolean;
  hasCookie?: boolean;
  hasSetCookie?: boolean;
}

export interface NavigationCachePolicy {
  cacheControl: string;
  varyCookie: boolean;
}

function parseUrl(value: URL | string, base?: string): URL | null {
  try {
    return value instanceof URL ? value : new URL(value, base);
  } catch {
    return null;
  }
}

/**
 * Only anonymous, same-origin top-level destinations are eligible. This uses
 * fetch/rel=prefetch; it never enables prerendering or changes click handling.
 */
export function isNavigationPrefetchAllowed(
  href: string,
  currentHref: string,
  authenticated = false,
): boolean {
  if (authenticated || !href || href.includes('?') || href.includes('#')) return false;

  const current = parseUrl(currentHref);
  const target = parseUrl(href, current?.href);
  if (!current || !target || current.origin !== target.origin) return false;
  if (target.username || target.password) return false;
  if (!(NAVIGATION_PREFETCH_PATHS as readonly string[]).includes(target.pathname)) return false;
  return target.href !== current.href;
}

export function getNavigationPrefetchAttribute(
  href: string,
  currentHref: string,
  authenticated = false,
): NavigationPrefetchStrategy {
  if (authenticated) {
    const current = parseUrl(currentHref);
    const target = parseUrl(href, current?.href);
    if (current && target && current.origin === target.origin
      && (NAVIGATION_PREFETCH_PATHS as readonly string[]).includes(target.pathname)) {
      return 'false';
    }
    return undefined;
  }
  return isNavigationPrefetchAllowed(href, currentHref) ? 'hover' : undefined;
}

function isPrefetchableRoute(url: URL, method: string): boolean {
  return (method === 'GET' || method === 'HEAD')
    && url.search === ''
    && (NAVIGATION_PREFETCH_PATHS as readonly string[]).includes(url.pathname);
}

export function getNavigationCachePolicy(input: NavigationCachePolicyInput): NavigationCachePolicy {
  const url = parseUrl(input.url, 'http://localhost');
  const routeIsSafe = Boolean(url && isPrefetchableRoute(url, input.method));
  const cacheable = routeIsSafe
    && input.status === 200
    && !input.authenticated
    && !input.hasCookie
    && !input.hasSetCookie;

  return {
    cacheControl: cacheable
      ? `private, max-age=${NAVIGATION_HTML_CACHE_MAX_AGE_SECONDS}`
      : 'no-store',
    // Safe routes always vary on the session cookie, including no-store
    // responses, so intermediary behavior cannot merge session variants.
    varyCookie: routeIsSafe,
  };
}

export interface NavigationHeaderBag {
  get(name: string): string | null;
  set(name: string, value: string): void;
}

export function applyNavigationCachePolicy(
  headers: NavigationHeaderBag,
  policy: NavigationCachePolicy,
): void {
  headers.set('Cache-Control', policy.cacheControl);
  if (!policy.varyCookie) return;

  const existing = headers.get('Vary');
  if (existing?.trim() === '*') return;
  const values = (existing ?? '').split(',').map((value) => value.trim()).filter(Boolean);
  if (!values.some((value) => value.toLowerCase() === 'cookie')) values.push('Cookie');
  headers.set('Vary', values.join(', '));
}
