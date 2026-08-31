import "server-only";
import type {
  AnalyticsRow,
  DashboardData,
  DistributionRow,
  HeadlineMetric,
  InjuryProfileRow,
  InjuryTypeFamilyRow,
  SeverityRow,
  SettingMetricRow,
  SeasonComparisonData,
} from "@/lib/reporting-types";
import {
  DEFAULT_REPORT_SECTION_IDS,
  type ReportMetric,
  type ReportModel,
  type ReportComparisonRow,
  type ReportComparisonBenchmarks,
  type ReportDistributionRow,
  type ReportInjuryTypeFamily,
  type ReportProfileRow,
  type ReportSectionId,
  type ReportSettingMetric,
  type SeasonComparisonMetric,
} from "@/lib/report-model-types";

export { DEFAULT_REPORT_SECTION_IDS } from "@/lib/report-model-types";
export type { ReportModel, ReportSectionId, SeasonComparisonModel } from "@/lib/report-model-types";

export type ReportModelRequest = {
  current: DashboardData;
  prior: DashboardData | null;
  expectedScope: DashboardData["scope"];
  expectedSeason: string;
  subjectName: string;
  protectedTerms: readonly string[];
  exportedAt?: string;
  comparisonRows?: readonly ReportComparisonRow[];
  comparisonBenchmarks?: ReportComparisonBenchmarks;
  seasonComparisonVisuals?: SeasonComparisonData;
  brand?: ReportModel["brand"];
};

const ALIAS_PATTERN = /\bTeam [A-Z]\b/;
const INTERNAL_KEY_PATTERN = /\b(?:team|comparison)[_-][a-z0-9_-]+\b/i;
const FORBIDDEN_KEYS = new Set([
  "player_id",
  "playerid",
  "player_identifier",
  "team_key",
  "teamid",
  "team_alias",
  "comparison_id",
  "viewer_comparison_id",
]);

export function filterReportSectionIds(sectionIds: readonly ReportSectionId[] | undefined): ReportSectionId[] {
  const enabled = new Set(sectionIds ?? DEFAULT_REPORT_SECTION_IDS);
  return DEFAULT_REPORT_SECTION_IDS.filter((sectionId) => enabled.has(sectionId));
}

function assertDashboardIdentity(
  dashboard: DashboardData,
  expectedScope: DashboardData["scope"],
  expectedSeason: string,
  subjectName: string,
): void {
  if (dashboard.scope !== expectedScope) throw new Error("Report scope does not match the approved dashboard");
  if (dashboard.season !== expectedSeason) throw new Error("Report season does not match the approved dashboard");
  if (dashboard.team !== subjectName) throw new Error("Report subject does not match the approved dashboard");
}

function sortByPresentation<T extends { label?: string; month?: string }>(rows: readonly T[]): T[] {
  return [...rows].sort((left, right) => (left.month ?? left.label ?? "").localeCompare(right.month ?? right.label ?? ""));
}

function monthTimestamp(value: string | undefined): number {
  if (!value) return Number.POSITIVE_INFINITY;
  const timestamp = /^\d{4}-\d{2}$/.test(value)
    ? Date.parse(`${value}-01T00:00:00Z`)
    : Date.parse(`1 ${value} UTC`);
  return Number.isNaN(timestamp) ? Number.POSITIVE_INFINITY : timestamp;
}

function sortByMonth<T extends { month?: string }>(rows: readonly T[]): T[] {
  return [...rows].sort((left, right) => monthTimestamp(left.month) - monthTimestamp(right.month));
}

function coverageStatusLabel(status: string): string {
  if (/temporary.*estimate/i.test(status)) {
    return "Temporary league-mean exposure estimate; source-backed exposure is not yet available";
  }
  if (/source.backed.*incomplete/i.test(status)) {
    return "Source-backed exposure has been submitted but may be incomplete";
  }
  const words = status.replace(/[_-]+/g, " ").trim();
  return words ? `${words[0].toUpperCase()}${words.slice(1)}` : "Temporary estimate or incomplete coverage";
}

function profileRows(rows: readonly InjuryProfileRow[], dimension: InjuryProfileRow["dimension"]): ReportProfileRow[] {
  return sortByPresentation(rows.filter((row) => row.dimension === dimension))
    .sort((left, right) => left.setting.localeCompare(right.setting) || right.time_loss_injuries - left.time_loss_injuries || left.label.localeCompare(right.label))
    .map((row) => ({
      code: row.code,
      label: row.label,
      setting: row.setting,
      recordedInjuries: row.recorded_injuries ?? null,
      timeLossInjuries: row.time_loss_injuries,
      daysLost: row.days_lost,
      incidencePer1000h: row.incidence_per_1000h,
      burdenPer1000h: row.burden_per_1000h,
      meanSeverityDays: row.mean_severity_days,
    }));
}

function distributionRows(rows: readonly (DistributionRow | SeverityRow)[]): ReportDistributionRow[] {
  return rows.map((row) => ({
    key: row.key,
    label: row.label,
    setting: row.setting ?? "all",
    recordedInjuries: row.recorded_injuries,
    timeLossInjuries: row.time_loss_injuries,
    daysLost: "days_lost" in row ? row.days_lost : null,
  }));
}

function injuryTypeFamilies(rows: readonly InjuryTypeFamilyRow[]): ReportInjuryTypeFamily[] {
  return rows.map((row) => ({
    code: row.code,
    label: row.label,
    setting: row.setting,
    recordedInjuries: row.recorded_injuries ?? null,
    timeLossInjuries: row.time_loss_injuries,
    daysLost: row.days_lost,
    incidencePer1000h: row.incidence_per_1000h,
    burdenPer1000h: row.burden_per_1000h,
    meanSeverityDays: row.mean_severity_days,
    subtypes: profileRows(row.subtypes, "injury_type"),
  }));
}

function asReportMetric(metric: HeadlineMetric): ReportMetric {
  return { key: metric.key, label: metric.label, value: metric.value, unit: metric.unit, formula: metric.formula };
}

function asSettingMetric(metric: SettingMetricRow): ReportSettingMetric {
  return {
    setting: metric.setting,
    label: metric.label,
    recordedInjuries: metric.recorded_injuries ?? null,
    timeLossInjuries: metric.time_loss_injuries,
    daysLost: metric.days_lost,
    exposureHours: metric.exposure_hours,
    overallIncidencePer1000h: metric.overall_incidence_per_1000h ?? null,
    incidencePer1000h: metric.incidence_per_1000h,
    burdenPer1000h: metric.burden_per_1000h,
    meanSeverityDays: metric.mean_severity_days,
  };
}

function isRate(metric: Pick<HeadlineMetric, "key" | "unit" | "formula">): boolean {
  return /incidence|burden/i.test(metric.key)
    || metric.unit.includes("/1000")
    || /incidence|burden|per 1?,?000/i.test(metric.formula);
}

function comparisonMetric(current: HeadlineMetric, prior: HeadlineMetric | undefined, comparableWindow: boolean, comparableCoverage: boolean): SeasonComparisonMetric {
  const base = { key: current.key, label: current.label, unit: current.unit, currentValue: current.value, priorValue: prior?.value ?? null };
  if (!prior) return { ...base, delta: null, deltaReason: "Not available in the comparison release" };
  if (current.unit !== prior.unit || current.formula !== prior.formula) return { ...base, delta: null, deltaReason: "Metric definition changed" };
  if (!comparableWindow) return { ...base, delta: null, deltaReason: "Analysis windows are not comparable" };
  if (isRate(current) && (!comparableCoverage || !current.denominator || !prior.denominator)) {
    return { ...base, delta: null, deltaReason: "Exposure denominator is not comparable" };
  }
  if (/severity|mean|median/i.test(current.key) && (!current.denominator || !prior.denominator)) {
    return { ...base, delta: null, deltaReason: "Case denominator is not comparable" };
  }
  if (current.value === null || prior.value === null) return { ...base, delta: null, deltaReason: "A released value is not available" };
  return { ...base, delta: current.value - prior.value, deltaReason: null };
}

function settingComparisonMetric(current: HeadlineMetric, prior: HeadlineMetric | undefined): SeasonComparisonMetric {
  return {
    key: current.key,
    label: current.label,
    unit: current.unit,
    currentValue: current.value,
    priorValue: prior?.value ?? null,
    delta: null,
    deltaReason: "Released setting definitions do not include comparable formula metadata",
  };
}

function settingHeadline(setting: SettingMetricRow): HeadlineMetric[] {
  return [
    { key: `${setting.setting}-recorded`, label: `${setting.label} recorded injuries`, value: setting.recorded_injuries ?? null, unit: "injuries", formula: "released recorded injury count" },
    { key: `${setting.setting}-time-loss`, label: `${setting.label} time-loss injuries`, value: setting.time_loss_injuries, unit: "injuries", formula: "released time-loss injury count" },
    { key: `${setting.setting}-incidence`, label: `${setting.label} incidence`, value: setting.incidence_per_1000h, unit: "per 1000 hours", denominator: setting.exposure_hours ?? undefined, formula: "released incidence per 1000 exposure hours" },
  ];
}

function denominatorClass(dashboard: DashboardData): "source-backed" | "temporary" | "incomplete" | "unavailable" {
  if (dashboard.coverage.hours === null || dashboard.coverage.hours <= 0) return "unavailable";
  const status = dashboard.coverage.included_exposure_status;
  if (/temporary|estimate/i.test(status)) return "temporary";
  if (/incomplete|partial|pending/i.test(status)) return "incomplete";
  return "source-backed";
}

function coverageComparable(current: DashboardData, prior: DashboardData): boolean {
  return denominatorClass(current) === denominatorClass(prior)
    && denominatorClass(current) === "source-backed";
}

function analysisWindowComparable(current: DashboardData, prior: DashboardData): boolean {
  return current.analysis_window.start.slice(5) === prior.analysis_window.start.slice(5)
    && current.analysis_window.end.slice(5) === prior.analysis_window.end.slice(5);
}

function assertNoForbiddenKeys(value: unknown, path = "report"): void {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoForbiddenKeys(item, `${path}[${index}]`));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, item] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.has(key.toLowerCase())) throw new Error(`Report model contains a protected field at ${path}`);
    assertNoForbiddenKeys(item, `${path}.${key}`);
  }
}

export function assertReportModelPrivacy(model: ReportModel, subjectName: string, protectedTerms: readonly string[]): void {
  if (protectedTerms.length === 0) throw new Error("Report model requires protected terms");
  assertNoForbiddenKeys(model);
  const serialized = JSON.stringify(model);
  if (ALIAS_PATTERN.test(serialized) || INTERNAL_KEY_PATTERN.test(serialized)) throw new Error("Report model contains protected team text");
  for (const term of protectedTerms) {
    if (!term || term.toLocaleLowerCase("en-IE") === subjectName.toLocaleLowerCase("en-IE")) continue;
    if (containsProtectedTerm(serialized, term)) throw new Error("Report model contains another club name");
  }
}

function containsProtectedTerm(value: string, term: string): boolean {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^a-z0-9])${escaped}([^a-z0-9]|$)`, "i").test(value);
}

function disclosureSafeLeagueText(items: readonly string[], protectedTerms: readonly string[]): string[] {
  return items.filter((item) => !protectedTerms.some((term) => term && containsProtectedTerm(item, term)));
}

function hasTemporaryOrIncompleteCoverage(status: string): boolean {
  return /temporary|estimate|incomplete|partial|pending/i.test(status);
}

export function buildReportModel(request: ReportModelRequest): ReportModel {
  const { current, prior, expectedScope, expectedSeason, subjectName, protectedTerms } = request;
  const exportedAt = request.exportedAt ?? current.generated_at;
  if (Number.isNaN(Date.parse(exportedAt))) throw new Error("Report export timestamp is invalid");
  assertDashboardIdentity(current, expectedScope, expectedSeason, subjectName);
  let comparisonRelease = current.prior_season;
  if (prior) {
    const directComparison = current.prior_season.season === prior.season;
    const reverseComparison = prior.prior_season.season === current.season;
    const approvalStatus = directComparison ? current.prior_season.status : prior.prior_season.status;
    if ((!directComparison && !reverseComparison) || !/^(approved|frozen)$/i.test(approvalStatus)) {
      throw new Error("Comparison release is not approved for comparison");
    }
    assertDashboardIdentity(prior, expectedScope, prior.season, subjectName);
    comparisonRelease = directComparison
      ? current.prior_season
      : { season: prior.season, status: "approved", note: `Compared with the approved ${prior.season} release.` };
  }

  const comparableWindow = prior ? analysisWindowComparable(current, prior) : false;
  const comparableCoverage = prior ? coverageComparable(current, prior) : false;
  const priorHeadline = new Map(prior?.headline.map((metric) => [metric.key, metric]));
  const priorSettings = new Map(prior?.setting_metrics.map((metric) => [metric.setting, metric]));
  const estimateOrIncompleteCoverage = hasTemporaryOrIncompleteCoverage(current.coverage.included_exposure_status);
  const comparisonSettings = current.setting_metrics.flatMap((setting) => {
    const oldSetting = priorSettings.get(setting.setting);
    const oldHeadline = oldSetting ? new Map(settingHeadline(oldSetting).map((metric) => [metric.key, metric])) : new Map<string, HeadlineMetric>();
    return settingHeadline(setting).map((metric) => settingComparisonMetric(metric, oldHeadline.get(metric.key)));
  });
  const method = expectedScope === "league"
    ? disclosureSafeLeagueText(current.method, protectedTerms)
    : current.method;
  const limitations = expectedScope === "league"
    ? disclosureSafeLeagueText(current.limitations, protectedTerms)
    : current.limitations;
  const temporaryEstimateCount = current.coverage.temporary_estimate_team_count ?? 0;
  const safeLimitations = expectedScope === "league" && temporaryEstimateCount > 0
    ? [`${temporaryEstimateCount} clubs use temporary league-mean exposure estimates while source-backed exposure is awaited.`, ...limitations]
    : limitations;

  const model: ReportModel = {
    schemaVersion: "urc-report-v1",
    reportVersion: "1.0",
    exportedAt,
    dataGeneratedAt: current.generated_at,
    brand: request.brand ?? { crestDataUri: null, accentColour: "#00B9D8" },
    scope: current.scope,
    subjectName,
    season: current.season,
    analysisWindow: { ...current.analysis_window },
    estimateOrIncompleteCoverage,
    coverageNote: estimateOrIncompleteCoverage ? coverageStatusLabel(current.coverage.included_exposure_status) : null,
    snapshotMetrics: current.headline.map(asReportMetric),
    monthlyInjuryPattern: sortByMonth(current.monthly).map((row: AnalyticsRow) => ({
      month: row.month ?? "",
      recordedInjuries: row.recorded_injuries ?? null,
      timeLossInjuries: row.time_loss_injuries,
      daysLost: row.days_lost,
      overallIncidencePer1000h: row.overall_incidence_per_1000h ?? null,
      incidencePer1000h: row.incidence_per_1000h ?? null,
      burdenPer1000h: row.burden_per_1000h ?? null,
    })),
    matchTraining: sortByPresentation(current.setting_metrics.filter((metric) => metric.setting === "match" || metric.setting === "training")).map(asSettingMetric),
    severityDistribution: distributionRows(current.severity_distribution),
    contactDistribution: distributionRows(current.contact_distribution ?? []),
    injuryProfile: {
      diagnoses: profileRows(current.injury_profiles, "diagnosis"),
      bodyLocations: profileRows(current.injury_profiles, "body_location"),
      injuryTypes: profileRows(current.injury_profiles, "injury_type"),
      injuryTypeFamilies: injuryTypeFamilies(current.injury_type_families),
    },
    exposure: {
      totalHours: current.coverage.hours,
      matchHours: current.coverage.match_hours ?? null,
      trainingHours: current.coverage.training_hours ?? null,
      totalDistanceKm: current.coverage.distance_km,
      monthly: sortByMonth(current.monthly).map((row) => ({ month: row.month ?? "", exposureHours: row.exposure_hours ?? null, distanceKm: row.distance_km ?? null })),
    },
    comparisonHeatmap: (request.comparisonRows ?? []).map((row) => ({ ...row })),
    comparisonBenchmarks: request.comparisonBenchmarks ?? {
      allIncidencePer1000h: null,
      allBurdenPer1000h: null,
      matchIncidencePer1000h: null,
      matchBurdenPer1000h: null,
      trainingIncidencePer1000h: null,
      trainingBurdenPer1000h: null,
    },
    seasonComparison: {
      comparisonSeason: prior?.season ?? comparisonRelease.season,
      status: comparisonRelease.status,
      note: comparisonRelease.note,
      headline: current.headline.map((metric) => comparisonMetric(metric, priorHeadline.get(metric.key), comparableWindow, comparableCoverage)),
      settings: comparisonSettings,
    },
    seasonComparisonVisuals: request.seasonComparisonVisuals ?? null,
    method: [...method],
    limitations: [...safeLimitations],
  };
  assertReportModelPrivacy(model, subjectName, protectedTerms);
  return model;
}
