import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function loadDashboardSeason() {
  const source = await readFile(new URL('../lib/dashboard-season.ts', import.meta.url), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

test('dashboard season routing accepts only the two supported seasons', async () => {
  const { resolveDashboardSeason, SUPPORTED_DASHBOARD_SEASONS } = await loadDashboardSeason();

  assert.deepEqual(SUPPORTED_DASHBOARD_SEASONS, ['2024-25', '2025-26']);
  assert.equal(resolveDashboardSeason('2024-25'), '2024-25');
  assert.equal(resolveDashboardSeason('2025-26'), '2025-26');
});

test('dashboard season routing defaults to the current season', async () => {
  const { resolveDashboardSeason } = await loadDashboardSeason();

  assert.equal(resolveDashboardSeason(undefined), '2025-26');
  assert.equal(resolveDashboardSeason('2023-24'), '2025-26');
  assert.equal(resolveDashboardSeason(['2025-26', '2024-25']), '2025-26');
});

test('season comparison resolves only an approved supported predecessor', async () => {
  const { previousDashboardSeason } = await loadDashboardSeason();

  assert.equal(previousDashboardSeason('2024-25'), null);
  assert.equal(previousDashboardSeason('2025-26'), '2024-25');
});

test('report comparison resolves the other supported season in either direction', async () => {
  const { comparisonDashboardSeason } = await loadDashboardSeason();

  assert.equal(comparisonDashboardSeason('2024-25'), '2025-26');
  assert.equal(comparisonDashboardSeason('2025-26'), '2024-25');
});

test('league and team routes resolve the query season before loading reporting data', async () => {
  const [leaguePage, teamPage] = await Promise.all([
    readFile(new URL('../app/urc/page.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../app/team/[teamId]/page.tsx', import.meta.url), 'utf8'),
  ]);

  assert.match(leaguePage, /resolveDashboardSeason\(seasonParameter\)/);
  assert.match(leaguePage, /getLeaguePageData\(season\)/);
  assert.match(teamPage, /resolveDashboardSeason\(seasonParameter\)/);
  assert.match(teamPage, /getTeamPageData\(team\.id, season\)/);
});

test('the shared dashboard renders an accessible season selector on the current route', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /aria-label="Choose season"/);
  assert.match(dashboard, /SUPPORTED_DASHBOARD_SEASONS\.map/);
  assert.match(dashboard, /href=\{`\$\{seasonPath\}\?season=\$\{option\}\$\{tabParameter\}`\}/);
});

test('team, league and season links give native link-local pending feedback', async () => {
  const [dashboard, teamTile, status] = await Promise.all([
    readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../components/team-tile.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../components/link-pending-status.tsx', import.meta.url), 'utf8'),
  ]);

  assert.match(status, /useLinkStatus\(\)/);
  assert.match(status, /role="status" aria-live="polite"/);
  assert.match(dashboard, /<LinkPendingStatus[\s\S]*Loading \$\{option\} season/);
  assert.match(dashboard, /aria-current=\{season === option \? 'page' : undefined\}/);
  assert.doesNotMatch(dashboard, /useOptimistic|useTransition|router\.push/);
  assert.match(teamTile, /<LinkPendingStatus[\s\S]*Loading \$\{team\.name\} dashboard/);
});
