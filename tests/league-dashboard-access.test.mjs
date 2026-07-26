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
  assert.doesNotMatch(page, /getExposureReviewPreview|exposurePreview/);

  assert.match(reporting, /reporting\.latest_league_dashboard_v3/);
  assert.match(reporting, /where season = \$1/);
  assert.match(reporting, /expected one league dashboard row/);
  assert.doesNotMatch(reporting, /reduce\(|incidence.*\/.*hours|burden.*\/.*hours/i);
});

test('published league dashboard is unlocked on the homepage', async () => {
  const home = await readFile(new URL('../app/page.tsx', import.meta.url), 'utf8');

  assert.match(home, /name: 'URC Overall'[\s\S]*status: 'live' as const/);
  assert.match(home, /href="\/urc"/);
});

test('team dashboard reads the v4 approved-build projection', async () => {
  const reporting = await readFile(new URL('../lib/reporting.ts', import.meta.url), 'utf8');

  assert.match(reporting, /reporting\.latest_team_dashboard_v4/);
  assert.match(reporting, /contact_distribution/);
  assert.match(reporting, /setting_metrics/);
  assert.match(reporting, /injury_profiles/);
  assert.match(reporting, /injury_type_families/);
  assert.match(reporting, /"injury_profile", "diagnosis"/);
  assert.match(reporting, /getTeamPageData/);
  assert.match(reporting, /getLeaguePageData/);
  assert.match(reporting, /one MVCC snapshot/);
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
  process.env.WEB_READER_DB_URL = 'postgres://fixture';
  let queryText = '';
  globalThis.__urcWebReaderPool = {
    query: async (sql) => {
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
  };

  try {
    const { getLeagueDashboard } = await loadReportingForFixtureTest();
    const dashboard = await getLeagueDashboard();
    assert.match(queryText, /reporting\.latest_league_dashboard_v4/);
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
  process.env.WEB_READER_DB_URL = 'postgres://fixture';
  process.env.TEAM_DISPLAY_ALIAS_JSON = JSON.stringify({ 'fixture-team': 'Team Q' });
  globalThis.__urcWebReaderPool = {
    query: async () => ({
      rows: [{
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
    injury_type_families: [],
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

  // Every controlled IOC region is hoverable, including regions with no cases, and
  // reports 0 rather than being inert (decision, 25 July 2026).
  assert.match(bodyMap, /pointerEvents:\s*'bounding-box' as const/);
  assert.doesNotMatch(bodyMap, /enabled\s*\?/);
  assert.match(bodyMap, /min-h-11|tabIndex:\s*0/);
});

test('injury impact uses a fixed log severity scale without changing burden bubbles or hiding singleton profiles', async () => {
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const impact = charts.slice(charts.indexOf('const IMPACT_LOG_SEVERITY_BASE_DOMAIN'));

  assert.match(impact, /const IMPACT_LOG_SEVERITY_BASE_DOMAIN = \[1, 400\] as const/);
  assert.match(impact, /const IMPACT_LOG_SEVERITY_BASE_TICKS = \[1, 2, 5, 10, 20, 50, 100, 200, 400\]/);
  assert.match(impact, /Math\.max\(IMPACT_LOG_SEVERITY_BASE_DOMAIN\[1\], 10 \*\* Math\.ceil\(Math\.log10\(maximum\)\)\)/);
  assert.match(impact, /domain=\{severityDomain\}/);
  assert.match(impact, /scale="log"/);
  assert.match(impact, /ticks=\{severityTicks\}/);
  assert.match(impact, /Mean severity, days \(logarithmic scale\)/);
  assert.match(impact, /isPlottableLogSeverity\(row\.mean_severity_days\)/);
  assert.match(impact, /Number\.isFinite\(value\) && value > 0/);
  assert.match(impact, /non-positive mean severity.*not shown because a logarithmic scale cannot represent those values/s);
  assert.match(impact, /bubble_burden: Math\.max\(row\.burden_per_1000h \?\? 0, 0\.01\)/);
  // The burden bubble range is unchanged; it is a named constant so the label
  // collision placement can size a label against the bubble it must clear.
  assert.match(impact, /const IMPACT_BUBBLE_SIZE = \[160, 1_100\] as const/);
  assert.match(impact, /<ZAxis type="number" dataKey="bubble_burden" range=\{\[IMPACT_BUBBLE_SIZE\[0\], IMPACT_BUBBLE_SIZE\[1\]\]\} name="Burden" \/>/);
  assert.doesNotMatch(impact, /time_loss_injuries\s*[<>]/);
  assert.doesNotMatch(impact, /ReferenceArea|ReferenceLine|median\(/);
  assert.doesNotMatch(impact, /aboveLogDomainRows|pending chart-domain review/);
  assert.doesNotMatch(dashboard, /View injury impact data|function AccessibleDataTable/);
});

test('injury impact tooltip prioritises burden, gives exact small-sample cautions, and supports pinning', async () => {
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');
  const tooltip = charts.slice(charts.indexOf('function ImpactTooltip'), charts.indexOf('function formatAxisTick'));
  const interaction = charts.slice(charts.indexOf('function ImpactBubble'), charts.indexOf('export function ImpactBubbleChart'));
  const chart = charts.slice(charts.indexOf('export function ImpactBubbleChart'));

  assert.match(tooltip, /\{row\.label\}.*settingLabel\(row\.setting\)/s);
  assert.ok(tooltip.indexOf('>Burden<') < tooltip.indexOf('>Incidence<'), 'burden must be the primary tooltip metric');
  assert.match(tooltip, /n = \{count\(row\.time_loss_injuries\)\} time-loss .*\{count\(row\.days_lost\)\} total days lost/s);
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
  assert.match(interaction, /radius \+ 5/);
  assert.match(interaction, /onPosition\(\{ row: payload, x: cx, y: cy \}\)/);
  assert.match(chart, /const syncPointPosition = useCallback/);
  assert.match(chart, /current\.x !== point\.x \|\| current\.y !== point\.y/);
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

test('exposure tab switches approved measures and gates provisional HSR behind the local preview', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');
  const charts = await readFile(new URL('../components/dashboard/charts.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /Total hours[\s\S]*Total distance/);
  assert.match(dashboard, /exposurePreview \? \[\{ value: 'hsr' as const, label: 'HSR' \}\] : \[\]/);
  assert.match(dashboard, /HSR distance/);
  assert.doesNotMatch(dashboard.slice(dashboard.indexOf('function ExposureComparison'), dashboard.indexOf('function LocationTab')), /League mean|const mean\b/);
  assert.match(dashboard, /monthlyMeasure[\s\S]*comparisonMeasure/);
  assert.match(dashboard, /label="Choose monthly exposure measure"/);
  assert.match(dashboard, /label="Choose team comparison exposure measure"/);
  assert.ok((dashboard.match(/scrollable=\{false\}/g) ?? []).length >= 2);
  assert.match(dashboard, /scrollable \? 'overflow-x-auto' : 'flex-wrap overflow-visible'/);
  assert.match(dashboard, /distance_km/);
  assert.match(charts, /match_exposure_hours/);
  assert.match(charts, /hsr_distance_km|hsr_percentage/);
  assert.match(charts, /HSR share/);
  assert.match(charts, /firstReportedMonth/);
  // Monthly charts drop pre-September months first (decision, 25 July 2026,
  // site-wide), then still open on the club's own first reported month.
  assert.match(charts, /fromSeptember\(sorted\)/);
  assert.match(charts, /inWindow\.slice\(firstReportedMonth\)/);
  assert.match(charts, /<BarChart aria-label=\{`Monthly \$\{exposureMeasureLabel\(measure\)\.toLowerCase\(\)\} chart`\} accessibilityLayer/);
  assert.match(charts, /w-full min-w-0/);
  assert.doesNotMatch(dashboard.slice(dashboard.indexOf('function ExposureTab'), dashboard.indexOf('function LocationTab')), /overflow-[xy]-auto|max-h-\[/);
});
