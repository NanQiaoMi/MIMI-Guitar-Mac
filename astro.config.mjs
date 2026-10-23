import { defineConfig } from 'astro/config';
import svelte from '@astrojs/svelte';
import node from '@astrojs/node';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
  integrations: [svelte()],
  prefetch: {
    prefetchAll: false,
    defaultStrategy: 'hover',
  },
  experimental: {
    clientPrerender: false,
  },
  vite: {
    plugins: [tailwindcss()],
    optimizeDeps: {
      exclude: ['@coderline/alphatab'],
    },
    server: {
      fs: {
        // 允许 dev 下直接以 @fs 路径访问 node_modules 内 alphaTab 的 worker/worklet 模块
        allow: ['..'],
      },
    },
  },
});
