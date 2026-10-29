import arSource from './vendor/ar.es.js?raw';
import { registerArLoader, getAr, type ArFn } from './ibe.ts';

/** 浏览器端 AR 解压库加载器（?raw + eval） */
export function installBrowserAr(): ArFn {
  registerArLoader(() => {
    const g = globalThis as any;
    // eslint-disable-next-line no-eval
    if (typeof g.ar !== 'function') (0, eval)(arSource);
    return g.ar as ArFn;
  });
  return getAr();
}