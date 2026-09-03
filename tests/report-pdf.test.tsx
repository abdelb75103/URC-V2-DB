import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import type { ReportModel } from "../lib/report-model-types";

const workDirectory = path.join(process.cwd(), "tmp", "report-pdf-test");
const bundledDocument = path.join(workDirectory, "report-document.mjs");
const renderedPdf = path.join(workDirectory, "report.pdf");

const syntheticComparison: NonNullable<ReportModel["seasonComparisonVisuals"]> = {
  rule_version: "season_comparison_reporting_2026_08_31_v4",
  scope: "team",
  previous_season: "2024-25",
  current_season: "2025-26",
  kpis: [
    { key: "time_loss_incidence", label: "TL injury incidence", previous: { value: 10, unit: "TL injuries per 1,000 player-hours" }, current: { value: 8, unit: "TL injuries per 1,000 player-hours" }, outcome_improvement_percent: 20 },
    { key: "mean_severity", label: "Mean severity", previous: { value: 30, unit: "days lost per injury" }, current: { value: 24, unit: "days lost per injury" }, outcome_improvement_percent: 20 },
    { key: "injury_burden", label: "Injury burden", previous: { value: 300, unit: "days lost per 1,000 player-hours" }, current: { value: 192, unit: "days lost per 1,000 player-hours" }, outcome_improvement_percent: 36 },
    { key: "time_loss_injuries", label: "Time-loss injuries", previous: { value: 40, unit: "TL injuries" }, current: { value: 32, unit: "TL injuries" }, outcome_improvement_percent: 20 },
  ],
  impact: (["all", "match", "training"] as const).map((setting) => ({
    setting,
    label: setting === "all" ? "Overall" : setting[0].toUpperCase() + setting.slice(1),
    previous: { time_loss_incidence_per_1000h: 10, mean_severity_days: 30, burden_per_1000h: 300, time_loss_injuries: 40, exposure_hours: 4_000 },
    current: { time_loss_incidence_per_1000h: 8, mean_severity_days: 24, burden_per_1000h: 192, time_loss_injuries: 32, exposure_hours: 4_000 },
  })),
  monthly: ["Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun"].map((label, index) => ({ month_key: `2024-${String((index + 8) % 12 + 1).padStart(2, "0")}`, label, previous_time_loss_injuries: 5 + index % 3, current_time_loss_injuries: 3 + index % 4 })),
  diagnoses: (["all", "match", "training"] as const).map((setting) => ({
    setting,
    label: setting === "all" ? "Overall" : setting[0].toUpperCase() + setting.slice(1),
    previous: ["Hamstring Injury", "Concussion", "Ankle Injury"].map((diagnosis, index) => ({ rank: index + 1, diagnosis, time_loss_injuries: 6 - index, incidence_per_1000h: 2 - index / 2, burden_per_1000h: 30 - index * 5 })),
    current: ["Concussion", "Hamstring Injury", "Shoulder Injury"].map((diagnosis, index) => ({ rank: index + 1, diagnosis, time_loss_injuries: 5 - index, incidence_per_1000h: 1.8 - index / 2, burden_per_1000h: 25 - index * 5 })),
  })),
  exposure: {
    previous: { exposure_hours: 4_000, status: "available", qualification: null },
    current: { exposure_hours: 4_000, status: "available", qualification: null },
  },
};

const syntheticModel: ReportModel = {
  schemaVersion: "urc-report-v1",
  reportVersion: "1.0",
  exportedAt: "2026-08-31T00:00:00Z",
  dataGeneratedAt: "2026-08-30T00:00:00Z",
  scope: "team",
  subjectName: "Harbour RFC",
  season: "2025-26",
  brand: { crestDataUri: null, accentColour: "#00B9D8" },
  analysisWindow: { start: "2025-07-01", end: "2026-06-30", basis: "season" },
  estimateOrIncompleteCoverage: false,
  coverageNote: null,
  snapshotMetrics: [
    { key: "recorded_injuries", label: "Recorded injuries", value: 74, unit: "injuries", formula: "released count" },
    { key: "time_loss_injuries", label: "Time-loss injuries", value: 52, unit: "injuries", formula: "released count" },
    { key: "incidence_per_1000h", label: "Incidence", value: 6.2, unit: "per 1,000 h", formula: "released rate" },
    { key: "overall_incidence_per_1000h", label: "Overall incidence", value: 8.8, unit: "per 1,000 h", formula: "released rate" },
    { key: "burden_per_1000h", label: "Burden", value: 80.1, unit: "days per 1,000 h", formula: "released rate" },
  ],
  preliminaryMonthlyRates: [],
  monthlyInjuryPattern: [{ month: "2025-08", recordedInjuries: 5, timeLossInjuries: 4, daysLost: 82, overallIncidencePer1000h: 10, incidencePer1000h: 8, burdenPer1000h: 164 }],
  matchTraining: [{
    setting: "match",
    label: "Match",
    recordedInjuries: 26,
    timeLossInjuries: 25,
    daysLost: 681,
    exposureHours: 420,
    overallIncidencePer1000h: 61.9,
    incidencePer1000h: 59.5,
    burdenPer1000h: 1622,
    meanSeverityDays: 27.2,
  }],
  severityDistribution: [],
  contactDistribution: [],
  illness: {
    summary: { setting: "all", recorded_illnesses: 12, known_duration_illnesses: 8, days_lost: 20, exposure_hours: 8400, incidence_per_1000h: 1.43, burden_per_1000h: 2.38, mean_severity_days: 2.5, qualification: "Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training." },
    profiles: [{ code: "respiratory", label: "Respiratory Illness", setting: "all", recorded_illnesses: 12, known_duration_illnesses: 8, days_lost: 20, exposure_hours: 8400, incidence_per_1000h: 1.43, burden_per_1000h: 2.38, mean_severity_days: 2.5 }],
  },
  injuryProfile: { diagnoses: [], bodyLocations: [], injuryTypes: [], injuryTypeFamilies: [] },
  injuryImpact: { diagnoses: [], bodyLocations: [], injuryTypes: [] } as ReportModel["injuryImpact"],
  exposure: {
    totalHoursLabel: "Total Hours",
    totalDistanceLabel: "Total Distance",
    dataQualityWarnings: [],
    totalHours: 8400,
    matchHours: 2100,
    trainingHours: 6300,
    totalDistanceKm: 120000,
    totalHsrDistanceKm: 6600,
    totalHsrPercentage: 5.5,
    hsrIsImputed: true,
    hsrDisplayNote: "League-mean placeholder pending source data.",
    hsrSourceStatus: "placeholder",
    monthly: [{
      month: "2025-09",
      exposureHours: 700,
      distanceKm: 10000,
      hsrDistanceKm: 550,
      hsrPercentage: 5.5,
      isImputed: true,
      imputationMethod: "league_mean_paired_hsr_percentage",
      displayNote: "League-mean placeholder pending source data.",
      hsrSourceStatus: "placeholder",
    }],
  },
  comparisonHeatmap: Array.from({ length: 16 }, (_, index) => ({
    label: index === 0 ? "Harbour RFC" : `Team ${String.fromCharCode(65 + index)}`,
    isSubject: index === 0,
    exposureHours: 8000 + index,
    distanceKm: 100000 + index,
    allIncidencePer1000h: 6 + index / 3,
    allBurdenPer1000h: 100 + index * 3,
    matchIncidencePer1000h: 8 + index / 2,
    matchBurdenPer1000h: 140 + index * 5,
    trainingIncidencePer1000h: 4 + index / 4,
    trainingBurdenPer1000h: 72 + index * 2,
  })),
  comparisonBenchmarks: { allIncidencePer1000h: 8, allBurdenPer1000h: 120, matchIncidencePer1000h: 10, matchBurdenPer1000h: 200, trainingIncidencePer1000h: 5, trainingBurdenPer1000h: 100 },
  seasonComparison: { comparisonSeason: "2024-25", status: "frozen", note: "Frozen approved release.", headline: [], settings: [] },
  seasonComparisonVisuals: syntheticComparison,
  method: ["Released aggregate metrics only."],
  limitations: ["Not available values are not inferred."],
};

function renderPdf(sectionIds?: string[], model: ReportModel = syntheticModel) {
  mkdirSync(workDirectory, { recursive: true });
  execFileSync("./node_modules/.bin/esbuild", [
    "components/report/report-document.tsx", "--bundle", "--platform=node", "--format=esm",
    "--external:@react-pdf/renderer", "--alias:@=.", `--outfile=${bundledDocument}`,
  ], { stdio: "pipe" });
  const program = `
    import React from "react";
    import { writeFileSync } from "node:fs";
    import { renderToBuffer } from "@react-pdf/renderer";
    import { ReportDocument } from ${JSON.stringify(`./${path.relative(process.cwd(), bundledDocument)}`)};
    const model = ${JSON.stringify(model)};
    const buffer = await renderToBuffer(React.createElement(ReportDocument, { model, enabledSectionIds: ${JSON.stringify(sectionIds)} }));
    writeFileSync(${JSON.stringify(renderedPdf)}, buffer);
    process.stdout.write(JSON.stringify({ pages: (buffer.toString("latin1").match(/\\/Type\\s+\\/Page(?!s)\\b/g) || []).length, bytes: buffer.length }));
  `;
  const output = execFileSync("node", ["--input-type=module", "--eval", program], { encoding: "utf8", maxBuffer: 2_000_000 });
  const result = JSON.parse(output) as { pages: number; bytes: number };
  const text = execFileSync("pdftotext", [renderedPdf, "-"], { encoding: "utf8" });
  const pageText = (page: number) => execFileSync("pdftotext", ["-f", String(page), "-l", String(page), renderedPdf, "-"], { encoding: "utf8" });
  const coverText = pageText(1);
  const overviewText = result.pages >= 2 ? pageText(2) : "";
  const comparisonText = result.pages >= 12
    ? execFileSync("pdftotext", ["-f", "12", "-l", "12", renderedPdf, "-"], { encoding: "utf8" })
    : "";
  return { ...result, text, pageText, coverText, overviewText, comparisonText };
}

test("the full document emits one A4 page for each stable section", () => {
  const result = renderPdf();
  assert.equal(result.pages, 13);
  assert.ok(result.bytes > 5_000);
  assert.match(result.text, /1,622 days\s*\/1,000 h/);
  assert.match(result.coverText, /\bSCRIIPT\b/);
  assert.doesNotMatch(result.coverText, /Recorded injuries|Overall incidence|Burden/);
  assert.match(result.overviewText, /Season Overview/);
  assert.match(result.overviewText, /Overall Injuries/);
  assert.match(result.overviewText, /Injury Impact By Season/);
  assert.match(result.pageText(6), /Risk Matrix/);
  assert.match(result.pageText(7), /Risk Matrix/);
  assert.match(result.pageText(8), /Most Common Illnesses/);
  assert.match(result.pageText(8), /Respiratory Illness/);
  assert.match(result.pageText(10), /HSR Distance/);
  assert.match(result.pageText(10), /6,600/);
  assert.match(result.pageText(10), /League-mean placeholder/);
  assert.match(result.pageText(11), /Team B/);
  assert.doesNotMatch(result.text, /Overall Incidence Ladder|Anonymous club \d|Impact Matrices/);
  assert.match(result.comparisonText, /Injuries By Month/);
  assert.match(result.comparisonText, /Most Common Diagnosis/);
  assert.match(result.comparisonText, /Decreased/);
  assert.doesNotMatch(result.comparisonText, /Improved/);
  assert.doesNotMatch(result.comparisonText, /Publication record/);
  assert.match(result.text, /End of report/i);
  assert.match(result.pageText(13), /\bSCRIIPT\b/);
  assert.doesNotMatch(result.text, /approved releases?|released|arc length|key numbers run|bars share one scale/i);
  for (const page of [1, 13]) {
    const cover = result.pageText(page).replace(/\s+/g, " ");
    assert.match(cover, /SCRIIPT Surveillance Of Continental Rugby Injury, Illness And Performance Tracking/i);
    assert.doesNotMatch(cover, /Injury surveillance|INJURY SURVEILLANCE|SCRIIPT Project|Source 30 Aug|\d+ \/ 13/);
  }
  assert.match(result.overviewText, /Source 30 Aug 2026/);
  assert.match(result.overviewText, /2 \/ 13/);
});

test("selected sections render in canonical PDF order", () => {
  const result = renderPdf(["season-methodology", "cover", "team-comparison"]);
  assert.equal(result.pages, 3);
  assert.match(result.pageText(1), /\bSCRIIPT\b/);
  assert.match(result.pageText(2), /Team Comparison/);
  assert.match(result.pageText(3), /Season Comparison/);
  assert.doesNotMatch(result.pageText(2), /Season Comparison/);
});

test("the PDF timeline displays both released incidence series without extra rate notes", () => {
  const result = renderPdf(["severity-contact"], {
    ...syntheticModel,
    monthlyInjuryPattern: [{ month: "Sep 2025", recordedInjuries: 20, timeLossInjuries: 12, daysLost: 50, overallIncidencePer1000h: 25, incidencePer1000h: 15, burdenPer1000h: null }],
    preliminaryMonthlyRates: [{ month: "2025-09", contributor_count: 14, exposure_hours: 800, time_loss_injuries: 8, days_lost: 40, incidence_per_1000h: 10, burden_per_1000h: 50, qualification: "Preliminary contributor-aligned rate." }],
  });
  assert.equal(result.pages, 1);
  assert.match(result.text, /Time Loss Incidence/);
  assert.match(result.text, /Overall Incidence/);
  assert.doesNotMatch(result.text, /preliminary contributor-aligned|Monthly incidence is not available/);
});

test("a dense diagnosis matrix keeps its complete key on its own page", () => {
  const diagnoses = Array.from({ length: 42 }, (_, index) => ({
    code: `diagnosis-${index + 1}`, label: `Diagnosis ${index + 1}`, setting: "all" as const,
    recordedInjuries: 1, timeLossInjuries: 1, daysLost: index + 1,
    incidencePer1000h: 0.2, burdenPer1000h: (index + 1) / 5, meanSeverityDays: index + 1,
  }));
  const result = renderPdf(["diagnosis-matrix"], {
    ...syntheticModel,
    injuryImpact: { ...syntheticModel.injuryImpact, diagnoses },
  });
  assert.equal(result.pages, 1);
  assert.match(result.text, /Diagnosis 1\b/);
  assert.match(result.text, /Diagnosis 42\b/);
});

test("copy cleanup preserves material qualifications and unavailable monthly exposure", () => {
  const model: ReportModel = {
    ...syntheticModel,
    exposure: {
      ...syntheticModel.exposure,
      dataQualityWarnings: ["Approved season totals include estimated exposure."],
      monthly: syntheticModel.exposure.monthly.map((row) => ({ ...row, exposureHours: null, distanceKm: null, hsrDistanceKm: null, hsrPercentage: null })),
    },
  };
  const result = renderPdf(["illnesses", "exposure"], model);
  assert.equal(result.pages, 2);
  const text = result.text.replace(/\s+/g, " ");
  assert.match(text, /season totals include estimated exposure/i);
  assert.match(text, /Monthly exposure data (?:is |are )?(?:not available|unavailable)/i);
  assert.match(text, /8,400/);
  assert.doesNotMatch(text, /Overall illness metrics use|Illness is not attributed/);
});

test("severity and contact show all three settings without raw severity slices or duplicate metrics", () => {
  const severityDistribution = (["all", "match", "training"] as const).flatMap((setting, index) => [
    { key: "one_day", label: "1 day", setting, recordedInjuries: 1 + index, timeLossInjuries: 1 + index, daysLost: 1 + index },
    { key: "two_to_three_days", label: "2-3 days", setting, recordedInjuries: 2, timeLossInjuries: 2, daysLost: 5 },
    { key: "four_to_seven_days", label: "4-7 days", setting, recordedInjuries: 3, timeLossInjuries: 3, daysLost: 15 },
    { key: "eight_to_twenty_eight_days", label: "8-28 days", setting, recordedInjuries: 4, timeLossInjuries: 4, daysLost: 50 },
    { key: "greater_than_twenty_eight_days", label: ">28 days", setting, recordedInjuries: 5, timeLossInjuries: 5, daysLost: 200 },
    { key: "unknown_or_censored", label: "Unknown or censored", setting, recordedInjuries: 77, timeLossInjuries: 77, daysLost: 0 },
  ]);
  const contactDistribution = (["all", "match", "training"] as const).flatMap((setting) => [
    { key: "contact", label: "Contact", setting, recordedInjuries: 10, timeLossInjuries: 10, daysLost: null },
    { key: "non_contact", label: "Non-contact", setting, recordedInjuries: 5, timeLossInjuries: 5, daysLost: null },
    { key: "unknown", label: "Unknown", setting, recordedInjuries: 2, timeLossInjuries: 2, daysLost: null },
  ]);
  const result = renderPdf(["severity-contact"], { ...syntheticModel, severityDistribution, contactDistribution });
  assert.equal(result.pages, 1);
  for (const label of ["1-7 Days", "8-28 Days", "Over 28 Days"]) {
    assert.equal(result.text.split(label).length - 1, 3, `${label} appears once for each setting`);
  }
  assert.equal(result.text.split("Unknown").length - 1, 3, "contact keeps its unclassified share");
  assert.doesNotMatch(result.text, /Unknown or censored|2-3 days|4-7 days|Match Versus Training|arc length/i);
});

test("rendered document metadata and source model do not contain protected sentinels", () => {
  const result = renderPdf();
  assert.doesNotMatch(JSON.stringify(syntheticModel), /Rivals RFC|comparison-private-sentinel/);
  assert.doesNotMatch(result.text, /Rivals RFC|comparison-private-sentinel|private-club-sentinel/);
  rmSync(workDirectory, { recursive: true, force: true });
});
