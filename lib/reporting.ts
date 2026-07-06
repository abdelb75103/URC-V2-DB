import "server-only";
import dashboard from "../data/reporting/munster_dashboard_2024-25.json";

export type HeadlineMetric = {
  key: string;
  label: string;
  value: number | null;
  unit: string;
  numerator?: number;
  denominator?: number;
  formula: string;
};

export type Coverage = {
  exposure_rows: number;
  exposed_players: number;
  weeks: number;
  hours: number;
  distance_km: number;
  included_exposure_status: string;
  scope_status: string;
};

export type AnalyticsRow = {
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

export type MunsterDashboard = {
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
  monthly: AnalyticsRow[];
  body_locations: AnalyticsRow[];
  injury_types: AnalyticsRow[];
  severity_distribution: SeverityRow[];
  prior_season: {
    season: string;
    status: string;
    note: string;
  };
  limitations: string[];
};

export function getMunsterDashboard(): MunsterDashboard {
  return dashboard as MunsterDashboard;
}
