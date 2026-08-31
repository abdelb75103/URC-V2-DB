import type { DashboardData } from "../lib/reporting-types";

export function dashboardFixture(overrides: Partial<DashboardData> = {}): DashboardData {
  return {
    scope: "team",
    generated_at: "2026-08-31T00:00:00Z",
    team: "Harbour RFC",
    season: "2025-26",
    analysis_window: { start: "2025-07-01", end: "2026-06-30", basis: "season" },
    method: ["Released injury and exposure metrics only."],
    coverage: {
      exposure_rows: 12,
      exposed_players: 36,
      weeks: 52,
      hours: 8400,
      match_hours: 2100,
      training_hours: 6300,
      distance_km: 120000,
      included_exposure_status: "complete",
    },
    headline: [
      { key: "recorded", label: "Recorded injuries", value: 74, unit: "injuries", numerator: 74, formula: "released recorded injury count" },
      { key: "incidence", label: "Time-loss incidence", value: 8.2, unit: "per 1000 hours", numerator: 69, denominator: 8400, formula: "released incidence per 1000 exposure hours" },
    ],
    setting_split: [],
    setting_metrics: [
      { setting: "match", label: "Match", recorded_injuries: 28, time_loss_injuries: 26, days_lost: 518, exposure_hours: 2100, overall_incidence_per_1000h: 13.3, incidence_per_1000h: 12.4, burden_per_1000h: 246.7, mean_severity_days: 19.9 },
      { setting: "training", label: "Training", recorded_injuries: 39, time_loss_injuries: 36, days_lost: 640, exposure_hours: 6300, overall_incidence_per_1000h: 6.2, incidence_per_1000h: 5.7, burden_per_1000h: 101.6, mean_severity_days: 17.8 },
    ],
    monthly: [
      { month: "2025-08", exposure_hours: 700, distance_km: 10000, time_loss_injuries: 4, recorded_injuries: 5, days_lost: 82 },
      { month: "2025-07", exposure_hours: 600, distance_km: 9000, time_loss_injuries: 3, recorded_injuries: 4, days_lost: 61 },
    ],
    body_locations: [],
    injury_types: [],
    injury_profiles: [
      { dimension: "diagnosis", code: "d1", label: "Hamstring strain", setting: "all", recorded_injuries: 12, time_loss_injuries: 11, days_lost: 180, exposure_hours: 8400, incidence_per_1000h: 1.3, burden_per_1000h: 21.4, mean_severity_days: 16.4 },
      { dimension: "body_location", code: "b1", label: "Thigh", setting: "all", recorded_injuries: 14, time_loss_injuries: 12, days_lost: 192, exposure_hours: 8400, incidence_per_1000h: 1.4, burden_per_1000h: 22.9, mean_severity_days: 16 },
      { dimension: "injury_type", code: "i1", label: "Muscle injury", setting: "all", recorded_injuries: 23, time_loss_injuries: 21, days_lost: 330, exposure_hours: 8400, incidence_per_1000h: 2.5, burden_per_1000h: 39.3, mean_severity_days: 15.7 },
    ],
    injury_type_families: [],
    severity_distribution: [],
    prior_season: { season: "2024-25", status: "frozen", note: "Frozen approved release." },
    limitations: ["Unknown-setting injuries are retained in season totals."],
    ...overrides,
  };
}

export function priorDashboardFixture(overrides: Partial<DashboardData> = {}): DashboardData {
  const current = dashboardFixture();
  return {
    ...current,
    season: "2024-25",
    headline: [
      { ...current.headline[0], value: 68, numerator: 68 },
      { ...current.headline[1], value: 7.9, numerator: 61, denominator: 7700 },
    ],
    coverage: { ...current.coverage, hours: 7700 },
    setting_metrics: current.setting_metrics.map((row) => ({ ...row, exposure_hours: row.setting === "match" ? 1900 : 5800 })),
    ...overrides,
  };
}
