import "server-only";
import connachtDashboard from "../content/reporting/connacht_dashboard_2024-25.json";
import leinsterDashboard from "../content/reporting/leinster_dashboard_2024-25.json";
import dashboard from "../content/reporting/munster_dashboard_2024-25.json";
import ulsterDashboard from "../content/reporting/ulster_dashboard_2024-25.json";

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
  exposure_periods?: number;
  exposure_grain?: string;
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

export type TeamDashboardData = {
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

export type MunsterDashboard = TeamDashboardData;

const dashboards: Record<string, TeamDashboardData> = {
  connacht: connachtDashboard as TeamDashboardData,
  leinster: leinsterDashboard as TeamDashboardData,
  munster: dashboard as TeamDashboardData,
  ulster: ulsterDashboard as TeamDashboardData,
};

export function getTeamDashboard(teamId: string): TeamDashboardData | undefined {
  return dashboards[teamId];
}

export function getMunsterDashboard(): TeamDashboardData {
  return dashboards.munster;
}
