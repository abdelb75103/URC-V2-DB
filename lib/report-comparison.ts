import "server-only";
import type { ReportComparisonBenchmarks, ReportComparisonRow, ReportScope } from "@/lib/report-model-types";
import type { SettingMetricRow, TeamComparisonRow } from "@/lib/reporting-types";

export function buildReportComparisonRows({
  rows,
  scope,
  subjectName,
  viewerComparisonId,
}: {
  rows: readonly TeamComparisonRow[];
  scope: ReportScope;
  subjectName: string;
  viewerComparisonId?: string | null;
}): ReportComparisonRow[] {
  if (scope === "team" && rows.length > 0) {
    const viewerRows = rows.filter((row) => row.comparison_id === viewerComparisonId);
    if (viewerRows.length !== 1) throw new Error("Team report comparison does not identify exactly one viewing club");
  }

  return rows.map((row) => {
    const isSubject = scope === "team" && row.comparison_id === viewerComparisonId;
    if (!isSubject && !/^(Team [A-Z]|Club \d{2})$/.test(row.team_alias)) {
      throw new Error("Report comparison requires an approved dashboard alias");
    }
    return {
      label: isSubject ? subjectName : row.team_alias,
      isSubject,
      exposureHours: row.exposure_hours,
      distanceKm: row.distance_km,
      allIncidencePer1000h: row.all?.incidence_per_1000h ?? null,
      allBurdenPer1000h: row.all?.burden_per_1000h ?? null,
      matchIncidencePer1000h: row.match?.incidence_per_1000h ?? null,
      matchBurdenPer1000h: row.match?.burden_per_1000h ?? null,
      trainingIncidencePer1000h: row.training?.incidence_per_1000h ?? null,
      trainingBurdenPer1000h: row.training?.burden_per_1000h ?? null,
    };
  }).sort((left, right) => Number(right.isSubject) - Number(left.isSubject));
}

export function buildReportComparisonBenchmarks(metrics: readonly SettingMetricRow[]): ReportComparisonBenchmarks {
  const all = metrics.find((metric) => metric.setting === "all");
  const match = metrics.find((metric) => metric.setting === "match");
  const training = metrics.find((metric) => metric.setting === "training");
  return {
    allIncidencePer1000h: all?.incidence_per_1000h ?? null,
    allBurdenPer1000h: all?.burden_per_1000h ?? null,
    matchIncidencePer1000h: match?.incidence_per_1000h ?? null,
    matchBurdenPer1000h: match?.burden_per_1000h ?? null,
    trainingIncidencePer1000h: training?.incidence_per_1000h ?? null,
    trainingBurdenPer1000h: training?.burden_per_1000h ?? null,
  };
}
