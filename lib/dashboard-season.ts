export const SUPPORTED_DASHBOARD_SEASONS = ['2024-25', '2025-26'] as const;

export type DashboardSeason = (typeof SUPPORTED_DASHBOARD_SEASONS)[number];

export const DEFAULT_DASHBOARD_SEASON: DashboardSeason = '2024-25';

export function previousDashboardSeason(season: DashboardSeason): DashboardSeason | null {
  const index = SUPPORTED_DASHBOARD_SEASONS.indexOf(season);
  return index > 0 ? SUPPORTED_DASHBOARD_SEASONS[index - 1] : null;
}

/** Returns the other released season while the dashboard supports exactly two. */
export function comparisonDashboardSeason(season: DashboardSeason): DashboardSeason {
  const comparison = SUPPORTED_DASHBOARD_SEASONS.find((candidate) => candidate !== season);
  if (!comparison) throw new Error('A comparison season is not available');
  return comparison;
}

/** Returns a supported season before a route loads any reporting data. */
export function resolveDashboardSeason(value: string | string[] | undefined): DashboardSeason {
  return typeof value === 'string' && SUPPORTED_DASHBOARD_SEASONS.includes(value as DashboardSeason)
    ? value as DashboardSeason
    : DEFAULT_DASHBOARD_SEASON;
}
