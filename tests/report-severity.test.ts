import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";
import { reportSeverityBands } from "../lib/report-severity";
import type { ReportDistributionRow } from "../lib/report-model-types";
import type { SeverityRow } from "../lib/reporting-types";

test("PDF severity equals the dashboard's three bands for each season and setting", () => {
  const files = readdirSync("content/reporting").filter((file) => /_dashboard_20(?:24-25|25-26)\.json$/.test(file));
  assert.equal(files.length, 34);
  for (const file of files) {
    const { severity_distribution: source } = JSON.parse(readFileSync(`content/reporting/${file}`, "utf8")) as { severity_distribution: SeverityRow[] };
    const rows: ReportDistributionRow[] = source.map((row) => ({
      key: row.key, label: row.label, setting: row.setting ?? "all",
      recordedInjuries: row.recorded_injuries, timeLossInjuries: row.time_loss_injuries, daysLost: row.days_lost ?? null,
    }));
    const before = structuredClone(rows);
    for (const setting of ["all", "match", "training"] as const) {
      const scoped = source.filter((row) => (row.setting ?? "all") === setting);
      const actual = reportSeverityBands(rows, setting);
      if (!scoped.length) {
        assert.deepEqual(actual, [], `${file} ${setting}: unavailable setting stays unavailable`);
        continue;
      }
      const expected = [
        scoped.filter((row) => ["one_day", "two_to_three_days", "four_to_seven_days"].includes(row.key)).reduce((sum, row) => sum + row.time_loss_injuries, 0),
        scoped.find((row) => row.key === "eight_to_twenty_eight_days")?.time_loss_injuries ?? 0,
        scoped.find((row) => row.key === "greater_than_twenty_eight_days")?.time_loss_injuries ?? 0,
      ];
      assert.deepEqual(actual.map((row) => row.label), ["1-7 Days", "8-28 Days", "Over 28 Days"]);
      assert.deepEqual(actual.map((row) => row.timeLossInjuries), expected, `${file} ${setting}`);
    }
    assert.deepEqual(rows, before, `${file}: source rows unchanged`);
  }
});

test("medical attention and censored cases never enter known-duration bands", () => {
  const row = (key: string, value: number, setting: ReportDistributionRow["setting"] = "all"): ReportDistributionRow => ({ key, label: key, setting, recordedInjuries: value, timeLossInjuries: value, daysLost: null });
  const rows = [row("one_day", 2), row("two_to_three_days", 3), row("four_to_seven_days", 4), row("eight_to_twenty_eight_days", 8), row("greater_than_twenty_eight_days", 9), row("unknown_or_censored", 70), row("zero_days_medical_attention_only", 50), row("one_day", 100, "match")];
  assert.deepEqual(reportSeverityBands(rows, "all").map((band) => band.timeLossInjuries), [9, 8, 9]);
  assert.deepEqual(reportSeverityBands(rows, "match").map((band) => band.timeLossInjuries), [100, 0, 0]);
  assert.deepEqual(reportSeverityBands(rows, "training"), []);
});
