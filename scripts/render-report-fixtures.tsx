/** Test-only renderer for visual PDF QA. It never enters the application bundle. */
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";
import { buildSync } from "esbuild";

const root = process.cwd();
const temporaryDirectory = path.join(root, "tmp", "report-fixture-renderer");
const runner = path.join(temporaryDirectory, "runner.mjs");

const source = `
  import React from "react";
  import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
  import path from "node:path";
  import { renderToBuffer } from "@react-pdf/renderer";
  import { ReportDocument } from "@/components/report/report-document";
  import { buildReportModel } from "@/lib/report-model";
  import { parseDashboardReaderRow } from "@/lib/reporting";
  const headlineValue = (dashboard, key) => dashboard.headline.find((metric) => metric.key === key)?.value ?? null;
  const impactValue = (dashboard, setting) => {
    if (setting === "all") return {
      time_loss_incidence_per_1000h: headlineValue(dashboard, "incidence_per_1000h"),
      mean_severity_days: headlineValue(dashboard, "severity_mean_days"),
      burden_per_1000h: headlineValue(dashboard, "burden_per_1000h"),
      time_loss_injuries: headlineValue(dashboard, "time_loss_injuries"),
      exposure_hours: dashboard.coverage.hours ?? null,
    };
    const row = dashboard.setting_metrics.find((metric) => metric.setting === setting);
    return {
      time_loss_incidence_per_1000h: row?.incidence_per_1000h ?? null,
      mean_severity_days: row?.mean_severity_days ?? null,
      burden_per_1000h: row?.burden_per_1000h ?? null,
      time_loss_injuries: row?.time_loss_injuries ?? null,
      exposure_hours: row?.exposure_hours ?? null,
    };
  };
  const topDiagnoses = (dashboard, setting) => dashboard.injury_profiles
    .filter((row) => row.dimension === "diagnosis" && row.setting === setting && row.time_loss_injuries > 0)
    .sort((left, right) => right.time_loss_injuries - left.time_loss_injuries || (right.burden_per_1000h ?? 0) - (left.burden_per_1000h ?? 0) || left.label.localeCompare(right.label))
    .slice(0, 3)
    .map((row, index) => ({ rank: index + 1, diagnosis: row.label, time_loss_injuries: row.time_loss_injuries, incidence_per_1000h: row.incidence_per_1000h, burden_per_1000h: row.burden_per_1000h }));
  const buildSeasonComparison = (previous, current, scope) => {
    const kpiDefinitions = [
      ["time_loss_incidence", "TL injury incidence", "incidence_per_1000h"],
      ["mean_severity", "Mean severity", "severity_mean_days"],
      ["injury_burden", "Injury burden", "burden_per_1000h"],
      ["time_loss_injuries", "Time-loss injuries", "time_loss_injuries"],
    ];
    const kpis = kpiDefinitions.map(([key, label, metricKey]) => {
      const previousValue = headlineValue(previous, metricKey), currentValue = headlineValue(current, metricKey);
      const improvement = previousValue === null || previousValue === 0 || currentValue === null ? null : 100 * (previousValue - currentValue) / previousValue;
      const unit = current.headline.find((metric) => metric.key === metricKey)?.unit ?? "value";
      return { key, label, previous: { value: previousValue, unit }, current: { value: currentValue, unit }, outcome_improvement_percent: improvement };
    });
    const settings = [["all", "Overall"], ["match", "Match"], ["training", "Training"]];
    const monthKeys = ["2024-09", "2024-10", "2024-11", "2024-12", "2025-01", "2025-02", "2025-03", "2025-04", "2025-05", "2025-06"];
    const monthLabels = ["Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun"];
    return {
      rule_version: "season_comparison_reporting_2026_08_31_v4",
      scope,
      previous_season: "2024-25",
      current_season: "2025-26",
      kpis,
      impact: settings.map(([setting, label]) => ({ setting, label, previous: impactValue(previous, setting), current: impactValue(current, setting) })),
      monthly: monthKeys.map((month_key, index) => ({ month_key, label: monthLabels[index], previous_time_loss_injuries: previous.monthly[index]?.time_loss_injuries ?? 0, current_time_loss_injuries: current.monthly[index]?.time_loss_injuries ?? 0 })),
      diagnoses: settings.map(([setting, label]) => ({ setting, label, previous: topDiagnoses(previous, setting), current: topDiagnoses(current, setting) })),
      exposure: {
        previous: { exposure_hours: previous.coverage.hours ?? null, status: previous.coverage.hours ? "available" : "unavailable", qualification: null },
        current: { exposure_hours: current.coverage.hours ?? null, status: current.coverage.hours ? "available" : "unavailable", qualification: null },
      },
    };
  };
  const fixtures = [
    { file: "leinster_dashboard_2025-26.json", priorFile: "leinster_dashboard_2024-25.json", scope: "team", subjectName: "Leinster", crest: "public/images/Team Crests/LeinsterRugby.svg.png", accentColour: "#003DA5", output: "leinster-2025-26-v1.0-2026-08-31.pdf" },
  ];
  const reportingDirectory = path.join(process.cwd(), "content/reporting");
  const reportingFiles = (await readdir(reportingDirectory)).filter((file) => file.endsWith(".json"));
  const protectedTerms = [...new Set((await Promise.all(reportingFiles.map(async (file) => {
    const item = JSON.parse(await readFile(path.join(reportingDirectory, file), "utf8"));
    return item.team;
  }))).filter(Boolean).concat(["Team A", "comparison-id", "team-key"]))];
  const outputDirectory = path.join(process.cwd(), "output/pdf");
  const teamFixtureFiles = reportingFiles.filter((file) => file.endsWith("_dashboard_2025-26.json") && !file.startsWith("urc_"));
  const currentTeamRows = await Promise.all(teamFixtureFiles.map(async (file) => {
    const source = JSON.parse(await readFile(path.join(reportingDirectory, file), "utf8"));
    const match = source.setting_metrics.find((row) => row.setting === "match");
    const training = source.setting_metrics.find((row) => row.setting === "training");
    const all = source.setting_metrics.find((row) => row.setting === "all");
    return { label: "Anonymous fixture club", team: source.team, exposureHours: source.coverage.hours ?? null, distanceKm: source.coverage.distance_km ?? null, allIncidencePer1000h: all?.incidence_per_1000h ?? null, allBurdenPer1000h: all?.burden_per_1000h ?? null, matchIncidencePer1000h: match?.incidence_per_1000h ?? null, matchBurdenPer1000h: match?.burden_per_1000h ?? null, trainingIncidencePer1000h: training?.incidence_per_1000h ?? null, trainingBurdenPer1000h: training?.burden_per_1000h ?? null };
  }));
  const leagueSource = JSON.parse(await readFile(path.join(reportingDirectory, "urc_dashboard_2025-26.json"), "utf8"));
  const leagueAll = leagueSource.setting_metrics.find((row) => row.setting === "all");
  const leagueMatch = leagueSource.setting_metrics.find((row) => row.setting === "match");
  const leagueTraining = leagueSource.setting_metrics.find((row) => row.setting === "training");
  const comparisonBenchmarks = { allIncidencePer1000h: leagueAll?.incidence_per_1000h ?? null, allBurdenPer1000h: leagueAll?.burden_per_1000h ?? null, matchIncidencePer1000h: leagueMatch?.incidence_per_1000h ?? null, matchBurdenPer1000h: leagueMatch?.burden_per_1000h ?? null, trainingIncidencePer1000h: leagueTraining?.incidence_per_1000h ?? null, trainingBurdenPer1000h: leagueTraining?.burden_per_1000h ?? null };
  await mkdir(outputDirectory, { recursive: true });
  const heroDataUri = "data:image/jpeg;base64," + (await readFile(path.join(process.cwd(), "public/images/report/urc-injury-surveillance-hero.jpg"))).toString("base64");
  const urcLogoDataUri = "data:image/png;base64," + (await readFile(path.join(process.cwd(), "public/images/URC.png"))).toString("base64");
  const partnerLogoDataUri = "data:image/png;base64," + (await readFile(path.join(process.cwd(), "public/images/UCDLogo.png"))).toString("base64");
  for (let index = 0; index < fixtures.length; index += 1) {
    const fixture = fixtures[index];
    const raw = JSON.parse(await readFile(path.join(reportingDirectory, fixture.file), "utf8"));
    const parsed = parseDashboardReaderRow(raw, raw.season, fixture.scope);
    const current = { ...parsed, scope: fixture.scope, team: fixture.subjectName };
    const priorRaw = JSON.parse(await readFile(path.join(reportingDirectory, fixture.priorFile), "utf8"));
    const prior = { ...parseDashboardReaderRow(priorRaw, priorRaw.season, fixture.scope), scope: fixture.scope, team: fixture.subjectName };
    const crestDataUri = "data:image/png;base64," + (await readFile(path.join(process.cwd(), fixture.crest))).toString("base64");
    const comparisonRows = currentTeamRows.map((row, index) => ({
      label: row.team === fixture.subjectName ? fixture.subjectName : "Club " + String(index + 1).padStart(2, "0"),
      isSubject: fixture.scope === "team" && row.team === fixture.subjectName,
      exposureHours: row.exposureHours,
      distanceKm: row.distanceKm,
      allIncidencePer1000h: row.allIncidencePer1000h,
      allBurdenPer1000h: row.allBurdenPer1000h,
      matchIncidencePer1000h: row.matchIncidencePer1000h,
      matchBurdenPer1000h: row.matchBurdenPer1000h,
      trainingIncidencePer1000h: row.trainingIncidencePer1000h,
      trainingBurdenPer1000h: row.trainingBurdenPer1000h,
    }));
    const denylist = protectedTerms.filter((term) => term !== fixture.subjectName);
    const model = buildReportModel({ current, prior, expectedScope: fixture.scope, expectedSeason: current.season, subjectName: fixture.subjectName, protectedTerms: denylist, exportedAt: "2026-08-31T12:00:00Z", comparisonRows, comparisonBenchmarks, seasonComparisonVisuals: buildSeasonComparison(priorRaw, raw, fixture.scope), brand: { crestDataUri, accentColour: fixture.accentColour, heroDataUri, urcLogoDataUri, partnerLogoDataUri } });
    const output = path.join(outputDirectory, fixture.output);
    await writeFile(output, Buffer.from(await renderToBuffer(React.createElement(ReportDocument, { model }))));
    process.stdout.write(output + "\\n");
  }
`;

mkdirSync(temporaryDirectory, { recursive: true });
buildSync({
  stdin: { contents: source, resolveDir: root, sourcefile: "render-report-fixtures.tsx", loader: "tsx" },
  bundle: true,
  format: "esm",
  platform: "node",
  outfile: runner,
  external: ["@react-pdf/renderer", "pg"],
  alias: { "@": root, "server-only": path.join(root, "node_modules/server-only/empty.js") },
});
execFileSync("node", [runner], { stdio: "inherit" });
