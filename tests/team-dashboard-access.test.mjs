import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

test('live team dashboards do not depend on password or session routes', async () => {
  const page = await readFile(new URL('../app/team/[teamId]/page.tsx', import.meta.url), 'utf8');
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(page, /getTeamDashboard\(team\.id\)/);
  assert.doesNotMatch(page, /cookie|session|password|\/unlock/i);
  assert.doesNotMatch(reporting, /team-auth|isTeamSessionAuthorized|sessionToken/);
  await assert.rejects(access(new URL('../app/unlock/page.tsx', import.meta.url)));
  await assert.rejects(access(new URL('../app/api/team-session/unlock/route.ts', import.meta.url)));
});
