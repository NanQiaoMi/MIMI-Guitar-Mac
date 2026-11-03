import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const require = createRequire(import.meta.url);
const candidates = [
  path.join(root, 'node_modules'),
  path.join(root, 'native-macos/.build/studio-bundle-tooling-20261024-a/node_modules'),
];
const modules = candidates.find(directory =>
  fs.existsSync(path.join(directory, 'esbuild/lib/main.js')) &&
  fs.existsSync(path.join(directory, '@coderline/alphatab/package.json')));
if (!modules) throw new Error('Local esbuild and @coderline/alphatab are required');
const esbuild = require(path.join(modules, 'esbuild/lib/main.js'));
const entry = 'native-macos/Resources/Player/guitar-audio-entry.ts';
const outfile = 'native-macos/Resources/Player/guitar-audio.bundle.js';
const result = await esbuild.build({
  absWorkingDir: root,
  entryPoints: [entry],
  outfile,
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'es2020',
  legalComments: 'inline',
  keepNames: true,
  minify: false,
  nodePaths: [modules],
});
console.log('Successfully built guitar-audio.bundle.js');
