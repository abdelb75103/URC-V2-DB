import assert from "node:assert/strict";
import test from "node:test";
import { assertReportModelPrivacy, buildReportModel, DEFAULT_REPORT_SECTION_IDS, filterReportSectionIds } from "../lib/report-model";
import { dashboardFixture, priorDashboardFixture } from "./report-fixtures";
import { buildReportComparisonRows } from "../lib/report-comparison";
import type { TeamComparisonRow } from "../lib/reporting-types";

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

test("rebuilds dashboard comparison rows with report-local anonymous labels", () => {
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

  assert.deepEqual(rows.map((item) => item.label), ["Harbour RFC", "Anonymous club 01"]);
  assert.doesNotMatch(JSON.stringify(rows), /comparison-private|Team Q|Team R/);
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

test("keeps the stable section order when filtering", () => {
  assert.deepEqual(DEFAULT_REPORT_SECTION_IDS, ["cover", "season-pattern", "severity-contact", "injury-location", "common-injuries", "impact-matrices", "injury-types", "exposure", "team-comparison", "season-methodology"]);
  assert.deepEqual(filterReportSectionIds(["season-methodology", "cover", "exposure"]), ["cover", "exposure", "season-methodology"]);
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
