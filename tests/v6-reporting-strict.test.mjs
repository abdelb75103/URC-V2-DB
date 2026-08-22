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
    .replace('import { Pool } from "pg";', `import pg from "${pgUrl}";\nconst { Pool } = pg;`)
    .replace('import { z } from "zod";', `import { z } from "${zodUrl}";`);
  const javascript = ts.transpileModule(executable, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString("base64")}`);
}

const analytics = {
  key: "all",
  label: "All",
  time_loss_injuries: 1,
  days_lost: 2,
  exposure_hours: 100,
  incidence_per_1000h: 10,
  burden_per_1000h: 20,
  mean_severity_days: 2,
};
const setting = {
  setting: "all",
  label: "All",
  time_loss_injuries: 1,
  days_lost: 2,
  exposure_hours: 100,
  incidence_per_1000h: 10,
  burden_per_1000h: 20,
  mean_severity_days: 2,
};
const profile = {
  dimension: "injury_type",
  code: "joint_sprain",
  label: "Joint sprain",
  ...setting,
};
const headline = [
  { key: "recorded_injuries", label: "Recorded injuries", value: 1, unit: "injuries", formula: "count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)" },
  { key: "time_loss_injuries", label: "Time-loss injuries", value: 1, unit: "injuries", formula: "count(eligible injury rows where days lost > 0)" },
  { key: "incidence_per_1000h", label: "Incidence", value: 10, unit: "per 1,000 player-hours", numerator: 1, denominator: 100, formula: "pooled time-loss injuries / pooled exposure hours * 1000" },
  { key: "severity_mean_days", label: "Mean severity", value: 2, unit: "days", numerator: 2, denominator: 1, formula: "pooled days lost / pooled time-loss injuries" },
  { key: "severity_median_days", label: "Median severity", value: 2, unit: "days", formula: "median(days lost) across pooled time-loss injuries" },
  { key: "burden_per_1000h", label: "Burden", value: 20, unit: "days per 1,000 player-hours", numerator: 2, denominator: 100, formula: "pooled days lost / pooled exposure hours * 1000" },
];
const teamCoverage = {
  exposure_rows: 1,
  exposed_players: 1,
  weeks: 1,
  match_hours: 10,
  training_hours: 90,
  hours: 100,
  distance_km: 0,
  included_exposure_status: "included_pending_protocol",
  analysis_window_start: "2025-09-01",
  analysis_window_end: "2026-06-30",
  exposure_grain: "session",
};

function validDashboard(scope = "team") {
  return {
    team: scope === "team" ? "Example" : "URC Overall",
    season: "2025-26",
    generated_at: "2026-08-15T00:00:00Z",
    analysis_window: { start: "2025-09-01", end: "2026-06-30", basis: "season" },
    method: ["Reviewed V6"],
    coverage: scope === "team"
      ? { ...teamCoverage }
      : (({ exposure_grain, ...coverage }) => ({ ...coverage, teams_included: 16 }))(teamCoverage),
    headline: structuredClone(headline),
    setting_split: ["all", "match", "training", "unknown"].map((key) => ({
      key, label: key[0].toUpperCase() + key.slice(1),
      time_loss_injuries: 1, days_lost: 2, exposure_hours: key === "unknown" ? null : 100,
    })),
    setting_metrics: ["all", "match", "training", "unknown"].map((key) => ({
      ...setting, setting: key, label: key[0].toUpperCase() + key.slice(1),
      exposure_hours: key === "unknown" ? null : 100,
    })),
    monthly: [{
      month: "2025-09", exposure_hours: 100, distance_km: 0,
      time_loss_injuries: 1, days_lost: 2,
      incidence_per_1000h: 10, burden_per_1000h: 20,
    }],
    body_locations: [{ ...analytics, key: "knee", label: "Knee" }],
    injury_types: [{ ...analytics, key: "joint_sprain", label: "Joint sprain" }],
    injury_profiles: [
      { ...profile },
      { ...profile, dimension: "diagnosis", code: "compound__thigh__muscle_injury", label: "Thigh · Muscle injury" },
    ],
    injury_type_families: [{
      ...profile,
      dimension: "injury_type_family",
      mapping_version: "injury_type_family_2026-07-21_v1",
      subtypes: [{ ...profile }],
    }],
    severity_distribution: [{
      key: "one_day", label: "One day", recorded_injuries: 1,
      time_loss_injuries: 1, days_lost: 1,
    }],
    contact_distribution: ["all", "match", "training", "unknown"].flatMap((setting) => [
      { key: "contact", label: "Contact", setting, recorded_injuries: 1, time_loss_injuries: 1 },
      { key: "non_contact", label: "Non-contact", setting, recorded_injuries: 0, time_loss_injuries: 0 },
      { key: "unknown", label: "Unknown", setting, recorded_injuries: 0, time_loss_injuries: 0 },
    ]),
    prior_season: { season: "2024-25", status: "frozen", note: "Frozen comparator" },
    limitations: ["Reviewed limitations"],
  };
}

test("2025-26 reader rejects unexpected fields at every public nesting boundary", async () => {
  const { parseDashboardReaderRow } = await loadReportingModule();
  assert.equal(parseDashboardReaderRow(validDashboard(), "2025-26", "team").season, "2025-26");

  const mutations = [
    (row) => { row.unexpected = true; },
    (row) => { row.coverage.unexpected = true; },
    (row) => { row.setting_split[0].unexpected = true; },
    (row) => { row.injury_profiles[0].unexpected = true; },
    (row) => { row.injury_type_families[0].unexpected = true; },
    (row) => { row.injury_type_families[0].subtypes[0].unexpected = true; },
    (row) => { row.contact_distribution[0].unexpected = true; },
  ];
  for (const mutate of mutations) {
    const row = structuredClone(validDashboard());
    mutate(row);
    assert.throws(() => parseDashboardReaderRow(row, "2025-26", "team"), /unrecognized_keys/i);
  }

  const crossSectionMutations = [
    (row) => { row.monthly[0].key = "known-elsewhere"; },
    (row) => { row.body_locations[0].month = "2025-09"; },
    (row) => { row.setting_split[0].incidence_per_1000h = 10; },
    (row) => { row.headline[0].numerator = 1; },
  ];
  for (const mutate of crossSectionMutations) {
    const row = structuredClone(validDashboard());
    mutate(row);
    assert.throws(() => parseDashboardReaderRow(row, "2025-26", "team"), /unrecognized_keys/i);
  }
});

test("2025-26 reader preserves unavailable coverage and monthly exposure as null", async () => {
  const { parseDashboardReaderRow } = await loadReportingModule();
  const unavailable = validDashboard();
  unavailable.coverage.hours = null;
  unavailable.coverage.distance_km = null;
  unavailable.monthly[0].exposure_hours = null;
  unavailable.monthly[0].distance_km = null;

  const parsed = parseDashboardReaderRow(unavailable, "2025-26", "team");
  assert.equal(parsed.coverage.hours, null);
  assert.equal(parsed.coverage.distance_km, null);
  assert.equal(parsed.monthly[0].exposure_hours, null);
  assert.equal(parsed.monthly[0].distance_km, null);
});

test("2024-25 legacy reader still rejects unavailable coverage", async () => {
  const { parseDashboardReaderRow } = await loadReportingModule();
  const unavailable = validDashboard();
  unavailable.coverage.hours = null;
  unavailable.coverage.distance_km = null;

  assert.throws(
    () => parseDashboardReaderRow(unavailable, "2024-25", "team"),
    /Expected number, received null/,
  );
});

test("exposure UI does not add preview figures to unavailable coverage", async () => {
  const dashboard = await readFile(new URL("../components/dashboard/team-dashboard.tsx", import.meta.url), "utf8");

  assert.match(dashboard, /function addPreviewToKnownValue[\s\S]*?if \(value === null \|\| value === undefined\) return null;/);
  assert.doesNotMatch(dashboard, /\(row\.exposure_hours \?\? 0\) \+ \(preview\?\.additional_hours \?\? 0\)/);
  assert.doesNotMatch(dashboard, /\(row\.distance_km \?\? 0\) \+ \(preview\?\.additional_distance_km \?\? 0\)/);
  assert.match(dashboard, /const totalHours = addPreviewToKnownValue\(\s*coverage\.hours,/);
  assert.match(dashboard, /const totalDistance = addPreviewToKnownValue\(\s*coverage\.distance_km,/);
  assert.match(dashboard, /label="Total hours" value=\{fmtHours\(totalHours\)\}/);
  assert.match(dashboard, /label="Total distance" value=\{fmt\(totalDistance\)\}/);
});

test("2025-26 reader requires explicit nullable keys and complete ordered nested grids", async () => {
  const { parseDashboardReaderRow } = await loadReportingModule();
  const missingRequiredKeys = [
    (row) => { delete row.headline[0].value; },
    (row) => { delete row.headline[2].numerator; },
    (row) => { delete row.monthly[0].exposure_hours; },
    (row) => { delete row.body_locations[0].mean_severity_days; },
    (row) => { delete row.setting_split[0].exposure_hours; },
    (row) => { delete row.setting_metrics[0].incidence_per_1000h; },
    (row) => { delete row.injury_profiles[0].burden_per_1000h; },
    (row) => { delete row.injury_type_families[0].mean_severity_days; },
    (row) => { delete row.coverage.match_hours; },
  ];
  for (const mutate of missingRequiredKeys) {
    const row = structuredClone(validDashboard());
    mutate(row);
    assert.throws(() => parseDashboardReaderRow(row, "2025-26", "team"));
  }

  const missingContact = structuredClone(validDashboard());
  missingContact.contact_distribution.pop();
  assert.throws(() => parseDashboardReaderRow(missingContact, "2025-26", "team"));

  const reorderedContact = structuredClone(validDashboard());
  [reorderedContact.contact_distribution[0], reorderedContact.contact_distribution[1]] =
    [reorderedContact.contact_distribution[1], reorderedContact.contact_distribution[0]];
  assert.throws(() => parseDashboardReaderRow(reorderedContact, "2025-26", "team"));

  const emptyFamily = structuredClone(validDashboard());
  emptyFamily.injury_type_families[0].subtypes = [];
  assert.throws(() => parseDashboardReaderRow(emptyFamily, "2025-26", "team"));

  const missingDiagnosis = structuredClone(validDashboard());
  missingDiagnosis.injury_profiles = missingDiagnosis.injury_profiles.filter(
    (profile) => profile.dimension !== "diagnosis",
  );
  assert.throws(() => parseDashboardReaderRow(missingDiagnosis, "2025-26", "team"), /diagnosis dimension/i);

  const nonFrozenPrior = structuredClone(validDashboard());
  nonFrozenPrior.prior_season.status = "available";
  assert.throws(() => parseDashboardReaderRow(nonFrozenPrior, "2025-26", "team"));
});

test("2025-26 team and league coverage shapes cannot be exchanged", async () => {
  const { parseDashboardReaderRow } = await loadReportingModule();
  assert.doesNotThrow(() => parseDashboardReaderRow(validDashboard("league"), "2025-26", "league"));
  assert.throws(() => parseDashboardReaderRow(validDashboard(), "2025-26", "league"));
  assert.throws(() => parseDashboardReaderRow(validDashboard("league"), "2025-26", "team"));
});

test("legacy reader keeps its existing unknown-key stripping behaviour", async () => {
  const { parseDashboardReaderRow } = await loadReportingModule();
  const legacy = validDashboard();
  legacy.season = "2024-25";
  legacy.unexpected = "legacy-compatible";
  legacy.coverage.unexpected = "legacy-compatible";
  assert.doesNotThrow(() => parseDashboardReaderRow(legacy, "2024-25", "team"));
});
