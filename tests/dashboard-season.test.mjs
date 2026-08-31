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

test('dashboard season routing safely falls back to the frozen default', async () => {
  const { resolveDashboardSeason } = await loadDashboardSeason();

  assert.equal(resolveDashboardSeason(undefined), '2024-25');
  assert.equal(resolveDashboardSeason('2023-24'), '2024-25');
  assert.equal(resolveDashboardSeason(['2025-26', '2024-25']), '2024-25');
});

test('season comparison resolves only an approved supported predecessor', async () => {
  const { previousDashboardSeason } = await loadDashboardSeason();

  assert.equal(previousDashboardSeason('2024-25'), null);
  assert.equal(previousDashboardSeason('2025-26'), '2024-25');
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
