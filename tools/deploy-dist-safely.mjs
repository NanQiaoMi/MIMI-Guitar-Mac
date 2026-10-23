#!/usr/bin/env node
/**
 * Safely deploy the build artefacts that can affect the live player without
 * touching the database, uploads, or static storage outside Astro's bundles.
 *
 * Usage (PowerShell):
 *   $env:MIMI_DEPLOY_PASSWORD_FILE = 'C:\\path\\to\\password.txt'
 *   node tools/deploy-dist-safely.mjs probe
 *   node tools/deploy-dist-safely.mjs deploy
 *
 * The password is read only at runtime and is never written to output, a
 * command line, an archive, or the repository.
 */
import { execFileSync } from 'node:child_process';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from 'ssh2';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDir, '..');
const distRoot = path.join(projectRoot, 'dist');

const host = process.env.MIMI_DEPLOY_HOST || '154.88.65.55';
const port = Number(process.env.MIMI_DEPLOY_PORT || '64555');
const passwordFile = process.env.MIMI_DEPLOY_PASSWORD_FILE;
const remoteRoot = '/var/www/mimi-guitar';
const serviceName = 'mimi-guitar';
const action = process.argv[2] || 'probe';

function fail(message) {
  console.error(`deploy failed: ${message}`);
  process.exitCode = 1;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function runLocal(command, args) {
  return execFileSync(command, args, {
    cwd: projectRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });
}

async function loadPassword() {
  if (!passwordFile) {
    throw new Error('set MIMI_DEPLOY_PASSWORD_FILE to a one-line password file before deploying');
  }
  const value = (await readFile(passwordFile, 'utf8')).replace(/[\r\n]+$/, '');
  if (!value) throw new Error('password file is empty');
  return value;
}

function connect(password) {
  return new Promise((resolve, reject) => {
    const client = new Client();
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      fn(value);
    };
    client.once('ready', () => finish(resolve, client));
    client.once('error', (error) => finish(reject, error));
    client.connect({
      host,
      port,
      username: 'root',
      password,
      readyTimeout: 20_000,
      tryKeyboard: false
    });
  });
}

function execRemote(client, script) {
  return new Promise((resolve, reject) => {
    client.exec(`sh -lc ${shellQuote(script)}`, (error, stream) => {
      if (error) {
        reject(error);
        return;
      }
      let stdout = '';
      let stderr = '';
      stream.on('data', (chunk) => { stdout += chunk.toString(); });
      stream.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
      stream.once('close', (code, signal) => {
        if (code === 0) {
          resolve({ stdout, stderr });
          return;
        }
        const detail = [stderr.trim(), stdout.trim()].filter(Boolean).join('\n');
        reject(new Error(`remote command exited ${code ?? signal ?? 'unknown'}${detail ? `: ${detail}` : ''}`));
      });
    });
  });
}

function openSftp(client) {
  return new Promise((resolve, reject) => {
    client.sftp((error, sftp) => error ? reject(error) : resolve(sftp));
  });
}

function uploadFile(sftp, localPath, remotePath) {
  return new Promise((resolve, reject) => {
    sftp.fastPut(localPath, remotePath, (error) => error ? reject(error) : resolve());
  });
}

function deploymentToken() {
  return new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14);
}

async function createArchive(token) {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'mimi-guitar-deploy-'));
  const archive = path.join(tempDir, `mimi-dist-${token}.tar.gz`);
  try {
    runLocal('tar', ['-czf', archive, '-C', distRoot, 'server', 'client/_astro']);
    const listing = runLocal('tar', ['-tzf', archive]);
    for (const required of ['server/', 'server/entry.mjs', 'client/_astro/', 'client/_astro/alphaTab.js']) {
      if (!listing.includes(required)) throw new Error(`archive verification did not find ${required}`);
    }
    return { archive, tempDir };
  } catch (error) {
    await rm(tempDir, { recursive: true, force: true });
    throw error;
  }
}

const probeScript = `
set -eu
ROOT=${shellQuote(remoteRoot)}
SERVICE=${shellQuote(serviceName)}
test -d "$ROOT"
test -d "$ROOT/dist/server"
test -d "$ROOT/dist/client/_astro"
test -f "$ROOT/dist/server/entry.mjs"
systemctl is-active --quiet "$SERVICE"
printf 'service=active\\n'
printf 'server_entry=present\\n'
printf 'astro_files='
find "$ROOT/dist/client/_astro" -maxdepth 1 -type f | wc -l
printf 'deploy_backups='
if [ -d "$ROOT/.codex-deploy-backups" ]; then find "$ROOT/.codex-deploy-backups" -mindepth 1 -maxdepth 1 -type d | wc -l; else printf '0\\n'; fi
`;

const diagnoseScript = `
set +e
ROOT=${shellQuote(remoteRoot)}
SERVICE=${shellQuote(serviceName)}
printf '%s\\n' '--- systemd ---'
systemctl status "$SERVICE" --no-pager -l 2>&1 | sed -n '1,30p'
printf '%s\\n' '--- unit ---'
systemctl cat "$SERVICE" 2>&1
printf '%s\\n' '--- listeners ---'
ss -lntp 2>&1 | grep -E '(:4321|:80|:22)' || true
printf '%s\\n' '--- process ---'
ps -eo pid,ppid,stat,lstart,args 2>&1 | grep -E '[n]ode|[m]imi-guitar' || true
printf '%s\\n' '--- recent journal ---'
journalctl -u "$SERVICE" -n 80 --no-pager 2>&1
printf '%s\\n' '--- tree ---'
find "$ROOT" -maxdepth 2 -type d -printf '%M %u:%g %p\\n' 2>&1 | sort | sed -n '1,80p'
printf '%s\\n' '--- backups ---'
if [ -d "$ROOT/.codex-deploy-backups" ]; then
  find "$ROOT/.codex-deploy-backups" -mindepth 1 -maxdepth 2 -printf '%M %u:%g %p\\n' 2>&1 | sort | sed -n '1,120p'
fi
`;

function deployScript(token) {
  const archive = `/tmp/mimi-guitar-dist-${token}.tar.gz`;
  const stage = `${remoteRoot}/.codex-deploy-staging/${token}`;
  const backup = `${remoteRoot}/.codex-deploy-backups/${token}`;
  return `
set -eu
ROOT=${shellQuote(remoteRoot)}
SERVICE=${shellQuote(serviceName)}
ARCHIVE=${shellQuote(archive)}
STAGE=${shellQuote(stage)}
BACKUP=${shellQuote(backup)}
old_server=0
old_astro=0
new_server=0
new_astro=0
rollback() {
  rc=$?
  trap - 0
  if [ "$rc" -ne 0 ]; then
    set +e
    printf 'deployment_error=rolling_back\\n' >&2
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    if [ "$new_astro" -eq 1 ] && [ -d "$ROOT/dist/client/_astro" ]; then
      mv "$ROOT/dist/client/_astro" "$BACKUP/new-client-_astro-failed"
    fi
    if [ "$new_server" -eq 1 ] && [ -d "$ROOT/dist/server" ]; then
      mv "$ROOT/dist/server" "$BACKUP/new-server-failed"
    fi
    if [ "$old_server" -eq 1 ] && [ -d "$BACKUP/server" ]; then
      mv "$BACKUP/server" "$ROOT/dist/server"
    fi
    if [ "$old_astro" -eq 1 ] && [ -d "$BACKUP/client-_astro" ]; then
      mv "$BACKUP/client-_astro" "$ROOT/dist/client/_astro"
    fi
    systemctl start "$SERVICE" >/dev/null 2>&1 || true
  fi
  rm -f "$ARCHIVE" || true
  exit "$rc"
}
trap rollback 0
test -f "$ARCHIVE"
test -d "$ROOT/dist/server"
test -d "$ROOT/dist/client/_astro"
mkdir -p "$STAGE" "$BACKUP"
tar -xzf "$ARCHIVE" -C "$STAGE"
test -f "$STAGE/server/entry.mjs"
test -f "$STAGE/client/_astro/alphaTab.js"
systemctl stop "$SERVICE"
mv "$ROOT/dist/server" "$BACKUP/server"
old_server=1
mv "$ROOT/dist/client/_astro" "$BACKUP/client-_astro"
old_astro=1
mv "$STAGE/server" "$ROOT/dist/server"
new_server=1
mv "$STAGE/client/_astro" "$ROOT/dist/client/_astro"
new_astro=1
systemctl start "$SERVICE"
systemctl is-active --quiet "$SERVICE"
healthy=0
attempt=1
while [ "$attempt" -le 30 ]; do
  if ! systemctl is-active --quiet "$SERVICE"; then
    printf 'service_failed_during_healthcheck\\n' >&2
    systemctl status "$SERVICE" --no-pager -l >&2 || true
    exit 1
  fi
  if command -v curl >/dev/null 2>&1; then
    if curl --fail --silent --show-error --max-time 2 http://127.0.0.1:4321/ >/dev/null 2>&1; then healthy=1; break; fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -O /dev/null http://127.0.0.1:4321/; then healthy=1; break; fi
  else
    if ss -lnt 2>/dev/null | grep -q '127.0.0.1:4321'; then healthy=1; break; fi
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ "$healthy" -ne 1 ]; then
  printf 'healthcheck_timeout=30s\\n' >&2
  systemctl status "$SERVICE" --no-pager -l >&2 || true
  journalctl -u "$SERVICE" -n 40 --no-pager >&2 || true
  exit 1
fi
rm -f "$ARCHIVE"
rmdir "$STAGE/client" "$STAGE" 2>/dev/null || true
printf 'deployment=complete\\n'
printf 'backup=%s\\n' "$BACKUP"
trap - 0
`;
}

async function main() {
  if (!['probe', 'diagnose', 'deploy'].includes(action)) {
    throw new Error('usage: node tools/deploy-dist-safely.mjs [probe|diagnose|deploy]');
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('MIMI_DEPLOY_PORT must be a valid TCP port');
  }

  const password = await loadPassword();
  const client = await connect(password);
  let tempDir = null;
  try {
    const firstCheck = action === 'diagnose' ? await execRemote(client, diagnoseScript) : await execRemote(client, probeScript);
    process.stdout.write(firstCheck.stdout);
    if (firstCheck.stderr) process.stderr.write(firstCheck.stderr);
    if (action !== 'deploy') return;

    const token = deploymentToken();
    const archiveInfo = await createArchive(token);
    tempDir = archiveInfo.tempDir;
    const remoteArchive = `/tmp/mimi-guitar-dist-${token}.tar.gz`;
    const sftp = await openSftp(client);
    await uploadFile(sftp, archiveInfo.archive, remoteArchive);
    const deployed = await execRemote(client, deployScript(token));
    process.stdout.write(deployed.stdout);
    if (deployed.stderr) process.stderr.write(deployed.stderr);
  } finally {
    client.end();
    if (tempDir) await rm(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => fail(error?.message || String(error)));
