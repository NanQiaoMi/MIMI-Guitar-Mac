/** 简易内存限流：滑动窗口，按 IP+路由 计数（单进程演示；多实例需换 Redis） */
const buckets = new Map<string, number[]>();

export function rateLimit(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  const arr = (buckets.get(key) ?? []).filter((t) => now - t < windowMs);
  if (arr.length >= limit) {
    buckets.set(key, arr);
    return false;
  }
  arr.push(now);
  buckets.set(key, arr);
  return true;
}

export function ipKey(req: Request, route: string): string {
  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'local';
  return route + ':' + ip;
}