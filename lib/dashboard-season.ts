export const SUPPORTED_DASHBOARD_SEASONS = ['2024-25', '2025-26'] as const;

export type DashboardSeason = (typeof SUPPORTED_DASHBOARD_SEASONS)[number];

export const DEFAULT_DASHBOARD_SEASON: DashboardSeason = '2024-25';

/** Returns a supported season before a route loads any reporting data. */
export function resolveDashboardSeason(value: string | string[] | undefined): DashboardSeason {
  return typeof value === 'string' && SUPPORTED_DASHBOARD_SEASONS.includes(value as DashboardSeason)
    ? value as DashboardSeason
    : DEFAULT_DASHBOARD_SEASON;
}
