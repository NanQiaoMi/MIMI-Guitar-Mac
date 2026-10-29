import { constants as fsConstants, promises as fs } from 'node:fs';
import { createReadStream } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';

export const RESOURCE_DIRECTORIES = Object.freeze(['scores', 'xhe', 'screenshots', 'soundfonts']);

const ALLOWED_EXTENSIONS = Object.freeze({
  scores: new Set(['.ibe', '.gp', '.gp3', '.gp4', '.gp5', '.bak']),
  xhe: new Set(['.json']),
  screenshots: new Set(['.jpg', '.jpeg', '.png', '.webp']),
  soundfonts: new Set(['.sf2', '.json']),
});

const DEFAULT_CONCURRENCY = 4;

export class ScoreResourceSafetyError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ScoreResourceSafetyError';
  }
}

function isWithin(parent, candidate) {
  const relative = path.relative(parent, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function assertAbsolutePath(input, label) {
  if (typeof input !== 'string' || !input.trim() || !path.isAbsolute(input)) {
    throw new ScoreResourceSafetyError(`${label} must be an explicit absolute path`);
  }
  return path.resolve(input);
}

function assertStorageRootShape(root, label) {
  if (path.basename(root).toLowerCase() !== 'storage' || path.basename(path.dirname(root)).toLowerCase() !== 'public') {
    throw new ScoreResourceSafetyError(`${label} must point to a project public/storage directory`);
  }
  return path.resolve(root, '..', '..');
}

async function inspectPathComponents(root, { allowMissing = false, label = 'path' } = {}) {
  const parsed = path.parse(root);
  const pieces = root.slice(parsed.root.length).split(path.sep).filter(Boolean);
  let current = parsed.root;
  for (let index = 0; index < pieces.length; index += 1) {
    current = path.join(current, pieces[index]);
    let info;
    try {
      info = await fs.lstat(current);
    } catch (error) {
      if (allowMissing && error?.code === 'ENOENT') return false;
      throw new ScoreResourceSafetyError(`${label} does not exist or cannot be inspected: ${current}`);
    }
    if (info.isSymbolicLink()) {
      throw new ScoreResourceSafetyError(`${label} contains a symbolic link or junction: ${current}`);
    }
    if (index < pieces.length - 1 && !info.isDirectory()) {
      throw new ScoreResourceSafetyError(`${label} has a non-directory path component: ${current}`);
    }
  }
  return true;
}

async function validateRootPair(sourceInput, targetInput, { targetLabel = 'target' } = {}) {
  const sourceRoot = assertAbsolutePath(sourceInput, 'source');
  const targetRoot = assertAbsolutePath(targetInput, targetLabel);
  const sourceProject = assertStorageRootShape(sourceRoot, 'source');
  const targetProject = assertStorageRootShape(targetRoot, targetLabel);

  await inspectPathComponents(sourceRoot, { label: 'source' });
  await inspectPathComponents(targetRoot, { allowMissing: true, label: targetLabel });

  if (isWithin(sourceRoot, targetRoot) || isWithin(targetRoot, sourceRoot)) {
    throw new ScoreResourceSafetyError('source and target storage paths must be disjoint');
  }
  if (isWithin(sourceProject, targetProject) || isWithin(targetProject, sourceProject)) {
    throw new ScoreResourceSafetyError('source and target must be separate project trees; the source project is read-only');
  }

  const sourcePublic = path.join(sourceProject, 'public');
  const targetPublic = path.join(targetProject, 'public');
  await inspectPathComponents(sourcePublic, { label: 'source public directory' });
  await inspectPathComponents(targetPublic, { label: `${targetLabel} public directory` });
  return { sourceRoot, targetRoot, sourceProject, targetProject, sourcePublic, targetPublic };
}

async function listFiles(root, { allowMissingRoot = false, label = 'resource root' } = {}) {
  const exists = await inspectPathComponents(root, { allowMissing: allowMissingRoot, label });
  if (!exists) return new Map();
  const rootInfo = await fs.lstat(root);
  if (!rootInfo.isDirectory()) throw new ScoreResourceSafetyError(`${label} is not a directory: ${root}`);

  const files = new Map();
  async function visit(directory, relativeDirectory = '') {
    const entries = await fs.readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name, 'en'));
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name);
      const relative = relativeDirectory ? path.posix.join(relativeDirectory, entry.name) : entry.name;
      const info = await fs.lstat(absolute);
      if (info.isSymbolicLink()) throw new ScoreResourceSafetyError(`${label} contains a symbolic link or junction: ${absolute}`);
      if (info.isDirectory()) {
        await visit(absolute, relative);
        continue;
      }
      if (!info.isFile()) throw new ScoreResourceSafetyError(`${label} contains a non-regular file: ${absolute}`);
      if (info.size <= 0) throw new ScoreResourceSafetyError(`${label} contains an empty resource: ${absolute}`);
      files.set(relative, { absolute, size: info.size });
    }
  }
  await visit(root);
  return files;
}

async function collectInventory(storageRoot, { allowMissingRoot = false, label = 'storage root' } = {}) {
  const available = await inspectPathComponents(storageRoot, { allowMissing: allowMissingRoot, label });
  if (!available) return new Map();
  const rootInfo = await fs.lstat(storageRoot);
  if (!rootInfo.isDirectory()) throw new ScoreResourceSafetyError(`${label} is not a directory: ${storageRoot}`);

  const result = new Map();
  for (const category of RESOURCE_DIRECTORIES) {
    const categoryRoot = path.join(storageRoot, category);
    let categoryExists = true;
    try {
      await fs.lstat(categoryRoot);
    } catch (error) {
      if (error?.code === 'ENOENT') categoryExists = false;
      else throw error;
    }
    if (!categoryExists) continue;
    const categoryFiles = await listFiles(categoryRoot, { label: `${label}/${category}` });
    for (const [relative, file] of categoryFiles) {
      const extension = path.extname(relative).toLowerCase();
      if (!ALLOWED_EXTENSIONS[category].has(extension)) {
        throw new ScoreResourceSafetyError(`${label}/${category} contains an unsupported file type: ${relative}`);
      }
      result.set(path.posix.join(category, relative), file);
    }
  }
  return result;
}

async function mapLimit(items, limit, worker) {
  const output = new Array(items.length);
  let cursor = 0;
  let failure = null;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (!failure) {
      const index = cursor;
      cursor += 1;
      if (index >= items.length) return;
      try {
        output[index] = await worker(items[index], index);
      } catch (error) {
        failure = error;
      }
    }
  });
  await Promise.all(workers);
  if (failure) throw failure;
  return output;
}

async function sha256(filePath) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

async function hashedInventory(files, concurrency = DEFAULT_CONCURRENCY) {
  const entries = [...files.entries()].sort(([left], [right]) => left.localeCompare(right, 'en'));
  const hashes = await mapLimit(entries, concurrency, async ([relative, file]) => ({
    path: relative,
    size: file.size,
    sha256: await sha256(file.absolute),
  }));
  return new Map(hashes.map((entry) => [entry.path, entry]));
}

function compareInventories(expected, actual) {
  const missing = [];
  const extra = [];
  const different = [];
  for (const [relative, expectedFile] of expected) {
    const actualFile = actual.get(relative);
    if (!actualFile) {
      missing.push({ path: relative, expected: expectedFile });
    } else if (expectedFile.size !== actualFile.size || expectedFile.sha256 !== actualFile.sha256) {
      different.push({ path: relative, expected: expectedFile, actual: actualFile });
    }
  }
  for (const [relative, actualFile] of actual) {
    if (!expected.has(relative)) extra.push({ path: relative, actual: actualFile });
  }
  return { missing, extra, different };
}

function compactSummary(files, comparison) {
  return {
    expectedFiles: files.size,
    expectedBytes: [...files.values()].reduce((sum, file) => sum + file.size, 0),
    missing: comparison.missing.length,
    extra: comparison.extra.length,
    different: comparison.different.length,
  };
}

async function ensureSafeDirectory(directory, boundary) {
  if (!isWithin(boundary, directory)) throw new ScoreResourceSafetyError(`write path escaped target public directory: ${directory}`);
  const relative = path.relative(boundary, directory);
  let current = boundary;
  if (relative) {
    for (const piece of relative.split(path.sep)) {
      current = path.join(current, piece);
      try {
        const info = await fs.lstat(current);
        if (info.isSymbolicLink()) throw new ScoreResourceSafetyError(`target contains a symbolic link or junction: ${current}`);
        if (!info.isDirectory()) throw new ScoreResourceSafetyError(`target path component is not a directory: ${current}`);
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
        try { await fs.mkdir(current); }
        catch (creationError) {
          if (creationError?.code !== 'EEXIST') throw creationError;
          const created = await fs.lstat(current);
          if (!created.isDirectory() || created.isSymbolicLink()) throw new ScoreResourceSafetyError(`unsafe target directory: ${current}`);
        }
      }
    }
  }
}

function requireReferencedResources(manifest, requiredPaths) {
  const missing = requiredPaths.filter((relative) => !manifest.has(relative));
  if (missing.length) throw new ScoreResourceSafetyError(`source is missing required catalog or soundfont resources: ${missing.join(', ')}`);
}

export async function prepareScoreResources({ sourceRoot, targetRoot, apply = false, concurrency = DEFAULT_CONCURRENCY, requiredPaths = [] } = {}) {
  const roots = await validateRootPair(sourceRoot, targetRoot);
  const sourceRaw = await collectInventory(roots.sourceRoot, { label: 'source storage' });
  const sourceManifest = await hashedInventory(sourceRaw, concurrency);
  if (sourceManifest.size === 0) throw new ScoreResourceSafetyError('source storage has no files in the four allowed resource directories');
  requireReferencedResources(sourceManifest, requiredPaths);

  const targetRaw = await collectInventory(roots.targetRoot, { allowMissingRoot: true, label: 'target storage' });
  const targetManifest = await hashedInventory(targetRaw, concurrency);
  const comparison = compareInventories(sourceManifest, targetManifest);
  const conflicts = [...comparison.different, ...comparison.extra];
  const base = {
    operation: apply ? 'prepare-apply' : 'prepare-dry-run',
    sourceRoot: roots.sourceRoot,
    targetRoot: roots.targetRoot,
    directories: [...RESOURCE_DIRECTORIES],
    summary: compactSummary(sourceManifest, comparison),
    sourceFiles: [...sourceManifest.values()],
    conflicts,
    copied: [],
    status: conflicts.length ? 'conflict' : 'ready',
  };
  if (conflicts.length || !apply || comparison.missing.length === 0) {
    return { ok: conflicts.length === 0, ...base };
  }

  const publicBoundary = roots.targetPublic;
  await ensureSafeDirectory(publicBoundary, roots.targetProject);
  const stageRoot = await fs.mkdtemp(path.join(publicBoundary, '.score-resource-stage-'));
  const missing = comparison.missing.map((entry) => entry.expected);
  const copied = [];
  try {
    await mapLimit(missing, concurrency, async (entry) => {
      const sourceFile = path.join(roots.sourceRoot, ...entry.path.split('/'));
      const stagedFile = path.join(stageRoot, ...entry.path.split('/'));
      const targetFile = path.join(roots.targetRoot, ...entry.path.split('/'));
      await fs.mkdir(path.dirname(stagedFile), { recursive: true });
      await fs.copyFile(sourceFile, stagedFile, fsConstants.COPYFILE_EXCL);
      const stagedInfo = await fs.stat(stagedFile);
      const stagedHash = await sha256(stagedFile);
      if (stagedInfo.size !== entry.size || stagedHash !== entry.sha256) {
        throw new Error(`staged resource verification failed: ${entry.path}`);
      }

      await ensureSafeDirectory(path.dirname(targetFile), publicBoundary);
      try {
        await fs.link(stagedFile, targetFile);
      } catch (error) {
        if (error?.code !== 'EEXIST') throw error;
        const existingInfo = await fs.lstat(targetFile);
        if (!existingInfo.isFile() || existingInfo.isSymbolicLink()) throw new ScoreResourceSafetyError(`unsafe existing target: ${entry.path}`);
        const existingHash = await sha256(targetFile);
        if (existingInfo.size !== entry.size || existingHash !== entry.sha256) {
          throw new ScoreResourceSafetyError(`target changed during preparation and now conflicts: ${entry.path}`);
        }
        return;
      }
      const finalInfo = await fs.lstat(targetFile);
      if (!finalInfo.isFile() || finalInfo.isSymbolicLink()) throw new ScoreResourceSafetyError(`unsafe published target: ${entry.path}`);
      const finalHash = await sha256(targetFile);
      if (finalInfo.size !== entry.size || finalHash !== entry.sha256) {
        throw new Error(`published resource verification failed: ${entry.path}`);
      }
      copied.push(entry.path);
    });
  } finally {
    if (!isWithin(publicBoundary, path.resolve(stageRoot)) || !path.basename(stageRoot).startsWith('.score-resource-stage-')) {
      throw new ScoreResourceSafetyError('refusing to clean a staging directory outside the target public directory');
    }
    await inspectPathComponents(stageRoot, { label: 'owned staging directory' });
    await fs.rm(stageRoot, { recursive: true, force: true });
  }

  const finalRaw = await collectInventory(roots.targetRoot, { label: 'target storage' });
  const finalManifest = await hashedInventory(finalRaw, concurrency);
  const finalComparison = compareInventories(sourceManifest, finalManifest);
  return {
    ok: finalComparison.missing.length === 0 && finalComparison.extra.length === 0 && finalComparison.different.length === 0,
    ...base,
    status: 'prepared',
    copied: copied.sort((left, right) => left.localeCompare(right, 'en')),
    summary: compactSummary(sourceManifest, finalComparison),
    verification: finalComparison,
  };
}

async function compareStorage(sourceRoot, targetRoot, label, concurrency) {
  const targetFiles = await collectInventory(targetRoot, { allowMissingRoot: true, label });
  const targetManifest = await hashedInventory(targetFiles, concurrency);
  return compareInventories(sourceRoot, targetManifest);
}

export async function checkScoreResources({ sourceRoot, publicRoot, distRoot, concurrency = DEFAULT_CONCURRENCY, requiredPaths = [] } = {}) {
  const roots = await validateRootPair(sourceRoot, publicRoot, { targetLabel: 'public storage' });
  let builtRoot = null;
  if (distRoot !== undefined) {
    builtRoot = assertAbsolutePath(distRoot, 'dist storage');
    const expectedDistRoot = path.join(roots.targetProject, 'dist', 'client', 'storage');
    if (path.resolve(builtRoot) !== path.resolve(expectedDistRoot)) {
      throw new ScoreResourceSafetyError(`dist storage must be this project's dist/client/storage: ${expectedDistRoot}`);
    }
    await inspectPathComponents(builtRoot, { allowMissing: true, label: 'dist storage' });
  }

  const sourceRaw = await collectInventory(roots.sourceRoot, { label: 'source storage' });
  const sourceManifest = await hashedInventory(sourceRaw, concurrency);
  if (sourceManifest.size === 0) throw new ScoreResourceSafetyError('source storage has no files in the four allowed resource directories');
  requireReferencedResources(sourceManifest, requiredPaths);
  const publicComparison = await compareStorage(sourceManifest, roots.targetRoot, 'public storage', concurrency);
  const builtComparison = builtRoot ? await compareStorage(sourceManifest, builtRoot, 'dist storage', concurrency) : null;
  const ok = [publicComparison, builtComparison].filter(Boolean).every((comparison) =>
    comparison.missing.length === 0 && comparison.extra.length === 0 && comparison.different.length === 0,
  );

  return {
    ok,
    operation: builtRoot ? 'check-built' : 'check-public',
    sourceRoot: roots.sourceRoot,
    publicRoot: roots.targetRoot,
    distRoot: builtRoot,
    directories: [...RESOURCE_DIRECTORIES],
    sourceFiles: [...sourceManifest.values()],
    summary: {
      source: compactSummary(sourceManifest, { missing: [], extra: [], different: [] }),
      public: compactSummary(sourceManifest, publicComparison),
      ...(builtComparison ? { dist: compactSummary(sourceManifest, builtComparison) } : {}),
    },
    public: publicComparison,
    ...(builtComparison ? { dist: builtComparison } : {}),
    status: ok ? 'verified' : 'mismatch',
  };
}

export async function writeScoreResourceReport(projectRoot, report) {
  const absoluteProject = assertAbsolutePath(projectRoot, 'project root');
  await inspectPathComponents(absoluteProject, { label: 'project root' });
  const cacheRoot = path.join(absoluteProject, 'tools', '.cache', 'score-resources');
  await ensureSafeDirectory(cacheRoot, absoluteProject);
  const filename = `${report.operation}-${new Date().toISOString().replaceAll(':', '-')}-${randomUUID()}.json`;
  const output = path.join(cacheRoot, filename);
  await fs.writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx' });
  return output;
}
