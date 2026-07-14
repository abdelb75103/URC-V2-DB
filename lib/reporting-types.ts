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
  hours: number;
  match_hours?: number;
  training_hours?: number;
  distance_km: number;
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
  exposure_hours?: number;
  distance_km?: number;
  time_loss_injuries: number;
  recorded_injuries?: number;
  days_lost: number;
  incidence_per_1000h?: number | null;
  burden_per_1000h?: number | null;
  mean_severity_days?: number | null;
};

export type SeverityRow = {
  key: string;
  label: string;
  recorded_injuries: number;
  time_loss_injuries: number;
  days_lost: number;
};

export type SettingMetricRow = {
  setting: 'all' | 'match' | 'training' | 'unknown';
  label: string;
  time_loss_injuries: number;
  days_lost: number;
  exposure_hours: number | null;
  incidence_per_1000h: number | null;
  burden_per_1000h: number | null;
  mean_severity_days: number | null;
};

export type InjuryProfileRow = {
  dimension: 'body_location' | 'injury_type' | 'injury_profile';
  code: string;
  label: string;
  setting: 'all' | 'match' | 'training' | 'unknown';
  time_loss_injuries: number;
  days_lost: number;
  exposure_hours: number | null;
  incidence_per_1000h: number | null;
  burden_per_1000h: number | null;
  mean_severity_days: number | null;
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
  severity_distribution: SeverityRow[];
  prior_season: {
    season: string;
    status: string;
    note: string;
  };
  limitations: string[];
};

export type TeamDashboardData = DashboardData;
