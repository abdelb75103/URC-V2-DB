export type HeadlineMetric = {
  key: string;
  label: string;
  value: number | null;
  unit: string;
  numerator?: number;
  denominator?: number;
  formula: string;
};

export type CoverageWindow = {
  start: string;
  end: string;
  teams?: number;
};

export type Coverage = {
  exposure_rows: number;
  exposed_players: number;
  weeks: number;
  exposure_periods?: number;
  exposure_grain?: string;
  hours: number | null;
  match_hours?: number;
  training_hours?: number;
  distance_km: number | null;
  teams_included?: number;
  coverage_windows?: CoverageWindow[];
  included_exposure_status: string;
  scope_status?: string;
  scope_status_counts?: Record<string, number>;
  injury_cohort_filters?: Record<string, boolean | Record<string, number>>;
};

export type AnalyticsRow = {
  key?: string;
  label?: string;
  month?: string;
  exposure_hours?: number | null;
  distance_km?: number | null;
  time_loss_injuries: number;
  recorded_injuries?: number;
  days_lost: number;
  /** Released rate for all recorded injuries, when the season payload provides it. */
  overall_incidence_per_1000h?: number | null;
  incidence_per_1000h?: number | null;
  burden_per_1000h?: number | null;
  mean_severity_days?: number | null;
};

export type SeverityRow = {
  key: string;
  label: string;
  setting?: 'all' | 'match' | 'training';
  recorded_injuries: number;
  time_loss_injuries: number;
  days_lost: number;
};

export type SeveritySettingRow = SeverityRow & {
  setting: 'all' | 'match' | 'training';
};

export type SettingMetricRow = {
  setting: 'all' | 'match' | 'training' | 'unknown';
  label: string;
  /** Released total-recorded count for this setting, when the payload provides it. */
  recorded_injuries?: number | null;
  time_loss_injuries: number;
  days_lost: number;
  exposure_hours: number | null;
  /** Released rate for all recorded injuries in this setting, when the payload provides it. */
  overall_incidence_per_1000h?: number | null;
  incidence_per_1000h: number | null;
  burden_per_1000h: number | null;
  mean_severity_days: number | null;
};

export type InjuryProfileRow = {
  dimension: 'body_location' | 'injury_type' | 'injury_profile' | 'diagnosis';
  code: string;
  label: string;
  setting: 'all' | 'match' | 'training' | 'unknown';
  recorded_injuries?: number;
  time_loss_injuries: number;
  days_lost: number;
  exposure_hours: number | null;
  incidence_per_1000h: number | null;
  burden_per_1000h: number | null;
  mean_severity_days: number | null;
};

export type InjuryTypeFamilyRow = Omit<InjuryProfileRow, 'dimension'> & {
  dimension: 'injury_type_family';
  mapping_version: 'injury_type_family_2026-07-21_v1';
  subtypes: InjuryProfileRow[];
};

export type MonthlySettingRow = {
  month: string;
  setting: 'all' | 'match' | 'training' | 'unknown';
  recorded_injuries?: number;
  time_loss_injuries: number;
  rate_time_loss_injuries: number;
  exposure_hours: number | null;
  /** Released rate for all recorded injuries, when the season payload provides it. */
  overall_incidence_per_1000h?: number | null;
  incidence_per_1000h: number | null;
};

export type DescriptiveConsequenceSummary = {
  recorded_injuries: number;
  time_loss_injuries: number;
  medical_attention_only: number;
  consequence_unknown: number;
  undated_injuries: number;
  outside_season_date_injuries: number;
  rate_ineligible_time_loss_injuries: number;
};

export type DistributionRow = {
  key: string;
  label: string;
  setting: 'all' | 'match' | 'training' | 'unknown';
  recorded_injuries: number;
  time_loss_injuries: number;
};

export type ConsequenceSummary = {
  recorded_injuries: number;
  positive_day_cases: number;
  zero_day_cases: number;
  duration_unknown_or_censored: number;
  source_reported_time_loss: number;
  source_reported_time_loss_without_positive_days: number;
  source_reported_medical_attention: number;
  source_class_unknown: number;
};

export type InferenceCoverageCounts = {
  source_reported: number;
  mapped: number;
  inferred: number;
  adjudicated: number;
  remaining_unknown: number;
  unknown_before_v3: number;
  classified: number;
  total: number;
};

export type InferenceCoverage = {
  cohort: 'attributed_descriptive_cases';
  body_location: InferenceCoverageCounts;
  tissue_pathology: InferenceCoverageCounts;
  diagnosis: InferenceCoverageCounts;
  contact_context: InferenceCoverageCounts;
};

export type DashboardSupplement = {
  status: 'draft_not_for_release';
  season: string;
  team_key: string;
  rule_version: 'urc-diagnosis-inference-v3-draft.9';
  cohort_rule: 'season_bound_2024-07-01_2025-06-30_no_exposure_window';
  generated_at: string;
  consequence_summary: ConsequenceSummary;
  descriptive_consequence_summary: DescriptiveConsequenceSummary;
  rate_setting_metrics: SettingMetricRow[];
  severity_distribution: SeveritySettingRow[];
  match_scope_summary: {
    positive_day_match_cases: number;
    confirmed_urc_match_cases: number;
    retained_generic_match_cases: number;
  };
  monthly_by_setting: MonthlySettingRow[];
  contact_distribution: DistributionRow[];
  body_locations: InjuryProfileRow[];
  injury_types: InjuryProfileRow[];
  common_injuries: InjuryProfileRow[];
  diagnosis_coverage: {
    classified_time_loss_injuries: number;
    eligible_time_loss_injuries: number;
  };
  inference_coverage: InferenceCoverage;
};

export type ExposureReviewPreview = {
  status: 'private_review_override';
  season: string;
  generated_at: string;
  source: string;
  hsr_field: string;
  source_file_count: number;
  monthly: Array<{
    month: string;
    additional_hours: number;
    additional_distance_km: number;
    hsr_distance_km: number;
    hsr_distance_denominator_km: number;
    hsr_reporting_teams: number;
    match_hours: number;
  }>;
  teams: Array<{
    team_alias: string;
    additional_hours: number;
    additional_distance_km: number;
    hsr_distance_km: number | null;
    hsr_distance_denominator_km: number;
  }>;
};

export type TeamComparisonRow = {
  comparison_id: string;
  team_alias: string;
  included_exposure_status: string;
  exposure_hours: number | null;
  distance_km: number | null;
  match_hours: number | null;
  training_hours: number | null;
  all: SettingMetricRow | null;
  match: SettingMetricRow | null;
  training: SettingMetricRow | null;
};

export type DashboardData = {
  scope: 'team' | 'league';
  generated_at: string;
  team: string;
  season: string;
  analysis_window: {
    start: string;
    end: string;
    basis: string;
  };
  method: string[];
  coverage: Coverage;
  headline: HeadlineMetric[];
  setting_split: AnalyticsRow[];
  setting_metrics: SettingMetricRow[];
  monthly: AnalyticsRow[];
  body_locations: AnalyticsRow[];
  injury_types: AnalyticsRow[];
  injury_profiles: InjuryProfileRow[];
  injury_type_families: InjuryTypeFamilyRow[];
  severity_distribution: SeverityRow[];
  // Optional: releases published before the 2026-07-26 contact-ring change do
  // not carry this key.
  contact_distribution?: DistributionRow[];
  prior_season: {
    season: string;
    status: string;
    note: string;
  };
  limitations: string[];
};

export type TeamDashboardData = DashboardData;
