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

test('passwords use the strict scrypt format and verify safely', async () => {
  const hash = await hashTeamPassword('correct horse battery staple', Buffer.alloc(16, 7));

  assert.equal(await verifyTeamPassword('correct horse battery staple', hash), true);
  assert.equal(await verifyTeamPassword('wrong password', hash), false);
  assert.deepEqual(
    parseTeamPasswordConfig(JSON.stringify({ munster: { hash, sessionVersion: 2 } })),
    { munster: { hash, sessionVersion: 2 } }
  );
  assert.equal(parseTeamPasswordConfig('{invalid'), undefined);
  await assert.rejects(() => hashTeamPassword('x'.repeat(MAX_PASSWORD_BYTES + 1)), /1-256/);
});

test('sessions are exact-team, expiring, versioned, and tamper-evident', () => {
  const key = Buffer.alloc(32, 1);
  const token = createTeamSession('munster', 4, key, 600, 1_000);
  const tampered = `${token.slice(0, -1)}${token.endsWith('A') ? 'B' : 'A'}`;

  assert.equal(verifyTeamSession(token, 'munster', 4, key, 1_001), true);
  assert.equal(verifyTeamSession(token, 'leinster', 4, key, 1_001), false);
  assert.equal(verifyTeamSession(token, 'munster', 5, key, 1_001), false);
  assert.equal(verifyTeamSession(token, 'munster', 4, key, 1_600), false);
  assert.equal(verifyTeamSession(tampered, 'munster', 4, key, 1_001), false);
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
