import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { createTeamSession, hashTeamPassword } from '../lib/team-session.ts';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const NEXT = fileURLToPath(new URL('../node_modules/next/dist/bin/next', import.meta.url));
const PASSWORD = 'route-test-password';
const HASH = await hashTeamPassword(PASSWORD, Buffer.alloc(16, 11));
const SIGNING_KEY = Buffer.alloc(32, 17);

async function availablePort() {
  const probe = createServer();
  await new Promise((resolve, reject) => {
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', resolve);
  });
  const address = probe.address();
  await new Promise((resolve) => probe.close(resolve));
  return address.port;
}

async function startDatabaseProbe() {
  let connections = 0;
  const server = createServer((socket) => {
    connections += 1;
    socket.destroy();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  return {
    server,
    connections: () => connections,
    url: `postgres://probe:probe@127.0.0.1:${address.port}/probe`,
  };
}

async function startApp(overrides = {}) {
  const port = await availablePort();
  const base = `http://localhost:${port}`;
  let output = '';
  const child = spawn(process.execPath, [NEXT, 'start', '-H', 'localhost', '-p', String(port)], {
    cwd: ROOT,
    env: {
      ...process.env,
      NEXT_TELEMETRY_DISABLED: '1',
      TEAM_PASSWORD_HASHES_JSON: JSON.stringify({
        munster: { hash: HASH, sessionVersion: 1 },
      }).replaceAll('$', '\\$'),
      TEAM_SESSION_SIGNING_KEY: SIGNING_KEY.toString('base64url'),
      TEAM_SESSION_TTL_SECONDS: '600',
      TEAM_UNLOCK_RATE_LIMIT_ENFORCED: 'true',
      WEB_READER_DB_URL: 'postgres://invalid:invalid@127.0.0.1:9/invalid',
      ...overrides,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  for (const stream of [child.stdout, child.stderr]) {
    stream.on('data', (chunk) => {
      output = `${output}${chunk}`.slice(-8000);
    });
  }

  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`Next server exited early:\n${output}`);
    try {
      const response = await fetch(base);
      if (response.ok) return { base, child, output: () => output };
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  child.kill('SIGTERM');
  throw new Error(`Next server did not start:\n${output}`);
}

async function stopApp(app) {
  if (app.child.exitCode !== null) return;
  const exited = new Promise((resolve) => app.child.once('exit', resolve));
  app.child.kill('SIGTERM');
  await Promise.race([exited, new Promise((resolve) => setTimeout(resolve, 5_000))]);
  if (app.child.exitCode === null) app.child.kill('SIGKILL');
}

function unlock(base, body, origin = base) {
  return fetch(`${base}/api/team-session/unlock`, {
    method: 'POST',
    redirect: 'manual',
    headers: { 'content-type': 'application/json', origin },
    body: JSON.stringify(body),
  });
}

test('unlock routes fail closed and issue only an exact-team session', async (t) => {
  const database = await startDatabaseProbe();
  const app = await startApp({ WEB_READER_DB_URL: database.url });
  t.after(async () => {
    await stopApp(app);
    await new Promise((resolve) => database.server.close(resolve));
  });

  assert.equal((await unlock(app.base, { teamId: 'munster', password: PASSWORD }, 'https://evil.test')).status, 403);
  assert.equal(
    (await unlock(app.base, { teamId: 'munster', password: 'wrong' })).status,
    401,
    app.output()
  );
  assert.equal((await unlock(app.base, { teamId: 'benetton', password: PASSWORD })).status, 401);

  const unlocked = await unlock(app.base, { teamId: 'munster', password: PASSWORD });
  assert.equal(unlocked.status, 200);
  const setCookie = unlocked.headers.get('set-cookie');
  assert.match(setCookie, /^__Host-urc-team-session=[^;]+;/);
  for (const attribute of ['httponly', 'secure', 'samesite=lax', 'path=/', 'max-age=600']) {
    assert.ok(setCookie.toLowerCase().includes(attribute));
  }
  const cookie = setCookie.split(';', 1)[0];

  const noSession = await fetch(`${app.base}/team/munster`);
  assert.match(await noSession.text(), /Team Access Required/);

  const wrongTeam = await fetch(`${app.base}/team/leinster`, { headers: { cookie } });
  assert.match(await wrongTeam.text(), /Team Access Required/);
  assert.equal(database.connections(), 0);

  const token = cookie.slice(cookie.indexOf('=') + 1);
  const expired = createTeamSession('munster', 1, SIGNING_KEY, 600, 1_000);
  const tampered = `${token.slice(0, -1)}${token.endsWith('A') ? 'B' : 'A'}`;
  for (const invalidToken of [expired, tampered]) {
    const response = await fetch(`${app.base}/team/munster`, {
      headers: { cookie: `__Host-urc-team-session=${invalidToken}` },
    });
    assert.match(await response.text(), /Team Access Required/);
  }

  const sameTeam = await fetch(`${app.base}/team/munster`, { headers: { cookie } });
  assert.match(await sameTeam.text(), /Dashboard Unavailable/);
  assert.equal(
    database.connections(),
    0,
    'the reporting boundary must reject an unapproved database target before opening a socket'
  );

  const logout = await fetch(`${app.base}/api/team-session/logout`, {
    method: 'POST',
    redirect: 'manual',
    headers: { origin: app.base },
  });
  assert.equal(logout.status, 303);
  assert.match(logout.headers.get('set-cookie'), /^__Host-urc-team-session=;/);
  assert.match(logout.headers.get('set-cookie'), /Max-Age=0/);
});

test('unlock fails closed until deployment rate limiting is confirmed', async (t) => {
  const app = await startApp({ TEAM_UNLOCK_RATE_LIMIT_ENFORCED: 'false' });
  t.after(() => stopApp(app));

  assert.equal((await unlock(app.base, { teamId: 'munster', password: PASSWORD })).status, 503);
});
