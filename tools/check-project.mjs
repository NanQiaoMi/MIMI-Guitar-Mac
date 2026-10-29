import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';

const require = createRequire(import.meta.url);
const tasks = [
  ['TypeScript', require.resolve('typescript/bin/tsc'), ['--noEmit', '--pretty', 'false']],
  ['Astro', resolve(dirname(require.resolve('@astrojs/check')), '../bin/astro-check.js'), ['--minimumSeverity', 'error']],
  ['Svelte', require.resolve('svelte-check/bin/svelte-check'), ['--workspace', '.', '--threshold', 'error']],
];

for (const [label, entry, args] of tasks) {
  console.log(`Checking ${label}`);
  const result = spawnSync(process.execPath, [entry, ...args], { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}
