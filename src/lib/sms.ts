/** 短信验证码本地 mock：内存存储，开发/演示用途；生产需接入真实短信服务 */
const codes = new Map<string, { code: string; exp: number }>();

export function issueCode(phone: string): string {
  const code = String(Math.floor(100000 + Math.random() * 900000));
  codes.set(phone, { code, exp: Date.now() + 5 * 60 * 1000 });
  return code;
}

export function consumeCode(phone: string, code: string): boolean {
  const rec = codes.get(phone);
  if (!rec) return false;
  codes.delete(phone);
  return rec.code === code && rec.exp > Date.now();
}