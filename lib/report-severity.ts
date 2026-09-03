import type { ReportDistributionRow } from "./report-model-types";

const bands = [
  { key: "one_to_seven", label: "1-7 Days", sources: ["one_day", "two_to_three_days", "four_to_seven_days"] },
  { key: "eight_to_twenty_eight", label: "8-28 Days", sources: ["eight_to_twenty_eight_days"] },
  { key: "greater_than_twenty_eight", label: "Over 28 Days", sources: ["greater_than_twenty_eight_days"] },
] as const;

/** Match the dashboard's three known-duration bands, scoped before aggregation. */
export function reportSeverityBands(
  rows: readonly ReportDistributionRow[],
  setting: "all" | "match" | "training",
): ReportDistributionRow[] {
  const scoped = rows.filter((row) => row.setting === setting);
  if (!scoped.length) return [];
  return bands.map(({ key, label, sources }) => {
    const members = scoped.filter((row) => (sources as readonly string[]).includes(row.key));
    return {
      key, label, setting,
      recordedInjuries: members.reduce((sum, row) => sum + row.recordedInjuries, 0),
      timeLossInjuries: members.reduce((sum, row) => sum + row.timeLossInjuries, 0),
      daysLost: members.some((row) => row.daysLost === null)
        ? null : members.reduce((sum, row) => sum + (row.daysLost ?? 0), 0),
    };
  });
}
