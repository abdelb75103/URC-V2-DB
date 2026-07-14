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

function stopDatabaseProbe(probe) {
  return new Promise((resolve) => probe.server.close(resolve));
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
      }),
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
  await Promise.race([
    exited,
    new Promise((resolve) => setTimeout(resolve, 5_000)),
  ]);
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

test('production shell serves the compiled global Tailwind stylesheet', async (t) => {
  const app = await startApp();
  t.after(() => stopApp(app));

  const html = await (await fetch(app.base)).text();
  const cssPaths = [...html.matchAll(/href="([^"]+\.css[^"]*)"/g)].map((match) => match[1]);
  assert.ok(cssPaths.length > 0, 'page must link a compiled stylesheet');
  const css = (await Promise.all(cssPaths.map(async (path) => (await fetch(new URL(path, app.base))).text()))).join('\n');
  assert.match(css, /\.flex\{display:flex\}/);
  assert.match(css, /radial-gradient\(circle at top/);
});

test('unlock routes fail closed and issue only a secure team-scoped session', async (t) => {
  const database = await startDatabaseProbe();
  const app = await startApp({ WEB_READER_DB_URL: database.url });
  t.after(async () => {
    await stopApp(app);
    await stopDatabaseProbe(database);
  });

  assert.equal((await unlock(app.base, { teamId: 'munster', password: PASSWORD }, 'https://evil.test')).status, 403);
  assert.equal((await unlock(app.base, { teamId: 'munster' })).status, 400);
  assert.equal((await unlock(app.base, { teamId: 'munster', password: 'wrong' })).status, 401);
  assert.equal((await unlock(app.base, { teamId: 'benetton', password: PASSWORD })).status, 401);

  const unlocked = await unlock(app.base, { teamId: 'munster', password: PASSWORD });
  assert.equal(unlocked.status, 200);
  const setCookie = unlocked.headers.get('set-cookie');
  assert.match(setCookie, /^__Host-urc-team-session=[^;]+;/);
  const cookieAttributes = setCookie.toLowerCase();
  for (const attribute of ['httponly', 'secure', 'samesite=lax', 'path=/', 'max-age=600']) {
    assert.ok(cookieAttributes.includes(attribute), `session cookie must include ${attribute}`);
  }
  const cookie = setCookie.split(';', 1)[0];

  const noSession = await fetch(`${app.base}/team/munster`);
  assert.equal(noSession.status, 200);
  assert.match(await noSession.text(), /Password required/);

  const token = cookie.slice(cookie.indexOf('=') + 1);
  const tamperedToken = `${token.slice(0, -1)}${token.endsWith('A') ? 'B' : 'A'}`;
  const expiredToken = createTeamSession('munster', 1, SIGNING_KEY, 600, 1_000);
  for (const invalidCookie of [
    `${cookie.split('=', 1)[0]}=${tamperedToken}`,
    `${cookie.split('=', 1)[0]}=${expiredToken}`,
  ]) {
    const response = await fetch(`${app.base}/team/munster`, { headers: { cookie: invalidCookie } });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /Password required/);
  }

  const wrongTeam = await fetch(`${app.base}/team/leinster`, { headers: { cookie } });
  assert.equal(wrongTeam.status, 200);
  assert.match(await wrongTeam.text(), /Password required/);
  assert.equal(database.connections(), 0, 'invalid and wrong-team sessions must not reach Postgres');

  const sameTeam = await fetch(`${app.base}/team/munster`, { headers: { cookie } });
  assert.equal(sameTeam.status, 200);
  assert.match(await sameTeam.text(), /Password required/);
  assert.equal(database.connections(), 1, 'a valid same-team session must cross the database boundary');

  const rejectedLogout = await fetch(`${app.base}/api/team-session/logout`, {
    method: 'POST',
    redirect: 'manual',
    headers: { origin: 'https://evil.test' },
  });
  assert.equal(rejectedLogout.status, 403);

  const logout = await fetch(`${app.base}/api/team-session/logout`, {
    method: 'POST',
    redirect: 'manual',
    headers: { origin: app.base },
  });
  assert.equal(logout.status, 303);
  assert.equal(logout.headers.get('location'), `${app.base}/`);
  assert.match(logout.headers.get('set-cookie'), /^__Host-urc-team-session=;/);
  assert.match(logout.headers.get('set-cookie'), /Max-Age=0/);
});

test('unlock endpoint returns 503 when the shared rate-limit gate is not confirmed', async (t) => {
  const app = await startApp({ TEAM_UNLOCK_RATE_LIMIT_ENFORCED: 'false' });
  t.after(() => stopApp(app));

  assert.equal((await unlock(app.base, { teamId: 'munster', password: PASSWORD })).status, 503);
});
