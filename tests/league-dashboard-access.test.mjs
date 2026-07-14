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

test('team dashboard reads the v2 approved-build projection', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(reporting, /reporting\.latest_team_dashboard_v2/);
  assert.match(reporting, /setting_metrics/);
  assert.match(reporting, /injury_profiles/);
});

test('body map regions keep a reliable touch and pointer hit area', async () => {
  const bodyMap = await readFile(new URL('../components/dashboard/body-map.tsx', import.meta.url), 'utf8');

  assert.match(bodyMap, /pointerEvents:\s*enabled \? 'bounding-box' : 'none'/);
  assert.match(bodyMap, /min-h-11|tabIndex:\s*0/);
});

test('impact chart formats floating point axis ticks for presentation', async () => {
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.match(charts, /function formatAxisTick/);
  assert.equal((charts.match(/tickFormatter=\{formatAxisTick\}/g) ?? []).length, 2);
  assert.doesNotMatch(charts, /unit=" \/1,000h"|unit=" days"/);
});
