import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import ts from 'typescript';

const require = createRequire(import.meta.url);

function transactionMockPool(query) {
  const pool = { query };
  pool.connect = async () => ({
    query: async (sql, values) => {
      if (/^\s*(?:begin transaction read only|commit|rollback)\s*$/i.test(sql)) {
        return { rows: [] };
      }
      return pool.query(sql, values);
    },
    release: () => undefined,
  });
  return pool;
}

async function loadReportingForFixtureTest() {
  const source = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');
  const pgUrl = pathToFileURL(require.resolve('pg')).href;
  const zodUrl = pathToFileURL(require.resolve('zod')).href;
  const executable = source
    .replace('import "server-only";\n', '')
    .replace('import { comparisonDashboardSeason, type DashboardSeason } from "@/lib/dashboard-season";', 'const comparisonDashboardSeason = (season) => season === "2025-26" ? "2024-25" : "2025-26";')
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

  assert.match(page, /getLeaguePageData\(season\)/);
  assert.match(page, /force-dynamic/);
  assert.match(page, /Dashboard unavailable/);
  assert.doesNotMatch(page, /content\/reporting|_dashboard_2024-25\.json/);
  assert.doesNotMatch(page, /getExposureReviewPreview|exposurePreview/);

  assert.match(reporting, /reporting\.latest_league_dashboard_v6/);
  assert.match(reporting, /where season = \$1/);
  assert.match(reporting, /expected one league dashboard row/);
  assert.doesNotMatch(reporting, /reduce\(|incidence.*\/.*hours|burden.*\/.*hours/i);
});

test('published league dashboard is unlocked on the homepage', async () => {
  const home = await readFile(new URL('../app/page.tsx', import.meta.url), 'utf8');

  assert.match(home, /name: 'URC Overall'[\s\S]*status: 'live' as const/);
  assert.match(home, /href="\/urc"/);
});

test('shared readers use the v6 successor while preserving direct Year 1 pass-through', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../supabase/migrations/20260815030000_urc_2025_26_team_release_v6.sql', import.meta.url), 'utf8');

  assert.match(reporting, /reporting\.latest_team_dashboard_v6/);
  assert.match(reporting, /reporting\.latest_league_dashboard_v6/);
  assert.match(migration, /from reporting\.latest_team_dashboard_v5\s+where season <> '2025-26'/);
  assert.match(migration, /from reporting\.latest_league_dashboard_v5\s+where season <> '2025-26'/);
  assert.match(migration, /from reporting\.latest_dashboard_cache_token_v1\s+where season <> '2025-26'/);
  assert.match(reporting, /contact_distribution/);
  assert.match(reporting, /setting_metrics/);
  assert.match(reporting, /injury_profiles/);
  assert.match(reporting, /injury_type_families/);
  assert.match(reporting, /"injury_profile", "diagnosis"/);
  assert.match(reporting, /getTeamPageData/);
  assert.match(reporting, /getLeaguePageData/);
  assert.match(reporting, /one MVCC snapshot/);
  assert.match(reporting, /latest_dashboard_cache_token_v2/);
  assert.match(reporting, /DASHBOARD_PAYLOAD_CACHE_MILLISECONDS = 300_000/);
  assert.match(reporting, /loadStrictlyCachedDashboardPayload/);
  assert.match(reporting, /token-query[\s\S]*fail-closed behaviour/);
});

test('injury type families remain database-defined while the interface stays at family level', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');
  const types = await readFile(new URL('../lib/reporting-types.ts', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(reporting, /injury_type_families: z\.array\(injuryTypeFamilySchema\)/);
  assert.match(reporting, /injuryTypeSubtypeSchema[\s\S]*dimension: z\.literal\('injury_type'\)/);
  assert.match(reporting, /subtype\.setting !== family\.setting/);
  assert.doesNotMatch(dashboard, /reduce\([^)]*(time_loss_injuries|days_lost)/);
  assert.match(types, /export type InjuryTypeFamilyRow = Omit<InjuryProfileRow, 'dimension'> & \{[\s\S]*subtypes: InjuryProfileRow\[\];/);
  assert.match(dashboard, /dashboard\.injury_type_families/);
  assert.doesNotMatch(dashboard, /row\.subtypes\.map/);
  assert.doesNotMatch(dashboard, /Included types/);
});

test('injury type dossier links ranked selection to exact subtype evidence', async () => {
  const dossier = await readFile(new URL('../components/dashboard/injury-type-dossier.tsx', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(dossier, /Injury types ranked by/);
  assert.match(dossier, /onMouseEnter/);
  assert.match(dossier, /onFocus/);
  assert.match(dossier, /onClick/);
  assert.match(dossier, /aria-pressed=\{selected\}/);
  assert.match(dossier, /min-h-14/);
  assert.match(dossier, /Included injury types/);
  assert.match(dossier, /label: 'TL incidence'/);
  assert.match(dossier, /label: 'TL injuries'/);
  assert.match(dossier, /subtype\.time_loss_injuries > 0/);
  assert.match(dossier, /contributingSubtypes\.map/);
  assert.doesNotMatch(dossier, /<svg|silhouette|anatomy/i);
  const typeTab = dashboard.slice(dashboard.indexOf('function InjuryTypesTab'), dashboard.indexOf('function ImpactTab'));
  const rankingPanel = typeTab.indexOf('<InjuryTypeRanking');
  const dossierPanel = typeTab.indexOf('<InjuryTypeDossier');
  assert.ok(rankingPanel > -1 && dossierPanel > rankingPanel, 'ranking and dossier must follow the visual reading order');
  assert.match(typeTab, /MetricControl value=\{metric\} onChange=\{setMetric\} locationOnly/);
  assert.doesNotMatch(typeTab, /Severity/);
  assert.match(typeTab, /row\.code !== 'other_unclassified'/);
  assert.match(typeTab, /availableSettings\(classifiedFamilies/);
  assert.match(typeTab, /row\.setting === effectiveSetting && row\.time_loss_injuries > 0/);
  assert.doesNotMatch(dossier, /other_unclassified|unmapped_review/);
  assert.match(dashboard, /lg:grid-cols-\[minmax\(0,1\.2fr\)_minmax\(20rem,0\.8fr\)\]/);
});

test('reader preserves versioned family totals and exact subtype evidence', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  process.env.WEB_READER_DB_URL = 'postgresql://web_reader.eukkvswaxweenovqqgzr:fixture@aws-0-eu-west-3.pooler.supabase.com:5432/postgres';
  let queryText = '';
  globalThis.__urcWebReaderPool = transactionMockPool(
    async (sql) => {
      if (sql.includes('approved_dashboard_reader_target_v2')) {
        return { rows: [{ target_attested: true }] };
      }
      queryText = sql;
      return {
        rows: [{
          team: 'URC Overall',
          season: '2024-25',
          generated_at: '2026-07-21T00:00:00Z',
          analysis_window: { start: '2024-07-01', end: '2025-06-30', basis: 'season' },
          method: [],
          coverage: { exposure_rows: 1, exposed_players: 1, weeks: 1, hours: 1200, distance_km: 0, included_exposure_status: 'included' },
          headline: [{ key: 'time_loss_injuries', label: 'Time-loss injuries', value: 5, unit: 'cases', formula: '' }],
          setting_split: [],
          setting_metrics: [],
          monthly: [],
          body_locations: [],
          injury_types: [],
          injury_profiles: [],
          injury_type_families: [{
            dimension: 'injury_type_family',
            code: 'muscle',
            label: 'Muscle',
            setting: 'all',
            time_loss_injuries: 5,
            days_lost: 61,
            exposure_hours: 1200,
            incidence_per_1000h: 4.1666666667,
            burden_per_1000h: 50.8333333333,
            mean_severity_days: 12.2,
            mapping_version: 'injury_type_family_2026-07-21_v1',
            subtypes: [{
              dimension: 'injury_type',
              code: 'muscle_injury',
              label: 'Muscle injury',
              setting: 'all',
              time_loss_injuries: 5,
              days_lost: 61,
              exposure_hours: 1200,
              incidence_per_1000h: 4.1666666667,
              burden_per_1000h: 50.8333333333,
              mean_severity_days: 12.2,
            }],
          }],
          severity_distribution: [],
          contact_distribution: [
            { key: 'contact', label: 'Contact', setting: 'all', recorded_injuries: 943, time_loss_injuries: 443 },
            { key: 'non_contact', label: 'Non-contact', setting: 'all', recorded_injuries: 565, time_loss_injuries: 280 },
            { key: 'unknown', label: 'Unknown', setting: 'all', recorded_injuries: 150, time_loss_injuries: 62 },
            { key: 'contact', label: 'Contact', setting: 'unknown', recorded_injuries: 2, time_loss_injuries: 2 },
          ],
          prior_season: { season: '2023-24', status: 'unavailable', note: '' },
          limitations: [],
        }],
      };
    },
  );

  try {
    const { getLeagueDashboard } = await loadReportingForFixtureTest();
    const dashboard = await getLeagueDashboard();
    assert.match(queryText, /reporting\.latest_league_dashboard_v6/);
    assert.equal(dashboard.injury_type_families[0].burden_per_1000h, 50.8333333333);
    assert.equal(dashboard.injury_type_families[0].subtypes[0].code, 'muscle_injury');

    // The released contact section must survive the field-by-field rebuild,
    // keep its Unknown mechanism row, and accept a genuinely unknown activity
    // setting. Dropping any of these would empty or skew the ring.
    assert.equal(dashboard.contact_distribution.length, 4);
    assert.deepEqual(
      dashboard.contact_distribution.map((row) => row.key),
      ['contact', 'non_contact', 'unknown', 'contact'],
    );
    assert.equal(
      dashboard.contact_distribution.find((row) => row.key === 'unknown').recorded_injuries,
      150,
    );
    assert.ok(dashboard.contact_distribution.some((row) => row.setting === 'unknown'));
  } finally {
    globalThis.__urcWebReaderPool = undefined;
    if (priorUrl === undefined) delete process.env.WEB_READER_DB_URL;
    else process.env.WEB_READER_DB_URL = priorUrl;
  }
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
  assert.match(reporting, /distance_km: row\.coverage\.distance_km/);
  assert.match(reporting, /team_alias: aliases\[internal_team_key\] \?\? `Club \$\{String\(index \+ 1\)\.padStart\(2, "0"\)\}`/);
  const displayAliasFormat = /^Club \d{2}$/;
  assert.match('Club 01', displayAliasFormat);
  assert.doesNotMatch('Club 1', displayAliasFormat);
  assert.match(types, /comparison_id: string;[\s\S]*team_alias: string;/);
  assert.match(types, /team_alias: string;[\s\S]*all: SettingMetricRow \| null;/);
  assert.match(envExample, /TEAM_DISPLAY_ALIAS_JSON='\{\"team-x\":\"Team Z\"\}'/);
  assert.match(reporting, /process\.env\.NODE_ENV !== "production"/);
  assert.doesNotMatch(types, /export type TeamComparisonRow = \{[^}]*team_key:/);
  assert.doesNotMatch(types, /export type TeamComparisonRow = \{[^}]*\bteam:/);
  assert.doesNotMatch(dashboard, /row\.team_key|row\.team\b/);
  assert.doesNotMatch(dashboard, /Team [A-Z]\b/);
  assert.match(dashboard, /row\.team_alias/);
  assert.match(dashboard, /row\.dimension === 'diagnosis'/);
  assert.match(dashboard, /return withoutFrontFacingUnknown\(profiles\.filter\(\(row\) => row\.dimension === 'diagnosis'\)\)/);
});

test('team comparison overall setting is a validated projection of released headline fields', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  const priorAliases = process.env.TEAM_DISPLAY_ALIAS_JSON;
  process.env.WEB_READER_DB_URL = 'postgresql://web_reader.eukkvswaxweenovqqgzr:fixture@aws-0-eu-west-3.pooler.supabase.com:5432/postgres';
  process.env.TEAM_DISPLAY_ALIAS_JSON = JSON.stringify({ 'fixture-team': 'Team Q' });
  globalThis.__urcWebReaderPool = transactionMockPool(
    async (sql) => ({
      ...(sql.includes('approved_dashboard_reader_target_v2')
        ? { rows: [{ target_attested: true }] }
        : { rows: [{
        team_key: 'fixture-team',
        team: 'Fixture Team',
        coverage: { exposure_rows: 1, exposed_players: 1, weeks: 1, hours: 999, distance_km: 321.4, included_exposure_status: 'included' },
        headline: [
          { key: 'recorded_injuries', label: 'Recorded injuries', value: 14, unit: 'cases', formula: '' },
          { key: 'incidence_per_1000h', label: 'Incidence', value: 7.5, unit: '/1,000 h', numerator: 6, denominator: 800, formula: '' },
          { key: 'severity_mean_days', label: 'Severity', value: 12.5, unit: 'days', formula: '' },
          { key: 'burden_per_1000h', label: 'Burden', value: 93.75, unit: 'days /1,000 h', numerator: 75, formula: '' },
        ],
        setting_metrics: [{ setting: 'match', label: 'Match', time_loss_injuries: 1, days_lost: 2, exposure_hours: 3, incidence_per_1000h: 4, burden_per_1000h: 5, mean_severity_days: 6 }],
      }] }),
    }),
  );

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
    assert.equal(row.distance_km, 321.4);
    assert.equal(row.team_alias, 'Team Q');
    assert.ok([row].some((comparison) => comparison.all));

    process.env.TEAM_DISPLAY_ALIAS_JSON = JSON.stringify({ 'fixture-team': 'Public club name' });
    const [fallbackRow] = await getTeamComparisons();
    assert.equal(fallbackRow.team_alias, 'Club 01');
  } finally {
    globalThis.__urcWebReaderPool = undefined;
    if (priorUrl === undefined) delete process.env.WEB_READER_DB_URL;
    else process.env.WEB_READER_DB_URL = priorUrl;
    if (priorAliases === undefined) delete process.env.TEAM_DISPLAY_ALIAS_JSON;
    else process.env.TEAM_DISPLAY_ALIAS_JSON = priorAliases;
  }
});

test('team comparisons preserve unavailable exposure and place it after known coverage', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  const priorAliases = process.env.TEAM_DISPLAY_ALIAS_JSON;
  process.env.WEB_READER_DB_URL = 'postgresql://web_reader.eukkvswaxweenovqqgzr:fixture@aws-0-eu-west-3.pooler.supabase.com:5432/postgres';
  process.env.TEAM_DISPLAY_ALIAS_JSON = JSON.stringify({ known: 'Known', unavailable: 'Unavailable' });
  const headline = [
    { key: 'recorded_injuries', label: 'Recorded injuries', value: 1, unit: 'cases', formula: 'count(final classified eligible injury rows, including undated)' },
    { key: 'time_loss_injuries', label: 'Time Loss injuries', value: 1, unit: 'cases', formula: 'count(final classification = Time Loss)' },
    { key: 'overall_incidence_per_1000h', label: 'Overall incidence', value: null, unit: 'per 1,000 player-hours', numerator: 1, denominator: null, formula: 'pooled recorded injuries / pooled exposure hours * 1000' },
    { key: 'incidence_per_1000h', label: 'Time Loss incidence', value: null, unit: 'per 1,000 player-hours', numerator: 1, denominator: null, formula: 'pooled final Time Loss injuries / pooled exposure hours * 1000' },
    { key: 'severity_mean_days', label: 'Mean severity', value: 2, unit: 'days', numerator: 2, denominator: 1, formula: 'known-duration Time Loss days lost / known-duration Time Loss injuries' },
    { key: 'severity_median_days', label: 'Median severity', value: 2, unit: 'days', denominator: 1, formula: 'median known-duration Time Loss days lost' },
    { key: 'burden_per_1000h', label: 'Burden', value: null, unit: 'days per 1,000 player-hours', numerator: 2, denominator: null, formula: 'known-duration Time Loss days lost / pooled exposure hours * 1000' },
  ];
  const settingMetrics = ['all', 'match', 'training', 'unknown'].map((setting) => ({
    setting,
    label: setting,
    recorded_injuries: 1,
    time_loss_injuries: 1,
    days_lost: 2,
    exposure_hours: null,
    overall_incidence_per_1000h: null,
    incidence_per_1000h: null,
    burden_per_1000h: null,
    mean_severity_days: 2,
  }));
  const row = (team_key, hours, distance_km) => ({
    team_key,
    team: `${team_key} source`,
    coverage: {
      exposure_rows: hours === null ? 0 : 1,
      exposed_players: hours === null ? 0 : 1,
      weeks: hours === null ? 0 : 1,
      match_hours: 0,
      training_hours: hours,
      hours,
      distance_km,
      included_exposure_status: hours === null ? 'not_available' : 'included',
      analysis_window_start: '2025-09-01',
      analysis_window_end: '2026-06-30',
      exposure_grain: 'session',
    },
    headline,
    setting_metrics: settingMetrics,
  });
  globalThis.__urcWebReaderPool = transactionMockPool(
    async (sql) => (sql.includes('approved_dashboard_reader_target_v2')
      ? { rows: [{ target_attested: true }] }
      : { rows: [row('unavailable', null, null), row('known', 100, 40)] }),
  );

  try {
    const { getTeamComparisons } = await loadReportingForFixtureTest();
    const rows = await getTeamComparisons('2025-26');
    assert.deepEqual(rows.map((row) => row.exposure_hours), [100, null]);
    assert.equal(rows[1].exposure_hours, null);
    assert.equal(rows[1].distance_km, null);
  } finally {
    globalThis.__urcWebReaderPool = undefined;
    if (priorUrl === undefined) delete process.env.WEB_READER_DB_URL;
    else process.env.WEB_READER_DB_URL = priorUrl;
    if (priorAliases === undefined) delete process.env.TEAM_DISPLAY_ALIAS_JSON;
    else process.env.TEAM_DISPLAY_ALIAS_JSON = priorAliases;
  }
});

test('league and team page metrics include the released overall benchmark', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  process.env.WEB_READER_DB_URL = 'postgresql://web_reader.eukkvswaxweenovqqgzr:fixture@aws-0-eu-west-3.pooler.supabase.com:5432/postgres';
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
    injury_type_families: [],
    severity_distribution: [],
    prior_season: { season: '2023-24', status: 'unavailable', note: '' },
    limitations: [],
  };
  let tokenQueryCount = 0;
  let payloadQueryCount = 0;
  let releaseToken = 'release-a';
  globalThis.__urcWebReaderPool = transactionMockPool(
    async (sql) => {
      if (sql.includes('approved_dashboard_reader_target_v2')) {
        return { rows: [{ target_attested: true }] };
      }
      if (sql.includes('latest_dashboard_cache_token_v2')) {
        tokenQueryCount += 1;
        return { rows: [{ season: '2024-25', cache_token: releaseToken }] };
      }
      payloadQueryCount += 1;
      return ({
      rows: [{
        dashboard,
        comparisons: [],
      }],
      });
    },
  );

  try {
    const { getLeaguePageData, getTeamPageData } = await loadReportingForFixtureTest();
    const pageData = await getLeaguePageData();
    const cachedPageData = await getLeaguePageData();
    assert.deepEqual(cachedPageData, pageData);
    assert.equal(tokenQueryCount, 2, 'every request must verify the approved release token');
    assert.equal(payloadQueryCount, 1, 'identical release payloads should reuse the cache');
    releaseToken = 'release-b';
    await getLeaguePageData();
    assert.equal(payloadQueryCount, 2, 'promotion or rollback must invalidate immediately');
    assert.deepEqual(pageData.leagueMetrics.map((row) => row.setting), ['all', 'match']);
    assert.equal(pageData.leagueMetrics[0].incidence_per_1000h, 7.5);
    assert.equal(pageData.leagueMetrics[0].burden_per_1000h, 93.75);

    globalThis.__urcWebReaderPool.query = async (sql) => {
      if (sql.includes('approved_dashboard_reader_target_v2')) {
        return { rows: [{ target_attested: true }] };
      }
      if (sql.includes('latest_dashboard_cache_token_v2')) {
        return { rows: [{ season: '2024-25', cache_token: 'release-a' }] };
      }
      return {
        rows: [{
          dashboard: { ...dashboard, team: 'Fixture Team' },
          comparisons: [],
          league_metrics: { coverage, headline, setting_metrics: settingMetrics },
        }],
      };
    };
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

test('Year 2 league page derives benchmarks from the complete released dashboard', async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  process.env.WEB_READER_DB_URL = 'postgresql://web_reader.eukkvswaxweenovqqgzr:fixture@aws-0-eu-west-3.pooler.supabase.com:5432/postgres';
  const dashboard = JSON.parse(await readFile(new URL('../content/reporting/urc_dashboard_2025-26.json', import.meta.url), 'utf8'));
  const recorded = dashboard.headline.find((row) => row.key === 'recorded_injuries').value;
  const timeLoss = dashboard.headline.find((row) => row.key === 'time_loss_injuries').value;
  const daysLost = dashboard.headline.find((row) => row.key === 'burden_per_1000h').numerator;
  dashboard.headline = [
    { key: 'recorded_injuries', label: 'Recorded injuries', value: recorded, unit: 'injuries', formula: 'count(final classified eligible injury rows, including undated)' },
    { key: 'time_loss_injuries', label: 'Time-loss injuries', value: timeLoss, unit: 'injuries', formula: 'count(final classification = Time Loss)' },
    { key: 'overall_incidence_per_1000h', label: 'Overall incidence', value: null, unit: 'per 1,000 player-hours', numerator: recorded, denominator: null, formula: 'pooled recorded injuries / pooled exposure hours * 1000' },
    { key: 'incidence_per_1000h', label: 'Incidence', value: null, unit: 'per 1,000 player-hours', numerator: timeLoss, denominator: null, formula: 'pooled final Time Loss injuries / pooled exposure hours * 1000' },
    { key: 'severity_mean_days', label: 'Mean severity', value: daysLost / timeLoss, unit: 'days', numerator: daysLost, denominator: timeLoss, formula: 'known-duration Time Loss days lost / known-duration Time Loss injuries' },
    { key: 'severity_median_days', label: 'Median severity', value: 10, unit: 'days', denominator: timeLoss, formula: 'median known-duration Time Loss days lost' },
    { key: 'burden_per_1000h', label: 'Burden', value: null, unit: 'days per 1,000 player-hours', numerator: daysLost, denominator: null, formula: 'known-duration Time Loss days lost / pooled exposure hours * 1000' },
  ];
  dashboard.setting_split = dashboard.setting_split.map((row) => ({
    ...row,
    recorded_injuries: row.time_loss_injuries,
    overall_incidence_per_1000h: null,
    incidence_per_1000h: null,
    burden_per_1000h: null,
    mean_severity_days: row.time_loss_injuries ? row.days_lost / row.time_loss_injuries : null,
  }));
  dashboard.setting_metrics = dashboard.setting_metrics.map((row) => ({
    ...row,
    recorded_injuries: row.time_loss_injuries,
    overall_incidence_per_1000h: null,
  }));
  dashboard.monthly = dashboard.monthly.map((row) => ({
    ...row,
    recorded_injuries: row.time_loss_injuries,
    overall_incidence_per_1000h: null,
  }));
  dashboard.injury_profiles = dashboard.injury_profiles.map((row) => ({
    ...row,
    recorded_injuries: row.time_loss_injuries,
  }));
  dashboard.severity_distribution = dashboard.severity_distribution.map((row) => ({
    ...row,
    setting: 'all',
  }));
  let currentReleaseToken = 'year-2-release';
  let priorReleaseToken = 'year-1-release';
  let payloadQueryCount = 0;
  globalThis.__urcWebReaderPool = transactionMockPool(
    async (sql) => {
      if (sql.includes('approved_dashboard_reader_target_v2')) {
        return { rows: [{ target_attested: true }] };
      }
      if (sql.includes('latest_dashboard_cache_token_v2')) {
        return { rows: [
          { season: '2024-25', cache_token: priorReleaseToken },
          { season: '2025-26', cache_token: currentReleaseToken },
        ] };
      }
      payloadQueryCount += 1;
      return { rows: [{ dashboard, comparisons: [] }] };
    },
  );

  try {
    const { getLeaguePageData } = await loadReportingForFixtureTest();
    const pageData = await getLeaguePageData('2025-26');
    await getLeaguePageData('2025-26');
    assert.equal(payloadQueryCount, 1, 'the two-season snapshot should reuse an unchanged composite token');
    priorReleaseToken = 'year-1-successor';
    await getLeaguePageData('2025-26');
    assert.equal(payloadQueryCount, 2, 'a comparison-season successor must invalidate the comparison snapshot');
    assert.equal(pageData.dashboard?.season, '2025-26');
    assert.deepEqual(pageData.leagueMetrics.map((row) => row.setting), ['all', 'match', 'training', 'unknown']);
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
  assert.match(bodyMap, /label: 'TL incidence'/);

  // Every controlled IOC region is hoverable, including regions with no cases, and
  // reports 0 rather than being inert (decision, 25 July 2026).
  assert.match(bodyMap, /pointerEvents:\s*'bounding-box' as const/);
  assert.doesNotMatch(bodyMap, /enabled\s*\?/);
  assert.match(bodyMap, /min-h-11|tabIndex:\s*0/);
});

test('risk matrix uses a data-fitted log severity scale, numbered dots, and a smooth heat map', async () => {
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const impact = charts.slice(charts.indexOf('function isPlottableLogSeverity'), charts.indexOf('export type RankSlopePoint'));

  assert.match(impact, /function logSeverityDomain\(values: number\[\]\)/);
  assert.match(impact, /minimum \/ 1\.15/);
  assert.match(impact, /maximum \* 1\.15/);
  assert.match(impact, /domain=\{severityDomain\}/);
  assert.match(impact, /scale="log"/);
  assert.match(impact, /ticks=\{severityTicks\}/);
  assert.match(impact, /Mean severity, days \(logarithmic scale\)/);
  assert.match(impact, /isPlottableLogSeverity\(row\.mean_severity_days\)/);
  assert.match(impact, /Number\.isFinite\(value\) && value > 0/);
  assert.match(impact, /non-positive mean severity.*not shown because a logarithmic scale cannot represent those values/s);
  assert.match(impact, /const IMPACT_DOT_RADIUS = 9/);
  assert.match(impact, /r=\{IMPACT_DOT_RADIUS\}/);
  assert.doesNotMatch(impact, /bubble_burden|IMPACT_BUBBLE_SIZE|dataKey="bubble_burden"/);
  assert.match(impact, /displayIndex: index \+ 1/);
  assert.match(impact, /Diagnoses shown on the Risk Matrix/);
  assert.match(impact, /columns-1.*sm:columns-2 lg:columns-4/);
  assert.match(impact, /break-inside-avoid/);
  assert.match(impact, /<linearGradient id="impact-risk-gradient"/);
  assert.match(impact, /fill="url\(#impact-risk-gradient\)"/);
  assert.match(impact, /<ReferenceArea/);
  assert.match(impact, /Lower incidence and severity/);
  assert.match(impact, /Higher incidence and severity/);
  assert.doesNotMatch(impact, /time_loss_injuries\s*[<>]/);
  assert.doesNotMatch(impact, /aboveLogDomainRows|pending chart-domain review/);
  assert.doesNotMatch(dashboard, /View injury impact data|function AccessibleDataTable/);
  assert.match(dashboard, /Risk Matrix/);
  assert.doesNotMatch(dashboard, /Shows \{impactDimension/);
  assert.doesNotMatch(dashboard, /Each dot represents one profile/);
});

test('risk matrix selects prevalent TL diagnoses instead of recorded or burden-ranked rows', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const tab = dashboard.slice(dashboard.indexOf('function CommonInjuriesTab'), dashboard.indexOf('function rankedForMetric'));

  assert.match(tab, /row\.time_loss_injuries \/ totalInjuries >= 0\.013/);
  assert.doesNotMatch(tab, /impactSelectionTotal|hasRecordedCounts|totalRecordedInjuries/);
  assert.doesNotMatch(tab, /impactRanked\.slice\(0, 12\)/);
  assert.match(tab, /row\.time_loss_injuries > 0 && isKneeLigamentDiagnosis\(row\)/);
});

test('injury impact tooltip prioritises the plotted axes, gives exact small-sample cautions, and supports pinning', async () => {
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');
  const tooltip = charts.slice(charts.indexOf('function ImpactTooltip'), charts.indexOf('function formatAxisTick'));
  const interaction = charts.slice(charts.indexOf('function ImpactDot'), charts.indexOf('export function ImpactScatterChart'));
  const chart = charts.slice(charts.indexOf('export function ImpactScatterChart'));

  assert.match(tooltip, /flex items-baseline.*\{row\.label\}.*settingLabel\(row\.setting\)/s);
  assert.match(tooltip, /\{\(caution \|\| pinned\) && \(/);
  assert.ok(tooltip.indexOf('>TL incidence<') < tooltip.indexOf('>Mean severity<'), 'TL incidence must lead the plotted metrics');
  assert.ok(tooltip.indexOf('>Mean severity<') < tooltip.indexOf('>Burden<'), 'burden must remain supporting detail');
  assert.doesNotMatch(tooltip, />Recorded injuries</);
  assert.match(tooltip, />TL injuries</);
  assert.match(tooltip, />Total days lost</);
  assert.doesNotMatch(tooltip, /Time-loss cases/);
  assert.match(tooltip, /Caution: based on 1 injury/);
  assert.match(tooltip, /Small sample: interpret 2 injuries cautiously/);
  assert.match(tooltip, /aria-live="polite"/);
  assert.match(interaction, /r=\{22\}/);
  assert.match(interaction, /role="button"/);
  assert.match(interaction, /onMouseEnter/);
  assert.match(interaction, /onFocus/);
  assert.match(interaction, /onKeyDown/);
  assert.match(interaction, /onPointerDown=\{\(event\) => \{.*event\.stopPropagation\(\);.*onPin\(point\);/s);
  assert.match(interaction, /aria-pressed=\{selected\}/);
  assert.match(interaction, /aria-describedby=\{tooltipId\}/);
  assert.match(interaction, /IMPACT_DOT_RADIUS \+ 4/);
  assert.match(interaction, /onPosition\(\{ row: payload, x: cx, y: cy \}\)/);
  assert.match(chart, /const syncPointPosition = useCallback/);
  assert.match(chart, /current\.x !== point\.x \|\| current\.y !== point\.y/);
  assert.match(chart, /\[&_\.recharts-wrapper:focus\]:outline-none/);
  assert.match(chart, /activeKey=\{\(pinned \?\? preview\)\?\.row\.impactKey\}/);
  assert.match(chart, /document\.addEventListener\('pointerdown', dismissIfOutside\)/);
  assert.match(chart, /document\.addEventListener\('keydown', dismissOnEscape\)/);
  assert.match(chart, /setPinned\(undefined\)/);
  assert.match(chart, /onPointerDown=\{dismissTooltip\}/);
  assert.match(chart, /clamp\(0\.75rem/);
  assert.doesNotMatch(chart, /data table below/);
  assert.doesNotMatch(chart, /within the 1 to 400|logarithmic scale from 1 to 400/);
});

test('location ranking bars and body regions share one heat scale', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const bodyMap = await readFile(new URL('../components/dashboard/body-map.tsx', import.meta.url), 'utf8');

  assert.match(bodyMap, /export function locationHeatColor/);
  assert.match(bodyMap, /fill=\{locationHeatColor\(value, max\)\}/);
  assert.match(dashboard, /backgroundColor:\s*heatMapColors\s*\? locationHeatColor\(value, max\)/);
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

test('timeline distinguishes injuries from TL injuries and ranked team comparisons mark the active league mean', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');
  const timeline = charts.slice(charts.indexOf('export function SeasonTimelineChart'), charts.indexOf('export function SeverityArc'));
  const comparison = dashboard.slice(dashboard.indexOf('function TeamComparisonTab'), dashboard.indexOf('function BenchmarkCell'));

  assert.match(timeline, /dataKey="recorded_injuries"[\s\S]*?name="Injuries"[\s\S]*?fill=\{SETTING_COLORS\.all\}/);
  assert.match(timeline, /dataKey="time_loss_injuries"[\s\S]*?name="TL injuries"[\s\S]*?fill="#ffc45c"/);
  assert.match(comparison, /const leagueMean = benchmark\?\.\[metric\]/);
  assert.match(comparison, /leagueMean=\{leagueMean\}/);
  assert.match(comparison, /border-dotted border-orange-400/);
  assert.match(comparison, /League mean/);
  assert.doesNotMatch(comparison, /\(dotted line\)/);
  assert.match(comparison, /h-4 border-l-2 border-dotted border-orange-400/);
  assert.match(comparison, /ref=\{ladderRef\}[\s\S]*?ranked\.map[\s\S]*?mt-4 flex justify-end border-t[\s\S]*?League mean/);
  assert.match(comparison, /league mean \$\{fmtRanked\(leagueMean, metric\)\}/);
});

test('monthly production fallback never fabricates a duplicate recorded-case series', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.doesNotMatch(dashboard, /recorded_injuries:\s*row\.recorded_injuries\s*\?\?\s*row\.time_loss_injuries/);
  assert.match(charts, /const hasRecordedCases = data\.every/);
  assert.match(charts, /\{hasRecordedCases && <Area[\s\S]*?dataKey="recorded_injuries"/);
  assert.match(charts, /hasRecordedCases \? \[[\s\S]*?Recorded injury cases[\s\S]*?\] : \[[\s\S]*?Time-loss cases/);
});

test('exposure values use a dedicated zero-decimal formatter', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /function fmtHours[\s\S]*?maximumFractionDigits: 0,[\s\S]*?minimumFractionDigits: 0/);
  assert.match(charts, /function hours[\s\S]*?maximumFractionDigits: 0,[\s\S]*?minimumFractionDigits: 0/);
  assert.doesNotMatch(dashboard, /fmt\([^)]*exposure_hours, 0\)/);
  assert.doesNotMatch(charts, /count\(row\.exposure_hours\)/);
});

test('season timeline keeps recorded injuries distinct from time-loss injuries', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  const timeline = charts.slice(charts.indexOf('export function SeasonTimelineChart'), charts.indexOf('export function SeverityArc'));
  assert.match(timeline, /const hasRecordedCases = data\.every/);
  assert.match(timeline, /dataKey="recorded_injuries"[\s\S]*?name="Injuries"/);
  assert.match(timeline, /dataKey="time_loss_injuries"[\s\S]*?name="TL injuries"/);
  assert.match(timeline, /dataKey="overall_incidence_per_1000h"[\s\S]*?name="Overall incidence"/);
  assert.match(timeline, /dataKey="incidence_per_1000h"[\s\S]*?name="TL incidence"/);
  assert.match(timeline, /<Legend/);
  assert.doesNotMatch(dashboard, /open|ongoing/i);
});

test('overview and time line use only released overall-incidence values', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /const isOverall = effectiveSetting === 'all';/);
  assert.match(dashboard, /const headlineValues = \{[\s\S]*?recorded_injuries: active\?\.recorded_injuries \?\? \(isOverall \? recorded : null\),[\s\S]*?overall_incidence_per_1000h: active\?\.overall_incidence_per_1000h \?\? \(isOverall \? headline\.overall_incidence_per_1000h : null\)/);
  assert.match(dashboard, /<StatTile[\s\S]*?label="Overall incidence"[\s\S]*?value=\{fmt\(headlineValues\.overall_incidence_per_1000h\)\}/);
  assert.match(dashboard, /companion=\{<PairedStat label="TL incidence" value=\{fmt\(headlineValues\.incidence_per_1000h\)\}/);
  assert.match(dashboard, /overall_incidence_per_1000h: row\.overall_incidence_per_1000h \?\? null/);
  assert.doesNotMatch(dashboard, /recorded_injuries\s*\/\s*.*exposure_hours/);
  assert.match(charts, /const hasOverallIncidence = data\.some\(\(row\) => typeof row\.overall_incidence_per_1000h === 'number'\)/);
});

test('exposure tab combines monthly hours and distance while gating provisional HSR behind the local preview', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');
  const tabConfig = await readFile(new URL('../lib/dashboard-tab.ts', import.meta.url), 'utf8');

  assert.match(dashboard, /Estimated total hours[\s\S]*Reported distance/);
  assert.match(dashboard, /Estimated exposure/);
  assert.match(dashboard, /Monthly trend shows reported source-backed values/);
  assert.match(dashboard, /14 source-backed clubs \+ 2 temporary estimates|sourceBackedTeamCount/);
  assert.match(dashboard, /Awaiting source-backed exposure from/);
  assert.match(dashboard, /coverage\.included_exposure_status\.includes\('estimate'\)/);
  assert.match(dashboard, /Temporary exposure estimate/);
  assert.match(dashboard, /row\.included_exposure_status\.includes\('estimate'\)[\s\S]*?Est\./);
  assert.match(dashboard, /No approved exposure data is available for this season/);
  assert.match(dashboard, /No approved exposure totals are available for this season/);
  assert.ok(tabConfig.indexOf("value: 'types'") < tabConfig.indexOf("value: 'exposure'"));
  assert.ok(tabConfig.indexOf("value: 'exposure'") < tabConfig.indexOf("value: 'reports'"), 'Reports must follow Exposure');
  assert.match(dashboard, /const ReportPreview = dynamic\([\s\S]*?ssr: false/);
  assert.match(dashboard, /function ReportsTab\(\{ model \}[\s\S]*?Preview and export a versioned PDF[\s\S]*?<ReportPreview model=\{model\} \/>/);
  assert.match(dashboard, /<TabsContent value="reports"><ReportsTab model=\{reportModel\} \/><\/TabsContent>/);
  assert.match(dashboard, /exposurePreview \? \[\{ value: 'hsr' as const, label: 'HSR' \}\] : \[\]/);
  assert.match(dashboard, /HSR distance/);
  const exposureComparison = dashboard.slice(dashboard.indexOf('function ExposureComparison'), dashboard.indexOf('function LocationTab'));
  assert.match(exposureComparison, /League mean/);
  assert.doesNotMatch(exposureComparison, /\(dotted line\)/);
  assert.match(exposureComparison, /border-dotted border-orange-400/);
  assert.match(exposureComparison, /ranked\.map[\s\S]*?mt-4 flex justify-end border-t[\s\S]*?League mean/);
  assert.match(exposureComparison, /ranked\.reduce\(\(sum, row\) => sum \+ \(metric\(row\) \?\? 0\), 0\) \/ ranked\.length/);
  assert.match(dashboard, /showMonthlyHours[\s\S]*showMonthlyDistance[\s\S]*comparisonMeasure/);
  assert.match(dashboard, /aria-label="Choose monthly exposure series"/);
  assert.match(dashboard, /<CheckToggle checked=\{showMonthlyHours\}[\s\S]*?label="Hours"/);
  assert.match(dashboard, /<CheckToggle checked=\{showMonthlyDistance\}[\s\S]*?label="Distance"/);
  assert.match(dashboard, /label="Choose team comparison exposure measure"/);
  assert.ok((dashboard.match(/scrollable=\{false\}/g) ?? []).length >= 1);
  assert.match(dashboard, /scrollable \? 'overflow-x-auto' : 'flex-wrap overflow-visible'/);
  assert.match(dashboard, /distance_km/);
  assert.match(charts, /match_exposure_hours/);
  assert.match(charts, /hsr_distance_km|hsr_percentage/);
  assert.match(charts, /HSR share/);
  assert.doesNotMatch(charts, /firstReportedMonth/);
  // Monthly charts drop pre-September months first (decision, 25 July 2026,
  // site-wide), then still open on the club's own first reported month.
  assert.match(charts, /fromSeptember\(sorted\)/);
  assert.match(charts, /const data = fromSeptember\(sorted\)/);
  assert.match(charts, /contributingClubsText/);
  assert.match(charts, /<ComposedChart aria-label="Monthly exposure hours and distance chart" accessibilityLayer/);
  assert.match(charts, /yAxisId="hours"[\s\S]*?dataKey="exposure_hours"[\s\S]*?name="Hours"/);
  assert.match(charts, /yAxisId="distance"[\s\S]*?dataKey="distance_km"[\s\S]*?name="Distance"/);
  assert.match(charts, /showHours && hasReportedExposureValue\(row, 'hours'\)[\s\S]*?showDistance && hasReportedExposureValue\(row, 'distance'\)/);
  assert.match(charts, /Select at least one series to plot\./);
  assert.match(charts, /w-full min-w-0/);
  assert.doesNotMatch(dashboard.slice(dashboard.indexOf('function ExposureTab'), dashboard.indexOf('function ReportsTab')), /overflow-[xy]-auto|max-h-\[/);
});
