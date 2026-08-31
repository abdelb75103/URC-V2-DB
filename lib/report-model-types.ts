import type { SeasonComparisonData } from "@/lib/reporting-types";

export const DEFAULT_REPORT_SECTION_IDS = [
  "cover",
  "season-pattern",
  "severity-contact",
  "injury-location",
  "common-injuries",
  "impact-matrices",
  "injury-types",
  "exposure",
  "team-comparison",
  "season-methodology",
] as const;

export type ReportSectionId = (typeof DEFAULT_REPORT_SECTION_IDS)[number];
export type ReportScope = "team" | "league";

export type ReportMetric = {
  key: string;
  label: string;
  value: number | null;
  unit: string;
  formula: string;
};

export type ReportPatternRow = {
  month: string;
  recordedInjuries: number | null;
  timeLossInjuries: number;
  daysLost: number;
  overallIncidencePer1000h: number | null;
  incidencePer1000h: number | null;
  burdenPer1000h: number | null;
};

export type ReportProfileRow = {
  code: string;
  label: string;
  setting: "all" | "match" | "training" | "unknown";
  recordedInjuries: number | null;
  timeLossInjuries: number;
  daysLost: number;
  incidencePer1000h: number | null;
  burdenPer1000h: number | null;
  meanSeverityDays: number | null;
};

export type ReportDistributionRow = {
  key: string;
  label: string;
  setting: "all" | "match" | "training" | "unknown";
  recordedInjuries: number;
  timeLossInjuries: number;
  daysLost: number | null;
};

export type ReportInjuryTypeFamily = ReportProfileRow & {
  subtypes: ReportProfileRow[];
};

export type ReportExposureRow = {
  month: string;
  exposureHours: number | null;
  distanceKm: number | null;
};

export type ReportComparisonRow = {
  label: string;
  isSubject: boolean;
  exposureHours: number | null;
  distanceKm: number | null;
  allIncidencePer1000h: number | null;
  allBurdenPer1000h: number | null;
  matchIncidencePer1000h: number | null;
  matchBurdenPer1000h: number | null;
  trainingIncidencePer1000h: number | null;
  trainingBurdenPer1000h: number | null;
};

export type ReportComparisonBenchmarks = {
  allIncidencePer1000h: number | null;
  allBurdenPer1000h: number | null;
  matchIncidencePer1000h: number | null;
  matchBurdenPer1000h: number | null;
  trainingIncidencePer1000h: number | null;
  trainingBurdenPer1000h: number | null;
};

export type ReportSettingMetric = {
  setting: "all" | "match" | "training" | "unknown";
  label: string;
  recordedInjuries: number | null;
  timeLossInjuries: number;
  daysLost: number;
  exposureHours: number | null;
  overallIncidencePer1000h: number | null;
  incidencePer1000h: number | null;
  burdenPer1000h: number | null;
  meanSeverityDays: number | null;
};

export type SeasonComparisonMetric = {
  key: string;
  label: string;
  unit: string;
  currentValue: number | null;
  priorValue: number | null;
  delta: number | null;
  deltaReason: string | null;
};

export type SeasonComparisonModel = {
  comparisonSeason: string;
  status: string;
  note: string;
  headline: SeasonComparisonMetric[];
  settings: SeasonComparisonMetric[];
};

export type ReportModel = {
  schemaVersion: "urc-report-v1";
  reportVersion: "1.0";
  exportedAt: string;
  dataGeneratedAt: string;
  brand: { crestDataUri: string | null; accentColour: string };
  scope: ReportScope;
  subjectName: string;
  season: string;
  analysisWindow: { start: string; end: string; basis: string };
  estimateOrIncompleteCoverage: boolean;
  coverageNote: string | null;
  snapshotMetrics: ReportMetric[];
  monthlyInjuryPattern: ReportPatternRow[];
  matchTraining: ReportSettingMetric[];
  severityDistribution: ReportDistributionRow[];
  contactDistribution: ReportDistributionRow[];
  injuryProfile: {
    diagnoses: ReportProfileRow[];
    bodyLocations: ReportProfileRow[];
    injuryTypes: ReportProfileRow[];
    injuryTypeFamilies: ReportInjuryTypeFamily[];
  };
  exposure: {
    totalHours: number | null;
    matchHours: number | null;
    trainingHours: number | null;
    totalDistanceKm: number | null;
    monthly: ReportExposureRow[];
  };
  comparisonHeatmap: ReportComparisonRow[];
  comparisonBenchmarks: ReportComparisonBenchmarks;
  seasonComparison: SeasonComparisonModel;
  seasonComparisonVisuals: SeasonComparisonData | null;
  method: string[];
  limitations: string[];
};
