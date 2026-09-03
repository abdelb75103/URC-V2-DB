import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

test('team comparison renders the already-loaded chart without a separate loading placeholder', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /import \{ ComparisonScatterChart, type ComparisonScatterRow \} from '@\/components\/dashboard\/charts'/);
  assert.doesNotMatch(dashboard, /const ComparisonScatterChart = dynamic/);
  assert.match(dashboard, /<ComparisonScatterChart\s+rows=\{scatterRows\}/);
});

test('live team dashboards do not depend on password or session routes', async () => {
  const page = await readFile(new URL('../app/team/[teamId]/page.tsx', import.meta.url), 'utf8');
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(page, /getTeamPageData\(team\.id, season\)/);
  assert.doesNotMatch(page, /cookie|session|password|\/unlock/i);
  assert.doesNotMatch(reporting, /team-auth|isTeamSessionAuthorized|sessionToken/);
  assert.match(reporting, /latest_dashboard_cache_token_v2/);
  assert.match(reporting, /loadStrictlyCachedDashboardPayload/);
  assert.doesNotMatch(reporting, /unstable_cache/);
  await assert.rejects(access(new URL('../app/unlock/page.tsx', import.meta.url)));
  await assert.rejects(access(new URL('../app/api/team-session/unlock/route.ts', import.meta.url)));
});
