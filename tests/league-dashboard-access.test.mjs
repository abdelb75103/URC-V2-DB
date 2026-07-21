import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import ts from 'typescript';

const require = createRequire(import.meta.url);

async function loadReportingForFixtureTest() {
  const source = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');
  const pgUrl = pathToFileURL(require.resolve('pg')).href;
  const zodUrl = pathToFileURL(require.resolve('zod')).href;
  const executable = source
    .replace('import "server-only";\n', '')
    .replace('import { Pool } from "pg";', `import pg from "${pgUrl}";\nconst { Pool } = pg;`)
    .replace('import { z } from "zod";', `import { z } from "${zodUrl}";`);
  const javascript = ts.transpileModule(executable, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

async function loadLocationViewForFixtureTest() {
  const source = await readFile(new URL('../lib/location-view.ts', import.meta.url), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

test('league dashboard uses the approved database consumer view and fails closed', async () => {
  const page = await readFile(new URL('../app/urc/page.tsx', import.meta.url), 'utf8');
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(page, /getLeaguePageData\(\)/);
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
  assert.match(reporting, /"injury_profile", "diagnosis"/);
  assert.match(reporting, /getTeamPageData/);
  assert.match(reporting, /getLeaguePageData/);
  assert.match(reporting, /one MVCC snapshot/);
});

test('team comparisons cross the client boundary with display aliases only', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');
  const types = await readFile(new URL('../lib/reporting-types.ts', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const envExample = await readFile(new URL('../.env.example', import.meta.url), 'utf8');

  assert.match(reporting, /comparison_id: `comparison-/);
  assert.match(reporting, /function teamDisplayAliases\(\)/);
  assert.match(reporting, /TEAM_DISPLAY_ALIAS_JSON/);
  assert.match(reporting, /all: overallSettingMetric\(row\.headline, row\.coverage\)/);
  assert.match(reporting, /team_alias: aliases\[internal_team_key\] \?\? `Club \$\{String\(index \+ 1\)\.padStart\(2, "0"\)\}`/);
  const displayAliasFormat = /^Club \d{2}$/;
  assert.match('Club 01', displayAliasFormat);
  assert.doesNotMatch('Club 1', displayAliasFormat);
  assert.match(types, /comparison_id: string;[\s\S]*team_alias: string;/);
  assert.match(types, /team_alias: string;[\s\S]*all: SettingMetricRow \| null;/);
  assert.match(envExample, /TEAM_DISPLAY_ALIAS_JSON=\{\"team-x\":\"Team Z\"\}/);
  assert.doesNotMatch(types, /export type TeamComparisonRow = \{[^}]*team_key:/);
  assert.doesNotMatch(types, /export type TeamComparisonRow = \{[^}]*\bteam:/);
  assert.doesNotMatch(dashboard, /row\.team_key|row\.team\b/);
  assert.doesNotMatch(dashboard, /Team [A-Z]\b/);
  assert.match(dashboard, /row\.team_alias/);
  assert.match(dashboard, /row\.dimension === 'diagnosis'/);
  assert.match(dashboard, /return profiles\.filter\(\(row\) => row\.dimension === 'diagnosis'\)/);
});

test('team comparison overall setting is a validated projection of released headline fields', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  process.env.WEB_READER_DB_URL = 'postgres://fixture';
  globalThis.__urcWebReaderPool = {
    query: async () => ({
      rows: [{
        team_key: 'fixture-team',
        team: 'Fixture Team',
        coverage: { exposure_rows: 1, exposed_players: 1, weeks: 1, hours: 999, distance_km: 0, included_exposure_status: 'included' },
        headline: [
          { key: 'recorded_injuries', label: 'Recorded injuries', value: 14, unit: 'cases', formula: '' },
          { key: 'incidence_per_1000h', label: 'Incidence', value: 7.5, unit: '/1,000 h', numerator: 6, denominator: 800, formula: '' },
          { key: 'severity_mean_days', label: 'Severity', value: 12.5, unit: 'days', formula: '' },
          { key: 'burden_per_1000h', label: 'Burden', value: 93.75, unit: 'days /1,000 h', numerator: 75, formula: '' },
        ],
        setting_metrics: [{ setting: 'match', label: 'Match', time_loss_injuries: 1, days_lost: 2, exposure_hours: 3, incidence_per_1000h: 4, burden_per_1000h: 5, mean_severity_days: 6 }],
      }],
    }),
  };

  try {
    const { getTeamComparisons } = await loadReportingForFixtureTest();
    const [row] = await getTeamComparisons();
    assert.deepEqual(row.all, {
      setting: 'all',
      label: 'All settings',
      time_loss_injuries: 6,
      days_lost: 75,
      exposure_hours: 800,
      incidence_per_1000h: 7.5,
      burden_per_1000h: 93.75,
      mean_severity_days: 12.5,
    });
    assert.ok([row].some((comparison) => comparison.all));
  } finally {
    globalThis.__urcWebReaderPool = undefined;
    if (priorUrl === undefined) delete process.env.WEB_READER_DB_URL;
    else process.env.WEB_READER_DB_URL = priorUrl;
  }
});

test('league and team page metrics include the released overall benchmark', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  process.env.WEB_READER_DB_URL = 'postgres://fixture';
  const coverage = {
    exposure_rows: 1,
    exposed_players: 1,
    weeks: 1,
    hours: 800,
    distance_km: 0,
    included_exposure_status: 'included',
  };
  const headline = [
    { key: 'recorded_injuries', label: 'Recorded injuries', value: 14, unit: 'cases', formula: '' },
    { key: 'time_loss_injuries', label: 'Time-loss injuries', value: 6, unit: 'cases', formula: '' },
    { key: 'incidence_per_1000h', label: 'Incidence', value: 7.5, unit: '/1,000 h', numerator: 6, denominator: 800, formula: '' },
    { key: 'severity_mean_days', label: 'Severity', value: 12.5, unit: 'days', numerator: 75, denominator: 6, formula: '' },
    { key: 'burden_per_1000h', label: 'Burden', value: 93.75, unit: 'days /1,000 h', numerator: 75, denominator: 800, formula: '' },
  ];
  const settingMetrics = [
    { setting: 'match', label: 'Match', time_loss_injuries: 1, days_lost: 2, exposure_hours: 3, incidence_per_1000h: 4, burden_per_1000h: 5, mean_severity_days: 2 },
  ];
  const dashboard = {
    team: 'URC Overall',
    season: '2024-25',
    generated_at: '2026-07-20T00:00:00Z',
    analysis_window: { start: '2024-07-01', end: '2025-06-30', basis: 'season' },
    method: [],
    coverage,
    headline,
    setting_split: [],
    setting_metrics: settingMetrics,
    monthly: [],
    body_locations: [],
    injury_types: [],
    injury_profiles: [],
    severity_distribution: [],
    prior_season: { season: '2023-24', status: 'unavailable', note: '' },
    limitations: [],
  };
  globalThis.__urcWebReaderPool = {
    query: async () => ({
      rows: [{
        dashboard,
        comparisons: [],
      }],
    }),
  };

  try {
    const { getLeaguePageData, getTeamPageData } = await loadReportingForFixtureTest();
    const pageData = await getLeaguePageData();
    assert.deepEqual(pageData.leagueMetrics.map((row) => row.setting), ['all', 'match']);
    assert.equal(pageData.leagueMetrics[0].incidence_per_1000h, 7.5);
    assert.equal(pageData.leagueMetrics[0].burden_per_1000h, 93.75);

    globalThis.__urcWebReaderPool.query = async () => ({
      rows: [{
        dashboard: { ...dashboard, team: 'Fixture Team' },
        comparisons: [],
        league_metrics: { coverage, headline, setting_metrics: settingMetrics },
      }],
    });
    const teamPageData = await getTeamPageData('fixture-team');
    assert.deepEqual(teamPageData.leagueMetrics.map((row) => row.setting), ['all', 'match']);
    assert.equal(teamPageData.leagueMetrics[0].incidence_per_1000h, 7.5);
    assert.equal(teamPageData.leagueMetrics[0].burden_per_1000h, 93.75);
  } finally {
    globalThis.__urcWebReaderPool = undefined;
    if (priorUrl === undefined) delete process.env.WEB_READER_DB_URL;
    else process.env.WEB_READER_DB_URL = priorUrl;
  }
});

test('comparison tab offers Overall when projected overall data exists', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const rows = [{ all: { setting: 'all' } }];

  assert.ok(rows.some((row) => row.all));
  assert.match(dashboard, /\{ value: 'all', label: 'Overall' \}/);
  assert.match(dashboard, /rows\.some\(\(row\) => row\[value\]\)/);
});

test('body map regions keep a reliable touch and pointer hit area', async () => {
  const bodyMap = await readFile(new URL('../components/dashboard/body-map.tsx', import.meta.url), 'utf8');

  assert.match(bodyMap, /pointerEvents:\s*enabled \? 'bounding-box' : 'none'/);
  assert.match(bodyMap, /min-h-11|tabIndex:\s*0/);
});

test('location ranking bars and body regions share one heat scale', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const bodyMap = await readFile(new URL('../components/dashboard/body-map.tsx', import.meta.url), 'utf8');

  assert.match(bodyMap, /export function locationHeatColor/);
  assert.match(bodyMap, /fill=\{locationHeatColor\(value, max\)\}/);
  assert.match(dashboard, /backgroundColor: heatMapColors \? locationHeatColor\(value, max\)/);
});

test('location detail becomes a vertical rail beside a larger desktop body map', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const bodyMap = await readFile(new URL('../components/dashboard/body-map.tsx', import.meta.url), 'utf8');

  assert.match(bodyMap, /max-w-\[390px\][^"\n]*lg:max-w-\[280px\][^"\n]*xl:max-w-\[320px\]/);
  assert.match(dashboard, /xl:grid-cols-\[minmax\(0,1fr\)_10rem\]/);
  assert.match(dashboard, /grid-cols-3[^"\n]*xl:flex[^"\n]*xl:flex-col/);
  assert.match(dashboard, /metric === 'incidence_per_1000h'/);
  assert.match(dashboard, /xl:border-l-primary/);
});

test('location setting filter wires the approved overall, match, and training profile rows', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /const locationProfiles = profiles\.filter\(\(row\) => row\.dimension === 'body_location'\)/);
  assert.match(dashboard, /availableSettings\(locationProfiles, \['all', 'match', 'training'\]\)/);
  assert.match(dashboard, /resolveLocationView\(\{/);
  assert.match(dashboard, /<SettingControl value=\{effectiveSetting\}/);
});

test('location view resolves setting transitions, selection persistence, and hover fallback', async () => {
  const { resolveLocationView } = await loadLocationViewForFixtureTest();
  const row = (setting, code, label, incidence) => ({
    dimension: 'body_location',
    setting,
    code,
    label,
    time_loss_injuries: incidence,
    days_lost: incidence * 10,
    exposure_hours: 1000,
    incidence_per_1000h: incidence,
    burden_per_1000h: incidence * 10,
    mean_severity_days: 10,
  });
  const profiles = [
    row('all', 'thigh', 'Thigh', 9),
    row('all', 'head', 'Head', 8),
    row('match', 'head', 'Head', 7),
    row('match', 'thigh', 'Thigh', 5),
    row('training', 'knee', 'Knee', 3),
    row('training', 'thigh', 'Thigh', 1),
  ];
  const view = (setting, selectedCode, hoveredCode) => resolveLocationView({
    profiles,
    setting,
    metric: 'incidence_per_1000h',
    selectedCode,
    hoveredCode,
  });

  assert.equal(view('all').activeCode, 'thigh');
  assert.equal(view('match').activeCode, 'head');
  assert.equal(view('training').activeCode, 'knee');
  assert.equal(view('match', 'thigh').selected.label, 'Thigh');
  assert.equal(view('match', 'thigh', 'head').activeCode, 'head');
  assert.equal(view('training', 'head', 'head').activeCode, 'knee');
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
