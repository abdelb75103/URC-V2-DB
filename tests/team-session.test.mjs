import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  MAX_PASSWORD_BYTES,
  createTeamSession,
  hashTeamPassword,
  isSameOrigin,
  parseSessionTtl,
  parseSigningKey,
  parseTeamPasswordConfig,
  verifyTeamPassword,
  verifyTeamSession,
} from '../lib/team-session.ts';

test('a valid team password verifies and a wrong password does not', async () => {
  const hash = await hashTeamPassword('correct horse battery staple', Buffer.alloc(16, 7));

  assert.equal(await verifyTeamPassword('correct horse battery staple', hash), true);
  assert.equal(await verifyTeamPassword('wrong password', hash), false);
});

test('password hashes use only the strict versioned scrypt format', async () => {
  const hash = await hashTeamPassword('secret', Buffer.alloc(16, 9));
  const config = parseTeamPasswordConfig(
    JSON.stringify({ munster: { hash, sessionVersion: 2 } })
  );

  assert.deepEqual(config, { munster: { hash, sessionVersion: 2 } });
  assert.equal(await verifyTeamPassword('secret', hash.replace('v1', 'v2')), false);
  assert.equal(parseTeamPasswordConfig(JSON.stringify({ munster: { hash, sessionVersion: 2, extra: true } })), undefined);
  assert.equal(parseTeamPasswordConfig('{invalid'), undefined);
});

test('password input is capped before expensive hashing', async () => {
  const tooLong = 'x'.repeat(MAX_PASSWORD_BYTES + 1);
  const hash = await hashTeamPassword('secret', Buffer.alloc(16, 4));

  assert.equal(await verifyTeamPassword(tooLong, hash), false);
  await assert.rejects(() => hashTeamPassword(tooLong), /1-256 UTF-8 bytes/);
});

test('sessions are exact-team scoped, expiring, and session-version scoped', () => {
  const key = Buffer.alloc(32, 1);
  const token = createTeamSession('munster', 4, key, 600, 1_000);

  assert.equal(verifyTeamSession(token, 'munster', 4, key, 1_001), true);
  assert.equal(verifyTeamSession(token, 'leinster', 4, key, 1_001), false);
  assert.equal(verifyTeamSession(token, 'munster', 5, key, 1_001), false);
  assert.equal(verifyTeamSession(token, 'munster', 4, key, 1_600), false);
});

test('tampering or signing-key rotation invalidates a session', () => {
  const key = Buffer.alloc(32, 2);
  const token = createTeamSession('ulster', 1, key, 600, 2_000);
  const tampered = `${token.slice(0, -1)}${token.endsWith('A') ? 'B' : 'A'}`;

  assert.equal(verifyTeamSession(tampered, 'ulster', 1, key, 2_001), false);
  assert.equal(verifyTeamSession(token, 'ulster', 1, Buffer.alloc(32, 3), 2_001), false);
});

test('runtime settings and same-origin checks fail closed', () => {
  const encodedKey = Buffer.alloc(32, 8).toString('base64url');

  assert.deepEqual(parseSigningKey(encodedKey), Buffer.alloc(32, 8));
  assert.equal(parseSigningKey('short'), undefined);
  assert.equal(parseSessionTtl('3600'), 3600);
  assert.equal(parseSessionTtl('299'), undefined);
  assert.equal(isSameOrigin('https://example.test/api/unlock', 'https://example.test'), true);
  assert.equal(isSameOrigin('https://example.test/api/unlock', 'https://evil.test'), false);
  assert.equal(isSameOrigin('https://example.test/api/unlock', null), false);
});
