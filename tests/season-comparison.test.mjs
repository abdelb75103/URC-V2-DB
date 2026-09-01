import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import test from "node:test";
import ts from "typescript";

const require = createRequire(import.meta.url);

async function loadReportingModule() {
  const source = await readFile(new URL("../lib/reporting.ts", import.meta.url), "utf8");
  const pgUrl = pathToFileURL(require.resolve("pg")).href;
  const zodUrl = pathToFileURL(require.resolve("zod")).href;
  const executable = source
    .replace('import "server-only";\n', "")
    .replace('import { comparisonDashboardSeason, type DashboardSeason } from "@/lib/dashboard-season";', 'const comparisonDashboardSeason = (season) => season === "2025-26" ? "2024-25" : "2025-26";')
    .replace('import { Pool } from "pg";', `import pg from "${pgUrl}";\nconst { Pool } = pg;`)
    .replace('import { z } from "zod";', `import { z } from "${zodUrl}";`);
  const javascript = ts.transpileModule(executable, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString("base64")}`);
}

function validComparison(scope = "team") {
  const metric = (value, unit) => ({ value, unit });
  return {
    rule_version: "season_comparison_reporting_2026_08_31_v4",
    scope,
    previous_season: "2024-25",
    current_season: "2025-26",
    kpis: [
      { key: "time_loss_incidence", label: "TL injury incidence", previous: metric(10, "TL injuries per 1,000 player-hours"), current: metric(8, "TL injuries per 1,000 player-hours"), outcome_improvement_percent: 20 },
      { key: "mean_severity", label: "Mean severity", previous: metric(5, "days lost per injury"), current: metric(4, "days lost per injury"), outcome_improvement_percent: 20 },
      { key: "injury_burden", label: "Injury burden", previous: metric(50, "days lost per 1,000 player-hours"), current: metric(32, "days lost per 1,000 player-hours"), outcome_improvement_percent: 36 },
      { key: "time_loss_injuries", label: "Time-loss injuries", previous: metric(10, "TL injuries"), current: metric(8, "TL injuries"), outcome_improvement_percent: 20 },
    ],
    impact: ["all", "match", "training"].map((setting) => ({
      setting,
      label: setting === "all" ? "Overall" : setting[0].toUpperCase() + setting.slice(1),
      previous: { time_loss_incidence_per_1000h: 10, mean_severity_days: 5, burden_per_1000h: 50, time_loss_injuries: 10, exposure_hours: 1_000 },
      current: { time_loss_incidence_per_1000h: 8, mean_severity_days: 4, burden_per_1000h: 32, time_loss_injuries: 8, exposure_hours: 1_000 },
    })),
    monthly: [
      ["2024-09", "Sep"], ["2024-10", "Oct"], ["2024-11", "Nov"], ["2024-12", "Dec"], ["2025-01", "Jan"],
      ["2025-02", "Feb"], ["2025-03", "Mar"], ["2025-04", "Apr"], ["2025-05", "May"], ["2025-06", "Jun"],
    ].map(([month_key, label]) => ({ month_key, label, previous_time_loss_injuries: 0, current_time_loss_injuries: 0 })),
    diagnoses: ["all", "match", "training"].map((setting) => ({
      setting,
      label: setting === "all" ? "Overall" : setting[0].toUpperCase() + setting.slice(1),
      previous: [
        { rank: 1, diagnosis: "Hamstring Injury", time_loss_injuries: 4, incidence_per_1000h: 4, burden_per_1000h: 20 },
        { rank: 2, diagnosis: "Concussion", time_loss_injuries: 3, incidence_per_1000h: 3, burden_per_1000h: 15 },
        { rank: 3, diagnosis: "Ankle Injury", time_loss_injuries: 2, incidence_per_1000h: 2, burden_per_1000h: 10 },
      ],
      current: [
        { rank: 1, diagnosis: "Concussion", time_loss_injuries: 3, incidence_per_1000h: 3, burden_per_1000h: 12 },
        { rank: 2, diagnosis: "Hamstring Injury", time_loss_injuries: 2, incidence_per_1000h: 2, burden_per_1000h: 8 },
        { rank: 3, diagnosis: "Shoulder Injury", time_loss_injuries: 1, incidence_per_1000h: 1, burden_per_1000h: 6 },
      ],
    })),
    exposure: {
      previous: { exposure_hours: 1_000, status: "available", qualification: null },
      current: { exposure_hours: 1_000, status: "available", qualification: null },
    },
  };
}

test("strictly parses the allowlisted comparison reader payload and its fixed time domain", async () => {
  const { parseSeasonComparisonReaderRow } = await loadReportingModule();
  const comparison = validComparison();

  assert.equal(parseSeasonComparisonReaderRow(comparison, "team").scope, "team");

  const extraField = structuredClone(comparison);
  extraField.kpis[0].previous.private_release_id = "not-public";
  assert.throws(() => parseSeasonComparisonReaderRow(extraField, "team"), /unrecognized_keys/i);

  const unorderedMonths = structuredClone(comparison);
  [unorderedMonths.monthly[0], unorderedMonths.monthly[1]] = [unorderedMonths.monthly[1], unorderedMonths.monthly[0]];
  assert.throws(() => parseSeasonComparisonReaderRow(unorderedMonths, "team"));

  const unorderedRanks = structuredClone(comparison);
  [unorderedRanks.diagnoses[0].previous[0], unorderedRanks.diagnoses[0].previous[1]] = [
    unorderedRanks.diagnoses[0].previous[1], unorderedRanks.diagnoses[0].previous[0],
  ];
  assert.throws(() => parseSeasonComparisonReaderRow(unorderedRanks, "team"), /ranks must be contiguous/i);

  assert.throws(() => parseSeasonComparisonReaderRow(comparison, "league"), /scope does not match/i);
});

test("governed SQL pins KPI formulas, chronological zero-filled months and diagnosis tie-breaking", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831140000_season_comparison_reporting_v1.sql", import.meta.url), "utf8");

  assert.match(sql, /when previous_value is null or previous_value = 0 or current_value is null[\s\S]*then null[\s\S]*else 100 \* \(previous_value - current_value\) \/ previous_value/);
  assert.match(sql, /\(1, 9, '2024-09', 'Sep'\)[\s\S]*\(10, 6, '2025-06', 'Jun'\)/);
  assert.match(sql, /previous_time_loss_injuries[\s\S]*coalesce\([\s\S]*\), 0\)/);
  assert.match(sql, /current_time_loss_injuries[\s\S]*coalesce\([\s\S]*\), 0\)/);
  assert.match(sql, /order by \(item ->> 'time_loss_injuries'\)::numeric desc,[\s\S]*\(item ->> 'burden_per_1000h'\)::numeric desc nulls last/);
});

test("governed SQL emits one ordered impact row per setting and supports the Year 1 overall shape", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831140000_season_comparison_reporting_v1.sql", import.meta.url), "utf8");
  const impactStart = sql.indexOf("with settings(ordinal, setting, label) as (");
  const impactEnd = sql.indexOf("with months(ordinal", impactStart);
  const impactSql = sql.slice(impactStart, impactEnd);

  assert.match(impactSql, /\(1, 'all', 'Overall'\),\s*\(2, 'match', 'Match'\),\s*\(3, 'training', 'Training'\)/);
  assert.equal((impactSql.match(/\(2, 'match', 'Match'\)/g) ?? []).length, 1);
  assert.match(impactSql, /case when settings\.setting = 'all' then jsonb_build_object\([\s\S]*previous_dashboard -> 'headline'/);
  assert.match(impactSql, /case when settings\.setting = 'all' then jsonb_build_object\([\s\S]*current_dashboard -> 'headline'/);
});

test("governed SQL uses approved pooled league payloads and the selected team pair only", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831140000_season_comparison_reporting_v1.sql", import.meta.url), "utf8");

  assert.match(sql, /create view reporting\.latest_team_season_comparison_v1[\s\S]*from reporting\.latest_team_dashboard_v6 previous[\s\S]*join reporting\.latest_team_dashboard_v6 current[\s\S]*current\.team_key = previous\.team_key/);
  assert.match(sql, /create view reporting\.latest_league_season_comparison_v1[\s\S]*from reporting\.latest_league_dashboard_v6 previous[\s\S]*cross join reporting\.latest_league_dashboard_v6 current/);
  assert.doesNotMatch(sql, /avg\s*\(/i);
});

test("comparison views can execute through one narrow pure builder grant", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831140000_season_comparison_reporting_v1.sql", import.meta.url), "utf8");

  assert.match(sql, /create function reporting\.build_season_comparison_v1\([\s\S]*stable\s+strict\s+security definer\s+set search_path = pg_catalog, pg_temp/);
  assert.match(sql, /grant execute on function reporting\.build_season_comparison_v1\(\s*jsonb, jsonb, text\s*\) to web_reader/);
  assert.doesNotMatch(sql, /grant execute on function reporting\.season_comparison_(?:exposure_qualification|severe_value)_v1/);
});

test("live-operation SQL pins the migration checksum and rechecks the reader boundary", async () => {
  const [preflight, registration, verification] = await Promise.all([
    readFile(new URL("../tools/sql/preflight_season_comparison_reporting_v1.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/register_season_comparison_reporting_v1_migration.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/verify_season_comparison_reporting_v1.sql", import.meta.url), "utf8"),
  ]);

  assert.match(preflight, /approved_dashboard_reader_target_v2/);
  assert.match(preflight, /migration_already_tracked/);
  assert.match(registration, /20260831140000/);
  assert.match(registration, /77b1e1cb6bc19eb53e264742d2e950431f327960744f36588b2352ad46bfa60b/);
  assert.match(registration, /on conflict \(version\) do nothing/);
  assert.match(verification, /migration_registered_exactly/);
  assert.match(verification, /approved_dashboard_reader_target_v3/);
  assert.match(verification, /exposure_helper_execute/);
  assert.match(verification, /severe_helper_execute/);
});

test("presentation V2 operation SQL pins its checksum and retired-reader boundary", async () => {
  const [preflight, registration, verification] = await Promise.all([
    readFile(new URL("../tools/sql/preflight_season_comparison_presentation_v2.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/register_season_comparison_presentation_v2_migration.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/verify_season_comparison_presentation_v2.sql", import.meta.url), "utf8"),
  ]);

  assert.match(preflight, /predecessor_registered_exactly/);
  assert.match(registration, /20260831150000/);
  assert.match(registration, /85722743687a87ce76d0d927687a2113b9e27b11b9ada8da0da3741e474384c3/);
  assert.match(registration, /latest_team_season_comparison_v1/);
  assert.match(verification, /target_v4_attested/);
  assert.match(verification, /non_presentation_values_match/);
  assert.match(verification, /team_v1_select/);
  assert.match(verification, /team_v2_select/);
});

test("governed SQL derives severe incidence only from the known-duration >28-day band and reports its limitation", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831140000_season_comparison_reporting_v1.sql", import.meta.url), "utf8");

  assert.match(sql, /where item ->> 'key' = 'severity_mean_days'/);
  assert.match(sql, /item ->> 'key' = 'greater_than_twenty_eight_days'[\s\S]*item ->> 'setting' = 'all'/);
  assert.match(sql, /Unknown and, where present, right-censored durations are excluded from the severe numerator/);
  assert.match(sql, /Byar approximate 95% Poisson confidence interval with exact zero-event upper limit/);
  assert.match(sql, /if severe_numerator = 0[\s\S]*-ln\(0\.025\)/);
  assert.match(sql, /when total_time_loss > 0 and known_duration_time_loss is not null/);
});

test("presentation V2 removes severe incidence and governs the hamstring display alias", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831150000_season_comparison_presentation_v2.sql", import.meta.url), "utf8");

  assert.match(sql, /comparison - 'severe'/);
  assert.match(sql, /season_comparison_reporting_2026_08_31_v2/);
  assert.match(sql, /hamstring injury[\s\S]*hamstring muscle injury[\s\S]*hamstring strain or tear[\s\S]*Hamstring Injury/);
  assert.match(sql, /current\.comparison - 'rule_version' - 'diagnoses'[\s\S]*predecessor\.comparison - 'rule_version' - 'diagnoses' - 'severe'/);
  assert.match(sql, /revoke select on reporting\.latest_team_season_comparison_v1/);
  assert.match(sql, /grant select on reporting\.latest_team_season_comparison_v2/);
});

test("diagnosis V3 emits ranked top-three families for each setting and retires V2 reader access", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260831160000_season_comparison_diagnosis_top_three_v3.sql", import.meta.url), "utf8");

  assert.match(sql, /season_comparison_reporting_2026_08_31_v3/);
  assert.match(sql, /where rank <= 3/);
  assert.match(sql, /order by time_loss_injuries desc,[\s\S]*burden_per_1000h desc nulls last/);
  assert.match(sql, /hamstring strain or tear[\s\S]*Hamstring Injury/);
  assert.match(sql, /acute_concussion[\s\S]*Concussion/);
  assert.match(sql, /revoke select on reporting\.latest_team_season_comparison_v2/);
  assert.match(sql, /grant select on reporting\.latest_team_season_comparison_v3/);
  assert.match(sql, /grant execute on function reporting\.build_season_comparison_v3/);
});

test("diagnosis V3 operation SQL pins its checksum and reader boundary", async () => {
  const [preflight, registration, verification] = await Promise.all([
    readFile(new URL("../tools/sql/preflight_season_comparison_diagnosis_top_three_v3.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/register_season_comparison_diagnosis_top_three_v3_migration.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/verify_season_comparison_diagnosis_top_three_v3.sql", import.meta.url), "utf8"),
  ]);

  assert.match(preflight, /predecessor_registered_exactly/);
  assert.match(registration, /20260831160000/);
  assert.doesNotMatch(registration, /MIGRATION_SHA256/);
  assert.match(verification, /target_v5_attested/);
  assert.match(verification, /non_diagnosis_values_match/);
  assert.match(verification, /team_v2_select/);
  assert.match(verification, /team_v3_select/);
});

test("concussion-family V4 includes released acute variants and retires historical builder grants", async () => {
  const [sql, registration, verification] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260831170000_season_comparison_concussion_family_v4.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/register_season_comparison_concussion_family_v4_migration.sql", import.meta.url), "utf8"),
    readFile(new URL("../tools/sql/verify_season_comparison_concussion_family_v4.sql", import.meta.url), "utf8"),
  ]);

  assert.match(sql, /\^acute_concussion\(\?:_\|\$\)/);
  assert.match(sql, /acute_concussion_with_visual_symptoms/);
  assert.match(sql, /revoke execute on function reporting\.build_season_comparison_v1/);
  assert.match(sql, /revoke execute on function reporting\.build_season_comparison_v3/);
  assert.match(registration, /076434262d9d9d107744116612baf324f8f0b9417b4e87d2f19fe39f5c171758/);
  assert.match(verification, /league_current_overall_concussion/);
  assert.match(verification, /builder_v1_execute/);
});

test("application page reads attach the strict comparison projection in the dashboard snapshot and use v7 attestation", async () => {
  const reporting = await readFile(new URL("../lib/reporting.ts", import.meta.url), "utf8");
  const leaguePage = await readFile(new URL("../app/urc/page.tsx", import.meta.url), "utf8");
  const teamPage = await readFile(new URL("../app/team/[teamId]/page.tsx", import.meta.url), "utf8");

  assert.match(reporting, /approved_dashboard_reader_target_v7/);
  assert.match(reporting, /from reporting\.latest_team_season_comparison_v5[\s\S]*where team_key = \$1/);
  assert.match(reporting, /from reporting\.latest_league_season_comparison_v5/);
  assert.match(reporting, /season_comparison: seasonComparisonReaderSchema\.nullable\(\)/);
  assert.match(reporting, /approvedSeasonComparisonReleaseToken[\s\S]*latest_dashboard_cache_token_v2[\s\S]*order by case season[\s\S]*2024-25[\s\S]*2025-26/);
  assert.doesNotMatch(reporting, /buildSeasonComparison|byarPoisson95|outcomeImprovement/);
  assert.doesNotMatch(leaguePage, /getLeagueSeasonComparison/);
  assert.doesNotMatch(teamPage, /getTeamSeasonComparison/);
});
