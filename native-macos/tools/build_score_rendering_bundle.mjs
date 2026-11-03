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
if (!modules) throw new Error('Local esbuild and @coderline/alphatab are required; this script does not install dependencies.');
const alphaTabPackage = JSON.parse(fs.readFileSync(path.join(modules, '@coderline/alphatab/package.json'), 'utf8'));
if (alphaTabPackage.version !== '1.8.4') throw new Error(`Expected original AlphaTab 1.8.4, found ${alphaTabPackage.version}`);
const esbuild = require(path.join(modules, 'esbuild/lib/main.js'));
const entry = 'native-macos/Resources/Player/score-rendering-entry.ts';
const outfile = 'native-macos/Resources/Player/score-rendering.bundle.js';
const result = await esbuild.build({
  absWorkingDir: root,
  entryPoints: [entry],
  outfile,
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'es2020',
  legalComments: 'inline',
  // Original renderer patches identify AlphaTab factories by constructor.name.
  keepNames: true,
  minify: false,
  nodePaths: [modules],
  plugins: [{
    name: 'local-ar-text',
    setup(build) {
      build.onResolve({ filter: /ar\.es\.js\?raw$/ }, args => ({
        path: path.resolve(args.resolveDir, args.path.slice(0, -4)),
        namespace: 'raw-text',
      }));
      build.onLoad({ filter: /.*/, namespace: 'raw-text' }, args => ({
        contents: `export default ${JSON.stringify(fs.readFileSync(args.path, 'utf8'))};`,
        loader: 'js',
      }));
    },
  }],
  metafile: true,
});
const digest = filename => crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
const manifest = {
  esbuildVersion: esbuild.version,
  alphaTabVersion: alphaTabPackage.version,
  entry, outfile,
  options: { format: 'iife', platform: 'browser', target: 'es2020', keepNames: true, minify: false },
  inputs: Object.fromEntries(Object.keys(result.metafile.inputs).map(filename => [
    filename, digest(path.resolve(root, filename.replace(/^raw-text:/, ''))),
  ])),
  outputSha256: digest(path.join(root, outfile)),
  outputBytes: fs.statSync(path.join(root, outfile)).size,
};
const buildDirectory = path.join(root, 'native-macos/.build');
fs.mkdirSync(buildDirectory, { recursive: true });
fs.writeFileSync(path.join(buildDirectory, 'score-rendering-metafile.json'), JSON.stringify(result.metafile, null, 2) + '\n');
fs.writeFileSync(path.join(buildDirectory, 'score-rendering-build.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify(manifest, null, 2));
