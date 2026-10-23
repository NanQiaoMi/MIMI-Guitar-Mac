#!/usr/bin/env node
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createMacBootstrap,
  createMacProcessRunner,
  MAC_BOOTSTRAP_HELP,
  MAC_BOOTSTRAP_RESTORE_HELP,
  MacBootstrapError,
} from './lib/mac-bootstrap.mjs';

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function parseCommandLine(argv) {
  if (argv.length === 0 || argv[0] === 'help' || argv[0] === '--help' || argv[0] === '-h') {
    return { command: 'help', dryRun: false };
  }
  const [command, ...flags] = argv;
  const commands = new Set(['doctor', 'install', 'restore-catalog', 'build', 'dev', 'start']);
  if (!commands.has(command)) throw new MacBootstrapError(`Unknown command: ${command}`);
  if (flags.length > 1 || (flags.length === 1 && flags[0] !== '--dry-run')) {
    throw new MacBootstrapError('Only the optional --dry-run flag is supported.');
  }
  if (flags.includes('--dry-run') && command === 'doctor') {
    throw new MacBootstrapError('doctor is already read-only and does not accept --dry-run.');
  }
  return { command, dryRun: flags.includes('--dry-run') };
}

async function main() {
  const request = parseCommandLine(process.argv.slice(2));
  if (request.command === 'help') {
    console.log(`${MAC_BOOTSTRAP_HELP}${MAC_BOOTSTRAP_RESTORE_HELP}`);
    return;
  }

  const bootstrap = createMacBootstrap({
    projectDir,
    run: createMacProcessRunner(),
    output: (message) => console.log(message),
  });

  if (request.command === 'doctor') {
    const result = await bootstrap.doctor();
    if (!result.ok) process.exitCode = 1;
    return;
  }
  if (request.command === 'install') return bootstrap.install({ dryRun: request.dryRun });
  if (request.command === 'restore-catalog') return bootstrap.restoreCatalog({ dryRun: request.dryRun });
  if (request.command === 'build') return bootstrap.build({ dryRun: request.dryRun });
  if (request.command === 'dev') return bootstrap.dev({ dryRun: request.dryRun });
  if (request.command === 'start') return bootstrap.start({ dryRun: request.dryRun });
}

main().catch((error) => {
  const message = error instanceof MacBootstrapError
    ? error.message
    : 'The Mac bootstrap stopped unexpectedly; review local files and tools before retrying.';
  console.error(`Mac bootstrap stopped: ${message}`);
  if (process.argv[2] === 'restore-catalog') {
    console.error('If the failure happened after resource creation, the tool left those resources in place. Inspect them manually before any retry.');
  }
  process.exitCode = 1;
});
