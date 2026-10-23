import crypto from 'node:crypto';

/** 认证与令牌工具：内置 crypto 实现 scrypt 密码哈希 + HMAC-SHA256 JWT，无第三方依赖 */

const JWT_SECRET = process.env.JWT_SECRET ?? 'mimi-guitar-dev-secret-change-me';
if (process.env.NODE_ENV === 'production' && !process.env.JWT_SECRET) {
  throw new Error('生产环境必须设置 JWT_SECRET 环境变量');
}
const TOKEN_TTL = 7 * 24 * 3600; // 7 天
const COOKIE_NAME = 'mimi_token';

export function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return salt + ':' + hash;
}

export function verifyPassword(password: string, stored: string): boolean {
  const parts = stored.split(':');
  if (parts.length !== 2) return false;
  const [salt, hash] = parts;
  const test = crypto.scryptSync(password, salt, 64);
  const expected = Buffer.from(hash, 'hex');
  return test.length === expected.length && crypto.timingSafeEqual(test, expected);
}

function b64url(o: unknown): string {
  return Buffer.from(JSON.stringify(o)).toString('base64url');
}

export interface TokenPayload {
  sub: string;
  [k: string]: unknown;
}

export function signToken(payload: TokenPayload): string {
  const header = { alg: 'HS256', typ: 'JWT' };
  const body = { ...payload, iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + TOKEN_TTL };
  const data = b64url(header) + '.' + b64url(body);
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(data).digest('base64url');
  return data + '.' + sig;
}

export function verifyToken(token: string): TokenPayload | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const data = parts[0] + '.' + parts[1];
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(data).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(parts[2]);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as TokenPayload;
    if (typeof payload.exp !== 'number' || payload.exp < Date.now() / 1000) return null;
    return payload;
  } catch {
    return null;
  }
}

export { COOKIE_NAME, TOKEN_TTL };