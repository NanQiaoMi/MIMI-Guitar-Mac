#!/usr/bin/env node
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkScoreResources, prepareScoreResources, writeScoreResourceReport } from './lib/score-resource-files.mjs';
import { DEMO_TABS } from '../src/lib/demoData.ts';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const requiredPaths = [...new Set([
  ...DEMO_TABS.flatMap((tab) => [tab.scoreUrl, tab.screenshotUrl].filter(Boolean).map((url) => url.slice('/storage/'.length))),
  'soundfonts/acoustic_guitar_fast.sf2', 'soundfonts/ukulele_fast.sf2', 'soundfonts/0.sf2',
])];

function usage() {
  return [
    'Usage:',
    '  node tools/prepare-score-resources.mjs prepare --source <absolute public/storage> --target <absolute public/storage> [--apply] [--concurrency <1..16>]',
    '  node tools/prepare-score-resources.mjs check --source <absolute public/storage> --public <absolute public/storage> [--dist <absolute dist/client/storage>] [--concurrency <1..16>]',
    'prepare is a dry run unless --apply is explicitly supplied. check with --dist verifies the Astro build output too.',
  ].join('\n');
}

function parseArgs(argv) {
  const [mode, ...rest] = argv;
  if (mode !== 'prepare' && mode !== 'check') throw new Error(usage());
  const options = { mode, apply: false, concurrency: 4 };
  for (let index = 0; index < rest.length; index += 1) {
    const argument = rest[index];
    if (argument === '--apply') {
      options.apply = true;
      continue;
    }
    if (!['--source', '--target', '--public', '--dist', '--concurrency'].includes(argument)) {
      throw new Error(`Unknown option: ${argument}\n${usage()}`);
    }
    const value = rest[index + 1];
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${argument}\n${usage()}`);
    index += 1;
    const key = argument.slice(2);
    options[key] = key === 'concurrency' ? Number(value) : value;
  }
  if (!options.source) throw new Error(`--source is required\n${usage()}`);
  if (options.mode === 'prepare' && !options.target) throw new Error(`--target is required for prepare\n${usage()}`);
  if (options.mode === 'check' && !options.public) throw new Error(`--public is required for check\n${usage()}`);
  if (options.mode === 'check' && options.apply) throw new Error('--apply is only valid with prepare');
  if (!Number.isInteger(options.concurrency) || options.concurrency < 1 || options.concurrency > 16) {
    throw new Error('--concurrency must be an integer from 1 to 16');
  }
  return options;
}

function printExamples(report) {
  const examples = [];
  const add = (kind, entries) => {
    for (const entry of entries ?? []) {
      if (examples.length >= 12) return;
      examples.push(`${kind}: ${entry.path}`);
    }
  };
  add('conflict', report.conflicts);
  add('public missing', report.public?.missing);
  add('public extra', report.public?.extra);
  add('public different', report.public?.different);
  add('dist missing', report.dist?.missing);
  add('dist extra', report.dist?.extra);
  add('dist different', report.dist?.different);
  if (examples.length) console.error(examples.join('\n'));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const report = options.mode === 'prepare'
    ? await prepareScoreResources({
        sourceRoot: options.source,
        targetRoot: options.target,
        apply: options.apply,
        concurrency: options.concurrency,
        requiredPaths,
      })
    : await checkScoreResources({
        sourceRoot: options.source,
        publicRoot: options.public,
        distRoot: options.dist,
        concurrency: options.concurrency,
        requiredPaths,
      });

  const manifestPath = await writeScoreResourceReport(projectRoot, report);
  console.log(`operation=${report.operation}`);
  console.log(`status=${report.status}`);
  console.log(`manifest=${manifestPath}`);
  console.log(JSON.stringify(report.summary, null, 2));
  if (!report.ok) {
    printExamples(report);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
