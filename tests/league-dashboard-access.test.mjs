import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('league dashboard uses the approved database consumer view and fails closed', async () => {
  const page = await readFile(new URL('../app/urc/page.tsx', import.meta.url), 'utf8');
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(page, /getLeagueDashboard\(\)/);
  assert.match(page, /force-dynamic/);
  assert.match(page, /Dashboard unavailable/);
  assert.doesNotMatch(page, /content\/reporting|_dashboard_2024-25\.json/);

  assert.match(reporting, /reporting\.latest_league_dashboard_v2/);
  assert.match(reporting, /where season = \$1/);
  assert.match(reporting, /expected one league dashboard row/);
  assert.doesNotMatch(reporting, /reduce\(|incidence.*\/.*hours|burden.*\/.*hours/i);
});

test('published league dashboard is unlocked on the homepage', async () => {
  const home = await readFile(new URL('../app/page.tsx', import.meta.url), 'utf8');

  assert.match(home, /name: 'URC Overall'[\s\S]*status: 'live' as const/);
  assert.match(home, /href="\/urc"/);
});

test('team dashboard reads the v2 approved-build projection', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(reporting, /reporting\.latest_team_dashboard_v2/);
  assert.match(reporting, /setting_metrics/);
  assert.match(reporting, /injury_profiles/);
});

test('team comparisons cross the client boundary with display aliases only', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');
  const types = await readFile(new URL('../lib/reporting-types.ts', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(reporting, /comparison_id: `comparison-/);
  assert.match(reporting, /team_alias: `Club \$\{String\(index \+ 1\)\.padStart\(2, "0"\)\}`/);
  const displayAliasFormat = /^Club \d{2}$/;
  assert.match('Club 01', displayAliasFormat);
  assert.doesNotMatch('Club 1', displayAliasFormat);
  assert.doesNotMatch(reporting, /Team \$\{String\.fromCharCode|Team [A-Z]\b/);
  assert.match(types, /comparison_id: string;[\s\S]*team_alias: string;/);
  assert.doesNotMatch(types, /export type TeamComparisonRow = \{[^}]*team_key:/);
  assert.doesNotMatch(types, /export type TeamComparisonRow = \{[^}]*\bteam:/);
  assert.doesNotMatch(dashboard, /row\.team_key|row\.team\b/);
  assert.doesNotMatch(dashboard, /Team [A-Z]\b/);
  assert.match(dashboard, /row\.team_alias/);
});

test('body map regions keep a reliable touch and pointer hit area', async () => {
  const bodyMap = await readFile(new URL('../components/dashboard/body-map.tsx', import.meta.url), 'utf8');

  assert.match(bodyMap, /pointerEvents:\s*enabled \? 'bounding-box' : 'none'/);
  assert.match(bodyMap, /min-h-11|tabIndex:\s*0/);
});

test('impact chart formats floating point axis ticks for presentation', async () => {
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.match(charts, /function formatAxisTick/);
  assert.ok((charts.match(/tickFormatter=\{formatAxisTick\}/g) ?? []).length >= 3);
  assert.doesNotMatch(charts, /unit=" \/1,000h"|unit=" days"/);
});

test('monthly production fallback never fabricates a duplicate recorded-case series', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.doesNotMatch(dashboard, /recorded_injuries:\s*row\.recorded_injuries\s*\?\?\s*row\.time_loss_injuries/);
  assert.match(charts, /const hasRecordedCases = data\.every/);
  assert.match(charts, /\{hasRecordedCases && <Area[\s\S]*?dataKey="recorded_injuries"/);
  assert.match(charts, /hasRecordedCases \? \[[\s\S]*?Recorded injury cases[\s\S]*?\] : \[[\s\S]*?Time-loss cases/);
});

test('exposure values use a dedicated one-decimal formatter', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /function fmtHours[\s\S]*?maximumFractionDigits: 1,[\s\S]*?minimumFractionDigits: 1/);
  assert.match(charts, /function hours[\s\S]*?maximumFractionDigits: 1,[\s\S]*?minimumFractionDigits: 1/);
  assert.doesNotMatch(dashboard, /fmt\([^)]*exposure_hours, 0\)/);
  assert.doesNotMatch(charts, /count\(row\.exposure_hours\)/);
});
