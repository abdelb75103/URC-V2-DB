import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const workDirectory = path.join(process.cwd(), "tmp", "report-pdf-test");
const bundledDocument = path.join(workDirectory, "report-document.mjs");
const renderedPdf = path.join(workDirectory, "report.pdf");

const syntheticModel = {
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
  snapshotMetrics: [{ key: "recorded", label: "Recorded injuries", value: 74, unit: "injuries", formula: "released count" }],
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
  injuryProfile: { diagnoses: [], bodyLocations: [], injuryTypes: [], injuryTypeFamilies: [] },
  exposure: { totalHours: 8400, matchHours: 2100, trainingHours: 6300, totalDistanceKm: null, monthly: [] },
  comparisonHeatmap: Array.from({ length: 16 }, (_, index) => ({
    label: index === 0 ? "Harbour RFC" : "private-club-sentinel",
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
  seasonComparison: { priorSeason: "2024-25", status: "frozen", note: "Frozen approved release.", headline: [], settings: [] },
  method: ["Released aggregate metrics only."],
  limitations: ["Not available values are not inferred."],
};

function renderPdf(sectionIds?: string[]) {
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
    const model = ${JSON.stringify(syntheticModel)};
    const buffer = await renderToBuffer(React.createElement(ReportDocument, { model, enabledSectionIds: ${JSON.stringify(sectionIds)} }));
    writeFileSync(${JSON.stringify(renderedPdf)}, buffer);
    process.stdout.write(JSON.stringify({ pages: (buffer.toString("latin1").match(/\\/Type\\s+\\/Page(?!s)\\b/g) || []).length, bytes: buffer.length }));
  `;
  const output = execFileSync("node", ["--input-type=module", "--eval", program], { encoding: "utf8", maxBuffer: 2_000_000 });
  const result = JSON.parse(output) as { pages: number; bytes: number };
  const text = execFileSync("pdftotext", [renderedPdf, "-"], { encoding: "utf8" });
  const coverText = execFileSync("pdftotext", ["-f", "1", "-l", "1", renderedPdf, "-"], { encoding: "utf8" });
  const overviewText = execFileSync("pdftotext", ["-f", "2", "-l", "2", renderedPdf, "-"], { encoding: "utf8" });
  return { ...result, text, coverText, overviewText };
}

test("the full document emits one A4 page for each stable section", () => {
  const result = renderPdf();
  assert.equal(result.pages, 10);
  assert.ok(result.bytes > 5_000);
  assert.match(result.text, /1,622 days\s*\/1,000 h/);
  assert.match(result.coverText, /Injury surveillance/);
  assert.doesNotMatch(result.coverText, /Recorded injuries|Overall incidence|Burden/);
  assert.match(result.overviewText, /Season overview/);
  assert.match(result.overviewText, /Recorded injuries/);
});

test("filtering sections removes pages and recalculates the document", () => {
  const result = renderPdf(["cover", "season-methodology"]);
  assert.equal(result.pages, 2);
});

test("rendered document metadata and source model do not contain protected sentinels", () => {
  const result = renderPdf();
  assert.doesNotMatch(JSON.stringify(syntheticModel), /Rivals RFC|Team A|comparison-private-sentinel/);
  assert.doesNotMatch(result.text, /Rivals RFC|Team A|comparison-private-sentinel|private-club-sentinel/);
  rmSync(workDirectory, { recursive: true, force: true });
});
