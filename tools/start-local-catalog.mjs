#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  DOCKER_TIMEOUT_MS,
  LocalCatalogRuntimeError,
  classifyDockerFailure,
  checkLocalCatalog,
  checkThenStart,
  probePrismaCatalog,
} from './lib/local-catalog-runtime.mjs';

const projectRoot = fileURLToPath(new URL('../', import.meta.url));
const serverEntry = path.join(projectRoot, 'dist', 'server', 'entry.mjs');

function runDocker(args) {
  const result = spawnSync('docker', args, {
    cwd: projectRoot,
    encoding: 'utf8',
    timeout: DOCKER_TIMEOUT_MS,
    maxBuffer: 1_000_000,
    windowsHide: true,
  });
  if (result.error || result.status !== 0) throw classifyDockerFailure(args, result);
  return result.stdout ?? '';
}

async function probePrisma(databaseUrl) {
  const { PrismaClient } = await import('@prisma/client');
  return probePrismaCatalog({
    databaseUrl,
    createClient: (url) => new PrismaClient({ datasources: { db: { url } } }),
  });
}

function parseArguments(argv) {
  if (argv.length === 0) return { mode: 'start' };
  if (argv.length === 1 && argv[0] === '--check') return { mode: 'check' };
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) return { mode: 'help' };
  throw new LocalCatalogRuntimeError('ARGUMENTS', '仅支持可选参数 --check。');
}

function printSafeStatus(result) {
  console.log(`[DATABASE_READY] 本地曲库预检通过：${result.database}，${result.rowCount} 条曲谱，127.0.0.1:${result.hostPort}。`);
  console.log('仅验证数据库、schema 与非空曲库；媒体资源仍需检查 /api/readiness。');
}

function launchServer(databaseUrl) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [serverEntry], {
      cwd: projectRoot,
      env: { ...process.env, DATABASE_URL: databaseUrl },
      stdio: 'inherit',
      windowsHide: true,
    });
    child.once('error', () => reject(new Error('无法启动本地站点进程。')));
    child.once('exit', (code) => {
      process.exitCode = Number.isInteger(code) ? code : 1;
      resolve();
    });
  });
}

async function main() {
  const { mode } = parseArguments(process.argv.slice(2));
  if (mode === 'help') {
    console.log('用法：npm run start:local [-- --check]\n只检查现存的 mimi-guitar-pg 容器和本地曲库；默认检查通过后启动已构建的站点。不会启动容器或迁移数据库。检查只验证数据库、schema 与非空曲库；媒体资源需另查 /api/readiness。');
    return;
  }

  if (mode === 'start' && !existsSync(serverEntry)) {
    throw new LocalCatalogRuntimeError('BUILD_MISSING', '未找到构建产物；请先运行 npm run build。');
  }

  const check = () => checkLocalCatalog({
    runDocker,
    probePrisma,
    existingDatabaseUrl: process.env.DATABASE_URL,
  });

  if (mode === 'check') {
    printSafeStatus(await check());
    return;
  }

  let checked;
  await checkThenStart({
    check: async () => {
      checked = await check();
      return checked;
    },
    launch: async (databaseUrl) => {
      printSafeStatus(checked);
      await launchServer(databaseUrl);
    },
  });
}

main().catch(async (error) => {
  const message = error instanceof LocalCatalogRuntimeError ? error.message : '本地曲库启动检查失败。';
  const code = error instanceof LocalCatalogRuntimeError ? error.code : 'START_FAILED';
  const output = `启动被保护检查拦截 [${code}]：${message}\n`;
  if (code === 'DATABASE_PROBE_TIMEOUT') {
    await new Promise((resolve) => process.stderr.write(output, resolve));
    // A timed-out Prisma engine may retain handles after bounded disconnect; fail closed and exit.
    process.exit(1);
  }
  console.error(output.trimEnd());
  process.exitCode = 1;
});
