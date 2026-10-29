import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { registerArLoader, getAr, type ArFn } from './ibe.ts';

/** Node 端 AR 解压库加载器（fs + vm） */
export function installNodeAr(): ArFn {
  registerArLoader(() => {
    const g = globalThis as any;
    if (!g.self) g.self = g;
    const code = readFileSync(new URL('./vendor/ar.es.js', import.meta.url), 'utf8');
    vm.runInThisContext(code);
    return g.ar as ArFn;
  });
  return getAr();
}