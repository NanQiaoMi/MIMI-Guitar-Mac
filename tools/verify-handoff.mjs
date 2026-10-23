#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { lstat, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function safeRelative(value) {
  return typeof value === 'string' && value.length > 0 && !/[\\:\x00-\x1f]/.test(value)
    && !value.startsWith('/') && value.split('/').every((part) => part && part !== '.' && part !== '..');
}

/** Verify immutable payload files before installing dependencies or opening the project. */
export async function verifyHandoff(rootInput, { onProgress = () => {} } = {}) {
  const root = await realpath(path.resolve(rootInput));
  const manifestPath = path.join(root, 'PACKAGE-MANIFEST.json');
  const stat = await lstat(manifestPath);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 64 * 1024 * 1024) {
    throw new Error('Invalid package manifest file.');
  }
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.files)
    || manifest.files.length < 1 || manifest.files.length > 200_000
    || manifest.fileCount !== manifest.files.length) throw new Error('Invalid manifest structure.');
  const seen = new Set();
  let declaredBytes = 0;
  for (const entry of manifest.files) {
    if (!safeRelative(entry.path) || !Number.isSafeInteger(entry.bytes) || entry.bytes < 0
      || !/^[0-9a-f]{64}$/.test(entry.sha256 ?? '')) throw new Error('Invalid manifest file entry.');
    const key = entry.path.normalize('NFC').toLowerCase();
    if (seen.has(key)) throw new Error('Duplicate or case-colliding manifest path.');
    seen.add(key);
    declaredBytes += entry.bytes;
    if (!Number.isSafeInteger(declaredBytes)) throw new Error('Manifest byte count is too large.');
  }
  if (manifest.totalBytes !== declaredBytes) throw new Error('Manifest byte count does not match.');
  const directories = new Set([root]);
  let verified = 0;
  let verifiedBytes = 0;
  let nextIndex = 0;
  async function verifyFile(entry) {
    const parts = entry.path.split('/');
    let directory = root;
    for (const part of parts.slice(0, -1)) {
      directory = path.join(directory, part);
      if (directories.has(directory)) continue;
      const parent = await lstat(directory);
      if (!parent.isDirectory() || parent.isSymbolicLink()) throw new Error(`Unsafe directory: ${entry.path}`);
      directories.add(directory);
    }
    const file = path.join(root, ...parts);
    const fileStat = await lstat(file);
    if (!fileStat.isFile() || fileStat.isSymbolicLink() || fileStat.size !== entry.bytes) {
      throw new Error(`Missing, changed, or unsafe file: ${entry.path}`);
    }
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(file)) hash.update(chunk);
    if (hash.digest('hex') !== entry.sha256) throw new Error(`Checksum mismatch: ${entry.path}`);
    verified += 1;
    verifiedBytes += fileStat.size;
    if (verified % 5000 === 0) onProgress({ verified, total: manifest.fileCount });
  }
  // Do not allocate all media files in memory. At most four streams are active.
  const workers = Array.from({ length: Math.min(4, manifest.fileCount) }, async () => {
    while (nextIndex < manifest.files.length) await verifyFile(manifest.files[nextIndex++]);
  });
  await Promise.all(workers);
  return { status: 'verified', files: verified, bytes: verifiedBytes, sourceRevision: manifest.sourceRevision };
}

export function parseVerifyArgs(args) {
  if (args.includes('--help') || args.includes('-h')) return { help: true };
  if (args.length === 0) return { root: path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..') };
  if (args.length === 2 && args[0] === '--root' && args[1] && !args[1].startsWith('--')) return { root: args[1] };
  throw new Error('Usage: node tools/verify-handoff.mjs [--root <package directory>]');
}

if (import.meta.main) {
  try {
    const options = parseVerifyArgs(process.argv.slice(2));
    if (options.help) console.log('Usage: node project/tools/verify-handoff.mjs --root .\nVerifies every immutable file in PACKAGE-MANIFEST.json; no install, database write, or network access. Run before npm ci.');
    else console.log(JSON.stringify(await verifyHandoff(options.root, { onProgress: (progress) => console.log(JSON.stringify(progress)) })));
  } catch (error) {
    console.error(`Package verification failed: ${error instanceof Error ? error.message : 'unknown failure'}`);
    process.exitCode = 1;
  }
}
