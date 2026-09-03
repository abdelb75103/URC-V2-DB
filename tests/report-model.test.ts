import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { teams } from "../config/teams";
import { assertReportModelPrivacy, buildReportModel, DEFAULT_REPORT_SECTION_IDS, filterReportSectionIds } from "../lib/report-model";
import { reportProtectedTerms } from "../lib/report-privacy";
import { REPORT_SECTION_LABELS } from "../lib/report-model-types";
import type { DashboardData } from "../lib/reporting-types";
import { dashboardFixture, priorDashboardFixture } from "./report-fixtures";
import { buildReportComparisonRows } from "../lib/report-comparison";
import type { TeamComparisonRow } from "../lib/reporting-types";

test("canonical team names match every accepted parity payload", async () => {
  const configuredNames = new Map(teams.map((team) => [team.id, team.name]));
  const files = (await readdir("content/reporting"))
    .filter((file) => /_dashboard_20(?:24-25|25-26)\.json$/.test(file) && !file.startsWith("urc_"));

  assert.equal(files.length, 32);
  for (const file of files) {
    const teamId = file.split("_dashboard_")[0];
    const payload = JSON.parse(await readFile(join("content/reporting", file), "utf8")) as { team: string };
    assert.equal(payload.team, configuredNames.get(teamId), file);
  }
});

test("allows only Glasgow's own canonical name in its report", async () => {
  for (const season of ["2024-25", "2025-26"] as const) {
    const current = {
      ...JSON.parse(await readFile(join("content/reporting", `glasgow_dashboard_${season}.json`), "utf8")),
      scope: "team",
    } as DashboardData;
    const request = {
      current,
      prior: null,
      expectedScope: "team" as const,
      expectedSeason: season,
      subjectName: "Glasgow Warriors",
      protectedTerms: reportProtectedTerms("glasgow"),
    };

    assert.doesNotThrow(() => buildReportModel(request));
    assert.throws(
      () => buildReportModel({
        ...request,
        current: { ...current, limitations: [...current.limitations, "Benetton must not appear in a Glasgow report."] },
      }),
      /another club name/,
    );
  }
});

test("builds a narrow team report model from approved current and prior payloads", () => {
  const model = buildReportModel({
    current: dashboardFixture(),
    prior: priorDashboardFixture(),
    expectedScope: "team",
    expectedSeason: "2025-26",
    subjectName: "Harbour RFC",
    protectedTerms: ["Rivals RFC", "team-internal-77", "compare-93", "Team A"],
  });

  assert.equal(model.subjectName, "Harbour RFC");
  assert.deepEqual(model.monthlyInjuryPattern.map((row) => row.month), ["2025-07", "2025-08"]);
  assert.equal(model.seasonComparison.headline.find((metric) => metric.key === "recorded")?.delta, 6);
  assert.ok(Math.abs((model.seasonComparison.headline.find((metric) => metric.key === "incidence")?.delta ?? 0) - 0.3) < 0.000001);
  assert.equal(model.snapshotMetrics[0].value, 74);
  assert.equal(model.matchTraining.length, 2);
  assert.equal(model.seasonComparison.settings.every((metric) => metric.delta === null), true);
  assert.equal(model.reportVersion, "1.0");
  assert.equal(model.exportedAt, model.dataGeneratedAt);
});

test("uses released diagnosis families for report common injuries", () => {
  const current = dashboardFixture({
    diagnosis_families: [
      {
        code: "concussion",
        label: "Concussion",
        setting: "training",
        recorded_injuries: 17,
        time_loss_injuries: 17,
        known_duration_time_loss_injuries: 17,
        days_lost: 217,
        exposure_hours: 1_000,
        incidence_per_1000h: 17,
        burden_per_1000h: 217,
        mean_severity_days: 12.8,
        subtypes: [{
          code: "dx_concussion",
          label: "Concussion",
          recorded_injuries: 12,
          time_loss_injuries: 12,
          known_duration_time_loss_injuries: 12,
          days_lost: 140,
        }],
      },
      {
        code: "hamstring_muscle_injury",
        label: "Hamstring Muscle Injury",
        setting: "training",
        recorded_injuries: 1,
        time_loss_injuries: 1,
        known_duration_time_loss_injuries: 1,
        days_lost: 10,
        exposure_hours: 1_000,
        incidence_per_1000h: 1,
        burden_per_1000h: 10,
        mean_severity_days: 10,
        subtypes: [],
      },
      {
        code: "unknown_diagnosis",
        label: "Unknown Diagnosis",
        setting: "training",
        recorded_injuries: 8,
        time_loss_injuries: 8,
        known_duration_time_loss_injuries: 8,
        days_lost: 80,
        exposure_hours: 1_000,
        incidence_per_1000h: 8,
        burden_per_1000h: 80,
        mean_severity_days: 10,
        subtypes: [],
      },
    ],
    injury_profiles: [
      ...dashboardFixture().injury_profiles,
      { dimension: "diagnosis", code: "hamstring_tendon", label: "Hamstring Tendon Injury", setting: "training", recorded_injuries: 9, time_loss_injuries: 9, days_lost: 90, exposure_hours: 1_000, incidence_per_1000h: 9, burden_per_1000h: 90, mean_severity_days: 10 },
      { dimension: "diagnosis", code: "hamstring_trigger", label: "Hamstring Trigger Point", setting: "training", recorded_injuries: 4, time_loss_injuries: 4, days_lost: 20, exposure_hours: 1_000, incidence_per_1000h: 4, burden_per_1000h: 20, mean_severity_days: 5 },
    ],
  });
  const model = buildReportModel({ current, prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] });

  assert.deepEqual(model.injuryProfile.diagnoses.map((row) => [row.label, row.timeLossInjuries]), [
    ["Concussion", 17],
    ["Hamstring Muscle Injury", 1],
  ]);
});

test("keeps an authoritative empty diagnosis family release empty", () => {
  const model = buildReportModel({
    current: dashboardFixture({ diagnosis_families: [] }),
    prior: null,
    expectedScope: "team",
    expectedSeason: "2025-26",
    subjectName: "Harbour RFC",
    protectedTerms: ["Rivals RFC"],
  });

  assert.deepEqual(model.injuryProfile.diagnoses, []);
});

test("uses the dashboard matrix threshold and retains low-count knee ligament injuries", () => {
  const base = { ...dashboardFixture().injury_profiles[0], dimension: "diagnosis" as const, setting: "all" as const };
  const current = dashboardFixture({
    headline: [{ key: "time_loss_injuries", label: "Injuries", value: 1000, unit: "injuries", formula: "released count" }],
    injury_profiles: [
      { ...base, code: "common", label: "Common Injury", time_loss_injuries: 13 },
      { ...base, code: "rare", label: "Rare Injury", time_loss_injuries: 12 },
      { ...base, code: "dx_acl_tear", label: "ACL Tear", time_loss_injuries: 1 },
      { ...base, code: "unknown", label: "Unknown", time_loss_injuries: 100 },
    ],
  });
  const model = buildReportModel({ current, prior: null, expectedScope: "team", expectedSeason: current.season, subjectName: current.team, protectedTerms: ["Rivals RFC"] });
  assert.deepEqual(model.injuryImpact.diagnoses.map(row => row.code), ["common", "dx_acl_tear"]);
  assert.deepEqual(model.injuryProfile.diagnoses.map(row => row.code), ["common", "rare", "dx_acl_tear"]);
  assert.equal(model.snapshotMetrics[0].value, 1000);
});

test("carries released illness metrics separately without replacing null rates or including unknown profiles", () => {
  const metrics = {
    setting: "all" as const, recorded_illnesses: 12, known_duration_illnesses: 8,
    days_lost: 20, exposure_hours: null, incidence_per_1000h: null,
    burden_per_1000h: null, mean_severity_days: 2.5,
  };
  const current = dashboardFixture({
    illness_summary: { ...metrics, qualification: "Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training." },
    illness_profiles: [
      { ...metrics, code: "respiratory", label: "Respiratory Illness" },
      { ...metrics, code: "unknown", label: "Unknown" },
    ],
  });
  const model = buildReportModel({ current, prior: null, expectedScope: "team", expectedSeason: current.season, subjectName: current.team, protectedTerms: ["Rivals RFC"] });
  assert.deepEqual(model.illness.summary, current.illness_summary);
  assert.deepEqual(model.illness.profiles, [current.illness_profiles![0]]);
  assert.deepEqual(model.snapshotMetrics.map(metric => metric.value), current.headline.map(metric => metric.value));
  const unavailable = buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "team", expectedSeason: current.season, subjectName: current.team, protectedTerms: ["Rivals RFC"] });
  assert.deepEqual(unavailable.illness, { summary: null, profiles: [] });
});

test("keeps approved league identity validation separate from its display name", () => {
  const current = { ...dashboardFixture(), scope: "league" as const, team: "URC Overall" };
  const model = buildReportModel({
    current,
    prior: null,
    expectedScope: "league",
    expectedSeason: "2025-26",
    subjectName: "URC Overall",
    displaySubjectName: "United Rugby Championship",
    protectedTerms: ["Rivals RFC"],
  });
  assert.equal(model.subjectName, "United Rugby Championship");
});

test("compares the selected earlier season with the approved later season", () => {
  const current = priorDashboardFixture({
    prior_season: { season: "2023-24", status: "frozen", note: "Earlier release." },
  });
  const comparison = dashboardFixture();
  const model = buildReportModel({
    current,
    prior: comparison,
    expectedScope: "team",
    expectedSeason: "2024-25",
    subjectName: "Harbour RFC",
    protectedTerms: ["Rivals RFC"],
  });

  const recorded = model.seasonComparison.headline.find((metric) => metric.key === "recorded");
  assert.equal(model.seasonComparison.comparisonSeason, "2025-26");
  assert.equal(recorded?.currentValue, 68);
  assert.equal(recorded?.priorValue, 74);
  assert.equal(recorded?.delta, -6);
});

test("preserves dashboard aliases and hides the viewing club alias in report comparisons", () => {
  const setting = (label: string) => ({
    setting: "match" as const,
    label,
    recorded_injuries: 1,
    time_loss_injuries: 1,
    days_lost: 2,
    exposure_hours: 100,
    overall_incidence_per_1000h: 10,
    incidence_per_1000h: 10,
    burden_per_1000h: 20,
    mean_severity_days: 2,
  });
  const row = (id: string, alias: string): TeamComparisonRow => ({
    comparison_id: id,
    team_alias: alias,
    included_exposure_status: "included",
    exposure_hours: 100,
    distance_km: 50,
    match_hours: 20,
    training_hours: 80,
    all: null,
    match: setting("Match"),
    training: { ...setting("Training"), setting: "training" },
  });
  const rows = buildReportComparisonRows({
    rows: [row("comparison-private-1", "Team Q"), row("comparison-private-2", "Team R")],
    scope: "team",
    subjectName: "Harbour RFC",
    viewerComparisonId: "comparison-private-1",
  });

  assert.deepEqual(rows.map((item) => item.label), ["Harbour RFC", "Team R"]);
  assert.doesNotMatch(JSON.stringify(rows), /comparison-private|Team Q/);
  const model = buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC", "Team Q", "Team R"], comparisonRows: rows });
  assert.equal(model.comparisonHeatmap[1].label, "Team R");
  assert.throws(() => assertReportModelPrivacy({ ...model, limitations: ["Team R is Rivals RFC"] }, model.subjectName, ["Rivals RFC", "Team R"]), /protected|another club/);
  assert.throws(() => assertReportModelPrivacy({ ...model, comparisonHeatmap: [{ ...rows[1], label: "Rivals RFC" }] }, model.subjectName, ["Rivals RFC"]), /display label/);
  assert.throws(() => buildReportComparisonRows({ rows: [row("comparison-private-2", "Rivals RFC")], scope: "league", subjectName: "URC" }), /approved dashboard alias/);
});

test("preserves released nulls and blocks rate deltas without comparable exposure", () => {
  const current = dashboardFixture({
    headline: [
      { key: "incidence", label: "Time-loss incidence", value: null, unit: "per 1000 hours", denominator: 8400, formula: "released incidence per 1000 exposure hours" },
    ],
    coverage: { ...dashboardFixture().coverage, included_exposure_status: "temporary estimate" },
  });
  const model = buildReportModel({ current, prior: priorDashboardFixture(), expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] });
  assert.equal(model.snapshotMetrics[0].value, null);
  assert.equal(model.seasonComparison.headline[0].delta, null);
  assert.equal(model.seasonComparison.headline[0].deltaReason, "Exposure denominator is not comparable");
  assert.equal(model.estimateOrIncompleteCoverage, true);
  assert.match(model.coverageNote ?? "", /Temporary league-mean exposure estimate/);
});

test("calculates missing monthly incidence from released counts and hours and preserves source warnings safely", () => {
  const current = dashboardFixture({
    preliminary_monthly_rates: [{ month: "Sep 2025", contributor_count: 14, exposure_hours: 1000, time_loss_injuries: 10, days_lost: 50, incidence_per_1000h: 10, burden_per_1000h: 50, qualification: "Preliminary contributor-aligned monthly rates." }],
    coverage: { ...dashboardFixture().coverage, data_quality_warnings: ["Rivals RFC retains a source distance anomaly."] },
  });
  const model = buildReportModel({ current, prior: null, expectedScope: "team", expectedSeason: current.season, subjectName: current.team, protectedTerms: ["Rivals RFC"] });
  assert.deepEqual(model.preliminaryMonthlyRates, current.preliminary_monthly_rates);
  assert.equal(model.monthlyInjuryPattern[0].incidencePer1000h, 5);
  assert.equal(model.monthlyInjuryPattern[0].overallIncidencePer1000h, 4 / 600 * 1000);
  assert.deepEqual(model.exposure.dataQualityWarnings, ["A club retains a source distance anomaly."]);
});

test("carries released HSR values and placeholder status into the exposure export", () => {
  const current = dashboardFixture({
    coverage: {
      ...dashboardFixture().coverage,
      hsr_distance_km: 6600,
      hsr_percentage: 5.5,
      is_imputed: true,
      display_note: "League-mean placeholder pending source data.",
      hsr_source_status: "placeholder",
    },
    monthly: [{
      ...dashboardFixture().monthly[0],
      hsr_distance_km: 550,
      hsr_percentage: 5.5,
      is_imputed: true,
      imputation_method: "league_mean_paired_hsr_percentage",
      display_note: "League-mean placeholder pending source data.",
      hsr_source_status: "placeholder",
    }],
  });
  const model = buildReportModel({
    current,
    prior: null,
    expectedScope: "team",
    expectedSeason: "2025-26",
    subjectName: "Harbour RFC",
    protectedTerms: ["Rivals RFC"],
  });

  assert.equal(model.exposure.totalHsrDistanceKm, 6600);
  assert.equal(model.exposure.totalHsrPercentage, 5.5);
  assert.equal(model.exposure.monthly[0].isImputed, true);
  assert.equal(model.exposure.monthly[0].displayNote, "League-mean placeholder pending source data.");
});

test("keeps released month rows in chronological order when labels are presentation text", () => {
  const rows = dashboardFixture().monthly;
  const current = dashboardFixture({
    monthly: [
      { ...rows[0], month: "Apr 2026" },
      { ...rows[1], month: "Sep 2025" },
      { ...rows[0], month: "Jan 2026" },
    ],
  });
  const model = buildReportModel({ current, prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] });

  assert.deepEqual(model.monthlyInjuryPattern.map((row) => row.month), ["Sep 2025", "Jan 2026", "Apr 2026"]);
  assert.deepEqual(model.exposure.monthly.map((row) => row.month), ["Sep 2025", "Jan 2026", "Apr 2026"]);
});

test("withholds deltas when definitions, windows or case denominators differ", () => {
  const current = dashboardFixture({
    headline: [
      { key: "count", label: "Count", value: 5, unit: "injuries", formula: "current definition" },
      { key: "severity_mean_days", label: "Mean severity", value: 10, unit: "days", formula: "known days / known injuries" },
    ],
  });
  const prior = priorDashboardFixture({
    analysis_window: { start: "2024-08-01", end: "2025-06-30", basis: "different lineage text is allowed" },
    headline: [
      { key: "count", label: "Count", value: 4, unit: "cases", formula: "prior definition" },
      { key: "severity_mean_days", label: "Mean severity", value: 8, unit: "days", formula: "known days / known injuries", denominator: 3 },
    ],
  });
  const model = buildReportModel({ current, prior, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] });

  assert.equal(model.seasonComparison.headline[0].deltaReason, "Metric definition changed");
  assert.equal(model.seasonComparison.headline[1].deltaReason, "Analysis windows are not comparable");

  const sameWindow = buildReportModel({ current, prior: { ...prior, analysis_window: { start: "2024-07-01", end: "2025-06-30", basis: "different lineage text is allowed" } }, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] });
  assert.equal(sameWindow.seasonComparison.headline[1].deltaReason, "Case denominator is not comparable");
});

test("requires exact scope, season and subject identity", () => {
  assert.throws(() => buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "league", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] }), /scope/);
  assert.throws(() => buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "team", expectedSeason: "2024-25", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] }), /season/);
  assert.throws(() => buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Rivals RFC", protectedTerms: ["Harbour RFC"] }), /subject/);
});

test("refuses an unapproved prior release", () => {
  const current = dashboardFixture({ prior_season: { season: "2024-25", status: "pending", note: "Not released." } });
  assert.throws(() => buildReportModel({ current, prior: priorDashboardFixture(), expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] }), /not approved/);
});

test("restores enabled sections in canonical order", () => {
  assert.deepEqual(DEFAULT_REPORT_SECTION_IDS, ["cover", "season-pattern", "severity-contact", "injury-location", "common-injuries", "diagnosis-matrix", "impact-matrices", "illnesses", "injury-types", "exposure", "team-comparison", "season-methodology", "closing"]);
  assert.deepEqual(REPORT_SECTION_LABELS, {
    cover: "Cover",
    "season-pattern": "Season Overview",
    "severity-contact": "Severity And Mechanism",
    "injury-location": "Injury Location",
    "common-injuries": "Most Common Injuries",
    "diagnosis-matrix": "Risk Matrix: Diagnosis",
    illnesses: "Most Common Illnesses",
    "impact-matrices": "Risk Matrix: Location And Type",
    "injury-types": "Injury Types",
    exposure: "Exposure",
    "team-comparison": "Team Comparison",
    "season-methodology": "Season Comparison",
    closing: "Closing",
  });
  assert.deepEqual(
    filterReportSectionIds(["season-methodology", "cover", "exposure", "cover"]),
    ["cover", "exposure", "season-methodology"],
  );
});

test("rejects protected team text before it can reach a team report model", () => {
  const current = dashboardFixture({ limitations: ["Rivals RFC uses Team A, team-internal-77 and compare-93."] });
  assert.throws(() => buildReportModel({
    current,
    prior: null,
    expectedScope: "team",
    expectedSeason: "2025-26",
    subjectName: "Harbour RFC",
    protectedTerms: ["Rivals RFC", "team-internal-77", "compare-93", "Team A"],
  }), /protected|another club/);
});

test("rejects copied protected free text and requires a denylist", () => {
  const current = dashboardFixture({ method: ["Rivals RFC supplied the source."], limitations: [] });
  assert.throws(() => buildReportModel({ current, prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] }), /another club/);
  assert.throws(() => buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: [] }), /requires protected terms/);
});

test("rejects forbidden identifiers for team and league models without echoing values", () => {
  const teamModel = buildReportModel({ current: dashboardFixture(), prior: null, expectedScope: "team", expectedSeason: "2025-26", subjectName: "Harbour RFC", protectedTerms: ["Rivals RFC"] });
  const leagueModel = { ...teamModel, scope: "league" as const, subjectName: "URC" };
  for (const model of [teamModel, leagueModel]) {
    for (const field of ["player_id", "playerId", "PlayerID", "player_identifier", "team_key", "teamId", "team_alias", "comparison_id", "viewer_comparison_id"]) {
      const unsafe = { ...model, [field]: "private-player-sentinel" } as unknown as typeof model;
      assert.throws(() => assertReportModelPrivacy(unsafe, model.subjectName, ["Rivals RFC"]), (error: Error) => !error.message.includes("private-player-sentinel"));
    }
  }
});
